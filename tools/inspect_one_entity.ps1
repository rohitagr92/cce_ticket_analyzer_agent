param([string]$Partition='2026-W23',[int]$Index=0)
$ctx = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -UseConnectedAccount
$tbl = (Get-AzStorageTable -Name 'IncidentsCategoryStats' -Context $ctx).CloudTable
$rows = Get-AzTableRow -Table $tbl -CustomFilter ("PartitionKey eq '{0}'" -f $Partition)
if ($rows.Count -le $Index) { Write-Host 'Not enough rows'; exit }
$r = $rows[$Index]
Write-Host "RowKey: $($r.RowKey)"
Write-Host "Properties:"
$r.PSObject.Properties | ForEach-Object { Write-Host "  $($_.Name) : $($_.Value -as [string] -replace "`r`n","\n" )" }
