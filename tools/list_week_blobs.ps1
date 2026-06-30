$rg='OPSW-Ticket-Analyzer'
$sa='opswprodtoolsblob'
$key=(Get-AzStorageAccountKey -ResourceGroupName $rg -Name $sa)[0].Value
$ctx=New-AzStorageContext -StorageAccountName $sa -StorageAccountKey $key
$blobs = Get-AzStorageBlob -Container results -Context $ctx | Where-Object { $_.Name -like 'ProductivityTools_Weekly_Report_2026-W25*' -or $_.Name -like 'ProductivityTools_Weekly_Report_2026-W26*' }
if ($blobs.Count -gt 0) {
    foreach ($b in $blobs) { Write-Output ("$($b.Name) | $($b.Length) bytes | $($b.LastModified)") }
} else { Write-Output 'No matching blobs found' }
