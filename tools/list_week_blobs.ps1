<#
.SYNOPSIS
    List all HTML report blobs in the results container for a specified YearWeek.

.DESCRIPTION
    Connects to the opswprodtoolsblob storage account and lists all blobs in the
    'results' container whose name matches the weekly report naming convention for
    the given YearWeek. Displays blob name, size in bytes, and last modified time.
    Useful for confirming that Build-WeeklyReports.ps1 produced output for a week.

.PARAMETER YearWeek
    The work week to filter by in YYYY-Www format (e.g. 2026-W26).

.USAGE
    .\tools\list_week_blobs.ps1 -YearWeek '2026-W26'
    .\tools\list_week_blobs.ps1 -YearWeek '2026-W27'
#>

param(
    [Parameter(Mandatory)]
    [string]$YearWeek
)

$rg = 'OPSW-Ticket-Analyzer'
$sa = 'opswprodtoolsblob'

# Connect to storage using the account key
$key = (Get-AzStorageAccountKey -ResourceGroupName $rg -Name $sa)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $sa -StorageAccountKey $key

# Filter blobs matching the standard weekly report naming convention for the requested week
$pattern = "ProductivityTools_Weekly_Report_${YearWeek}*"
$blobs   = Get-AzStorageBlob -Container results -Context $ctx |
           Where-Object { $_.Name -like $pattern }

if ($blobs.Count -gt 0) {
    foreach ($b in $blobs) {
        Write-Output ("$($b.Name) | $($b.Length) bytes | $($b.LastModified)")
    }
} else {
    Write-Output "No blobs found matching: $pattern"
}
