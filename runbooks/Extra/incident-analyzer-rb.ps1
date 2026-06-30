# Detect execution environment
$Script:IsAzureAutomation = $env:AUTOMATION_ASSET_ACCOUNTID -or $PSPrivateMetadata.JobId

function Get-AutomationVariableFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Names,
        [switch]$Optional
    )

    foreach ($name in $Names) {
        try {
            $value = Get-AutomationVariable -Name $name -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return $value
            }
        } catch {
            continue
        }
    }

    if ($Optional) {
        return $null
    }

    throw "Missing required automation variable. Checked: $($Names -join ', ')"
}

 
if ($Script:IsAzureAutomation) {
    Write-Host "Running in Azure Automation environment" -ForegroundColor Green
    #Requires -Modules Az.Storage, Az.Accounts
    # Import Az modules (use whatever versions are available in Automation Account)
    Import-Module -Name Az.Storage -Force -ErrorAction Stop
    Import-Module -Name Az.Accounts -Force -ErrorAction Stop

    # Set your log file name prefix - this will be used as: "{LogFilePrefix}-{timestamp}.log"
    $Script:LogFilePrefix = "AI-ResolvedIncidents-StrictCategorization"
    # Container name for logs in storage account
    $Script:LogContainerName = "logs"
    # Azure Automation - blob logging enabled
    $Script:LogLevel = "Info"
    $Script:EnableBlobLogging = $true
    # Azure Automation - use automation variables
    $Script:BlobConfig = @{
        StorageAccountName = Get-AutomationVariableFallback -Names @("Incidents_analyzer_StorageAccountName", "PSD_AI_Automations_StorageAccountName")
        PromptContainerName = Get-AutomationVariableFallback -Names @("Incidents_analyzer_PromptTemplateContainerName", "PSD_AI_Automations_PromptTemplateContainerName", "PSD-AI-Automations_PromptTemplateContainerName")
        ResourceGroupName = Get-AutomationVariableFallback -Names @("Incidents_analyzer_ResourceGroupName", "PSD_AI_Automations_ResourceGroupName")
        DataContainerName = Get-AutomationVariableFallback -Names @("Incidents_analyzer_DataContainerName", "PSD_AI_Automations_DataContainerName", "PSD-AI-Automations_DataContainerName") -Optional
        ResultsContainerName = Get-AutomationVariableFallback -Names @("Incidents_analyzer_ResultsContainerName", "PSD_AI_Automations_ResultsContainerName", "PSD-AI-Automations_ResultsContainerName") -Optional
        SubscriptionId = Get-AutomationVariableFallback -Names @("Incidents_analyzer_SubscriptionId", "PSD_AI_Automations_SubscriptionId", "PSD-AI-Automations_SubscriptionId") -Optional
        StatisticsTableName = "IncidentsCategoryStats"  # Azure Table for statistics
        }

    if ([string]::IsNullOrWhiteSpace($Script:BlobConfig.DataContainerName)) { $Script:BlobConfig.DataContainerName = "data" }
    if ([string]::IsNullOrWhiteSpace($Script:BlobConfig.ResultsContainerName)) { $Script:BlobConfig.ResultsContainerName = "results" }
    Write-Host ("Blob config resolved - Account: {0}, ResourceGroup: {1}, PromptContainer: {2}, DataContainer: {3}, ResultsContainer: {4}" -f $Script:BlobConfig.StorageAccountName, $Script:BlobConfig.ResourceGroupName, $Script:BlobConfig.PromptContainerName, $Script:BlobConfig.DataContainerName, $Script:BlobConfig.ResultsContainerName) -ForegroundColor Cyan
    # Azure Automation - use automation variables
    $Script:Constants = @{
        ServiceNowIncidentsClientID = Get-AutomationVariable -Name "ServiceNowIncidentsClientID"
        ServiceNowIncidentsClientSecret = Get-AutomationVariable -Name "ServiceNowIncidentsClientSecret"
        ServiceNowIncidentsScope = Get-AutomationVariable -Name "ServiceNowIncidentsScope"
        TokenUrl = Get-AutomationVariable -Name "TokenUrl"
        AzureOpenAIBaseUrl = Get-AutomationVariable -Name "AzureOpenAIBaseUrl"
        AzureOpenAIDeployment = Get-AutomationVariable -Name "AzureOpenAIDeployment"
        AzureOpenAIApiKey = Get-AutomationVariable -Name "AzureOpenAIApiKey"
        AzureOpenAIApiVersion = Get-AutomationVariable -Name "AzureOpenAIApiVersion"
        ServicenowIncidentsURL = Get-AutomationVariable -Name "ServiceNowIncidentsURL"
        ServicenowRequestsURL = Get-AutomationVariable -Name "ServiceNowRequestsURL"
        LogicAppSendAIEmailWebHookURL = Get-AutomationVariable -Name "LogicAppSendAIEmailWebHookURL" -ErrorAction SilentlyContinue 
        UseClaudeModel = Get-AutomationVariable -Name "UseClaudeModel" -ErrorAction SilentlyContinue 
        ClaudeEndpoint = Get-AutomationVariable -Name "ClaudeEndpoint" -ErrorAction SilentlyContinue 
        ClaudeDeployment = Get-AutomationVariable -Name "ClaudeDeployment" -ErrorAction SilentlyContinue 
        ClaudeApiKey = Get-AutomationVariable -Name "ClaudeApiKey" -ErrorAction SilentlyContinue 
        ClaudeApiVersion = Get-AutomationVariable -Name "ClaudeApiVersion" -ErrorAction SilentlyContinue
        UseStoredIncidents = Get-AutomationVariable -Name "UseStoredIncidents" -ErrorAction SilentlyContinue
        StoredDataFileName = Get-AutomationVariable -Name "StoredDataFileName" -ErrorAction SilentlyContinue
        SaveRawDataLocally = Get-AutomationVariable -Name "SaveRawDataLocally" -ErrorAction SilentlyContinue
        DailyLookbackHours = Get-AutomationVariable -Name "DailyLookbackHours" -ErrorAction SilentlyContinue
        SaveRunArtifacts = Get-AutomationVariable -Name "SaveRunArtifacts" -ErrorAction SilentlyContinue
        GenerateWeeklyMergedReportOnWeekend = Get-AutomationVariable -Name "GenerateWeeklyMergedReportOnWeekend" -ErrorAction SilentlyContinue
        WeeklyMergeLookbackDays = Get-AutomationVariable -Name "WeeklyMergeLookbackDays" -ErrorAction SilentlyContinue
        WeeklyReportOnlyMode = Get-AutomationVariable -Name "WeeklyReportOnlyMode" -ErrorAction SilentlyContinue
        WeeklyReportDayOfWeek = Get-AutomationVariable -Name "WeeklyReportDayOfWeek" -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "Running in local development environment" -ForegroundColor Yellow
    # Local development - console logging only, more verbose
    $Script:LogLevel = "Debug"
    $Script:EnableBlobLogging = $false

    # Local development - load from LocalConfig.psd1
    $Script:ScriptDirectory = $PSScriptRoot
    Set-Location $Script:ScriptDirectory
    # $configPath = Join-Path $Script:ScriptDirectory "LocalConfig.psd1"
    $configPath = ".\LocalConfig.psd1"
    if (Test-Path $configPath) {
        Write-Host "Loading local configuration from $configPath" -ForegroundColor Green
        $Script:LocalConfig = Import-PowerShellDataFile -Path $configPath
    } else {
        throw "LocalConfig.psd1 not found. Please create it for local development."
    }
    # Local development - use loaded config
    $Script:Constants = @{
        ServiceNowIncidentsClientID = $Script:LocalConfig.ServiceNowIncidentsClientID
        ServiceNowIncidentsClientSecret = $Script:LocalConfig.ServiceNowIncidentsClientSecret
        ServiceNowIncidentsScope = $Script:LocalConfig.ServiceNowIncidentsScope
        TokenUrl = $Script:LocalConfig.TokenUrl
        AzureOpenAIBaseUrl = $Script:LocalConfig.AzureOpenAIBaseUrl
        AzureOpenAIDeployment = $Script:LocalConfig.AzureOpenAIDeployment
        AzureOpenAIApiKey = $Script:LocalConfig.AzureOpenAIApiKey
        AzureOpenAIApiVersion = $Script:LocalConfig.AzureOpenAIApiVersion
        ServicenowIncidentsURL = $Script:LocalConfig.ServicenowIncidentsURL
        ServicenowRequestsURL = $Script:LocalConfig.ServicenowRequestsURL
        LogicAppSendAIEmailWebHookURL = $Script:LocalConfig.WebhookUrl
        # Local data storage settings
        SaveRawDataLocally = $Script:LocalConfig.SaveRawDataLocally
        UseStoredIncidents = $Script:LocalConfig.UseStoredIncidents
        StoredDataFileName = $Script:LocalConfig.StoredDataFileName
        # Claude/Anthropic settings
        UseClaudeModel = $Script:LocalConfig.UseClaudeModel
        ClaudeEndpoint = $Script:LocalConfig.ClaudeEndpoint
        ClaudeDeployment = $Script:LocalConfig.ClaudeDeployment
        ClaudeApiKey = $Script:LocalConfig.ClaudeApiKey
        ClaudeApiVersion = $Script:LocalConfig.ClaudeApiVersion
        DailyLookbackHours = $Script:LocalConfig.DailyLookbackHours
        SaveRunArtifacts = $Script:LocalConfig.SaveRunArtifacts
        GenerateWeeklyMergedReportOnWeekend = $Script:LocalConfig.GenerateWeeklyMergedReportOnWeekend
        WeeklyMergeLookbackDays = $Script:LocalConfig.WeeklyMergeLookbackDays
        WeeklyReportOnlyMode = $Script:LocalConfig.WeeklyReportOnlyMode
        WeeklyReportDayOfWeek = $Script:LocalConfig.WeeklyReportDayOfWeek
    }
}

<#
.SYNOPSIS
    ServiceNow Mobile Device Management Incident Categorization System
    
.DESCRIPTION
    This script retrieves resolved incidents from ServiceNow for the Mobile Device Management team,
    processes them using AI for root cause categorization and summarization, then generates an HTML 
    report that is sent via webhook for email delivery.
    
.NOTES
    Version: 1.3
    Purpose: Automated incident categorization and reporting for EUC team
    Added: Enhanced blob storage logging with detailed ticket processing and AI reasoning
    Added: AI reasoning to outputted HTML and updated to use AzureOpenAI endpoints now iGPT is EOL
#>

#region logging config
$Script:LogConfig = @{
    EnableBlobLogging = $Script:EnableBlobLogging
    LogLevel = $Script:LogLevel
    LogFilePrefix = $Script:LogFilePrefix
    LogContainerName = $Script:LogContainerName
    CurrentLogFile = $null
    LogBuffer = [System.Collections.Generic.List[string]]::new()
    StorageContext = $null
}
#endregion

#region Enhanced Logging to Azure Blob Storage

function Initialize-BlobLogging {
    [CmdletBinding()]
    param()
    
    if (-not $Script:LogConfig.EnableBlobLogging) { 
        Write-Host "Blob logging disabled by configuration" -ForegroundColor Yellow
        return 
    }
    
    try {
        # Create log file name with timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $Script:LogConfig.CurrentLogFile = "$($Script:LogConfig.LogFilePrefix)-$timestamp.log"
        
        Write-Host "Initializing blob logging to: $($Script:LogConfig.CurrentLogFile)" -ForegroundColor Cyan
        
        # Get storage context using managed identity
        $azContext = Get-AzContext
        if (-not $azContext) {
            Write-Host "Connecting with Managed Identity..." -ForegroundColor Yellow
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        }
        
        # Get storage account key for authentication
        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $Script:BlobConfig.ResourceGroupName -Name $Script:BlobConfig.StorageAccountName)[0].Value
        $Script:LogConfig.StorageContext = New-AzStorageContext -StorageAccountName $Script:BlobConfig.StorageAccountName -StorageAccountKey $storageKey
        
        # Add initial log entry
        $Script:LogConfig.LogBuffer.Add("=== $($Script:LogConfig.LogFilePrefix) Execution Log ===")
        $Script:LogConfig.LogBuffer.Add("Execution Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $Script:LogConfig.LogBuffer.Add("PowerShell Version: $($PSVersionTable.PSVersion)")
        $Script:LogConfig.LogBuffer.Add("Log Level: $($Script:LogConfig.LogLevel)")
        $Script:LogConfig.LogBuffer.Add("Storage Account: $($Script:BlobConfig.StorageAccountName)")
        $Script:LogConfig.LogBuffer.Add("Log Container: $($Script:LogConfig.LogContainerName)")
        $Script:LogConfig.LogBuffer.Add("=" * 80)
        $Script:LogConfig.LogBuffer.Add("")
        
        Write-Host "Blob logging initialized successfully" -ForegroundColor Green
        
    } catch {
        Write-Host "Failed to initialize blob logging: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Continuing without blob logging..." -ForegroundColor Yellow
        $Script:LogConfig.EnableBlobLogging = $false
    }
}

function Write-BlobLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Debug', 'Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info',
        
        [string]$Category = 'General'
    )
    
    if (-not $Script:LogConfig.EnableBlobLogging) { return }
    
    # Check log level
    $logLevels = @{ 'Debug' = 0; 'Info' = 1; 'Success' = 1; 'Warning' = 2; 'Error' = 3 }
    $currentLevel = $logLevels[$Script:LogConfig.LogLevel]
    $messageLevel = $logLevels[$Level]
    
    if ($messageLevel -lt $currentLevel) { return }
    
    # Format log entry
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [$Category] $Message"
    
    # Add to buffer
    $Script:LogConfig.LogBuffer.Add($logEntry)
    
    # If buffer gets too large, flush it
    if ($Script:LogConfig.LogBuffer.Count -gt 50) {
        Write-LogBufferToBlob
    }
}

function Write-LogBufferToBlob {
    [CmdletBinding()]
    param()
    
    if (-not $Script:LogConfig.EnableBlobLogging -or $Script:LogConfig.LogBuffer.Count -eq 0) { return }
    
    try {
        # Convert buffer to string
        $logContent = $Script:LogConfig.LogBuffer -join "`n"
        
        # Check if log file already exists
        $existingBlob = Get-AzStorageBlob -Container $Script:LogConfig.LogContainerName -Blob $Script:LogConfig.CurrentLogFile -Context $Script:LogConfig.StorageContext -ErrorAction SilentlyContinue
        
        if ($existingBlob) {
            # Append to existing log
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                # Download existing content
                Get-AzStorageBlobContent -Container $Script:LogConfig.LogContainerName -Blob $Script:LogConfig.CurrentLogFile -Destination $tempFile -Context $Script:LogConfig.StorageContext -Force | Out-Null
                
                # Append new content
                Add-Content -Path $tempFile -Value "`n$logContent" -Encoding UTF8
                
                # Upload back
                Set-AzStorageBlobContent -File $tempFile -Container $Script:LogConfig.LogContainerName -Blob $Script:LogConfig.CurrentLogFile -Context $Script:LogConfig.StorageContext -Force | Out-Null
                
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        } else {
            # Create new log file
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tempFile -Value $logContent -Encoding UTF8
                Set-AzStorageBlobContent -File $tempFile -Container $Script:LogConfig.LogContainerName -Blob $Script:LogConfig.CurrentLogFile -Context $Script:LogConfig.StorageContext | Out-Null
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
        
        # Clear buffer
        $Script:LogConfig.LogBuffer.Clear()
        
    } catch {
        Write-Host "Failed to write logs to blob storage: $($_.Exception.Message)" -ForegroundColor Red
        # Don't throw - we don't want logging issues to break the main process
    }
}

function Complete-BlobLogging {
    [CmdletBinding()]
    param(
        [string]$FinalMessage = "Execution completed successfully"
    )
    
    if (-not $Script:LogConfig.EnableBlobLogging) { return }
    
    try {
        # Add final log entries
        $Script:LogConfig.LogBuffer.Add("")
        $Script:LogConfig.LogBuffer.Add("=" * 80)
        $Script:LogConfig.LogBuffer.Add("$FinalMessage")
        $Script:LogConfig.LogBuffer.Add("Execution Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $Script:LogConfig.LogBuffer.Add("Total Processed Tickets: $($Script:ProcessedTickets.Count)")
        $Script:LogConfig.LogBuffer.Add("=== End of Log ===")
        
        # Flush final buffer
        Write-LogBufferToBlob
        
        Write-Host ("Log file saved to blob storage: {0}" -f $Script:LogConfig.CurrentLogFile) -ForegroundColor Green
        Write-Host ("  Container: {0}" -f $Script:LogConfig.LogContainerName) -ForegroundColor Gray
        Write-Host ("  Storage Account: {0}" -f $Script:BlobConfig.StorageAccountName) -ForegroundColor Gray
        
    } catch {
        Write-Host "Failed to complete blob logging: $($_.Exception.Message)" -ForegroundColor Red
    }
}

#endregion

#region Core Utility Functions

function Get-StorageContext {
    [CmdletBinding()]
    param()
    
    try {
        # Ensure we have a valid Azure context
        $azContext = Get-AzContext
        if (-not $azContext) {
            Write-ScriptLog "No Azure context found, connecting with managed identity..." -Level Info
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

function New-ReportBlobReadSasUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $StorageContext,

        [Parameter(Mandatory)]
        [string]$ContainerName,

        [Parameter(Mandatory)]
        [string]$BlobName,

        [int]$ExpiryDays = 30
    )

    $expiry = (Get-Date).ToUniversalTime().AddDays($ExpiryDays)
    $sasToken = New-AzStorageBlobSASToken `
        -Container $ContainerName `
        -Blob $BlobName `
        -Context $StorageContext `
        -Permission r `
        -ExpiryTime $expiry

    if (-not $sasToken.StartsWith('?')) { $sasToken = '?' + $sasToken }

    return "https://$($Script:BlobConfig.StorageAccountName).blob.core.windows.net/$ContainerName/$BlobName$sasToken"
}

function Get-ReportsManifestObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $StorageContext,

        [Parameter(Mandatory)]
        [string]$ContainerName,

        [string]$ManifestBlobName = "reports-manifest.json"
    )

    $manifest = [ordered]@{
        version        = 1
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        storageAccount = [string]$Script:BlobConfig.StorageAccountName
        container      = [string]$ContainerName
        reports        = @()
    }

    $blob = Get-AzStorageBlob -Container $ContainerName -Blob $ManifestBlobName -Context $StorageContext -ErrorAction SilentlyContinue
    if (-not $blob) { return $manifest }

    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        Get-AzStorageBlobContent -Container $ContainerName -Blob $ManifestBlobName -Destination $tempFile -Context $StorageContext -Force | Out-Null
        $raw = Get-Content -Path $tempFile -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($raw)) { return $manifest }

        $parsed = $raw | ConvertFrom-Json -Depth 20
        if ($null -ne $parsed) {
            if ($parsed.PSObject.Properties.Name -contains 'version')        { $manifest.version = [int]$parsed.version }
            if ($parsed.PSObject.Properties.Name -contains 'generatedAtUtc') { $manifest.generatedAtUtc = [string]$parsed.generatedAtUtc }
            if ($parsed.PSObject.Properties.Name -contains 'storageAccount') { $manifest.storageAccount = [string]$parsed.storageAccount }
            if ($parsed.PSObject.Properties.Name -contains 'container')      { $manifest.container = [string]$parsed.container }
            if ($parsed.PSObject.Properties.Name -contains 'reports' -and $null -ne $parsed.reports) {
                $manifest.reports = @($parsed.reports)
            }
        }

        return $manifest
    }
    finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

function Add-OrUpdate-ReportsManifestEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Manifest,

        [Parameter(Mandatory)]
        [hashtable]$Entry
    )

    $reports = [System.Collections.Generic.List[object]]::new()
    foreach ($r in @($Manifest.reports)) { [void]$reports.Add($r) }

    for ($i = $reports.Count - 1; $i -ge 0; $i--) {
        $existingName = [string]$reports[$i].filename
        if ($existingName -eq [string]$Entry.filename) {
            $reports.RemoveAt($i)
        }
    }

    [void]$reports.Add([pscustomobject]$Entry)
    $Manifest.reports = @($reports | Sort-Object -Property date -Descending)
    $Manifest.generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")

    return $Manifest
}

function Save-ReportsManifestObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $StorageContext,

        [Parameter(Mandatory)]
        [string]$ContainerName,

        [Parameter(Mandatory)]
        [hashtable]$Manifest,

        [string]$ManifestBlobName = "reports-manifest.json"
    )

    $json = $Manifest | ConvertTo-Json -Depth 20
    $tempFile = [System.IO.Path]::GetTempFileName()

    try {
        [System.IO.File]::WriteAllText($tempFile, $json, [System.Text.UTF8Encoding]::new($false))
        Set-AzStorageBlobContent -File $tempFile -Container $ContainerName -Blob $ManifestBlobName -Context $StorageContext -Force | Out-Null
    }
    finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

function Get-BlobMarkdownContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName
    )
    
    try {
        if (-not $FileName.EndsWith('.md')) {
            $FileName = "$FileName.md"
        }
        
        Write-ScriptLog ('Retrieving markdown file: {0}' -f $FileName) -Level Info

        if (-not $Script:IsAzureAutomation) {
            # Local development - support custom template folder and legacy/default paths.
            $templatePaths = [System.Collections.Generic.List[string]]::new()
            if ($Script:LocalConfig -and $Script:LocalConfig.PromptTemplatesLocalPath) {
                $templatePaths.Add((Join-Path $Script:LocalConfig.PromptTemplatesLocalPath $FileName))
            }
            $templatePaths.Add((Join-Path '.\Templates' $FileName))
            $templatePaths.Add((Join-Path '.' $FileName))

            $localPath = $templatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($localPath) {
                Write-ScriptLog ('Loading local template: {0}' -f $localPath) -Level Info
                $content = Get-Content $localPath -Raw -Encoding UTF8
                if ([string]::IsNullOrWhiteSpace($content)) {
                    throw ('Local template file is empty: {0}' -f $localPath)
                }
                Write-ScriptLog ('Successfully retrieved {0} ({1} characters)' -f $FileName, $content.Length) -Level Success
                return $content
            }

            throw ('Local template file not found in configured/default paths: {0}' -f ($templatePaths -join '; '))
        }

        # Azure Automation - use blob storage
        # Ensure we have a valid Azure context
        $azContext = Get-AzContext
        if (-not $azContext) {
            Write-ScriptLog 'No Azure context found, connecting with managed identity...' -Level Warning
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
            Write-ScriptLog 'Successfully authenticated with managed identity' -Level Success
        }

        # Get storage account key for authentication
        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $Script:BlobConfig.ResourceGroupName -Name $Script:BlobConfig.StorageAccountName)[0].Value
        $Context = New-AzStorageContext -StorageAccountName $Script:BlobConfig.StorageAccountName -StorageAccountKey $storageKey

        # Check if blob exists
        $blob = Get-AzStorageBlob -Container $Script:BlobConfig.PromptContainerName -Blob $FileName -Context $Context -ErrorAction SilentlyContinue
        
        if (-not $blob) {
            # List available blobs for debugging
            Write-ScriptLog ('Blob ''{0}'' not found. Available blobs in container ''{1}'':' -f $FileName, $Script:BlobConfig.PromptContainerName) -Level Warning
            $availableBlobs = Get-AzStorageBlob -Container $Script:BlobConfig.PromptContainerName -Context $Context -ErrorAction SilentlyContinue
            if ($availableBlobs) {
                $availableBlobs | ForEach-Object { Write-ScriptLog "  - $($_.Name)" -Level Debug }
            } else {
                Write-ScriptLog "  No blobs found or unable to list container contents" -Level Warning
            }
            throw ('Markdown file ''{0}'' not found in container ''{1}''' -f $FileName, $Script:BlobConfig.PromptContainerName)
        }
        
        $tempFile = [System.IO.Path]::GetTempFileName()
        
        try {
            Write-ScriptLog ('Downloading blob to temporary file: {0}' -f $tempFile) -Level Debug
            Get-AzStorageBlobContent -Container $Script:BlobConfig.PromptContainerName -Blob $FileName -Destination $tempFile -Context $Context -Force -ErrorAction Stop | Out-Null
            
            if (-not (Test-Path $tempFile)) {
                throw "Failed to download blob - temporary file not created"
            }
            
            $content = Get-Content -Path $tempFile -Raw -Encoding UTF8
            
            if ([string]::IsNullOrWhiteSpace($content)) {
                throw "Downloaded file is empty or contains only whitespace"
            }
            
            Write-ScriptLog ('Successfully retrieved {0} ({1} characters)' -f $FileName, $content.Length) -Level Success
            return $content
            
        } finally {
            if (Test-Path $tempFile) {
                Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        
    } catch {
        Write-ScriptLog ('Failed to get markdown file ''{0}'': {1}' -f $FileName, $_.Exception.Message) -Level Error
        Write-ScriptLog ('Container: {0}' -f $Script:BlobConfig.PromptContainerName) -Level Error
        Write-ScriptLog ('Storage Account: {0}' -f $Script:BlobConfig.StorageAccountName) -Level Error
        throw
    }
}

function Write-ScriptLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info',
        
        [string]$Category = 'General'
    )
    
    if ($Level -eq 'Debug' -and -not $Script:Config.Logging.EnableDebug) { return }
    
    $timestamp = Get-Date -Format $Script:Config.Logging.TimestampFormat
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Console logging (existing functionality)
    switch ($Level) {
        'Debug'   { Write-Host $logEntry -ForegroundColor DarkGray }
        'Info'    { Write-Host $logEntry -ForegroundColor Cyan }
        'Success' { Write-Host $logEntry -ForegroundColor Green }
        'Warning' { Write-Host $logEntry -ForegroundColor Yellow }
        'Error'   { Write-Host $logEntry -ForegroundColor Red }
    }
    
    # Enhanced blob logging with category
    Write-BlobLog -Message $Message -Level $Level -Category $Category
}

function Invoke-TextCleanup {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string]$Text,
        
        [ValidateSet('Markdown', 'Json', 'Plain')]
        [string]$ProcessingType = 'Markdown'
    )
    
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    
    switch ($ProcessingType) {
        'Markdown' {
            $cleaned = $Text -replace '\*\*([^*]+)\*\*', '$1'
            $cleaned = $cleaned -replace '\*([^*]+)\*', '$1'
            $cleaned = $cleaned -replace '`([^`]+)`', '$1'
            $cleaned = $cleaned -replace '#+ ', ''
            $cleaned = $cleaned -replace '(?m)^>\s*', ''
            return $cleaned.Trim()
        }
        'Json' {
            return $Text.Trim()
        }
        'Plain' {
            return $Text.Trim()
        }
    }
}

#endregion

#region Authentication and API Functions

function Get-AIEndpoint {
    [CmdletBinding()]
    param()
    
    if ($Script:Constants.UseClaudeModel) {
        # Claude/Anthropic endpoint format - model goes in request body, not URL
        return $Script:Constants.ClaudeEndpoint
    } else {
        # Azure OpenAI endpoint format
        return "$($Script:Constants.AzureOpenAIBaseUrl)/openai/deployments/$($Script:Constants.AzureOpenAIDeployment)/chat/completions?api-version=$($Script:Constants.AzureOpenAIApiVersion)"
    }
}

function Use-MaxCompletionTokensForAzureOpenAI {
    [CmdletBinding()]
    param()

    if ($Script:Constants.UseClaudeModel) {
        return $false
    }

    $deploymentName = [string]$Script:Constants.AzureOpenAIDeployment
    return $deploymentName -match '^(?i:gpt-5|o1|o3|o4)'
}

function Test-AzureOpenAIDeployment {
    [CmdletBinding()]
    param(
        [int]$TimeoutSeconds = 45
    )

    if ($Script:Constants.UseClaudeModel) {
        Write-ScriptLog "Skipping Azure OpenAI preflight check because UseClaudeModel is enabled" -Level Info -Category "Configuration"
        return
    }

    $testRequest = @{
        messages = @(
            @{ role = 'system'; content = 'Health check.' },
            @{ role = 'user'; content = 'Respond with OK.' }
        )
        model = $Script:Constants.AzureOpenAIDeployment
        temperature = 0
    }

    if (Use-MaxCompletionTokensForAzureOpenAI) {
        $testRequest.max_completion_tokens = 8
    } else {
        $testRequest.max_tokens = 8
    }

    try {
        $null = Invoke-AuthenticatedApiCall -Url (Get-AIEndpoint) -Method POST -RequestBody $testRequest -ApiKey $Script:Constants.AzureOpenAIApiKey -TimeoutSeconds $TimeoutSeconds
        Write-ScriptLog "Azure OpenAI deployment preflight check passed" -Level Success -Category "Configuration"
    } catch {
        throw "Azure OpenAI preflight failed for deployment '$($Script:Constants.AzureOpenAIDeployment)' with api-version '$($Script:Constants.AzureOpenAIApiVersion)'. $($_.Exception.Message)"
    }
}

# Legacy function name for backward compatibility
function Get-AzureOpenAIEndpoint {
    [CmdletBinding()]
    param()
    return Get-AIEndpoint
}

function Get-AccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TokenUrl,
        
        [Parameter(Mandatory)]
        [string]$ClientId,
        
        [Parameter(Mandatory)]
        [string]$ClientSecret,
        
        [string]$Scope
    )
    
    try {
        Write-ScriptLog "Requesting OAuth token for API authentication" -Level Info
        
        $authBody = @{
            grant_type = "client_credentials"
            client_id = $ClientId
            client_secret = $ClientSecret
        }
        
        if ($Scope) { $authBody.scope = $Scope }
        
        $token = $(Invoke-RestMethod -Method Post -Uri $TokenUrl -Body $authBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop).access_token
        
        Write-ScriptLog "OAuth token retrieved successfully" -Level Success
        return $token
        
    } catch {
        Write-ScriptLog "OAuth token request failed: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Add-QueryParamIfMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$ParamName,

        [Parameter(Mandatory)]
        [string]$ParamValue
    )

    $pattern = '(?i)(?:\?|&)' + [regex]::Escape($ParamName) + '='
    if ($Url -match $pattern) {
        return $Url
    }

    $separator = if ($Url.Contains('?')) { '&' } else { '?' }
    return "{0}{1}{2}={3}" -f $Url, $separator, $ParamName, [System.Uri]::EscapeDataString($ParamValue)
}

function Invoke-AuthenticatedApiCall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        
        [string]$AccessToken,
        
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method = 'GET',
        
        [object]$RequestBody,
        
        [int]$TimeoutSeconds = 300,
        
        [string]$ApiKey,
        
        [switch]$IsClaudeApi
    )
    
    try {
        # Choose authentication method based on parameters
        if ($ApiKey) {
            if ($IsClaudeApi -or $Script:Constants.UseClaudeModel) {
                # Claude/Anthropic API authentication - uses x-api-key header
                $headers = @{
                    "x-api-key" = $ApiKey
                    "anthropic-version" = $Script:Constants.ClaudeApiVersion
                }
            } else {
                # Azure OpenAI API key authentication
                $headers = @{
                    "api-key" = $ApiKey
                }
            }
        } else {
            # OAuth Bearer token authentication (for ServiceNow)
            $headers = @{
                Authorization = "Bearer $AccessToken"
            }
        }
        
        $requestParams = @{
            Method = $Method
            Uri = $Url
            Headers = $headers
            TimeoutSec = $TimeoutSeconds
            ErrorAction = 'Stop'
            ContentType = 'application/json; charset=utf-8'
        }
        
        if ($RequestBody -and $Method -in @('POST', 'PUT')) {
            $requestBodyJson = if ($RequestBody -is [string]) { 
                $RequestBody 
            } else { 
                $RequestBody | ConvertTo-Json -Depth 10 -Compress
            }
            
            # Convert to UTF8 byte array for consistent encoding across PowerShell versions
            $requestParams.Body = [System.Text.Encoding]::UTF8.GetBytes($requestBodyJson)
        }
        
        $response = Invoke-RestMethod @requestParams
        Write-ScriptLog "$Method API request completed successfully" -Level Success
        
        return $response
        
    } catch {
        Write-ScriptLog "API Call Error: $($_.Exception.Message)" -Level Error
        
        # Extract HTTP status code and detailed error from response (cross-PS version compatible)
        if ($_.Exception.Response) {
            try {
                $statusCode = $null
                $statusDescription = ""
                $responseBody = ""
                $responseObj = $_.Exception.Response

                if ($responseObj -is [System.Net.Http.HttpResponseMessage]) {
                    $statusCode = [int]$responseObj.StatusCode
                    $statusDescription = [string]$responseObj.ReasonPhrase
                    if ($responseObj.Content) {
                        $responseBody = $responseObj.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    }
                } else {
                    $statusCode = [int]$responseObj.StatusCode
                    $statusDescription = $responseObj.StatusDescription

                    if ($responseObj.GetResponseStream) {
                        $responseStream = $responseObj.GetResponseStream()
                        $reader = New-Object System.IO.StreamReader($responseStream)
                        $responseBody = $reader.ReadToEnd()
                        $reader.Close()
                        $responseStream.Close()
                    }
                }

                Write-ScriptLog "HTTP Status: $statusCode - $statusDescription" -Level Error

                if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
                    Write-ScriptLog "API Error Response: $responseBody" -Level Error
                }
                
                # Try to parse as JSON for better readability
                try {
                    $errorJson = $responseBody | ConvertFrom-Json
                    if ($errorJson.error) {
                        Write-ScriptLog "Parsed Error: $($errorJson.error | ConvertTo-Json -Depth 5 -Compress)" -Level Error
                    }
                    if ($errorJson.message) {
                        Write-ScriptLog "Error Message: $($errorJson.message)" -Level Error
                    }
                } catch {
                    # Response body is not JSON, already logged as plain text
                }
                
            } catch {
                Write-ScriptLog "Could not read error response: $($_.Exception.Message)" -Level Warning
            }
        }
        
        # Log ErrorDetails if available (PowerShell's additional error info)
        if ($_.ErrorDetails) {
            Write-ScriptLog "PowerShell ErrorDetails: $($_.ErrorDetails.Message)" -Level Error
        }
        
        Write-ScriptLog "$Method API request failed" -Level Error
        throw
    }
}

#endregion

#region AI Processing Functions

function New-AiRequestBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SystemPrompt,
        
        [Parameter(Mandatory)]
        [string]$UserContent,
        
        [ValidateSet('Cleanup', 'Summary', 'Category')]
        [string]$TaskType = 'Summary'
    )
    
    if ($Script:Constants.UseClaudeModel) {
        # Claude/Anthropic API format
        return @{
            model = $Script:Constants.ClaudeDeployment
            max_tokens = $Script:Config.AI.MaxTokens
            temperature = $Script:Config.AI.Temperature.$TaskType
            system = $SystemPrompt
            messages = @(
                @{
                    role = "user"
                    content = $UserContent
                }
            )
        }
    } else {
        # Azure OpenAI API format
        $requestBody = @{
            messages = @(
                @{
                    role = "system"
                    content = $SystemPrompt
                },
                @{
                    role = "user" 
                    content = $UserContent
                }
            )
            model = $Script:Constants.AzureOpenAIDeployment
            temperature = $Script:Config.AI.Temperature.$TaskType
            top_p = $Script:Config.AI.TopP
            frequency_penalty = $Script:Config.AI.FrequencyPenalty
            presence_penalty = $Script:Config.AI.PresencePenalty
            stop = $null
        }

        if (Use-MaxCompletionTokensForAzureOpenAI) {
            $requestBody.max_completion_tokens = $Script:Config.AI.MaxTokens
        } else {
            $requestBody.max_tokens = $Script:Config.AI.MaxTokens
        }

        return $requestBody
    }
}

function Get-CleanedWorkNotes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Incident
    )
    
    $workNotesData = @{
        work_notes = $Incident.work_notes
        close_notes = $Incident.close_notes
    }
    # Use -Compress for consistent JSON formatting across PowerShell versions
    $workNotesJson = $workNotesData | ConvertTo-Json -Depth 5 -Compress
    $requestBody = New-AiRequestBody -SystemPrompt $Script:PromptTemplates.WorkNotesCleanup -UserContent $workNotesJson -TaskType 'Cleanup'
    
    $apiKey = if ($Script:Constants.UseClaudeModel) { $Script:Constants.ClaudeApiKey } else { $Script:Constants.AzureOpenAIApiKey }
    $aiResponse = Invoke-AuthenticatedApiCall -Url (Get-AIEndpoint) -Method POST -RequestBody $requestBody -ApiKey $apiKey -IsClaudeApi:$Script:Constants.UseClaudeModel
    
    # Extract content based on API type
    $cleanedNotes = if ($Script:Constants.UseClaudeModel) {
        $aiResponse.content[0].text | Invoke-TextCleanup -ProcessingType Markdown
    } else {
        $aiResponse.choices[0].message.content | Invoke-TextCleanup -ProcessingType Markdown
    }
    
    # Log cleaned work notes (truncated for readability)
    $truncatedNotes = if ($cleanedNotes.Length -gt 500) { 
        $cleanedNotes.Substring(0, 500) + "..." 
    } else { 
        $cleanedNotes 
    }
    Write-ScriptLog "Cleaned work notes for $($Incident.number): $truncatedNotes" -Level Info -Category "WorkNotes"
    
    return $cleanedNotes
}

function Get-IncidentSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CleanedNotes,
        
        [Parameter(Mandatory)]
        [string]$IncidentNumber
    )
    
    $systemPrompt = $Script:PromptTemplates.WorkNotesSummary + "`n`n" + $Script:PromptTemplates.IntuneEnvironmentContext
    $requestBody = New-AiRequestBody -SystemPrompt $systemPrompt -UserContent $CleanedNotes -TaskType 'Summary'
    
    $apiKey = if ($Script:Constants.UseClaudeModel) { $Script:Constants.ClaudeApiKey } else { $Script:Constants.AzureOpenAIApiKey }
    $aiResponse = Invoke-AuthenticatedApiCall -Url (Get-AIEndpoint) -Method POST -RequestBody $requestBody -ApiKey $apiKey -IsClaudeApi:$Script:Constants.UseClaudeModel
    
    # Extract content based on API type
    $summary = if ($Script:Constants.UseClaudeModel) {
        $aiResponse.content[0].text | Invoke-TextCleanup -ProcessingType Markdown
    } else {
        $aiResponse.choices[0].message.content | Invoke-TextCleanup -ProcessingType Markdown
    }
    
    # Log generated summary
    Write-ScriptLog "Generated summary for ${IncidentNumber}: $summary" -Level Info -Category "AISummary"
    
    return $summary
}

function Get-IncidentCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$IncidentData,

        [Parameter(Mandatory = $false)]
        [hashtable]$RuleResult
    )
    
    try {
        $systemPrompt = $Script:PromptTemplates.TicketCategorisation + "`n`n" + $Script:PromptTemplates.IntuneEnvironmentContext
        # $systemPrompt = $Script:PromptTemplates.TicketCategorisation 
        
        # Convert to JSON with consistent formatting - use Compress to avoid whitespace issues
        $incidentJson = $IncidentData | ConvertTo-Json -Depth 4 -Compress

        # Optional rule-based pre-classification hint for AI (supporting evidence only)
        $userContent = $incidentJson
        if ($RuleResult) {
            $ruleCategory = if ($RuleResult.ContainsKey('Category')) { [string]$RuleResult.Category } else { '' }
            $ruleConfidence = if ($RuleResult.ContainsKey('Confidence')) { [string]$RuleResult.Confidence } else { '' }
            $matchedKeywordsRaw = if ($RuleResult.ContainsKey('MatchedKeywords')) { $RuleResult.MatchedKeywords } else { $null }

            $hasRuleCategory = -not [string]::IsNullOrWhiteSpace($ruleCategory)
            $isEligibleConfidence = $ruleConfidence -in @('High', 'Medium')

            if ($hasRuleCategory -and $isEligibleConfidence) {
                $matchedKeywordsText = if ($matchedKeywordsRaw -is [System.Collections.IEnumerable] -and -not ($matchedKeywordsRaw -is [string])) {
                    (($matchedKeywordsRaw | ForEach-Object { [string]$_ }) -join ', ')
                } elseif (-not [string]::IsNullOrWhiteSpace([string]$matchedKeywordsRaw)) {
                    [string]$matchedKeywordsRaw
                } else {
                    'None'
                }

                $ruleHintBlock = @(
                    'A keyword pre-classifier suggests this may be: ' + $ruleCategory + '. Evaluate independently and override if evidence contradicts it.',
                    '--- Rule-Based Pre-Classification ---',
                    'Category: ' + $ruleCategory,
                    'Confidence: ' + $ruleConfidence,
                    'Matched Keywords: ' + $matchedKeywordsText,
                    '--- End Pre-Classification ---'
                ) -join "`n"

                # Place hint before ticket content in user message
                $userContent = $ruleHintBlock + "`n`n" + $incidentJson
            }
        }
        
        # Validate JSON before sending
        try {
            $null = $incidentJson | ConvertFrom-Json
        } catch {
            Write-ScriptLog "WARNING: Incident JSON validation failed: $($_.Exception.Message)" -Level Warning -Category "Categorization"
            throw "Invalid JSON generated from incident data"
        }
        
        $requestBody = New-AiRequestBody -SystemPrompt $systemPrompt -UserContent $userContent -TaskType 'Category'
        
        # Validate the complete request body before sending
        try {
            $testJson = $requestBody | ConvertTo-Json -Depth 10 -Compress
            $null = $testJson | ConvertFrom-Json
        } catch {
            Write-ScriptLog "ERROR: Request body JSON validation failed: $($_.Exception.Message)" -Level Error -Category "Categorization"
            throw "Invalid JSON in request body"
        }
        
        $apiKey = if ($Script:Constants.UseClaudeModel) { $Script:Constants.ClaudeApiKey } else { $Script:Constants.AzureOpenAIApiKey }
        $aiResponse = Invoke-AuthenticatedApiCall -Url (Get-AIEndpoint) -Method POST -RequestBody $requestBody -ApiKey $apiKey -IsClaudeApi:$Script:Constants.UseClaudeModel
        
        # Extract content based on API type
        $responseText = if ($Script:Constants.UseClaudeModel) {
            $aiResponse.content[0].text
        } else {
            $aiResponse.choices[0].message.content
        }
        
        $categoryInfo = ConvertFrom-AiCategoryResponse -ResponseText $responseText
        
            # DEBUG: Log raw AI response to diagnose parsing issues
            Write-ScriptLog "DEBUG: Raw AI response for $($IncidentData.IncidentNumber):`n$responseText" -Level Info -Category "Categorization"

            # Log categorization results with reasoning
            Write-ScriptLog "Category selected for $($IncidentData.IncidentNumber): $($categoryInfo.primary_category) (Confidence: $($categoryInfo.confidence_level))" -Level Info -Category "Categorization"
        if ($categoryInfo.reasoning) {
            Write-ScriptLog "AI reasoning for $($IncidentData.IncidentNumber): $($categoryInfo.reasoning)" -Level Info -Category "Categorization"
        }
        
        return $categoryInfo
        
    } catch {
        Write-ScriptLog "ERROR in Get-IncidentCategory for $($IncidentData.IncidentNumber): $($_.Exception.Message)" -Level Error -Category "Categorization"
        throw
    }
}

function ConvertFrom-AiCategoryResponse {
    [CmdletBinding()]
    param([string]$ResponseText)
    
    $cleanText = $ResponseText.Trim()
    $result = @{}

    function Set-ResultField {
        param(
            [string]$TargetName,
            [object]$Value
        )

        if ($null -ne $Value) {
            $textValue = [string]$Value
            if (-not [string]::IsNullOrWhiteSpace($textValue)) {
                $result[$TargetName] = $textValue.Trim()
            }
        }
    }

    function Sanitize-PrimaryCategory {
        param([string]$CategoryValue)

        if ([string]::IsNullOrWhiteSpace($CategoryValue)) {
            return $CategoryValue
        }

        $sanitizedValue = $CategoryValue.Trim()
        if ($sanitizedValue -notmatch '^[\"'':\{]') {
            return $sanitizedValue
        }

        $jsonCategoryPatterns = @(
            '(?is)"(?:Category|Primary Category|primary_category)"\s*:\s*"(?<category>[^"]+)"',
            "(?is)'(?:Category|Primary Category|primary_category)'\s*:\s*'(?<category>[^']+)'",
            '(?is)(?:Category|Primary Category|primary_category)\s*[:=]\s*"?(?<category>[^"'',\r\n}]+)'
        )

        foreach ($pattern in $jsonCategoryPatterns) {
            $categoryMatch = [regex]::Match($sanitizedValue, $pattern)
            if ($categoryMatch.Success) {
                $extractedCategory = $categoryMatch.Groups['category'].Value.Trim()
                if (-not [string]::IsNullOrWhiteSpace($extractedCategory)) {
                    return $extractedCategory
                }
            }
        }

        return $sanitizedValue
    }

    function Map-JsonResponse {
        param([object]$JsonObject)

        if ($null -eq $JsonObject) { return $false }

        $source = $JsonObject
        if ($source -is [System.Collections.IEnumerable] -and -not ($source -is [string])) {
            $source = @($source)[0]
        }

        if ($null -eq $source) { return $false }

        $propertyNames = @($source.PSObject.Properties.Name)
        if ($propertyNames.Count -eq 0) { return $false }

        Set-ResultField -TargetName 'primary_category' -Value $source.Category
        if (-not $result.ContainsKey('primary_category')) { Set-ResultField -TargetName 'primary_category' -Value $source.'Primary Category' }
        if (-not $result.ContainsKey('primary_category')) { Set-ResultField -TargetName 'primary_category' -Value $source.primary_category }

        Set-ResultField -TargetName 'confidence_level' -Value $source.Confidence
        if (-not $result.ContainsKey('confidence_level')) { Set-ResultField -TargetName 'confidence_level' -Value $source.'Confidence Level' }
        if (-not $result.ContainsKey('confidence_level')) { Set-ResultField -TargetName 'confidence_level' -Value $source.confidence_level }

        Set-ResultField -TargetName 'reasoning' -Value $source.Reasoning
        if (-not $result.ContainsKey('reasoning')) { Set-ResultField -TargetName 'reasoning' -Value $source.reasoning }

        Set-ResultField -TargetName 'key_evidence' -Value $source.Evidence
        if (-not $result.ContainsKey('key_evidence')) { Set-ResultField -TargetName 'key_evidence' -Value $source.'Key Evidence' }
        if (-not $result.ContainsKey('key_evidence')) { Set-ResultField -TargetName 'key_evidence' -Value $source.key_evidence }

        Set-ResultField -TargetName 'resolution_summary' -Value $source.ResolutionSummary
        if (-not $result.ContainsKey('resolution_summary')) { Set-ResultField -TargetName 'resolution_summary' -Value $source.'Resolution Summary' }
        if (-not $result.ContainsKey('resolution_summary')) { Set-ResultField -TargetName 'resolution_summary' -Value $source.resolution_summary }

        Set-ResultField -TargetName 'how_do_i_or_error' -Value $source.'How Do I or Error'
        if (-not $result.ContainsKey('how_do_i_or_error')) { Set-ResultField -TargetName 'how_do_i_or_error' -Value $source.how_do_i_or_error }

        Set-ResultField -TargetName 'kb_provided' -Value $source.'KB Provided'
        if (-not $result.ContainsKey('kb_provided')) { Set-ResultField -TargetName 'kb_provided' -Value $source.kb_provided }

        Set-ResultField -TargetName 'exclusion_reason' -Value $source.'Exclusion Reason'
        if (-not $result.ContainsKey('exclusion_reason')) { Set-ResultField -TargetName 'exclusion_reason' -Value $source.exclusion_reason }

        return $true
    }

    # Prefer structured JSON when the model returns it.
    try {
        $parsedJson = $cleanText | ConvertFrom-Json -ErrorAction Stop
        if (Map-JsonResponse -JsonObject $parsedJson) {
            if ($result.ContainsKey('primary_category')) {
                $result['primary_category'] = Sanitize-PrimaryCategory -CategoryValue $result['primary_category']
            }
            if (-not $result.ContainsKey('primary_category')) { $result['primary_category'] = '' }
            if (-not $result.ContainsKey('confidence_level')) { $result['confidence_level'] = '' }
            return [PSCustomObject]$result
        }
    } catch {
        # Fall back to regex parsing below.
    }
    
    # Patterns handle optional markdown bold formatting (**) around field names
    $patterns = @{
        'primary_category' = "(?s)\*{0,2}(?:Primary Category|Category):?\*{0,2}\s*(.+?)(?=\n\*{0,2}Exclusion|\n\*{0,2}Confidence|\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\Z)"
        'exclusion_reason' = "(?s)\*{0,2}Exclusion Reason:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Confidence|\n\*{0,2}Reasoning|\Z)"
        'confidence_level' = "(?s)\*{0,2}(?:Confidence Level|Confidence):?\*{0,2}\s*(.+?)(?=\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\n\*{0,2}Resolution|\Z)"
        'reasoning' = "(?s)\*{0,2}Reasoning:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Key Evidence|\n\*{0,2}Resolution Summary|\n\*{0,2}How Do I|\Z)"
        'key_evidence' = "(?s)\*{0,2}(?:Key Evidence|Evidence):?\*{0,2}\s*(.+?)(?=\n\*{0,2}Resolution Summary|\n\*{0,2}How Do I|\Z)"
        'resolution_summary' = "(?s)\*{0,2}(?:Resolution Summary|Resolution):?\*{0,2}\s*(.+?)(?=\n\*{0,2}How Do I|\n\*{0,2}KB Provided|\Z)"
        'how_do_i_or_error' = "(?s)\*{0,2}How Do I or Error:?\*{0,2}\s*(.+?)(?=\n\*{0,2}KB Provided|\Z)"
        'kb_provided' = "(?s)\*{0,2}KB Provided:?\*{0,2}\s*(.+)"
    }
    
    foreach ($key in $patterns.Keys) {
        if ($cleanText -match $patterns[$key]) {
            $value = $matches[1].Trim() -replace '^"(.+)"$', '$1'
            # Remove any trailing markdown bold markers and clean up
            $value = $value -replace '\*{2,}$', ''
            $result[$key] = $value.Trim()
        }
    }

    if ($result.ContainsKey('primary_category')) {
        $result['primary_category'] = Sanitize-PrimaryCategory -CategoryValue $result['primary_category']
    }

    if (-not $result.ContainsKey('primary_category')) { $result['primary_category'] = '' }
    if (-not $result.ContainsKey('confidence_level')) { $result['confidence_level'] = '' }
    
    return [PSCustomObject]$result
}

#endregion

#region Data Storage Functions (Local & Blob)

function Save-IncidentsData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Incidents
    )
    
    try {
        # Generate filename with timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $fileName = "incidents_$timestamp.json"
        
        # Convert incidents to JSON
        $jsonContent = $Incidents | ConvertTo-Json -Depth 10 -Compress
        
        if ($Script:IsAzureAutomation) {
            # Azure Automation - save to blob storage
            Write-ScriptLog "Saving incident data to blob storage..." -Level Info
            
            $storageContext = Get-StorageContext
            
            # Create temp file for upload
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tempFile -Value $jsonContent -Encoding UTF8
                
                # Upload to blob storage
                Set-AzStorageBlobContent -File $tempFile `
                    -Container $Script:BlobConfig.DataContainerName `
                    -Blob $fileName `
                    -Context $storageContext `
                    -Force | Out-Null
                
                Write-ScriptLog "Raw incident data saved to blob: $fileName (Container: $($Script:BlobConfig.DataContainerName))" -Level Success
                Write-Host ("Raw incident data saved to blob: {0}" -f $fileName) -ForegroundColor Green
                
                return $fileName
                
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
            
        } else {
            # Local development - save to data directory
            $dataDir = ".\data"
            if (-not (Test-Path $dataDir)) {
                New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
                Write-ScriptLog "Created data directory: $dataDir" -Level Info
            }
            
            $filePath = Join-Path $dataDir $fileName
            Set-Content -Path $filePath -Value $jsonContent -Encoding UTF8
            
            Write-ScriptLog "Raw incident data saved locally: $filePath" -Level Success
            Write-Host ("Raw incident data saved to: {0}" -f $filePath) -ForegroundColor Green
            
            return $filePath
        }
        
    } catch {
        Write-ScriptLog "Failed to save incident data: $($_.Exception.Message)" -Level Error
        Write-Host ("Failed to save incident data: {0}" -f $_.Exception.Message) -ForegroundColor Red
        throw
    }
}

function Get-StoredIncidents {
    [CmdletBinding()]
    param(
        [string]$FileName = $null
    )
    
    try {
        if ($Script:IsAzureAutomation) {
            # Azure Automation - load from blob storage
            Write-ScriptLog "Loading stored incident data from blob storage..." -Level Info
            
            $storageContext = Get-StorageContext
            
            if ($FileName) {
                # Use specific file
                $blobName = $FileName
            } else {
                # Get latest file from blob storage
                $blobs = Get-AzStorageBlob -Container $Script:BlobConfig.DataContainerName `
                    -Context $storageContext `
                    -Prefix "incidents_" | 
                    Sort-Object LastModified -Descending
                
                if ($blobs.Count -eq 0) {
                    throw "No incident files found in blob container: $($Script:BlobConfig.DataContainerName)"
                }
                
                $blobName = $blobs[0].Name
            }
            
            # Download blob content
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Get-AzStorageBlobContent -Container $Script:BlobConfig.DataContainerName `
                    -Blob $blobName `
                    -Destination $tempFile `
                    -Context $storageContext `
                    -Force | Out-Null
                
                $jsonContent = Get-Content -Path $tempFile -Raw -Encoding UTF8
                $incidents = $jsonContent | ConvertFrom-Json
                
                Write-ScriptLog "Successfully loaded $($incidents.Count) incidents from blob: $blobName" -Level Success
                Write-Host ("Loaded {0} incidents from blob: {1}" -f $incidents.Count, $blobName) -ForegroundColor Green
                
                return $incidents
                
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
            
        } else {
            # Local development - load from data directory
            $dataDir = ".\data"
            
            if (-not (Test-Path $dataDir)) {
                throw "Data directory does not exist: $dataDir"
            }
            
            if ($FileName) {
                # Use specific file
                $filePath = Join-Path $dataDir $FileName
                if (-not (Test-Path $filePath)) {
                    throw "Specified incident file not found: $filePath"
                }
            } else {
                # Use latest incident file
                $incidentFiles = Get-ChildItem -Path $dataDir -Filter "incidents_*.json" | Sort-Object LastWriteTime -Descending
                if ($incidentFiles.Count -eq 0) {
                    throw "No incident files found in $dataDir"
                }
                $filePath = $incidentFiles[0].FullName
            }
            
            Write-ScriptLog "Loading stored incident data from: $filePath" -Level Info
            
            $jsonContent = Get-Content -Path $filePath -Raw -Encoding UTF8
            $incidents = $jsonContent | ConvertFrom-Json
            
            Write-ScriptLog "Successfully loaded $($incidents.Count) incidents from stored data" -Level Success
            Write-Host ("Loaded {0} incidents from: {1}" -f $incidents.Count, [System.IO.Path]::GetFileName($filePath)) -ForegroundColor Green
            
            return $incidents
        }
        
    } catch {
        Write-ScriptLog "Failed to load stored incident data: $($_.Exception.Message)" -Level Error
        Write-Host ("Failed to load stored incident data: {0}" -f $_.Exception.Message) -ForegroundColor Red
        throw
    }
}

function Get-AvailableIncidentFiles {
    [CmdletBinding()]
    param()
    
    try {
        if ($Script:IsAzureAutomation) {
            # Azure Automation - list blobs from data container
            $storageContext = Get-StorageContext
            $blobs = Get-AzStorageBlob -Container $Script:BlobConfig.DataContainerName `
                -Context $storageContext `
                -Prefix "incidents_" -ErrorAction SilentlyContinue | 
                Sort-Object LastModified -Descending
            
            if ($blobs.Count -gt 0) {
                Write-Host "Available incident files in blob storage:" -ForegroundColor Cyan
                foreach ($blob in $blobs) {
                    $lastModifiedText = Get-Date $blob.LastModified -Format 'yyyy-MM-dd HH:mm:ss'
                    $sizeKb = [math]::Round($blob.Length / 1KB, 1)
                    $fileInfo = '  - {0} ({1}, {2} KB)' -f $blob.Name, $lastModifiedText, $sizeKb
                    Write-Host $fileInfo -ForegroundColor Gray
                }
                return $blobs
            } else {
                Write-Host ('No incident files found in blob container: {0}' -f $Script:BlobConfig.DataContainerName) -ForegroundColor Yellow
                return @()
            }
        } else {
            # Local development - list files from data directory
            $dataDir = ".\data"
            if (Test-Path $dataDir) {
                $incidentFiles = Get-ChildItem -Path $dataDir -Filter "incidents_*.json" | Sort-Object LastWriteTime -Descending
                if ($incidentFiles.Count -gt 0) {
                    Write-Host "Available incident files:" -ForegroundColor Cyan
                    foreach ($file in $incidentFiles) {
                        $lastWriteText = Get-Date $file.LastWriteTime -Format 'yyyy-MM-dd HH:mm:ss'
                        $sizeKb = [math]::Round($file.Length / 1KB, 1)
                        $fileInfo = '  - {0} ({1}, {2} KB)' -f $file.Name, $lastWriteText, $sizeKb
                        Write-Host $fileInfo -ForegroundColor Gray
                    }
                    return $incidentFiles
                } else {
                    Write-Host ('No incident files found in {0}' -f $dataDir) -ForegroundColor Yellow
                    return @()
                }
            } else {
                Write-Host ('Data directory does not exist: {0}' -f $dataDir) -ForegroundColor Yellow
                return @()
            }
        }
    } catch {
        Write-ScriptLog "Failed to list incident files: $($_.Exception.Message)" -Level Warning
        return @()
    }
}

function Save-RunProcessingArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$DetailedSummaries,

        [string]$ReportPeriod,

        [string]$DataSource = "Live API"
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $fileName = "run_artifact_$timestamp.json"

        # Calculate ISO week number for this artifact
        $artifactWeekNumber = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
            (Get-Date),
            [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
            [System.DayOfWeek]::Monday
        )
        $artifactYear = (Get-Date).Year
        $artifactYearWeek = "{0:D4}-W{1:D2}" -f $artifactYear, $artifactWeekNumber

        $artifact = [PSCustomObject]@{
            RunGeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            YearWeek = $artifactYearWeek
            ReportPeriod = $ReportPeriod
            DataSource = $DataSource
            PromptVersions = @{}
            ProcessedTickets = @($Script:ProcessedTickets)
            DetailedSummaries = @($DetailedSummaries)
        }

        $artifact.PromptVersions = if ($Script:PromptVersions) { [hashtable]$Script:PromptVersions } else { @{} }

        $jsonContent = $artifact | ConvertTo-Json -Depth 15 -Compress

        if ($Script:IsAzureAutomation) {
            $storageContext = Get-StorageContext
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tempFile -Value $jsonContent -Encoding UTF8

                Set-AzStorageBlobContent -File $tempFile `
                    -Container $Script:BlobConfig.DataContainerName `
                    -Blob $fileName `
                    -Context $storageContext `
                    -Force | Out-Null

                Write-ScriptLog "Run artifact saved to blob: $fileName" -Level Success
                return $fileName
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        } else {
            $artifactDir = ".\data"
            if (-not (Test-Path $artifactDir)) {
                New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
            }

            $filePath = Join-Path $artifactDir $fileName
            Set-Content -Path $filePath -Value $jsonContent -Encoding UTF8
            Write-ScriptLog "Run artifact saved locally: $filePath" -Level Success
            return $filePath
        }
    } catch {
        Write-ScriptLog "Failed to save run artifact: $($_.Exception.Message)" -Level Warning
        return $null
    }
}

function Get-MergedWeeklyRunData {
    [CmdletBinding()]
    param(
        [int]$LookbackDays = 7
    )

    try {
        Write-ScriptLog "Merging artifacts from the last $LookbackDays day(s)" -Level Info

        $cutoffUtc = (Get-Date).ToUniversalTime().AddDays(-1 * $LookbackDays)
        $artifacts = @()

        if ($Script:IsAzureAutomation) {
            $storageContext = Get-StorageContext
            $blobs = Get-AzStorageBlob -Container $Script:BlobConfig.DataContainerName `
                -Context $storageContext `
                -Prefix "run_artifact_" -ErrorAction SilentlyContinue | 
                Sort-Object LastModified

            foreach ($blob in $blobs) {
                if ($blob.LastModified.UtcDateTime -lt $cutoffUtc) { continue }

                $tempFile = [System.IO.Path]::GetTempFileName()
                try {
                    Get-AzStorageBlobContent -Container $Script:BlobConfig.DataContainerName `
                        -Blob $blob.Name `
                        -Destination $tempFile `
                        -Context $storageContext `
                        -Force | Out-Null

                    $artifact = (Get-Content -Path $tempFile -Raw -Encoding UTF8) | ConvertFrom-Json
                    
                    # Calculate YearWeek from RunGeneratedAtUtc for old artifacts without the property
                    $artifactYearWeek = $artifact.YearWeek
                    if (-not $artifactYearWeek -and $artifact.RunGeneratedAtUtc) {
                        $artifactDate = [DateTime]::Parse($artifact.RunGeneratedAtUtc)
                        $artifactWeekNum = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
                            $artifactDate,
                            [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
                            [System.DayOfWeek]::Monday
                        )
                        $artifactYearWeek = "{0:D4}-W{1:D2}" -f $artifactDate.Year, $artifactWeekNum
                    }
                    
                    Write-ScriptLog "Including artifact $($blob.Name) - Week: $artifactYearWeek, Tickets: $($artifact.ProcessedTickets.Count)" -Level Info
                    $artifacts += $artifact
                } finally {
                    if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
                }
            }
        } else {
            $artifactDir = ".\data"
            if (Test-Path $artifactDir) {
                $files = Get-ChildItem -Path $artifactDir -Filter "run_artifact_*.json" | Sort-Object LastWriteTime
                foreach ($file in $files) {
                    if ($file.LastWriteTime.ToUniversalTime() -lt $cutoffUtc) { continue }
                    $artifact = (Get-Content -Path $file.FullName -Raw -Encoding UTF8) | ConvertFrom-Json
                    
                    # Calculate YearWeek from RunGeneratedAtUtc for old artifacts without the property
                    $artifactYearWeek = $artifact.YearWeek
                    if (-not $artifactYearWeek -and $artifact.RunGeneratedAtUtc) {
                        $artifactDate = [DateTime]::Parse($artifact.RunGeneratedAtUtc)
                        $artifactWeekNum = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
                            $artifactDate,
                            [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
                            [System.DayOfWeek]::Monday
                        )
                        $artifactYearWeek = "{0:D4}-W{1:D2}" -f $artifactDate.Year, $artifactWeekNum
                    }
                    
                    Write-ScriptLog "Including artifact $($file.Name) - Week: $artifactYearWeek, Tickets: $($artifact.ProcessedTickets.Count)" -Level Info
                    $artifacts += $artifact
                }
            }
        }

        if ($artifacts.Count -eq 0) {
            return [PSCustomObject]@{
                ProcessedTickets = [System.Collections.Generic.List[TicketAnalysis]]::new()
                DetailedSummaries = @()
            }
        }

        # Deduplicate by incident number, keeping latest version from latest artifact
        $ticketMap = @{}
        $summaryMap = @{}

        foreach ($artifact in $artifacts) {
            foreach ($ticket in @($artifact.ProcessedTickets)) {
                if (-not $ticket.Number) { continue }

                $converted = [TicketAnalysis]::new([string]$ticket.Number)
                $converted.Category = [string]$ticket.Category
                $converted.ExclusionReason = [string]$ticket.ExclusionReason
                $converted.Confidence = [string]$ticket.Confidence
                $converted.Reasoning = [string]$ticket.Reasoning
                $converted.Evidence = [string]$ticket.Evidence
                $converted.Resolution = [string]$ticket.Resolution
                $converted.Type = [string]$ticket.Type
                $converted.KnowledgeBase = [string]$ticket.KnowledgeBase
                $converted.OriginalDescription = [string]$ticket.OriginalDescription
                # Re-hydrate ResolvedAt across the JSON round-trip so per-ticket partitioning still works.
                $converted.ResolvedAt = [string]$ticket.ResolvedAt

                [DateTime]$parsedProcessed = [DateTime]::MinValue
                if ([DateTime]::TryParse([string]$ticket.Processed, [ref]$parsedProcessed)) {
                    $converted.Processed = $parsedProcessed
                }

                $ticketMap[[string]$ticket.Number] = $converted
            }

            foreach ($summary in @($artifact.DetailedSummaries)) {
                if (-not $summary.IncidentNumber) { continue }
                $summaryMap[[string]$summary.IncidentNumber] = [PSCustomObject]@{
                    IncidentNumber = [string]$summary.IncidentNumber
                    SummarisedNotes = [string]$summary.SummarisedNotes
                }
            }
        }

        $mergedTickets = [System.Collections.Generic.List[TicketAnalysis]]::new()
        foreach ($number in ($ticketMap.Keys | Sort-Object)) {
            $mergedTickets.Add($ticketMap[$number])
        }

        $mergedSummaries = @()
        foreach ($number in ($summaryMap.Keys | Sort-Object)) {
            $mergedSummaries += $summaryMap[$number]
        }

        return [PSCustomObject]@{
            ProcessedTickets = $mergedTickets
            DetailedSummaries = $mergedSummaries
            YearWeek = $currentYearWeek  # The week these artifacts belong to
        }
    } catch {
        Write-ScriptLog "Failed to merge weekly run artifacts: $($_.Exception.Message)" -Level Warning
        return [PSCustomObject]@{
            ProcessedTickets = [System.Collections.Generic.List[TicketAnalysis]]::new()
            DetailedSummaries = @()
            YearWeek = $null
        }
    }
}

function Filter-IncidentsByResolvedWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Incidents,

        [int]$LookbackHours = 26
    )

    if ($LookbackHours -le 0) {
        return $Incidents
    }

    $cutoff = (Get-Date).AddHours(-1 * $LookbackHours)
    $filtered = [System.Collections.Generic.List[object]]::new()

    foreach ($incident in $Incidents) {
        [DateTime]$resolvedAt = [DateTime]::MinValue
        if ([DateTime]::TryParse([string]$incident.resolved_at, [ref]$resolvedAt)) {
            if ($resolvedAt -ge $cutoff) {
                $filtered.Add($incident)
            }
        } else {
            # If date cannot be parsed, keep the record to avoid accidental data loss
            $filtered.Add($incident)
        }
    }

    Write-ScriptLog ("Applied resolved_at lookback filter ({0} hours): {1}/{2} incidents retained" -f $LookbackHours, $filtered.Count, $Incidents.Count) -Level Info
    return @($filtered)
}

#endregion

#region Data Processing Functions

function Invoke-FallbackCategorization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ShortDescription,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$AiCategory = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$AiConfidence = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [array]$CategoryRules = @(),

        [Parameter(Mandatory = $false)]
        [string]$Reasoning = '',

        [Parameter(Mandatory = $false)]
        [string]$Evidence = '',

        [Parameter(Mandatory = $false)]
        [string]$ResolutionSummary = ''
    )

    $normalizedConfidence = ([string]$AiConfidence).Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedConfidence)) {
        $normalizedConfidence = 'Low'
    }

    $normalizedCategory = ([string]$AiCategory).Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedCategory)) {
        $normalizedCategory = 'Other / Miscellaneous'
    }

    # Keep AI result when confidence is already reliable
    if ($normalizedConfidence -eq 'High' -or ($normalizedConfidence -eq 'Medium' -and $normalizedCategory -ne 'Other / Miscellaneous')) {
        return [PSCustomObject]@{
            Category = $normalizedCategory
            Confidence = $normalizedConfidence
            Reasoning = $Reasoning
            Evidence = $Evidence
            ResolutionSummary = $ResolutionSummary
            FallbackUsed = $false
        }
    }

    if (-not $CategoryRules -or [string]::IsNullOrWhiteSpace($ShortDescription)) {
        return [PSCustomObject]@{
            Category = $normalizedCategory
            Confidence = $normalizedConfidence
            Reasoning = $Reasoning
            Evidence = $Evidence
            ResolutionSummary = $ResolutionSummary
            FallbackUsed = $false
        }
    }

    $bestRule = $null
    $bestPriority = [int]::MinValue
    $bestMatchedKeywords = @()

    foreach ($rule in $CategoryRules) {
        if (-not $rule -or -not $rule.Name -or -not $rule.Keywords) {
            continue
        }

        $matchedKeywords = @()
        foreach ($keyword in $rule.Keywords) {
            $kw = [string]$keyword
            if ([string]::IsNullOrWhiteSpace($kw)) {
                continue
            }

            if ($ShortDescription.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $matchedKeywords += $kw
            }
        }

        if ($matchedKeywords.Count -gt 0) {
            $priority = if ($null -ne $rule.Priority) { [int]$rule.Priority } else { 0 }

            if (-not $bestRule -or $priority -gt $bestPriority -or ($priority -eq $bestPriority -and $matchedKeywords.Count -gt $bestMatchedKeywords.Count)) {
                $bestRule = $rule
                $bestPriority = $priority
                $bestMatchedKeywords = $matchedKeywords
            }
        }
    }

    if ($bestRule) {
        return [PSCustomObject]@{
            Category = [string]$bestRule.Name
            Confidence = 'Low'
            Reasoning = "Fallback: AI returned ${normalizedCategory}/${normalizedConfidence}. Keyword rule matched: $($bestRule.Name)"
            Evidence = ($bestMatchedKeywords -join ', ')
            ResolutionSummary = $ResolutionSummary
            FallbackUsed = $true
        }
    }

    return [PSCustomObject]@{
        Category = $normalizedCategory
        Confidence = $normalizedConfidence
        Reasoning = $Reasoning
        Evidence = $Evidence
        ResolutionSummary = $ResolutionSummary
        FallbackUsed = $false
    }
}

function Invoke-TicketProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Incident
    )
    
    # Determine ticket type for enhanced logging
    $ticketType = if ($Incident.number.StartsWith("INC")) { "Incident" } elseif ($Incident.number.StartsWith("SCTASK")) { "Service Request" } else { "Unknown" }
    
    Write-ScriptLog "Processing $ticketType $($Incident.number): $($Incident.short_description)" -Level Info -Category "TicketData"
    
    try {
        $cleanedNotes = Get-CleanedWorkNotes -Incident $Incident
        $summary = Get-IncidentSummary -CleanedNotes $cleanedNotes -IncidentNumber $Incident.number
        $incidentData = [PSCustomObject]@{
            IncidentNumber = $Incident.number
            "User Description" = $Incident.description
            "User Short Description" = $Incident.short_description
            "User Work Notes" = $cleanedNotes
            "Incident Duration" = $Incident.calendar_duration
            "Incident Close Code" = $Incident.close_code
            "Incident Opened At" = $Incident.opened_at
            "Incident Resolved At" = $Incident.resolved_at
            "AI Summary" = $summary
        }
        $categoryInfo = Get-IncidentCategory -IncidentData $incidentData

        # Optional fallback: if AI returns low confidence or Other/Misc, try keyword rules
        $fallbackCategoryRules = @()
        $categoryRulesVar = Get-Variable -Name CategoryRules -Scope Script -ErrorAction SilentlyContinue
        if ($categoryRulesVar -and $categoryRulesVar.Value) {
            $fallbackCategoryRules = @($categoryRulesVar.Value)
        }

        $fallbackCategoryInfo = Invoke-FallbackCategorization `
            -ShortDescription ([string]$Incident.short_description) `
            -AiCategory ([string]$categoryInfo.primary_category) `
            -AiConfidence ([string]$categoryInfo.confidence_level) `
            -CategoryRules $fallbackCategoryRules `
            -Reasoning ([string]$categoryInfo.reasoning) `
            -Evidence ([string]$categoryInfo.key_evidence) `
            -ResolutionSummary ([string]$categoryInfo.resolution_summary)

        if ($fallbackCategoryInfo.FallbackUsed) {
            Write-ScriptLog "Fallback categorization used for $($Incident.number): $($fallbackCategoryInfo.Category) (Evidence: $($fallbackCategoryInfo.Evidence))" -Level Warning -Category "Categorization"
        }
        
        $ticket = [TicketAnalysis]::new($Incident.number)
        
        # Clean up category - should be a short category name, not a long AI response
        $rawCategory = $fallbackCategoryInfo.Category
        if ($rawCategory -and $rawCategory.Length -gt 100) {
            # Category is too long - likely parsing failed, extract first line only
            $rawCategory = ($rawCategory -split "`n")[0].Trim()
        }
        # Remove any markdown formatting from category
        $rawCategory = $rawCategory -replace '\*+', ''
        
        $ticket.Category = $rawCategory
        $ticket.ExclusionReason = $categoryInfo.exclusion_reason
        $ticket.Confidence = $fallbackCategoryInfo.Confidence
        $ticket.Reasoning = $fallbackCategoryInfo.Reasoning
        $ticket.Evidence = $fallbackCategoryInfo.Evidence
        $ticket.Resolution = $fallbackCategoryInfo.ResolutionSummary
        $ticket.Type = $categoryInfo.how_do_i_or_error
        $ticket.KnowledgeBase = $categoryInfo.kb_provided
        $ticket.OriginalDescription = $Incident.short_description
        # Carry the raw resolved_at so Save-CategoryStatisticsToTable can partition by true ISO week.
        $ticket.ResolvedAt = [string]$Incident.resolved_at
        
        $Script:ProcessedTickets.Add($ticket)
        
        Write-ScriptLog "Successfully processed $ticketType $($Incident.number) - Category: $($ticket.Category)" -Level Success -Category "Processing"
        
        return [PSCustomObject]@{
            IncidentNumber = $Incident.number
            SummarisedNotes = $summary
        }
        
    } catch {
        Write-ScriptLog "Failed to process $ticketType $($Incident.number): $($_.Exception.Message)" -Level Error -Category "Processing"
        throw
    }
}

function Get-CategoryStatistics {
    [CmdletBinding()]
    param()
    
    # Return empty array if no tickets processed
    if ($Script:ProcessedTickets.Count -eq 0) {
        Write-ScriptLog "No processed tickets found - returning empty category statistics" -Level Warning
        return @()
    }
    
    # Group all Excluded tickets under a single "Excluded" category
    # Individual exclusion reasons are shown in the detail table, not the summary
    $ticketsWithDisplayCategory = $Script:ProcessedTickets | ForEach-Object {
        [PSCustomObject]@{
            Number = $_.Number
            DisplayCategory = $_.Category  # Always use raw category name ("Excluded", not per-ticket reason)
        }
    }
    
    $statistics = $ticketsWithDisplayCategory | 
                  Group-Object -Property DisplayCategory | 
                  Select-Object Name, Count, @{Name='Tickets'; Expression={$_.Group.Number}} |
                  Sort-Object Count -Descending
    
    # Ensure we always return an array
    if ($null -eq $statistics) {
        return @()
    }
    
    return $statistics
}

#endregion

#region Azure Table Storage Functions for Statistics

function Initialize-StatisticsTable {
    <#
    .SYNOPSIS
        Gets the Azure Table for storing ticket statistics - table must already exist
    .DESCRIPTION
        Validates that the statistics table exists. If not, logs an error and returns $null.
        Use Setup-StatisticsTable.ps1 to create the table before running the analyzer.
    #>
    [CmdletBinding()]
    param()
    
    try {
        $storageContext = Get-StorageContext
        $tableName = $Script:BlobConfig.StatisticsTableName
        
        # Check if table exists - DO NOT create it automatically
        $table = Get-AzStorageTable -Name $tableName -Context $storageContext -ErrorAction SilentlyContinue
        
        if (-not $table) {
            Write-ScriptLog "ERROR: Statistics table '$tableName' does not exist!" -Level Error
            Write-ScriptLog "Please run Setup-StatisticsTable.ps1 to create the table before running the analyzer." -Level Error
            Write-Host ("Statistics table '{0}' not found. Run Setup-StatisticsTable.ps1 first." -f $tableName) -ForegroundColor Red
            return $null
        }
        
        return $table.CloudTable
        
    } catch {
        Write-ScriptLog "Failed to access statistics table: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Test-CloudTableEntityExists {
    <#
    .SYNOPSIS
        Checks whether a specific entity exists in an Azure CloudTable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Table,

        [Parameter(Mandatory)]
        [string]$PartitionKey,

        [Parameter(Mandatory)]
        [string]$RowKey
    )

    $partitionFilter = [Microsoft.Azure.Cosmos.Table.TableQuery]::GenerateFilterCondition(
        'PartitionKey',
        [Microsoft.Azure.Cosmos.Table.QueryComparisons]::Equal,
        $PartitionKey
    )
    $rowFilter = [Microsoft.Azure.Cosmos.Table.TableQuery]::GenerateFilterCondition(
        'RowKey',
        [Microsoft.Azure.Cosmos.Table.QueryComparisons]::Equal,
        $RowKey
    )

    $combinedFilter = [Microsoft.Azure.Cosmos.Table.TableQuery]::CombineFilters(
        $partitionFilter,
        [Microsoft.Azure.Cosmos.Table.TableOperators]::And,
        $rowFilter
    )

    $query = [Microsoft.Azure.Cosmos.Table.TableQuery]::new()
    $query.FilterString = $combinedFilter
    $query.TakeCount = 1

    return ($null -ne ($Table.ExecuteQuery($query) | Select-Object -First 1))
}

function Set-CloudTableEntity {
    <#
    .SYNOPSIS
        Inserts or replaces an entity in an Azure CloudTable without AzTable helper cmdlets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Table,

        [Parameter(Mandatory)]
        [string]$PartitionKey,

        [Parameter(Mandatory)]
        [string]$RowKey,

        [Parameter(Mandatory)]
        [hashtable]$Properties
    )

    $entity = [Microsoft.Azure.Cosmos.Table.DynamicTableEntity]::new($PartitionKey, $RowKey)

    foreach ($propertyName in $Properties.Keys) {
        if ($propertyName -in @('Year', 'WeekNumber') -and $Properties[$propertyName] -match '^\d+$') {
            $entity.Properties[$propertyName] = [Microsoft.Azure.Cosmos.Table.EntityProperty]::new([int]$Properties[$propertyName])
        } else {
            $entity.Properties[$propertyName] = [Microsoft.Azure.Cosmos.Table.EntityProperty]::new([string]$Properties[$propertyName])
        }
    }

    $operation = [Microsoft.Azure.Cosmos.Table.TableOperation]::InsertOrReplace($entity)
    $Table.Execute($operation) | Out-Null
}

function Test-TicketAlreadyProcessedThisWeek {
    <#
    .SYNOPSIS
        Checks whether a ticket already exists in Azure Table Storage for the current YearWeek partition.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TicketNumber
    )

    if (-not $Script:IsAzureAutomation) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($TicketNumber)) {
        return $false
    }

    try {
        $cloudTable = Initialize-StatisticsTable
        if (-not $cloudTable) {
            return $false
        }

        $currentDate = Get-Date
        $weekNumber = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
            $currentDate,
            [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
            [System.DayOfWeek]::Monday
        )
        $yearWeekString = "{0:D4}-W{1:D2}" -f $currentDate.Year, $weekNumber

        Write-ScriptLog "Dedup check running for each ticket: $TicketNumber (Partition: $yearWeekString)" -Level Info -Category "Processing"
        return (Test-CloudTableEntityExists -Table $cloudTable -PartitionKey $yearWeekString -RowKey $TicketNumber)
    } catch {
        Write-ScriptLog "Failed dedup lookup for ${TicketNumber}: $($_.Exception.Message)" -Level Warning -Category "Configuration"
        return $false
    }
}

function Save-CategoryStatisticsToTable {
    <#
    .SYNOPSIS
        Saves individual incident records to Azure Table Storage
    .DESCRIPTION
        Stores one row per incident with category assignment for easy querying and reporting.
        Table Schema:
        - PartitionKey: YearWeek (e.g., "2026-W06") for efficient weekly queries
        - RowKey: Incident ID (e.g., "INC15285226")
        - Category: Assigned category name
        - Date: Incident date (YYYY-MM-DD)
        - YearWeek: Year and week string (YYYY-Wnn)
        - Year: Year number
        - WeekNumber: ISO week number
        - ReportBlobName: Filename of the HTML report in results blob container
        - Timestamp: Auto-generated by Azure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$CategoryData,  # Kept for backward compatibility, but we use ProcessedTickets
        
        [DateTime]$ReportDate = (Get-Date),

        [string]$ReportBlobName = ""
    )
    
    if (-not $Script:IsAzureAutomation) {
        Write-ScriptLog "Skipping Azure Table storage in local environment" -Level Info
        return
    }
    
    # Use ProcessedTickets for individual incident records
    if ($Script:ProcessedTickets.Count -eq 0) {
        Write-ScriptLog "No processed tickets to save to table" -Level Warning
        return
    }
    
    try {
        $cloudTable = Initialize-StatisticsTable
        
        # Exit if table doesn't exist
        if (-not $cloudTable) {
            Write-ScriptLog "Skipping statistics save - table not available" -Level Warning
            return
        }
        
        # Calculate date components for partitioning
        $dateString = $ReportDate.ToString("yyyy-MM-dd")
        $year = $ReportDate.Year
        $weekNumber = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
            $ReportDate, 
            [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, 
            [System.DayOfWeek]::Monday
        )
        $yearWeekString = "{0:D4}-W{1:D2}" -f $year, $weekNumber
        
        Write-ScriptLog "Saving $($Script:ProcessedTickets.Count) incident records to Azure Table - Date: $dateString, Week: $yearWeekString" -Level Info
        
        $savedCount = 0
        $errorCount = 0
        
        # Fallback partition values (used when the ticket lacks a parseable ResolvedAt).
        $fallbackDateString = $dateString
        $fallbackYear = $year
        $fallbackWeekNumber = $weekNumber
        $fallbackYearWeek = $yearWeekString

        foreach ($ticket in $Script:ProcessedTickets) {
            try {
                # Per-ticket partitioning: parse $ticket.ResolvedAt so each row lands in the
                # ISO week it was actually resolved in, not the merged-report week.
                [DateTime]$resolvedDt = [DateTime]::MinValue
                if (-not [string]::IsNullOrWhiteSpace([string]$ticket.ResolvedAt) -and
                    [DateTime]::TryParse([string]$ticket.ResolvedAt, [ref]$resolvedDt)) {
                    $rowDateString = $resolvedDt.ToString("yyyy-MM-dd")
                    $rowYear       = $resolvedDt.Year
                    $rowWeekNumber = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
                        $resolvedDt,
                        [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
                        [System.DayOfWeek]::Monday
                    )
                    $rowYearWeek   = "{0:D4}-W{1:D2}" -f $rowYear, $rowWeekNumber
                } else {
                    $rowDateString = $fallbackDateString
                    $rowYear       = $fallbackYear
                    $rowWeekNumber = $fallbackWeekNumber
                    $rowYearWeek   = $fallbackYearWeek
                }

                # Create entity properties for individual incident.
                # AIAnalysis is sourced from $ticket.Reasoning (the AI's narrative);
                # cap to 4000 chars to stay well under Azure Table's 64 KiB property limit.
                $aiAnalysisValue = if ([string]::IsNullOrWhiteSpace([string]$ticket.Reasoning)) { '' }
                    elseif (([string]$ticket.Reasoning).Length -gt 4000) { ([string]$ticket.Reasoning).Substring(0, 4000) + '...' }
                    else { [string]$ticket.Reasoning }

                $entityProperties = @{
                    "Category"       = [string]$ticket.Category
                    "Date"           = [string]$rowDateString
                    "YearWeek"       = [string]$rowYearWeek
                    "Year"           = [int]$rowYear
                    "WeekNumber"     = [int]$rowWeekNumber
                    "ReportBlobName" = [string]$ReportBlobName
                    "AIAnalysis"     = $aiAnalysisValue
                    "Confidence"     = [string]$ticket.Confidence
                }
                
                # Save incident record
                # PartitionKey = YearWeek (derived per-ticket from ResolvedAt)
                # RowKey = Incident ID (unique)
                Set-CloudTableEntity -Table $cloudTable `
                    -PartitionKey $rowYearWeek `
                    -RowKey $ticket.Number `
                    -Properties $entityProperties
                
                $savedCount++
                Write-ScriptLog "Table row written successfully for each processed ticket: $($ticket.Number)" -Level Info -Category "Storage"
                
            } catch {
                $errorCount++
                Write-ScriptLog "Failed to save incident $($ticket.Number): $($_.Exception.Message)" -Level Warning
            }
        }
        
        if ($errorCount -eq 0) {
            Write-ScriptLog "Successfully saved $savedCount incident records to Azure Table" -Level Success
            Write-Host ("Statistics saved: {0} incidents to table {1}" -f $savedCount, $Script:BlobConfig.StatisticsTableName) -ForegroundColor Green
        } else {
            Write-ScriptLog "Saved $savedCount incidents with $errorCount errors" -Level Warning
            Write-Host ("Statistics: {0} saved, {1} errors" -f $savedCount, $errorCount) -ForegroundColor Yellow
        }
        
    } catch {
        Write-ScriptLog "Failed to save statistics to Azure Table: $($_.Exception.Message)" -Level Error
        Write-ScriptLog "Stack Trace: $($_.ScriptStackTrace)" -Level Error
        Write-Host ("Failed to save statistics: {0}" -f $_.Exception.Message) -ForegroundColor Red
        # Don't throw - statistics saving shouldn't break the main workflow
    }
}

function Get-StatisticsRestApiInfo {
    <#
    .SYNOPSIS
        Returns information about accessing the statistics table via REST API
    .DESCRIPTION
        Azure Table Storage has a built-in REST API. This function provides the URL and 
        sample queries for accessing the individual incident statistics data.
        
        New Schema (one row per incident):
        - PartitionKey: YearWeek (e.g., "2026-W06")
        - RowKey: IncidentID (e.g., "INC15285226")
        - Category, Date, YearWeek, Year, WeekNumber, ReportBlobName
    #>
    [CmdletBinding()]
    param()
    
    $storageAccount = $Script:BlobConfig.StorageAccountName
    $tableName = $Script:BlobConfig.StatisticsTableName
    
    $info = @{
        BaseUrl = "https://$storageAccount.table.core.windows.net/$tableName"
        SampleQueries = @{
            "AllIncidents" = "https://$storageAccount.table.core.windows.net/$tableName()"
            "ByWeek" = "https://$storageAccount.table.core.windows.net/$tableName()?`$filter=PartitionKey%20eq%20'2026-W06'"
            "ByCategory" = "https://$storageAccount.table.core.windows.net/$tableName()?`$filter=Category%20eq%20'Hardware%20Issues'"
            "ByDate" = "https://$storageAccount.table.core.windows.net/$tableName()?`$filter=Date%20eq%20'2026-02-10'"
            "SpecificIncident" = "https://$storageAccount.table.core.windows.net/$tableName(PartitionKey='2026-W06',RowKey='INC15285226')"
        }
        Authentication = "Use SAS token or Azure AD for authentication"
        Documentation = "https://docs.microsoft.com/en-us/rest/api/storageservices/querying-tables-and-entities"
    }
    
    return $info
}

#endregion

#region Report Generation Functions

function New-HtmlTicketReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$CategoryData,
        
        [array]$DetailedSummaries = @()
    )
    
    Write-ScriptLog "Generating HTML report for Outlook team with $($CategoryData.Count) categories" -Level Info
    
    $totalTickets = ($CategoryData | Measure-Object -Property Count -Sum).Sum
    $totalCategories = $CategoryData.Count
    
    $categoryLookup = @{}
    foreach ($category in $CategoryData) {
        $ticketArray = if ($category.Tickets -is [array]) { $category.Tickets } else { @($category.Tickets) }
        foreach ($ticket in $ticketArray) {
            $categoryLookup[$ticket] = $category.Name
        }
    }
    
    $categoryTableHtml = New-CategoryTableHtml -CategoryData $CategoryData
    $incidentDetailsHtml = New-DetailsTableHtml -DetailedSummaries $DetailedSummaries -CategoryLookup $categoryLookup -TicketType 'Incident' -ProcessedTicketsData $Script:ProcessedTickets
    $serviceRequestDetailsHtml = New-DetailsTableHtml -DetailedSummaries $DetailedSummaries -CategoryLookup $categoryLookup -TicketType 'ServiceRequest' -ProcessedTicketsData $Script:ProcessedTickets

    $promptVersionRows = @()
    if ($Script:PromptVersions -and $Script:PromptVersions.Keys.Count -gt 0) {
        foreach ($promptKey in ($Script:PromptVersions.Keys | Sort-Object)) {
            $promptVersionRows += "<tr><td style='font-weight:600;color:#0071c5;'>$promptKey</td><td>$($Script:PromptVersions[$promptKey])</td></tr>"
        }
    } else {
        $promptVersionRows += "<tr><td colspan='2'>Not captured</td></tr>"
    }
    $analysisMetadataHtml = @"
        <div class='section'>
            <h2>Analysis metadata</h2>
            <table>
                <tr><th>Prompt Template</th><th>Version (LastModified UTC)</th></tr>
                $($promptVersionRows -join "`n")
            </table>
        </div>
"@
    
    $htmlTemplate = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Outlook Service Health — Weekly Report</title>
    <style>
        body { margin:0; padding:20px; background:#f5f7fa; font-family:'Segoe UI',sans-serif; }
        .container { max-width:1200px; margin:0 auto; background:white; border-radius:8px; box-shadow:0 4px 12px rgba(0,0,0,0.1); overflow:hidden; }
        .header { background:#0071c5; color:white; padding:20px; text-align:center; }
        .header h1 { margin:0 0 5px 0; font-size:24px; font-weight:400; }
        .header .subtitle { font-size:14px; opacity:0.9; }
        .stats { background:#f8f9fa; padding:20px; display:flex; justify-content:space-around; border-bottom:1px solid #dee2e6; }
        .stat { text-align:center; }
        .stat-value { font-size:28px; font-weight:bold; color:#0071c5; margin-bottom:5px; }
        .stat-label { font-size:12px; color:#666; text-transform:uppercase; letter-spacing:1px; }
        .section { margin:25px; }
        .section h2 { color:#0071c5; font-size:20px; margin-bottom:15px; padding-bottom:8px; border-bottom:2px solid #0071c5; }
        table { width:100%; border-collapse:collapse; background:white; border-radius:6px; overflow:hidden; box-shadow:0 2px 8px rgba(0,0,0,0.1); }
        th { background:#0071c5; color:white; padding:12px; text-align:left; font-weight:600; font-size:12px; letter-spacing:1px; }
        td { padding:12px; border-bottom:1px solid #e0e0e0; vertical-align:top; }
        .ticket-link { background:#ecf0f1; color:#0071c5; padding:4px 8px; margin:2px; border-radius:3px; text-decoration:none; font-size:11px; font-weight:bold; display:inline-block; }
        .servicenow-link { background:#f8f9fa; color:#0071c5; padding:6px 10px; border-radius:3px; text-decoration:none; font-size:11px; font-weight:600; border:1px solid #dee2e6; white-space:nowrap; display:inline-block; }
        .footer { background:#0071c5; color:white; text-align:center; padding:15px; font-size:12px; }
        .total-row { background:#0071c5; color:white; font-weight:bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Outlook Service Health — Weekly Report</h1>
            <div class="subtitle">Analysis Period: $Script:reportperiod</div>
        </div>
        <div class="stats">
            <div class="stat">
                <div class="stat-value">$totalTickets</div>
                <div class="stat-label">Resolved Tickets Processed</div>
            </div>
            <div class="stat">
                <div class="stat-value">$totalCategories</div>
                <div class="stat-label">Root Cause Categories Applied</div>
            </div>
        </div>
        <div class="section">
            <h2 id="category-summary">Root Cause Category Analysis Summary</h2>
            $categoryTableHtml
        </div>
        $incidentDetailsHtml
        $serviceRequestDetailsHtml
        $analysisMetadataHtml
        <div class="footer">
            Generated by Outlook AI Categorization System - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        </div>
    </div>
</body>
</html>
"@
    
    Write-ScriptLog ("HTML report generated successfully for Outlook team ({0} KB)" -f (($htmlTemplate.Length / 1024).ToString('N1'))) -Level Success
    return $htmlTemplate
}

function New-CategoryTableHtml {
    [CmdletBinding()]
    param([array]$CategoryData)
    
    $tableRows = foreach ($category in $CategoryData) {
        $ticketArray = if ($category.Tickets -is [array]) { $category.Tickets } else { @($category.Tickets) }
        $ticketLinks = ($ticketArray | ForEach-Object {
            # Determine appropriate anchor prefix based on ticket type
            $anchorPrefix = if ($_.StartsWith("INC")) { "incident" } else { "request" }
            "<a href='#$anchorPrefix-$_' class='ticket-link'>$_</a>"
        }) -join " "
        
        "<tr><td style='font-weight:600;color:#0071c5;'>$($category.Name)</td><td style='text-align:center;color:#0071c5;font-weight:bold;'>$($category.Count)</td><td>$ticketLinks</td></tr>"
    }
    
    $totalTickets = ($CategoryData | Measure-Object -Property Count -Sum).Sum
    
    return @"
<table>
    <thead>
        <tr>
            <th style="width:35%;">ROOT CAUSE CATEGORY</th>
            <th style="width:10%;">COUNT</th>
            <th style="width:55%;">TICKET NUMBERS</th>
        </tr>
    </thead>
    <tbody>
        $($tableRows -join "`n        ")
        <tr class="total-row">
            <td>TOTAL PROCESSED</td>
            <td style="text-align:center;">$totalTickets</td>
            <td style="font-style:italic;">All resolved Outlook tickets categorized</td>
        </tr>
    </tbody>
</table>
"@
}

function New-DetailsTableHtml {
    [CmdletBinding()]
    param(
        [array]$DetailedSummaries,
        [hashtable]$CategoryLookup,
        [ValidateSet('Incident', 'ServiceRequest')]
        [string]$TicketType = 'Incident',
        [array]$ProcessedTicketsData = @()
    )
    
    if ($DetailedSummaries.Count -eq 0) { return "" }
    
    # Filter summaries by ticket type
    $filteredSummaries = $DetailedSummaries | Where-Object { 
        if ($TicketType -eq 'Incident') {
            $_.IncidentNumber.StartsWith("INC")
        } else {
            $_.IncidentNumber.StartsWith("SCTASK")
        }
    }
    
    if ($filteredSummaries.Count -eq 0) { return "" }
    
    $detailRows = foreach ($summary in $filteredSummaries) {
        $category = $CategoryLookup[$summary.IncidentNumber]
        if ([string]::IsNullOrWhiteSpace([string]$category)) {
            $category = "Unknown"
        }
        
        # For Excluded tickets, append the exclusion reason below the category in the detail row
        if ($category -eq 'Excluded' -and $ProcessedTicketsData.Count -gt 0) {
            $ticketData = $ProcessedTicketsData | Where-Object { $_.Number -eq $summary.IncidentNumber } | Select-Object -First 1
            if ($ticketData -and $ticketData.ExclusionReason) {
                $category = "Excluded<br><span style='font-weight:normal;font-size:11px;color:#6c757d;'>$($ticketData.ExclusionReason)</span>"
            }
        }
        
        $formattedSummary = $summary.SummarisedNotes -replace "`r`n|`n|`r", "<br>"
        $formattedSummary = $formattedSummary -replace "Key Actions:", "<strong style='color:#0071c5;'>Key Actions:</strong>"
        $formattedSummary = $formattedSummary -replace "Critical Details:", "<strong style='color:#0071c5;'>Critical Details:</strong>"
        $formattedSummary = $formattedSummary -replace "Work Notes:", "<strong style='color:#0071c5;'>Work Notes:</strong>"
        $formattedSummary = $formattedSummary -replace "â€¢", "&bull;"
        
        if ($formattedSummary -notmatch "^<strong.*?>Problem:</strong>") {
            $formattedSummary = "<strong style='color:#0071c5;'>Problem:</strong> " + $formattedSummary
        }
        
        # Add AI reasoning and confidence if available
        if ($ProcessedTicketsData.Count -gt 0) {
            $ticketAnalysis = $ProcessedTicketsData | Where-Object { $_.Number -eq $summary.IncidentNumber } | Select-Object -First 1
            if ($ticketAnalysis -and $ticketAnalysis.Reasoning) {
                $confidenceLevel = $ticketAnalysis.Confidence
                if ([string]::IsNullOrWhiteSpace([string]$confidenceLevel)) {
                    $confidenceLevel = "Unknown"
                }
                $reasoning = $ticketAnalysis.Reasoning
                
                # Set colors based on confidence level
                $confidenceColor = switch ($confidenceLevel) {
                    "High"    { "#28a745" }  # Green
                    "Medium"  { "#ffc107" }  # Orange/Amber
                    "Low"     { "#dc3545" }  # Red
                    default   { "#6c757d" }  # Gray for Unknown
                }
                
                $aiReasoningSection = @"
<hr style="margin:10px 0; border:1px solid #dee2e6;">
<div style="background:#f8f9fa; padding:8px; border-radius:4px; font-size:12px; border-left:4px solid $confidenceColor;">
<strong style='color:$confidenceColor;'>AI Analysis ($confidenceLevel Confidence):</strong><br>
$reasoning
</div>
"@
                $formattedSummary += $aiReasoningSection
            }
        }
        
        # Generate appropriate ServiceNow link based on ticket type
        $serviceNowUrl = if ($summary.IncidentNumber.StartsWith("INC")) {
            "https://intel.service-now.com/nav_to.do?uri=incident.do?sysparm_query=number=$($summary.IncidentNumber)"
        } elseif ($summary.IncidentNumber.StartsWith("SCTASK")) {
            "https://intel.service-now.com/sc_task.do?sys_id=$($summary.IncidentNumber)"
        } else {
            "#"
        }
        
        # Generate appropriate anchor ID
        $anchorPrefix = if ($TicketType -eq 'Incident') { "incident" } else { "request" }
        
        @"
        <tr id="$anchorPrefix-$($summary.IncidentNumber)">
            <td style="text-align:center;"><a href="#category-summary" class='ticket-link'>$($summary.IncidentNumber)</a></td>
            <td style="font-weight:600;color:#0071c5;font-size:12px;">$category</td>
            <td style="line-height:1.4;font-size:13px;">$formattedSummary</td>
            <td style="text-align:center;"><a href="$serviceNowUrl" target="_blank" class="servicenow-link">View in ServiceNow</a></td>
        </tr>
"@
    }
    
    # Generate section title and headers based on ticket type
    $sectionTitle = if ($TicketType -eq 'Incident') { 
        "Detailed Outlook Incident Analysis" 
    } else { 
        "Detailed Outlook Service Request Analysis" 
    }
    
    $headerLabel = if ($TicketType -eq 'Incident') { 
        "INCIDENT" 
    } else { 
        "SERVICE REQUEST" 
    }
    
    return @"
        <div class="section">
            <h2>$sectionTitle</h2>
            <table>
                <thead>
                    <tr>
                        <th style="width:12%;">$headerLabel</th>
                        <th style="width:18%;">ROOT CAUSE CATEGORY</th>
                        <th style="width:55%;">DETAILED SUMMARY</th>
                        <th style="width:15%;">SERVICENOW LINK</th>
                    </tr>
                </thead>
                <tbody>
                    $($detailRows -join "`n                    ")
                </tbody>
            </table>
        </div>
"@
}

function Send-ReportWebhook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WebhookUrl,
        
        [Parameter(Mandatory)]
        [string]$HtmlContent,
        
        [string]$Subject = $Script:Config.Webhook.DefaultSubject,
        
        [int]$TimeoutSeconds = $Script:Config.Webhook.TimeoutSeconds,
        
        [int]$RetryAttempts = $Script:Config.Webhook.RetryAttempts
    )
    
    Write-ScriptLog ("Sending HTML report to webhook for email delivery ({0} KB)" -f (($HtmlContent.Length / 1024).ToString('N1'))) -Level Info
    
    if (-not ($WebhookUrl -match "^https://")) {
        throw "Invalid webhook URL format - must start with https://"
    }
    
    $payload = @{
        subject = $Subject
        htmlContent = $HtmlContent
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        contentSize = $HtmlContent.Length
    } | ConvertTo-Json -Depth 5 -Compress
    
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
        'User-Agent' = 'PowerShell-MDM-Reporter/1.2'
    }
    
    $attempt = 0
    
    do {
        $attempt++
        try {
            Write-ScriptLog "Sending webhook for email delivery (Attempt $attempt/$RetryAttempts)" -Level Info
            
            Invoke-RestMethod -Uri $WebhookUrl -Method POST -Body $payload -Headers $headers -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            
            Write-ScriptLog "EUC report sent successfully via webhook" -Level Success
            return @{
                Status = "Success"
                TimeSent = Get-Date
                Subject = $Subject
                ContentSize = $HtmlContent.Length
                AttemptsUsed = $attempt
            }
            
        } catch {
            Write-ScriptLog "Webhook delivery attempt $attempt failed: $($_.Exception.Message)" -Level Warning
            
            if ($attempt -lt $RetryAttempts) {
                $waitTime = [Math]::Pow(2, $attempt) * 2
                Write-ScriptLog "Waiting $waitTime seconds before retry" -Level Info
                Start-Sleep -Seconds $waitTime
            }
        }
    } while ($attempt -lt $RetryAttempts)
    
    Write-ScriptLog "All webhook delivery attempts failed" -Level Error
    throw "Failed to send webhook after $RetryAttempts attempts"
}

#endregion

#region Configuration
# Load prompt templates with consolidated logging
$Script:PromptTemplates = @{}
$Script:PromptVersions = @{}
$promptProfileSuffix = ""
if ($Script:IsAzureAutomation) {
    $promptProfileSuffix = Get-AutomationVariable -Name "PromptProfileSuffix" -ErrorAction SilentlyContinue
} elseif ($Script:LocalConfig -and $Script:LocalConfig.PromptProfileSuffix) {
    $promptProfileSuffix = $Script:LocalConfig.PromptProfileSuffix
}

$promptProfileSuffix = [string]$promptProfileSuffix
if ($promptProfileSuffix) {
    Write-ScriptLog "Prompt profile suffix enabled: '$promptProfileSuffix'" -Level Info -Category "Configuration"
}

$requiredFiles = @("WorkNotesCleanup", "WorkNotesSummary", "TicketCategorisation", "EnvironmentContext")
$loadedCount = 0
$failedFiles = @()

foreach ($file in 
$requiredFiles) {
    try {
        $resolvedPromptFile = "$file$promptProfileSuffix"
        $loadedPromptBlobName = $resolvedPromptFile
        try {
            $Script:PromptTemplates[$file] = Get-BlobMarkdownContent -FileName $resolvedPromptFile
        } catch {
            if ($promptProfileSuffix) {
                Write-ScriptLog "Falling back to default prompt template '$file'" -Level Warning -Category "Configuration"
                $Script:PromptTemplates[$file] = Get-BlobMarkdownContent -FileName $file
                $loadedPromptBlobName = $file
            } else {
                throw
            }
        }

        # Capture prompt version metadata (LastModified UTC) for reproducibility.
        if ($Script:IsAzureAutomation) {
            $storageContext = Get-StorageContext
            $blobName = if ($loadedPromptBlobName.EndsWith('.md')) { $loadedPromptBlobName } else { "$loadedPromptBlobName.md" }
            $promptBlob = Get-AzStorageBlob -Container $Script:BlobConfig.PromptContainerName -Blob $blobName -Context $storageContext -ErrorAction Stop
            $Script:PromptVersions[$file] = $promptBlob.LastModified.UtcDateTime.ToString('o')
        } else {
            $Script:PromptVersions[$file] = (Get-Date).ToUniversalTime().ToString('o')
        }

        $loadedCount++
    } catch {
        $failedFiles += $file
        Write-Host ("Failed to load: {0} - {1}" -f $file, $_.Exception.Message) -ForegroundColor Red
    }
}

if ($Script:PromptTemplates.EnvironmentContext -and -not $Script:PromptTemplates.IntuneEnvironmentContext) {
    # Keep compatibility with existing prompt composition code.
    $Script:PromptTemplates.IntuneEnvironmentContext = $Script:PromptTemplates.EnvironmentContext
}

if ($loadedCount -eq $requiredFiles.Count) {
    Write-Host ("Successfully loaded all {0} prompt templates" -f $loadedCount) -ForegroundColor Green
} else {
    Write-Host ("Loaded {0}/{1} prompt templates. Failed: {2}" -f $loadedCount, $requiredFiles.Count, ($failedFiles -join ', ')) -ForegroundColor Yellow
}

$Script:Config = @{
    AI = @{
        Model = $Script:Constants.AzureOpenAIDeployment
        Temperature = @{
            Cleanup = 0.3
            Summary = 0.2
            Category = 0
        }
        MaxTokens = 8192
        TopP = 1.0
        FrequencyPenalty = 0
        PresencePenalty = 0
    }
    
    Webhook = @{
        TimeoutSeconds = 300
        RetryAttempts = 3
        DefaultSubject = "EUC Resolved Ticket AI Root Cause Categorization Report"
    }
    
    Logging = @{
        EnableDebug = $true
        TimestampFormat = "yyyy-MM-dd HH:mm:ss"
    }
}

class TicketAnalysis {
    [string]$Number
    [string]$TicketType
    [string]$Category
    [string]$ExclusionReason
    [string]$Confidence
    [string]$Reasoning
    [string]$Evidence
    [string]$Resolution
    [string]$Type
    [string]$KnowledgeBase
    [string]$OriginalDescription
    [string]$ResolvedAt          # Raw ServiceNow resolved_at string (used for per-ticket week partitioning)
    [datetime]$Processed = (Get-Date)
    
    TicketAnalysis([string]$ticketNumber) {
        $this.Number = $ticketNumber
        # Auto-detect ticket type based on number prefix
        if ($ticketNumber.StartsWith("INC")) {
            $this.TicketType = "Incident"
        } elseif ($ticketNumber.StartsWith("SCTASK")) {
            $this.TicketType = "ServiceRequest"
        } else {
            $this.TicketType = "Unknown"
        }
    }
}

$Script:ProcessedTickets = [System.Collections.Generic.List[TicketAnalysis]]::new()

#endregion

#region Script Entry Point

if (-not $Script:Constants) {
    Write-ScriptLog "ERROR: Constants object not found. Please ensure configuration is loaded." -Level Error
    throw "Missing required configuration object: Constants"
}

if (-not $Script:PromptTemplates) {
    Write-ScriptLog "ERROR: PromptTemplates object not found. Please ensure prompt templates are loaded." -Level Error
    throw "Missing required configuration object: PromptTemplates"
}

Write-ScriptLog "ServiceNow EUC Ticket Categorization System v1.2" -Level Info
$aiModel = if ($Script:Constants.UseClaudeModel) { "Claude Sonnet 4.5 ({0})" -f $Script:Constants.ClaudeDeployment } else { "Azure OpenAI ({0})" -f $Script:Constants.AzureOpenAIDeployment }
Write-ScriptLog "AI Model: $aiModel" -Level Info
Write-ScriptLog "All functions loaded successfully - EUC system ready for execution" -Level Success

try {
    # Initialize enhanced logging
    Initialize-BlobLogging

    # Fail fast if Azure OpenAI deployment/version are misconfigured.
    Test-AzureOpenAIDeployment
    
    Write-ScriptLog "=== STARTING EUC Ticket PROCESSING WORKFLOW ===" -Level Info
    
    # Data Retrieval Phase - Check if using stored data or API
    if ($Script:Constants.UseStoredIncidents) {
        Write-ScriptLog "=== LOADING STORED INCIDENT DATA ===" -Level Info
        
        # Show available files for reference
        Get-AvailableIncidentFiles | Out-Null
        
        # Load stored incidents
        $incidents = Get-StoredIncidents -FileName $Script:Constants.StoredDataFileName
        
        $lookbackHours = if ($null -ne $Script:Constants.DailyLookbackHours) { [int]$Script:Constants.DailyLookbackHours } else { 26 }

        # Set report period based on stored data or current date
        $yesterday = (Get-Date).AddHours(-1 * $lookbackHours)
        $today = Get-Date
        $Script:reportperiod = "Stored Data Analysis - $($yesterday.ToString('yyyy-MM-dd HH:mm')) to $($today.ToString('yyyy-MM-dd HH:mm'))"
        
    } else {
        # Authentication Phase
        Write-ScriptLog "=== AUTHENTICATION PHASE ===" -Level Info
        $serviceNowToken = Get-AccessToken -TokenUrl $Script:Constants.TokenUrl -ClientId $Script:Constants.ServiceNowIncidentsClientID -ClientSecret $Script:Constants.ServiceNowIncidentsClientSecret -Scope $Script:Constants.ServiceNowIncidentsScope
        
        # ServiceNow Incidents API Call
        Write-ScriptLog "=== SERVICENOW INCIDENT DATA RETRIEVAL ===" -Level Info
        $lookbackHours = if ($null -ne $Script:Constants.DailyLookbackHours) { [int]$Script:Constants.DailyLookbackHours } else { 26 }
        $yesterday = (Get-Date).AddHours(-1 * $lookbackHours)
        $today = Get-Date
        $Script:reportperiod = "$($yesterday.ToString('yyyy-MM-dd HH:mm'))" + " to " + "$($today.ToString('yyyy-MM-dd HH:mm'))"

        $maxIncidentsPerRun = 500
        if ($Script:Constants.PSObject.Properties.Name -contains 'MaxIncidentsPerRun') {
            try {
                $configuredLimit = [int]$Script:Constants.MaxIncidentsPerRun
                if ($configuredLimit -gt 0) { $maxIncidentsPerRun = $configuredLimit }
            } catch {
                Write-ScriptLog "Invalid MaxIncidentsPerRun configured; using default 500" -Level Warning -Category "Configuration"
            }
        }

        $requiredFields = 'number,description,short_description,work_notes,close_notes,calendar_duration,close_code,opened_at,resolved_at'
        $incidentsUrl = [string]$Script:Constants.ServicenowIncidentsURL
        $incidentsUrl = Add-QueryParamIfMissing -Url $incidentsUrl -ParamName 'sysparm_limit' -ParamValue ([string]$maxIncidentsPerRun)
        $incidentsUrl = Add-QueryParamIfMissing -Url $incidentsUrl -ParamName 'sysparm_fields' -ParamValue $requiredFields
        $incidentsUrl = Add-QueryParamIfMissing -Url $incidentsUrl -ParamName 'sysparm_exclude_reference_link' -ParamValue 'true'

        Write-ScriptLog "ServiceNow request optimization applied (limit=$maxIncidentsPerRun, reduced field set enabled)" -Level Info -Category "Configuration"

        $incidentsResponse = Invoke-AuthenticatedApiCall -Url $incidentsUrl -AccessToken $serviceNowToken -Method GET
        $incidents = $incidentsResponse.result
        if (-not $incidents -or $incidents.Count -eq 0) {
            Write-Output "No incidents returned from ServiceNow API. Nothing to process for this run."
            Write-Output "Query URL: $ServiceNowIncidentsURL"
            Write-Output "Lookback hours: $DailyLookbackHours"
            return
        }
        $incidents = Filter-IncidentsByResolvedWindow -Incidents $incidents -LookbackHours $lookbackHours

        if ($incidentsResponse.result.Count -ge $maxIncidentsPerRun) {
            Write-ScriptLog "Incident API response reached configured limit ($maxIncidentsPerRun). Narrow ServiceNow query or increase MaxIncidentsPerRun only if memory permits." -Level Warning -Category "Configuration"
        }
        
        Write-ScriptLog "Retrieved $($incidents.Count) resolved incidents for processing" -Level Success
        
        # Save raw incident data if enabled (to blob in Azure, local folder in development)
        if ($Script:Constants.SaveRawDataLocally -and -not $Script:IsAzureAutomation) {
            Save-IncidentsData -Incidents $incidents | Out-Null
        } elseif ($Script:IsAzureAutomation) {
            # Always save to blob in Azure Automation for audit trail
            Save-IncidentsData -Incidents $incidents | Out-Null
        }
    }
    
    # COMMENTED OUT - Service Requests Processing
    # Write-ScriptLog "=== SERVICENOW SERVICE REQUESTS DATA RETRIEVAL ===" -Level Info
    # $requestsResponse = Invoke-AuthenticatedApiCall -Url $Script:Constants.ServicenowRequestsURL -AccessToken $serviceNowToken -Method GET
    # $requests = $requestsResponse.result | Where-Object {$_.state -eq "Closed Complete"}
    # Write-ScriptLog "Retrieved $($requests.Count) resolved requests for processing" -Level Success
    $requests = @()  # Empty array since we're not processing requests

    # Check if we have incidents to process
    if ($incidents.count -eq 0) {
        Write-ScriptLog "No incidents found to process - exiting without generating report" -Level Warning
        Complete-BlobLogging -FinalMessage "No incidents found to process"
        return
    }
    
    # Process incidents and requests
    Write-ScriptLog "=== AI PROCESSING PHASE ===" -Level Info
    $allsummarisednotes = [System.Collections.Generic.List[PSCustomObject]]::new()
    $processedIncidentCount = 0
    $processedRequestCount = 0
    $totalIncidents = $incidents.Count
    $totalRequests = $requests.Count
    $totalTickets = $totalIncidents + $totalRequests
    
# Process incidents first
Write-ScriptLog "Processing $totalIncidents incidents..." -Level Info
foreach ($incident in $incidents) {
    if (Test-TicketAlreadyProcessedThisWeek -TicketNumber ([string]$incident.number)) {
        Write-ScriptLog "Skipping already-processed incident $($incident.number) (exists in current week table partition)" -Level Info -Category "Processing"
        continue
    }

    $maxRetries = 3
    $retryCount = 0
    $success = $false
    
    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            $processedTicket = Invoke-TicketProcessing -Incident $incident
            $allsummarisednotes.Add($processedTicket)
            $processedIncidentCount++
            $success = $true
            
            # Progress reporting for incidents
            if ($totalIncidents -gt 0) {
                $percentComplete = [math]::Round(($processedIncidentCount / $totalIncidents) * 100)
                if ($percentComplete -in @(25, 50, 75) -or $processedIncidentCount -eq $totalIncidents) {
                    Write-ScriptLog ("Incident processing progress: {0}/{1} incidents ({2}%)" -f $processedIncidentCount, $totalIncidents, $percentComplete) -Level Info
                }
            }
            
        } catch {
            $retryCount++
            $errorMessage = $_.Exception.Message
            
            if ($errorMessage -match "429" -or $errorMessage -match "Too Many Requests") {
                $waitTime = [math]::Min(30, [math]::Pow(2, $retryCount) * 5) # Exponential backoff, max 30 seconds
                Write-ScriptLog "Rate limit hit for incident $($incident.number). Waiting $waitTime seconds before retry $retryCount/$maxRetries" -Level Warning
                Start-Sleep -Seconds $waitTime
            } elseif ($retryCount -ge $maxRetries) {
                Write-ScriptLog "Failed to process incident $($incident.number) after $maxRetries attempts: $errorMessage" -Level Warning
                break
            } else {
                Write-ScriptLog "Retry $retryCount/$maxRetries for incident $($incident.number): $errorMessage" -Level Warning
                Start-Sleep -Seconds 2
            }
        }
    }
    
    # Rate limiting delay - increase this if you continue to hit limits
    Start-Sleep -Seconds 3
}

Write-ScriptLog "Completed incident processing: $processedIncidentCount/$totalIncidents successful" -Level Success

# COMMENTED OUT - Service Request Processing
# Write-ScriptLog "Processing $totalRequests service requests..." -Level Info
# foreach ($request in $requests) {
#     $maxRetries = 3
#     $retryCount = 0
#     $success = $false
#     
#     while (-not $success -and $retryCount -lt $maxRetries) {
#         try {
#             $processedTicket = Invoke-TicketProcessing -Incident $request
#             $allsummarisednotes.Add($processedTicket)
#             $processedRequestCount++
#             $success = $true
#             
#             # Progress reporting for service requests
#             if ($totalRequests -gt 0) {
#                 $percentComplete = [math]::Round(($processedRequestCount / $totalRequests) * 100)
#                 if ($percentComplete -in @(25, 50, 75) -or $processedRequestCount -eq $totalRequests) {
#                     Write-ScriptLog "Service request processing progress: $processedRequestCount/$totalRequests requests ($percentComplete%)" -Level Info
#                 }
#             }
#             
#         } catch {
#             $retryCount++
#             $errorMessage = $_.Exception.Message
#             
#             if ($errorMessage -match "429" -or $errorMessage -match "Too Many Requests") {
#                 $waitTime = [math]::Min(30, [math]::Pow(2, $retryCount) * 5) # Exponential backoff, max 30 seconds
#                 Write-ScriptLog "Rate limit hit for service request $($request.number). Waiting $waitTime seconds before retry $retryCount/$maxRetries" -Level Warning
#                 Start-Sleep -Seconds $waitTime
#             } elseif ($retryCount -ge $maxRetries) {
#                 Write-ScriptLog "Failed to process service request $($request.number) after $maxRetries attempts: $errorMessage" -Level Warning
#                 break
#             } else {
#                 Write-ScriptLog "Retry $retryCount/$maxRetries for service request $($request.number): $errorMessage" -Level Warning
#                 Start-Sleep -Seconds 2
#             }
#         }
#     }
#     
#     # Rate limiting delay for service requests
#     Start-Sleep -Seconds 3
# }    
# Write-ScriptLog "Completed service request processing: $processedRequestCount/$totalRequests successful" -Level Success
Write-ScriptLog "Service request processing disabled - focusing on incidents only" -Level Info
    Write-ScriptLog "Total AI processing completed: $processedIncidentCount/$totalTickets incidents successful" -Level Success
    
    # Check if any tickets were actually processed successfully
    if ($Script:ProcessedTickets.Count -eq 0) {
        Write-ScriptLog "ERROR: No incidents were successfully processed - check AI authentication and API endpoints" -Level Error
        Complete-BlobLogging -FinalMessage "Processing failed - no incidents successfully processed"
        return
    }
    
    $dataSource = if ($Script:Constants.UseStoredIncidents -and -not $Script:IsAzureAutomation) { "Stored Data" } else { "Live API" }

    # Save per-run artifact for weekly merge
    $saveRunArtifacts = if ($null -ne $Script:Constants.SaveRunArtifacts) { [bool]$Script:Constants.SaveRunArtifacts } else { $true }
    if ($saveRunArtifacts -eq $true) {
        Save-RunProcessingArtifact -DetailedSummaries $allsummarisednotes -ReportPeriod $Script:reportperiod -DataSource $dataSource | Out-Null
    }

    $weeklyReportOnlyMode = if ($null -ne $Script:Constants.WeeklyReportOnlyMode) { [bool]$Script:Constants.WeeklyReportOnlyMode } else { $false }
    $weeklyReportDayOfWeek = if ([string]::IsNullOrWhiteSpace([string]$Script:Constants.WeeklyReportDayOfWeek)) { "Sunday" } else { [string]$Script:Constants.WeeklyReportDayOfWeek }
    $validDays = @('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')
    if ($weeklyReportDayOfWeek -notin $validDays) {
        Write-ScriptLog ("Invalid WeeklyReportDayOfWeek '{0}' configured; defaulting to Sunday" -f $weeklyReportDayOfWeek) -Level Warning -Category "Configuration"
        $weeklyReportDayOfWeek = "Sunday"
    }
    $isWeeklyReportDay = (Get-Date).DayOfWeek.ToString() -eq $weeklyReportDayOfWeek

    # Weekly merge mode runs on configured weekly report day.
    $mergedData = $null
    $generateWeeklyMergedSetting = if ($null -ne $Script:Constants.GenerateWeeklyMergedReportOnWeekend) { [bool]$Script:Constants.GenerateWeeklyMergedReportOnWeekend } else { $false }
    $generateWeeklyMerged = (($generateWeeklyMergedSetting -eq $true) -or ($weeklyReportOnlyMode -eq $true)) -and $isWeeklyReportDay
    if ($generateWeeklyMerged) {
        $lookbackDays = if ($null -ne $Script:Constants.WeeklyMergeLookbackDays) { [int]$Script:Constants.WeeklyMergeLookbackDays } else { 7 }
        $mergedData = Get-MergedWeeklyRunData -LookbackDays $lookbackDays
        if ($mergedData.ProcessedTickets.Count -gt 0) {
            $Script:ProcessedTickets = $mergedData.ProcessedTickets
            $allsummarisednotes = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($summary in $mergedData.DetailedSummaries) {
                $allsummarisednotes.Add([PSCustomObject]@{
                    IncidentNumber = $summary.IncidentNumber
                    SummarisedNotes = $summary.SummarisedNotes
                })
            }
            $dataSource = "Merged Weekly ({0} incidents)" -f $Script:ProcessedTickets.Count
            Write-ScriptLog ("Weekly merge completed - {0} unique incidents from last {1} days" -f $Script:ProcessedTickets.Count, $lookbackDays) -Level Success
        } else {
            Write-ScriptLog "Weekly merge mode enabled but no prior run artifacts found - using current run data only" -Level Warning
        }
    }

    if ($weeklyReportOnlyMode -eq $true -and -not $isWeeklyReportDay) {
        Save-CategoryStatisticsToTable -CategoryData (Get-CategoryStatistics) -ReportDate (Get-Date) -ReportBlobName ""
        Write-ScriptLog ("WeeklyReportOnlyMode is enabled. Skipping report generation today ({0}); artifacts saved for weekly report on {1}." -f (Get-Date).DayOfWeek, $weeklyReportDayOfWeek) -Level Info -Category "Configuration"
        Complete-BlobLogging -FinalMessage ("Execution completed - artifacts saved; report generation day is {0}" -f $weeklyReportDayOfWeek)
        return
    }

    # Generate and send report
    Write-ScriptLog "=== REPORT GENERATION ===" -Level Info
    $CategoryData = Get-CategoryStatistics
    $totalTickets = if ($CategoryData.Count -gt 0) { 
        ($CategoryData | Measure-Object -Property Count -Sum).Sum 
    } else { 
        0 
    }
    
    $htmlcontent = New-HtmlTicketReport -CategoryData $CategoryData -DetailedSummaries $allsummarisednotes
    $totalProcessedTickets = $Script:ProcessedTickets.Count

    # Use the merged data's YearWeek (from artifacts) to avoid week boundary issues
    # e.g., running on Monday (W11) with merged W10 artifacts should still use W10
    if ($mergedData.YearWeek) {
        $reportYearWeek = $mergedData.YearWeek
    } else {
        # Fallback: calculate from current date
        $reportYear = (Get-Date).Year
        $reportWeekNumber = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
            (Get-Date),
            [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
            [System.DayOfWeek]::Monday
        )
        $reportYearWeek = "{0:D4}-W{1:D2}" -f $reportYear, $reportWeekNumber
    }
    $reportBlobName = "Outlook_Weekly_Report_$reportYearWeek.html"
    $dynamicSubject = "EUC AI Weekly Report $reportYearWeek - $totalProcessedTickets Incidents, $($CategoryData.Count) Categories"
    $Script:reportperiod = "Weekly cumulative report $reportYearWeek (updated $(Get-Date -Format 'dd MMM yyyy'))"
    
    # Save statistics to Azure Table Storage for historical tracking and REST API access
    Write-ScriptLog "=== SAVING STATISTICS TO AZURE TABLE ===" -Level Info
    # Parse the reportYearWeek to get a date that falls within the correct week for PartitionKey
    # This ensures W10 data gets PartitionKey "2026-W10" even if running on W11 Monday
    $reportDateForTable = Get-Date
    if ($reportYearWeek -match '^(\d{4})-W(\d{2})$') {
        $ywYear = [int]$Matches[1]
        $ywWeek = [int]$Matches[2]
        $currentWeekNum = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
            (Get-Date),
            [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
            [System.DayOfWeek]::Monday
        )
        # If artifact week differs from current week, use Thursday of that week as representative date
        if ($ywWeek -ne $currentWeekNum -or $ywYear -ne (Get-Date).Year) {
            # ISO week: Jan 4 is always in week 1. Calculate Thursday of target week.
            $jan4 = [DateTime]::new($ywYear, 1, 4)
            $jan4Monday = $jan4.AddDays(-([int]$jan4.DayOfWeek + 6) % 7)
            $targetThursday = $jan4Monday.AddDays(($ywWeek - 1) * 7 + 3)
            $reportDateForTable = $targetThursday
            Write-ScriptLog "Using date $($targetThursday.ToString('yyyy-MM-dd')) for PartitionKey (artifact week: $reportYearWeek, current week: W$currentWeekNum)" -Level Info
        }
    }
    Save-CategoryStatisticsToTable -CategoryData $CategoryData -ReportDate $reportDateForTable -ReportBlobName $reportBlobName
    
    # Always save report to blob/local storage (needed for static web app viewer)
    if ($Script:IsAzureAutomation) {
        try {
            if ([string]::IsNullOrWhiteSpace($Script:BlobConfig.ResultsContainerName)) {
                throw "ResultsContainerName is empty after configuration resolution"
            }

            $storageContext = Get-StorageContext
            Write-ScriptLog "Uploading report to Azure Blob - Account: $($Script:BlobConfig.StorageAccountName), Container: $($Script:BlobConfig.ResultsContainerName), Blob: $reportBlobName" -Level Info -Category "Storage"

            $targetContainer = Get-AzStorageContainer -Name $Script:BlobConfig.ResultsContainerName -Context $storageContext -ErrorAction SilentlyContinue
            if (-not $targetContainer) {
                throw "Results container '$($Script:BlobConfig.ResultsContainerName)' does not exist or is not accessible in storage account '$($Script:BlobConfig.StorageAccountName)'"
            }

            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tempFile -Value $htmlcontent -Encoding UTF8
                Set-AzStorageBlobContent -File $tempFile `
                    -Container $Script:BlobConfig.ResultsContainerName `
                    -Blob $reportBlobName `
                    -Context $storageContext `
                    -Force | Out-Null

                $savedBlob = Get-AzStorageBlob -Container $Script:BlobConfig.ResultsContainerName -Blob $reportBlobName -Context $storageContext -ErrorAction SilentlyContinue
                if (-not $savedBlob) {
                    throw "Blob upload verification failed for '$reportBlobName' in container '$($Script:BlobConfig.ResultsContainerName)'"
                }

                # Best-effort manifest update (non-critical path)
                try {
                    $reportSasUrl = New-ReportBlobReadSasUrl `
                        -StorageContext $storageContext `
                        -ContainerName $Script:BlobConfig.ResultsContainerName `
                        -BlobName $reportBlobName `
                        -ExpiryDays 30

                    $manifest = Get-ReportsManifestObject `
                        -StorageContext $storageContext `
                        -ContainerName $Script:BlobConfig.ResultsContainerName `
                        -ManifestBlobName "reports-manifest.json"

                    $entry = [ordered]@{
                        filename = [string]$reportBlobName
                        date     = (Get-Date).ToUniversalTime().ToString("o")
                        type     = "Weekly"
                        sasUrl   = [string]$reportSasUrl
                    }

                    $manifest = Add-OrUpdate-ReportsManifestEntry -Manifest $manifest -Entry $entry

                    Save-ReportsManifestObject `
                        -StorageContext $storageContext `
                        -ContainerName $Script:BlobConfig.ResultsContainerName `
                        -Manifest $manifest `
                        -ManifestBlobName "reports-manifest.json"

                    Write-ScriptLog "reports-manifest.json updated for weekly report: $reportBlobName" -Level Info -Category "Storage"
                } catch {
                    Write-ScriptLog "Manifest update warning (weekly report): $($_.Exception.Message)" -Level Warning -Category "Storage"
                }

                Write-ScriptLog "Report saved to blob: $reportBlobName (Container: $($Script:BlobConfig.ResultsContainerName))" -Level Success
                Write-Host ("HTML report saved to blob: {0}" -f $reportBlobName) -ForegroundColor Green
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        } catch {
            Write-ScriptLog "Failed to save report to blob storage: $($_.Exception.Message)" -Level Error
            Write-Host ("Failed to save HTML report to blob: {0}" -f $_.Exception.Message) -ForegroundColor Red
            throw
        }
    } else {
        # Local development - save to results directory
        $resultsDir = ".\results"
        if (-not (Test-Path $resultsDir)) {
            New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
            Write-ScriptLog "Created results directory: $resultsDir" -Level Info
        }
        $filePath = Join-Path $resultsDir $reportBlobName
        try {
            Set-Content -Path $filePath -Value $htmlcontent -Encoding UTF8
            Write-ScriptLog "Report saved locally: $filePath" -Level Success
            Write-Host ("HTML report saved to: {0}" -f $filePath) -ForegroundColor Green
        } catch {
            Write-ScriptLog "Failed to save report locally: $($_.Exception.Message)" -Level Error
            Write-Host ("Failed to save HTML report: {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
    }

    # Email webhook delivery (enabled when a Logic App webhook URL is configured)
    $webhookUrl = $Script:Constants.LogicAppSendAIEmailWebHookURL
    if ($webhookUrl) {
        Write-ScriptLog "Sending report with $totalProcessedTickets processed incidents via webhook..." -Level Info
        $result = Send-ReportWebhook -WebhookUrl $webhookUrl -HtmlContent $htmlcontent -Subject $dynamicSubject
        Write-ScriptLog "Report sent successfully: $totalProcessedTickets incidents across $($CategoryData.Count) categories" -Level Success
    } else {
        Write-ScriptLog "No Logic App webhook URL configured; skipping email delivery" -Level Warning
    }
    
    # Complete logging with success message
    Complete-BlobLogging -FinalMessage ("Execution completed successfully - {0} incidents processed ({1})" -f $totalProcessedTickets, $dataSource)
    
} catch {
    Write-ScriptLog "EUC workflow execution failed: $($_.Exception.Message)" -Level Error
    Write-ScriptLog "Stack trace: $($_.ScriptStackTrace)" -Level Debug
    
    # Complete logging even on error
    Complete-BlobLogging -FinalMessage "Execution failed with error: $($_.Exception.Message)"
    
    throw
}

#endregion

<#
.NOTES
===================================================================================
SERVICENOW EUC INCIDENT CATEGORIZATION SYSTEM v1.2
===================================================================================

PURPOSE:
This system provides automated categorization and reporting for resolved Mobile 
Device Management incidents from ServiceNow using AI-powered analysis with root cause 
categorization rules.

NEW IN v1.2:
- Enhanced detailed logging with ticket-specific information
- AI reasoning capture and logging for category selections
- Categorized logging (TicketData, WorkNotes, AISummary, Categorization, Processing)
- Cleaned work notes logging (truncated for readability)
- AI explanation logging for transparency and troubleshooting
- Updated TicketAnalysis class with Reasoning property

LOGGING ENHANCEMENTS:
- Detailed ticket processing logs with categories
- Cleaned work notes logged (first 500 chars for readability)
- AI-generated summaries logged for each ticket
- Category selection with confidence levels logged
- AI reasoning for category choices logged for transparency
- Processing success/failure tracking per ticket

LOG CATEGORIES:
- TicketData: Original ticket information and descriptions
- WorkNotes: Work notes processing and cleanup
- AISummary: AI-generated incident summaries
- Categorization: Category selection, confidence, and AI reasoning
- Processing: General processing flow and results

EXAMPLE LOG OUTPUT:
[2025-06-27 14:30:15] [Info] [TicketData] Processing ticket INC0123456: Outlook not syncing emails
[2025-06-27 14:30:15] [Info] [WorkNotes] Cleaned work notes for INC0123456: User reported Outlook sync issues...
[2025-06-27 14:30:17] [Info] [AISummary] Generated summary for INC0123456: Email sync resolved by profile reset
[2025-06-27 14:30:18] [Info] [Categorization] Category selected for INC0123456: Email Configuration (Confidence: High)
[2025-06-27 14:30:18] [Info] [Categorization] AI reasoning for INC0123456: Keywords 'Outlook', 'syncing' indicate email client issue
[2025-06-27 14:30:18] [Success] [Processing] Successfully processed ticket INC0123456 - Category: Email Configuration

LOGGING CONFIGURATION:
- Set $Script:LogFilePrefix to customize log file names
- Set $Script:LogContainerName to specify the blob container for logs
- Set $Script:LogLevel to control logging verbosity (Debug, Info, Warning, Error)
- Set $Script:EnableBlobLogging to enable/disable blob storage logging

These can be viewed in:
- Azure Portal > Storage Account > Containers > {LogContainerName}

ARCHITECTURE:
The system is built using a modular, pipeline-based architecture with enhanced logging:

1. CONFIGURATION LAYER
   - Centralized settings for AI processing and webhook delivery
   - Enhanced logging configuration with blob storage support
   - Updated class definitions with AI reasoning support

2. UTILITY LAYER  
   - Enhanced logging with categories and detailed ticket information
   - Unified text processing pipeline for AI responses
   - Input validation and error handling

3. SERVICE LAYER
   - OAuth authentication for ServiceNow and AI APIs
   - Standardized API communication with retry logic
   - Timeout handling and connection management

4. AI PROCESSING LAYER
   - Enhanced AI processing with detailed logging at each step
   - Work notes cleanup with before/after logging
   - Incident summarization with result logging
    - Root cause categorization with reasoning capture
   - Structured response parsing with AI explanation extraction

5. DATA PROCESSING LAYER
   - Enhanced ticket processing with detailed logging
   - Category statistics generation
   - Structured data representation with reasoning

6. REPORTING LAYER
   - Professional HTML report generation (reasoning not included in reports)
   - Modular table generation for maintainability
   - Webhook delivery with exponential backoff retry

7. ORCHESTRATION LAYER
   - Main workflow coordination with enhanced progress logging
   - Comprehensive error handling and logging
   - Detailed execution tracking and summary statistics

WORKFLOW:
ServiceNow Authentication â†’ Incident Retrieval â†’ Enhanced AI Processing â†’ 
Root Cause Categorization with Reasoning â†’ Report Generation â†’ Email Delivery

TROUBLESHOOTING:
- Check execution logs in Azure Blob Storage for detailed ticket processing information
- Review AI reasoning logs to understand category selection decisions
- Monitor work notes processing to ensure proper cleanup
- Track processing success/failure rates by category
- Analyze AI confidence levels for quality assurance

===================================================================================
#>



