<#
.SYNOPSIS
    Diagnostic: compares ServiceNow's incident count for a given YearWeek against
    the IncidentsCategoryStats table.

.PARAMETER YearWeek
    Target week (default 2026-W21). Format: YYYY-Wnn.
#>

[CmdletBinding()]
param(
    [string]$YearWeek = '2026-W21',
    [string]$SubscriptionId = '1c6d384e-bc83-4b02-859c-76eeb87f7676',
    [string]$BusinessServiceId = 'a1de2ff2db8f50108062531dd3961911',
    [string]$ServiceOfferingId = 'fcb18407dbcf50108062531dd39619c4'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$cfg     = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'config\LocalConfig-ProductivityTools.psd1')
$secrets = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'config\LocalSecrets-ProductivityTools.psd1')
foreach ($k in $secrets.Keys) { $cfg[$k] = $secrets[$k] }

# -------- Compute Mon-Sun range for the given ISO YearWeek (FirstFourDayWeek, Monday) --------
if ($YearWeek -notmatch '^(\d{4})-W(\d{2})$') { throw "Bad YearWeek format: $YearWeek" }
$year = [int]$matches[1]
$wk   = [int]$matches[2]
$jan4 = Get-Date -Year $year -Month 1 -Day 4 -Hour 0 -Minute 0 -Second 0
$jan4Dow = [int]$jan4.DayOfWeek    # Sun=0..Sat=6
if ($jan4Dow -eq 0) { $jan4Dow = 7 }  # Treat Sunday as 7 for Monday-first
$week1Mon = $jan4.AddDays( -1 * ($jan4Dow - 1) )
$weekStart = $week1Mon.AddDays( ($wk - 1) * 7 )  # Monday 00:00
$weekEnd   = $weekStart.AddDays(7).AddSeconds(-1) # Sunday 23:59:59

Write-Host "=== Diagnosing $YearWeek ===" -ForegroundColor Cyan
Write-Host ("  ISO Monday-first week range : {0:yyyy-MM-dd} .. {1:yyyy-MM-dd}" -f $weekStart, $weekEnd) -ForegroundColor Gray

# -------- ServiceNow auth + fetch --------
$body = @{
    grant_type    = 'client_credentials'
    client_id     = $cfg.ServiceNowIncidentsClientID
    client_secret = $cfg.ServiceNowIncidentsClientSecret
    scope         = $cfg.ServiceNowIncidentsScope
}
$token = (Invoke-RestMethod -Method Post -Uri $cfg.TokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded').access_token

$startStr = $weekStart.ToString('yyyy-MM-dd 00:00:00')
$endStr   = $weekEnd.ToString('yyyy-MM-dd 23:59:59')

function Invoke-SnQuery {
    param([string]$Query)
    $url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$Query&sysparm_display_value=true&sysparm_limit=2000"
    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
    (Invoke-RestMethod -Method Get -Uri $url -Headers $headers -TimeoutSec 180).result
}

# Query A: same as backfill - resolved_at in week, state 6 or 7
$qA = "business_service=$BusinessServiceId^service_offering=$ServiceOfferingId^stateIN6,7^resolved_at>=$startStr^resolved_at<=$endStr"
Write-Host "`n[A] resolved_at in week + state IN (6,7) [== backfill query]" -ForegroundColor Yellow
$snA = @(Invoke-SnQuery -Query $qA)
Write-Host ("    ServiceNow returned: {0} incidents" -f $snA.Count) -ForegroundColor Green

# Query B: resolved_at in week, ANY state
$qB = "business_service=$BusinessServiceId^service_offering=$ServiceOfferingId^resolved_at>=$startStr^resolved_at<=$endStr"
Write-Host "`n[B] resolved_at in week + ANY state" -ForegroundColor Yellow
$snB = @(Invoke-SnQuery -Query $qB)
Write-Host ("    ServiceNow returned: {0} incidents" -f $snB.Count) -ForegroundColor Green

# Query C: opened_at in week, ANY state (what most reports use)
$qC = "business_service=$BusinessServiceId^service_offering=$ServiceOfferingId^opened_at>=$startStr^opened_at<=$endStr"
Write-Host "`n[C] opened_at in week + ANY state [common report definition]" -ForegroundColor Yellow
$snC = @(Invoke-SnQuery -Query $qC)
Write-Host ("    ServiceNow returned: {0} incidents" -f $snC.Count) -ForegroundColor Green

# -------- Table content for this partition --------
Write-Host "`n[Table] Rows in partition $YearWeek" -ForegroundColor Yellow
$ctxAz = Get-AzContext
if (-not $ctxAz) {
    Connect-AzAccount -Subscription $SubscriptionId | Out-Null
} elseif ($ctxAz.Subscription.Id -ne $SubscriptionId) {
    Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null
}
$saKey = (Get-AzStorageAccountKey -ResourceGroupName $cfg.PSD_AI_Automations_ResourceGroupName -Name $cfg.PSD_AI_Automations_StorageAccountName)[0].Value
$saCtx = New-AzStorageContext -StorageAccountName $cfg.PSD_AI_Automations_StorageAccountName -StorageAccountKey $saKey
Import-Module AzTable -Force
$tbl   = Get-AzStorageTable -Name 'IncidentsCategoryStats' -Context $saCtx
$rows  = @(Get-AzTableRow -Table $tbl.CloudTable -PartitionKey $YearWeek)
Write-Host ("    Table contains: {0} rows" -f $rows.Count) -ForegroundColor Green

$tableSet = [System.Collections.Generic.HashSet[string]]::new()
foreach ($r in $rows) { [void]$tableSet.Add([string]$r.RowKey) }

# -------- Show what's in A but missing from table --------
$snASet = [System.Collections.Generic.HashSet[string]]::new()
foreach ($i in $snA) { [void]$snASet.Add([string]$i.number) }

$missingFromTable = $snA | Where-Object { -not $tableSet.Contains([string]$_.number) }
Write-Host "`n=== Incidents in ServiceNow [A] but NOT in table ($($missingFromTable.Count)) ===" -ForegroundColor Magenta
$missingFromTable | ForEach-Object {
    $resolvedDt = $_.resolved_at
    Write-Host ("  {0,-15} state={1,-12} resolved={2}  short=`"{3}`"" -f $_.number, $_.state, $resolvedDt, ($_.short_description -replace '\s+',' ' | ForEach-Object { if ($_.Length -gt 60) { $_.Substring(0,60)+'...' } else { $_ } }))
}

$extraInTable = $rows | Where-Object { -not $snASet.Contains([string]$_.RowKey) }
Write-Host "`n=== Rows in table but NOT in ServiceNow [A] ($($extraInTable.Count)) ===" -ForegroundColor Magenta
$extraInTable | ForEach-Object {
    Write-Host ("  {0,-15} date={1}  category={2}" -f $_.RowKey, $_.Date, $_.Category)
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host ("  ServiceNow [A] resolved_at+state6,7 : {0}" -f $snA.Count)
Write-Host ("  ServiceNow [B] resolved_at+anyState  : {0}" -f $snB.Count)
Write-Host ("  ServiceNow [C] opened_at+anyState    : {0}" -f $snC.Count)
Write-Host ("  Table partition $YearWeek            : {0}" -f $rows.Count)
Write-Host ("  Missing from table (in A not table) : {0}" -f $missingFromTable.Count)
