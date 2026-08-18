# HDI PRC Review Analysis
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Connect-AzAccount -Subscription '1c6d384e-bc83-4b02-859c-76eeb87f7676' | Out-Null
Set-AzContext -Subscription '1c6d384e-bc83-4b02-859c-76eeb87f7676' | Out-Null
$rg = 'OPSW-Ticket-Analyzer'; $sa = 'opswprodtoolsblob'
$key = ((Get-AzStorageAccountKey -ResourceGroupName $rg -AccountName $sa)[0].Value)
$ctx = New-AzStorageContext -StorageAccountName $sa -StorageAccountKey $key
Import-Module AzTable -Force
$tbl = (Get-AzStorageTable -Name 'IncidentsCategoryStats' -Context $ctx).CloudTable

$cfg = Import-PowerShellDataFile (Join-Path $repoRoot 'config\LocalConfig-ProductivityTools.psd1')
if (Test-Path (Join-Path $repoRoot 'config\LocalSecrets-ProductivityTools.psd1')) {
    $sec = Import-PowerShellDataFile (Join-Path $repoRoot 'config\LocalSecrets-ProductivityTools.psd1')
    foreach ($k in $sec.Keys) { $cfg[$k] = $sec[$k] }
}
$oaiBase = $cfg.AzureOpenAIBaseUrl; $oaiDeploy = $cfg.AzureOpenAIDeployment
$oaiVer = $cfg.AzureOpenAIApiVersion; $oaiKey = $cfg.AzureOpenAIApiKey
$uri = "$oaiBase/openai/deployments/$oaiDeploy/chat/completions?api-version=$oaiVer"

# Canonical PRC lists per category (from template, cleaned)
$prcMap = @{
    'Microsoft OneDrive Issues' = 'Sync Stall, Long File Path Issue, File Availability Setting, Quota Storage Issue, OneDrive Client Failure, Shared File Permission Denied, Stale or Revoked Share Link, PUID Mismatch, Rejoin Access Issue, Prior OneDrive Site Expired, Former Employee Data Request, Prior OneDrive Site Inaccessible, Missing Files After PC Refresh, OneDrive Sign-In / Connectivity Failure, Known Folder Backup Failure, Permission issue on the synced file or shortcut'
    'Microsoft 365 Copilot Issues' = 'Copilot License Blackout, Copilot SKU Not Provisioned, License Propagation Delay, ChunkLoadError / Stale Cache, Phased Rollout Gate, License Not Assigned After Rejoin, Feature Inconsistency Across Apps, Copilot Transient Service Issue, Copilot Access / Environment Configuration Issue'
    'Microsoft 365 Apps for Enterprise Issues' = 'Corrupted Office Identity, F3 License Restriction, Licensing Endpoint Unreachable, Click-to-Run Installer Corruption, Company Portal Install Stuck, Office Feature Not Working, License Not Assigned After Rejoin, Office App Crash, Office Compatibility Issue, Sign-in / Login Failure, Office Activation Failure'
    'Microsoft Word Issues' = 'Corporate Add-in Not Available, Office Store Blocked by Policy, Word Document Won''t Open, Word File Corruption, Hung Word Process, Word Performance Degradation, Word Formatting / Layout Issue, Document lock or stuck Word process'
}

$weeks = 19..34 | ForEach-Object { '2026-W{0:D2}' -f $_ }
$allHDI = [System.Collections.Generic.List[object]]::new()
foreach ($w in $weeks) {
    $rows = @(Get-AzTableRow -Table $tbl -PartitionKey $w | Where-Object { [string]$_.PossibleRootCause -imatch 'How Do I|Usage Guidance' })
    $rows | ForEach-Object { $allHDI.Add($_) }
}
Write-Host "HDI tickets: $($allHDI.Count)"

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($row in $allHDI) {
    $cat = [string]$row.Category
    $prcList = $prcMap[$cat]
    if (-not $prcList) { $prcList = 'Unknown' }

    $ai = ([string]$row.AIAnalysis)
    if ([string]::IsNullOrWhiteSpace($ai)) { 
        $results.Add([PSCustomObject]@{ Week=$row.PartitionKey; Incident=$row.RowKey; Category=$cat; OldPRC='Usage Guidance (How Do I)'; ProposedPRC='Unknown'; AISnippet='(no AI data)' })
        continue
    }

    $aiSnippet = $ai.Substring(0, [Math]::Min(200, $ai.Length)) -replace "`n", ' '
    $sys = "You are a ticket classifier. This is a 'How Do I' guidance question - the user asked for help, not reporting a failure. Pick ONE specific root cause label from the list below that best describes WHAT the user needed help with (the underlying product capability or issue area). Do NOT output 'Usage Guidance (How Do I)'. If nothing fits, output: Unknown.`n`nAvailable PRC labels for '$cat':`n$prcList`n`nOutput format (one line only): Proposed PRC: <label>"

    try {
        $b = [ordered]@{ messages=@(@{role='system';content=$sys},@{role='user';content=$ai}); temperature=0; max_completion_tokens=50 } | ConvertTo-Json -Depth 10
        $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers @{ 'api-key'=$oaiKey; 'Content-Type'='application/json' } -Body $b
        $txt = $resp.choices[0].message.content.Trim()
        $proposed = if ($txt -match '(?im)Proposed PRC:\s*(.+)') { $Matches[1].Trim() -replace '\*+','' } else { $txt -replace '\*+','' }
        Write-Host "  $($row.PartitionKey)/$($row.RowKey) [$cat] -> $proposed"
        $results.Add([PSCustomObject]@{ Week=$row.PartitionKey; Incident=$row.RowKey; Category=$cat; OldPRC='Usage Guidance (How Do I)'; ProposedPRC=$proposed; AISnippet=$aiSnippet })
    } catch {
        Write-Host "  ERR $($row.PartitionKey)/$($row.RowKey): $($_.Exception.Message)"
        $results.Add([PSCustomObject]@{ Week=$row.PartitionKey; Incident=$row.RowKey; Category=$cat; OldPRC='Usage Guidance (How Do I)'; ProposedPRC='ERR'; AISnippet=$aiSnippet })
    }
}

Write-Host "`n=== REVIEW TABLE ==="
$results | Format-Table -AutoSize -Property Week,Incident,Category,OldPRC,ProposedPRC

$outCsv = Join-Path $PSScriptRoot 'HDI-PRC-Review.csv'
$results | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8
Write-Host "`nFull review saved to: $outCsv"
