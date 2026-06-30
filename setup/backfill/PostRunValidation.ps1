param([string]$YearWeek)
if (-not $YearWeek) { Write-Host 'Usage: .\PostRunValidation.ps1 -YearWeek 2026-W26'; exit 1 }
$ResourceGroup = 'OPSW-Ticket-Analyzer'
$StorageAccount = 'opswprodtoolsblob'
$table = 'IncidentsCategoryStats'
$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $key
$sas = New-AzStorageTableSASToken -Name $table -Permission r -ExpiryTime (Get-Date).AddMinutes(15) -Protocol HttpsOnly -Context $ctx
$base = "https://$StorageAccount.table.core.windows.net/$table()?$sas"
$filter = "`$filter=PartitionKey eq '$YearWeek'"
$url = $base + '&' + $filter + "&`$top=1"
$r = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
$vals = ($r.Content | ConvertFrom-Json).value
$count = 0
if ($vals) { $count = $vals.Count }
Write-Host "Partition $YearWeek row count: $count"
if ($count -eq 0) {
    Write-Host "No rows found for $YearWeek — running Backfill-TrendData for last 10 days to populate." -ForegroundColor Yellow
    & .\Backfill-TrendData.ps1 -Days 10
} else { Write-Host "Partition $YearWeek has $count rows. No action needed." -ForegroundColor Green }
