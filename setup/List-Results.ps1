$key = (Get-AzStorageAccountKey -ResourceGroupName 'OPSW-Ticket-Analyzer' -Name 'opswprodtoolsblob')[0].Value
$ctx = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -StorageAccountKey $key
Get-AzStorageBlob -Container 'results' -Context $ctx |
    Sort-Object LastModified -Descending |
    Select-Object Name, LastModified, @{N = 'SizeKB'; E = { [math]::Round($_.Length / 1024, 1) } } |
    Format-Table -AutoSize
