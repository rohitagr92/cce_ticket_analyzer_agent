<#
.SYNOPSIS
    Publishes the daily reconciliation runbook, ensures its schedule, and tries to
    grant the Automation Account permission to start auto-heal jobs.

.DESCRIPTION
    1. Publishes runbooks\incident-reconcile-rb-prodtools.ps1 to the Automation Account
    2. Ensures a daily schedule exists and is linked to the runbook
    3. Tries to assign Automation Contributor to the Automation Account managed identity
       so the runbook can start the backfill runbook during auto-heal

    Run this from the repository root or a parent folder with Az modules installed.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName     = 'OPSW-Ticket-Analyzer',
    [string]$AutomationAccountName = 'OPSW-ProductivityTools-account',
    [string]$RunbookName           = 'incident-reconcile-rb-prodtools',
    [string]$ScheduleName          = 'Daily-Reconcile-0400UTC',
    [int]$RunHourUTC               = 4
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $repoRoot "runbooks\$RunbookName.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Runbook source not found: $scriptPath"
}

Import-Module Az.Automation -Force
Import-Module Az.Resources -Force

Write-Host "=== Publishing reconciliation runbook ===" -ForegroundColor Cyan
Write-Host "Runbook: $RunbookName" -ForegroundColor Gray
Write-Host "Source : $scriptPath" -ForegroundColor Gray
Write-Host ""

$existing = Get-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName -Name $RunbookName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing existing runbook before republishing..." -ForegroundColor Yellow
    Remove-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName -Name $RunbookName -Force
}

Import-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName -Name $RunbookName `
    -Type PowerShell72 -Path $scriptPath -Force | Out-Null

Publish-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName -Name $RunbookName | Out-Null
Write-Host "Runbook published." -ForegroundColor Green

Write-Host ""
Write-Host "=== Ensuring automation identity can start jobs ===" -ForegroundColor Cyan
try {
    $automationAccount = Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName `
        -Name $AutomationAccountName -ErrorAction Stop
    $subscriptionId = (Get-AzContext -ErrorAction Stop).Subscription.Id
    $automationResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName"
    $principalId = $null
    if ($automationAccount.Identity -and $automationAccount.Identity.PrincipalId) {
        $principalId = [string]$automationAccount.Identity.PrincipalId
    }

    if ([string]::IsNullOrWhiteSpace($principalId)) {
        Write-Host 'Automation Account does not expose a system-assigned identity. Enable it before auto-heal can self-start.' -ForegroundColor Yellow
    }
    else {
        $existingAssignment = Get-AzRoleAssignment -ObjectId $principalId -Scope $automationResourceId `
            -RoleDefinitionName 'Automation Contributor' -ErrorAction SilentlyContinue

        if (-not $existingAssignment) {
            New-AzRoleAssignment -ObjectId $principalId -Scope $automationResourceId `
                -RoleDefinitionName 'Automation Contributor' | Out-Null
            Write-Host 'Granted Automation Contributor to the Automation Account managed identity.' -ForegroundColor Green
        }
        else {
            Write-Host 'Automation Account managed identity already has Automation Contributor.' -ForegroundColor Gray
        }
    }
}
catch {
    Write-Host ('Could not verify or grant the role assignment: ' + $_.Exception.Message) -ForegroundColor Yellow
    Write-Host 'If auto-heal still reports limited access, grant Automation Contributor on the Automation Account scope to its managed identity.' -ForegroundColor Yellow
}

Write-Host "" 
Write-Host "=== Ensuring daily schedule ($($RunHourUTC.ToString('D2')):00 UTC) ===" -ForegroundColor Cyan
$existingSchedule = Get-AzAutomationSchedule -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName -Name $ScheduleName -ErrorAction SilentlyContinue

if (-not $existingSchedule) {
    $startUtc = [DateTime]::UtcNow.Date.AddHours($RunHourUTC)
    if ($startUtc -lt [DateTime]::UtcNow.AddMinutes(10)) {
        $startUtc = $startUtc.AddDays(1)
    }

    Write-Host "Creating schedule starting $($startUtc.ToString('yyyy-MM-dd HH:mm')) UTC..." -ForegroundColor Yellow
    New-AzAutomationSchedule -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName -Name $ScheduleName `
        -StartTime $startUtc -DayInterval 1 -TimeZone 'UTC' | Out-Null
    Write-Host 'Schedule created.' -ForegroundColor Green
}
else {
    Write-Host 'Schedule already exists. Reusing.' -ForegroundColor Gray
}

$linked = Get-AzAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName -RunbookName $RunbookName -ErrorAction SilentlyContinue |
    Where-Object { $_.ScheduleName -eq $ScheduleName }

if (-not $linked) {
    Register-AzAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName -RunbookName $RunbookName `
        -ScheduleName $ScheduleName | Out-Null
    Write-Host 'Schedule linked to runbook.' -ForegroundColor Green
}
else {
    Write-Host 'Schedule already linked to runbook.' -ForegroundColor Gray
}

Write-Host "" 
Write-Host '[OK] Daily reconciliation is scheduled.' -ForegroundColor Green
Write-Host "    Runbook : $RunbookName"
Write-Host "    Schedule: $ScheduleName (daily at $($RunHourUTC.ToString('D2')):00 UTC)"