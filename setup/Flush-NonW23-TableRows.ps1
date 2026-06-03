# Deletes all rows from IncidentsCategoryStats EXCEPT PartitionKey = '2026-W23'
param(
    [string]$ResourceGroupName = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccountName = 'opswprodtoolsblob',
    [string]$TableName          = 'IncidentsCategoryStats',
    [string]$KeepPartitionKey   = '2026-W23'
)

$ErrorActionPreference = 'Stop'

$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $key
$table = (Get-AzStorageTable -Name $TableName -Context $ctx).CloudTable

# Query all rows where PartitionKey != KeepPartitionKey
Add-Type -AssemblyName 'Microsoft.Azure.Cosmos.Table' -ErrorAction SilentlyContinue

$filter = "PartitionKey ne '$KeepPartitionKey'"
$query = New-Object Microsoft.Azure.Cosmos.Table.TableQuery
$query = $query.Where($filter)

Write-Host "Scanning table '$TableName' for rows where PartitionKey != '$KeepPartitionKey'..." -ForegroundColor Cyan

$token = $null
$batches = @{}   # PartitionKey -> list of entities
$totalFound = 0
do {
    $segment = $table.ExecuteQuerySegmentedAsync($query, $token).GetAwaiter().GetResult()
    foreach ($e in $segment.Results) {
        if (-not $batches.ContainsKey($e.PartitionKey)) {
            $batches[$e.PartitionKey] = New-Object System.Collections.Generic.List[object]
        }
        $batches[$e.PartitionKey].Add($e)
        $totalFound++
    }
    $token = $segment.ContinuationToken
} while ($null -ne $token)

Write-Host "Found $totalFound rows to delete across $($batches.Keys.Count) partitions:" -ForegroundColor Yellow
$batches.Keys | Sort-Object | ForEach-Object { "  $_  ($($batches[$_].Count) rows)" }

if ($totalFound -eq 0) { Write-Host "Nothing to delete."; return }

Write-Host "`nDeleting..." -ForegroundColor Cyan
$deleted = 0
foreach ($pk in $batches.Keys) {
    $entities = $batches[$pk]
    # Azure Table batch limit = 100 ops per batch, single partition
    for ($i = 0; $i -lt $entities.Count; $i += 100) {
        $chunk = $entities | Select-Object -Skip $i -First 100
        $batch = New-Object Microsoft.Azure.Cosmos.Table.TableBatchOperation
        foreach ($e in $chunk) {
            $e.ETag = '*'
            $batch.Delete($e)
        }
        $table.ExecuteBatchAsync($batch).GetAwaiter().GetResult() | Out-Null
        $deleted += $chunk.Count
        Write-Host "  $pk : $deleted / $totalFound" -ForegroundColor DarkGray
    }
}
Write-Host "`nDone. Deleted $deleted rows. Kept PartitionKey '$KeepPartitionKey'." -ForegroundColor Green

# Verify remaining row count for KeepPartitionKey
$verifyFilter = "PartitionKey eq '$KeepPartitionKey'"
$verifyQuery = (New-Object Microsoft.Azure.Cosmos.Table.TableQuery).Where($verifyFilter)
$keepCount = 0
$token = $null
do {
    $seg = $table.ExecuteQuerySegmentedAsync($verifyQuery, $token).GetAwaiter().GetResult()
    $keepCount += $seg.Results.Count
    $token = $seg.ContinuationToken
} while ($null -ne $token)
Write-Host "Remaining rows in '$KeepPartitionKey': $keepCount" -ForegroundColor Cyan
