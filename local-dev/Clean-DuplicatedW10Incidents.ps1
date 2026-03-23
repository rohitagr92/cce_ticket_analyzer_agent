<#
.SYNOPSIS
    Cleans up W10 incidents that were duplicated into W11 in the IncidentsCategoryStats table.

.DESCRIPTION
    Finds all incident IDs that exist in BOTH 2026-W10 and 2026-W11 partitions,
    then deletes the W11 duplicates (keeping the original W10 records).
    
    Requires: Az.Storage module and authenticated Azure context.

.EXAMPLE
    # Dry run (default) - shows what would be deleted
    .\Clean-DuplicatedW10Incidents.ps1

    # Actually delete
    .\Clean-DuplicatedW10Incidents.ps1 -Execute
#>

[CmdletBinding()]
param(
    [switch]$Execute
)

$storageAccountName = "incidentsanalyzersa"
$resourceGroupName = "Incidents-analyzer-rg"
$tableName = "IncidentsCategoryStats"

Write-Host "Connecting to Azure Table Storage (using Az context)..." -ForegroundColor Cyan
$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
$storageContext = $storageAccount.Context
$cloudTable = (Get-AzStorageTable -Name $tableName -Context $storageContext).CloudTable

# Query all W10 records
Write-Host "Querying 2026-W10 partition..." -ForegroundColor Yellow
$w10Filter = [Microsoft.Azure.Cosmos.Table.TableQuery]::GenerateFilterCondition(
    "PartitionKey", 
    [Microsoft.Azure.Cosmos.Table.QueryComparisons]::Equal, 
    "2026-W10"
)
$w10Query = [Microsoft.Azure.Cosmos.Table.TableQuery]::new()
$w10Query.FilterString = $w10Filter
$w10Records = [Microsoft.Azure.Cosmos.Table.TableOperation]
$w10Records = $cloudTable.ExecuteQuery($w10Query)
$w10IncidentIds = @($w10Records | ForEach-Object { $_.RowKey })
Write-Host "  Found $($w10IncidentIds.Count) records in W10" -ForegroundColor White

# Query all W11 records
Write-Host "Querying 2026-W11 partition..." -ForegroundColor Yellow
$w11Filter = [Microsoft.Azure.Cosmos.Table.TableQuery]::GenerateFilterCondition(
    "PartitionKey", 
    [Microsoft.Azure.Cosmos.Table.QueryComparisons]::Equal, 
    "2026-W11"
)
$w11Query = [Microsoft.Azure.Cosmos.Table.TableQuery]::new()
$w11Query.FilterString = $w11Filter
$w11Records = $cloudTable.ExecuteQuery($w11Query)
$w11Incidents = @($w11Records)
Write-Host "  Found $($w11Incidents.Count) records in W11" -ForegroundColor White

# Find duplicates: incidents that exist in BOTH W10 and W11
$w10Set = [System.Collections.Generic.HashSet[string]]::new()
foreach ($id in $w10IncidentIds) { $w10Set.Add($id) | Out-Null }

$duplicates = @($w11Incidents | Where-Object { $w10Set.Contains($_.RowKey) })
$w11Only = @($w11Incidents | Where-Object { -not $w10Set.Contains($_.RowKey) })

Write-Host "`n== Analysis ==" -ForegroundColor Cyan
Write-Host "  W10 total records:          $($w10IncidentIds.Count)" -ForegroundColor White
Write-Host "  W11 total records:          $($w11Incidents.Count)" -ForegroundColor White
Write-Host "  W11 records ALSO in W10:    $($duplicates.Count)  <-- duplicates to remove" -ForegroundColor Red
Write-Host "  W11 records unique to W11:  $($w11Only.Count)  <-- will be kept" -ForegroundColor Green

if ($duplicates.Count -eq 0) {
    Write-Host "`nNo duplicates found. Nothing to clean up." -ForegroundColor Green
    exit 0
}

# Show sample of duplicates
Write-Host "`nSample duplicates (first 10):" -ForegroundColor Yellow
$duplicates | Select-Object -First 10 | ForEach-Object {
    Write-Host "  PartitionKey=2026-W11, RowKey=$($_.RowKey)" -ForegroundColor DarkGray
}
if ($duplicates.Count -gt 10) {
    Write-Host "  ... and $($duplicates.Count - 10) more" -ForegroundColor DarkGray
}

if (-not $Execute) {
    Write-Host "`n[DRY RUN] No changes made. Use -Execute to delete the $($duplicates.Count) duplicate records." -ForegroundColor Yellow
    exit 0
}

# Delete duplicate W11 records
Write-Host "`nDeleting $($duplicates.Count) duplicate W11 records..." -ForegroundColor Red
$deleted = 0
$failed = 0

foreach ($record in $duplicates) {
    try {
        $deleteOp = [Microsoft.Azure.Cosmos.Table.TableOperation]::Delete($record)
        $cloudTable.Execute($deleteOp) | Out-Null
        $deleted++
        
        if ($deleted % 50 -eq 0) {
            Write-Host "  Deleted $deleted / $($duplicates.Count)..." -ForegroundColor DarkGray
        }
    } catch {
        $failed++
        Write-Host "  Failed to delete $($record.RowKey): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n== Cleanup Complete ==" -ForegroundColor Cyan
Write-Host "  Deleted:  $deleted" -ForegroundColor Green
Write-Host "  Failed:   $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "  W11 remaining: $($w11Only.Count) (legitimate W11 records)" -ForegroundColor White
