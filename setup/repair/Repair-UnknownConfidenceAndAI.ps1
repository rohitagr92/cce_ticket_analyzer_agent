[CmdletBinding()]
param(
    [string]$ResourceGroup = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccount = 'opswprodtoolsblob',
    [string]$TableName = 'IncidentsCategoryStats',
    [string]$PartitionKey = '',
    [switch]$Apply,
    [switch]$RewriteGeneratedAiAnalysis
)

$ErrorActionPreference = 'Stop'

function Get-NormalizedConfidenceValue {
    param([string]$Raw)
    $c = ([string]$Raw).Trim().ToLowerInvariant()
    if ($c -eq 'high') { return 'High' }
    if ($c -in @('medium', 'moderate', 'med')) { return 'Medium' }
    if ($c -eq 'low') { return 'Low' }
    return ''
}

function Get-FallbackAnalysisText {
    param([object]$Row)

    $category = ([string]$Row.Category).Trim()
    if ([string]::IsNullOrWhiteSpace($category)) { $category = 'Other / Miscellaneous' }

    $sub = ([string]$Row.Subcategory).Trim()
    if ([string]::IsNullOrWhiteSpace($sub)) { $sub = 'not explicitly captured in work notes' }

    $prc = ([string]$Row.PossibleRootCause).Trim()
    if ([string]::IsNullOrWhiteSpace($prc) -or $prc.ToLowerInvariant() -eq 'unknown' -or $prc -eq '-') {
        $prc = 'not explicitly captured in the stored record'
    }

    $drc = ([string]$Row.DetailedRootCause).Trim()
    if ([string]::IsNullOrWhiteSpace($drc) -or $drc.ToLowerInvariant() -eq 'unknown' -or $drc -eq '-') {
        $drc = 'no additional detailed root-cause narrative was stored'
    }

    $conf = Get-NormalizedConfidenceValue -Raw ([string]$Row.Confidence)
    if ([string]::IsNullOrWhiteSpace($conf)) { $conf = 'Unknown' }

    if ($category -eq 'Excluded') {
        return "The ticket was excluded from Productivity Tools incident categorization because the request context suggests ownership outside this service boundary. The reported symptom was '$sub', and the stored notes indicate routing or queue-alignment actions rather than an in-scope product defect. Root-cause detail remains limited ($drc), so the next action is to verify assignment and handoff with user-impact context included. User response and closure confirmation are not consistently captured in excluded flows, so confidence should be treated carefully during reporting. Confidence for this reconstructed analysis is $conf."
    }

    return "The ticket is classified under $category based on the symptom '$sub' and the troubleshooting details captured in the incident row. The most likely cause is $prc, and additional root-cause context indicates $drc. Because the original AI narrative was missing or too short, this analysis was rebuilt from structured fields so reviewers still get a readable incident story. Engineer actions should be cross-checked against full work notes, and user recovery confirmation should be validated before final RCA sign-off. Confidence for this reconstructed analysis is $conf."
}

function Get-AllRowsFromTable {
    param(
        [string]$StorageAccountName,
        [string]$Table,
        $StorageContext,
        [string]$Pk
    )

    if (-not [string]::IsNullOrWhiteSpace($Pk)) {
        return @(Get-AzTableRow -Table $cloudTable -PartitionKey $Pk -ErrorAction Stop)
    }

    $sas = New-AzStorageTableSASToken -Name $Table -Permission 'r' -ExpiryTime (Get-Date).AddMinutes(20) -Protocol HttpsOnly -Context $StorageContext
    $base = "https://$StorageAccountName.table.core.windows.net/$Table()?$sas"

    $rows = @()
    $url = $base
    while ($url) {
        $resp = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
        $payload = $resp.Content | ConvertFrom-Json
        $rows += @($payload.value)

        $nextPk = $resp.Headers['x-ms-continuation-NextPartitionKey']
        $nextRk = $resp.Headers['x-ms-continuation-NextRowKey']
        if ($nextPk) {
            $url = $base + '&NextPartitionKey=' + [Uri]::EscapeDataString([string]$nextPk)
            if ($nextRk) { $url += '&NextRowKey=' + [Uri]::EscapeDataString([string]$nextRk) }
        } else {
            $url = $null
        }
    }
    return $rows
}

if (-not (Get-Module -ListAvailable -Name AzTable)) {
    Write-Host 'Installing AzTable module...' -ForegroundColor Yellow
    Install-Module -Name AzTable -Scope CurrentUser -Force -AllowClobber
}
Import-Module AzTable -ErrorAction Stop

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $storageKey
$cloudTable = (Get-AzStorageTable -Name $TableName -Context $ctx -ErrorAction Stop).CloudTable

Write-Host "Scanning table $TableName in $StorageAccount..." -ForegroundColor Cyan
$rows = Get-AllRowsFromTable -StorageAccountName $StorageAccount -Table $TableName -StorageContext $ctx -Pk $PartitionKey
Write-Host "Rows scanned: $($rows.Count)" -ForegroundColor Gray

$checked = 0
$candidates = 0
$updated = 0
$analysisUpdated = 0
$confidenceUpdated = 0
$errors = 0

foreach ($r in $rows) {
    $checked++
    $pk = [string]$r.PartitionKey
    $rk = [string]$r.RowKey

    $currentAi = ([string]$r.AIAnalysis).Trim()
    $currentConfNorm = Get-NormalizedConfidenceValue -Raw ([string]$r.Confidence)

    $aiLooksGenerated = $currentAi -match '(?i)fallback analysis generated during data repair|::\s*symptom:|\*\*category:\*\*|\*\*symptom/subcategory:\*\*|\*\*possible root cause:\*\*|\*\*detailed root cause:\*\*'
    $needsAi = [string]::IsNullOrWhiteSpace($currentAi) -or ($RewriteGeneratedAiAnalysis -and $aiLooksGenerated)
    $needsConf = [string]::IsNullOrWhiteSpace($currentConfNorm)

    if (-not $needsAi -and -not $needsConf) { continue }

    $candidates++

    $newAi = $currentAi
    if ($needsAi) {
        $newAi = Get-FallbackAnalysisText -Row $r
        if ($newAi.Length -gt 4000) { $newAi = $newAi.Substring(0, 4000) + '...' }
    }

    $newConf = $currentConfNorm
    if ($needsConf) {
        $root = ([string]$r.PossibleRootCause).Trim().ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($root) -and $root -ne 'unknown' -and $root -ne '-') {
            $newConf = 'Medium'
        } else {
            $newConf = 'Low'
        }
    }

    if (-not $Apply) {
        $aiFrom = 'ok'
        $aiTo = 'keep'
        if ([string]::IsNullOrWhiteSpace($currentAi)) {
            $aiFrom = 'blank'
            $aiTo = 'set'
        } elseif ($RewriteGeneratedAiAnalysis -and $aiLooksGenerated) {
            $aiFrom = 'generated-short'
            $aiTo = 'rewrite-detailed'
        }
        Write-Host ("[DRY-RUN] {0}/{1} AI:{2}->{3} CONF:{4}->{5}" -f $pk, $rk, $aiFrom, $aiTo, ([string]$r.Confidence), $newConf) -ForegroundColor DarkGray
        continue
    }

    try {
        $row = Get-AzTableRow -Table $cloudTable -PartitionKey $pk -RowKey $rk -ErrorAction Stop
        if ($null -eq ($row.PSObject.Properties['AIAnalysis'])) {
            Add-Member -InputObject $row -MemberType NoteProperty -Name 'AIAnalysis' -Value '' -Force
        }
        if ($null -eq ($row.PSObject.Properties['Confidence'])) {
            Add-Member -InputObject $row -MemberType NoteProperty -Name 'Confidence' -Value '' -Force
        }

        $row.AIAnalysis = $newAi
        $row.Confidence = $newConf
        $null = $row | Update-AzTableRow -Table $cloudTable

        $updated++
        if ($needsAi) { $analysisUpdated++ }
        if ($needsConf) { $confidenceUpdated++ }
    } catch {
        $errors++
        Write-Host ("ERROR {0}/{1}: {2}" -f $pk, $rk, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '=== Repair Summary ===' -ForegroundColor Cyan
Write-Host "Checked rows        : $checked"
Write-Host "Candidate rows      : $candidates"
if ($Apply) {
    Write-Host "Rows updated        : $updated" -ForegroundColor Green
    Write-Host "AIAnalysis patched  : $analysisUpdated" -ForegroundColor Green
    Write-Host "Confidence patched  : $confidenceUpdated" -ForegroundColor Green
    Write-Host "Errors              : $errors" -ForegroundColor Yellow
} else {
    Write-Host 'No updates applied (dry run). Re-run with -Apply to patch rows.' -ForegroundColor Yellow
}
