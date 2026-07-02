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
$AutomationAccountName   = 'OPSW-contentengg-account'
$StorageAccountName      = 'opswcontentenggblob'
$KeyVaultName           = 'OPSWcontentenggkey'
$StorageRegion           = 'eastus'

$BusinessServiceId       = 'a1de2ff2db8f50108062531dd3961911'   # End-User Collaboration (shared with PT)
$ServiceOfferingId       = 'ce614555dbeb5c105447610ed39619f8'   # Content Engineering

$TableName               = 'IncidentsCategoryStats'
$Containers              = @('templates', 'data', 'logs', 'results')

$AzureOpenAIBaseUrl      = 'https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com'
$AzureOpenAIDeployment   = 'gpt-5.4-mini'
$AzureOpenAIApiVersion   = '2025-04-01-preview'

$TokenUrl                = 'https://apis.intel.com/v1/auth/token'
$ServiceNowClientId      = '6e7adbde-53d8-4993-8740-f658cba16a8b'
$ServiceNowScope         = 'api://71c9ae16-9d10-45b7-9c1d-30925311dabf/.default'

$ServiceNowClientSecretName = 'ContentEng-ServiceNowClientSecret'
$AzureOpenAIApiKeySecretName = 'ContentEng-AzureOpenAIApiKey'

# ServiceNow incidents URL scoped to Content Engineering (business_service + service_offering)
$ServiceNowIncidentsURL  = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=business_service=a1de2ff2db8f50108062531dd3961911^service_offering=ce614555dbeb5c105447610ed39619f8^stateIN6,7^ORDERBYDESCresolved_at&sysparm_display_value=true&sysparm_limit=1000"
$ServiceNowRequestsURL   = "https://apis.intel.com/itsm/api/now/table/sc_task?sysparm_query=business_service=$BusinessServiceId^service_offering=$ServiceOfferingId^stateIN6,7^ORDERBYDESCresolved_at&sysparm_display_value=true&sysparm_limit=1000"

# Content Engineering runbooks/scripts source-of-truth
$ContentEngRunbooks = @(
    [PSCustomObject]@{
        SourceFile   = '..\\..\\content-engineering\\runbooks\\incident-trend-backfill-rb-contenteng.ps1'
        RunbookName  = 'incident-trend-backfill-rb-contenteng'
        ScheduleUtc  = '03:30 UTC'
    },
    [PSCustomObject]@{
        SourceFile   = '..\\..\\content-engineering\\runbooks\\incident-analyzer-rb-contenteng.ps1'
        RunbookName  = 'incident-analyzer-rb-contenteng'
        ScheduleUtc  = '06:30 UTC'
    },
    [PSCustomObject]@{
        SourceFile   = '..\\..\\content-engineering\\runbooks\\incident-trend-rb-contenteng.ps1'
        RunbookName  = 'incident-trend-rb-contenteng'
        ScheduleUtc  = 'Manual/On-demand'
    }
)

# Keep CE scheduling aligned with ProdTools: only 2 scheduled jobs.
$ContentEngScheduledRunbooks = @()
$ContentEngScheduledRunbooks += $ContentEngRunbooks | Where-Object { $_.RunbookName -eq 'incident-trend-backfill-rb-contenteng' }
$ContentEngScheduledRunbooks += $ContentEngRunbooks | Where-Object { $_.RunbookName -eq 'incident-analyzer-rb-contenteng' }

$ContentEngScripts = @(
    [PSCustomObject]@{ Name = 'Upload templates'; Path = '.\\setup\\publish\\Upload-TemplateFiles.ps1' },
    [PSCustomObject]@{ Name = 'Publish runbook';   Path = '.\\setup\\publish\\Publish-runbook.ps1' },
    [PSCustomObject]@{ Name = 'Deploy web';        Path = '.\\setup\\publish\\Deploy-Web.ps1' }
)

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

function Set-KeyVaultSecret {
    param(
        [Parameter(Mandatory = $true)][string]$VaultName,
        [Parameter(Mandatory = $true)][string]$SecretName,
        [Parameter(Mandatory = $true)][securestring]$SecretValue
    )

    if ($DryRun) {
        Write-Skip "DRY-RUN  Set-AzKeyVaultSecret  $SecretName in $VaultName"
        return
    }

    Set-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -SecretValue $SecretValue -ErrorAction Stop | Out-Null
    Write-Ok "Stored secret '$SecretName' in Key Vault '$VaultName'"
}

function Import-AzModuleBestEffort {
    param(
        [Parameter(Mandatory = $true)][string]$ModuleName,
        [version]$MinimumVersion
    )

    $candidates = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending
    if (-not $candidates) {
        throw "Required module '$ModuleName' is not installed."
    }

    if ($MinimumVersion) {
        $candidates = @($candidates | Where-Object { $_.Version -ge $MinimumVersion })
        if (-not $candidates) {
            throw "No installed '$ModuleName' version satisfies minimum version $MinimumVersion."
        }
    }

    foreach ($candidate in $candidates) {
        try {
            Import-Module -Name $candidate.Path -Force -ErrorAction Stop | Out-Null
            Write-Ok "Loaded $ModuleName $($candidate.Version)"
            return
        } catch {
            Write-Skip "Failed loading $ModuleName $($candidate.Version). Trying next available version."
            Write-Info "Reason: $($_.Exception.Message)"
        }
    }

    throw "Unable to load module '$ModuleName' from installed versions."
}

# ── Azure connection ───────────────────────────────────────────────────────────
Write-Step 'Connecting to Azure'

# Ensure compatible Az modules in this host (try best available versions).
Import-AzModuleBestEffort -ModuleName 'Az.Accounts' -MinimumVersion ([version]'2.0.0')
Import-AzModuleBestEffort -ModuleName 'Az.Resources' -MinimumVersion ([version]'2.0.0')

# Some environments throw a TypeLoadException in Get-AzContext because of
# incompatible Az module versions. Fall back to direct sign-in.
$ctx = $null
try {
    $ctx = Get-AzContext -ErrorAction Stop
} catch {
    Write-Skip "Get-AzContext failed in this session. Falling back to direct sign-in."
    Write-Info "Error: $($_.Exception.Message)"
}

if (-not $ctx) {
    Connect-AzAccount -ErrorAction Stop | Out-Null
    try {
        $ctx = Get-AzContext -ErrorAction Stop
    } catch {
        throw "Connected to Azure, but Get-AzContext is still failing. Fix Az module installation in this shell (Az.Accounts/Az.Resources version mismatch)."
    }
}
Write-Ok "Signed in as $($ctx.Account.Id)"
Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
Write-Ok "Subscription set to OPSW Resources ($SubscriptionId)"

# ── Phase 1 : Storage account ──────────────────────────────────────────────────
Write-Step 'Phase 1 — Storage Account'

$sa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if ($sa) {
    Write-Skip "Storage account '$StorageAccountName' already exists - skipped"
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
        Write-Skip "Table '$TableName' already exists - skipped"
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
Set-AutoVar 'ContentEng_ServiceNowClientID'           $ServiceNowClientId
Set-AutoVar 'ContentEng_ServiceNowScope'              $ServiceNowScope
Set-AutoVar 'ContentEng_AzureOpenAIBaseUrl'           $AzureOpenAIBaseUrl
Set-AutoVar 'ContentEng_AzureOpenAIDeployment'        $AzureOpenAIDeployment
Set-AutoVar 'ContentEng_AzureOpenAIApiVersion'        $AzureOpenAIApiVersion
Set-AutoVar 'ContentEng_KeyVaultName'                 $KeyVaultName
Set-AutoVar 'ContentEng_ServiceNowClientSecretName'   $ServiceNowClientSecretName
Set-AutoVar 'ContentEng_AzureOpenAIApiKeySecretName'  $AzureOpenAIApiKeySecretName
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

Write-Step 'Phase 3 — Automation Variables (secrets — loaded from local config)'

# Load secrets automatically from local config files (no interactive prompts).
# LocalSecrets-ContentEngineering.psd1 takes priority; falls back to LocalSecrets-ProductivityTools.psd1.
$_scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($_scriptRoot)) { $_scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$_ceSecretsPath = Join-Path $_scriptRoot '..\config\LocalSecrets-ContentEngineering.psd1'
$_ptSecretsPath = Join-Path $_scriptRoot '..\..\config\LocalSecrets-ProductivityTools.psd1'

$_snSecret = $null
$_oaiKey   = $null

if (Test-Path $_ceSecretsPath) {
    $s = Import-PowerShellDataFile -Path $_ceSecretsPath
    if ($s.ServiceNowClientSecret -and $s.ServiceNowClientSecret -ne '<SET_IN_LOCAL_ONLY>') { $_snSecret = $s.ServiceNowClientSecret }
    if ($s.AzureOpenAIApiKey      -and $s.AzureOpenAIApiKey      -ne '<SET_IN_LOCAL_ONLY>') { $_oaiKey   = $s.AzureOpenAIApiKey }
}
if ((-not $_snSecret -or -not $_oaiKey) -and (Test-Path $_ptSecretsPath)) {
    $p = Import-PowerShellDataFile -Path $_ptSecretsPath
    if (-not $_snSecret -and $p.ServiceNowIncidentsClientSecret) { $_snSecret = $p.ServiceNowIncidentsClientSecret }
    if (-not $_oaiKey   -and $p.AzureOpenAIApiKey)               { $_oaiKey   = $p.AzureOpenAIApiKey }
}

if ($DryRun) {
    Write-Skip 'DRY-RUN  Skipping Key Vault secret writes'
    Set-KeyVaultSecret -VaultName $KeyVaultName -SecretName $ServiceNowClientSecretName -SecretValue (ConvertTo-SecureString 'DRYRUN' -AsPlainText -Force)
    Set-KeyVaultSecret -VaultName $KeyVaultName -SecretName $AzureOpenAIApiKeySecretName -SecretValue (ConvertTo-SecureString 'DRYRUN' -AsPlainText -Force)
} else {
    if (-not $_snSecret) { throw "ServiceNow Client Secret not found in CE or PT local secrets files. Populate LocalSecrets-ContentEngineering.psd1." }
    if (-not $_oaiKey)   { throw "Azure OpenAI API Key not found in CE or PT local secrets files. Populate LocalSecrets-ContentEngineering.psd1." }
    Set-KeyVaultSecret -VaultName $KeyVaultName -SecretName $ServiceNowClientSecretName  -SecretValue (ConvertTo-SecureString $_snSecret -AsPlainText -Force)
    Set-KeyVaultSecret -VaultName $KeyVaultName -SecretName $AzureOpenAIApiKeySecretName -SecretValue (ConvertTo-SecureString $_oaiKey   -AsPlainText -Force)
    Write-Ok "Secrets loaded from local config and stored in Key Vault '$KeyVaultName'"
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host " Setup complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Storage account : $StorageAccountName" -ForegroundColor White
Write-Host " Containers      : $($Containers -join ', ')" -ForegroundColor White
Write-Host " Table           : $TableName" -ForegroundColor White
Write-Host " Automation vars : ContentEng_* (25 variables)" -ForegroundColor White
Write-Host " Runbooks        : $($ContentEngRunbooks.Count) defined (Content Engineering)" -ForegroundColor White
Write-Host " Schedules       : $($ContentEngScheduledRunbooks.Count) enabled (ProdTools-like model)" -ForegroundColor White
Write-Host ""
Write-Host " Next steps:" -ForegroundColor Yellow
Write-Host "  1. Upload templates to storage:"  -ForegroundColor Gray
Write-Host "     cd setup\publish" -ForegroundColor Gray
Write-Host "     .\Upload-TemplateFiles.ps1 -StorageAccountName $StorageAccountName -LocalTemplatesFolder '..\..\content-engineering\templates' -FilterPattern '*_ContentEngineering*'" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Publish the CE runbooks:"  -ForegroundColor Gray
Write-Host "     cd setup\publish" -ForegroundColor Gray
foreach ($rb in $ContentEngRunbooks) {
    Write-Host "     .\Publish-runbook.ps1 -SourceFile '$($rb.SourceFile)' -RunbookName '$($rb.RunbookName)' -AutomationAccountName '$AutomationAccountName'" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  3. Create CE schedules in Azure Portal:" -ForegroundColor Gray
foreach ($rb in $ContentEngScheduledRunbooks) {
    Write-Host "     $($rb.ScheduleUtc) -> $($rb.RunbookName)" -ForegroundColor Gray
}
Write-Host "     incident-trend-rb-contenteng stays manual/on-demand" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Add Content Engineering to web/config.json and redeploy:" -ForegroundColor Gray
Write-Host "     .\setup\publish\Deploy-Web.ps1" -ForegroundColor Gray
Write-Host ""
