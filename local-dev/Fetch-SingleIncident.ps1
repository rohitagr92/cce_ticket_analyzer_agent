param([string]$IncidentNumber = "INC15548712")

$config  = Import-PowerShellDataFile "$PSScriptRoot\..\config\LocalConfig-ProductivityTools.psd1"
$secrets = Import-PowerShellDataFile "$PSScriptRoot\..\config\LocalSecrets-ProductivityTools.psd1"

# Get OAuth token
$tokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $config.ServiceNowIncidentsClientID
    client_secret = $secrets.ServiceNowIncidentsClientSecret
    scope         = $config.ServiceNowIncidentsScope
}
$tokenResponse = Invoke-RestMethod -Uri $config.TokenUrl -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
$token = $tokenResponse.access_token
Write-Host "Token acquired ($($token.Length) chars)" -ForegroundColor Green

# Fetch incident by number
$fields = "number,short_description,description,cause,close_notes,category,subcategory,state,opened_at,resolved_at,work_notes,comments"
$incidentUrl = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=number=$IncidentNumber&sysparm_display_value=true&sysparm_fields=$fields&sysparm_limit=1"
$headers = @{ Authorization = "Bearer $token" }
$result = Invoke-RestMethod -Uri $incidentUrl -Headers $headers -Method Get

if (-not $result.result -or $result.result.Count -eq 0) {
    Write-Host "No incident found for $IncidentNumber" -ForegroundColor Red
    exit 1
}

$inc = $result.result[0]
Write-Host ""
Write-Host "===== INCIDENT: $($inc.number) =====" -ForegroundColor Cyan
Write-Host "Short Description : $($inc.short_description)"
Write-Host "State             : $($inc.state)"
Write-Host "Category          : $($inc.category)"
Write-Host "Subcategory       : $($inc.subcategory)"
Write-Host "Opened At         : $($inc.opened_at)"
Write-Host "Resolved At       : $($inc.resolved_at)"
Write-Host ""
Write-Host "--- SYMPTOM (Description) ---" -ForegroundColor Yellow
Write-Host $inc.description
Write-Host ""
Write-Host "--- ROOT CAUSE (Cause field) ---" -ForegroundColor Yellow
Write-Host $inc.cause
Write-Host ""
Write-Host "--- CLOSE NOTES (Resolution / AI Analysis) ---" -ForegroundColor Yellow
Write-Host $inc.close_notes
Write-Host ""
Write-Host "--- WORK NOTES ---" -ForegroundColor DarkGray
Write-Host $inc.work_notes
