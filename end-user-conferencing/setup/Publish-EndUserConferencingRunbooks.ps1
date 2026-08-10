<#
.SYNOPSIS
    Publishes the End User Conferencing runbooks and relinks schedules.

.DESCRIPTION
    Uses the shared publish helper so all EUC runbooks follow the same safe
    publish behavior as the existing Productivity Tools and Content Engineering
    setups.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName     = 'OPSW-Ticket-Analyzer',
    [string]$AutomationAccountName = 'opswconferautomation'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$publishHelper = Join-Path $repoRoot 'setup\publish\Publish-runbook.ps1'
$manifestPath = Join-Path $PSScriptRoot 'EndUserConferencingRunbooks.psd1'

if (-not (Test-Path $publishHelper)) {
    throw "Publish helper not found: $publishHelper"
}

if (-not (Test-Path $manifestPath)) {
    throw "Runbook manifest not found: $manifestPath"
}

$manifest = Import-PowerShellDataFile -Path $manifestPath
$serviceOfferings = @($manifest.ServiceOfferings)

Write-Host "Publishing End User Conferencing runbooks..." -ForegroundColor Cyan
Write-Host "Storage account: $($manifest.SharedAzureAssets.StorageAccountName)" -ForegroundColor Gray
Write-Host "Key Vault      : $($manifest.SharedAzureAssets.KeyVaultName)" -ForegroundColor Gray
Write-Host "Automation acct: $AutomationAccountName" -ForegroundColor Gray

foreach ($offering in $serviceOfferings) {
    Write-Host "`n=== $($offering.Name) ===" -ForegroundColor Cyan
    foreach ($runbook in @($offering.Runbooks)) {
        $publishArgs = @{
            SourceFile          = $runbook.SourceFile
            RunbookName         = $runbook.PublishedName
            ResourceGroupName   = $ResourceGroupName
            AutomationAccountName = $AutomationAccountName
        }
        if ($runbook.SkipSchedule) {
            $publishArgs.SkipSchedule = $true
        } else {
            $publishArgs.ScheduleName = $runbook.ScheduleName
            $publishArgs.RunHourUTC   = [int]$runbook.RunHourUTC
            $publishArgs.RunMinuteUTC = [int]$runbook.RunMinuteUTC
        }
        & $publishHelper @publishArgs
    }
}

Write-Host "`n[OK] End User Conferencing runbooks published." -ForegroundColor Green
