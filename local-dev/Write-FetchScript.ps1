# Writes the rebuilt Fetch-Incidents-NoAI.ps1 using .Keys -based config access

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path (Split-Path $scriptRoot -Parent) 'servicenow\Fetch-Incidents-NoAI.ps1'

$newContent = @'
<#
.SYNOPSIS
  Fetch ServiceNow incidents for a service offering and output CSV (no AI).

.NOTES
  - Mirrors EUC runbook logic: token via client credentials, direct per-offering URL or
    fallback to BusinessServiceId + OfferingId.
  - Fields exported: Number, Resolution Category, Short Description, Work Notes, Resolution Info.
  - Use -DryRun to print the constructed URL without making network calls.
#>

param(
    [string] $ServiceOfferingName,
    [string] $StartWeek,
    [string] $EndWeek,
    [string] $ConfigPath = 'config/LocalConfig-ProductivityTools.psd1',
    [string] $OutputFolder = '.',
    [switch] $DryRun
)

if (-not $ServiceOfferingName) { $ServiceOfferingName = Read-Host 'Enter Service Offering Name' }
if (-not $StartWeek)           { $StartWeek            = Read-Host 'Enter Start Week (YYYY-Wnn)' }
if (-not $EndWeek)             { $EndWeek              = Read-Host 'Enter End Week (YYYY-Wnn)'   }

# Auto-select EUC config for meetings/rooms/hardware
if ($ServiceOfferingName -match '(?i)meeting|room|hardware|confer') {
    $ConfigPath = 'end-user-conferencing\config\LocalConfig-EndUserConferencing.psd1'
}

# Resolve config to absolute path; Import-PowerShellDataFile requires it
function Resolve-AbsPath {
    param([string]$Path)
    if (Test-Path $Path) { return (Resolve-Path $Path).Path }
    $alt = Join-Path $PSScriptRoot "..\$Path"
    if (Test-Path $alt)  { return (Resolve-Path $alt).Path  }
    return $null
}

# Safe hashtable helpers — Import-PowerShellDataFile returns Hashtable, not PSCustomObject
function HasKey { param([object]$h, [string]$k); return ($null -ne $h) -and ($h -is [System.Collections.Hashtable]) -and $h.ContainsKey($k) }
function GetKey { param([object]$h, [string]$k); if (HasKey $h $k) { return $h[$k] } ; return $null }

$cfg = $null
$absConfig = Resolve-AbsPath $ConfigPath
if ($absConfig) {
    try   { $cfg = Import-PowerShellDataFile -Path $absConfig -ErrorAction Stop }
    catch { Write-Host "Warning: failed to import $absConfig : $_" }
}

# Parse weeks
function Get-DateFromIsoWeek { param($year,$week); return [System.Globalization.ISOWeek]::ToDateTime([int]$year, [int]$week, 1) }
try {
    $sY,$sW = $StartWeek.Split('-W')
    $eY,$eW = $EndWeek.Split('-W')
    $startDate = Get-DateFromIsoWeek $sY $sW
    $endDate   = (Get-DateFromIsoWeek $eY $eW).AddDays(6).AddHours(23).AddMinutes(59).AddSeconds(59)
} catch { Write-Error "Invalid week format (expected YYYY-Wnn): $_"; exit 2 }

$startStr = $startDate.ToString('yyyy-MM-dd HH:mm:ss')
$endStr   = $endDate.ToString('yyyy-MM-dd HH:mm:ss')

Write-Host "Querying ServiceNow for '$ServiceOfferingName' | $startStr -> $endStr"

# Resolve ServiceNow incidents URL — mirrors EucRunbookCore Get-EucIncidents logic
$snUrl = $null
if ($ServiceOfferingName -match '(?i)room|hardware|meeting') {
    $candidate = GetKey $cfg 'RoomsIncidentsURL'
    if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { $snUrl = [string]$candidate }
}
if (-not $snUrl) {
    $candidate = GetKey $cfg 'MessagingIncidentsURL'
    if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { $snUrl = [string]$candidate }
}
if (-not $snUrl) {
    $candidate = GetKey $cfg 'ServiceNowIncidentsURL'
    if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { $snUrl = [string]$candidate }
}

if (-not $snUrl) {
    # Build from IDs — same fallback as EucRunbookCore
    $bs = [string](GetKey $cfg 'BusinessServiceId')
    $so = if ($ServiceOfferingName -match '(?i)room|hardware|meeting') {
        [string](GetKey $cfg 'RoomsServiceOfferingId')
    } else {
        [string](GetKey $cfg 'MessagingServiceOfferingId')
    }
    if ($bs -and $so) {
        $bq   = "business_service=${bs}^service_offering=${so}^stateIN6,7^ORDERBYDESCresolved_at"
        $snUrl = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$([uri]::EscapeDataString($bq))&sysparm_display_value=true&sysparm_limit=1000"
    }
}

if (-not $snUrl -and $env:SERVICENOW_APIURL) { $snUrl = $env:SERVICENOW_APIURL }
if (-not $snUrl) { Write-Error 'ServiceNow API URL not found. Provide -ConfigPath or env SERVICENOW_APIURL.'; exit 2 }

# Append date range filter to existing URL query
$urlParts       = $snUrl -split '\?', 2
$base           = $urlParts[0]
$qs             = if ($urlParts.Length -gt 1) { $urlParts[1] } else { '' }
$existingQuery  = ($qs -split '&' | Where-Object { $_ -like 'sysparm_query=*' }) -replace '^sysparm_query=','' -join ''
$otherParams    = ($qs -split '&' | Where-Object { $_ -notlike 'sysparm_query=*' -and $_ -ne '' }) -join '&'
$dateFilter     = "resolved_at>=$startStr^resolved_at<=$endStr"
$fullQuery      = if ($existingQuery) { "${existingQuery}^${dateFilter}" } else { $dateFilter }
$fields         = 'number,resolution_code,category,short_description,work_notes,close_notes'
$url            = "$base?sysparm_query=$([uri]::EscapeDataString($fullQuery))&sysparm_fields=$([uri]::EscapeDataString($fields))&sysparm_limit=10000&sysparm_display_value=true"
if ($otherParams) { $url += "&$otherParams" }

if ($DryRun) { Write-Host "DryRun URL: $url"; exit 0 }

# Acquire bearer token via client credentials — mirrors Get-EucServiceNowToken
$headers = @{ Accept = 'application/json' }
$bearer  = $env:SERVICENOW_BEARER_TOKEN

if (-not $bearer) {
    $clientId     = [string](GetKey $cfg 'ServiceNowClientID')
    $tokenUrl     = [string](GetKey $cfg 'TokenUrl')
    $scope        = [string](GetKey $cfg 'ServiceNowScope')
    $clientSecret = $env:SERVICENOW_CLIENT_SECRET
    if (-not $clientSecret) { $clientSecret = $env:SERVICENOW_INCIDENTS_CLIENTSECRET }
    if (-not $clientSecret) { $clientSecret = [string](GetKey $cfg 'ServiceNowClientSecret') }

    if ($clientId -and $clientSecret -and $tokenUrl) {
        Write-Host "Acquiring token from $tokenUrl ..."
        try {
            $tokenResp = Invoke-RestMethod -Method Post -Uri $tokenUrl `
                -ContentType 'application/x-www-form-urlencoded' `
                -Body @{ grant_type='client_credentials'; client_id=$clientId; client_secret=$clientSecret; scope=$scope } `
                -ErrorAction Stop -TimeoutSec 60
            $bearer = $tokenResp.access_token
        } catch { Write-Error "Token request failed: $_"; exit 3 }
    }
}

if ($bearer) { $headers['Authorization'] = "Bearer $bearer" }

# Fetch incidents
Write-Host "Calling ServiceNow API ..."
try {
    $resp = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -ErrorAction Stop -TimeoutSec 180
} catch { Write-Error "API call failed: $_"; exit 3 }

if (-not $resp.result -or $resp.result.Count -eq 0) { Write-Host 'No results returned.'; exit 0 }
Write-Host "Received $($resp.result.Count) incident(s)."

# Helper: extract display_value from field regardless of whether SN returned string or object
function FV {
    param([object]$v)
    if ($null -eq $v) { return '' }
    if ($v -is [string]) { return $v }
    if ($v.PSObject.Properties['display_value']) { return [string]$v.display_value }
    return [string]$v
}

# Map fields; exclude Proactive System Alert + unassigned (mirrors Apply-EucOfferingIncidentExclusions)
$rows = foreach ($inc in $resp.result) {
    if ($ServiceOfferingName -match '(?i)room|hardware|meeting') {
        $ch = (FV $inc.contact_type).Trim()
        $at = (FV $inc.assigned_to).Trim()
        if ([string]::Equals($ch, 'Proactive System Alert', [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::IsNullOrWhiteSpace($at)) { continue }
    }
    [PSCustomObject]@{
        Number             = FV $inc.number
        ResolutionCategory = if ((FV $inc.resolution_code) -ne '') { FV $inc.resolution_code } else { FV $inc.category }
        ShortDescription   = FV $inc.short_description
        WorkNotes          = (FV $inc.work_notes) -replace '(?s)\r?\n', ' ; '
        ResolutionInfo     = (FV $inc.close_notes) -replace '(?s)\r?\n', ' ; '
    }
}

$rows = @($rows)
if ($rows.Count -eq 0) { Write-Host 'All incidents filtered out.'; exit 0 }

$safeOffering = $ServiceOfferingName -replace '[^a-zA-Z0-9_-]', '_'
$outFile = Join-Path $OutputFolder "ServiceNow_${safeOffering}_${StartWeek}_to_${EndWeek}.csv"
$rows | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
Write-Host "Wrote $($rows.Count) rows to $outFile"
'@

Set-Content -Path $target -Value $newContent -Encoding UTF8
Write-Host "Written: $target"
