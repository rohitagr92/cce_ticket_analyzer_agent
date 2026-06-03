$ErrorActionPreference = 'Stop'
$key = (Get-AzStorageAccountKey -ResourceGroupName 'OPSW-Ticket-Analyzer' -Name 'opswprodtoolsblob')[0].Value
$ctx = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -StorageAccountKey $key
$sas = New-AzStorageTableSASToken -Name 'IncidentsCategoryStats' -Permission 'r' -ExpiryTime (Get-Date).AddMinutes(10) -Protocol HttpsOnly -Context $ctx

# Sample current week
$ww = '2026-W23'
$url = "https://opswprodtoolsblob.table.core.windows.net/IncidentsCategoryStats()?`$filter=PartitionKey%20eq%20%27$ww%27&`$top=5&$sas"
$resp = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
$rows = ($resp.Content | ConvertFrom-Json).value
Write-Host "Week $ww - sample of $($rows.Count) rows`n" -ForegroundColor Cyan
foreach ($r in $rows) {
    Write-Host "RowKey: $($r.RowKey)"
    $r.PSObject.Properties | Where-Object { $_.Name -in 'Category','Subcategory','PossibleRootCause','DetailedRootCause','Service','Misrouted' } | ForEach-Object {
        '  {0,-20} = {1}' -f $_.Name, $_.Value
    }
    Write-Host ''
}
$present = $rows[0].PSObject.Properties.Name
Write-Host "All columns present on first row:" -ForegroundColor Yellow
$present -join ', '
