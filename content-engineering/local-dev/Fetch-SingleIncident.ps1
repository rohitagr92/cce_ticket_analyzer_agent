<#
.SYNOPSIS
    Fetch a single Content Engineering incident by number from ServiceNow.

.PARAMETER IncidentNumber
    The INC number to fetch. Defaults to a recent resolved incident.

.EXAMPLE
    .\Fetch-SingleIncident.ps1
    .\Fetch-SingleIncident.ps1 -IncidentNumber INC15600000
#>
param(
    [string]$IncidentNumber = ""
)

$ErrorActionPreference = 'Stop'

$configPath  = "$PSScriptRoot\..\config\LocalConfig-ContentEngineering.psd1"
$secretsPath = "$PSScriptRoot\..\config\LocalSecrets-ContentEngineering.psd1"

if (-not (Test-Path $configPath))  { throw "Config not found: $configPath" }
if (-not (Test-Path $secretsPath)) { throw "Secrets not found: $secretsPath. Copy LocalSecrets-ContentEngineering.psd1 and fill in ServiceNowClientSecret." }

$config  = Import-PowerShellDataFile $configPath
$secrets = Import-PowerShellDataFile $secretsPath

if ([string]::IsNullOrWhiteSpace($secrets.ServiceNowClientSecret)) {
    throw "ServiceNowClientSecret is empty in LocalSecrets-ContentEngineering.psd1. Add the secret and retry."
}

# ── Acquire OAuth token ────────────────────────────────────────────────────────
Write-Host "Acquiring OAuth token..." -ForegroundColor Cyan
$tokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $config.ServiceNowClientID
    client_secret = $secrets.ServiceNowClientSecret
    scope         = $config.ServiceNowScope
}
$tokenResponse = Invoke-RestMethod -Uri $config.TokenUrl -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
$token = $tokenResponse.access_token
Write-Host "Token acquired ($($token.Length) chars)" -ForegroundColor Green

$headers = @{ Authorization = "Bearer $token" }
$fields  = "number,short_description,description,cause,close_notes,category,subcategory,state,opened_at,resolved_at,work_notes,business_service,service_offering"

# ── If no incident number given, find the most recent CE-scoped one ────────────
if ([string]::IsNullOrWhiteSpace($IncidentNumber)) {
    Write-Host "No incident number given — fetching the most recent Content Engineering incident..." -ForegroundColor Yellow
    $listUrl = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=business_service=$($config.BusinessServiceId)^service_offering=$($config.ServiceOfferingId)^stateIN6,7^ORDERBYDESCresolved_at&sysparm_display_value=true&sysparm_fields=number,short_description,resolved_at&sysparm_limit=1"
    $listResult = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ErrorAction Stop

    if (-not $listResult.result -or $listResult.result.Count -eq 0) {
        Write-Host "No resolved Content Engineering incidents found. Check business_service/service_offering sys_ids." -ForegroundColor Red
        exit 1
    }
    $IncidentNumber = $listResult.result[0].number
    Write-Host "Most recent CE incident: $IncidentNumber (resolved $($listResult.result[0].resolved_at))" -ForegroundColor Green
}

# ── Fetch full incident detail ─────────────────────────────────────────────────
Write-Host "`nFetching $IncidentNumber..." -ForegroundColor Cyan
$incUrl = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=number=$IncidentNumber&sysparm_display_value=true&sysparm_fields=$fields&sysparm_limit=1"
$result = Invoke-RestMethod -Uri $incUrl -Headers $headers -Method Get -ErrorAction Stop

if (-not $result.result -or $result.result.Count -eq 0) {
    Write-Host "Incident $IncidentNumber not found in ServiceNow." -ForegroundColor Red
    exit 1
}

$inc = $result.result[0]

# ── Display ───────────────────────────────────────────────────────────────────
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
