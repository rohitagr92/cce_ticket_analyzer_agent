<#
.SYNOPSIS
    One-stop setup script for the End User Conferencing service offering.

.DESCRIPTION
    Creates or validates the shared Azure assets used by this service offering:
    - Storage account
    - Blob containers
    - Azure Table
    - Automation variables
    - Key Vault secret names / values

    The script is parameterized because ServiceNow IDs and secret values are not
    hard-coded in the repo.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$SubscriptionId = '1c6d384e-bc83-4b02-859c-76eeb87f7676',
    [string]$ResourceGroupName = 'OPSW-Ticket-Analyzer',
    [string]$AutomationAccountName = 'opswconferautomation',
    [string]$StorageAccountName = 'opswconferblob',
    [string]$KeyVaultName = 'opswconferkeyvault',
    [string]$BusinessServiceId,
    [string]$MessagingServiceOfferingId,
    [string]$RoomsServiceOfferingId,
    [string]$ServiceNowClientId,
    [string]$ServiceNowScope,
    [string]$ServiceNowTokenUrl = 'https://apis.intel.com/v1/auth/token',
    [string]$MessagingServiceNowIncidentsUrl,
    [string]$RoomsServiceNowIncidentUrl,
    [string]$AzureOpenAIBaseUrl = 'https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com',
    [string]$AzureOpenAIDeployment = 'gpt-5.4-mini',
    [string]$AzureOpenAIApiVersion = '2025-04-01-preview',
    [string]$ServiceNowClientSecretName = 'EndUserConferencing-ServiceNowClientSecret',
    [string]$AzureOpenAIApiKeySecretName = 'EndUserConferencing-AzureOpenAIApiKey',
    [string]$ServiceNowClientSecret,
    [string]$AzureOpenAIApiKey,
    [string]$TemplatesContainerName = 'templates',
    [string]$DataContainerName = 'data',
    [string]$LogsContainerName = 'logs',
    [string]$ResultsContainerName = 'results',
    [string]$TableName = 'IncidentsCategoryStats',
    [int]$DailyLookbackDays = 2,
    [int]$AnalyzerLookbackDays = 7,
    [bool]$SaveRunArtifacts = $true
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

if (Get-Module -ListAvailable -Name Az.Storage) {
    Import-Module Az.Storage -Force -ErrorAction Stop
} else {
    throw 'Az.Storage is required for End User Conferencing setup.'
}

if (Get-Module -ListAvailable -Name Az.Accounts) {
    Import-Module Az.Accounts -Force -ErrorAction Stop
} else {
    throw 'Az.Accounts is required for End User Conferencing setup.'
}

if (Get-Module -ListAvailable -Name Az.KeyVault) {
    Import-Module Az.KeyVault -Force -ErrorAction Stop
} else {
    throw 'Az.KeyVault is required for End User Conferencing setup.'
}

if (Get-Module -ListAvailable -Name AzTable) {
    Import-Module AzTable -Force -ErrorAction Stop
} else {
    throw 'AzTable is required for End User Conferencing setup.'
}

function Write-Step { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "  [OK]  $Message" -ForegroundColor Green }
function Write-Skip { param([string]$Message) Write-Host "  [--]  $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "        $Message" -ForegroundColor Gray }

function Set-EucAutomationVariable {
    param(
        [string]$Name,
        [object]$Value,
        [bool]$Encrypted = $false
    )

    if ($DryRun) {
        Write-Skip "DRY-RUN Set-AzAutomationVariable $Name"
        return
    }

    $existing = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Name -Value $Value -Encrypted $Encrypted | Out-Null
        Write-Ok "Updated $Name"
    } else {
        New-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Name -Value $Value -Encrypted $Encrypted | Out-Null
        Write-Ok "Created $Name"
    }
}

function Set-EucKeyVaultSecret {
    param(
        [string]$VaultName,
        [string]$SecretName,
        [string]$SecretValue
    )

    if ($DryRun) {
        Write-Skip "DRY-RUN Set-AzKeyVaultSecret $SecretName in $VaultName"
        return
    }

    Set-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -SecretValue (ConvertTo-SecureString $SecretValue -AsPlainText -Force) | Out-Null
    Write-Ok "Stored secret '$SecretName' in '$VaultName'"
}

function Upload-EucTemplateFiles {
    param(
        [string]$LocalTemplateRoot,
        [string]$StorageAccountName,
        [string]$ContainerName
    )

    if (-not (Test-Path $LocalTemplateRoot)) {
        throw "Template folder not found: $LocalTemplateRoot"
    }

    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageKey
    $templateFiles = Get-ChildItem -Path $LocalTemplateRoot -Recurse -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' }

    foreach ($templateFile in $templateFiles) {
        $relativePath = $templateFile.FullName.Substring($LocalTemplateRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        Write-Info "Uploading template $relativePath"
        Set-AzStorageBlobContent -File $templateFile.FullName -Container $ContainerName -Blob $relativePath -Context $storageContext -Force | Out-Null
    }
}

function Set-EucStorageCors {
    param(
        [string]$StorageAccountName,
        [string]$Origin
    )

    if ($DryRun) {
        Write-Skip "DRY-RUN Set-AzStorageCORSRule for $StorageAccountName"
        return
    }

    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageKey
    $rules = @(@{
        AllowedOrigins  = @($Origin)
        AllowedMethods  = @('GET', 'HEAD', 'OPTIONS')
        AllowedHeaders  = @('*')
        ExposedHeaders  = @('x-ms-*')
        MaxAgeInSeconds = 3600
    })

    Set-AzStorageCORSRule -ServiceType Table -CorsRules $rules -Context $storageContext | Out-Null
    Set-AzStorageCORSRule -ServiceType Blob -CorsRules $rules -Context $storageContext | Out-Null
    Write-Ok "Applied CORS for $Origin on $StorageAccountName"
}

Write-Step 'Connecting to Azure'
Connect-AzAccount -ErrorAction Stop | Out-Null
Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
Write-Ok "Subscription set to $SubscriptionId"

if (-not $BusinessServiceId) { throw 'BusinessServiceId is required.' }
if (-not $MessagingServiceOfferingId) { throw 'MessagingServiceOfferingId is required.' }
if (-not $RoomsServiceOfferingId) { throw 'RoomsServiceOfferingId is required.' }
if (-not $ServiceNowClientId) { throw 'ServiceNowClientId is required.' }
if (-not $ServiceNowScope) { throw 'ServiceNowScope is required.' }
if (-not $ServiceNowClientSecret) { throw 'ServiceNowClientSecret is required.' }
if (-not $AzureOpenAIApiKey) { throw 'AzureOpenAIApiKey is required.' }

Write-Step 'Storage account and table'
$storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (-not $storageAccount) {
    if ($DryRun) {
        Write-Skip "DRY-RUN New-AzStorageAccount $StorageAccountName"
    } else {
        New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location 'eastus' -SkuName 'Standard_LRS' -Kind 'StorageV2' -EnableHttpsTrafficOnly $true -AllowBlobPublicAccess $false | Out-Null
        Write-Ok "Created storage account $StorageAccountName"
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
    }
} else {
    Write-Skip "Storage account '$StorageAccountName' already exists"
}

Write-Step 'Storage CORS'
Set-EucStorageCors -StorageAccountName $StorageAccountName -Origin 'https://nice-wave-080119d1e.7.azurestaticapps.net'

if (-not $DryRun) {
    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageKey
    foreach ($container in @($TemplatesContainerName, $DataContainerName, $LogsContainerName, $ResultsContainerName)) {
        $existingContainer = Get-AzStorageContainer -Name $container -Context $storageContext -ErrorAction SilentlyContinue
        if (-not $existingContainer) {
            New-AzStorageContainer -Name $container -Context $storageContext -Permission Off | Out-Null
            Write-Ok "Created container '$container'"
        } else {
            Write-Skip "Container '$container' already exists"
        }
    }
    $existingTable = Get-AzStorageTable -Name $TableName -Context $storageContext -ErrorAction SilentlyContinue
    if (-not $existingTable) {
        New-AzStorageTable -Name $TableName -Context $storageContext | Out-Null
        Write-Ok "Created table '$TableName'"
    } else {
        Write-Skip "Table '$TableName' already exists"
    }
}

Write-Step 'Template upload'
$templateRoot = Join-Path $PSScriptRoot '..\templates'
if ($DryRun) {
    Write-Skip "DRY-RUN upload templates from $templateRoot"
} else {
    Upload-EucTemplateFiles -LocalTemplateRoot $templateRoot -StorageAccountName $StorageAccountName -ContainerName $TemplatesContainerName
    Write-Ok "Uploaded EUC templates to '$TemplatesContainerName'"
}

Write-Step 'Managed identity role assignments'
$automationAccount = Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName -ErrorAction Stop
$principalId = $automationAccount.Identity.PrincipalId
if (-not $principalId) {
    Write-Skip 'Managed identity principal id not available; assign IAM roles manually.'
} else {
    $scope = $storageAccount.Id
    foreach ($role in @('Storage Blob Data Contributor', 'Storage Account Contributor')) {
        $existingRole = Get-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName $role -Scope $scope -ErrorAction SilentlyContinue
        if (-not $existingRole) {
            if ($DryRun) {
                Write-Skip "DRY-RUN New-AzRoleAssignment $role"
            } else {
                New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName $role -Scope $scope | Out-Null
                Write-Ok "Assigned '$role'"
            }
        } else {
            Write-Skip "Role '$role' already assigned"
        }
    }
}

Write-Step 'Automation variables'
Set-EucAutomationVariable 'EUC_StorageAccountName' $StorageAccountName
Set-EucAutomationVariable 'EUC_ResourceGroupName' $ResourceGroupName
Set-EucAutomationVariable 'EUC_PromptTemplateContainerName' $TemplatesContainerName
Set-EucAutomationVariable 'EUC_DataContainerName' $DataContainerName
Set-EucAutomationVariable 'EUC_LogsContainerName' $LogsContainerName
Set-EucAutomationVariable 'EUC_ResultsContainerName' $ResultsContainerName
Set-EucAutomationVariable 'EUC_TrendTableName' $TableName
Set-EucAutomationVariable 'EUC_DailyLookbackDays' $DailyLookbackDays
Set-EucAutomationVariable 'EUC_AnalyzerLookbackDays' $AnalyzerLookbackDays
Set-EucAutomationVariable 'EUC_SaveRunArtifacts' $SaveRunArtifacts
Set-EucAutomationVariable 'EUC_KeyVaultName' $KeyVaultName
Set-EucAutomationVariable 'EUC_ServiceNowClientId' $ServiceNowClientId
Set-EucAutomationVariable 'EUC_ServiceNowScope' $ServiceNowScope
Set-EucAutomationVariable 'EUC_ServiceNowTokenUrl' $ServiceNowTokenUrl
if ($MessagingServiceNowIncidentsUrl) { Set-EucAutomationVariable 'EUC_MessagingServiceNowIncidentsUrl' $MessagingServiceNowIncidentsUrl }
if ($RoomsServiceNowIncidentUrl) { Set-EucAutomationVariable 'EUC_RoomsServiceNowIncidentUrl' $RoomsServiceNowIncidentUrl }
Set-EucAutomationVariable 'EUC_AzureOpenAIBaseUrl' $AzureOpenAIBaseUrl
Set-EucAutomationVariable 'EUC_AzureOpenAIDeployment' $AzureOpenAIDeployment
Set-EucAutomationVariable 'EUC_AzureOpenAIApiVersion' $AzureOpenAIApiVersion
Set-EucAutomationVariable 'EUC_BusinessServiceId' $BusinessServiceId
Set-EucAutomationVariable 'EUC_MessagingServiceOfferingId' $MessagingServiceOfferingId
Set-EucAutomationVariable 'EUC_RoomsServiceOfferingId' $RoomsServiceOfferingId
Set-EucAutomationVariable 'EUC_ServiceNowClientSecretName' $ServiceNowClientSecretName
Set-EucAutomationVariable 'EUC_AzureOpenAIApiKeySecretName' $AzureOpenAIApiKeySecretName

Write-Step 'Key Vault secrets'
if ($DryRun) {
    Write-Skip 'DRY-RUN skipping secret writes'
} else {
    Set-EucKeyVaultSecret -VaultName $KeyVaultName -SecretName $ServiceNowClientSecretName -SecretValue $ServiceNowClientSecret
    Set-EucKeyVaultSecret -VaultName $KeyVaultName -SecretName $AzureOpenAIApiKeySecretName -SecretValue $AzureOpenAIApiKey
}

Write-Host "`n[OK] End User Conferencing setup complete." -ForegroundColor Green
