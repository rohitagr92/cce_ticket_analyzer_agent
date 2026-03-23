[CmdletBinding()]
param(
    [Parameter()]
    [string]$SourceFile = 'incident-analyzer-rb.ps1',
    
    [Parameter()]
    [string]$RunbookName,
    
    [Parameter()]
    [string]$ResourceGroupName = 'Incidents-analyzer-rg',
    
    [Parameter()]
    [string]$AutomationAccountName = 'incident-analyzer-aa'
)

# Determine script path
$baseDir = $PSScriptRoot

# If SourceFile is just a filename, construct full path
if (-not [System.IO.Path]::IsPathRooted($SourceFile)) {
    $ScriptPath = Join-Path $baseDir $SourceFile
} else {
    $ScriptPath = $SourceFile
}

# Validate script file exists
if (-not (Test-Path $ScriptPath)) {
    Write-Host "✗ Script file not found: $ScriptPath" -ForegroundColor Red
    exit 1
}

# Auto-detect RunbookName from filename if not specified
if ([string]::IsNullOrWhiteSpace($RunbookName)) {
    $RunbookName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
} else {
    # Strip .ps1 extension if provided in RunbookName
    $RunbookName = $RunbookName -replace '\.ps1$', ''
}

Write-Host "`n=== Publish Configuration ===" -ForegroundColor Cyan
Write-Host "Source File: $(Split-Path $ScriptPath -Leaf)" -ForegroundColor Gray
Write-Host "Script Path: $ScriptPath" -ForegroundColor Gray
Write-Host "Target Runbook Name: $RunbookName" -ForegroundColor Gray
Write-Host ""

# Check and import Az.Automation module
Write-Host "`n=== Checking Azure Modules ===" -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name Az.Automation)) {
    Write-Host "Az.Automation module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Az.Automation -Scope CurrentUser -Force -AllowClobber
    Write-Host "✓ Az.Automation module installed" -ForegroundColor Green
}

Write-Host "Importing Az.Automation module..." -ForegroundColor Yellow
Import-Module Az.Automation -Force
Write-Host "✓ Module imported" -ForegroundColor Green

Write-Host "`n=== Publishing Runbook to Azure Automation ===" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "Automation Account: $AutomationAccountName" -ForegroundColor Gray
Write-Host "Runbook: $RunbookName" -ForegroundColor Gray
Write-Host ""

# Check if runbook exists
try {
    
    $existingRunbook = Get-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
                                                -AutomationAccountName $AutomationAccountName `
                                                -Name $RunbookName `
                                                -ErrorAction SilentlyContinue
    
    if ($existingRunbook) {
        Write-Host "Found existing runbook:" -ForegroundColor Yellow
        Write-Host "  Type: $($existingRunbook.RunbookType)" -ForegroundColor Gray
        Write-Host "  State: $($existingRunbook.State)" -ForegroundColor Gray
        Write-Host ""
        
        # Delete existing runbook to avoid type mismatch
        Write-Host "Removing existing runbook..." -ForegroundColor Yellow
        Remove-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
                                   -AutomationAccountName $AutomationAccountName `
                                   -Name $RunbookName `
                                   -Force
        Write-Host "✓ Existing runbook removed" -ForegroundColor Green
        Write-Host ""
    }
    
    # Import new runbook
    Write-Host "Importing new runbook..." -ForegroundColor Yellow
    Import-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
                               -AutomationAccountName $AutomationAccountName `
                               -Name $RunbookName `
                               -Type PowerShell72 `
                               -Path $ScriptPath `
                               -Force | Out-Null
    
    Write-Host "✓ Runbook imported" -ForegroundColor Green
    Write-Host ""
    
    # Publish the runbook
    Write-Host "Publishing runbook..." -ForegroundColor Yellow
    Publish-AzAutomationRunbook -ResourceGroupName $ResourceGroupName `
                                -AutomationAccountName $AutomationAccountName `
                                -Name $RunbookName
    
    Write-Host ""
    Write-Host "✓ Runbook published successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now run the runbook from Azure Portal or schedule it." -ForegroundColor Cyan
    
} catch {
    Write-Host ""
    Write-Host "✗ Failed to publish runbook:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Ensure you're connected to Azure: Connect-AzAccount" -ForegroundColor Gray
    Write-Host "2. Verify you have permissions on the Automation Account" -ForegroundColor Gray
    Write-Host "3. Check that the script path is correct" -ForegroundColor Gray
}