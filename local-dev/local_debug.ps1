# Set debug preferences
$VerbosePreference = "Continue"
$DebugPreference = "Continue"

# Ensure you're authenticated to Azure
if (-not (Get-AzContext)) {
    Write-Host "Connecting to Azure..." -ForegroundColor Yellow
    Connect-AzAccount
}

# Set subscription
$subscriptionId = "dccc24b6-135c-4614-a303-98879e1bf5dd"
Set-AzContext -SubscriptionId $subscriptionId

Write-Host "`n=== Starting Local Runbook Debug ===" -ForegroundColor Cyan
Write-Host "Environment: Local (not Azure Automation)" -ForegroundColor Cyan
Write-Host "Config: LocalConfig.psd1" -ForegroundColor Cyan
Write-Host "Reports: .\results folder" -ForegroundColor Cyan

# Run the runbook
..\runbooks\incident-analyzer-rb.ps1

Write-Host "`n=== Debug Complete ===" -ForegroundColor Green