param([string]$Pk)

$ErrorActionPreference = 'Stop'
$key = (Get-AzStorageAccountKey -ResourceGroupName 'OPSW-Ticket-Analyzer' -Name 'opswticketanal0571255553')[0].Value
$ctx = New-AzStorageContext -StorageAccountName 'opswticketanal0571255553' -StorageAccountKey $key
$tables = Get-AzStorageTable -Context $ctx
Write-Host "Tables in opswticketanal0571255553:"
$tables | Select-Object Name | Format-Table -AutoSize

$tableName = $tables | Where-Object { $_.Name -like '*Stat*' -or $_.Name -like '*Incident*' -or $_.Name -like '*Category*' } | Select-Object -First 1 -ExpandProperty Name
if (-not $tableName) {
    Write-Host "No stats table found. All tables shown above." -ForegroundColor Yellow
    return
}
Write-Host "Using table: $tableName"
$tbl = (Get-AzStorageTable -Name $tableName -Context $ctx).CloudTable

if (-not $Pk) {
    Write-Host "--- All partitions ---"
    $all = Get-AzTableRow -Table $tbl
    Write-Host "Total rows: $($all.Count)"
    $all | Group-Object PartitionKey | Sort-Object Name -Descending | Select-Object -First 8 | Format-Table Name, Count -AutoSize
    return
}

$rows = Get-AzTableRow -Table $tbl -PartitionKey $Pk
$withAI = ($rows | Where-Object { $_.AIAnalysis -and $_.AIAnalysis.Length -gt 0 }).Count
$withConf = ($rows | Where-Object { $_.Confidence -and $_.Confidence.ToString().Length -gt 0 }).Count
Write-Host "Partition $Pk : Total=$($rows.Count)  WithAIAnalysis=$withAI  WithConfidence=$withConf"
$rows | Sort-Object RowKey | Select-Object -First 6 RowKey, Category, Confidence, @{n='AILen';e={ if($_.AIAnalysis){$_.AIAnalysis.Length}else{0} }}, Date | Format-Table -AutoSize
