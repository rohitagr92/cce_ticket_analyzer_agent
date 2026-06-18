<#
.SYNOPSIS
    Pulls Productivity Tools incidents for an ISO week (Mon-Sun) from ServiceNow,
    Resolved (6) + Closed (7) by resolved_at. Writes CSV + console list for cross-check.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$YearWeek,
    [string]$BusinessServiceId = 'a1de2ff2db8f50108062531dd3961911',
    [string]$ServiceOfferingId = 'fcb18407dbcf50108062531dd39619c4',
    [string]$ConfigPath  = "$PSScriptRoot\..\config\LocalConfig-ProductivityTools.psd1",
    [string]$SecretsPath = "$PSScriptRoot\..\config\LocalSecrets-ProductivityTools.psd1",
    [string]$OutDir      = "$PSScriptRoot\..\local-output\week-crosscheck"
)

$ErrorActionPreference = 'Stop'

$cfg = Import-PowerShellDataFile -Path $ConfigPath
$sec = Import-PowerShellDataFile -Path $SecretsPath
foreach ($k in $sec.Keys) { $cfg[$k] = $sec[$k] }

if ($YearWeek -notmatch '^(?<y>\d{4})-W(?<w>\d{1,2})$') { throw "Invalid YearWeek: $YearWeek" }
$year = [int]$Matches.y; $wk = [int]$Matches.w
# US work week (Intel convention): Sunday-Saturday.
# Anchor: WW1 contains Jan 1. Week starts on the Sunday on/before Jan 1.
$jan1 = (Get-Date -Year $year -Month 1 -Day 1).Date
$dow  = [int]$jan1.DayOfWeek   # Sunday = 0 .. Saturday = 6
$week1Sun  = $jan1.AddDays(-1 * $dow)
$weekStart = $week1Sun.AddDays(($wk - 1) * 7)            # Sun 00:00 IST (local day)
$weekEnd   = $weekStart.AddDays(7).AddSeconds(-1)         # Sat 23:59:59 IST

# Treat $weekStart / $weekEnd as IST (Intel reporting timezone) and convert to UTC
# for the ServiceNow filter, because SN stores datetimes in UTC server-side.
$istOffset = New-TimeSpan -Hours 5 -Minutes 30
$weekStartUtc = $weekStart - $istOffset
$weekEndUtc   = $weekEnd   - $istOffset
$startStr     = $weekStartUtc.ToString('yyyy-MM-dd HH:mm:ss')
$endStr       = $weekEndUtc.ToString('yyyy-MM-dd HH:mm:ss')

Write-Host "=== $YearWeek (IST week) : $($weekStart.ToString('yyyy-MM-dd')) (Sun) to $($weekEnd.ToString('yyyy-MM-dd')) (Sat) ===" -ForegroundColor Cyan
Write-Host "    UTC filter window      : $startStr  ..  $endStr" -ForegroundColor DarkGray

$tokenBody = @{
    grant_type    = 'client_credentials'
    client_id     = $cfg.ServiceNowIncidentsClientID
    client_secret = $cfg.ServiceNowIncidentsClientSecret
    scope         = $cfg.ServiceNowIncidentsScope
}
$token = (Invoke-RestMethod -Method Post -Uri $cfg.TokenUrl -Body $tokenBody -ContentType 'application/x-www-form-urlencoded').access_token
if (-not $token) { throw "Failed to acquire ServiceNow token" }

$query = "business_service=$BusinessServiceId^service_offering=$ServiceOfferingId^stateIN6,7^resolved_at>=$startStr^resolved_at<=$endStr"
$fields = 'number,state,opened_at,resolved_at,closed_at,short_description,assignment_group,assigned_to'
$url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$query&sysparm_fields=$fields&sysparm_display_value=true&sysparm_limit=2000"

$resp = Invoke-RestMethod -Method Get -Uri $url -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json' } -TimeoutSec 120
$incidents = @($resp.result)

Write-Host "ServiceNow returned $($incidents.Count) incidents (state Resolved+Closed, resolved_at in week)." -ForegroundColor Green

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$csvPath = Join-Path $OutDir ($YearWeek + '_Incidents.csv')

$incidents |
    Select-Object @{n='Number';e={$_.number}},
                  @{n='State';e={$_.state}},
                  @{n='Opened';e={$_.opened_at}},
                  @{n='Resolved';e={$_.resolved_at}},
                  @{n='Closed';e={$_.closed_at}},
                  @{n='AssignmentGroup';e={ if ($_.assignment_group -is [string]) { $_.assignment_group } else { $_.assignment_group.display_value } }},
                  @{n='AssignedTo';e={ if ($_.assigned_to -is [string]) { $_.assigned_to } else { $_.assigned_to.display_value } }},
                  @{n='ShortDescription';e={$_.short_description}} |
    Sort-Object Resolved |
    Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "Saved CSV: $csvPath" -ForegroundColor Yellow

$incidents | ForEach-Object {
    $sd = if ($_.short_description) { ($_.short_description -replace '\s+', ' ') } else { '' }
    if ($sd.Length -gt 70) { $sd = $sd.Substring(0, 70) }
    [pscustomobject]@{
        Number   = $_.number
        State    = $_.state
        Resolved = $_.resolved_at
        Short    = $sd
    }
} | Sort-Object Resolved | Format-Table -AutoSize
