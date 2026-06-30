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

    Make sure AzTable module is added to the Automation Account (Modules gallery,
    "AzTable", scope: PowerShell 7.2). It does not auto-install in runbooks.
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

# -------- Check AzTable module in Automation Account (PowerShell 7.2 runtime) --------
Write-Host "=== Checking AzTable module in Automation Account ===" -ForegroundColor Cyan
$azTablePresent = $false
try {
    # PS 7.2 modules live in the "Powershell72Modules" collection. Use REST since the
    # classic Get-AzAutomationModule cmdlet targets PS 5.1 modules only.
    $sub = (Get-AzContext).Subscription.Id
    $uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/powershell72Modules/AzTable?api-version=2023-11-01"
    $token = (Get-AzAccessToken).Token
    $r = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
    if ($r.properties.provisioningState -eq 'Succeeded') {
        Write-Host "  AzTable module present (PowerShell 7.2 runtime)." -ForegroundColor Green
        $azTablePresent = $true
    } else {
        Write-Host "  AzTable module exists but state: $($r.properties.provisioningState)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  AzTable module NOT installed in Powershell72Modules." -ForegroundColor Yellow
}

if (-not $azTablePresent) {
    Write-Host "  Attempting automatic install via REST..." -ForegroundColor Yellow
    try {
        $body = @{
            properties = @{
                contentLink = @{ uri = 'https://www.powershellgallery.com/api/v2/package/AzTable' }
            }
        } | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Method Put -Uri $uri -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } -Body $body -ErrorAction Stop | Out-Null
        Write-Host "  Install initiated. Polling..." -ForegroundColor Yellow
        for ($n = 0; $n -lt 30; $n++) {
            Start-Sleep -Seconds 20
            try {
                $r = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
                Write-Host "    state=$($r.properties.provisioningState)" -ForegroundColor Gray
                if ($r.properties.provisioningState -eq 'Succeeded') { $azTablePresent = $true; break }
                if ($r.properties.provisioningState -eq 'Failed')    { break }
            } catch {}
        }
        if ($azTablePresent) { Write-Host "  AzTable installed successfully." -ForegroundColor Green }
    } catch {
        Write-Host "  Automatic install failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if (-not $azTablePresent) {
    Write-Host ""
    Write-Host "MANUAL STEP REQUIRED:" -ForegroundColor Yellow
    Write-Host "  1. Open Azure Portal -> Automation Account '$AutomationAccountName' -> Modules (Runtime 7.2)" -ForegroundColor Yellow
    Write-Host "  2. Click 'Add a module' -> Browse gallery -> search 'AzTable' -> Select -> Import" -ForegroundColor Yellow
    Write-Host "  3. Wait ~3-5 minutes for state to become 'Available', then re-run this script." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Continuing with runbook publish; the schedule will fail until AzTable is installed." -ForegroundColor Yellow
}

Write-Host "`n=== Publishing runbook ===" -ForegroundColor Cyan
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
