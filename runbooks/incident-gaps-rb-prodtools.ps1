<#
.SYNOPSIS
    Daily gap-quality analysis for Productivity Tools incidents.
    Queries IncidentsCategoryStats for Low/Medium confidence tickets,
    classifies quality gaps, and uploads ticket_gaps_productivity-tools.json
    to the results blob container — no dependency on any other runbook.

.NOTES
    Schedule: ProdTools-GapAnalysis-0600IST (12:30 AM UTC = 6:00 AM IST)
    Uses same managed identity and automation variables as the analyzer runbook.
#>

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Msg) Write-Output "[$(Get-Date -Format 'HH:mm:ss')] $Msg" }

# ── Auth ──────────────────────────────────────────────────────────────────────
Write-Step 'Connecting to Azure...'
Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity | Out-Null

$storageAccount   = Get-AutomationVariable -Name 'Incidents_analyzer_StorageAccountName'
$resourceGroup    = Get-AutomationVariable -Name 'Incidents_analyzer_ResourceGroupName'
$tableName        = 'IncidentsCategoryStats'
$resultsContainer = Get-AutomationVariable -Name 'Incidents_analyzer_ResultsContainerName'

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageAccount)[0].Value
$saCtx      = New-AzStorageContext -StorageAccountName $storageAccount -StorageAccountKey $storageKey

# ── Fetch Low/Medium confidence incidents ─────────────────────────────────────
Write-Step 'Fetching Low/Medium confidence incidents...'
$sas = New-AzStorageTableSASToken -Name $tableName -Permission 'r' `
    -ExpiryTime (Get-Date).AddMinutes(30) -Protocol HttpsOnly -Context $saCtx
$uri = "https://$storageAccount.table.core.windows.net/$tableName()?`$select=PartitionKey,RowKey,Category,Subcategory,RootCause,Confidence,AIAnalysis&$sas"
$rows = @(); $next = $uri
while ($next) {
    $r = Invoke-WebRequest -Uri $next -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
    $rows += ($r.Content | ConvertFrom-Json).value
    $npk = $r.Headers['x-ms-continuation-NextPartitionKey']
    $nrk = $r.Headers['x-ms-continuation-NextRowKey']
    $next = if ($npk) { $uri + '&NextPartitionKey=' + [Uri]::EscapeDataString([string]$npk) + (if ($nrk) { '&NextRowKey=' + [Uri]::EscapeDataString([string]$nrk) } else { '' }) } else { $null }
}

$pool = $rows | Where-Object {
    $c = ($_.Confidence -replace '\s', '').ToLower()
    ($c -eq 'low' -or $c -eq 'medium') -and $_.AIAnalysis -and $_.AIAnalysis.Length -gt 50
} | Select-Object -First 100

Write-Step "Pool: $($pool.Count) Low/Medium confidence incidents to analyze"

# ── Gap classification ────────────────────────────────────────────────────────
function Classify-Gap {
    param([string]$RowKey, [string]$Category, [string]$RootCause, [string]$Analysis)
    $gaps = @()
    $a  = $Analysis.ToLower()
    $rc = $RootCause.ToLower()
    $cat = $Category.ToLower()

    if (($cat -match 'copilot|365 apps') -and ($rc -match 'license|sku|blackout|propagation') -and
        ($a -notmatch '15 min|30 min|wait|propagat|hours')) {
        $gaps += [PSCustomObject]@{ ticket = $RowKey; category = 'License Propagation Wait Skipped'
            description = 'License-related incident closed without advising the user to wait for propagation (15 min – 4 hours).' }
    }
    if (($cat -match 'onedrive') -and ($rc -match 'sync stall|sync|client') -and
        ($a -notmatch 'reset|onedrive\.exe|sign.out|unlink')) {
        $gaps += [PSCustomObject]@{ ticket = $RowKey; category = 'OneDrive Reset Not Attempted'
            description = 'OneDrive sync issue resolved without attempting OneDrive client reset or re-link.' }
    }
    if (($rc -match 'sync|sign.in|connectivity|failure') -and
        ($a -notmatch '0x|error code|error message|screenshot')) {
        $gaps += [PSCustomObject]@{ ticket = $RowKey; category = 'Missing Error Code / Evidence'
            description = 'Sync or sign-in failure closed without capturing specific error codes or screenshots.' }
    }
    if (($a -match 'escalat') -and ($a -notmatch 'restart|sign.out|repair|reset|clear cache|basic')) {
        $gaps += [PSCustomObject]@{ ticket = $RowKey; category = 'Premature Escalation'
            description = 'Ticket escalated without evidence that standard L1 troubleshooting steps were attempted first.' }
    }
    if ($Analysis.Length -lt 150 -and ($a -match 'issue.*resolv|user.*resolv|ticket.*clos|resolv.*issue')) {
        $gaps += [PSCustomObject]@{ ticket = $RowKey; category = 'Vague / Insufficient Documentation'
            description = 'Work notes are too brief. No specific troubleshooting steps, evidence, or resolution confirmation captured.' }
    }
    if (($rc -match 'pc refresh|known folder|missing files') -and
        ($a -notmatch 'kfm|known folder|onedrive sign|backup')) {
        $gaps += [PSCustomObject]@{ ticket = $RowKey; category = 'KFM / Backup Verification Skipped'
            description = 'PC refresh missing files incident closed without verifying Known Folder Move (KFM) status on old device.' }
    }
    return $gaps
}

$allGaps = @()
foreach ($row in $pool) {
    $allGaps += Classify-Gap -RowKey $row.RowKey -Category $row.Category `
        -RootCause ($row.RootCause -replace '[*]', '') -Analysis $row.AIAnalysis
}

$uniqueWithGaps = ($allGaps | Select-Object ticket -Unique | Measure-Object).Count
$gapRate        = if ($pool.Count -gt 0) { [math]::Round($uniqueWithGaps / $pool.Count * 100, 1) } else { 0 }
$dist           = $allGaps | Group-Object category | Sort-Object Count -Descending

Write-Step "Gaps: $($allGaps.Count) in $($pool.Count) reviewed | $uniqueWithGaps tickets | $gapRate% rate | $($dist.Count) categories"

# ── Build JSON ────────────────────────────────────────────────────────────────
$badges  = @('r', 'o', 'y', 'b', 'p', 'p', 'p')
$distArr = @()
$i = 0
foreach ($grp in $dist) {
    $pct = if ($allGaps.Count -gt 0) { [math]::Round($grp.Count / $allGaps.Count * 100, 1) } else { 0 }
    $distArr += [ordered]@{
        rank     = $i + 1
        category = $grp.Name
        count    = $grp.Count
        pct      = $pct
        badge    = $badges[$i % $badges.Count]
        tickets  = @($grp.Group | Select-Object -ExpandProperty ticket -Unique)
    }
    $i++
}

$output = [ordered]@{
    service        = 'Productivity Tools'
    review_date    = (Get-Date -Format 'yyyy-MM-dd')
    total_reviewed = $pool.Count
    kpis           = [ordered]@{
        tickets_reviewed = $pool.Count
        gaps_identified  = $uniqueWithGaps
        gap_rate_pct     = $gapRate
        gap_categories   = $dist.Count
    }
    distribution    = $distArr
    per_ticket_gaps = @($allGaps | ForEach-Object { [ordered]@{ category = $_.category; ticket = $_.ticket; description = $_.description } })
    recommendations = @(
        [ordered]@{ num = 1; title = 'Advise License Propagation Wait'; body = 'For all Copilot and M365 licensing issues: always tell the user to wait 15 min – 4 hours after AGS approval before escalating. Document expected wait in work notes.' }
        [ordered]@{ num = 2; title = 'Attempt OneDrive Reset Before Escalating'; body = 'For OneDrive sync failures: perform reset (onedrive.exe /reset), sign-out/in, or re-link before escalating. Document the steps and outcome.' }
        [ordered]@{ num = 3; title = 'Capture Error Codes and Screenshots'; body = 'For sync, sign-in, or connectivity failures: capture the exact error code (0x80xxxxxx) or screenshot before applying any fix.' }
        [ordered]@{ num = 4; title = 'Complete L1 Steps Before Escalating'; body = 'Escalation requires evidence that basic steps (restart, sign-out/in, clear cache, repair) were attempted and documented.' }
        [ordered]@{ num = 5; title = 'Verify KFM Before Closing Refresh Tickets'; body = 'For PC refresh missing file reports: always verify whether Known Folder Move was enabled on the old device. If not, set correct expectations.' }
    )
}

# ── Upload to blob ────────────────────────────────────────────────────────────
$blobName = 'ticket_gaps_productivity-tools.json'
$tmpFile  = [System.IO.Path]::GetTempFileName()
try {
    $output | ConvertTo-Json -Depth 6 | Out-File -FilePath $tmpFile -Encoding UTF8 -NoNewline
    Set-AzStorageBlobContent -File $tmpFile -Container $resultsContainer -Blob $blobName `
        -Context $saCtx -Properties @{ ContentType = 'application/json' } -Force | Out-Null
    Write-Step "Uploaded $blobName to $resultsContainer"
} finally {
    if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
}

Write-Step '=== Gap analysis complete ==='
