<#
.SYNOPSIS
    Print all stored properties of a single row from the IncidentsCategoryStats
    Azure Table for quick inspection.

.DESCRIPTION
    Retrieves all rows for the specified YearWeek partition and displays the
    full property set (Category, Subcategory, RootCause, AIAnalysis, Confidence,
    Date, YearWeek, etc.) of a single row by index. Useful for verifying that
    the correct values were written after a correction or backfill run.

.PARAMETER Partition
    The YearWeek partition to query (e.g. 2026-W26). Defaults to the current WW26.

.PARAMETER Index
    Zero-based index of the row to display within the partition. Defaults to 0.

.USAGE
    .\tools\inspect_one_entity.ps1 -Partition '2026-W26'
    .\tools\inspect_one_entity.ps1 -Partition '2026-W27' -Index 3
#>

param(
    [string]$Partition = '2026-W26',
    [int]$Index = 0
)

# Connect using the currently logged-in Azure account (no storage key required)
$ctx  = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -UseConnectedAccount
$tbl  = (Get-AzStorageTable -Name 'IncidentsCategoryStats' -Context $ctx).CloudTable

# Fetch all rows in the partition and select the one at the requested index
$rows = Get-AzTableRow -Table $tbl -CustomFilter ("PartitionKey eq '{0}'" -f $Partition)
if ($rows.Count -le $Index) {
    Write-Host "Not enough rows -- partition '$Partition' has $($rows.Count) row(s), index $Index requested." -ForegroundColor Red
    exit 1
}

# Display the row key and every property stored on this entity
$r = $rows[$Index]
Write-Host "RowKey: $($r.RowKey)" -ForegroundColor Cyan
Write-Host "Properties:"
$r.PSObject.Properties | ForEach-Object {
    Write-Host "  $($_.Name) : $($_.Value -as [string] -replace '\r\n', '\n')"
}
