$ErrorActionPreference = 'Stop'

$subId = '1c6d384e-bc83-4b02-859c-76eeb87f7676'
$rg = 'OPSW-Ticket-Analyzer'

Connect-AzAccount -Subscription $subId | Out-Null
Set-AzContext -Subscription $subId | Out-Null

$sa = Get-AzStorageAccount -ResourceGroupName $rg | Select-Object -First 1
if (-not $sa) { throw 'No storage account found in RG OPSW-Ticket-Analyzer' }

$key = (Get-AzStorageAccountKey -ResourceGroupName $rg -Name $sa.StorageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $sa.StorageAccountName -StorageAccountKey $key

Import-Module AzTable -Force
$table = Get-AzStorageTable -Name 'IncidentsCategoryStats' -Context $ctx -ErrorAction Stop
$rows = @(Get-AzTableRow -Table $table.CloudTable -PartitionKey '2026-W33')
Write-Host "WW33Rows=$($rows.Count)"

if ($rows.Count -gt 0) {
    $rows | Select-Object -First 5 `
        @{Name='RowKey';Expression={$_.RowKey}},
        @{Name='Category';Expression={$_.Category}},
        @{Name='Subcategory';Expression={$_.Subcategory}},
        @{Name='Preview';Expression={ if ($_.AIAnalysis) { (($_.AIAnalysis -split "`r?`n" | Select-Object -First 5) -join ' | ') } else { '' } }} |
        Format-Table -AutoSize
}

$w33Blobs = @(Get-AzStorageBlob -Container 'results' -Context $ctx | Where-Object { $_.Name -like '*2026-W33*' -or $_.Name -like '*WW33*' })
Write-Host "ReportBlobs=$($w33Blobs.Count)"
if ($w33Blobs.Count -gt 0) {
    $w33Blobs | Select-Object -ExpandProperty Name | Sort-Object
}
