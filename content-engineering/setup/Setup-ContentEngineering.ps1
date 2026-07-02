<#
.SYNOPSIS
    One-stop setup script to onboard the Content Engineering service offering.

.DESCRIPTION
    Runs all Azure provisioning steps needed before the Content Engineering
    runbooks can execute:

    Phase 1 – Storage account, blob containers, Azure Table
    Phase 2 – IAM role assignments for the Automation Account managed identity
    Phase 3 – Azure Automation variables (ContentEng_ prefix)

    Sensitive values (secrets, API keys) are collected via Read-Host -AsSecureString
    and stored as encrypted Automation variables.

.PARAMETER DryRun
    Print what would be done without making any changes.

.EXAMPLE
    .\Setup-ContentEngineering.ps1
    .\Setup-ContentEngineering.ps1 -DryRun

.NOTES
    Run once per environment. Safe to re-run — existing variables are updated
    only when you confirm the prompt. Existing storage/table resources are skipped.
#>

param(
    [switch]$DryRun
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# ── Constants ─────────────────────────────────────────────────────────────────
$SubscriptionId          = '1c6d384e-bc83-4b02-859c-76eeb87f7676'
$ResourceGroupName       = 'OPSW-Ticket-Analyzer'
$AutomationAccountName   = 'OPSW-ProductivityTools-account'
$StorageAccountName      = 'opswcontentenggblob'
$StorageRegion           = 'eastus'

$BusinessServiceId       = 'a1de2ff2db8f50108062531dd3961911'   # End-User Collaboration (shared with PT)
$ServiceOfferingId       = 'ce614555dbeb5c105447610ed39619f8'   # Content Engineering

$TableName               = 'IncidentsCategoryStats'
$Containers              = @('templates', 'data', 'logs', 'results')

$AzureOpenAIBaseUrl      = 'https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com'
$AzureOpenAIDeployment   = 'gpt-5.4-mini'
$AzureOpenAIApiVersion   = '2025-04-01-preview'

$TokenUrl                = 'https://apis.intel.com/v1/auth/token'

# ServiceNow incidents URL scoped to Content Engineering (business_service + service_offering)
$ServiceNowIncidentsURL  = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=business_service=a1de2ff2db8f50108062531dd3961911^service_offering=ce614555dbeb5c105447610ed39619f8^stateIN6,7^ORDERBYDESCresolved_at&sysparm_display_value=true&sysparm_limit=1000"
$ServiceNowRequestsURL   = "https://apis.intel.com/itsm/api/now/table/sc_task?sysparm_query=business_service=$BusinessServiceId^service_offering=$ServiceOfferingId^stateIN6,7^ORDERBYDESCresolved_at&sysparm_display_value=true&sysparm_limit=1000"

# ── Helpers ───────────────────────────────────────────────────────────────────
function Write-Step { param([string]$Msg) Write-Host "`n=== $Msg ===" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  [OK]  $Msg" -ForegroundColor Green }
function Write-Skip { param([string]$Msg) Write-Host "  [--]  $Msg" -ForegroundColor Yellow }
function Write-Info { param([string]$Msg) Write-Host "        $Msg" -ForegroundColor Gray }

function Set-AutoVar {
    param(
        [string]$Name,
        [object]$Value,
        [bool]$Encrypted = $false
    )
    if ($DryRun) { Write-Skip "DRY-RUN  Set-AzAutomationVariable  $Name"; return }

    $existing = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName -Name $Name -ErrorAction SilentlyContinue

    if ($existing) {
        Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name $Name -Value $Value -Encrypted $Encrypted | Out-Null
        Write-Ok "Updated  $Name"
    } else {
        New-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name $Name -Value $Value -Encrypted $Encrypted | Out-Null
        Write-Ok "Created  $Name"
    }
}

function Set-AutoVarSecure {
    param([string]$Name, [securestring]$SecureValue)
    if ($DryRun) { Write-Skip "DRY-RUN  Set-AzAutomationVariable (encrypted)  $Name"; return }

    $existing = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName -Name $Name -ErrorAction SilentlyContinue

    if ($existing) {
        Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name $Name -Value $SecureValue -Encrypted $true | Out-Null
        Write-Ok "Updated (encrypted)  $Name"
    } else {
        New-AzAutomationVariable -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name $Name -Value $SecureValue -Encrypted $true | Out-Null
        Write-Ok "Created (encrypted)  $Name"
    }
}

# ── Azure connection ───────────────────────────────────────────────────────────
Write-Step 'Connecting to Azure'
$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (-not $ctx) {
    Connect-AzAccount -ErrorAction Stop | Out-Null
    $ctx = Get-AzContext
}
Write-Ok "Signed in as $($ctx.Account.Id)"
Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
Write-Ok "Subscription set to OPSW Resources ($SubscriptionId)"

# ── Phase 1 : Storage account ──────────────────────────────────────────────────
Write-Step 'Phase 1 — Storage Account'

$sa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if ($sa) {
    Write-Skip "Storage account '$StorageAccountName' already exists — skipped"
} elseif ($DryRun) {
    Write-Skip "DRY-RUN  New-AzStorageAccount  $StorageAccountName"
} else {
    Write-Info "Creating storage account '$StorageAccountName' in $StorageRegion..."
    New-AzStorageAccount `
        -ResourceGroupName $ResourceGroupName `
        -Name $StorageAccountName `
        -Location $StorageRegion `
        -SkuName 'Standard_LRS' `
        -Kind 'StorageV2' `
        -EnableHttpsTrafficOnly $true `
        -AllowBlobPublicAccess $false `
        -ErrorAction Stop | Out-Null
    Write-Ok "Created storage account '$StorageAccountName'"
    $sa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
}

# ── Phase 1 : Blob containers ──────────────────────────────────────────────────
Write-Step 'Phase 1 — Blob Containers'

if (-not $DryRun) {
    $saKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
    $saCtx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $saKey
}

foreach ($container in $Containers) {
    if ($DryRun) {
        Write-Skip "DRY-RUN  New-AzStorageContainer  $container"
        continue
    }
    $existing = Get-AzStorageContainer -Name $container -Context $saCtx -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Skip "Container '$container' already exists"
    } else {
        New-AzStorageContainer -Name $container -Context $saCtx -Permission Off -ErrorAction Stop | Out-Null
        Write-Ok "Created container '$container'"
    }
}

# ── Phase 1 : Azure Table ──────────────────────────────────────────────────────
Write-Step 'Phase 1 — Azure Table'

if ($DryRun) {
    Write-Skip "DRY-RUN  New-AzStorageTable  $TableName"
} else {
    $existingTable = Get-AzStorageTable -Name $TableName -Context $saCtx -ErrorAction SilentlyContinue
    if ($existingTable) {
        Write-Skip "Table '$TableName' already exists — skipped"
    } else {
        New-AzStorageTable -Name $TableName -Context $saCtx -ErrorAction Stop | Out-Null
        Write-Ok "Created table '$TableName'"
    }
}

# ── Phase 2 : IAM role assignments ────────────────────────────────────────────
Write-Step 'Phase 2 — IAM Role Assignments'

Write-Info "Fetching managed identity principal ID for '$AutomationAccountName'..."
$aa = Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName -ErrorAction Stop
$principalId = $aa.Identity.PrincipalId
if (-not $principalId) {
    Write-Host "  [WARN] Could not read managed identity PrincipalId. Assign IAM roles manually in the Portal." -ForegroundColor Yellow
    Write-Info "  Roles needed on '$StorageAccountName':"
    Write-Info "    Storage Blob Data Contributor"
    Write-Info "    Storage Account Contributor"
} else {
    Write-Info "Managed identity principal: $principalId"
    $saScope = (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).Id

    foreach ($role in @('Storage Blob Data Contributor', 'Storage Account Contributor')) {
        $existing = Get-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName $role -Scope $saScope -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Skip "Role '$role' already assigned"
        } elseif ($DryRun) {
            Write-Skip "DRY-RUN  New-AzRoleAssignment  $role"
        } else {
            New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName $role -Scope $saScope -ErrorAction Stop | Out-Null
            Write-Ok "Assigned role '$role'"
        }
    }
}

# ── Phase 3 : Automation Variables ────────────────────────────────────────────
Write-Step 'Phase 3 — Automation Variables (non-secret)'

Set-AutoVar 'ContentEng_StorageAccountName'           $StorageAccountName
Set-AutoVar 'ContentEng_ResourceGroupName'            $ResourceGroupName
Set-AutoVar 'ContentEng_PromptTemplateContainerName'  'templates'
Set-AutoVar 'ContentEng_SubscriptionId'               $SubscriptionId
Set-AutoVar 'ContentEng_DataContainerName'            'data'
Set-AutoVar 'ContentEng_ResultsContainerName'         'results'
Set-AutoVar 'ContentEng_TokenUrl'                     $TokenUrl
Set-AutoVar 'ContentEng_AzureOpenAIBaseUrl'           $AzureOpenAIBaseUrl
Set-AutoVar 'ContentEng_AzureOpenAIDeployment'        $AzureOpenAIDeployment
Set-AutoVar 'ContentEng_AzureOpenAIApiVersion'        $AzureOpenAIApiVersion
Set-AutoVar 'ContentEng_ServiceNowIncidentsURL'       $ServiceNowIncidentsURL
Set-AutoVar 'ContentEng_ServiceNowRequestsURL'        $ServiceNowRequestsURL

# SN scope / IDs
Set-AutoVar 'ContentEng_BusinessServiceId'            'a1de2ff2db8f50108062531dd3961911'   # End-User Collaboration
Set-AutoVar 'ContentEng_ServiceOfferingId'            'ce614555dbeb5c105447610ed39619f8'   # Content Engineering
Set-AutoVar 'ContentEng_TrendTableName'               $TableName
Set-AutoVar 'ContentEng_TrendLookbackDays'            2
Set-AutoVar 'ContentEng_ReconcileWeeksToCheck'        2
Set-AutoVar 'ContentEng_ReconcileDeltaThreshold'      0
Set-AutoVar 'ContentEng_ReconcileEnableAutoHeal'      $true
Set-AutoVar 'ContentEng_ReconcileMaxHealPerWeekPerDay' 1
Set-AutoVar 'ContentEng_ReconcileDelayHours'          30

Write-Step 'Phase 3 — Automation Variables (secrets — you will be prompted)'

# ServiceNow credentials
Write-Host "`n  Enter the ServiceNow OAuth Client ID for Content Engineering:" -ForegroundColor Yellow
Write-Info "(Check the API gateway app registration, or reuse the PT client ID: 6e7adbde-53d8-4993-8740-f658cba16a8b)"
$snClientId = Read-Host "  ContentEng_ServiceNowClientID"
if (-not [string]::IsNullOrWhiteSpace($snClientId)) {
    Set-AutoVar 'ContentEng_ServiceNowClientID' $snClientId
}

Write-Host "`n  Enter the ServiceNow OAuth Scope for Content Engineering:" -ForegroundColor Yellow
Write-Info "(Default PT scope: api://71c9ae16-9d10-45b7-9c1d-30925311dabf/.default)"
$snScope = Read-Host "  ContentEng_ServiceNowScope"
if ([string]::IsNullOrWhiteSpace($snScope)) { $snScope = 'api://71c9ae16-9d10-45b7-9c1d-30925311dabf/.default' }
Set-AutoVar 'ContentEng_ServiceNowScope' $snScope

Write-Host "`n  Enter the ServiceNow OAuth Client Secret (input hidden):" -ForegroundColor Yellow
$snSecret = Read-Host "  ContentEng_ServiceNowClientSecret" -AsSecureString
Set-AutoVarSecure 'ContentEng_ServiceNowClientSecret' $snSecret

Write-Host "`n  Enter the Azure OpenAI API Key (input hidden):" -ForegroundColor Yellow
Write-Info "(Reuse the same key as Productivity Tools if sharing the same deployment)"
$oaiKey = Read-Host "  ContentEng_AzureOpenAIApiKey" -AsSecureString
Set-AutoVarSecure 'ContentEng_AzureOpenAIApiKey' $oaiKey

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host " Setup complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Storage account : $StorageAccountName" -ForegroundColor White
Write-Host " Containers      : $($Containers -join ', ')" -ForegroundColor White
Write-Host " Table           : $TableName" -ForegroundColor White
Write-Host " Automation vars : ContentEng_* (22 variables)" -ForegroundColor White
Write-Host ""
Write-Host " Next steps:" -ForegroundColor Yellow
Write-Host "  1. Upload templates to storage:"  -ForegroundColor Gray
Write-Host "     cd setup\publish" -ForegroundColor Gray
Write-Host "     .\Upload-TemplateFiles.ps1 -StorageAccountName $StorageAccountName -LocalTemplatesFolder '..\..\content-engineering\templates' -FilterPattern '*_ContentEngineering*'" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Publish the 4 CE runbooks:"  -ForegroundColor Gray
Write-Host "     cd setup\publish" -ForegroundColor Gray
Write-Host "     .\Publish-runbook.ps1 -SourceFile '..\..\content-engineering\runbooks\incident-trend-backfill-rb-contenteng.ps1'" -ForegroundColor Gray
Write-Host "     .\Publish-runbook.ps1 -SourceFile '..\..\content-engineering\runbooks\incident-analyzer-rb-contenteng.ps1'" -ForegroundColor Gray
Write-Host "     .\Publish-runbook.ps1 -SourceFile '..\..\content-engineering\runbooks\incident-reconcile-rb-contenteng.ps1'" -ForegroundColor Gray
Write-Host "     .\Publish-runbook.ps1 -SourceFile '..\..\content-engineering\runbooks\incident-trend-rb-contenteng.ps1'" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Create 4 schedules in Azure Portal (staggered +30 min from PT):" -ForegroundColor Gray
Write-Host "     03:30 UTC  -> incident-trend-backfill-rb-contenteng" -ForegroundColor Gray
Write-Host "     06:30 UTC  -> incident-analyzer-rb-contenteng" -ForegroundColor Gray
Write-Host "     07:30 UTC  -> incident-reconcile-rb-contenteng" -ForegroundColor Gray
Write-Host "     08:30 UTC  -> incident-trend-rb-contenteng" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Add Content Engineering to web/config.json and redeploy:" -ForegroundColor Gray
Write-Host "     .\setup\publish\Deploy-Web.ps1" -ForegroundColor Gray
Write-Host ""
