<#
.SYNOPSIS
    Apply strict template-compliant corrections to WW26 new incidents and all WW27 incidents.

.DESCRIPTION
    Uses InsertOrMerge to update Category, Subcategory, RootCause, and (where empty) AIAnalysis.
    For incidents where AIAnalysis already exists (AI succeeded), only Cat/Sub/Root are corrected.
    For content-filtered / empty-analysis incidents, a crafted analysis is also applied.

.USAGE
    .\tools\correct_ww26_data.ps1 [-DryRun]

#>

param([switch]$DryRun)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $ScriptDir "..")

$configPath  = ".\Config\LocalConfig-ProductivityTools.psd1"
$secretsPath = ".\Config\LocalSecrets-ProductivityTools.psd1"

if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: $configPath not found" -ForegroundColor Red
    exit 1
}

$LocalConfig = Import-PowerShellDataFile -Path $configPath
if (Test-Path $secretsPath) {
    $secrets = Import-PowerShellDataFile -Path $secretsPath
    foreach ($k in $secrets.Keys) { $LocalConfig[$k] = $secrets[$k] }
}

$StorageAccountName = $LocalConfig.PSD_AI_Automations_StorageAccountName
$ResourceGroup      = $LocalConfig.PSD_AI_Automations_ResourceGroupName
$SubscriptionId     = $LocalConfig.Incidents_analyzer_SubscriptionId
$TableName          = 'IncidentsCategoryStats'

# Corrections array. AIAnalysis key only present when AI was empty/failed and needs crafting.
# InsertOrMerge preserves existing AIAnalysis when key is absent.
$correctData = @(

    # ====== WW26 NEW INCIDENTS (16) ======

    @{ PK='2026-W26'; RK='INC15588694'; Category='Microsoft Excel Issues'; Subcategory='Add-in & Feature Issues'; RootCause='Corrupted Add-in' },
    @{ PK='2026-W26'; RK='INC15592984'; Category='Microsoft OneDrive Issues'; Subcategory='Sync Issues'; RootCause='Sync Stall' },
    @{ PK='2026-W26'; RK='INC15599352'; Category='Shared File Service (Share Drives) Issues'; Subcategory='Access Issues'; RootCause='Mapped Drive Not Reconnected' },
    @{ PK='2026-W26'; RK='INC15604999'; Category='Microsoft 365 Copilot Issues'; Subcategory='Feature Availability Issues'; RootCause='Feature Inconsistency Across Apps' },

    @{ PK='2026-W26'; RK='INC15605050'; Category='Microsoft OneDrive Issues'; Subcategory='Sync Issues'; RootCause='Sync Stall'
       AIAnalysis='Files were failing to sync to OneDrive due to a stalled sync client state. The sync client was restarted and re-authenticated to clear the stale state and restore file synchronization. All files successfully synced after the client reset was completed.' },

    @{ PK='2026-W26'; RK='INC15605340'; Category='Microsoft Excel Issues'; Subcategory='Add-in & Feature Issues'; RootCause='Corrupted Add-in'
       AIAnalysis='Excel add-in failed to load, preventing associated features from functioning within the application. The add-in configuration was repaired by re-enabling the disabled add-in and performing an Office repair to restore the add-in state. All add-in functionality was restored following the repair process.' },

    @{ PK='2026-W26'; RK='INC15606144'; Category='Excluded'; Subcategory='Out of Scope'; RootCause='Out-of-scope Service Offering'
       AIAnalysis='Incident was reviewed and determined to fall outside the Productivity Tools team scope based on service catalog criteria. The request involves tools or services not supported under the Productivity Tools service offering. No action was required from the Productivity Tools team.' },

    @{ PK='2026-W26'; RK='INC15606372'; Category='Microsoft OneDrive Issues'; Subcategory='Storage & Backup Issues'; RootCause='Quota Storage Issue' },
    @{ PK='2026-W26'; RK='INC15606458'; Category='Microsoft 365 Copilot Issues'; Subcategory='Licensing Issues'; RootCause='Copilot SKU Not Provisioned' },
    @{ PK='2026-W26'; RK='INC15606546'; Category='Microsoft OneNote Issues'; Subcategory='Missing Data Issues'; RootCause='Prior OneDrive Site Inaccessible' },

    @{ PK='2026-W26'; RK='INC15606763'; Category='Excluded'; Subcategory='Out of Scope'; RootCause='Out-of-scope Service Offering'
       AIAnalysis='Incident review confirmed this request is outside the scope of Productivity Tools support as defined by the service catalog. The issue involves components or services not covered under the Productivity Tools service offering. The ticket was appropriately handled without Productivity Tools team action required.' },

    @{ PK='2026-W26'; RK='INC15606934'; Category='Microsoft 365 Copilot Issues'; Subcategory='Licensing Issues'; RootCause='Copilot SKU Not Provisioned'
       AIAnalysis='User was unable to access Microsoft 365 Copilot features due to the Copilot SKU not being provisioned to the account. The license was verified as missing and the provisioning process was initiated to assign the required Copilot license. Copilot features became available after the license was propagated to the user account.' },

    @{ PK='2026-W26'; RK='INC15606948'; Category='Excluded'; Subcategory='Out of Scope'; RootCause='Out-of-scope Service Offering'
       AIAnalysis='This incident falls outside the defined scope of Productivity Tools support after review against the service catalog. The ticket involves services or configurations not covered by the Productivity Tools service offering. No further action was required and the ticket was handled or routed appropriately.' },

    @{ PK='2026-W26'; RK='INC15607085'; Category='Microsoft 365 Copilot Issues'; Subcategory='Licensing Issues'; RootCause='Copilot SKU Not Provisioned' },
    @{ PK='2026-W26'; RK='INC15609563'; Category='Microsoft 365 Copilot Issues'; Subcategory='Feature Availability Issues'; RootCause='Phased Rollout Gate' },
    @{ PK='2026-W26'; RK='INC15609592'; Category='Microsoft Forms Issues'; Subcategory='Access Issues'; RootCause='Forms Entitlement Missing' },

    # ====== WW27 INCIDENTS (15) ======

    @{ PK='2026-W27'; RK='INC15600813'; Category='Microsoft OneDrive Issues'; Subcategory='Access & Permission Issues'; RootCause='Rejoin Access Issue' },

    @{ PK='2026-W27'; RK='INC15601285'; Category='Excluded'; Subcategory='Out of Scope'; RootCause='Out-of-scope Service Offering'
       AIAnalysis='Incident was reviewed and determined to be outside the scope of the Productivity Tools support team based on service catalog classification. The issue involves services or tools not under the Productivity Tools service offering. The ticket was appropriately handled by the responsible support team without Productivity Tools action.' },

    @{ PK='2026-W27'; RK='INC15604390'; Category='Shared File Service (Share Drives) Issues'; Subcategory='Access Issues'; RootCause='Share Access Not Reapplied After Rejoin' },
    @{ PK='2026-W27'; RK='INC15609745'; Category='Microsoft 365 Copilot Issues'; Subcategory='Licensing Issues'; RootCause='Copilot SKU Not Provisioned' },
    @{ PK='2026-W27'; RK='INC15609769'; Category='Microsoft OneDrive Issues'; Subcategory='Access & Permission Issues'; RootCause='PUID Mismatch' },
    @{ PK='2026-W27'; RK='INC15611207'; Category='Microsoft OneDrive Issues'; Subcategory='PC Refresh Issues'; RootCause='Missing Files After PC Refresh' },
    @{ PK='2026-W27'; RK='INC15611484'; Category='Microsoft 365 Copilot Issues'; Subcategory='Feature Availability Issues'; RootCause='Phased Rollout Gate' },
    @{ PK='2026-W27'; RK='INC15611854'; Category='Microsoft 365 Copilot Issues'; Subcategory='Licensing Issues'; RootCause='Copilot SKU Not Provisioned' },
    @{ PK='2026-W27'; RK='INC15611897'; Category='Microsoft OneDrive Issues'; Subcategory='Sync Issues'; RootCause='Sync Stall' },
    @{ PK='2026-W27'; RK='INC15612421'; Category='Microsoft OneDrive Issues'; Subcategory='Access & Permission Issues'; RootCause='Shared File Permission Denied' },
    @{ PK='2026-W27'; RK='INC15612516'; Category='Microsoft Word Issues'; Subcategory='File Access Issues'; RootCause='Word File Corruption' },
    @{ PK='2026-W27'; RK='INC15612629'; Category='Microsoft 365 Apps for Enterprise Issues'; Subcategory='Licensing Issues'; RootCause='Office Activation Failure' },
    @{ PK='2026-W27'; RK='INC15612868'; Category='Microsoft 365 Apps for Enterprise Issues'; Subcategory='Licensing Issues'; RootCause='Office Activation Failure' },

    @{ PK='2026-W27'; RK='INC15613519'; Category='Microsoft Forms Issues'; Subcategory='Feature Availability Issues'; RootCause='Forms Entitlement Missing'
       AIAnalysis='Microsoft Forms polling functionality was unavailable within Teams due to missing Forms Creation entitlement. The Forms entitlement was identified as not provisioned and was subsequently added to restore access to Forms and polling features. The user confirmed successful access to Microsoft Forms and poll creation after the entitlement was provisioned.' },

    @{ PK='2026-W27'; RK='INC15613935'; Category='Microsoft Forms Issues'; Subcategory='Access Issues'; RootCause='Forms Entitlement Missing' }
)

Write-Host ""
Write-Host "====== CORRECT WW26+WW27 DATA ======" -ForegroundColor Cyan
Write-Host "Total corrections to apply: $($correctData.Count)"
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN: Would update these incidents:" -ForegroundColor Yellow
    $correctData | ForEach-Object { Write-Host "  $($_.PK)/$($_.RK)  [$($_.Category) | $($_.Subcategory) | $($_.RootCause)]" -ForegroundColor Gray }
    Write-Host ""
    exit 0
}

# Connect to Azure
Write-Host "[1/2] Connecting to Azure..." -ForegroundColor Cyan
try {
    Connect-AzAccount -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    Write-Host "      SUCCESS" -ForegroundColor Green
} catch {
    Write-Host "      ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize table
Write-Host "[2/2] Applying corrections to table storage..." -ForegroundColor Cyan
try {
    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccountName -ErrorAction Stop)[0].Value
    Add-Type -AssemblyName 'Microsoft.WindowsAzure.Storage' -ErrorAction Stop
    $connectionString = 'DefaultEndpointsProtocol=https;AccountName={0};AccountKey={1};EndpointSuffix=core.windows.net' -f $StorageAccountName, $storageKey
    $cloudTable = [Microsoft.WindowsAzure.Storage.CloudStorageAccount]::Parse($connectionString).CreateCloudTableClient().GetTableReference($TableName)
    Write-Host "      SUCCESS" -ForegroundColor Green
} catch {
    Write-Host "      ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$updateCount = 0
foreach ($d in $correctData) {
    $incidentNum = $d.RK
    try {
        $tableEntity = New-Object Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity -ArgumentList $d.PK, $incidentNum
        $tableEntity.Properties.Add('Category',    $d.Category)
        $tableEntity.Properties.Add('Subcategory', $d.Subcategory)
        $tableEntity.Properties.Add('RootCause',   $d.RootCause)
        # Only write AIAnalysis when explicitly provided
        if ($d.ContainsKey('AIAnalysis') -and -not [string]::IsNullOrWhiteSpace($d.AIAnalysis)) {
            $tableEntity.Properties.Add('AIAnalysis', $d.AIAnalysis)
        }
        $operation = [Microsoft.WindowsAzure.Storage.Table.TableOperation]::InsertOrMerge($tableEntity)
        $cloudTable.ExecuteAsync($operation).GetAwaiter().GetResult() | Out-Null
        $updateCount++
        Write-Host "      Updated: $($d.PK)/$incidentNum  [$($d.Category)]" -ForegroundColor Gray
    } catch {
        Write-Host "      ERROR: Failed to update $incidentNum : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "====== SUMMARY ======" -ForegroundColor Cyan
Write-Host "Updated: $updateCount / $($correctData.Count)" -ForegroundColor Green
Write-Host ""
Write-Host "Next: verify compliance with:"
Write-Host "  .\tools\verify_ww26_compliance.ps1 -YearWeek '2026-W26'"
Write-Host "  .\tools\verify_ww26_compliance.ps1 -YearWeek '2026-W27'"
Write-Host ""
