# Sets up CORS + read-only Table SAS for the Static Web App dashboard
$ErrorActionPreference = 'Stop'

$rg     = 'OPSW-Ticket-Analyzer'
$sa     = 'opswprodtoolsblob'
$origin = 'https://nice-wave-080119d1e.7.azurestaticapps.net'

$key = (Get-AzStorageAccountKey -ResourceGroupName $rg -Name $sa)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $sa -StorageAccountKey $key

$rules = @(@{
    AllowedOrigins  = @($origin)
    AllowedMethods  = @('GET','HEAD','OPTIONS')
    AllowedHeaders  = @('*')
    ExposedHeaders  = @('x-ms-*')
    MaxAgeInSeconds = 3600
})
Set-AzStorageCORSRule -ServiceType Table -CorsRules $rules -Context $ctx
Set-AzStorageCORSRule -ServiceType Blob  -CorsRules $rules -Context $ctx
Write-Host "CORS applied for $origin (Table + Blob)." -ForegroundColor Green

$tableSas = New-AzStorageTableSASToken -Name 'IncidentsCategoryStats' -Permission 'r' -ExpiryTime (Get-Date '2027-12-31T23:59:59Z') -Protocol HttpsOnly -Context $ctx
Write-Host "Table SAS (read-only):" -ForegroundColor Cyan
Write-Host $tableSas
