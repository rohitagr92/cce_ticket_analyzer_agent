<#
.SYNOPSIS
    Sets up all required automation variables for the incident-analyzer-rb runbook in Azure Automation.

.DESCRIPTION
    This script creates all 14 automation variables needed by the incident-analyzer-rb.ps1 runbook.
    It will prompt you for each value and create them in your Azure Automation account.
    Sensitive values (secrets, API keys) are created as encrypted variables.

.NOTES
    Author: Incident Analyzer Setup Script
    Date: December 18, 2025
    Prerequisites: 
    - Azure PowerShell module (Az.Automation)
    - Authenticated to Azure (Connect-AzAccount)
    - Contributor or higher access to the Automation Account
#>

# ============================================================================
# STEP 1: Connect to Azure
# ============================================================================
Write-Host "`n=== Step 1: Azure Authentication ===" -ForegroundColor Cyan
Write-Host "Checking if already connected to Azure..." -ForegroundColor Yellow

try {
    # Get current Azure context to check if already authenticated
    $context = Get-AzContext
    if ($null -eq $context) {
        Write-Host "Not connected. Initiating Azure login..." -ForegroundColor Yellow
        Connect-AzAccount
    } else {
        Write-Host "Already connected as: $($context.Account.Id)" -ForegroundColor Green
        Write-Host "Subscription: $($context.Subscription.Name)" -ForegroundColor Green
    }
} catch {
    Write-Host "Error checking Azure connection. Attempting to connect..." -ForegroundColor Yellow
    Connect-AzAccount
}

# ============================================================================
# STEP 2: Collect Azure Automation Account Details
# ============================================================================
Write-Host "`n=== Step 2: Azure Automation Account Configuration ===" -ForegroundColor Cyan
Write-Host "Enter your Azure Automation account details:" -ForegroundColor Yellow

# Prompt for automation account name
$AutomationAccountName = Read-Host "Enter your Automation Account name"

# Prompt for resource group name where automation account is located
$AutomationResourceGroup = Read-Host "Enter the Resource Group name (where Automation Account is located)"

# Verify the automation account exists
Write-Host "`nVerifying automation account exists..." -ForegroundColor Yellow
try {
    $automationAccount = Get-AzAutomationAccount -ResourceGroupName $AutomationResourceGroup -Name $AutomationAccountName -ErrorAction Stop
    Write-Host "✓ Automation Account found: $($automationAccount.AutomationAccountName)" -ForegroundColor Green
} catch {
    Write-Host "✗ ERROR: Could not find automation account '$AutomationAccountName' in resource group '$AutomationResourceGroup'" -ForegroundColor Red
    Write-Host "Please verify the names and try again." -ForegroundColor Red
    exit
}

# ============================================================================
# STEP 3: Collect Azure Storage Configuration Values
# ============================================================================
Write-Host "`n=== Step 3: Azure Storage Configuration ===" -ForegroundColor Cyan
Write-Host "These variables configure where prompt templates and logs are stored." -ForegroundColor Yellow

# Storage account name (where prompt templates are stored)
$StorageAccountName = Read-Host "`nEnter Storage Account name (for prompt templates and logs)"

# Resource group containing the storage account
$StorageResourceGroup = Read-Host "Enter Resource Group name (where Storage Account is located)"

# Container name for prompt templates
Write-Host "`nDefault prompt template container: 'templates'" -ForegroundColor Gray
$PromptContainerName = Read-Host "Enter Prompt Template Container name (press Enter for 'templates')"
if ([string]::IsNullOrWhiteSpace($PromptContainerName)) {
    $PromptContainerName = "templates"
}

# ============================================================================
# STEP 4: Collect ServiceNow OAuth Configuration
# ============================================================================
Write-Host "`n=== Step 4: ServiceNow OAuth Configuration ===" -ForegroundColor Cyan
Write-Host "These variables authenticate to ServiceNow API using OAuth 2.0." -ForegroundColor Yellow

# ServiceNow OAuth Client ID
$ServiceNowClientID = Read-Host "`nEnter ServiceNow OAuth Client ID"

# ServiceNow OAuth Client Secret (will be encrypted)
$ServiceNowClientSecret = Read-Host "Enter ServiceNow OAuth Client Secret (will be encrypted)" -AsSecureString

# ServiceNow OAuth Scope
Write-Host "`nDefault scope: 'useraccount'" -ForegroundColor Gray
$ServiceNowScope = Read-Host "Enter ServiceNow OAuth Scope (press Enter for 'useraccount')"
if ([string]::IsNullOrWhiteSpace($ServiceNowScope)) {
    $ServiceNowScope = "useraccount"
}

# ServiceNow Token URL
Write-Host "`nExample: https://your-instance.service-now.com/oauth_token.do" -ForegroundColor Gray
$TokenUrl = Read-Host "Enter ServiceNow Token URL"

# ============================================================================
# STEP 5: Collect ServiceNow API Endpoints
# ============================================================================
Write-Host "`n=== Step 5: ServiceNow API Endpoints ===" -ForegroundColor Cyan
Write-Host "These URLs point to ServiceNow incident and request APIs." -ForegroundColor Yellow

# ServiceNow Incidents API endpoint
Write-Host "`nExample: https://your-instance.service-now.com/api/now/table/incident" -ForegroundColor Gray
$ServiceNowIncidentsURL = Read-Host "Enter ServiceNow Incidents API URL"

# ServiceNow Requests API endpoint
Write-Host "`nExample: https://your-instance.service-now.com/api/now/table/sc_request" -ForegroundColor Gray
$ServiceNowRequestsURL = Read-Host "Enter ServiceNow Requests API URL"

# ============================================================================
# STEP 6: Collect Azure OpenAI / Azure AI Configuration
# ============================================================================
Write-Host "`n=== Step 6: Azure OpenAI / Azure AI Configuration ===" -ForegroundColor Cyan
Write-Host "These variables configure the AI model used for ticket categorization." -ForegroundColor Yellow

# Azure OpenAI Base URL
Write-Host "`nExample: https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com" -ForegroundColor Gray
$AzureOpenAIBaseUrl = Read-Host "Enter Azure OpenAI Base URL (endpoint)"

# Azure OpenAI model/deployment name
Write-Host "`nExample: gpt-5.4-mini" -ForegroundColor Gray
$AzureOpenAIModel = Read-Host "Enter Azure OpenAI model or deployment name"
if ([string]::IsNullOrWhiteSpace($AzureOpenAIModel)) {
    $AzureOpenAIModel = "gpt-5.4-mini"
}
$AzureOpenAIDeployment = $AzureOpenAIModel

# Azure OpenAI API Key (will be encrypted)
$AzureOpenAIApiKey = Read-Host "Enter Azure OpenAI API Key (will be encrypted)" -AsSecureString

# Azure OpenAI API Version
Write-Host "`nDefault API version: 2025-04-01-preview" -ForegroundColor Gray
$AzureOpenAIApiVersion = Read-Host "Enter Azure OpenAI API Version (press Enter for '2025-04-01-preview')"
if ([string]::IsNullOrWhiteSpace($AzureOpenAIApiVersion)) {
    $AzureOpenAIApiVersion = "2025-04-01-preview"
}

# ============================================================================
# STEP 7: Collect Logic App Webhook URL (Optional)
# ============================================================================
Write-Host "`n=== Step 7: Notification Configuration ===" -ForegroundColor Cyan
Write-Host "Optional: Logic App webhook URL for sending email notifications." -ForegroundColor Yellow

$LogicAppWebHookURL = Read-Host "`nEnter Logic App Webhook URL (press Enter to skip)"

# ============================================================================
# STEP 8: Summary and Confirmation
# ============================================================================
Write-Host "`n=== Step 8: Configuration Summary ===" -ForegroundColor Cyan
Write-Host "Review the configuration before creating variables:" -ForegroundColor Yellow
Write-Host ""
Write-Host "Automation Account:" -ForegroundColor White
Write-Host "  - Account Name: $AutomationAccountName" -ForegroundColor Gray
Write-Host "  - Resource Group: $AutomationResourceGroup" -ForegroundColor Gray
Write-Host ""
Write-Host "Azure Storage:" -ForegroundColor White
Write-Host "  - Storage Account: $StorageAccountName" -ForegroundColor Gray
Write-Host "  - Storage RG: $StorageResourceGroup" -ForegroundColor Gray
Write-Host "  - Prompt Container: $PromptContainerName" -ForegroundColor Gray
Write-Host ""
Write-Host "ServiceNow:" -ForegroundColor White
Write-Host "  - Client ID: $ServiceNowClientID" -ForegroundColor Gray
Write-Host "  - Scope: $ServiceNowScope" -ForegroundColor Gray
Write-Host "  - Token URL: $TokenUrl" -ForegroundColor Gray
Write-Host "  - Incidents URL: $ServiceNowIncidentsURL" -ForegroundColor Gray
Write-Host "  - Requests URL: $ServiceNowRequestsURL" -ForegroundColor Gray
Write-Host ""
Write-Host "Azure OpenAI:" -ForegroundColor White
Write-Host "  - Base URL: $AzureOpenAIBaseUrl" -ForegroundColor Gray
Write-Host "  - Model: $AzureOpenAIModel" -ForegroundColor Gray
Write-Host "  - API Version: $AzureOpenAIApiVersion" -ForegroundColor Gray
Write-Host ""
if (![string]::IsNullOrWhiteSpace($LogicAppWebHookURL)) {
    Write-Host "Logic App:" -ForegroundColor White
    Write-Host "  - Webhook URL: $LogicAppWebHookURL" -ForegroundColor Gray
    Write-Host ""
}

$confirm = Read-Host "Proceed with creating these variables? (Y/N)"
if ($confirm -ne 'Y' -and $confirm -ne 'y') {
    Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    exit
}

# ============================================================================
# STEP 9: Create Automation Variables
# ============================================================================
Write-Host "`n=== Step 9: Creating Automation Variables ===" -ForegroundColor Cyan
Write-Host "Creating 15 automation variables..." -ForegroundColor Yellow

# Helper function to create or update automation variables
function Set-AutomationVariableSafe {
    param(
        [string]$Name,
        [object]$Value,
        [bool]$Encrypted = $false,
        [string]$Description = ""
    )
    
    try {
        # Check if variable already exists
        $existing = Get-AzAutomationVariable -ResourceGroupName $AutomationResourceGroup `
                                             -AutomationAccountName $AutomationAccountName `
                                             -Name $Name `
                                             -ErrorAction SilentlyContinue
        
        if ($existing) {
            # Update existing variable
            Write-Host "  ↻ Updating: $Name" -ForegroundColor Yellow
            Set-AzAutomationVariable -ResourceGroupName $AutomationResourceGroup `
                                     -AutomationAccountName $AutomationAccountName `
                                     -Name $Name `
                                     -Value $Value `
                                     -Encrypted $Encrypted | Out-Null
        } else {
            # Create new variable
            Write-Host "  + Creating: $Name" -ForegroundColor Green
            New-AzAutomationVariable -ResourceGroupName $AutomationResourceGroup `
                                     -AutomationAccountName $AutomationAccountName `
                                     -Name $Name `
                                     -Value $Value `
                                     -Encrypted $Encrypted `
                                     -Description $Description | Out-Null
        }
        Write-Host "    ✓ Success" -ForegroundColor Green
    } catch {
        Write-Host "    ✗ Failed: $_" -ForegroundColor Red
    }
}

Write-Host "`n--- Azure Storage Variables ---" -ForegroundColor Cyan

# 1. Storage Account Name - Used to access Azure Storage for prompt templates and logs
Set-AutomationVariableSafe -Name "PSD_AI_Automations_StorageAccountName" `
                           -Value $StorageAccountName `
                           -Description "Storage account name for prompt templates and logs"

# 2. Prompt Template Container - Container where prompt template files are stored
Set-AutomationVariableSafe -Name "PSD-AI-Automations_PromptTemplateContainerName" `
                           -Value $PromptContainerName `
                           -Description "Container name for prompt template files"

# 3. Storage Resource Group - Resource group containing the storage account
Set-AutomationVariableSafe -Name "PSD_AI_Automations_ResourceGroupName" `
                           -Value $StorageResourceGroup `
                           -Description "Resource group containing the storage account"

Write-Host "`n--- ServiceNow OAuth Variables ---" -ForegroundColor Cyan

# 4. ServiceNow Client ID - OAuth client ID for ServiceNow authentication
Set-AutomationVariableSafe -Name "ServiceNowIncidentsClientID" `
                           -Value $ServiceNowClientID `
                           -Description "ServiceNow OAuth Client ID"

# 5. ServiceNow Client Secret - OAuth client secret (ENCRYPTED for security)
Set-AutomationVariableSafe -Name "ServiceNowIncidentsClientSecret" `
                           -Value $ServiceNowClientSecret `
                           -Encrypted $true `
                           -Description "ServiceNow OAuth Client Secret (encrypted)"

# 6. ServiceNow OAuth Scope - Defines access scope for ServiceNow API
Set-AutomationVariableSafe -Name "ServiceNowIncidentsScope" `
                           -Value $ServiceNowScope `
                           -Description "ServiceNow OAuth scope"

# 7. ServiceNow Token URL - Endpoint to obtain OAuth access tokens
Set-AutomationVariableSafe -Name "TokenUrl" `
                           -Value $TokenUrl `
                           -Description "ServiceNow OAuth token endpoint"

Write-Host "`n--- ServiceNow API Endpoint Variables ---" -ForegroundColor Cyan

# 8. ServiceNow Incidents URL - API endpoint to retrieve incident records
Set-AutomationVariableSafe -Name "ServiceNowIncidentsURL" `
                           -Value $ServiceNowIncidentsURL `
                           -Description "ServiceNow incidents API endpoint"

# 9. ServiceNow Requests URL - API endpoint to retrieve service request records
Set-AutomationVariableSafe -Name "ServiceNowRequestsURL" `
                           -Value $ServiceNowRequestsURL `
                           -Description "ServiceNow requests API endpoint"

Write-Host "`n--- Azure OpenAI / AI Configuration Variables ---" -ForegroundColor Cyan

# 10. Azure OpenAI Base URL - Your Azure OpenAI resource endpoint
Set-AutomationVariableSafe -Name "AzureOpenAIBaseUrl" `
                           -Value $AzureOpenAIBaseUrl `
                           -Description "Azure OpenAI endpoint URL"

# 11. Azure OpenAI Deployment - Name of your deployed AI model
Set-AutomationVariableSafe -Name "AzureOpenAIDeployment" `
                           -Value $AzureOpenAIDeployment `
                           -Description "Azure OpenAI deployment/model name"

# 12. Azure OpenAI Model - Name sent in the Responses API request body
Set-AutomationVariableSafe -Name "AzureOpenAIModel" `
                           -Value $AzureOpenAIModel `
                           -Description "Azure OpenAI model name for Responses API"

# 13. Azure OpenAI API Key - Authentication key for Azure OpenAI (ENCRYPTED for security)
Set-AutomationVariableSafe -Name "AzureOpenAIApiKey" `
                           -Value $AzureOpenAIApiKey `
                           -Encrypted $true `
                           -Description "Azure OpenAI API key (encrypted)"

# 14. Azure OpenAI API Version - API version for Azure OpenAI service
Set-AutomationVariableSafe -Name "AzureOpenAIApiVersion" `
                           -Value $AzureOpenAIApiVersion `
                           -Description "Azure OpenAI API version"

Write-Host "`n--- Notification Configuration Variables ---" -ForegroundColor Cyan

# 15. Logic App Webhook URL - URL to trigger email notifications via Logic App
if (![string]::IsNullOrWhiteSpace($LogicAppWebHookURL)) {
    Set-AutomationVariableSafe -Name "LogicAppSendAIEmailWebHookURL" `
                               -Value $LogicAppWebHookURL `
                               -Description "Logic App webhook URL for email notifications"
} else {
    Write-Host "  - Skipping: LogicAppSendAIEmailWebHookURL (not provided)" -ForegroundColor Gray
}

# ============================================================================
# STEP 10: Verification
# ============================================================================
Write-Host "`n=== Step 10: Verification ===" -ForegroundColor Cyan
Write-Host "Retrieving all automation variables to verify creation..." -ForegroundColor Yellow

try {
    $allVariables = Get-AzAutomationVariable -ResourceGroupName $AutomationResourceGroup `
                                             -AutomationAccountName $AutomationAccountName
    
    Write-Host "`nAll Automation Variables in account:" -ForegroundColor White
    $allVariables | Select-Object Name, @{Name="Encrypted";Expression={$_.Encrypted}} | Format-Table -AutoSize
    
    # Check for required variables
    $requiredVars = @(
        "PSD_AI_Automations_StorageAccountName",
        "PSD-AI-Automations_PromptTemplateContainerName",
        "PSD_AI_Automations_ResourceGroupName",
        "ServiceNowIncidentsClientID",
        "ServiceNowIncidentsClientSecret",
        "ServiceNowIncidentsScope",
        "TokenUrl",
        "AzureOpenAIBaseUrl",
        "AzureOpenAIModel",
        "AzureOpenAIDeployment",
        "AzureOpenAIApiKey",
        "AzureOpenAIApiVersion",
        "ServiceNowIncidentsURL",
        "ServiceNowRequestsURL"
    )
    
    $missingVars = @()
    foreach ($varName in $requiredVars) {
        if ($allVariables.Name -notcontains $varName) {
            $missingVars += $varName
        }
    }
    
    if ($missingVars.Count -eq 0) {
        Write-Host "`n✓ All required variables created successfully!" -ForegroundColor Green
    } else {
        Write-Host "`n✗ Missing variables:" -ForegroundColor Red
        $missingVars | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }
    
} catch {
    Write-Host "Error retrieving variables: $_" -ForegroundColor Red
}

# ============================================================================
# STEP 11: Next Steps
# ============================================================================
Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Upload prompt template files to storage container: $PromptContainerName" -ForegroundColor Yellow
Write-Host "   Required files:" -ForegroundColor Yellow
Write-Host "   - ProductivityTools_TicketCategorisation.md" -ForegroundColor Gray
Write-Host "   - ProductivityTools_WorkNotesCleanup.md" -ForegroundColor Gray
Write-Host "   - ProductivityTools_WorkNotesSummary.md" -ForegroundColor Gray
Write-Host "   - ProductivityTools_EnvironmentContext.md" -ForegroundColor Gray
Write-Host "   - ProductivityTools_PortfolioSummary.md" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Import the incident-analyzer-rb.ps1 runbook to your Automation Account" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. Ensure the Automation Account has required modules:" -ForegroundColor Yellow
Write-Host "   - Az.Storage (version 8.0.0 or higher)" -ForegroundColor Gray
Write-Host "   - Az.Accounts (version 4.0.0 or higher)" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Configure Managed Identity or Run As Account for Azure Storage access" -ForegroundColor Yellow
Write-Host ""
Write-Host "5. Test the runbook with a small date range to verify configuration" -ForegroundColor Yellow
Write-Host ""
Write-Host "Setup complete! ✓" -ForegroundColor Green
