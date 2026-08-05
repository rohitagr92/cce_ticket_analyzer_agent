<#
.SYNOPSIS
    Keeps Productivity Tools automation in autopilot mode.

.DESCRIPTION
    This script publishes both PT runbooks, ensures daily schedules,
    normalizes key automation variables, clears stale backfill state,
    and can trigger an immediate catch-up run.

.NOTES
    Scope: Productivity Tools only.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'OPSW-Ticket-Analyzer',
    [string]$AutomationAccountName = 'OPSW-ProductivityTools-account',
    [string]$AnalyzerScheduleName = 'IncidentAnalyzer-ProdTools-Daily-0630UTC',
    [int]$AnalyzerRunHourUTC = 6,
    [string]$TrendScheduleName = 'IncidentTrendBackfill-Daily-0300UTC',
    [int]$TrendRunHourUTC = 3,
    [int]$DailyLookbackHours = 72,
    [int]$TrendLookbackDays = 7,
    [switch]$RunCatchupNow,
    [int]$CatchupLookbackDays = 14
)

$ErrorActionPreference = 'Stop'

$publishDir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $publishDir)

Write-Host "=== Productivity Tools Autopilot Hardening ===" -ForegroundColor Cyan
Write-Host "Resource Group    : $ResourceGroupName" -ForegroundColor Gray
Write-Host "Automation Account: $AutomationAccountName" -ForegroundColor Gray

# 1) Ensure trend backfill runbook is published + scheduled daily.
& (Join-Path $publishDir 'Publish-TrendBackfillRunbook.ps1') `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -RunbookName 'incident-trend-backfill-rb-prodtools' `
    -ScheduleName $TrendScheduleName `
    -RunHourUTC $TrendRunHourUTC

# 2) Ensure analyzer runbook is published + scheduled daily.
& (Join-Path $publishDir 'Publish-runbook.ps1') `
    -SourceFile '..\..\runbooks\incident-analyzer-rb-prodtools.ps1' `
    -RunbookName 'incident-analyzer-rb-prodtools' `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -ScheduleName $AnalyzerScheduleName `
    -RunHourUTC $AnalyzerRunHourUTC

# 3) Normalize variables used by daily runs.
Write-Host "=== Enforcing Automation variables ===" -ForegroundColor Cyan
function Set-OrCreateAutomationVariable {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    $existing = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Name -Value $Value -Encrypted $false | Out-Null
    } else {
        New-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Name -Value $Value -Encrypted $false | Out-Null
    }
}

Set-OrCreateAutomationVariable -Name 'DailyLookbackHours' -Value ([string]$DailyLookbackHours)
Set-OrCreateAutomationVariable -Name 'PT_TrendLookbackDays' -Value ([string]$TrendLookbackDays)

# Clear stale backfill context so normal daily runs do not get pinned to an old week.
$bfVar = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name 'BackfillYearWeek' -ErrorAction SilentlyContinue
if ($bfVar) {
    Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name 'BackfillYearWeek' -Value '' -Encrypted $false | Out-Null
    Write-Host "Cleared BackfillYearWeek." -ForegroundColor Green
}

if ($RunCatchupNow) {
    Write-Host "=== Triggering immediate PT catch-up run ===" -ForegroundColor Cyan
    $job = Start-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name 'incident-trend-backfill-rb-prodtools' -Parameters @{ LookbackDays = $CatchupLookbackDays; MaxPerDay = 0 }
    Write-Host "Started runbook job: $($job.JobId)" -ForegroundColor Green
}

Write-Host "[OK] PT autopilot hardening completed." -ForegroundColor Green
