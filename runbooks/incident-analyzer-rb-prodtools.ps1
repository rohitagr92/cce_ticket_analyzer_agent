# Detect execution environment
$Script:IsAzureAutomation = $env:AUTOMATION_ASSET_ACCOUNTID -or $PSPrivateMetadata.JobId

 
if ($Script:IsAzureAutomation) {
    Write-Host "Running in Azure Automation environment" -ForegroundColor Green
    #Requires -Modules Az.Storage, Az.Accounts
    
    # AUTO-AUTHENTICATION: Use managed identity - NO SIGN-IN PROMPT
    Write-Host "Authenticating with managed identity..." -ForegroundColor Yellow
    try {
        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        Write-Host "Authenticated successfully" -ForegroundColor Green
    } catch {
        Write-Error "Failed to authenticate with managed identity: $_"
        throw
    }
    
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
        # Description: use a sortable timestamp (YYYY-MM-DD_HH-mm-ss) to
        # produce unique, time-ordered log filenames. This format is used for
        # blob log file naming so that logs sort correctly in storage and can
        # be correlated with run artifacts and weekly merges.
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

#region Log Analytics Heartbeat (monitoring)

# Posts a compact JSON heartbeat to a Log Analytics workspace via the HTTP Data
# Collector API. Used for per-run monitoring (job Started/Completed/Failed).
# Workspace id/key are read from Automation variables LAWorkspaceId / LAWorkspaceKey.
function Send-LogAnalyticsHeartbeat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Started','Completed','Failed')][string]$Status,
        [int]$ProcessedCount = 0,
        [int]$ErrorCount = 0,
        [string]$Message = ''
    )

    try {
        # Resolve workspace credentials (Automation variables in cloud; LocalConfig locally)
        if ($Script:IsAzureAutomation) {
            $workspaceId  = Get-AutomationVariable -Name 'LAWorkspaceId' -ErrorAction SilentlyContinue
            $workspaceKey = Get-AutomationVariable -Name 'LAWorkspaceKey' -ErrorAction SilentlyContinue
        } else {
            $workspaceId  = $Script:LocalConfig.LAWorkspaceId
            $workspaceKey = $Script:LocalConfig.LAWorkspaceKey
        }

        if ([string]::IsNullOrWhiteSpace($workspaceId) -or [string]::IsNullOrWhiteSpace($workspaceKey)) {
            Write-Host 'Heartbeat skipped: LAWorkspaceId/LAWorkspaceKey not configured' -ForegroundColor Yellow
            return
        }

        $jobId = if ($PSPrivateMetadata.JobId) { $PSPrivateMetadata.JobId.Guid } else { [string]([guid]::NewGuid()) }

        $body = @{
            jobId          = $jobId
            jobName        = 'incident-analyzer-rb-prodtools'
            status         = $Status
            processedCount = $ProcessedCount
            errorCount     = $ErrorCount
            message        = $Message
            timestamp      = (Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json -Depth 4

        $logType        = 'IncidentAnalyzerHeartbeat'
        $rfc1123date    = (Get-Date).ToUniversalTime().ToString('r')
        $contentLength  = [System.Text.Encoding]::UTF8.GetByteCount($body)
        $stringToHash   = "POST`n$contentLength`napplication/json`nx-ms-date:$rfc1123date`n/api/logs"
        $bytesToHash    = [System.Text.Encoding]::UTF8.GetBytes($stringToHash)
        $keyBytes       = [Convert]::FromBase64String($workspaceKey)
        $hmac           = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key       = $keyBytes
        $encodedHash    = [Convert]::ToBase64String($hmac.ComputeHash($bytesToHash))
        $signature      = "SharedKey ${workspaceId}:${encodedHash}"
        $uri            = "https://$workspaceId.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"

        $headers = @{
            'Authorization'        = $signature
            'Log-Type'             = $logType
            'x-ms-date'            = $rfc1123date
            'time-generated-field' = 'timestamp'
        }

        Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null
        Write-Host "Heartbeat sent: $Status" -ForegroundColor Cyan
    } catch {
        # Monitoring must never break the main workflow
        Write-Host "Heartbeat failed ($Status): $($_.Exception.Message)" -ForegroundColor Yellow
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
    
    # Description: log entry timestamp format is controlled by
    # $Script:Config.Logging.TimestampFormat so logging consumers (console
    # output, blob logs, and any downstream parsers) see consistent timestamps.
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
                $statusCode = [int]$_.Exception.Response.StatusCode
                $statusDescription = $_.Exception.Response.StatusDescription
                Write-ScriptLog "HTTP Status: $statusCode - $statusDescription" -Level Error
                
                # Read the response stream to get detailed error message
                $responseStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($responseStream)
                $responseBody = $reader.ReadToEnd()
                $reader.Close()
                $responseStream.Close()
                
                Write-ScriptLog "API Error Response: $responseBody" -Level Error
                
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
            max_completion_tokens = $Script:Config.AI.MaxTokens
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
        # Build the system prompt with all 4 reference MD files so the AI can ONLY
        # pick labels from the canonical lists defined by the source-of-truth templates.
        $systemPrompt = $Script:PromptTemplates.TicketCategorisation + "`n`n" +
                        $Script:PromptTemplates.EnvironmentContext + "`n`n" +
                        "## REFERENCE: Subcategory (Sub-Symptom) Labels`n" +
                        $Script:PromptTemplates.TrendSubCategorisation + "`n`n" +
                        "## REFERENCE: Possible Root Cause Labels`n" +
                        $Script:PromptTemplates.PossibleRootCause + "`n`n" +
                        "## REFERENCE: Detailed Root Cause Entries`n" +
                        $Script:PromptTemplates.DetailedRootCause + "`n`n" +
                        @"
## ADDITIONAL REQUIRED OUTPUT FIELDS

After the existing Primary Category / Sub-symptom / Confidence / Reasoning / Key Evidence / Resolution Summary / How Do I or Error / KB Provided fields, append these two lines:

Possible Root Cause: [Pick exactly ONE label from the 'Root Cause Label' column of the chosen Primary Category's table in the 'Possible Root Cause' reference above. Copy the label verbatim. If no label fits, write "Unknown".]

Detailed Root Cause: [Pick exactly ONE entry heading from the chosen Primary Category's section in the 'Detailed Root Cause' reference above (the '### Heading' lines). Copy verbatim. If no entry fits, write "Unknown".]

STRICT RULE: Do NOT invent labels. Do NOT paraphrase. Output the exact text from the MD reference files. Anything you produce that is not in those files will be rejected and replaced with "Unknown".
"@
        
        # Convert to JSON with consistent formatting - use Compress to avoid whitespace issues
        $incidentJson = $IncidentData | ConvertTo-Json -Depth 4 -Compress
        
        # Validate JSON before sending
        try {
            $null = $incidentJson | ConvertFrom-Json
        } catch {
            Write-ScriptLog "WARNING: Incident JSON validation failed: $($_.Exception.Message)" -Level Warning -Category "Categorization"
            throw "Invalid JSON generated from incident data"
        }
        
        $requestBody = New-AiRequestBody -SystemPrompt $systemPrompt -UserContent $incidentJson -TaskType 'Category'
        
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
    
    # Patterns handle optional markdown bold formatting (**) around field names
    # IMPORTANT: every primary_category/exclusion_reason lookahead MUST include
    # 'Sub-symptom' so the sub-symptom line does not bleed into the category text.
    $patterns = @{
        'primary_category'     = "(?s)\*{0,2}Primary Category:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Exclusion|\n\*{0,2}Sub-symptom|\n\*{0,2}Confidence|\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'exclusion_reason'     = "(?s)\*{0,2}Exclusion Reason:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Sub-symptom|\n\*{0,2}Confidence|\n\*{0,2}Reasoning|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'sub_symptom'          = "(?s)\*{0,2}Sub-symptom:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Confidence|\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'confidence_level'     = "(?s)\*{0,2}Confidence Level:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\n\*{0,2}Resolution|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'reasoning'            = "(?s)\*{0,2}Reasoning:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Key Evidence|\n\*{0,2}Resolution Summary|\n\*{0,2}How Do I|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'key_evidence'         = "(?s)\*{0,2}Key Evidence:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Resolution Summary|\n\*{0,2}How Do I|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'resolution_summary'   = "(?s)\*{0,2}Resolution Summary:?\*{0,2}\s*(.+?)(?=\n\*{0,2}How Do I|\n\*{0,2}KB Provided|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'how_do_i_or_error'    = "(?s)\*{0,2}How Do I or Error:?\*{0,2}\s*(.+?)(?=\n\*{0,2}KB Provided|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'kb_provided'          = "(?s)\*{0,2}KB Provided:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'possible_root_cause'  = "(?s)\*{0,2}Possible Root Cause:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Detailed Root|\Z)"
        'detailed_root_cause'  = "(?s)\*{0,2}Detailed Root Cause:?\*{0,2}\s*(.+)"
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

# === Stage 2 Rescue: narrow re-classifier for PRC/DRC Unknowns ===
# When the main categorization returns Unknown for PossibleRootCause or DetailedRootCause,
# this function makes a second, much smaller AI call that sees ONLY the labels valid for
# the already-confirmed Category. This dramatically reduces ambiguity vs. the giant
# 4-template prompt used in Get-IncidentCategory.
function Resolve-RootCauseRescue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Category,
        [string]$Subcategory,
        [Parameter(Mandatory)] [string]$AnalystSummary,
        [string]$ShortDescription,
        [string]$WorkNotes,
        [System.Collections.Generic.List[string]]$PrcAllowlist,
        [System.Collections.Generic.List[string]]$DrcAllowlist,
        [bool]$NeedPrc = $true,
        [bool]$NeedDrc = $true
    )

    try {
        $prcLines = if ($PrcAllowlist) { ($PrcAllowlist | ForEach-Object { "- $_" }) -join "`n" } else { '' }
        $drcLines = if ($DrcAllowlist) { ($DrcAllowlist | ForEach-Object { "- $_" }) -join "`n" } else { '' }

        $askPrc = if ($NeedPrc -and $PrcAllowlist -and $PrcAllowlist.Count -gt 0) { @"

VALID POSSIBLE ROOT CAUSE LABELS for Category '$Category' (pick the BEST matching one):
$prcLines
"@ } else { '' }

        $askDrc = if ($NeedDrc -and $DrcAllowlist -and $DrcAllowlist.Count -gt 0) { @"

VALID DETAILED ROOT CAUSE HEADINGS for Category '$Category' (pick the BEST matching one):
$drcLines
"@ } else { '' }

        $systemPrompt = @"
You are a strict classification mapper. The ticket has already been confirmed to belong to the Category below. Your job is to pick the SINGLE BEST matching label from each provided list.

Rules:
1. You MUST pick a label from the list whenever any reasonable semantic match exists. Partial matches are acceptable - pick the closest one.
2. Copy the chosen label EXACTLY as written, including capitalization, punctuation, parentheses, and special characters. Do not paraphrase, shorten, or reword.
3. Only output 'Unknown' if the ticket evidence is genuinely unrelated to every label in the list (extremely rare - the ticket has already been classified into this Category, so at least one label almost always applies).
4. Tie-breaker priority when multiple labels seem plausible: prefer the most specific label over the most generic one.
5. Use the analyst summary AND the work notes together. The work notes often contain the smoking-gun keyword.

Category: $Category
Subcategory: $Subcategory
$askPrc
$askDrc

Respond in EXACTLY this format, no preamble, no explanation, no markdown:
PossibleRootCause: <one label copied verbatim from the PRC list>
DetailedRootCause: <one heading copied verbatim from the DRC list>
"@

        $userContent = @"
Short Description: $ShortDescription

Analyst Summary: $AnalystSummary

Cleaned Work Notes (truncated):
$($WorkNotes -replace '\s+', ' ' | ForEach-Object { if ($_.Length -gt 2000) { $_.Substring(0,2000) } else { $_ } })
"@

        $requestBody = New-AiRequestBody -SystemPrompt $systemPrompt -UserContent $userContent -TaskType 'Category'
        $apiKey = if ($Script:Constants.UseClaudeModel) { $Script:Constants.ClaudeApiKey } else { $Script:Constants.AzureOpenAIApiKey }
        $aiResponse = Invoke-AuthenticatedApiCall -Url (Get-AIEndpoint) -Method POST -RequestBody $requestBody -ApiKey $apiKey -IsClaudeApi:$Script:Constants.UseClaudeModel

        $responseText = if ($Script:Constants.UseClaudeModel) { $aiResponse.content[0].text } else { $aiResponse.choices[0].message.content }
        $responseText = [string]$responseText

        $prc = $null; $drc = $null
        if ($responseText -match '(?im)^\s*PossibleRootCause:\s*(.+?)\s*$') { $prc = $matches[1].Trim() -replace '\*+','' }
        if ($responseText -match '(?im)^\s*DetailedRootCause:\s*(.+?)\s*$')  { $drc = $matches[1].Trim() -replace '\*+','' }

        return [PSCustomObject]@{
            PossibleRootCause = $prc
            DetailedRootCause = $drc
            RawResponse       = $responseText
        }
    } catch {
        Write-ScriptLog "Resolve-RootCauseRescue failed: $($_.Exception.Message)" -Level Warning -Category "RescueClassifier"
        return [PSCustomObject]@{ PossibleRootCause = $null; DetailedRootCause = $null; RawResponse = $null }
    }
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
        # Description: create a timestamped artifact filename for run outputs.
        # The artifact includes `RunGeneratedAtUtc` and `YearWeek` fields so
        # weekly merge jobs can easily group artifacts by ISO week. The
        # filename uses the same sortable timestamp format as logs to simplify
        # cross-referencing artifacts with job logs.
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $fileName = "run_artifact_$timestamp.json"

        # Calculate ISO week number for this artifact
        # Compute ISO-style week number (FirstFourDayWeek, Monday start) so
        # weekly artifacts align with business reporting windows used by the
        # trend/backfill runbooks. This YearWeek value is included in the
        # artifact payload for consistent weekly merging and reporting.
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
        # Calculate the current week number to filter artifacts
        $currentWeekNumber = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
            (Get-Date),
            [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
            [System.DayOfWeek]::Monday
        )
        $currentYear = (Get-Date).Year
        $currentYearWeek = "{0:D4}-W{1:D2}" -f $currentYear, $currentWeekNumber
        Write-ScriptLog "Merging artifacts for current week: $currentYearWeek" -Level Info

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
                    
                    # Filter by week: only include artifacts from the current week
                    if ($artifactYearWeek -and $artifactYearWeek -ne $currentYearWeek) {
                        Write-ScriptLog "Skipping artifact $($blob.Name) from week $artifactYearWeek (current week: $currentYearWeek)" -Level Info
                        continue
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
                    
                    # Filter by week: only include artifacts from the current week
                    if ($artifactYearWeek -and $artifactYearWeek -ne $currentYearWeek) {
                        Write-ScriptLog "Skipping artifact $($file.Name) from week $artifactYearWeek (current week: $currentYearWeek)" -Level Info
                        continue
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
                $converted.SubSymptom = [string]$ticket.SubSymptom
                # New canonical fields (Phase 1) - copy from cache if present
                $converted.Subcategory       = [string]$ticket.Subcategory
                $converted.PossibleRootCause = [string]$ticket.PossibleRootCause
                $converted.DetailedRootCause = [string]$ticket.DetailedRootCause
                $converted.Service           = if ([string]::IsNullOrWhiteSpace([string]$ticket.Service)) { 'Productivity Tools' } else { [string]$ticket.Service }
                $converted.Misrouted         = [bool]($converted.Category -eq 'Excluded')
                $converted.ExclusionReason = [string]$ticket.ExclusionReason
                $converted.Confidence = [string]$ticket.Confidence
                $converted.Reasoning = [string]$ticket.Reasoning
                $converted.Evidence = [string]$ticket.Evidence
                $converted.Resolution = [string]$ticket.Resolution
                $converted.Type = [string]$ticket.Type
                $converted.KnowledgeBase = [string]$ticket.KnowledgeBase
                $converted.OriginalDescription = [string]$ticket.OriginalDescription
                # Carry through ResolvedAt so Save-CategoryStatisticsToTable can partition
                # each row to its true ISO week (not the merged-report week).
                $converted.ResolvedAt = [string]$ticket.ResolvedAt

                [DateTime]$parsedProcessed = [DateTime]::MinValue
                if ([DateTime]::TryParse([string]$ticket.Processed, [ref]$parsedProcessed)) {
                    $converted.Processed = $parsedProcessed
                }

                $null = Ensure-TicketAiFields -Ticket $converted

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
        [array]$Incidents = @(),

        [int]$LookbackHours = 26
    )

    if ($LookbackHours -le 0) {
        return $Incidents
    }

    # Description: the $LookbackHours parameter controls the sliding window
    # used to select recently-resolved incidents for the daily job. Default
    # is 26 (24 hours + 2 hour buffer) to ensure late-arriving resolved
    # tickets are included in the day's processing. $cutoff is computed from
    # the current local time and compared against each incident's resolved_at
    # timestamp. If an incident's date cannot be parsed it is conservatively
    # kept to avoid accidental data loss.
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
        $rawCategory = Get-CanonicalAlias -Field 'Category' -Product '' -Raw $rawCategory
        
        # STRICT MD ALLOWLIST: coerce category to a canonical label from TicketCategorisation.md
        $canonicalCategory = Get-CanonicalLabel -Raw $rawCategory -Allowlist $Script:CanonicalLabels.Categories -Fallback 'Other / Miscellaneous'
        if ($canonicalCategory -ne $rawCategory) {
            Write-ScriptLog "Coerced category '$rawCategory' -> '$canonicalCategory' (MD allowlist)" -Level Info -Category "Categorization"
        }
        $ticket.Category = $canonicalCategory

        # Clean sub-symptom: strip bold markers and keep only the first line if AI emitted extras
        $rawSubSymptom = [string]$categoryInfo.sub_symptom
        if ($rawSubSymptom) {
            $rawSubSymptom = ($rawSubSymptom -split "`n")[0].Trim()
            $rawSubSymptom = $rawSubSymptom -replace '\*+', ''
        }
        $rawSubSymptom = Get-CanonicalAlias -Field 'Subcategory' -Product $canonicalCategory -Raw $rawSubSymptom
        $ticket.SubSymptom = $rawSubSymptom

        # Canonical subcategory (per-product allowlist from TrendSubCategorisation.md)
        $subAllowlist = Get-AllowlistForProduct -Map $Script:CanonicalLabels.Subcategories -Product $canonicalCategory
        $ticket.Subcategory = Get-CanonicalLabel -Raw $rawSubSymptom -Allowlist $subAllowlist -Fallback ''
        if ([string]::IsNullOrWhiteSpace($ticket.Subcategory)) {
            $ticket.Subcategory = Get-CanonicalFallbackLabel -Field Subcategory -Product $canonicalCategory -Allowlist $subAllowlist
        }

        # Canonical Possible Root Cause (per-product allowlist from PossibleRootCause.md)
        $prcAllowlist = Get-AllowlistForProduct -Map $Script:CanonicalLabels.PossibleRootCauses -Product $canonicalCategory
        $rawPrc = Get-CanonicalAlias -Field 'PossibleRootCause' -Product $canonicalCategory -Raw ([string]$categoryInfo.possible_root_cause)
        $ticket.PossibleRootCause = Get-CanonicalLabel -Raw $rawPrc -Allowlist $prcAllowlist -Fallback ''
        if ([string]::IsNullOrWhiteSpace($ticket.PossibleRootCause)) {
            $ticket.PossibleRootCause = Get-CanonicalFallbackLabel -Field PossibleRootCause -Product $canonicalCategory -Allowlist $prcAllowlist
        }

        # Canonical Detailed Root Cause (per-product allowlist from DetailedRootCause.md)
        $drcAllowlist = Get-AllowlistForProduct -Map $Script:CanonicalLabels.DetailedRootCauses -Product $canonicalCategory
        $rawDrc = Get-CanonicalAlias -Field 'DetailedRootCause' -Product $canonicalCategory -Raw ([string]$categoryInfo.detailed_root_cause)
        $ticket.DetailedRootCause = Get-CanonicalLabel -Raw $rawDrc -Allowlist $drcAllowlist -Fallback ''
        if ([string]::IsNullOrWhiteSpace($ticket.DetailedRootCause)) {
            $ticket.DetailedRootCause = Get-CanonicalFallbackLabel -Field DetailedRootCause -Product $canonicalCategory -Allowlist $drcAllowlist
        }

        # Stage 2 rescue: if either PRC or DRC is still empty, ask the AI to map again
        # using ONLY the narrow per-category allowlists. This trades 1 extra small AI call
        # for a much lower empty-label rate without touching the source-of-truth MD files.
        $needPrcRescue = ([string]::IsNullOrWhiteSpace($ticket.PossibleRootCause) -and $prcAllowlist -and $prcAllowlist.Count -gt 0)
        $needDrcRescue = ([string]::IsNullOrWhiteSpace($ticket.DetailedRootCause) -and $drcAllowlist -and $drcAllowlist.Count -gt 0)
        if ($Script:Config.Rescue.Enabled -and ($needPrcRescue -or $needDrcRescue)) {
            Write-ScriptLog "RESCUE [$($Incident.number)] invoking narrow re-classifier (needPrc=$needPrcRescue needDrc=$needDrcRescue)" -Level Info -Category "RescueClassifier"
            $rescue = Resolve-RootCauseRescue `
                -Category          $canonicalCategory `
                -Subcategory       $ticket.Subcategory `
                -AnalystSummary    ([string]$summary) `
                -ShortDescription  ([string]$Incident.short_description) `
                -WorkNotes         ([string]$cleanedNotes) `
                -PrcAllowlist      $prcAllowlist `
                -DrcAllowlist      $drcAllowlist `
                -NeedPrc           $needPrcRescue `
                -NeedDrc           $needDrcRescue
            if ($needPrcRescue -and $rescue.PossibleRootCause) {
                $coerced = Get-CanonicalLabel -Raw $rescue.PossibleRootCause -Allowlist $prcAllowlist -Fallback ''
                if (-not [string]::IsNullOrWhiteSpace($coerced)) {
                    Write-ScriptLog "RESCUE [$($Incident.number)] PRC '$($ticket.PossibleRootCause)' -> '$coerced' (raw='$($rescue.PossibleRootCause)')" -Level Info -Category "RescueClassifier"
                    $ticket.PossibleRootCause = $coerced
                }
            }
            if ($needDrcRescue -and $rescue.DetailedRootCause) {
                $coerced = Get-CanonicalLabel -Raw $rescue.DetailedRootCause -Allowlist $drcAllowlist -Fallback ''
                if (-not [string]::IsNullOrWhiteSpace($coerced)) {
                    Write-ScriptLog "RESCUE [$($Incident.number)] DRC '$($ticket.DetailedRootCause)' -> '$coerced' (raw='$($rescue.DetailedRootCause)')" -Level Info -Category "RescueClassifier"
                    $ticket.DetailedRootCause = $coerced
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($ticket.PossibleRootCause)) {
            $ticket.PossibleRootCause = Get-CanonicalFallbackLabel -Field PossibleRootCause -Product $canonicalCategory -Allowlist $prcAllowlist
        }
        if ([string]::IsNullOrWhiteSpace($ticket.DetailedRootCause)) {
            $ticket.DetailedRootCause = Get-CanonicalFallbackLabel -Field DetailedRootCause -Product $canonicalCategory -Allowlist $drcAllowlist
        }

        # Service is hardcoded for this runbook (separate runbook will handle Email and Calendaring)
        $ticket.Service   = 'Productivity Tools'
        $ticket.Misrouted = ($ticket.Category -eq 'Excluded')

        $ticket.ExclusionReason = $categoryInfo.exclusion_reason

        # Always persist a usable Confidence (High/Medium/Low) so the dashboards
        # never fall back to empty. When the model gives no parseable level we
        # derive one from whether both root causes resolved to canonical labels.
        $rootCausesKnown = (-not [string]::IsNullOrWhiteSpace($ticket.PossibleRootCause) -and -not [string]::IsNullOrWhiteSpace($ticket.DetailedRootCause))
        $ticket.Confidence = Get-NormalizedConfidence -Raw ([string]$categoryInfo.confidence_level) -RootCausesKnown $rootCausesKnown
        if ([string]::IsNullOrWhiteSpace([string]$categoryInfo.confidence_level)) {
            Write-ScriptLog "Confidence not parsed for $($Incident.number) - defaulted to '$($ticket.Confidence)' (rootCausesKnown=$rootCausesKnown)" -Level Info -Category "Categorization"
        }

        # Always persist a non-empty reasoning narrative so AIAnalysis (and the AI
        # Recommendations tab) always has something to show / distil.
        if ([string]::IsNullOrWhiteSpace([string]$categoryInfo.reasoning)) {
            $ticket.Reasoning = Get-FallbackReasoning -Ticket $ticket -CategoryInfo $categoryInfo
            Write-ScriptLog "Reasoning empty for $($Incident.number) - composed fallback narrative from canonical fields" -Level Info -Category "Categorization"
        } else {
            $ticket.Reasoning = [string]$categoryInfo.reasoning
        }
        $ticket.Evidence = $categoryInfo.key_evidence
        $ticket.Resolution = $categoryInfo.resolution_summary
        $ticket.Type = $categoryInfo.how_do_i_or_error
        $ticket.KnowledgeBase = $categoryInfo.kb_provided
        $ticket.OriginalDescription = $Incident.short_description
        $ticket.ResolvedAt = [string]$Incident.resolved_at
        
        $null = Ensure-TicketAiFields -Ticket $ticket -CategoryInfo $categoryInfo
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

function New-FallbackTicketAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Incident,

        [string]$FailureReason = ''
    )

    $ticket = [TicketAnalysis]::new([string]$Incident.number)
    $ticket.Category = 'Other / Miscellaneous'
    $ticket.SubSymptom = 'Unclassified'
    $ticket.Subcategory = 'Unclassified'
    $ticket.PossibleRootCause = 'Usage Guidance (How Do I)'
    $ticket.DetailedRootCause = 'Automated fallback classification'
    $ticket.Service = 'Productivity Tools'
    $ticket.Misrouted = $false
    $ticket.ExclusionReason = ''
    $ticket.Confidence = 'Low'

    $short = ([string]$Incident.short_description).Trim()
    if ([string]::IsNullOrWhiteSpace($short)) {
        $short = ([string]$Incident.description).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($short)) {
        $short = 'No incident summary available from source payload.'
    }

    $reasoning = "Fallback analysis generated because AI categorization failed after retries. Incident: $short"
    if (-not [string]::IsNullOrWhiteSpace($FailureReason)) {
        $reasoning += ". Error: $FailureReason"
    }
    $ticket.Reasoning = $reasoning
    $ticket.Evidence = ''
    $ticket.Resolution = ''
    $ticket.Type = ''
    $ticket.KnowledgeBase = ''
    $ticket.OriginalDescription = [string]$Incident.short_description
    $ticket.ResolvedAt = [string]$Incident.resolved_at

    $null = Ensure-TicketAiFields -Ticket $ticket
    return $ticket
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
        
        # Fallback date components (used only if a ticket has no parseable resolved_at)
        $fallbackDateString = $ReportDate.ToString("yyyy-MM-dd")
        $fallbackYear = $ReportDate.Year
        $fallbackWeekNumber = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
            $ReportDate, 
            [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, 
            [System.DayOfWeek]::Monday
        )
        $fallbackYearWeek = "{0:D4}-W{1:D2}" -f $fallbackYear, $fallbackWeekNumber
        
        Write-ScriptLog "Saving $($Script:ProcessedTickets.Count) incident records to Azure Table (per-ticket week partition; fallback Week=$fallbackYearWeek)" -Level Info
        
        $savedCount = 0
        $errorCount = 0
        $analysisFallbackCount = 0
        $confidenceFallbackCount = 0
        
        foreach ($ticket in $Script:ProcessedTickets) {
            try {
                $reasoningWasBlank = [string]::IsNullOrWhiteSpace([string]$ticket.Reasoning)
                $confidenceWasBlank = [string]::IsNullOrWhiteSpace([string]$ticket.Confidence)
                $null = Ensure-TicketAiFields -Ticket $ticket
                if ($reasoningWasBlank) { $analysisFallbackCount++ }
                if ($confidenceWasBlank) { $confidenceFallbackCount++ }

                # Per-ticket partitioning: use the ticket's own resolved_at so cross-week runs
                # (e.g. backfills, Monday catch-ups) land in the correct week partition.
                $resolvedDt = [DateTime]::MinValue
                $useFallback = $true
                if (-not [string]::IsNullOrWhiteSpace($ticket.ResolvedAt)) {
                    if ([DateTime]::TryParse($ticket.ResolvedAt, [ref]$resolvedDt)) {
                        $useFallback = $false
                    }
                }
                if ($useFallback) {
                    $dateString     = $fallbackDateString
                    $year           = $fallbackYear
                    $weekNumber     = $fallbackWeekNumber
                    $yearWeekString = $fallbackYearWeek
                } else {
                    $dateString     = $resolvedDt.ToString("yyyy-MM-dd")
                    $year           = $resolvedDt.Year
                    $weekNumber     = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
                        $resolvedDt,
                        [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
                        [System.DayOfWeek]::Monday
                    )
                    $yearWeekString = "{0:D4}-W{1:D2}" -f $year, $weekNumber
                }
                
                # Create entity properties for individual incident.
                # Schema source-of-truth: this is what the web app's Trends + Ops Report tabs read.
                $entityProperties = @{
                    "Category"          = [string]$ticket.Category
                    "Subcategory"       = [string]$ticket.Subcategory
                    "PossibleRootCause" = [string]$ticket.PossibleRootCause
                    "DetailedRootCause" = [string]$ticket.DetailedRootCause
                    "Service"           = [string]$ticket.Service
                    "Misrouted"         = [bool]$ticket.Misrouted
                    "Date"              = [string]$dateString
                    "YearWeek"          = [string]$yearWeekString
                    "Year"              = [int]$year
                    "WeekNumber"        = [int]$weekNumber
                    "ReportBlobName"    = [string]$ReportBlobName
                    # Free-form AI rationale + confidence shown in the web Ops report
                    # incident-detail modal alongside the canonical DetailedRootCause.
                    # AIAnalysis is sourced from $ticket.Reasoning (the AI's narrative);
                    # cap to keep Azure Table single-property size sane (64 KiB hard limit).
                    "AIAnalysis"        = if (([string]$ticket.Reasoning).Length -gt 4000) { ([string]$ticket.Reasoning).Substring(0, 4000) + '...' } else { [string]$ticket.Reasoning }
                    "Confidence"        = [string]$ticket.Confidence
                }
                
                # Save incident record
                # PartitionKey = YearWeek (derived from ticket.ResolvedAt; falls back to $ReportDate)
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

        Write-ScriptLog "Data quality guardrails: AIAnalysis fallback applied to $analysisFallbackCount tickets; Confidence fallback applied to $confidenceFallbackCount tickets" -Level Info
        
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
        .servicenow-link { background:#f8f9fa; color:#0071c5; padding:6px 10px; border-radius:3px; text-decoration:none; font-size:11px; font-weight:600; border:1px solid #dee2e6; white-space:nowrap; display:inline-block; }
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
        if ($CategoryLookup[$summary.IncidentNumber]) {
            $category = $CategoryLookup[$summary.IncidentNumber]
        } else {
            $category = "Unknown"
        }
        if ($ProcessedTicketsData.Count -gt 0) {
            $ticketRecord = $ProcessedTicketsData | Where-Object { $_.Number -eq $summary.IncidentNumber } | Select-Object -First 1
        } else {
            $ticketRecord = $null
        }

        # For Excluded tickets, append the exclusion reason below the category in the detail row
        if ($category -eq 'Excluded' -and $ticketRecord -and $ticketRecord.ExclusionReason) {
            $category = "Excluded<br><span style='font-weight:normal;font-size:11px;color:#6c757d;'>$($ticketRecord.ExclusionReason)</span>"
        } elseif ($ticketRecord -and $ticketRecord.SubSymptom) {
            # Show Sub-symptom on a second line beneath the strict category
            $category = "$category<br><span style='font-weight:normal;font-size:11px;color:#6c757d;'>Sub-symptom: $($ticketRecord.SubSymptom)</span>"
        }
        
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
                # Normalize to High/Medium/Low so report UI never shows Unknown.
                $confidenceLevel = Get-NormalizedConfidence -Raw ([string]$ticketAnalysis.Confidence) -RootCausesKnown $true
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
#
# Description:
#  The following map defines the prompt/template files used to construct the
#  large-system prompt that is sent to the AI model. Each entry maps a short
#  logical key (used throughout this runbook) to the template filename base
#  (the markdown files live under `templates/` locally or in the configured
#  blob container in Azure Automation). These templates are the source-of-truth
#  for allowed labels, example phrasing, and the strict categorization rules.
#
#  Template usage summary:
#    - WorkNotesCleanup:   Cleanup rules applied to work notes before summarizing
#    - WorkNotesSummary:   Short human-friendly summary of work notes for context
#    - TicketCategorisation: System prompt + examples for Category/Subcategory
#    - EnvironmentContext: Runtime/environment info appended to prompts
#    - TrendSubCategorisation: Guidance for subcategorization used by trend jobs
#    - PossibleRootCause:   Canonical PRC allowlist (source-of-truth for PRC)
#    - DetailedRootCause:   Canonical DRC headings (detailed root cause entries)
#
#  Note: Get-BlobMarkdownContent will load the named markdown file either from
#  `./Templates/<name>.md` when running locally, or from the configured blob
#  container when running in Azure Automation. The parsed contents are later
#  coerced into canonical allowlists used for dashboard-safe labels.
$Script:PromptTemplates = @{}
$templateMap = [ordered]@{
    WorkNotesCleanup       = "WorkNotesCleanup_ProductivityTools"
    WorkNotesSummary       = "WorkNotesSummary_ProductivityTools"
    TicketCategorisation   = "TicketCategorisation_ProductivityTools"
    EnvironmentContext     = "EnvironmentContext_ProductivityTools"
    TrendSubCategorisation = "TrendSubCategorisation_ProductivityTools"
    PossibleRootCause      = "PossibleRootCause_ProductivityTools"
    DetailedRootCause      = "DetailedRootCause_ProductivityTools"
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

#region Canonical MD Allowlists
# Parses the 4 reference markdown files into hashtables of canonical labels.
# This is what enforces "the MD file is the single source of truth" for
# Category, Subcategory, PossibleRootCause, and DetailedRootCause assignment.
# AI output is later coerced against these lists; anything not matching is force-mapped
# to a canonical fallback label per category.

function Get-CanonicalLabelsFromTemplates {
    [CmdletBinding()]
    param()

    $result = @{
        Categories          = New-Object System.Collections.Generic.List[string]
        Subcategories       = @{}   # product => list of subcategory group headers
        SubcategoryAliasMap = @{}   # "<productNorm>||<symptomNorm>" => group header
        PossibleRootCauses  = @{}   # product => list of root-cause labels
        DetailedRootCauses  = @{}   # product => list of detailed entry headings
    }

    # --- Categories: bold-line product headers in TicketCategorisation ("**Microsoft X Issues**") ---
    $catText = [string]$Script:PromptTemplates.TicketCategorisation
    foreach ($m in [regex]::Matches($catText, '(?m)^\*\*([^*\n]+? Issues)\*\*\s*$')) {
        $label = $m.Groups[1].Value.Trim()
        if (-not $result.Categories.Contains($label)) { $result.Categories.Add($label) }
    }
    # Excluded is a valid category even though it's not "...Issues"
    if (-not $result.Categories.Contains('Excluded'))              { $result.Categories.Add('Excluded') }
    if (-not $result.Categories.Contains('Other / Miscellaneous')) { $result.Categories.Add('Other / Miscellaneous') }

    # --- Subcategories: "#### Product" sections in TrendSubCategorisation ---
    # Canonical value must be the bold grouping header (for example "Sync Issues").
    # Bulleted symptom lines are treated as aliases that map to the active header.
    # Product key here lacks the " Issues" suffix (e.g. "Microsoft OneDrive"); the lookup
    # helper's substring fallback handles "Microsoft OneDrive Issues" -> "Microsoft OneDrive".
    $subText = [string]$Script:PromptTemplates.TrendSubCategorisation
    if ($subText) {
        $sections = [regex]::Split($subText, '(?m)^####\s+') | Where-Object { $_ -match '\S' }
        foreach ($section in $sections) {
            $lines = $section -split "`r?`n", 2
            if ($lines.Count -lt 2) { continue }
            $product = $lines[0].Trim()
            $body    = $lines[1]
            $headers = New-Object System.Collections.Generic.List[string]
            $currentHeader = ''
            foreach ($ln in ($body -split "`r?`n")) {
                $trim = [string]$ln
                $trim = $trim.Trim()
                if (-not $trim) { continue }

                if ($trim -match '^\*\*(.+?)\*\*\s*$') {
                    $currentHeader = $matches[1].Trim()
                    if ($currentHeader -and -not $headers.Contains($currentHeader)) { $headers.Add($currentHeader) }
                    continue
                }

                if ($trim -match '^\s*[-*]\s+(.+?)\s*$') {
                    $sym = $matches[1].Trim()
                    if ($sym -match '^\*\*.+\*\*$') { continue }
                    if ($sym -match '^\*[A-Z]') { continue }
                    $sym = $sym -replace '\s*\(.+?\)\s*$', ''
                    if ($currentHeader -and $sym) {
                        $aliasKey = ('{0}||{1}' -f (Normalize-CanonicalText -Raw $product), (Normalize-CanonicalText -Raw $sym))
                        if (-not $result.SubcategoryAliasMap.ContainsKey($aliasKey)) {
                            $result.SubcategoryAliasMap[$aliasKey] = $currentHeader
                        }
                    }
                }
            }
            if ($headers.Count -gt 0) { $result.Subcategories[$product] = $headers }
        }
    }

    # --- Possible Root Causes: each "## N. Product Issues" section has a markdown table ---
    # Table rows look like: | 1.1 | **Sync Stall** | description |
    $prcText = [string]$Script:PromptTemplates.PossibleRootCause
    if ($prcText) {
        $sections = [regex]::Split($prcText, '(?m)^##\s+\d+\.\s+') | Where-Object { $_ -match '\S' }
        foreach ($section in $sections) {
            $lines = $section -split "`r?`n", 2
            if ($lines.Count -lt 2) { continue }
            $product = $lines[0].Trim()
            $body    = $lines[1]
            $labels  = New-Object System.Collections.Generic.List[string]
            foreach ($m in [regex]::Matches($body, '(?m)^\|\s*\d+\.\d+\s*\|\s*\*\*([^|*]+?)\*\*\s*\|')) {
                $lbl = $m.Groups[1].Value.Trim()
                if ($lbl -and -not $labels.Contains($lbl)) { $labels.Add($lbl) }
            }
            if ($labels.Count -gt 0) { $result.PossibleRootCauses[$product] = $labels }
        }
    }

    # --- Detailed Root Causes: "### Entry heading" lines under each "## Product" section ---
    $drcText = [string]$Script:PromptTemplates.DetailedRootCause
    if ($drcText) {
        $sections = [regex]::Split($drcText, '(?m)^##\s+') | Where-Object { $_ -match '\S' }
        foreach ($section in $sections) {
            $lines = $section -split "`n", 2
            if ($lines.Count -lt 2) { continue }
            $product = ($lines[0] -split '\r?\n')[0].Trim()
            $body    = $lines[1]
            $labels  = New-Object System.Collections.Generic.List[string]
            foreach ($m in [regex]::Matches($body, '(?m)^###\s+(.+?)\s*$')) {
                $lbl = $m.Groups[1].Value.Trim()
                if ($lbl -and -not $labels.Contains($lbl)) { $labels.Add($lbl) }
            }
            if ($labels.Count -gt 0) { $result.DetailedRootCauses[$product] = $labels }
        }
    }

    return $result
}

# Coerces a raw string to a canonical label from an allowlist.
# Strategy: exact (case-insensitive) -> contains -> "Unknown"
function Get-NormalizedConfidence {
    [CmdletBinding()]
    param(
        [string]$Raw,
        [bool]$RootCausesKnown = $true
    )
    # Extract a High/Medium/Low level from whatever the model emitted (handles
    # "**High**", "High - because ...", "Confidence: medium", etc.).
    if (-not [string]::IsNullOrWhiteSpace($Raw)) {
        $clean = ($Raw -replace '\*+', '').Trim()
        if ($clean -imatch '\bhigh\b')                       { return 'High' }
        if ($clean -imatch '\bmedium\b|\bmoderate\b|\bmed\b') { return 'Medium' }
        if ($clean -imatch '\blow\b')                        { return 'Low' }
    }
    # Could not parse a level — derive a defensible default so the dashboards
    # never show "Unknown": both root causes resolved to canonical labels means a
    # solid classification (Medium); otherwise it is weak (Low).
    if ($RootCausesKnown) { return 'Medium' }
    return 'Low'
}

# Build a minimal analysis narrative from canonical fields so AIAnalysis is never
# blank in the dashboards when the model returned no reasoning text.
function Get-FallbackReasoning {
    [CmdletBinding()]
    param([object]$Ticket, [object]$CategoryInfo)
    $parts = @()
    if ($Ticket.Subcategory)                                                    { $parts += "Symptom: $($Ticket.Subcategory)" }
    if ($Ticket.PossibleRootCause -and $Ticket.PossibleRootCause -ne 'Unknown') { $parts += "Possible root cause: $($Ticket.PossibleRootCause)" }
    if ($Ticket.DetailedRootCause -and $Ticket.DetailedRootCause -ne 'Unknown') { $parts += "Detailed root cause: $($Ticket.DetailedRootCause)" }
    $resolution = [string]$CategoryInfo.resolution_summary
    if (-not [string]::IsNullOrWhiteSpace($resolution))                         { $parts += "Resolution: $resolution" }
    if ($parts.Count -gt 0) { return ("$($Ticket.Category) :: " + ($parts -join '. ') + '.') }
    return "$($Ticket.Category): detailed analysis was not captured for this ticket."
}

function Ensure-TicketAiFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Ticket,

        [object]$CategoryInfo = $null
    )

    $rootCausesKnown = (
        -not [string]::IsNullOrWhiteSpace([string]$Ticket.PossibleRootCause) -and
        -not [string]::IsNullOrWhiteSpace([string]$Ticket.DetailedRootCause)
    )
    $Ticket.Confidence = Get-NormalizedConfidence -Raw ([string]$Ticket.Confidence) -RootCausesKnown $rootCausesKnown

    if ([string]::IsNullOrWhiteSpace([string]$Ticket.Reasoning)) {
        $fallbackInfo = if ($CategoryInfo) {
            $CategoryInfo
        } else {
            [PSCustomObject]@{ resolution_summary = [string]$Ticket.Resolution }
        }
        $Ticket.Reasoning = Get-FallbackReasoning -Ticket $Ticket -CategoryInfo $fallbackInfo
    }

    return $Ticket
}

function Normalize-CanonicalText {
    [CmdletBinding()]
    param([string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    $s = $Raw
    $s = $s -replace '[\u2010\u2011\u2012\u2013\u2014\u2015]', '-'
    $s = $s -replace '\*+', ''
    $s = $s -replace '^\["\s]+|["\]\s]+$', ''
    $s = $s -replace '\s+', ' '
    return $s.Trim().ToLowerInvariant()
}

function Get-CanonicalAlias {
    [CmdletBinding()]
    param(
        [ValidateSet('Category','Subcategory','PossibleRootCause','DetailedRootCause')]
        [string]$Field,
        [string]$Product,
        [string]$Raw
    )

    if ([string]::IsNullOrWhiteSpace($Raw)) { return $Raw }

    $p = Normalize-CanonicalText -Raw $Product
    $k = Normalize-CanonicalText -Raw $Raw

    switch ($Field) {
        'Category' {
            if ($k -eq 'microsoft 365 groups / planner / to do issues') { return 'Microsoft 365 Planner / To Do Issues' }
        }
        'Subcategory' {
            if ($Script:CanonicalLabels -and $Script:CanonicalLabels.SubcategoryAliasMap) {
                $aliasKey = ('{0}||{1}' -f $p, $k)
                if ($Script:CanonicalLabels.SubcategoryAliasMap.ContainsKey($aliasKey)) {
                    return [string]$Script:CanonicalLabels.SubcategoryAliasMap[$aliasKey]
                }
            }
            if ($k -eq 'former employee data - beyond 30 days') { return 'Former employee data - beyond 30 days (not recoverable)' }
            if ($k -eq 'former employee data - within 30 days') { return 'Former employee data - within 30 days' }
            if ($k -eq 'copilot not visible (icon missing in excel / word / powerpoint / teams)') { return 'Feature Availability Issues' }
            if ($k -eq 'sync failure (file not uploading, file in cloud missing on device)') { return 'Sync Issues' }
            if ($k -eq 'permissions / access after rehire') { return 'Access & Permission Issues' }
            if ($p -eq 'excluded' -and ($k -eq 'out of scope')) { return 'Out of Scope' }
        }
        'PossibleRootCause' {
            if ($k -eq 'document lock or stuck word process') { return "Word Document Won't Open" }
            if ($k -eq 'permission issue on the synced file or shortcut') { return 'Shared File Permission Denied' }
            if ($k -eq 'rejoin access issue') { return 'PUID Mismatch' }
            if ($k -eq 'sharepoint online access request') { return 'Out-of-scope Service Offering' }
        }
        'DetailedRootCause' {
            if ($k -eq 'unknown' -and $p -eq 'excluded') { return 'Out-of-scope service offering' }
        }
    }

    return $Raw
}

function Get-CanonicalFallbackLabel {
    [CmdletBinding()]
    param(
        [ValidateSet('Subcategory','PossibleRootCause','DetailedRootCause')]
        [string]$Field,
        [string]$Product,
        [System.Collections.Generic.List[string]]$Allowlist
    )

    if (-not $Allowlist -or $Allowlist.Count -eq 0) { return '' }

    $preferred = @()
    switch ($Field) {
        'Subcategory' {
            switch ($Product) {
                'Excluded' { $preferred = @('Out of Scope') }
                'Microsoft OneDrive Issues' { $preferred = @('Access & Permission Issues','Sync Issues') }
                'Microsoft Word Issues' { $preferred = @('File Access Issues','Performance Issues') }
                'Microsoft Excel Issues' { $preferred = @('File Opening Issues','Performance Issues') }
                'Microsoft PowerPoint Issues' { $preferred = @('File Opening Issues','Performance Issues') }
                'Microsoft 365 Copilot Issues' { $preferred = @('Feature Availability Issues','Licensing Issues') }
                'Microsoft 365 Apps for Enterprise Issues' { $preferred = @('Application Access Issues','Licensing Issues') }
                'Microsoft OneNote Issues' { $preferred = @('Application Issues','Missing Data Issues') }
                'Microsoft Forms Issues' { $preferred = @('Access Issues') }
                'Shared File Service (Share Drives) Issues' { $preferred = @('Access Issues') }
                'Google Workspace Issues' { $preferred = @('Access Issues') }
                'Microsoft Loop Issues' { $preferred = @('Workspace Access Issues') }
                'Microsoft 365 Planner / To Do Issues' { $preferred = @('Access Issues') }
                'Smartsheet Issues' { $preferred = @('Access Issues') }
                'Microsoft Project Issues' { $preferred = @('File Handling Issues','Application Issues') }
                default { $preferred = @() }
            }
        }
        'PossibleRootCause' {
            switch ($Product) {
                'Excluded' { $preferred = @('Out-of-scope Service Offering') }
                'Microsoft OneDrive Issues' { $preferred = @('PUID Mismatch','Shared File Permission Denied','Sync Stall') }
                'Microsoft Word Issues' { $preferred = @("Word Document Won't Open") }
                'Microsoft Excel Issues' { $preferred = @('Hung Excel Process') }
                'Microsoft PowerPoint Issues' { $preferred = @("Presentation Won't Open") }
                'Microsoft 365 Copilot Issues' { $preferred = @('Copilot License Blackout') }
                'Microsoft 365 Apps for Enterprise Issues' { $preferred = @('Corrupted Office Identity') }
                'Microsoft OneNote Issues' { $preferred = @('OneNote Feature Not Working') }
                'Microsoft Forms Issues' { $preferred = @('Forms Entitlement Missing') }
                'Shared File Service (Share Drives) Issues' { $preferred = @('AGS Share Entitlement Missing') }
                'Google Workspace Issues' { $preferred = @('External Application Access Issue') }
                'Microsoft Loop Issues' { $preferred = @('Workspace Load Failure') }
                'Microsoft 365 Planner / To Do Issues' { $preferred = @('To Do Account Provisioning Delay') }
                'Smartsheet Issues' { $preferred = @('Smartsheet Entitlement Missing') }
                'Microsoft Project Issues' { $preferred = @('Project File Open / Save Failure') }
                default { $preferred = @('Usage Guidance (How Do I)') }
            }
        }
        'DetailedRootCause' {
            switch ($Product) {
                'Excluded' { $preferred = @('Out-of-scope service offering') }
                'Microsoft OneDrive Issues' { $preferred = @('Rejoin access not reapplied to OneDrive','Shared file permission denied') }
                'Microsoft Word Issues' { $preferred = @("Word document won't open") }
                'Microsoft Excel Issues' { $preferred = @('Excel data refresh failure') }
                'Microsoft PowerPoint Issues' { $preferred = @("Presentation won't open") }
                'Microsoft 365 Copilot Issues' { $preferred = @('Copilot licence blackout (pool depleted)') }
                'Microsoft 365 Apps for Enterprise Issues' { $preferred = @('Corrupted Office installation') }
                'Microsoft OneNote Issues' { $preferred = @('OneNote feature not working') }
                'Microsoft Forms Issues' { $preferred = @('Forms Creation Access entitlement missing') }
                'Shared File Service (Share Drives) Issues' { $preferred = @('Missing AGS entitlement for share') }
                'Google Workspace Issues' { $preferred = @('Google external application access issue') }
                'Microsoft Loop Issues' { $preferred = @('Loop workspace load failure') }
                'Microsoft 365 Planner / To Do Issues' { $preferred = @('M365 Group membership removed') }
                'Smartsheet Issues' { $preferred = @('Smartsheet entitlement missing') }
                'Microsoft Project Issues' { $preferred = @('Project file open / save failure') }
                default { $preferred = @() }
            }
        }
    }

    foreach ($pick in $preferred) {
        foreach ($lbl in $Allowlist) {
            if ($lbl -ieq $pick) { return $lbl }
        }
    }
    return $Allowlist[0]
}

function Get-CanonicalLabel {
    [CmdletBinding()]
    param(
        [string]$Raw,
        [System.Collections.Generic.List[string]]$Allowlist,
        [string]$Fallback = ''
    )

    if (-not $Allowlist -or $Allowlist.Count -eq 0) { return $Fallback }
    if ([string]::IsNullOrWhiteSpace($Raw))         { return $Fallback }

    $clean = Normalize-CanonicalText -Raw $Raw
    if ([string]::IsNullOrWhiteSpace($clean)) { return $Fallback }

    # Exact match (case-insensitive)
    foreach ($lbl in $Allowlist) {
        if ($lbl -ieq $Raw) { return $lbl }
        if ((Normalize-CanonicalText -Raw $lbl) -eq $clean) { return $lbl }
    }
    # Substring match either direction
    foreach ($lbl in $Allowlist) {
        $nLbl = Normalize-CanonicalText -Raw $lbl
        if ($clean -like "*$nLbl*" -or $nLbl -like "*$clean*") { return $lbl }
    }
    return $Fallback
}

# Lookup helpers — pick the allowlist for a product, with case-insensitive product key match
function Get-AllowlistForProduct {
    [CmdletBinding()]
    param(
        [hashtable]$Map,
        [string]$Product
    )
    if (-not $Map -or -not $Product) { return $null }
    if ($Map.ContainsKey($Product))  { return $Map[$Product] }
    foreach ($k in $Map.Keys) {
        if ($k -ieq $Product)               { return $Map[$k] }
        if ($Product -like "*$k*" -or $k -like "*$Product*") { return $Map[$k] }
    }

    # Token-overlap fallback. Handles minor category-name drift such as
    # "Google Issues" (classifier output) -> "Google Workspace Issues" (template key)
    # or "Shared File Access Issues" -> "Shared File Service (Share Drives) Issues".
    # We strip the common " Issues" suffix, normalise to lowercase alphanumeric
    # tokens, drop noise words, and pick the key with the highest shared-token
    # count (Jaccard-ish), preferring a substring hit on the first token.
    $stop = @('issues','microsoft','365','for','enterprise','the','and','of','a','an')
    $tokenize = {
        param([string]$s)
        $s = ($s -replace '\s*Issues\s*$','').ToLower()
        $raw = [regex]::Split($s, '[^a-z0-9]+') | Where-Object { $_ -and $_ -notin $stop }
        @($raw)
    }
    $pTokens = & $tokenize $Product
    if ($pTokens.Count -eq 0) { return $null }
    $best = $null; $bestScore = 0
    foreach ($k in $Map.Keys) {
        $kTokens = & $tokenize $k
        if ($kTokens.Count -eq 0) { continue }
        $shared = @($pTokens | Where-Object { $kTokens -contains $_ }).Count
        if ($shared -gt $bestScore) { $bestScore = $shared; $best = $k }
    }
    if ($best -and $bestScore -gt 0) { return $Map[$best] }
    return $null
}

$Script:CanonicalLabels = Get-CanonicalLabelsFromTemplates
$catCount = $Script:CanonicalLabels.Categories.Count
$subCount = $Script:CanonicalLabels.Subcategories.Count
$prcCount = $Script:CanonicalLabels.PossibleRootCauses.Count
$drcCount = $Script:CanonicalLabels.DetailedRootCauses.Count
Write-Host "[OK] Canonical labels loaded: $catCount categories, $subCount subcategory groups, $prcCount root-cause groups, $drcCount detailed-cause groups" -ForegroundColor Green
#endregion

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

    # Stage 2 rescue classifier — second narrow AI call when PRC/DRC come back Unknown.
    # Tradeoff: ~1 extra small AI call per Unknown ticket. Set to $false to disable.
    Rescue = @{
        Enabled = $true
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

class TicketAnalysis {
    [string]$Number
    [string]$TicketType
    [string]$Category
    [string]$SubSymptom
    [string]$Subcategory          # Canonical (MD-validated) sub-symptom label
    [string]$PossibleRootCause    # Canonical PossibleRootCause label from MD
    [string]$DetailedRootCause    # Canonical DetailedRootCause entry from MD
    [string]$Service              # Service offering ("Productivity Tools" / "Email and Calendaring")
    [bool]$Misrouted              # True if Category = "Excluded"
    [string]$ExclusionReason
    [string]$Confidence
    [string]$Reasoning
    [string]$Evidence
    [string]$Resolution
    [string]$Type
    [string]$KnowledgeBase
    [string]$OriginalDescription
    [string]$ResolvedAt          # Raw ServiceNow resolved_at string (used for week partitioning)
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

# Load-only guard: allows local test harnesses to dot-source this runbook and
# call individual functions (e.g. Resolve-RootCauseRescue) without running the
# full ServiceNow -> AI -> Storage workflow. Azure Automation never sets this.
if ($env:RUNBOOK_LOAD_ONLY -eq '1') {
    Write-Host "RUNBOOK_LOAD_ONLY=1 detected; skipping orchestration." -ForegroundColor Yellow
    return
}

try {
    # Initialize enhanced logging
    Initialize-BlobLogging

    # Monitoring heartbeat: job started
    Send-LogAnalyticsHeartbeat -Status 'Started' -Message 'EUC ticket processing workflow started'
    
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
        # Normalize to a safe array so null API payloads do not fail downstream mandatory binding.
        $incidents = @($incidentsResponse.result)

        if ($Script:Constants.DailyLookbackHours) {
            $lookbackHours = [int]$Script:Constants.DailyLookbackHours
        } else {
            $lookbackHours = 26
        }
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

                $fallbackTicket = New-FallbackTicketAnalysis -Incident $incident -FailureReason $errorMessage
                $Script:ProcessedTickets.Add($fallbackTicket)
                $allsummarisednotes.Add([PSCustomObject]@{
                    IncidentNumber = $incident.number
                    SummarisedNotes = "Fallback summary generated because AI categorization failed after retries."
                })
                $processedIncidentCount++
                $success = $true
                Write-ScriptLog "Applied no-skip fallback ticket for incident $($incident.number)" -Level Warning -Category "Processing"
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

    # Backfill mode: if BackfillYearWeek Automation Variable is set (e.g. "2026-W17"),
    # skip artifact save + weekly merge so historical week runs don't pollute or merge
    # with current-week data. Daily runs leave this variable empty/unset.
    $backfillYearWeek = $null
    try {
        $bfVar = Get-AutomationVariable -Name 'BackfillYearWeek' -ErrorAction SilentlyContinue
        if ($bfVar -and $bfVar -match '^\d{4}-W\d{2}$') { $backfillYearWeek = $bfVar }
    } catch { }
    if ($backfillYearWeek) {
        Write-ScriptLog "BACKFILL MODE active for $backfillYearWeek - skipping artifact save and weekly merge" -Level Info
    }

    # Save per-run artifact for weekly merge (skipped in backfill mode)
    $saveArtifacts = if ($Script:Constants.SaveRunArtifacts) { $Script:Constants.SaveRunArtifacts } else { $true }
    if (-not $backfillYearWeek -and ($saveArtifacts -eq $true)) {
        Save-RunProcessingArtifact -DetailedSummaries $allsummarisednotes -ReportPeriod $Script:reportperiod -DataSource $dataSource | Out-Null
    }

    # Always merge all current week's artifacts to build cumulative weekly report
    # Each daily run adds its artifact, then the full week is merged and the report is overwritten
    # (skipped in backfill mode so historical runs use only the current cohort)
    $lookbackDays = [int](if ($Script:Constants.WeeklyMergeLookbackDays) { $Script:Constants.WeeklyMergeLookbackDays } else { 7 })
    $mergedData = if ($backfillYearWeek) { @{ ProcessedTickets = @(); DetailedSummaries = @(); YearWeek = $backfillYearWeek } } else { Get-MergedWeeklyRunData -LookbackDays $lookbackDays }
    if ($mergedData.ProcessedTickets.Count -gt 0) {
        $Script:ProcessedTickets = $mergedData.ProcessedTickets
        $allsummarisednotes = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($summary in $mergedData.DetailedSummaries) {
            $allsummarisednotes.Add([PSCustomObject]@{
                IncidentNumber = $summary.IncidentNumber
                SummarisedNotes = $summary.SummarisedNotes
            })
        }
        $dataSource = "Merged Weekly ($($Script:ProcessedTickets.Count) incidents)"
        Write-ScriptLog "Weekly merge completed - $($Script:ProcessedTickets.Count) unique incidents from last $lookbackDays days" -Level Success
    } else {
        Write-ScriptLog "No prior run artifacts found - using current run data only" -Level Warning
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
    $reportBlobName = "EUC_Weekly_Report_$reportYearWeek.html"
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
            $storageContext = Get-StorageContext
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tempFile -Value $htmlcontent -Encoding UTF8
                Set-AzStorageBlobContent -File $tempFile `
                    -Container $Script:BlobConfig.ResultsContainerName `
                    -Blob $reportBlobName `
                    -Context $storageContext `
                    -Force | Out-Null
                Write-ScriptLog "Report saved to blob: $reportBlobName (Container: $($Script:BlobConfig.ResultsContainerName))" -Level Success
                Write-Host "✓ HTML report saved to blob: $reportBlobName" -ForegroundColor Green
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
        $filePath = Join-Path $resultsDir $reportBlobName
        try {
            Set-Content -Path $filePath -Value $htmlcontent -Encoding UTF8
            Write-ScriptLog "Report saved locally: $filePath" -Level Success
            Write-Host "✓ HTML report saved to: $filePath" -ForegroundColor Green
        } catch {
            Write-ScriptLog "Failed to save report locally: $($_.Exception.Message)" -Level Error
            Write-Host "✗ Failed to save HTML report: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # COMMENTED OUT - Email webhook delivery (not currently used)
    # $webhookUrl = $Script:Constants.LogicAppSendAIEmailWebHookURL
    # if ($webhookUrl) {
    #     Write-ScriptLog "Sending report with $totalProcessedTickets processed incidents via webhook..." -Level Info
    #     $result = Send-ReportWebhook -WebhookUrl $webhookUrl -HtmlContent $htmlcontent -Subject $dynamicSubject
    #     Write-ScriptLog "Report sent successfully: $totalProcessedTickets incidents across $($CategoryData.Count) categories" -Level Success
    # }
    
    # Monitoring heartbeat: job completed
    Send-LogAnalyticsHeartbeat -Status 'Completed' -ProcessedCount $totalProcessedTickets -Message "Execution completed successfully ($dataSource)"

    # ===== REGENERATE DASHBOARD =====
    # TODO: Optimize dashboard generation - currently disabled to prevent timeout
    # Will be re-enabled after performance tuning
    Write-ScriptLog "Dashboard regeneration temporarily disabled for performance optimization" -Level Info

    # Complete logging with success message
    Complete-BlobLogging -FinalMessage "Execution completed successfully - $totalProcessedTickets incidents processed ($dataSource)"
    
} catch {
    Write-ScriptLog "EUC workflow execution failed: $($_.Exception.Message)" -Level Error
    Write-ScriptLog "Stack trace: $($_.ScriptStackTrace)" -Level Debug

    # Monitoring heartbeat: job failed
    Send-LogAnalyticsHeartbeat -Status 'Failed' -ErrorCount 1 -Message $_.Exception.Message
    
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