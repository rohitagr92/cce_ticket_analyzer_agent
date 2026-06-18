$key = (Get-AzStorageAccountKey -ResourceGroupName 'OPSW-Ticket-Analyzer' -Name 'opswprodtoolsblob')[0].Value
$ctx = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -StorageAccountKey $key
$blobs = Get-AzStorageBlob -Container 'data' -Context $ctx -Prefix 'run_artifact_'
$cutoff = [DateTime]::Parse('2026-06-01T00:00:00Z')
$toDelete = $blobs | Where-Object { $_.LastModified.UtcDateTime -ge $cutoff }
Write-Host "Will delete $($toDelete.Count) W23 artifacts:" -ForegroundColor Yellow
$toDelete | ForEach-Object { Write-Host "  $($_.Name)" }
foreach ($b in $toDelete) {
    Remove-AzStorageBlob -Container 'data' -Blob $b.Name -Context $ctx -Force
}
Write-Host "Done." -ForegroundColor Green
