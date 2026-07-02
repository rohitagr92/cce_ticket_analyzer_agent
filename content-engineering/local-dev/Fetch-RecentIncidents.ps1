<#
.SYNOPSIS
    Fetch recent resolved Content Engineering incidents from ServiceNow.

.PARAMETER Limit
    Number of incidents to fetch. Default 10.

.PARAMETER LookbackDays
    Only return incidents resolved within the last N days. Default 14.

.EXAMPLE
    .\Fetch-RecentIncidents.ps1
    .\Fetch-RecentIncidents.ps1 -Limit 5 -LookbackDays 7
#>
param(
    [int]$Limit       = 10,
    [int]$LookbackDays = 14
)

$ErrorActionPreference = 'Stop'

$configPath  = "$PSScriptRoot\..\config\LocalConfig-ContentEngineering.psd1"
$secretsPath = "$PSScriptRoot\..\config\LocalSecrets-ContentEngineering.psd1"

if (-not (Test-Path $configPath))  { throw "Config not found: $configPath" }
if (-not (Test-Path $secretsPath)) { throw "Secrets not found: $secretsPath" }

$config  = Import-PowerShellDataFile $configPath
$secrets = Import-PowerShellDataFile $secretsPath

if ([string]::IsNullOrWhiteSpace($secrets.ServiceNowClientSecret)) {
    throw "ServiceNowClientSecret is empty in LocalSecrets-ContentEngineering.psd1."
}

# ── OAuth token ────────────────────────────────────────────────────────────────
Write-Host "Acquiring OAuth token..." -ForegroundColor Cyan
$tokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $config.ServiceNowClientID
    client_secret = $secrets.ServiceNowClientSecret
    scope         = $config.ServiceNowScope
}
$tokenResponse = Invoke-RestMethod -Uri $config.TokenUrl -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
$token = $tokenResponse.access_token
Write-Host "Token acquired." -ForegroundColor Green

$headers = @{ Authorization = "Bearer $token" }

# ── Build date filter ──────────────────────────────────────────────────────────
$since = (Get-Date).AddDays(-$LookbackDays).ToString("yyyy-MM-dd")
$query = "business_service=$($config.BusinessServiceId)" +
         "^service_offering=$($config.ServiceOfferingId)" +
         "^stateIN6,7" +
         "^resolved_at>=$($since)" +
         "^ORDERBYDESCresolved_at"
$queryEnc = [uri]::EscapeDataString($query)

$url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$queryEnc&sysparm_display_value=true&sysparm_fields=number,short_description,category,subcategory,resolved_at,business_service,service_offering&sysparm_limit=$Limit"

# ── Fetch ──────────────────────────────────────────────────────────────────────
Write-Host "`nFetching up to $Limit Content Engineering incidents resolved in the last $LookbackDays days..." -ForegroundColor Cyan
$result = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop

if (-not $result.result -or $result.result.Count -eq 0) {
    Write-Host "`nNo Content Engineering incidents found in the last $LookbackDays days." -ForegroundColor Yellow
    Write-Host "Check: business_service and service_offering sys_ids in LocalConfig-ContentEngineering.psd1" -ForegroundColor Yellow
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
