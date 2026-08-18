<#
.SYNOPSIS
    Finds WW32-WW34 tickets tagged "Copilot License Blackout" and
    recategorizes any that fail the mandatory evidence gate.
.NOTES
    Run from repo root after az login / Connect-AzAccount.
    -DryRun shows what would change without writing.
#>
param(
    [string[]]$Weeks   = @('2026-W32','2026-W33','2026-W34'),
    [switch]$DryRun,
    [switch]$ForceAll
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Connect-AzAccount -Subscription '1c6d384e-bc83-4b02-859c-76eeb87f7676' | Out-Null
Set-AzContext   -Subscription '1c6d384e-bc83-4b02-859c-76eeb87f7676' | Out-Null

$rg  = 'OPSW-Ticket-Analyzer'
$sa  = 'opswprodtoolsblob'
$key = ((Get-AzStorageAccountKey -ResourceGroupName $rg -AccountName $sa)[0].Value)
$ctx = New-AzStorageContext -StorageAccountName $sa -StorageAccountKey $key

$cfg     = Import-PowerShellDataFile (Join-Path $repoRoot 'config\LocalConfig-ProductivityTools.psd1')
$secPath = Join-Path $repoRoot 'config\LocalSecrets-ProductivityTools.psd1'
if (Test-Path $secPath) {
    $sec = Import-PowerShellDataFile $secPath
    foreach ($k in $sec.Keys) { $cfg[$k] = $sec[$k] }
}
$oaiBase    = $cfg.AzureOpenAIBaseUrl
$oaiDeploy  = $cfg.AzureOpenAIDeployment
$oaiVersion = $cfg.AzureOpenAIApiVersion
$oaiKey     = $cfg.AzureOpenAIApiKey

function Get-BlobText([string]$name) {
    $b = Get-AzStorageBlob -Container 'templates' -Blob $name -Context $ctx
    $s = $b.ICloudBlob.OpenRead()
    $r = [System.IO.StreamReader]::new($s)
    $c = $r.ReadToEnd()
    $r.Dispose(); $s.Dispose()
    return $c
}
Write-Host 'Loading templates...' -ForegroundColor Cyan
$tplTicket = Get-BlobText 'TicketCategorisation_ProductivityTools.md'
$tplPRC    = Get-BlobText 'PossibleRootCause_ProductivityTools.md'
$tplDRC    = Get-BlobText 'DetailedRootCause_ProductivityTools.md'
$tplTrend  = Get-BlobText 'TrendSubCategorisation_ProductivityTools.md'

Import-Module AzTable -Force
$cloudTable = (Get-AzTableTable -storageAccountFriendlyName $sa -resourceGroup $rg -TableName 'IncidentsCategoryStats').CloudTable

# Returns $true when the stored row should NOT be "Copilot License Blackout"
function Test-GateFails([object]$Row) {
    if ($ForceAll) { return $true }
    $text = ('{0} {1} {2} {3}' -f [string]$Row.AIAnalysis, [string]$Row.RootCauseNarrative, [string]$Row.Resolution, [string]$Row.Issue)
    $licActive  = $text -imatch 'license (is |was |has been )?(verified|active|assigned|valid)|assigned and active|license assigned|entitlement (is |was )?(active|valid|confirmed)'
    $worksOther = $text -imatch 'copilot (is |was )?(working|present|works) in (other|another)|works in (teams|word|outlook|powerpoint|onenote)|other (office |microsoft )?(apps?|applications?)'
    $selfFixed  = $text -imatch 'self.resolv|resolved without|no license change|service.side outage|microsoft.acknowledged'
    return ($licActive -or $worksOther -or $selfFixed)
}

function Invoke-AiRecategorize([object]$Row) {
    $extraNote = "IMPORTANT: The previous classification used 'Copilot License Blackout'. " +
        "Apply the mandatory evidence gate from PossibleRootCause section 3.1. " +
        "ELIMINATE Copilot License Blackout if: license is shown active in AGS, OR Copilot works in another host app. " +
        "Use 'Feature Inconsistency Across Apps', 'Copilot Access / Environment Configuration Issue', or 'Copilot Transient Service Issue' instead if the gate fails."

    $sys  = $tplTicket + "`n## REFERENCE: Sub-symptoms`n" + $tplTrend +
            "`n## REFERENCE: PRC Labels`n" + $tplPRC +
            "`n## REFERENCE: DRC Entries`n" + $tplDRC +
            "`n`n" + $extraNote

    $user = "Incident: $([string]$Row.RowKey)`n" +
            "Category: $([string]$Row.Category)`n" +
            "Current PRC (may be wrong): $([string]$Row.PossibleRootCause)`n" +
            "Issue: $([string]$Row.Issue)`n" +
            "Root Cause Narrative: $([string]$Row.RootCauseNarrative)`n" +
            "Resolution: $([string]$Row.Resolution)`n" +
            "AI Analysis: $([string]$Row.AIAnalysis)"

    $bodyJson = (@{
        messages    = @(@{ role='system'; content=$sys }, @{ role='user'; content=$user })
        temperature = 0
        max_completion_tokens = 600
    } | ConvertTo-Json -Depth 10)

    $uri  = "$oaiBase/openai/deployments/$oaiDeploy/chat/completions?api-version=$oaiVersion"
    $resp = Invoke-RestMethod -Method Post -Uri $uri `
        -Headers @{ 'api-key'=$oaiKey; 'Content-Type'='application/json' } `
        -Body $bodyJson
    return $resp.choices[0].message.content
}

function Get-Field([string]$Text, [string]$Label) {
    if ($Text -match "(?im)^\s*$([regex]::Escape($Label)):\s*(.+?)\s*$") {
        return ($Matches[1].Trim() -replace '\*+', '')
    }
    return $null
}

$summary = [System.Collections.Generic.List[hashtable]]::new()

foreach ($week in $Weeks) {
    Write-Host ("`n=== $week ===") -ForegroundColor Cyan
    $allRows      = @(Get-AzTableRow -Table $cloudTable -PartitionKey $week)
    $blackoutRows = @($allRows | Where-Object { [string]$_.PossibleRootCause -imatch 'Copilot License Blackout' })
    Write-Host "  Rows: $($allRows.Count)   Copilot License Blackout: $($blackoutRows.Count)"

    foreach ($row in $blackoutRows) {
        $inc = [string]$row.RowKey
        if (-not (Test-GateFails $row)) {
            Write-Host "  [KEEP  ] $inc — evidence confirms real blackout" -ForegroundColor Green
            $summary.Add(@{ Week=$week; Inc=$inc; Action='KEEP'; Old='Copilot License Blackout'; New='' })
        } elseif ($DryRun) {
            Write-Host "  [DRYRUN] $inc — would recategorize" -ForegroundColor Yellow
            $summary.Add(@{ Week=$week; Inc=$inc; Action='DRYRUN'; Old='Copilot License Blackout'; New='?' })
        } else {
            Write-Host "  [FIX   ] $inc — calling AI..." -ForegroundColor Yellow
            $aiText = Invoke-AiRecategorize $row
            $newPRC = Get-Field $aiText 'Possible Root Cause'
            $newDRC = Get-Field $aiText 'Detailed Root Cause'
            $newReason = Get-Field $aiText 'Reasoning'

            if (-not $newPRC -or $newPRC -ieq 'Copilot License Blackout') {
                Write-Host "         AI returned unchanged or blank PRC — skipping" -ForegroundColor Red
                $summary.Add(@{ Week=$week; Inc=$inc; Action='SKIP'; Old='Copilot License Blackout'; New=$newPRC })
            } else {
                $row.PossibleRootCause = $newPRC
                $row.RootCause         = $newPRC
                $row.TopRootCause      = $newPRC
                if ($newDRC)    { $row.DetailedRootCause = $newDRC }
                if ($newReason) { $row.AIAnalysis         = $newReason }
                $row.RepairNote = "Recategorized from Copilot License Blackout $(Get-Date -Format 'yyyy-MM-dd')"
                $row | Update-AzTableRow -Table $cloudTable | Out-Null
                Write-Host "         Fixed: $newPRC" -ForegroundColor Green
                if ($newDRC) { Write-Host "         DRC  : $newDRC" -ForegroundColor Green }
                $summary.Add(@{ Week=$week; Inc=$inc; Action='FIXED'; Old='Copilot License Blackout'; New=$newPRC })
            }
        }
    }
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
$summary | ForEach-Object {
    Write-Host ("  [{0,-8}] {1}  {2}  ->  {3}" -f $_['Action'], $_['Week'], $_['Inc'], $_['New'])
}

$fixedWeeks = @($summary | Where-Object { $_['Action'] -eq 'FIXED' } | ForEach-Object { $_['Week'] }) | Select-Object -Unique
if ($fixedWeeks.Count -gt 0) {
    Write-Host "`nTickets updated. Regenerate reports for: $($fixedWeeks -join ', ')" -ForegroundColor Green
} else {
    Write-Host "`nNo tickets changed." -ForegroundColor Yellow
}
