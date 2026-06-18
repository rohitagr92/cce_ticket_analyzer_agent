<#
.SYNOPSIS
    Backfill the IncidentsCategoryStats table for a specific work week.

.DESCRIPTION
    Thin wrapper around the production runbook 'incident-analyzer-rb-prodtools'.
    Does NOT contain its own AI prompt, MD parsing, or table-write logic — it
    just supplies a date-window ServiceNow URL to the runbook so the same
    analyzer, the same MD templates from blob, and the same rescue function
    are used as in daily scheduled runs.

    Steps:
      1. Compute the IST Sunday->Saturday UTC window for -YearWeek.
      2. Backup the current 'ServiceNowIncidentsURL' Automation Variable.
      3. Patch it to filter on resolved_at within the week window
         (broad Productivity Tools scope via business_service + service_offering).
      4. Start the runbook and wait for completion.
      5. Restore the original Automation Variable.

.PARAMETER YearWeek
    Required, e.g. '2026-W23'.

.PARAMETER BusinessServiceId
    SN sys_id for the Productivity Tools business service.

.PARAMETER ServiceOfferingId
    SN sys_id for the Productivity Tools service offering.

.EXAMPLE
    .\setup\backfill\Backfill-WeekData.ps1 -YearWeek '2026-W23'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$YearWeek,
    [string]$BusinessServiceId  = 'a1de2ff2db8f50108062531dd3961911',
    [string]$ServiceOfferingId  = 'fcb18407dbcf50108062531dd39619c4',
    [string]$ResourceGroupName  = 'OPSW-Ticket-Analyzer',
    [string]$AutomationAccount  = 'OPSW-ProductivityTools-account',
    [string]$RunbookName        = 'incident-analyzer-rb-prodtools',
    [int]$PollSeconds           = 30,
    [int]$MaxPollMinutes        = 120
)

$ErrorActionPreference = 'Stop'

$setupRoot = Split-Path -Parent $PSScriptRoot
$backupDir = Join-Path $setupRoot 'archive\backups'
$toolsDir = Join-Path $setupRoot 'tools'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null

# -------- Compute IST Sun-Sat window for the requested WW (US/Intel convention) --------
if ($YearWeek -notmatch '^(?<y>\d{4})-W(?<w>\d{1,2})$') { throw "Invalid YearWeek: $YearWeek" }
$year = [int]$Matches.y; $wk = [int]$Matches.w
$jan1 = (Get-Date -Year $year -Month 1 -Day 1).Date
$dow  = [int]$jan1.DayOfWeek                       # Sun=0..Sat=6
$week1Sun  = $jan1.AddDays(-1 * $dow)
$weekStart = $week1Sun.AddDays(($wk - 1) * 7)      # IST Sun 00:00
$weekEnd   = $weekStart.AddDays(7).AddSeconds(-1)  # IST Sat 23:59:59
$istOffset = New-TimeSpan -Hours 5 -Minutes 30
$startUtc  = ($weekStart - $istOffset).ToString('yyyy-MM-dd HH:mm:ss')
$endUtc    = ($weekEnd   - $istOffset).ToString('yyyy-MM-dd HH:mm:ss')

Write-Host "=== Backfilling $YearWeek ===" -ForegroundColor Cyan
Write-Host "    IST window : $($weekStart.ToString('yyyy-MM-dd')) Sun -> $($weekEnd.ToString('yyyy-MM-dd')) Sat" -ForegroundColor Gray
Write-Host "    UTC filter : $startUtc  ->  $endUtc" -ForegroundColor DarkGray

# -------- Backup current Automation Variable --------
$origUrlVar = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Name 'ServiceNowIncidentsURL'
$origLookVar = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Name 'DailyLookbackHours' -ErrorAction SilentlyContinue
$backupPath = Join-Path $backupDir ("sn-url-backup-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$origUrlVar.Value | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backed up original URL to: $backupPath" -ForegroundColor Gray

# -------- Build date-window URL (broad PT scope, resolved within week) --------
# Note: spaces in the date must be URL-encoded as %20 for the SN REST call.
$startEnc = $startUtc -replace ' ', '%20'
$endEnc   = $endUtc   -replace ' ', '%20'
$query = "business_service=$BusinessServiceId^service_offering=$ServiceOfferingId^stateIN6,7^resolved_at>=$startEnc^resolved_at<=$endEnc"
$newUrl = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$query&sysparm_display_value=true&sysparm_limit=2000"
Write-Host "Patched SN URL:" -ForegroundColor Cyan
Write-Host "  $newUrl" -ForegroundColor DarkCyan

try {
    Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Name 'ServiceNowIncidentsURL' -Value $newUrl -Encrypted $false | Out-Null
    # Disable the lookback filter so all incidents in the date-window URL are processed.
    Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Name 'DailyLookbackHours' -Value '0' -Encrypted $false | Out-Null
    # Tell the runbook this is a backfill: it will skip artifact save + weekly merge
    # and use this YearWeek as the PartitionKey (instead of today's week).
    $bfExists = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Name 'BackfillYearWeek' -ErrorAction SilentlyContinue
    if ($bfExists) {
        Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Name 'BackfillYearWeek' -Value $YearWeek -Encrypted $false | Out-Null
    } else {
        New-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Name 'BackfillYearWeek' -Value $YearWeek -Encrypted $false | Out-Null
    }

    # -------- Start runbook and poll to completion --------
    Write-Host "Starting runbook '$RunbookName'..." -ForegroundColor Yellow
    $job = Start-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Name $RunbookName
    $jobId = $job.JobId
    Write-Host "  JobId: $jobId" -ForegroundColor Green
    $jobId | Set-Content (Join-Path $toolsDir 'last-job-id.txt')

    $maxIter = [int](($MaxPollMinutes * 60) / $PollSeconds)
    for ($i = 0; $i -lt $maxIter; $i++) {
        $j = Get-AzAutomationJob -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Id $jobId
        Write-Host ("  [{0}] Status: {1}" -f (Get-Date -Format HH:mm:ss), $j.Status)
        if ($j.Status -in 'Completed','Failed','Stopped','Suspended') { break }
        Start-Sleep -Seconds $PollSeconds
    }

    if ($j.Exception) { Write-Host "Exception: $($j.Exception)" -ForegroundColor Red }
    $color = if ($j.Status -eq 'Completed') { 'Green' } else { 'Red' }
    Write-Host "Runbook final status: $($j.Status)" -ForegroundColor $color
}
finally {
    # -------- Always restore the original Automation Variables --------
    Write-Host "Restoring original Automation Variables..." -ForegroundColor Yellow
    Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Name 'ServiceNowIncidentsURL' -Value $origUrlVar.Value -Encrypted $false | Out-Null
    if ($origLookVar) {
        Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Name 'DailyLookbackHours' -Value $origLookVar.Value -Encrypted $false | Out-Null
    }
    # Clear backfill marker so the next daily run behaves normally
    Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Name 'BackfillYearWeek' -Value '' -Encrypted $false -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Restored." -ForegroundColor Green
}
