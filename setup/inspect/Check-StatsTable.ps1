$ErrorActionPreference = 'Stop'
$key = (Get-AzStorageAccountKey -ResourceGroupName 'OPSW-Ticket-Analyzer' -Name 'opswprodtoolsblob')[0].Value
$ctx = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -StorageAccountKey $key
$sas = New-AzStorageTableSASToken -Name 'IncidentsCategoryStats' -Permission 'r' -ExpiryTime (Get-Date).AddMinutes(10) -Protocol HttpsOnly -Context $ctx

$base = "https://opswprodtoolsblob.table.core.windows.net/IncidentsCategoryStats()?$sas"
$all = @()
$url = $base
while ($url) {
    $resp = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
    $all += ($resp.Content | ConvertFrom-Json).value
    $npk = $resp.Headers['x-ms-continuation-NextPartitionKey']
    $nrk = $resp.Headers['x-ms-continuation-NextRowKey']
    if ($npk) {
        $url = $base + '&NextPartitionKey=' + [Uri]::EscapeDataString([string]$npk)
        if ($nrk) { $url += '&NextRowKey=' + [Uri]::EscapeDataString([string]$nrk) }
    }
    else { $url = $null }
}
Write-Host "Total rows: $($all.Count)" -ForegroundColor Green
Write-Host "`nBy week:"
$all | Group-Object PartitionKey | Sort-Object Name | ForEach-Object { '  {0}  {1,3} incidents' -f $_.Name, $_.Count }
Write-Host "`nTop categories (latest week 2026-W22):"
$all | Where-Object PartitionKey -eq '2026-W22' | Group-Object Category | Sort-Object Count -Descending | Select-Object Name, Count | Format-Table -AutoSize
