<#
.SYNOPSIS
    Adds blob storage container automation variables for data and results storage.

.DESCRIPTION
    This script creates two new automation variables required for the enhanced blob storage support:
    - Incidents_analyzer_DataContainerName: Container for raw incident data (JSON files)
    - Incidents_analyzer_ResultsContainerName: Container for HTML report files
    
    These containers mirror the local development folders:
    - Local: .\data folder maps to Azure data container
    - Local: .\results folder maps to Azure results container

.NOTES
    Prerequisites:
    - Az.Automation module installed
    - Authenticated to Azure (Connect-AzAccount)
    - Contributor or Owner role on the automation account
    
    Run this script ONCE to add the new variables to your existing automation account.
#>

param(
    [string]$ResourceGroupName = "OPSW-Ticket-Analyzer",
    [string]$AutomationAccountName = "OPSW-ProductivityTools-account",
    [string]$DataContainerName = "data",
    [string]$ResultsContainerName = "results"
)

Write-Host "=== Adding Blob Storage Container Variables ===" -ForegroundColor Cyan
Write-Host ""

try {
    # Check if authenticated
    $azContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $azContext) {
        Write-Host "Not authenticated to Azure. Initiating device code authentication..." -ForegroundColor Yellow
        Connect-AzAccount -DeviceCode -ErrorAction Stop
        Write-Host "Successfully authenticated" -ForegroundColor Green
    } else {
        Write-Host "Already authenticated as: $($azContext.Account.Id)" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Target Configuration:" -ForegroundColor Cyan
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
    Write-Host "  Automation Account: $AutomationAccountName" -ForegroundColor Gray
    Write-Host "  Data Container: $DataContainerName" -ForegroundColor Gray
    Write-Host "  Results Container: $ResultsContainerName" -ForegroundColor Gray
    Write-Host ""
    
    # Verify automation account exists
    $automationAccount = Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName -ErrorAction Stop
    Write-Host "Found automation account: $($automationAccount.AutomationAccountName)" -ForegroundColor Green
    Write-Host ""
    
    # Create DataContainerName variable
    Write-Host "Creating Incidents_analyzer_DataContainerName variable..." -ForegroundColor Yellow
    $existingDataVar = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Name "Incidents_analyzer_DataContainerName" `
        -ErrorAction SilentlyContinue
    
    if ($existingDataVar) {
        Write-Host "  Variable already exists with value: $($existingDataVar.Value)" -ForegroundColor Yellow
        $updateData = Read-Host "  Update to '$DataContainerName'? (y/n)"
        if ($updateData -eq 'y') {
            Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -Name "Incidents_analyzer_DataContainerName" `
                -Value $DataContainerName `
                -Encrypted $false | Out-Null
            Write-Host "  Updated Incidents_analyzer_DataContainerName = $DataContainerName" -ForegroundColor Green
        } else {
            Write-Host "  Skipped update" -ForegroundColor Gray
        }
    } else {
        New-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name "Incidents_analyzer_DataContainerName" `
            -Value $DataContainerName `
            -Encrypted $false | Out-Null
        Write-Host "  Created Incidents_analyzer_DataContainerName = $DataContainerName" -ForegroundColor Green
    }
    
    # Create ResultsContainerName variable
    Write-Host "Creating Incidents_analyzer_ResultsContainerName variable..." -ForegroundColor Yellow
    $existingResultsVar = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Name "Incidents_analyzer_ResultsContainerName" `
        -ErrorAction SilentlyContinue
    
    if ($existingResultsVar) {
        Write-Host "  Variable already exists with value: $($existingResultsVar.Value)" -ForegroundColor Yellow
        $updateResults = Read-Host "  Update to '$ResultsContainerName'? (y/n)"
        if ($updateResults -eq 'y') {
            Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -Name "Incidents_analyzer_ResultsContainerName" `
                -Value $ResultsContainerName `
                -Encrypted $false | Out-Null
            Write-Host "  Updated Incidents_analyzer_ResultsContainerName = $ResultsContainerName" -ForegroundColor Green
        } else {
            Write-Host "  Skipped update" -ForegroundColor Gray
        }
    } else {
        New-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name "Incidents_analyzer_ResultsContainerName" `
            -Value $ResultsContainerName `
            -Encrypted $false | Out-Null
        Write-Host "  Created Incidents_analyzer_ResultsContainerName = $ResultsContainerName" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "Blob storage container variables configured successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "1. Create blob containers in storage account:" -ForegroundColor White
    Write-Host "   - Container: $DataContainerName (for raw incident JSON files)" -ForegroundColor Gray
    Write-Host "   - Container: $ResultsContainerName (for HTML report files)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Run the following commands to create containers:" -ForegroundColor White
    Write-Host "   `$storageAccountName = 'opswprodtoolsblob'" -ForegroundColor Gray
    Write-Host "   `$resourceGroup = '$ResourceGroupName'" -ForegroundColor Gray
    Write-Host "   `$subscriptionId = (Get-AzSubscription | Out-GridView -Title 'Select Subscription' -PassThru).Id" -ForegroundColor Gray
    Write-Host "   Set-AzContext -SubscriptionId `$subscriptionId" -ForegroundColor Gray
    Write-Host "   `$storageKey = (Get-AzStorageAccountKey -ResourceGroupName `$resourceGroup -Name `$storageAccountName)[0].Value" -ForegroundColor Gray
    Write-Host "   `$ctx = New-AzStorageContext -StorageAccountName `$storageAccountName -StorageAccountKey `$storageKey" -ForegroundColor Gray
    Write-Host "   New-AzStorageContainer -Name '$DataContainerName' -Context `$ctx -Permission Off" -ForegroundColor Gray
    Write-Host "   New-AzStorageContainer -Name '$ResultsContainerName' -Context `$ctx -Permission Off" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Republish the runbook:" -ForegroundColor White
    Write-Host "   .\Publish-runbook.ps1" -ForegroundColor Gray
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "=== ERROR ===" -ForegroundColor Red
    Write-Host "Failed to add automation variables: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}
