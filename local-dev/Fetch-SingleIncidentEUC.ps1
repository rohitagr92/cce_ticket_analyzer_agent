param([string]$IncidentNumber = 'INC15646264')

$cfg = Import-PowerShellDataFile -Path (Resolve-Path 'end-user-conferencing\config\LocalConfig-EndUserConferencing.psd1').Path

$clientId     = $cfg['ServiceNowClientID']
$tokenUrl     = $cfg['TokenUrl']
$scope        = $cfg['ServiceNowScope']
$clientSecret = $env:SERVICENOW_CLIENT_SECRET

if (-not $clientSecret) { throw 'Set env SERVICENOW_CLIENT_SECRET first.' }

Write-Host "Acquiring token..."
$tokenResp = Invoke-RestMethod -Method Post -Uri $tokenUrl `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ grant_type='client_credentials'; client_id=$clientId; client_secret=$clientSecret; scope=$scope } `
    -TimeoutSec 60

$headers = @{ Authorization = "Bearer $($tokenResp.access_token)"; Accept = 'application/json' }

$url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=number=$IncidentNumber&sysparm_display_value=true"
Write-Host "Fetching $IncidentNumber ..."
$resp = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -TimeoutSec 60

if (-not $resp.result -or $resp.result.Count -eq 0) { Write-Host "Incident not found."; exit }

$inc = $resp.result[0]
Write-Host ""
Write-Host "=== Field dump for $IncidentNumber ==="
$inc.PSObject.Properties | Sort-Object Name | ForEach-Object {
    $val = $_.Value
    $disp = if ($null -eq $val) { '<null>' } elseif ($val -is [string]) { $val.Substring(0, [Math]::Min(120, $val.Length)) } else { if ($val.PSObject.Properties['display_value']) { $val.display_value } else { [string]$val } }
    Write-Host ("  {0,-35} = {1}" -f $_.Name, $disp)
}
