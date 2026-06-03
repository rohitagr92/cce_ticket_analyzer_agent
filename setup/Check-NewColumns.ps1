$ctx = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -UseConnectedAccount
$tbl = Get-AzStorageTable -Name 'IncidentsCategoryStats' -Context $ctx -ErrorAction Stop
Write-Host "Table found: $($tbl.Name)" -ForegroundColor Green
$cloudTbl = $tbl.CloudTable

$q = [Microsoft.Azure.Cosmos.Table.TableQuery]::new()
$q.TakeCount = 5
try {
    $rows = @($cloudTbl.ExecuteQuery($q))
    Write-Host "Sample rows: $($rows.Count)"
    foreach ($r in $rows) {
        $p = $r.Properties
        Write-Host "`n--- PK=$($r.PartitionKey) RK=$($r.RowKey) ---"
        $p.GetEnumerator() | ForEach-Object {
            "$($_.Key) = $($_.Value.PropertyAsObject)"
        }
    }
} catch {
    Write-Host "Query error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red
}
