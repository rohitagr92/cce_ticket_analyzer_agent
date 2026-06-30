param([string[]]$Incidents)
$ResourceGroup = 'OPSW-Ticket-Analyzer'
$StorageAccount = 'opswprodtoolsblob'
$table = 'IncidentsCategoryStats'
$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $key
$sas = New-AzStorageTableSASToken -Name $table -Permission r -ExpiryTime (Get-Date).AddMinutes(15) -Protocol HttpsOnly -Context $ctx
$base = "https://$StorageAccount.table.core.windows.net/$table()?$sas"
foreach ($inc in $Incidents) {
    $filter = "`$filter=RowKey eq '$inc'"
    $url = $base + '&' + $filter + "&`$top=1000"
    try {
        $r = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
        $vals = ($r.Content | ConvertFrom-Json).value
        if ($vals -and $vals.Count -gt 0) {
            foreach ($v in $vals) { Write-Output "$inc -> PartitionKey=$($v.PartitionKey) | RowKey=$($v.RowKey)" }
        } else { Write-Output "$inc -> Not found in table" }
    } catch {
        $msg = $_.Exception.Message -replace '"','' 
        Write-Output ("Error querying for {0}: {1}" -f $inc, $msg)
    }
}
