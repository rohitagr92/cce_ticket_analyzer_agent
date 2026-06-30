<#!
.SYNOPSIS
    Publish and ensure schedules for all Productivity Tools runbooks used in production.

.DESCRIPTION
    Calls the existing publish helpers to publish and link schedules for:
      - incident-analyzer-rb-prodtools (via Publish-runbook.ps1)
      - incident-trend-backfill-rb-prodtools (via Publish-TrendBackfillRunbook.ps1)
      - incident-trend-rb-prodtools (published via Publish-runbook or handled separately)
      - incident-reconcile-rb-prodtools (via Publish-ReconcileRunbook.ps1)

.NOTES
    Run this from `setup/publish` with Az modules available and an authenticated account.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'OPSW-Ticket-Analyzer',
    [string]$AutomationAccountName = 'OPSW-ProductivityTools-account'
)

Set-StrictMode -Version Latest
$base = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host 'Publishing analyzer runbook...' -ForegroundColor Cyan
& "$base\Publish-runbook.ps1" -SourceFile '..\..\runbooks\incident-analyzer-rb-prodtools.ps1' -RunbookName 'incident-analyzer-rb-prodtools' -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName

Write-Host 'Publishing backfill runbook and schedule...' -ForegroundColor Cyan
& "$base\Publish-TrendBackfillRunbook.ps1" -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -RunbookName 'incident-trend-backfill-rb-prodtools'

Write-Host 'Publishing reconcile runbook and schedule...' -ForegroundColor Cyan
& "$base\Publish-ReconcileRunbook.ps1" -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -RunbookName 'incident-reconcile-rb-prodtools'

Write-Host 'Publishing trend runbook (no dedicated publisher) via generic publisher...' -ForegroundColor Cyan
& "$base\Publish-runbook.ps1" -SourceFile '..\..\runbooks\incident-trend-rb-prodtools.ps1' -RunbookName 'incident-trend-rb-prodtools' -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName

Write-Host 'All publish steps invoked. Verify Azure Portal for schedule links and runbook states.' -ForegroundColor Green
