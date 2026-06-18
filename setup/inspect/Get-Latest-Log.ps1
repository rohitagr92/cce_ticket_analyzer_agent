$key = (Get-AzStorageAccountKey -ResourceGroupName 'OPSW-Ticket-Analyzer' -Name 'opswprodtoolsblob')[0].Value
$ctx = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -StorageAccountKey $key
$logCont = 'logs'
Write-Host "LogContainer: $logCont"
$latest = Get-AzStorageBlob -Container $logCont -Context $ctx -Prefix 'AI-ResolvedIncidents-StrictCategorization' | Sort-Object LastModified -Descending | Select-Object -First 1
Write-Host "Latest log: $($latest.Name) ($($latest.LastModified.UtcDateTime))"
$tmp = [IO.Path]::GetTempFileName()
Get-AzStorageBlobContent -Container $logCont -Blob $latest.Name -Destination $tmp -Context $ctx -Force | Out-Null
$lines = Get-Content $tmp
Remove-Item $tmp -Force
Write-Host "Total log lines: $($lines.Count)"
Write-Host "`n=== PRC-DIAG lines ===" -ForegroundColor Cyan
$lines | Select-String 'PRC-DIAG' | ForEach-Object { $_.Line }
Write-Host "`n=== Coerced category lines (first 5) ===" -ForegroundColor Cyan
$lines | Select-String 'Coerced category' | Select-Object -First 5 | ForEach-Object { $_.Line }
Write-Host "`n=== Canonical labels loaded ===" -ForegroundColor Cyan
$lines | Select-String 'Canonical labels' | ForEach-Object { $_.Line }
