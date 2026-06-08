param([string]$Pk = '2026-W24')

$ErrorActionPreference = 'Stop'
$key = (Get-AzStorageAccountKey -ResourceGroupName 'OPSW-Ticket-Analyzer' -Name 'opswprodtoolsblob')[0].Value
$ctx = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -StorageAccountKey $key
$tbl = (Get-AzStorageTable -Name 'IncidentsCategoryStats' -Context $ctx).CloudTable
$rows = Get-AzTableRow -Table $tbl -CustomFilter ("PartitionKey eq '{0}'" -f $Pk)
Write-Host "Partition $Pk total rows: $($rows.Count)"
$withAI = ($rows | Where-Object { $_.AIAnalysis -and $_.AIAnalysis.Length -gt 0 }).Count
$withConf = ($rows | Where-Object { $_.Confidence -and $_.Confidence.ToString().Length -gt 0 }).Count
Write-Host "  Rows with AIAnalysis populated: $withAI"
Write-Host "  Rows with Confidence populated: $withConf"
Write-Host ""
$rows | Sort-Object RowKey | Select-Object RowKey,Category,PossibleRootCause,Confidence,@{n='AILen';e={ if($_.AIAnalysis){$_.AIAnalysis.Length}else{0} }},@{n='Timestamp';e={ $_.TableTimestamp }} | Format-Table -AutoSize
