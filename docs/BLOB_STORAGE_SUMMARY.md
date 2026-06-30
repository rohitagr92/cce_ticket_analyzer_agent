# Blob Storage Integration - Implementation Summary

## Overview
Added blob storage support for "data" and "results" containers to enable Azure Automation to save raw incident data and HTML reports, matching local development folder structure.

## Changes Made

### 1. Files Modified
.\Publish-runbook.ps1 -SourceFile incident-analyzer-rb-debug.ps1
**Location:** Line ~20-27 (BlobConfig section)

For the daily reconciliation/auto-heal flow, use:
```powershell
.\publish\Publish-ReconcileRunbook.ps1
```

That publisher republishes `incident-reconcile-rb-prodtools`, links the daily schedule, and attempts to grant the Automation Account managed identity the permission needed to start the backfill runbook during auto-heal.

**Added:**
```powershell
$Script:BlobConfig = @{
    StorageAccountName = Get-AutomationVariable -Name "Incidents_analyzer_StorageAccountName"
    PromptContainerName = Get-AutomationVariable -Name "Incidents_analyzer_PromptTemplateContainerName"
    ResourceGroupName = Get-AutomationVariable -Name "Incidents_analyzer_ResourceGroupName"
    DataContainerName = Get-AutomationVariable -Name "Incidents_analyzer_DataContainerName"        # NEW
    ResultsContainerName = Get-AutomationVariable -Name "Incidents_analyzer_ResultsContainerName"  # NEW
    SubscriptionId = Get-AutomationVariable -Name "Incidents_analyzer_SubscriptionId"              # ADDED
}
```


### Daily Reconcile
4. ✅ **Run daily reconcile:** `\.\publish\Publish-ReconcileRunbook.ps1`
**Location:** Added at start of Core Utility Functions region

**Purpose:** 
- Centralized Azure Storage authentication
- Reusable across all blob operations
- Handles managed identity authentication
- Sets subscription context

**Code:**
```powershell
function Get-StorageContext {
    [CmdletBinding()]
    param()
    
    try {
        # Ensure we have a valid Azure context
        $azContext = Get-AzContext
        if (-not $azContext) {
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        }
        
        # Set subscription context if configured
        if ($Script:BlobConfig.SubscriptionId) {
            Set-AzContext -SubscriptionId $Script:BlobConfig.SubscriptionId -ErrorAction Stop | Out-Null
        }
        
        # Get storage account key for authentication
        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $Script:BlobConfig.ResourceGroupName -Name $Script:BlobConfig.StorageAccountName)[0].Value
        $storageContext = New-AzStorageContext -StorageAccountName $Script:BlobConfig.StorageAccountName -StorageAccountKey $storageKey
        
        return $storageContext
    } catch {
        Write-ScriptLog "Failed to get storage context: $($_.Exception.Message)" -Level Error
        throw
    }
}
```

### C. Enhanced Save-IncidentsData Function
**Replaced:** `Save-IncidentsToLocal` (old name)  
**New Name:** `Save-IncidentsData`

**Features:**
- ✅ Environment detection (Azure vs Local)
- ✅ Azure: Saves to blob storage "data" container
- ✅ Local: Saves to .\data folder
- ✅ Automatic temp file cleanup
- ✅ Consistent file naming: incidents_yyyy-MM-dd_HH-mm-ss.json

**Behavior:**
| Environment | Storage Location | Method |
|------------|------------------|--------|
| Azure Automation | Blob: data container | Upload via temp file |
| Local Development | Folder: .\data | Direct file write |

### D. Enhanced Get-StoredIncidents Function
**Features:**
- ✅ Supports blob storage in Azure
- ✅ Supports local files in development
- ✅ Can specify filename or use latest
- ✅ Lists available files from appropriate source

**Behavior:**
| Environment | Source | Latest Selection |
|------------|---------|------------------|
| Azure Automation | Blob container | Sort by LastModified descending |
| Local Development | .\data folder | Sort by LastWriteTime descending |

### E. Enhanced Get-AvailableIncidentFiles Function
**Features:**
- ✅ Lists files from blob storage (Azure)
- ✅ Lists files from local folder (Development)
- ✅ Formatted output with timestamps and file sizes
- ✅ Graceful error handling

### F. Enhanced Report Saving Logic
**Location:** Near end of script, report generation section

**Features:**
- ✅ Azure: Saves to "results" blob container
- ✅ Local: Saves to .\results folder
- ✅ Sanitized filenames from dynamic subject
- ✅ Always saves in Azure (audit trail)
- ✅ Only saves locally if SaveRawDataLocally = $true

**Behavior:**
```powershell
if ($webhookUrl) {
    # Send via webhook (email delivery)
} else {
    if ($Script:IsAzureAutomation) {
        # Save to results blob container
    } else {
        # Save to .\results folder
    }
}
```

### G. Updated Save Incidents Call
**Location:** ServiceNow data retrieval section

**Old:**
```powershell
if ($Script:Constants.SaveRawDataLocally -and -not $Script:IsAzureAutomation) {
    Save-IncidentsToLocal -Incidents $incidents | Out-Null
}
```

**New:**
```powershell
if ($Script:Constants.SaveRawDataLocally -and -not $Script:IsAzureAutomation) {
    Save-IncidentsData -Incidents $incidents | Out-Null
} elseif ($Script:IsAzureAutomation) {
    # Always save to blob in Azure Automation for audit trail
    Save-IncidentsData -Incidents $incidents | Out-Null
}
```

**Key Change:** Azure Automation ALWAYS saves raw data to blob (audit trail), regardless of SaveRawDataLocally setting.

## New Automation Variables Required

| Variable Name | Value | Encrypted | Purpose |
|--------------|-------|-----------|---------|
| Incidents_analyzer_DataContainerName | `data` | No | Container for raw incident JSON files |
| Incidents_analyzer_ResultsContainerName | `results` | No | Container for HTML report files |

## Blob Container Structure

### Storage Account: incidentsanalyzersa

```
📦 incidentsanalyzersa (Storage Account)
├── 📁 templates (Existing - AI prompts)
├── 📁 logs (Existing - Execution logs)
├── 📁 mdm-ai-reports (Existing - Legacy reports)
├── 📁 data (NEW - Raw incident data)
│   ├── incidents_2026-01-28_14-30-15.json
│   ├── incidents_2026-01-27_08-15-22.json
│   └── incidents_2026-01-26_09-45-33.json
└── 📁 results (NEW - HTML reports)
    ├── MDM_AI_Analysis_Report_50_Incidents_5_Categories_Live_API_28_Jan.html
    ├── MDM_AI_Analysis_Report_45_Incidents_6_Categories_Live_API_27_Jan.html
    └── MDM_AI_Analysis_Report_38_Incidents_4_Categories_Live_API_26_Jan.html
```

## Deployment Steps

### Step 1: Add Automation Variables
Run the helper script to add the new automation variables:

```powershell
.\Add-BlobStorageVariables.ps1
```

**What it does:**
- Authenticates to Azure (device code if needed)
- Creates or updates Incidents_analyzer_DataContainerName variable
- Creates or updates Incidents_analyzer_ResultsContainerName variable
- Provides next steps guidance

**Default Values:**
- DataContainerName: "data"
- ResultsContainerName: "results"

### Step 2: Create Blob Containers
Run the helper script to create the containers in your storage account:

```powershell
.\Create-BlobContainers.ps1
```

**What it does:**

**Container Access Level:** Private (Off)

### Step 3: Republish Runbook
Publish the updated runbook to Azure Automation:

```powershell
.\Publish-runbook.ps1
```

Or for debug version:
```powershell
.\Publish-runbook.ps1 -SourceFile incident-analyzer-rb-debug.ps1
```

For the daily reconciliation/auto-heal flow, use:
```powershell
.\publish\Publish-ReconcileRunbook.ps1
```

That publisher republishes `incident-reconcile-rb-prodtools`, links the daily schedule, and attempts to grant the Automation Account managed identity the permission needed to start the backfill runbook during auto-heal.

### Step 4: Test in Azure Automation
1. Navigate to Azure Portal → Automation Account → Runbooks
2. Select incident-analyzer-rb
3. Click "Test pane"
4. Click "Start"
5. Monitor execution logs

**Expected Behavior:**
- ✅ Raw incident data saved to "data" container
- ✅ HTML report saved to "results" container (if no webhook)
- ✅ Execution logs saved to "logs" container
- ✅ No errors related to blob storage

### Daily Reconcile
Run the reconcile publisher after the runbook has been imported:

```powershell
.\publish\Publish-ReconcileRunbook.ps1
```

## Verification

### Check Automation Variables
```powershell
$rg = "Incidents-analyzer-rg"
$aa = "incident-analyzer-aa"

Get-AzAutomationVariable -ResourceGroupName $rg -AutomationAccountName $aa | 
    Where-Object { $_.Name -like "*Container*" } | 
    Select-Object Name, Value
```

**Expected Output:**
```
Name                                      Value
----                                      -----
Incidents_analyzer_PromptTemplateContainerName    templates
Incidents_analyzer_DataContainerName              data
Incidents_analyzer_ResultsContainerName           results
```

### Check Blob Containers
```powershell
$storageAccountName = "incidentsanalyzersa"
$resourceGroup = "Incidents-analyzer-rg"

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey

Get-AzStorageContainer -Context $ctx | 
    Select-Object Name, LastModified, PublicAccess
```

**Expected Output:**
```
Name                LastModified                PublicAccess
----                ------------                ------------
templates           1/15/2026 10:30:00 AM       Off
logs                1/28/2026 2:45:00 PM        Off
mdm-ai-reports      1/20/2026 8:15:00 AM        Off
data                1/28/2026 3:10:00 PM        Off  ← NEW
results             1/28/2026 3:10:00 PM        Off  ← NEW
```

### Check Saved Data After Runbook Execution
```powershell
# List files in data container
Get-AzStorageBlob -Container "data" -Context $ctx | 
    Select-Object Name, LastModified, Length | 
    Sort-Object LastModified -Descending

# List files in results container
Get-AzStorageBlob -Container "results" -Context $ctx | 
    Select-Object Name, LastModified, Length | 
    Sort-Object LastModified -Descending
```

## Testing Scenarios

### Scenario 1: Live API with Webhook (Production)
**Config:**
- UseStoredIncidents = $false
- LogicAppSendAIEmailWebHookURL = (configured)

**Expected:**
- ✅ Fetches incidents from ServiceNow API
- ✅ Saves raw data to "data" blob container
- ✅ Processes with AI
- ✅ Sends report via webhook (email)
- ✅ Does NOT save to "results" container

### Scenario 2: Live API without Webhook (Testing)
**Config:**
- UseStoredIncidents = $false
- LogicAppSendAIEmailWebHookURL = (empty/not configured)

**Expected:**
- ✅ Fetches incidents from ServiceNow API
- ✅ Saves raw data to "data" blob container
- ✅ Processes with AI
- ✅ Saves HTML report to "results" blob container
- ✅ No email sent

### Scenario 3: Stored Data Testing
**Config:**
- UseStoredIncidents = $true
- StoredDataFileName = "incidents_2026-01-27_08-15-22.json"

**Expected:**
- ✅ Loads incidents from "data" blob container
- ✅ Does NOT fetch from ServiceNow API
- ✅ Processes with AI
- ✅ Saves report based on webhook config
- ✅ Useful for testing without consuming API quota

## Local Development Compatibility

**No changes needed** for local development:
- ✅ .\data folder still works as before
- ✅ .\results folder still works as before
- ✅ LocalConfig.psd1 unchanged
- ✅ All existing functionality preserved

**Environment Detection:**
```powershell
$Script:IsAzureAutomation = $env:AUTOMATION_ASSET_ACCOUNTID -or $PSPrivateMetadata.JobId
```

## Benefits

### 1. Audit Trail
- **Raw Data:** Every execution saves incident data to blob
- **Reports:** HTML reports saved when no webhook configured
- **Logs:** Execution logs already saved to "logs" container

### 2. Debugging
- **Load Stored Data:** Test AI processing without API calls
- **Review Raw Data:** Inspect incident data that caused issues
- **Compare Reports:** Track changes in categorization over time

### 3. Cost Optimization
- **API Quota:** Test with stored data to avoid API rate limits
- **Development:** Use stored data for testing new prompts/logic

### 4. Compliance
- **Data Retention:** Automatic backup of processed incidents
- **Traceability:** Link reports back to original data
- **Reproducibility:** Re-run analysis on historical data

## Troubleshooting

### Issue: "Failed to get storage context"
**Cause:** Managed identity doesn't have permissions

**Solution:**
```powershell
$automationAccount = Get-AzAutomationAccount -ResourceGroupName "Incidents-analyzer-rg" -Name "incident-analyzer-aa"
$identityId = $automationAccount.Identity.PrincipalId

# Check current permissions
Get-AzRoleAssignment -ObjectId $identityId

# Add Contributor role (if missing)
New-AzRoleAssignment -ObjectId $identityId `
    -RoleDefinitionName "Contributor" `
    -ResourceGroupName "Incidents-analyzer-rg"
```

### Issue: "Container not found"
**Cause:** Blob containers don't exist

**Solution:**
```powershell
.\Create-BlobContainers.ps1
```

### Issue: "Automation variable not found"
**Cause:** New variables not created

**Solution:**
```powershell
.\Add-BlobStorageVariables.ps1
```

### Issue: "Access Denied" when accessing blobs
**Cause:** Subscription context not set

**Solution:** Ensure Incidents_analyzer_SubscriptionId variable is configured:
```powershell
$subscriptionId = (Get-AzSubscription | Out-GridView -PassThru).Id

Set-AzAutomationVariable -ResourceGroupName "Incidents-analyzer-rg" `
    -AutomationAccountName "incident-analyzer-aa" `
    -Name "Incidents_analyzer_SubscriptionId" `
    -Value $subscriptionId `
    -Encrypted $false
```

## File Manifest

### Modified Files
- ✅ incident-analyzer-rb-debug.ps1 (1853 lines → 1920+ lines)
- ✅ incident-analyzer-rb.ps1 (1703 lines → 1770+ lines)

### New Files
- ✅ Add-BlobStorageVariables.ps1 (142 lines)
- ✅ Create-BlobContainers.ps1 (203 lines)
- ✅ BLOB_STORAGE_SUMMARY.md (this file)

## Summary Statistics

**Lines Added:** ~300+ lines (across both runbook files)
**New Functions:** 1 (Get-StorageContext)
**Enhanced Functions:** 3 (Save-IncidentsData, Get-StoredIncidents, Get-AvailableIncidentFiles)
**New Automation Variables:** 2 (DataContainerName, ResultsContainerName)
**New Blob Containers:** 2 (data, results)
**Helper Scripts:** 2 (Add-BlobStorageVariables.ps1, Create-BlobContainers.ps1)

## Next Steps

1. ✅ **Run:** `.\Add-BlobStorageVariables.ps1`
2. ✅ **Run:** `.\Create-BlobContainers.ps1`
3. ✅ **Run:** `.\Publish-runbook.ps1`
4. ⏳ **Test:** Run runbook in Azure Automation
5. ⏳ **Verify:** Check "data" and "results" containers for files
6. ⏳ **Monitor:** Review execution logs for any blob storage errors

---

**Implementation Date:** January 28, 2026  
**Status:** ✅ Complete - Ready for deployment  
**Tested:** ⏳ Pending Azure deployment and testing
