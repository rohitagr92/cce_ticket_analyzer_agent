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
    [string]$QualityGuardScheduleName = 'IncidentQualityGuard-Daily-0330UTC',
    [int]$QualityGuardRunHourUTC = 3,
    [int]$QualityGuardRunMinuteUTC = 30,
    [int]$DailyLookbackHours = 72,
    [int]$TrendLookbackDays = 7,
    [int]$ReconcileWeeksToCheck = 2,
    [int]$ReconcileDeltaThreshold = 0,
    [bool]$EnableReconcileAutoHeal = $true,
    [int]$ReconcileMaxHealPerWeekPerDay = 1,
    [switch]$RunCatchupNow,
    [int]$CatchupLookbackDays = 14
)

$ErrorActionPreference = 'Stop'

$publishDir = $PSScriptRoot

Write-Host "=== Productivity Tools Autopilot Hardening ===" -ForegroundColor Cyan
Write-Host "Resource Group    : $ResourceGroupName" -ForegroundColor Gray
Write-Host "Automation Account: $AutomationAccountName" -ForegroundColor Gray

function Ensure-RunbookScheduleLink {
    param(
        [Parameter(Mandatory)][string]$RunbookName,
        [Parameter(Mandatory)][string]$ScheduleName,
        [Parameter(Mandatory)][int]$RunHourUTC,
        [Parameter(Mandatory)][int]$RunMinuteUTC
    )

    $existingSchedule = Get-AzAutomationSchedule -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Name $ScheduleName -ErrorAction SilentlyContinue

    if (-not $existingSchedule) {
        $startUtc = [DateTime]::UtcNow.Date.AddHours($RunHourUTC).AddMinutes($RunMinuteUTC)
        if ($startUtc -lt [DateTime]::UtcNow.AddMinutes(10)) { $startUtc = $startUtc.AddDays(1) }
        Write-Host "Creating schedule '$ScheduleName' starting $($startUtc.ToString('yyyy-MM-dd HH:mm')) UTC..." -ForegroundColor Yellow
        New-AzAutomationSchedule -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name $ScheduleName `
            -StartTime $startUtc `
            -DayInterval 1 `
            -TimeZone 'UTC' | Out-Null
    } else {
        Write-Host "Schedule '$ScheduleName' already exists. Reusing." -ForegroundColor Gray
    }

    $existingLinks = @(Get-AzAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -RunbookName $RunbookName -ErrorAction SilentlyContinue)

    foreach ($link in $existingLinks) {
        if ($link.ScheduleName -ne $ScheduleName) {
            Write-Host "Removing stale schedule link '$($link.ScheduleName)' from runbook '$RunbookName'." -ForegroundColor Yellow
            Unregister-AzAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -RunbookName $RunbookName `
                -ScheduleName $link.ScheduleName -Force | Out-Null
        }
    }

    $linked = Get-AzAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -RunbookName $RunbookName -ErrorAction SilentlyContinue |
        Where-Object { $_.ScheduleName -eq $ScheduleName }

    if (-not $linked) {
        Register-AzAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -RunbookName $RunbookName `
            -ScheduleName $ScheduleName | Out-Null
        Write-Host "Linked schedule '$ScheduleName' to runbook '$RunbookName'." -ForegroundColor Green
    } else {
        Write-Host "Runbook '$RunbookName' is already linked to '$ScheduleName'." -ForegroundColor Gray
    }
}

function Remove-StaleProdToolsSchedules {
    $allowed = @($AnalyzerScheduleName, $TrendScheduleName, $QualityGuardScheduleName)
    $allSchedules = @(Get-AzAutomationSchedule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName)

    foreach ($schedule in $allSchedules) {
        $name = [string]$schedule.Name
        $isExpected = $allowed -contains $name
        $looksLikePt = $name -match 'Incident.*ProdTools|ProdTools|Daily.*(Analyzer|Backfill|Quality)|IncidentAnalyzer|IncidentTrendBackfill|IncidentQualityGuard'

        if (-not $isExpected -and $looksLikePt) {
            Write-Host "Removing stale Productivity Tools schedule '$name'." -ForegroundColor Yellow
            Remove-AzAutomationSchedule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $name -Force | Out-Null
        }
    }
}

Remove-StaleProdToolsSchedules

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

# 3) Ensure quality guard runbook is published and linked daily after trend backfill.
& (Join-Path $publishDir 'Publish-runbook.ps1') `
    -SourceFile '..\..\runbooks\incident-quality-guard-rb-prodtools.ps1' `
    -RunbookName 'incident-quality-guard-rb-prodtools' `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -SkipSchedule

Ensure-RunbookScheduleLink `
    -RunbookName 'incident-quality-guard-rb-prodtools' `
    -ScheduleName $QualityGuardScheduleName `
    -RunHourUTC $QualityGuardRunHourUTC `
    -RunMinuteUTC $QualityGuardRunMinuteUTC

# 4) Normalize variables used by daily runs.
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
Set-OrCreateAutomationVariable -Name 'PT_ReconcileWeeksToCheck' -Value ([string]$ReconcileWeeksToCheck)
Set-OrCreateAutomationVariable -Name 'PT_ReconcileDeltaThreshold' -Value ([string]$ReconcileDeltaThreshold)
Set-OrCreateAutomationVariable -Name 'PT_ReconcileEnableAutoHeal' -Value ([string]$EnableReconcileAutoHeal)
Set-OrCreateAutomationVariable -Name 'PT_ReconcileMaxHealPerWeekPerDay' -Value ([string]$ReconcileMaxHealPerWeekPerDay)

$healStateDefault = '{"date":"","attempts":{}}'
$healStateVar = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name 'PT_ReconcileAutoHealState' -ErrorAction SilentlyContinue
if (-not $healStateVar) {
    New-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name 'PT_ReconcileAutoHealState' -Value $healStateDefault -Encrypted $false | Out-Null
    Write-Host "Initialized PT_ReconcileAutoHealState." -ForegroundColor Green
}

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
