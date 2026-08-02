param(
    [ValidateSet('Messaging','Rooms')]
    [string]$Offering = 'Messaging',
    [string]$IncidentNumber = "",
    [string]$IncidentSysId = "",
    [string]$IncidentUrl = ""
)

$ErrorActionPreference = 'Stop'

$configPath  = Join-Path $PSScriptRoot '..\config\LocalConfig-EndUserConferencing.psd1'
$secretsPath = Join-Path $PSScriptRoot '..\config\LocalSecrets-EndUserConferencing.psd1'

if (-not (Test-Path $configPath))  { throw "Config not found: $configPath" }
if (-not (Test-Path $secretsPath)) { throw "Secrets not found: $secretsPath. Copy LocalSecrets-EndUserConferencing.psd1 and fill in ServiceNowClientSecret." }

$config  = Import-PowerShellDataFile $configPath
$secrets = Import-PowerShellDataFile $secretsPath

if ([string]::IsNullOrWhiteSpace($config.ServiceNowClientID) -or $config.ServiceNowClientID.StartsWith('<fill-in')) {
    throw "ServiceNowClientID is not set in LocalConfig-EndUserConferencing.psd1."
}

if ([string]::IsNullOrWhiteSpace($secrets.ServiceNowClientSecret) -or $secrets.ServiceNowClientSecret.StartsWith('<paste')) {
    throw "ServiceNowClientSecret is empty in LocalSecrets-EndUserConferencing.psd1. Add the secret and retry."
}

$serviceOfferingId = switch ($Offering) {
    'Messaging' { $config.MessagingServiceOfferingId }
    'Rooms' { $config.RoomsServiceOfferingId }
}

if (-not [string]::IsNullOrWhiteSpace($IncidentUrl) -and [string]::IsNullOrWhiteSpace($IncidentSysId)) {
    $match = [regex]::Match($IncidentUrl, 'sys_id=([0-9a-f]{32})', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        $IncidentSysId = $match.Groups[1].Value
    }
}

if ([string]::IsNullOrWhiteSpace($config.BusinessServiceId) -or $config.BusinessServiceId.StartsWith('<fill-in')) {
    if ([string]::IsNullOrWhiteSpace($IncidentSysId)) {
        throw "BusinessServiceId is not set in LocalConfig-EndUserConferencing.psd1 and no IncidentSysId was provided."
    }
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
Write-Host "Token acquired ($($token.Length) chars)" -ForegroundColor Green

$headers = @{ Authorization = "Bearer $token" }
$fields  = 'number,short_description,description,cause,close_notes,category,subcategory,state,opened_at,resolved_at,work_notes,business_service,service_offering'

if ([string]::IsNullOrWhiteSpace($IncidentNumber) -and [string]::IsNullOrWhiteSpace($IncidentSysId)) {
    Write-Host "No incident number given - fetching the most recent $Offering incident..." -ForegroundColor Yellow
    $listQuery = "business_service=$($config.BusinessServiceId)^service_offering=$serviceOfferingId^stateIN6,7^ORDERBYDESCresolved_at"
    $listUrl = 'https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=' + [uri]::EscapeDataString($listQuery) + '&sysparm_display_value=true&sysparm_fields=number,short_description,resolved_at&sysparm_limit=1'
    $listResult = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ErrorAction Stop

    if (-not $listResult.result -or $listResult.result.Count -eq 0) {
        Write-Host "No resolved $Offering incidents found. Check business_service/service_offering sys_ids." -ForegroundColor Red
        exit 1
    }

    $IncidentNumber = $listResult.result[0].number
    Write-Host "Most recent $Offering incident: $IncidentNumber (resolved $($listResult.result[0].resolved_at))" -ForegroundColor Green
}

if (-not [string]::IsNullOrWhiteSpace($IncidentSysId)) {
    Write-Host "`nFetching incident sys_id $IncidentSysId..." -ForegroundColor Cyan
} else {
    Write-Host "`nFetching $IncidentNumber..." -ForegroundColor Cyan
}

$incQuery = if (-not [string]::IsNullOrWhiteSpace($IncidentSysId)) { "sys_id=$IncidentSysId" } else { "number=$IncidentNumber" }
$incUrl = 'https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=' + [uri]::EscapeDataString($incQuery) + '&sysparm_display_value=true&sysparm_fields=' + [uri]::EscapeDataString($fields) + '&sysparm_limit=1'
$result = Invoke-RestMethod -Uri $incUrl -Headers $headers -Method Get -ErrorAction Stop

if (-not $result.result -or $result.result.Count -eq 0) {
    Write-Host "Incident $IncidentNumber not found in ServiceNow." -ForegroundColor Red
    exit 1
}

$inc = $result.result[0]

Write-Host ""
Write-Host "===== INCIDENT: $($inc.number) =====" -ForegroundColor Cyan
Write-Host "Short Description  : $($inc.short_description)"
Write-Host "State              : $($inc.state)"
Write-Host "Category           : $($inc.category)"
Write-Host "Subcategory        : $($inc.subcategory)"
Write-Host "Business Service   : $($inc.business_service)"
Write-Host "Service Offering   : $($inc.service_offering)"
Write-Host "Opened At          : $($inc.opened_at)"
Write-Host "Resolved At        : $($inc.resolved_at)"
Write-Host ""
Write-Host "--- DESCRIPTION ---" -ForegroundColor Yellow
Write-Host $inc.description
Write-Host ""
Write-Host "--- CAUSE ---" -ForegroundColor Yellow
Write-Host $inc.cause
Write-Host ""
Write-Host "--- CLOSE NOTES ---" -ForegroundColor Yellow
Write-Host $inc.close_notes
Write-Host ""
Write-Host "--- WORK NOTES ---" -ForegroundColor DarkGray
Write-Host $inc.work_notes
Write-Host ""
Write-Host "Done." -ForegroundColor Green