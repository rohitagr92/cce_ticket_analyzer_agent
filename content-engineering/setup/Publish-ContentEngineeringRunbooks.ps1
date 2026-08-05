<#
.SYNOPSIS
    Publishes the Content Engineering runbooks and relinks the scheduled jobs.

.DESCRIPTION
    Uses the shared publish helper in setup/publish/Publish-runbook.ps1 so the
    CE runbooks are published with the same schedule-safe behavior as PT.

    Scheduled runbooks:
      - incident-trend-backfill-rb-contenteng.ps1 -> IncidentTrendBackfill-ContentEng-Daily-0330UTC
      - incident-analyzer-rb-contenteng.ps1       -> IncidentAnalyzer-ContentEng-Daily-0630UTC

    Manual runbook:
      - incident-trend-rb-contenteng.ps1          -> published without a schedule link

.NOTES
    This script is intentionally lightweight. It delegates publish and schedule
    creation to the shared helper so there is one enforcement path for PT and CE.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName     = 'OPSW-Ticket-Analyzer',
    [string]$AutomationAccountName = 'OPSW-contentengg-account'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$publishHelper = Join-Path $repoRoot 'setup\publish\Publish-runbook.ps1'
$manifestPath = Join-Path $PSScriptRoot 'ContentEngineeringRunbooks.psd1'

if (-not (Test-Path $publishHelper)) {
    throw "Publish helper not found: $publishHelper"
}

if (-not (Test-Path $manifestPath)) {
    throw "Runbook manifest not found: $manifestPath"
}

$manifest = Import-PowerShellDataFile -Path $manifestPath
$runbooks = @($manifest.Runbooks)

Write-Host "Publishing Content Engineering runbooks with PT-style schedule safety..." -ForegroundColor Cyan

foreach ($runbook in $runbooks) {
    $runbook = [pscustomobject]$runbook
    Write-Host "`n=== $($runbook.RunbookName) ===" -ForegroundColor Cyan
    $publishArgs = @{
        SourceFile          = $runbook.SourceFile
        RunbookName         = $runbook.RunbookName
        ResourceGroupName   = $ResourceGroupName
        AutomationAccountName = $AutomationAccountName
    }

    if ($runbook.SkipSchedule) {
        $publishArgs.SkipSchedule = $true
    } else {
        $publishArgs.ScheduleName = $runbook.ScheduleName
        $publishArgs.RunHourUTC   = [int]$runbook.RunHourUTC
    }

    & $publishHelper @publishArgs
}

Write-Host "`n[OK] Content Engineering runbooks published and scheduled." -ForegroundColor Green