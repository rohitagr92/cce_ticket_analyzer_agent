param(
    [string]$StorageAccountName = 'opswprodtoolsblob',
    [string]$ResourceGroupName  = 'OPSW-Ticket-Analyzer',
    [string]$TableName          = 'IncidentsCategoryStats'
)

$ErrorActionPreference = 'Continue'

Import-Module AzTable
$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $key
$table = (Get-AzStorageTable -Name $TableName -Context $ctx).CloudTable

$weeks = 19..27 | ForEach-Object { "2026-W{0:D2}" -f $_ }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$summaryLog = Join-Path $repoRoot 'setup\archive\backups\ww19-27-refill-summary2.log'

"=== WW19-27 erase+refill attempt #2 started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $summaryLog -Append -Encoding utf8

foreach ($wk in $weeks) {
    Write-Host "`n##### $wk : deleting existing rows #####" -ForegroundColor Magenta
    $rows = Get-AzTableRow -Table $table -PartitionKey $wk
    $rowCount = ($rows | Measure-Object).Count
    foreach ($row in $rows) {
        Remove-AzTableRow -Table $table -partitionKey $row.PartitionKey -rowKey $row.RowKey | Out-Null
    }
    $verify = Get-AzTableRow -Table $table -PartitionKey $wk
    $verifyCount = ($verify | Measure-Object).Count
    "Deleted $rowCount rows for $wk at $(Get-Date -Format 'HH:mm:ss'); remaining after delete: $verifyCount" | Out-File -FilePath $summaryLog -Append -Encoding utf8

    Write-Host "##### $wk : backfilling #####" -ForegroundColor Cyan
    & (Join-Path $repoRoot 'setup\backfill\Backfill-WeekData.ps1') -YearWeek $wk
    "Backfill invocation for $wk finished at $(Get-Date -Format 'HH:mm:ss')" | Out-File -FilePath $summaryLog -Append -Encoding utf8
}

"=== WW19-27 erase+refill attempt #2 ALL DONE $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $summaryLog -Append -Encoding utf8
