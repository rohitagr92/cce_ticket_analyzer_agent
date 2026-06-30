<#
.SYNOPSIS
    List all unique YearWeek partition keys present in the IncidentsCategoryStats
    Azure Table, sorted alphabetically.

.DESCRIPTION
    Uses a SAS-token REST call with continuation-token support to enumerate every
    distinct PartitionKey in the table. Safe read-only operation — no data modified.
    Useful for auditing which weeks have data and spotting coverage gaps.

.USAGE
    .\tools\list_table_partitions.ps1
#>

$ResourceGroup  = 'OPSW-Ticket-Analyzer'
$StorageAccount = 'opswprodtoolsblob'

# Get storage key and build a short-lived read-only SAS token
$key  = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx  = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $key
$sas  = New-AzStorageTableSASToken -Name 'IncidentsCategoryStats' -Permission 'r' -ExpiryTime (Get-Date).AddMinutes(15) -Protocol HttpsOnly -Context $ctx
$base = "https://$StorageAccount.table.core.windows.net/IncidentsCategoryStats()?$sas"

# Request only the PartitionKey column to minimize response payload
$url        = $base + "&`$select=PartitionKey&`$top=1000"
$partitions = @()

# Page through all results — the table may span many continuation pages
while ($url) {
    $r          = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
    $vals       = ($r.Content | ConvertFrom-Json).value
    $partitions += ($vals | ForEach-Object { $_.PartitionKey })

    # Follow continuation tokens if more pages remain
    $npk = $r.Headers['x-ms-continuation-NextPartitionKey']
    $nrk = $r.Headers['x-ms-continuation-NextRowKey']
    if ($npk) {
        $url = $base + "?`$select=PartitionKey&NextPartitionKey=" + [Uri]::EscapeDataString([string]$npk)
        if ($nrk) { $url += '&NextRowKey=' + [Uri]::EscapeDataString([string]$nrk) }
    } else {
        $url = $null
    }
}

# Deduplicate and sort — each incident row shares the same PartitionKey within a week
$partitions | Sort-Object -Unique | ForEach-Object { Write-Output $_ }
