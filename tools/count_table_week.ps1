<#
.SYNOPSIS
    Count the number of incident rows stored in a given YearWeek partition
    of the IncidentsCategoryStats Azure Table.

.DESCRIPTION
    Uses a SAS-token REST call with continuation-token support to count all rows
    in the specified partition. Safe read-only operation — no data is modified.
    Useful for quickly verifying whether the table count matches ServiceNow.

.PARAMETER YearWeek
    Target week partition in YYYY-Www format (e.g. 2026-W26).

.USAGE
    .\tools\count_table_week.ps1 -YearWeek '2026-W26'
    .\tools\count_table_week.ps1 -YearWeek '2026-W27'
#>

param(
    [Parameter(Mandatory)]
    [string]$YearWeek
)

$ResourceGroup  = 'OPSW-Ticket-Analyzer'
$StorageAccount = 'opswprodtoolsblob'
$table          = 'IncidentsCategoryStats'
# Get storage key and build a short-lived read-only SAS token for REST queries
$key    = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx    = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $key
$sas    = New-AzStorageTableSASToken -Name $table -Permission r -ExpiryTime (Get-Date).AddMinutes(15) -Protocol HttpsOnly -Context $ctx
$base   = "https://$StorageAccount.table.core.windows.net/$table()?$sas"

# Filter to only rows in the requested YearWeek partition
$filter = "`$filter=PartitionKey eq '$YearWeek'"
$url    = $base + '&' + $filter + "&`$top=1000"
$count  = 0

# Page through results using continuation tokens (Azure Table pages at 1000 rows max)
while ($url) {
    $r    = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
    $vals = ($r.Content | ConvertFrom-Json).value
    if ($vals) { $count += $vals.Count }

    # Follow continuation tokens if the result set spans multiple pages
    $npk = $r.Headers['x-ms-continuation-NextPartitionKey']
    $nrk = $r.Headers['x-ms-continuation-NextRowKey']
    if ($npk) {
        $url = $base + '&' + $filter + '&NextPartitionKey=' + [Uri]::EscapeDataString([string]$npk)
        if ($nrk) { $url += '&NextRowKey=' + [Uri]::EscapeDataString([string]$nrk) }
    } else {
        $url = $null
    }
}

Write-Output "$YearWeek rows: $count"
