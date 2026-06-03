$sa = Get-AzAutomationVariable -ResourceGroupName 'OPSW-Ticket-Analyzer' -AutomationAccountName 'OPSW-ProductivityTools-account' -Name 'Incidents_analyzer_DataContainerName'
Write-Host "DataContainer: $($sa.Value)" -ForegroundColor Cyan
$key = (Get-AzStorageAccountKey -ResourceGroupName 'OPSW-Ticket-Analyzer' -Name 'opswprodtoolsblob')[0].Value
$ctx = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -StorageAccountKey $key
$blobs = Get-AzStorageBlob -Container $sa.Value -Context $ctx -Prefix 'run_artifact_' | Sort-Object LastModified -Descending
Write-Host "Found $($blobs.Count) run_artifact_ blobs"
$blobs | Select-Object -First 15 | Select-Object Name, @{N='ModUtc';E={$_.LastModified.UtcDateTime}}, Length | Format-Table -AutoSize
