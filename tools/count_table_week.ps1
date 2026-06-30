$ResourceGroup = 'OPSW-Ticket-Analyzer'
$StorageAccount = 'opswprodtoolsblob'
$table = 'IncidentsCategoryStats'
$week = '2026-W26'
$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $key
$sas = New-AzStorageTableSASToken -Name $table -Permission r -ExpiryTime (Get-Date).AddMinutes(15) -Protocol HttpsOnly -Context $ctx
$base = "https://$StorageAccount.table.core.windows.net/$table()?$sas"
$filter = "`$filter=PartitionKey eq '$week'"
$url = $base + '&' + $filter + "&`$top=1000"
$count = 0
while ($url) {
    $r = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
    $vals = ($r.Content | ConvertFrom-Json).value
    if ($vals) { $count += $vals.Count }
    $npk = $r.Headers['x-ms-continuation-NextPartitionKey']
    $nrk = $r.Headers['x-ms-continuation-NextRowKey']
    if ($npk) { $url = $base + '&' + $filter + '&NextPartitionKey=' + [Uri]::EscapeDataString([string]$npk); if ($nrk) { $url += '&NextRowKey=' + [Uri]::EscapeDataString([string]$nrk) } }
    else { $url = $null }
}
Write-Output "$week rows: $count"
