<#
.SYNOPSIS
    Publishes the incremental backfill runbook and creates a daily schedule.
.DESCRIPTION
    1. Publishes runbooks\incident-trend-backfill-rb-prodtools.ps1 to the Automation Account
    2. Ensures a daily schedule exists (default 03:00 UTC) - linked to the runbook
    3. Idempotent: re-running just refreshes the published runbook content.

    Make sure the templates container holds these blobs (Upload-TemplateFiles.ps1 does this):
        TicketCategorisation_ProductivityTools.md
        EnvironmentContext_ProductivityTools.md

    The runbook now uses the native Microsoft.WindowsAzure.Storage SDK, so no AzTable
    gallery module is required in the Automation Account.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName     = 'OPSW-Ticket-Analyzer',
    [string]$AutomationAccountName = 'OPSW-ProductivityTools-account',
    [string]$RunbookName           = 'incident-trend-backfill-rb-prodtools',
    [string]$ScheduleName          = 'IncidentTrendBackfill-Daily-0300UTC',
    [int]$RunHourUTC               = 3
)

$ErrorActionPreference = 'Stop'
$repoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $repoRoot "runbooks\$RunbookName.ps1"
if (-not (Test-Path $scriptPath)) { throw "Runbook source not found: $scriptPath" }

Import-Module Az.Automation -Force

Write-Host "=== Publishing runbook ===" -ForegroundColor Cyan
Write-Host "Backfill runbook uses native table SDK; no AzTable module check is required." -ForegroundColor Gray

$existing = Get-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName -Name $RunbookName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  Removing existing runbook to replace..." -ForegroundColor Yellow
    Remove-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName -Name $RunbookName -Force
}

Import-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName -Name $RunbookName `
    -Type PowerShell72 -Path $scriptPath -Force | Out-Null

Publish-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName -Name $RunbookName | Out-Null
Write-Host "  Runbook published: $RunbookName" -ForegroundColor Green

Write-Host "`n=== Ensuring daily schedule ($($RunHourUTC.ToString('D2')):00 UTC) ===" -ForegroundColor Cyan
$existingSchedule = Get-AzAutomationSchedule -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName -Name $ScheduleName -ErrorAction SilentlyContinue

if (-not $existingSchedule) {
    # Start at the next occurrence of RunHourUTC; if already past today, use tomorrow
    $startUtc = [DateTime]::UtcNow.Date.AddHours($RunHourUTC)
    if ($startUtc -lt [DateTime]::UtcNow.AddMinutes(10)) { $startUtc = $startUtc.AddDays(1) }
    Write-Host "  Creating schedule starting $($startUtc.ToString('yyyy-MM-dd HH:mm')) UTC..." -ForegroundColor Yellow
    New-AzAutomationSchedule -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName -Name $ScheduleName `
        -StartTime $startUtc -DayInterval 1 -TimeZone 'UTC' | Out-Null
    Write-Host "  Schedule created." -ForegroundColor Green
} else {
    Write-Host "  Schedule already exists. Reusing." -ForegroundColor Gray
}

# Link schedule to runbook (idempotent - Register returns existing link if present)
$linked = Get-AzAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName -RunbookName $RunbookName -ErrorAction SilentlyContinue |
    Where-Object { $_.ScheduleName -eq $ScheduleName }
if (-not $linked) {
    Register-AzAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName -RunbookName $RunbookName `
        -ScheduleName $ScheduleName | Out-Null
    Write-Host "  Schedule linked to runbook." -ForegroundColor Green
} else {
    Write-Host "  Schedule already linked to runbook." -ForegroundColor Gray
}

Write-Host "`n[OK] Daily incremental backfill is scheduled." -ForegroundColor Green
Write-Host "    Runbook : $RunbookName"
Write-Host "    Schedule: $ScheduleName (daily at $($RunHourUTC.ToString('D2')):00 UTC)"
Write-Host ""
Write-Host "Tip: To trigger an immediate test run, use the Azure Portal -> Automation Account ->"
Write-Host "     Runbooks -> $RunbookName -> Start."
