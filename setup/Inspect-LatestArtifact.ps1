$key = (Get-AzStorageAccountKey -ResourceGroupName 'OPSW-Ticket-Analyzer' -Name 'opswprodtoolsblob')[0].Value
$ctx = New-AzStorageContext -StorageAccountName 'opswprodtoolsblob' -StorageAccountKey $key
$latest = Get-AzStorageBlob -Container 'data' -Context $ctx -Prefix 'run_artifact_' | Sort-Object LastModified -Descending | Select-Object -First 1
Write-Host "Latest artifact: $($latest.Name) ($($latest.LastModified.UtcDateTime) UTC)" -ForegroundColor Cyan
$tmp = [IO.Path]::GetTempFileName()
Get-AzStorageBlobContent -Container 'data' -Blob $latest.Name -Destination $tmp -Context $ctx -Force | Out-Null
$art = Get-Content $tmp -Raw | ConvertFrom-Json
Remove-Item $tmp -Force
Write-Host "ProcessedTickets count: $($art.ProcessedTickets.Count)"
$sample = $art.ProcessedTickets | Select-Object -First 3
foreach ($t in $sample) {
    Write-Host "`n--- $($t.Number) ---" -ForegroundColor Yellow
    Write-Host "Category:         $($t.Category)"
    Write-Host "SubSymptom:       $($t.SubSymptom)"
    Write-Host "Subcategory:      $($t.Subcategory)"
    Write-Host "PossibleRootCause:$($t.PossibleRootCause)"
    Write-Host "DetailedRootCause:$($t.DetailedRootCause)"
    Write-Host "Service:          $($t.Service)"
    Write-Host "Reasoning:        $($t.Reasoning)"
}
