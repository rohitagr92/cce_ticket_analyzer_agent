<#
.SYNOPSIS
    Creates blob storage containers for data and results storage.

.DESCRIPTION
    This script creates the required blob storage containers in your storage account:
    - data: For storing raw incident JSON files
    - results: For storing HTML report files
    
    These containers are accessed by the Azure Automation runbook to save:
    - Raw incident data (audit trail)
    - HTML reports (when no webhook URL is configured)

.NOTES
    Prerequisites:
    - Az.Storage module installed
    - Authenticated to Azure (Connect-AzAccount)
    - Storage Account Key Operator or Contributor role on the storage account
    
    Container Access Level: Private (Off)
    - Only accessible via storage account key or SAS token
    - Managed identity has access through key retrieval
#>

param(
    [string]$ResourceGroupName = "Incidents-analyzer-rg",
    [string]$StorageAccountName = "incidentsanalyzersa",
    [string]$DataContainerName = "data",
    [string]$ResultsContainerName = "results"
)

Write-Host "=== Creating Blob Storage Containers ===" -ForegroundColor Cyan
Write-Host ""

try {
    # Check if authenticated
    $azContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $azContext) {
        Write-Host "Not authenticated to Azure. Initiating device code authentication..." -ForegroundColor Yellow
        Connect-AzAccount -DeviceCode -ErrorAction Stop
        Write-Host "✓ Successfully authenticated" -ForegroundColor Green
    } else {
        Write-Host "✓ Already authenticated as: $($azContext.Account.Id)" -ForegroundColor Green
    }
    
    Write-Host ""
    
    # Select subscription if multiple
    $subscriptions = Get-AzSubscription
    if ($subscriptions.Count -gt 1) {
        Write-Host "Multiple subscriptions found. Please select one:" -ForegroundColor Yellow
        $subscription = $subscriptions | Out-GridView -Title "Select Azure Subscription" -PassThru
        if (-not $subscription) {
            throw "No subscription selected"
        }
        Set-AzContext -SubscriptionId $subscription.Id | Out-Null
        Write-Host "✓ Using subscription: $($subscription.Name)" -ForegroundColor Green
    } else {
        Write-Host "✓ Using subscription: $($subscriptions[0].Name)" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Target Configuration:" -ForegroundColor Cyan
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
    Write-Host "  Storage Account: $StorageAccountName" -ForegroundColor Gray
    Write-Host "  Data Container: $DataContainerName" -ForegroundColor Gray
    Write-Host "  Results Container: $ResultsContainerName" -ForegroundColor Gray
    Write-Host ""
    
    # Verify storage account exists
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
    Write-Host "✓ Found storage account: $($storageAccount.StorageAccountName)" -ForegroundColor Green
    Write-Host ""
    
    # Get storage context
    Write-Host "Getting storage account key..." -ForegroundColor Yellow
    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageKey
    Write-Host "✓ Storage context created" -ForegroundColor Green
    Write-Host ""
    
    # Create data container
    Write-Host "Creating '$DataContainerName' container..." -ForegroundColor Yellow
    $existingDataContainer = Get-AzStorageContainer -Name $DataContainerName -Context $storageContext -ErrorAction SilentlyContinue
    
    if ($existingDataContainer) {
        Write-Host "  ⚠ Container '$DataContainerName' already exists" -ForegroundColor Yellow
        Write-Host "  Container details:" -ForegroundColor Gray
        Write-Host "    - Name: $($existingDataContainer.Name)" -ForegroundColor Gray
        Write-Host "    - Last Modified: $($existingDataContainer.LastModified)" -ForegroundColor Gray
        Write-Host "    - Public Access: $($existingDataContainer.PublicAccess)" -ForegroundColor Gray
    } else {
        New-AzStorageContainer -Name $DataContainerName -Context $storageContext -Permission Off | Out-Null
        Write-Host "  ✓ Created '$DataContainerName' container (Private access)" -ForegroundColor Green
    }
    
    # Create results container
    Write-Host "Creating '$ResultsContainerName' container..." -ForegroundColor Yellow
    $existingResultsContainer = Get-AzStorageContainer -Name $ResultsContainerName -Context $storageContext -ErrorAction SilentlyContinue
    
    if ($existingResultsContainer) {
        Write-Host "  ⚠ Container '$ResultsContainerName' already exists" -ForegroundColor Yellow
        Write-Host "  Container details:" -ForegroundColor Gray
        Write-Host "    - Name: $($existingResultsContainer.Name)" -ForegroundColor Gray
        Write-Host "    - Last Modified: $($existingResultsContainer.LastModified)" -ForegroundColor Gray
        Write-Host "    - Public Access: $($existingResultsContainer.PublicAccess)" -ForegroundColor Gray
    } else {
        New-AzStorageContainer -Name $ResultsContainerName -Context $storageContext -Permission Off | Out-Null
        Write-Host "  ✓ Created '$ResultsContainerName' container (Private access)" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "=== Container Summary ===" -ForegroundColor Cyan
    $allContainers = Get-AzStorageContainer -Context $storageContext | 
        Where-Object { $_.Name -in @($DataContainerName, $ResultsContainerName, "templates", "logs", "mdm-ai-reports") }
    
    if ($allContainers) {
        $allContainers | ForEach-Object {
            $icon = switch ($_.Name) {
                $DataContainerName { "📁" }
                $ResultsContainerName { "📊" }
                "templates" { "📝" }
                "logs" { "📋" }
                "mdm-ai-reports" { "📈" }
                default { "📦" }
            }
            
            $description = switch ($_.Name) {
                $DataContainerName { "(Raw incident JSON files)" }
                $ResultsContainerName { "(HTML report files)" }
                "templates" { "(AI prompt templates)" }
                "logs" { "(Execution logs)" }
                "mdm-ai-reports" { "(Legacy reports - optional)" }
                default { "" }
            }
            
            Write-Host "  $icon $($_.Name) $description" -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "Blob storage containers configured successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Container Purpose:" -ForegroundColor Cyan
    Write-Host "  📁 $DataContainerName" -ForegroundColor White
    Write-Host "     - Stores raw incident data as JSON files" -ForegroundColor Gray
    Write-Host "     - Files named: incidents_yyyy-MM-dd_HH-mm-ss.json" -ForegroundColor Gray
    Write-Host "     - Used for audit trail and debugging" -ForegroundColor Gray
    Write-Host "     - Can be loaded later with UseStoredIncidents setting" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  📊 $ResultsContainerName" -ForegroundColor White
    Write-Host "     - Stores HTML report files" -ForegroundColor Gray
    Write-Host "     - Files named: MDM_AI_Analysis_Report_*.html" -ForegroundColor Gray
    Write-Host "     - Used when webhook URL is not configured" -ForegroundColor Gray
    Write-Host "     - Can be viewed by downloading from Azure Portal" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "1. Verify automation variables are configured:" -ForegroundColor White
    Write-Host "   .\Add-BlobStorageVariables.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Republish the runbook with blob storage support:" -ForegroundColor White
    Write-Host "   .\Publish-runbook.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Test the runbook in Azure Automation" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "=== ERROR ===" -ForegroundColor Red
    Write-Host "Failed to create blob containers: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Common Issues:" -ForegroundColor Yellow
    Write-Host "  - Insufficient permissions: Ensure you have Contributor or Storage Account Key Operator role" -ForegroundColor Gray
    Write-Host "  - Storage account not found: Verify ResourceGroupName and StorageAccountName" -ForegroundColor Gray
    Write-Host "  - Subscription context: Use Set-AzContext to select the correct subscription" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}
