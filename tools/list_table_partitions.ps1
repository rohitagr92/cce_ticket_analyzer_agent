$ResourceGroup = 'OPSW-Ticket-Analyzer'
$StorageAccount = 'opswprodtoolsblob'
$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $key
$sas = New-AzStorageTableSASToken -Name 'IncidentsCategoryStats' -Permission 'r' -ExpiryTime (Get-Date).AddMinutes(15) -Protocol HttpsOnly -Context $ctx
$base = "https://$StorageAccount.table.core.windows.net/IncidentsCategoryStats()?$sas"
$url = $base + "&`$select=PartitionKey&`$top=1000"
$partitions = @()
while ($url) {
    $r = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
    $vals = ($r.Content | ConvertFrom-Json).value
    $partitions += ($vals | ForEach-Object { $_.PartitionKey })
    $npk = $r.Headers['x-ms-continuation-NextPartitionKey']
    $nrk = $r.Headers['x-ms-continuation-NextRowKey']
    if ($npk) { $url = $base + "?`$select=PartitionKey&NextPartitionKey=" + [Uri]::EscapeDataString([string]$npk); if ($nrk) { $url += '&NextRowKey=' + [Uri]::EscapeDataString([string]$nrk) } } else { $url = $null }
}
$partitions | Sort-Object -Unique | ForEach-Object { Write-Output $_ }
