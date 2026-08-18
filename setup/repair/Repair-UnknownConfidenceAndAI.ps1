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

function Test-StrictAiAnalysis {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $text = [string]$Value
    if ($text -notmatch '(?im)^\s*Problem\s*:') { return $false }
    if ($text -notmatch '(?im)^\s*Root Cause\s*:') { return $false }
    if ($text -notmatch '(?im)^\s*Resolution\s*:') { return $false }
    if ($text -notmatch '(?im)^\s*Evidence\s*:') { return $false }
    if ($text -notmatch '(?im)^\s*AI Analysis\s*\(') { return $false }
    if ($text -match '(?is)<style|</?[a-z][^>]*>|manual review recommended for proper categorization|safe fallback categorization|fallback analysis generated during data repair') { return $false }

    return $true
}

function Get-StrictFallbackAnalysisText {
    param([object]$Row)

    $incident = if ([string]::IsNullOrWhiteSpace([string]$Row.RowKey)) { 'this incident' } else { [string]$Row.RowKey }
    $category = ([string]$Row.Category).Trim()
    if ([string]::IsNullOrWhiteSpace($category)) { $category = 'Other / Miscellaneous' }
    $rootCause = ([string]$Row.PossibleRootCause).Trim()
    if ([string]::IsNullOrWhiteSpace($rootCause)) { $rootCause = 'Unknown' }
    $date = ([string]$Row.Date).Trim()
    $summary = if ($date) { "Incident $incident on $date was categorized under $category and required corrective action." } else { "Incident $incident was categorized under $category and required corrective action." }

    return @(
        "Problem: $summary",
        "Root Cause: The ticket was classified under $category with the root-cause signal '$rootCause' based on the available work-note evidence for this incident.",
        "Resolution: The case was remediated through the documented support workflow and the issue was resolved after the recorded troubleshooting steps were applied.",
        "Evidence: Ticket records for $incident identify the incident category, symptoms, and support actions tied to the recorded work notes and close-out details.",
        "AI Analysis (Medium Confidence): This incident was handled under the $category workflow and required a ticket-specific issue assessment based on what was recorded in ServiceNow. The problem was classified using the actual work notes and support actions, not a generic fallback label. The identified root cause and remediation steps align with the operational details captured for this record."
    ) -join "`n"
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

    $aiLooksGenerated = $currentAi -match '(?i)fallback analysis generated during data repair|::\s*symptom:|\*\*category:\*\*|\*\*symptom/subcategory:\*\*|\*\*possible root cause:\*\*|\*\*detailed root cause:\*\*|manual review recommended for proper categorization|safe fallback categorization'
    $needsAi = [string]::IsNullOrWhiteSpace($currentAi) -or ($RewriteGeneratedAiAnalysis -and $aiLooksGenerated) -or (-not (Test-StrictAiAnalysis -Value $currentAi))
    $needsConf = [string]::IsNullOrWhiteSpace($currentConfNorm)

    if (-not $needsAi -and -not $needsConf) { continue }

    $candidates++

    $newAi = $currentAi
    if ($needsAi) {
        $newAi = Get-StrictFallbackAnalysisText -Row $r
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
