$ErrorActionPreference = 'Stop'

$subId = '1c6d384e-bc83-4b02-859c-76eeb87f7676'
Connect-AzAccount -Subscription $subId | Out-Null
Set-AzContext -Subscription $subId | Out-Null

$rg = 'OPSW-Ticket-Analyzer'
$sa = Get-AzStorageAccount -ResourceGroupName $rg | Select-Object -First 1
$key = (Get-AzStorageAccountKey -ResourceGroupName $rg -Name $sa.StorageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $sa.StorageAccountName -StorageAccountKey $key
Import-Module AzTable -Force
$table = Get-AzStorageTable -Name 'IncidentsCategoryStats' -Context $ctx -ErrorAction Stop
$rows = @(Get-AzTableRow -Table $table.CloudTable -PartitionKey '2026-W33')
Write-Host "TotalWW33=$($rows.Count)"
$first = $rows | Select-Object -First 1
if ($first -and $first.AIAnalysis) {
    $text = $first.AIAnalysis
    Write-Host '---AIAnalysisPreview---'
    $text.Split("`r`n") | Select-Object -First 15 | ForEach-Object { Write-Host $_ }
}
else {
    Write-Host 'No AIAnalysis found on first row.'
}
