<#
.SYNOPSIS
    Look up one or more incident numbers in the IncidentsCategoryStats Azure Table
    and print the YearWeek partition each one belongs to.

.DESCRIPTION
    Queries the table by RowKey (incident number) using a SAS-token REST call.
    Useful for quickly confirming whether a specific incident was ingested
    and which week partition it was stored in.

.PARAMETER Incidents
    One or more incident numbers to look up (e.g. INC15588694).

.USAGE
    .\tools\find_incidents_in_table.ps1 -Incidents INC15588694
    .\tools\find_incidents_in_table.ps1 -Incidents INC15588694,INC15592984,INC15604999
#>

param([string[]]$Incidents)

$ResourceGroup  = 'OPSW-Ticket-Analyzer'
$StorageAccount = 'opswprodtoolsblob'
$table          = 'IncidentsCategoryStats'
# Get storage key and build a short-lived read-only SAS token for REST queries
$key  = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx  = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $key
$sas  = New-AzStorageTableSASToken -Name $table -Permission r -ExpiryTime (Get-Date).AddMinutes(15) -Protocol HttpsOnly -Context $ctx
$base = "https://$StorageAccount.table.core.windows.net/$table()?$sas"

foreach ($inc in $Incidents) {
    # Each RowKey is the incident number and is unique across all partitions
    $filter = "`$filter=RowKey eq '$inc'"
    $url    = $base + '&' + $filter + "&`$top=1000"
    try {
        $r    = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
        $vals = ($r.Content | ConvertFrom-Json).value
        if ($vals -and $vals.Count -gt 0) {
            # Print the YearWeek partition (PartitionKey) where this incident lives
            foreach ($v in $vals) {
                Write-Output "$inc -> PartitionKey=$($v.PartitionKey) | RowKey=$($v.RowKey)"
            }
        } else {
            Write-Output "$inc -> Not found in table"
        }
    } catch {
        $msg = $_.Exception.Message -replace '"', ''
        Write-Output ("Error querying for {0}: {1}" -f $inc, $msg)
    }
}
