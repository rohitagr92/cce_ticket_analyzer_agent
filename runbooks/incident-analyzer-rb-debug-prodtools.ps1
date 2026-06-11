# Detect execution environment
$Script:IsAzureAutomation = $env:AUTOMATION_ASSET_ACCOUNTID -or $PSPrivateMetadata.JobId

 
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
        StorageAccountName = Get-AutomationVariable -Name "Incidents_analyzer_StorageAccountName"
        PromptContainerName = Get-AutomationVariable -Name "Incidents_analyzer_PromptTemplateContainerName"
        ResourceGroupName = Get-AutomationVariable -Name "Incidents_analyzer_ResourceGroupName"
        DataContainerName = Get-AutomationVariable -Name "Incidents_analyzer_DataContainerName"
        ResultsContainerName = Get-AutomationVariable -Name "Incidents_analyzer_ResultsContainerName"
        SubscriptionId = Get-AutomationVariable -Name "Incidents_analyzer_SubscriptionId"
        StatisticsTableName = "IncidentsCategoryStats"  # Azure Table for statistics
        }
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
    }
} else {
    Write-Host "Running in local development environment" -ForegroundColor Yellow
    # Local development - console logging only, more verbose
    $Script:LogLevel = "Debug"
    $Script:EnableBlobLogging = $false

    # Local development - load Productivity Tools config + secrets
    $Script:ScriptDirectory = $PSScriptRoot
    Set-Location $Script:ScriptDirectory
    $configPath  = ".\Config\LocalConfig-ProductivityTools.psd1"
    $secretsPath = ".\Config\LocalSecrets-ProductivityTools.psd1"
    if (Test-Path $configPath) {
        Write-Host "Loading Productivity Tools configuration from $configPath" -ForegroundColor Green
        $Script:LocalConfig = Import-PowerShellDataFile -Path $configPath
    } else {
        throw "$configPath not found. Please create it for local development."
    }
    if (Test-Path $secretsPath) {
        Write-Host "Merging Productivity Tools secrets from $secretsPath" -ForegroundColor Green
        $secrets = Import-PowerShellDataFile -Path $secretsPath
        foreach ($k in $secrets.Keys) { $Script:LocalConfig[$k] = $secrets[$k] }
    } else {
        Write-Host "WARNING: $secretsPath not found - ClientSecret / API key will be null" -ForegroundColor Yellow
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
    }
}

<#
.SYNOPSIS
    ServiceNow Mobile Device Management Incident Categorization System
    
.DESCRIPTION
    This script retrieves resolved incidents from ServiceNow for the Mobile Device Management team,
    processes them using AI for strict categorization and summarization, then generates an HTML 
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
        
        Write-Host "✓ Log file saved to blob storage: $($Script:LogConfig.CurrentLogFile)" -ForegroundColor Green
        Write-Host "  Container: $($Script:LogConfig.LogContainerName)" -ForegroundColor Gray
        Write-Host "  Storage Account: $($Script:BlobConfig.StorageAccountName)" -ForegroundColor Gray
        
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
        
        Write-ScriptLog "Retrieving markdown file: $FileName" -Level Info

        if (-not $Script:IsAzureAutomation) {
            # Local development - use local template files
            $localPath = ".\Templates\$FileName"
            if (Test-Path $localPath) {
                Write-ScriptLog "Loading local template: $localPath" -Level Info
                $content = Get-Content $localPath -Raw -Encoding UTF8
                if ([string]::IsNullOrWhiteSpace($content)) {
                    throw "Local template file is empty: $localPath"
                }
                Write-ScriptLog "Successfully retrieved $FileName ($(($content.Length)) characters)" -Level Success
                return $content
            } else {
                throw "Local template file not found: $localPath"
            }
        }

        # Azure Automation - use blob storage
        # Ensure we have a valid Azure context
        $azContext = Get-AzContext
        if (-not $azContext) {
            Write-ScriptLog "No Azure context found, connecting with managed identity..." -Level Warning
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
            Write-ScriptLog "Successfully authenticated with managed identity" -Level Success
        }

        # Get storage account key for authentication
        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $Script:BlobConfig.ResourceGroupName -Name $Script:BlobConfig.StorageAccountName)[0].Value
        $Context = New-AzStorageContext -StorageAccountName $Script:BlobConfig.StorageAccountName -StorageAccountKey $storageKey

        # Check if blob exists
        $blob = Get-AzStorageBlob -Container $Script:BlobConfig.PromptContainerName -Blob $FileName -Context $Context -ErrorAction SilentlyContinue
        
        if (-not $blob) {
            # List available blobs for debugging
            Write-ScriptLog "Blob '$FileName' not found. Available blobs in container '$($Script:BlobConfig.PromptContainerName)':" -Level Warning
            $availableBlobs = Get-AzStorageBlob -Container $Script:BlobConfig.PromptContainerName -Context $Context -ErrorAction SilentlyContinue
            if ($availableBlobs) {
                $availableBlobs | ForEach-Object { Write-ScriptLog "  - $($_.Name)" -Level Debug }
            } else {
                Write-ScriptLog "  No blobs found or unable to list container contents" -Level Warning
            }
            throw "Markdown file '$FileName' not found in container '$($Script:BlobConfig.PromptContainerName)'"
        }
        
        $tempFile = [System.IO.Path]::GetTempFileName()
        
        try {
            Write-ScriptLog "Downloading blob to temporary file: $tempFile" -Level Debug
            Get-AzStorageBlobContent -Container $Script:BlobConfig.PromptContainerName -Blob $FileName -Destination $tempFile -Context $Context -Force -ErrorAction Stop | Out-Null
            
            if (-not (Test-Path $tempFile)) {
                throw "Failed to download blob - temporary file not created"
            }
            
            $content = Get-Content -Path $tempFile -Raw -Encoding UTF8
            
            if ([string]::IsNullOrWhiteSpace($content)) {
                throw "Downloaded file is empty or contains only whitespace"
            }
            
            Write-ScriptLog "Successfully retrieved $FileName ($(($content.Length)) characters)" -Level Success
            return $content
            
        } finally {
            if (Test-Path $tempFile) {
                Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        
    } catch {
        Write-ScriptLog "Failed to get markdown file '$FileName': $($_.Exception.Message)" -Level Error
        Write-ScriptLog "Container: $($Script:BlobConfig.PromptContainerName)" -Level Error
        Write-ScriptLog "Storage Account: $($Script:BlobConfig.StorageAccountName)" -Level Error
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


function Write-ApiRequestDebug {
    [CmdletBinding()]
    param(
        [string]$Url,
        [hashtable]$Headers,
        [object]$Body,
        [string]$Method
    )
    
    Write-ScriptLog "=== DETAILED API REQUEST DEBUG ===" -Level Debug
    Write-ScriptLog "Method: $Method" -Level Debug
    Write-ScriptLog "URL: $Url" -Level Debug
    
    # Log headers (mask sensitive data)
    Write-ScriptLog "Headers:" -Level Debug
    foreach ($key in $Headers.Keys) {
        $value = if ($key -like "*key*" -or $key -like "*token*" -or $key -like "*auth*") {
            "***MASKED*** (length: $($Headers[$key].Length))"
        } else {
            $Headers[$key]
        }
        Write-ScriptLog "  $key : $value" -Level Debug
    }
    
    # Log body details
    if ($Body) {
        $bodyJson = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 }
        Write-ScriptLog "Body size: $($bodyJson.Length) bytes" -Level Debug
        
        # Log first 2000 chars of body
        $bodyPreview = if ($bodyJson.Length -gt 2000) {
            $bodyJson.Substring(0, 2000) + "`n... [TRUNCATED] ..."
        } else {
            $bodyJson
        }
        Write-ScriptLog "Body content:" -Level Debug
        Write-ScriptLog $bodyPreview -Level Debug
    }
    
    Write-ScriptLog "=== END REQUEST DEBUG ===" -Level Debug
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
        Write-ScriptLog "=== DEBUG: API Call Start ===" -Level Debug
        Write-ScriptLog "Method: $Method" -Level Debug
        Write-ScriptLog "URL: $Url" -Level Debug
        
        # Choose authentication method based on parameters
        if ($ApiKey) {
            if ($IsClaudeApi -or $Script:Constants.UseClaudeModel) {
                # Claude/Anthropic API authentication - uses x-api-key header
                $headers = @{
                    "x-api-key" = $ApiKey
                    "anthropic-version" = $Script:Constants.ClaudeApiVersion
                }
                Write-ScriptLog "Using Claude authentication (x-api-key)" -Level Debug
                Write-ScriptLog "Anthropic version: $($Script:Constants.ClaudeApiVersion)" -Level Debug
            } else {
                # Azure OpenAI API key authentication
                $headers = @{
                    "api-key" = $ApiKey
                }
                Write-ScriptLog "Using Azure OpenAI authentication (api-key)" -Level Debug
            }
        } else {
            # OAuth Bearer token authentication (for ServiceNow)
            $headers = @{
                Authorization = "Bearer $AccessToken"
            }
            Write-ScriptLog "Using OAuth Bearer token authentication" -Level Debug
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
            
            Write-ScriptLog "Request body size: $($requestBodyJson.Length) bytes" -Level Debug
            
            # Log body preview for debugging (first 1000 chars)
            $bodyPreview = if ($requestBodyJson.Length -gt 1000) {
                $requestBodyJson.Substring(0, 1000) + "..."
            } else {
                $requestBodyJson
            }
            Write-ScriptLog "Request body preview: $bodyPreview" -Level Debug
        }
        
        Write-ScriptLog "Sending $Method request..." -Level Debug
        Write-ApiRequestDebug -Url $Url -Headers $headers -Body $requestParams.Body -Method $Method
        $response = Invoke-RestMethod @requestParams
        
        Write-ScriptLog "$Method API request completed successfully" -Level Success
        Write-ScriptLog "=== DEBUG: API Call Complete ===" -Level Debug
        
        return $response
        
    } catch {
        Write-ScriptLog "=== API CALL ERROR DETAILS ===" -Level Error
        Write-ScriptLog "Error Message: $($_.Exception.Message)" -Level Error
        Write-ScriptLog "Error Type: $($_.Exception.GetType().FullName)" -Level Error
        
        # Extract HTTP status code and description
        if ($_.Exception.Response) {
            try {
                $statusCode = [int]$_.Exception.Response.StatusCode
                $statusDescription = $_.Exception.Response.StatusDescription
                Write-ScriptLog "HTTP Status Code: $statusCode" -Level Error
                Write-ScriptLog "HTTP Status Description: $statusDescription" -Level Error
                
                # Read the response stream to get detailed error message
                $responseStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($responseStream)
                $responseBody = $reader.ReadToEnd()
                $reader.Close()
                $responseStream.Close()
                
                Write-ScriptLog "=== API ERROR RESPONSE BODY ===" -Level Error
                Write-ScriptLog $responseBody -Level Error
                Write-ScriptLog "=== END API ERROR RESPONSE ===" -Level Error
                
                # Try to parse as JSON for better readability
                try {
                    $errorJson = $responseBody | ConvertFrom-Json
                    if ($errorJson.error) {
                        Write-ScriptLog "Parsed Error: $($errorJson.error | ConvertTo-Json -Depth 5)" -Level Error
                    }
                    if ($errorJson.message) {
                        Write-ScriptLog "Error Message: $($errorJson.message)" -Level Error
                    }
                    if ($errorJson.type) {
                        Write-ScriptLog "Error Type: $($errorJson.type)" -Level Error
                    }
                } catch {
                    # Response body is not JSON, already logged as plain text above
                    Write-ScriptLog "Response body is not JSON format" -Level Debug
                }
                
            } catch {
                Write-ScriptLog "Could not read error response stream: $($_.Exception.Message)" -Level Warning
            }
        }
        
        # Log ErrorDetails if available (PowerShell's additional error info)
        if ($_.ErrorDetails) {
            Write-ScriptLog "=== POWERSHELL ERROR DETAILS ===" -Level Error
            Write-ScriptLog $_.ErrorDetails.Message -Level Error
            Write-ScriptLog "=== END ERROR DETAILS ===" -Level Error
        }
        
        # Log target information
        if ($_.TargetObject) {
            Write-ScriptLog "Target Object: $($_.TargetObject)" -Level Debug
        }
        
        # Log stack trace for debugging
        Write-ScriptLog "=== STACK TRACE ===" -Level Debug
        Write-ScriptLog $_.ScriptStackTrace -Level Debug
        Write-ScriptLog "=== END STACK TRACE ===" -Level Debug
        
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
        return @{
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
            max_tokens = $Script:Config.AI.MaxTokens
            top_p = $Script:Config.AI.TopP
            frequency_penalty = $Script:Config.AI.FrequencyPenalty
            presence_penalty = $Script:Config.AI.PresencePenalty
            stop = $null
        }
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
        [object]$IncidentData
    )
    
    try {
        Write-ScriptLog "=== DEBUG: Get-IncidentCategory Start ===" -Level Debug -Category "Categorization"
        Write-ScriptLog "Incident Number: $($IncidentData.IncidentNumber)" -Level Debug -Category "Categorization"
        
        $systemPrompt = $Script:PromptTemplates.TicketCategorisation + "`n`n" + $Script:PromptTemplates.IntuneEnvironmentContext
        # $systemPrompt = $Script:PromptTemplates.TicketCategorisation 
        
        # Convert to JSON with consistent formatting - use Compress to avoid whitespace issues
        $incidentJson = $IncidentData | ConvertTo-Json -Depth 4 -Compress
        
        # Validate JSON before sending
        try {
            $null = $incidentJson | ConvertFrom-Json
            Write-ScriptLog "Incident JSON validated successfully" -Level Debug -Category "Categorization"
        } catch {
            Write-ScriptLog "WARNING: Incident JSON validation failed: $($_.Exception.Message)" -Level Warning -Category "Categorization"
            Write-ScriptLog "Problematic JSON: $incidentJson" -Level Error -Category "Categorization"
            throw "Invalid JSON generated from incident data"
        }
        
        $jsonSize = $incidentJson.Length
        Write-ScriptLog "Incident JSON size: $jsonSize bytes" -Level Debug -Category "Categorization"
        
        $requestBody = New-AiRequestBody -SystemPrompt $systemPrompt -UserContent $incidentJson -TaskType 'Category'
        
        # Validate the complete request body before sending
        try {
            $testJson = $requestBody | ConvertTo-Json -Depth 10 -Compress
            $null = $testJson | ConvertFrom-Json
            Write-ScriptLog "Request body JSON validated successfully, size: $($testJson.Length) bytes" -Level Debug -Category "Categorization"
        } catch {
            Write-ScriptLog "ERROR: Request body JSON validation failed: $($_.Exception.Message)" -Level Error -Category "Categorization"
            Write-ScriptLog "Problematic request body: $($requestBody | ConvertTo-Json -Depth 10)" -Level Error -Category "Categorization"
            throw "Invalid JSON in request body"
        }
        
        $apiKey = if ($Script:Constants.UseClaudeModel) { $Script:Constants.ClaudeApiKey } else { $Script:Constants.AzureOpenAIApiKey }
        
        Write-ScriptLog "Using AI model: $(if ($Script:Constants.UseClaudeModel) { 'Claude' } else { 'Azure OpenAI' })" -Level Info -Category "Categorization"
        Write-ScriptLog "Sending categorization request to AI..." -Level Info -Category "Categorization"
        
        $aiResponse = Invoke-AuthenticatedApiCall -Url (Get-AIEndpoint) -Method POST -RequestBody $requestBody -ApiKey $apiKey -IsClaudeApi:$Script:Constants.UseClaudeModel
        
        Write-ScriptLog "AI categorization response received successfully" -Level Success -Category "Categorization"
        
        # Extract content based on API type
        $responseText = if ($Script:Constants.UseClaudeModel) {
            $aiResponse.content[0].text
        } else {
            $aiResponse.choices[0].message.content
        }
        
        Write-ScriptLog "Response text length: $($responseText.Length) characters" -Level Debug -Category "Categorization"
        
        $categoryInfo = ConvertFrom-AiCategoryResponse -ResponseText $responseText
        
        # Log categorization results with reasoning
        Write-ScriptLog "Category selected for $($IncidentData.IncidentNumber): $($categoryInfo.primary_category) (Confidence: $($categoryInfo.confidence_level))" -Level Info -Category "Categorization"
        if ($categoryInfo.reasoning) {
            Write-ScriptLog "AI reasoning for $($IncidentData.IncidentNumber): $($categoryInfo.reasoning)" -Level Info -Category "Categorization"
        }
        
        Write-ScriptLog "=== DEBUG: Get-IncidentCategory Complete ===" -Level Debug -Category "Categorization"
        
        return $categoryInfo
        
    } catch {
        Write-ScriptLog "=== ERROR in Get-IncidentCategory ===" -Level Error -Category "Categorization"
        Write-ScriptLog "Incident: $($IncidentData.IncidentNumber)" -Level Error -Category "Categorization"
        Write-ScriptLog "Error: $($_.Exception.Message)" -Level Error -Category "Categorization"
        Write-ScriptLog "Stack Trace: $($_.ScriptStackTrace)" -Level Error -Category "Categorization"
        throw
    }
}

function ConvertFrom-AiCategoryResponse {
    [CmdletBinding()]
    param([string]$ResponseText)
    
    $cleanText = $ResponseText.Trim()
    $result = @{}
    
    # Patterns handle optional markdown bold formatting (**) around field names
    $patterns = @{
        'primary_category' = "(?s)\*{0,2}Primary Category:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Exclusion|\n\*{0,2}Confidence|\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\Z)"
        'exclusion_reason' = "(?s)\*{0,2}Exclusion Reason:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Confidence|\n\*{0,2}Reasoning|\Z)"
        'confidence_level' = "(?s)\*{0,2}Confidence Level:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\n\*{0,2}Resolution|\Z)"
        'reasoning' = "(?s)\*{0,2}Reasoning:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Key Evidence|\n\*{0,2}Resolution Summary|\n\*{0,2}How Do I|\Z)"
        'key_evidence' = "(?s)\*{0,2}Key Evidence:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Resolution Summary|\n\*{0,2}How Do I|\Z)"
        'resolution_summary' = "(?s)\*{0,2}Resolution Summary:?\*{0,2}\s*(.+?)(?=\n\*{0,2}How Do I|\n\*{0,2}KB Provided|\Z)"
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
                Write-Host "✓ Raw incident data saved to blob: $fileName" -ForegroundColor Green
                
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
            Write-Host "✓ Raw incident data saved to: $filePath" -ForegroundColor Green
            
            return $filePath
        }
        
    } catch {
        Write-ScriptLog "Failed to save incident data: $($_.Exception.Message)" -Level Error
        Write-Host "✗ Failed to save incident data: $($_.Exception.Message)" -ForegroundColor Red
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
                Write-Host "✓ Loaded $($incidents.Count) incidents from blob: $blobName" -ForegroundColor Green
                
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
            Write-Host "✓ Loaded $($incidents.Count) incidents from: $([System.IO.Path]::GetFileName($filePath))" -ForegroundColor Green
            
            return $incidents
        }
        
    } catch {
        Write-ScriptLog "Failed to load stored incident data: $($_.Exception.Message)" -Level Error
        Write-Host "✗ Failed to load stored incident data: $($_.Exception.Message)" -ForegroundColor Red
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
                    $fileInfo = "  - $($blob.Name) ($(Get-Date $blob.LastModified -Format 'yyyy-MM-dd HH:mm:ss'), $([math]::Round($blob.Length/1KB, 1)) KB)"
                    Write-Host $fileInfo -ForegroundColor Gray
                }
                return $blobs
            } else {
                Write-Host "No incident files found in blob container: $($Script:BlobConfig.DataContainerName)" -ForegroundColor Yellow
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
                        $fileInfo = "  - $($file.Name) ($(Get-Date $file.LastWriteTime -Format 'yyyy-MM-dd HH:mm:ss'), $([math]::Round($file.Length/1KB, 1)) KB)"
                        Write-Host $fileInfo -ForegroundColor Gray
                    }
                    return $incidentFiles
                } else {
                    Write-Host "No incident files found in $dataDir" -ForegroundColor Yellow
                    return @()
                }
            } else {
                Write-Host "Data directory does not exist: $dataDir" -ForegroundColor Yellow
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

        $artifact = [PSCustomObject]@{
            RunGeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            ReportPeriod = $ReportPeriod
            DataSource = $DataSource
            ProcessedTickets = @($Script:ProcessedTickets)
            DetailedSummaries = @($DetailedSummaries)
        }

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
            $artifactDir = ".\data\run_artifacts"
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
                    $artifacts += $artifact
                } finally {
                    if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
                }
            }
        } else {
            $artifactDir = ".\data\run_artifacts"
            if (Test-Path $artifactDir) {
                $files = Get-ChildItem -Path $artifactDir -Filter "run_artifact_*.json" | Sort-Object LastWriteTime
                foreach ($file in $files) {
                    if ($file.LastWriteTime.ToUniversalTime() -lt $cutoffUtc) { continue }
                    $artifact = (Get-Content -Path $file.FullName -Raw -Encoding UTF8) | ConvertFrom-Json
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
        }
    } catch {
        Write-ScriptLog "Failed to merge weekly run artifacts: $($_.Exception.Message)" -Level Warning
        return [PSCustomObject]@{
            ProcessedTickets = [System.Collections.Generic.List[TicketAnalysis]]::new()
            DetailedSummaries = @()
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

    Write-ScriptLog "Applied resolved_at lookback filter ($LookbackHours hours): $($filtered.Count)/$($Incidents.Count) incidents retained" -Level Info
    return @($filtered)
}

#endregion

#region Data Processing Functions

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
        
        $ticket = [TicketAnalysis]::new($Incident.number)
        
        # Clean up category - should be a short category name, not a long AI response
        $rawCategory = $categoryInfo.primary_category
        if ($rawCategory -and $rawCategory.Length -gt 100) {
            # Category is too long - likely parsing failed, extract first line only
            $rawCategory = ($rawCategory -split "`n")[0].Trim()
        }
        # Remove any markdown formatting from category
        $rawCategory = $rawCategory -replace '\*+', ''
        
        $ticket.Category = $rawCategory
        $ticket.ExclusionReason = $categoryInfo.exclusion_reason
        # Always persist a usable Confidence + non-empty reasoning so dashboards
        # never show "Unknown" / blank AIAnalysis.
        $ticket.Confidence = Get-NormalizedConfidence -Raw ([string]$categoryInfo.confidence_level)
        if ([string]::IsNullOrWhiteSpace([string]$categoryInfo.reasoning)) {
            $ticket.Reasoning = Get-FallbackReasoning -Ticket $ticket -CategoryInfo $categoryInfo
        } else {
            $ticket.Reasoning = [string]$categoryInfo.reasoning
        }
        $ticket.Evidence = $categoryInfo.key_evidence
        $ticket.Resolution = $categoryInfo.resolution_summary
        $ticket.Type = $categoryInfo.how_do_i_or_error
        $ticket.KnowledgeBase = $categoryInfo.kb_provided
        $ticket.OriginalDescription = $Incident.short_description
        
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
    
    # For display purposes, combine Category with ExclusionReason for Excluded tickets
    $ticketsWithDisplayCategory = $Script:ProcessedTickets | ForEach-Object {
        $displayCategory = $_.Category
        if ($_.Category -eq 'Excluded' -and $_.ExclusionReason) {
            $displayCategory = "Excluded`nExclusion Reason: $($_.ExclusionReason)"
        }
        [PSCustomObject]@{
            Number = $_.Number
            DisplayCategory = $displayCategory
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
            Write-Host "✗ Statistics table '$tableName' not found. Run Setup-StatisticsTable.ps1 first." -ForegroundColor Red
            return $null
        }
        
        return $table.CloudTable
        
    } catch {
        Write-ScriptLog "Failed to access statistics table: $($_.Exception.Message)" -Level Error
        return $null
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
        - Timestamp: Auto-generated by Azure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$CategoryData,  # Kept for backward compatibility, but we use ProcessedTickets
        
        [DateTime]$ReportDate = (Get-Date)
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
        
        foreach ($ticket in $Script:ProcessedTickets) {
            try {
                # Create entity properties for individual incident
                $entityProperties = @{
                    "Category"   = [string]$ticket.Category
                    "Date"       = [string]$dateString
                    "YearWeek"   = [string]$yearWeekString
                    "Year"       = [int]$year
                    "WeekNumber" = [int]$weekNumber
                }
                
                # Save incident record
                # PartitionKey = YearWeek for efficient weekly queries
                # RowKey = Incident ID (unique)
                Add-AzTableRow -Table $cloudTable `
                    -PartitionKey $yearWeekString `
                    -RowKey $ticket.Number `
                    -Property $entityProperties `
                    -UpdateExisting | Out-Null
                
                $savedCount++
                
            } catch {
                $errorCount++
                Write-ScriptLog "Failed to save incident $($ticket.Number): $($_.Exception.Message)" -Level Warning
            }
        }
        
        if ($errorCount -eq 0) {
            Write-ScriptLog "Successfully saved $savedCount incident records to Azure Table" -Level Success
            Write-Host "✓ Statistics saved: $savedCount incidents to table $($Script:BlobConfig.StatisticsTableName)" -ForegroundColor Green
        } else {
            Write-ScriptLog "Saved $savedCount incidents with $errorCount errors" -Level Warning
            Write-Host "! Statistics: $savedCount saved, $errorCount errors" -ForegroundColor Yellow
        }
        
    } catch {
        Write-ScriptLog "Failed to save statistics to Azure Table: $($_.Exception.Message)" -Level Error
        Write-ScriptLog "Stack Trace: $($_.ScriptStackTrace)" -Level Error
        Write-Host "✗ Failed to save statistics: $($_.Exception.Message)" -ForegroundColor Red
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
        - Category, Date, YearWeek, Year, WeekNumber
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
    
    Write-ScriptLog "Generating HTML report for EUC team with $($CategoryData.Count) categories" -Level Info
    
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
    
    $htmlTemplate = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>EUC Resolved Tickets AI Categorization Report</title>
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
        .servicenow-link { background:#f8f9fa; color:#0071c5; padding:6px 10px; border-radius:3px; text-decoration:none; font-size:11px; font-weight:600; border:1px solid #dee2e6; }
        .footer { background:#0071c5; color:white; text-align:center; padding:15px; font-size:12px; }
        .total-row { background:#0071c5; color:white; font-weight:bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>EUC Resolved Tickets AI Categorization</h1>
            <div class="subtitle">Analysis Period: $Script:reportperiod</div>
        </div>
        <div class="stats">
            <div class="stat">
                <div class="stat-value">$totalTickets</div>
                <div class="stat-label">Resolved Tickets Processed</div>
            </div>
            <div class="stat">
                <div class="stat-value">$totalCategories</div>
                <div class="stat-label">Strict Categories Applied</div>
            </div>
        </div>
        <div class="section">
            <h2 id="category-summary">Strict Category Analysis Summary</h2>
            $categoryTableHtml
        </div>
        $incidentDetailsHtml
        $serviceRequestDetailsHtml
        <div class="footer">
            Generated by EUC AI Categorization System • $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        </div>
    </div>
</body>
</html>
"@
    
    Write-ScriptLog "HTML report generated successfully for EUC team ($(($htmlTemplate.Length / 1024).ToString('N1')) KB)" -Level Success
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
            <th style="width:35%;">STRICT CATEGORY</th>
            <th style="width:10%;">COUNT</th>
            <th style="width:55%;">TICKET NUMBERS</th>
        </tr>
    </thead>
    <tbody>
        $($tableRows -join "`n        ")
        <tr class="total-row">
            <td>TOTAL PROCESSED</td>
            <td style="text-align:center;">$totalTickets</td>
            <td style="font-style:italic;">All resolved EUC tickets categorized</td>
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
        $category = $CategoryLookup[$summary.IncidentNumber] ?? "Unknown"
        
        $formattedSummary = $summary.SummarisedNotes -replace "`r`n|`n|`r", "<br>"
        $formattedSummary = $formattedSummary -replace "Key Actions:", "<strong style='color:#0071c5;'>Key Actions:</strong>"
        $formattedSummary = $formattedSummary -replace "Critical Details:", "<strong style='color:#0071c5;'>Critical Details:</strong>"
        $formattedSummary = $formattedSummary -replace "Work Notes:", "<strong style='color:#0071c5;'>Work Notes:</strong>"
        $formattedSummary = $formattedSummary -replace "•", "&bull;"
        
        if ($formattedSummary -notmatch "^<strong.*?>Problem:</strong>") {
            $formattedSummary = "<strong style='color:#0071c5;'>Problem:</strong> " + $formattedSummary
        }
        
        # Add AI reasoning and confidence if available
        if ($ProcessedTicketsData.Count -gt 0) {
            $ticketAnalysis = $ProcessedTicketsData | Where-Object { $_.Number -eq $summary.IncidentNumber } | Select-Object -First 1
            if ($ticketAnalysis -and $ticketAnalysis.Reasoning) {
                $confidenceLevel = $ticketAnalysis.Confidence ?? "Unknown"
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
        "Detailed EUC Incident Analysis" 
    } else { 
        "Detailed EUC Service Request Analysis" 
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
                        <th style="width:18%;">STRICT CATEGORY</th>
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
    
    Write-ScriptLog "Sending HTML report to webhook for email delivery ($(($HtmlContent.Length / 1024).ToString('N1')) KB)" -Level Info
    
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
# Productivity Tools: blob/file names carry the _ProductivityTools suffix but
# the hashtable keys are kept short so existing references in this script work.
$Script:PromptTemplates = @{}
$templateMap = [ordered]@{
    WorkNotesCleanup     = "WorkNotesCleanup_ProductivityTools"
    WorkNotesSummary     = "WorkNotesSummary_ProductivityTools"
    TicketCategorisation = "TicketCategorisation_ProductivityTools"
    EnvironmentContext   = "EnvironmentContext_ProductivityTools"
}
$loadedCount = 0
$failedFiles = @()

foreach ($key in $templateMap.Keys) {
    $blobName = $templateMap[$key]
    try {
        $Script:PromptTemplates[$key] = Get-BlobMarkdownContent -FileName $blobName
        $loadedCount++
    } catch {
        $failedFiles += $blobName
        Write-Host "✗ Failed to load: $blobName - $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($loadedCount -eq $templateMap.Count) {
    Write-Host "✓ Successfully loaded all $loadedCount Productivity Tools prompt templates" -ForegroundColor Green
} else {
    Write-Host "⚠ Loaded $loadedCount/$($templateMap.Count) prompt templates. Failed: $($failedFiles -join ', ')" -ForegroundColor Yellow
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
        DefaultSubject = "EUC Resolved Ticket AI Strict Categorization Report"
    }
    
    Logging = @{
        EnableDebug = $true
        TimestampFormat = "yyyy-MM-dd HH:mm:ss"
    }
}

# Normalises a raw confidence value to High/Medium/Low so the dashboards never
# fall back to "Unknown". When the model gives no parseable level, defaults to
# Medium (no per-product root-cause signal is available in this debug variant).
function Get-NormalizedConfidence {
    [CmdletBinding()]
    param([string]$Raw)
    if (-not [string]::IsNullOrWhiteSpace($Raw)) {
        $clean = ($Raw -replace '\*+', '').Trim()
        if ($clean -imatch '\bhigh\b')                       { return 'High' }
        if ($clean -imatch '\bmedium\b|\bmoderate\b|\bmed\b') { return 'Medium' }
        if ($clean -imatch '\blow\b')                        { return 'Low' }
    }
    return 'Medium'
}

# Composes a minimal narrative so AIAnalysis is never blank in the dashboards.
function Get-FallbackReasoning {
    [CmdletBinding()]
    param([object]$Ticket, [object]$CategoryInfo)
    $parts = @()
    $resolution = [string]$CategoryInfo.resolution_summary
    if (-not [string]::IsNullOrWhiteSpace($resolution)) { $parts += "Resolution: $resolution" }
    if ($parts.Count -gt 0) { return ("$($Ticket.Category) :: " + ($parts -join '. ') + '.') }
    return "$($Ticket.Category): detailed analysis was not captured for this ticket."
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
$aiModel = if ($Script:Constants.UseClaudeModel) { "Claude Sonnet 4.5 ($($Script:Constants.ClaudeDeployment))" } else { "Azure OpenAI ($($Script:Constants.AzureOpenAIDeployment))" }
Write-ScriptLog "AI Model: $aiModel" -Level Info
Write-ScriptLog "All functions loaded successfully - EUC system ready for execution" -Level Success

try {
    # Initialize enhanced logging
    Initialize-BlobLogging
    
    Write-ScriptLog "=== STARTING EUC Ticket PROCESSING WORKFLOW ===" -Level Info
    
    # Data Retrieval Phase - Check if using stored data or API
    if ($Script:Constants.UseStoredIncidents) {
        Write-ScriptLog "=== LOADING STORED INCIDENT DATA ===" -Level Info
        
        # Show available files for reference
        Get-AvailableIncidentFiles | Out-Null
        
        # Load stored incidents
        $incidents = Get-StoredIncidents -FileName $Script:Constants.StoredDataFileName
        
        # Set report period based on stored data or current date
        $yesterday = (Get-Date).AddDays(-1)
        $today = Get-Date
        $Script:reportperiod = "Stored Data Analysis - $($yesterday.ToString('yyyy-MM-dd HH:mm')) to $($today.ToString('yyyy-MM-dd HH:mm'))"
        
    } else {
        # Authentication Phase
        Write-ScriptLog "=== AUTHENTICATION PHASE ===" -Level Info
        $serviceNowToken = Get-AccessToken -TokenUrl $Script:Constants.TokenUrl -ClientId $Script:Constants.ServiceNowIncidentsClientID -ClientSecret $Script:Constants.ServiceNowIncidentsClientSecret -Scope $Script:Constants.ServiceNowIncidentsScope
        
        # ServiceNow Incidents API Call
        Write-ScriptLog "=== SERVICENOW INCIDENT DATA RETRIEVAL ===" -Level Info
        $yesterday = (Get-Date).AddDays(-1)
        $today = Get-Date
        $Script:reportperiod = "$($yesterday.ToString('yyyy-MM-dd HH:mm'))" + " to " + "$($today.ToString('yyyy-MM-dd HH:mm'))"

        $incidentsResponse = Invoke-AuthenticatedApiCall -Url $Script:Constants.ServicenowIncidentsURL -AccessToken $serviceNowToken -Method GET
        $incidents = $incidentsResponse.result

        $lookbackHours = [int]($Script:Constants.DailyLookbackHours ?? 26)
        $incidents = Filter-IncidentsByResolvedWindow -Incidents $incidents -LookbackHours $lookbackHours
        
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
                    Write-ScriptLog "Incident processing progress: $processedIncidentCount/$totalIncidents incidents ($percentComplete%)" -Level Info
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
    if (($Script:Constants.SaveRunArtifacts ?? $true) -eq $true) {
        Save-RunProcessingArtifact -DetailedSummaries $allsummarisednotes -ReportPeriod $Script:reportperiod -DataSource $dataSource | Out-Null
    }

    # Weekend weekly merge mode - merge last N days and de-duplicate by incident number
    $generateWeeklyMerged = ($Script:Constants.GenerateWeeklyMergedReportOnWeekend ?? $false) -eq $true -and ((Get-Date).DayOfWeek -in @('Saturday', 'Sunday'))
    if ($generateWeeklyMerged) {
        $lookbackDays = [int]($Script:Constants.WeeklyMergeLookbackDays ?? 7)
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
            $Script:reportperiod = "Weekly merged report (last $lookbackDays days)"
            $dataSource = "Merged Weekly Artifacts"
            Write-ScriptLog "Weekly merge mode enabled - merged $($Script:ProcessedTickets.Count) unique incidents" -Level Success
        } else {
            Write-ScriptLog "Weekly merge mode enabled but no run artifacts found - using current run data" -Level Warning
        }
    }

    # Generate and send report
    Write-ScriptLog "=== REPORT GENERATION ===" -Level Info
    $CategoryData = Get-CategoryStatistics
    $totalTickets = if ($CategoryData.Count -gt 0) { 
        ($CategoryData | Measure-Object -Property Count -Sum).Sum 
    } else { 
        0 
    }
    
    # Save statistics to Azure Table Storage for historical tracking and REST API access
    Write-ScriptLog "=== SAVING STATISTICS TO AZURE TABLE ===" -Level Info
    Save-CategoryStatisticsToTable -CategoryData $CategoryData -ReportDate (Get-Date)
    
    $htmlcontent = New-HtmlTicketReport -CategoryData $CategoryData -DetailedSummaries $allsummarisednotes
    $totalProcessedTickets = $processedIncidentCount
    if ($dataSource -eq "Merged Weekly Artifacts") {
        $totalProcessedTickets = $Script:ProcessedTickets.Count
    }
    $dynamicSubject = "EUC AI Analysis Report - $totalProcessedTickets Incidents, $($CategoryData.Count) Categories ($dataSource) - $(Get-Date -Format 'dd MMM')"
    
    $webhookUrl = $Script:Constants.LogicAppSendAIEmailWebHookURL
    if ($webhookUrl) {
        Write-ScriptLog "Sending report with $totalProcessedTickets processed incidents via webhook..." -Level Info
        $result = Send-ReportWebhook -WebhookUrl $webhookUrl -HtmlContent $htmlcontent -Subject $dynamicSubject
        Write-ScriptLog "Report sent successfully: $totalProcessedTickets incidents across $($CategoryData.Count) categories" -Level Success
    } else {
        Write-ScriptLog "No webhook URL configured - saving report to storage instead" -Level Warning
        
        # Generate filename from dynamic subject (sanitize for filesystem)
        $sanitizedSubject = $dynamicSubject  -replace '[^a-zA-Z0-9]', '_'  -replace '_+','_'
        $fileName = "$sanitizedSubject.html"
        
        if ($Script:IsAzureAutomation) {
            # Azure Automation - save to blob storage
            try {
                $storageContext = Get-StorageContext
                
                # Create temp file for upload
                $tempFile = [System.IO.Path]::GetTempFileName()
                try {
                    Set-Content -Path $tempFile -Value $htmlcontent -Encoding UTF8
                    
                    # Upload to blob storage
                    Set-AzStorageBlobContent -File $tempFile `
                        -Container $Script:BlobConfig.ResultsContainerName `
                        -Blob $fileName `
                        -Context $storageContext `
                        -Force | Out-Null
                    
                    Write-ScriptLog "Report saved to blob: $fileName (Container: $($Script:BlobConfig.ResultsContainerName))" -Level Success
                    Write-ScriptLog "Blob report contains: $totalProcessedTickets incidents across $($CategoryData.Count) categories" -Level Info
                    Write-Host "✓ HTML report saved to blob: $fileName" -ForegroundColor Green
                    
                } finally {
                    if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
                }
            } catch {
                Write-ScriptLog "Failed to save report to blob storage: $($_.Exception.Message)" -Level Error
                Write-Host "✗ Failed to save HTML report to blob: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            # Local development - save to results directory
            $resultsDir = ".\results"
            if (-not (Test-Path $resultsDir)) {
                New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
                Write-ScriptLog "Created results directory: $resultsDir" -Level Info
            }
            
            $filePath = Join-Path $resultsDir $fileName
            
            try {
                # Save HTML content to file
                Set-Content -Path $filePath -Value $htmlcontent -Encoding UTF8
                Write-ScriptLog "Report saved locally: $filePath" -Level Success
                Write-ScriptLog "Local report contains: $totalProcessedTickets incidents across $($CategoryData.Count) categories" -Level Info
                Write-Host "✓ HTML report saved to: $filePath" -ForegroundColor Green
            } catch {
                Write-ScriptLog "Failed to save report locally: $($_.Exception.Message)" -Level Error
                Write-Host "✗ Failed to save HTML report: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    
    # Complete logging with success message
    Complete-BlobLogging -FinalMessage "Execution completed successfully - $totalProcessedTickets incidents processed ($dataSource)"
    
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
Device Management incidents from ServiceNow using AI-powered analysis with strict 
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
   - Strict categorization with reasoning capture
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
ServiceNow Authentication → Incident Retrieval → Enhanced AI Processing → 
Strict Categorization with Reasoning → Report Generation → Email Delivery

TROUBLESHOOTING:
- Check execution logs in Azure Blob Storage for detailed ticket processing information
- Review AI reasoning logs to understand category selection decisions
- Monitor work notes processing to ensure proper cleanup
- Track processing success/failure rates by category
- Analyze AI confidence levels for quality assurance

===================================================================================
#>