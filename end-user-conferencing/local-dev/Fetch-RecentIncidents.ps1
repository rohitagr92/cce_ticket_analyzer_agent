param(
    [ValidateSet('Messaging','Rooms')]
    [string]$Offering = 'Messaging',
    [int]$Limit = 10,
    [int]$LookbackDays = 14
)

$ErrorActionPreference = 'Stop'

$configPath  = Join-Path $PSScriptRoot '..\config\LocalConfig-EndUserConferencing.psd1'
$secretsPath = Join-Path $PSScriptRoot '..\config\LocalSecrets-EndUserConferencing.psd1'

if (-not (Test-Path $configPath))  { throw "Config not found: $configPath" }
if (-not (Test-Path $secretsPath)) { throw "Secrets not found: $secretsPath" }

$config  = Import-PowerShellDataFile $configPath
$secrets = Import-PowerShellDataFile $secretsPath

if ([string]::IsNullOrWhiteSpace($secrets.ServiceNowClientSecret) -or $secrets.ServiceNowClientSecret.StartsWith('<paste')) {
    throw "ServiceNowClientSecret is empty in LocalSecrets-EndUserConferencing.psd1."
}

$serviceOfferingId = switch ($Offering) {
    'Messaging' { $config.MessagingServiceOfferingId }
    'Rooms' { $config.RoomsServiceOfferingId }
}

if ([string]::IsNullOrWhiteSpace($serviceOfferingId) -or $serviceOfferingId.StartsWith('<fill-in')) {
    throw "Service offering sys_id is not set for $Offering in LocalConfig-EndUserConferencing.psd1."
}

Write-Host "Acquiring OAuth token..." -ForegroundColor Cyan
$tokenBody = @{
    grant_type    = 'client_credentials'
    client_id     = $config.ServiceNowClientID
    client_secret = $secrets.ServiceNowClientSecret
    scope         = $config.ServiceNowScope
}
$tokenResponse = Invoke-RestMethod -Uri $config.TokenUrl -Method Post -Body $tokenBody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
$token = [string]$tokenResponse.access_token
Write-Host "Token acquired." -ForegroundColor Green

$headers = @{ Authorization = "Bearer $token" }
$since = (Get-Date).AddDays(-$LookbackDays).ToString('yyyy-MM-dd')
$query = "business_service=$($config.BusinessServiceId)^service_offering=$serviceOfferingId^stateIN6,7^resolved_at>=$since^ORDERBYDESCresolved_at"
$queryEnc = [uri]::EscapeDataString($query)

$url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$queryEnc&sysparm_display_value=true&sysparm_fields=number,short_description,category,subcategory,resolved_at,business_service,service_offering&sysparm_limit=$Limit"

Write-Host "`nFetching up to $Limit $Offering incidents resolved in the last $LookbackDays days..." -ForegroundColor Cyan
$result = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop

if (-not $result.result -or $result.result.Count -eq 0) {
    Write-Host "`nNo $Offering incidents found in the last $LookbackDays days." -ForegroundColor Yellow
    Write-Host "Check: business_service and service_offering sys_ids in LocalConfig-EndUserConferencing.psd1" -ForegroundColor Yellow
    exit 0
}

$incidents = $result.result
Write-Host "`nFound $($incidents.Count) incident(s):`n" -ForegroundColor Green

$incidents | ForEach-Object {
    Write-Host "  $($_.number)  |  $($_.resolved_at.Substring(0,10))  |  $($_.category) / $($_.subcategory)" -ForegroundColor White
    Write-Host "             $($_.short_description)" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "Service Offering verified: $($incidents[0].service_offering)" -ForegroundColor Cyan
Write-Host "Business Service verified: $($incidents[0].business_service)" -ForegroundColor Cyan