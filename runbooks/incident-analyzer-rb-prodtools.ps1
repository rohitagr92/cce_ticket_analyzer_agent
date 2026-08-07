# Detect execution environment
$Script:IsAzureAutomation = $env:AUTOMATION_ASSET_ACCOUNTID -or $PSPrivateMetadata.JobId

# ===================================================================================
# IN-SCRIPT CONFIGURATION OVERRIDES
# Set OverrideDailyLookback to $true to force the script to use the DailyLookbackHours
# value defined below, ignoring Azure Automation Variables / Local Config files.
# ===================================================================================
$Script:LocalOverrides = @{
    OverrideDailyLookback = $false  # Set to $true only for local debugging when you need a fixed lookback
    DailyLookbackHours    = 72     # Local debug fallback; Automation variables should drive real runs/backfills
}

# Work week repair controls.
# Daily runs use the lookback hours above.
# Explicit week repairs are handled by the Azure backfill wrapper with BackfillYearWeek.
# Keep the recent-week window here so it is easy to spot and adjust when needed.
$Script:WorkWeekRepairConfig = @{
    RecentWorkWeeksToReview = 2
    ExplicitYearWeeks       = @()   # Example: @('2026-W30','2026-W31')
}

if ($Script:IsAzureAutomation) {
    Write-Host "Running in Azure Automation environment" -ForegroundColor Green
    
    # Import required Az modules
    Import-Module -Name Az.Storage -Force -ErrorAction Stop
    Import-Module -Name Az.Accounts -Force -ErrorAction Stop

    # Logging and Container Configurations
    $Script:LogFilePrefix = "AI-ResolvedIncidents-StrictCategorization"
    $Script:LogContainerName = "logs"
    $Script:LogLevel = "Info"
    $Script:EnableBlobLogging = $true

    # Storage and Asset Configurations from Automation Variables
    $Script:BlobConfig = @{
        StorageAccountName  = Get-AutomationVariable -Name "Incidents_analyzer_StorageAccountName"
        PromptContainerName = Get-AutomationVariable -Name "Incidents_analyzer_PromptTemplateContainerName"
        ResourceGroupName   = Get-AutomationVariable -Name "Incidents_analyzer_ResourceGroupName"
        DataContainerName   = Get-AutomationVariable -Name "Incidents_analyzer_DataContainerName"
        ResultsContainerName= Get-AutomationVariable -Name "Incidents_analyzer_ResultsContainerName"
        SubscriptionId      = Get-AutomationVariable -Name "Incidents_analyzer_SubscriptionId"
        StatisticsTableName = "IncidentsCategoryStats"
    }

    # Resolve DailyLookbackHours (In-Script Override vs Automation Variable)
    $backfillYearWeek = Get-AutomationVariable -Name 'BackfillYearWeek' -ErrorAction SilentlyContinue
    $effectiveLookback = if ($backfillYearWeek -and $backfillYearWeek -match '^\d{4}-W\d{2}$') {
        0
    } elseif ($Script:LocalOverrides.OverrideDailyLookback) {
        $Script:LocalOverrides.DailyLookbackHours
    } else {
        Get-AutomationVariable -Name "DailyLookbackHours" -ErrorAction SilentlyContinue
    }

    $Script:Constants = @{
        ServiceNowIncidentsClientID          = Get-AutomationVariable -Name "ServiceNowIncidentsClientID"
        ServiceNowIncidentsClientSecret      = Get-AutomationVariable -Name "ServiceNowIncidentsClientSecret"
        ServiceNowIncidentsScope             = Get-AutomationVariable -Name "ServiceNowIncidentsScope"
        TokenUrl                             = Get-AutomationVariable -Name "TokenUrl"
        AzureOpenAIBaseUrl                   = Get-AutomationVariable -Name "AzureOpenAIBaseUrl"
        AzureOpenAIDeployment                = Get-AutomationVariable -Name "AzureOpenAIDeployment"
        AzureOpenAIApiKey                    = Get-AutomationVariable -Name "AzureOpenAIApiKey"
        AzureOpenAIApiVersion                = Get-AutomationVariable -Name "AzureOpenAIApiVersion"
        ServicenowIncidentsURL               = Get-AutomationVariable -Name "ServiceNowIncidentsURL"
        ServicenowRequestsURL                = Get-AutomationVariable -Name "ServiceNowRequestsURL"
        LogicAppSendAIEmailWebHookURL        = Get-AutomationVariable -Name "LogicAppSendAIEmailWebHookURL" -ErrorAction SilentlyContinue 
        UseClaudeModel                       = Get-AutomationVariable -Name "UseClaudeModel" -ErrorAction SilentlyContinue 
        ClaudeEndpoint                       = Get-AutomationVariable -Name "ClaudeEndpoint" -ErrorAction SilentlyContinue 
        ClaudeDeployment                     = Get-AutomationVariable -Name "ClaudeDeployment" -ErrorAction SilentlyContinue 
        ClaudeApiKey                         = Get-AutomationVariable -Name "ClaudeApiKey" -ErrorAction SilentlyContinue 
        ClaudeApiVersion                     = Get-AutomationVariable -Name "ClaudeApiVersion" -ErrorAction SilentlyContinue
        UseStoredIncidents                   = Get-AutomationVariable -Name "UseStoredIncidents" -ErrorAction SilentlyContinue
        StoredDataFileName                   = Get-AutomationVariable -Name "StoredDataFileName" -ErrorAction SilentlyContinue
        SaveRawDataLocally                   = Get-AutomationVariable -Name "SaveRawDataLocally" -ErrorAction SilentlyContinue
        DailyLookbackHours                   = $effectiveLookback
        SaveRunArtifacts                     = Get-AutomationVariable -Name "SaveRunArtifacts" -ErrorAction SilentlyContinue
        GenerateWeeklyMergedReportOnWeekend  = Get-AutomationVariable -Name "GenerateWeeklyMergedReportOnWeekend" -ErrorAction SilentlyContinue
        WeeklyMergeLookbackDays              = Get-AutomationVariable -Name "WeeklyMergeLookbackDays" -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "Running in local development environment" -ForegroundColor Yellow

    $Script:LogLevel = "Debug"
    $Script:EnableBlobLogging = $false

    # Local Development Configurations
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

    # Resolve DailyLookbackHours (In-Script Override vs Local Config)
    $effectiveLookback = if ($Script:LocalOverrides.OverrideDailyLookback) {
        $Script:LocalOverrides.DailyLookbackHours
    } else {
        $Script:LocalConfig.DailyLookbackHours
    }

    $Script:Constants = @{
        ServiceNowIncidentsClientID          = $Script:LocalConfig.ServiceNowIncidentsClientID
        ServiceNowIncidentsClientSecret      = $Script:LocalConfig.ServiceNowIncidentsClientSecret
        ServiceNowIncidentsScope             = $Script:LocalConfig.ServiceNowIncidentsScope
        TokenUrl                             = $Script:LocalConfig.TokenUrl
        AzureOpenAIBaseUrl                   = $Script:LocalConfig.AzureOpenAIBaseUrl
        AzureOpenAIDeployment                = $Script:LocalConfig.AzureOpenAIDeployment
        AzureOpenAIApiKey                    = $Script:LocalConfig.AzureOpenAIApiKey
        AzureOpenAIApiVersion                = $Script:LocalConfig.AzureOpenAIApiVersion
        ServicenowIncidentsURL               = $Script:LocalConfig.ServicenowIncidentsURL
        ServicenowRequestsURL                = $Script:LocalConfig.ServicenowRequestsURL
        LogicAppSendAIEmailWebHookURL        = $Script:LocalConfig.WebhookUrl
        SaveRawDataLocally                   = $Script:LocalConfig.SaveRawDataLocally
        UseStoredIncidents                   = $Script:LocalConfig.UseStoredIncidents
        StoredDataFileName                   = $Script:LocalConfig.StoredDataFileName
        UseClaudeModel                       = $Script:LocalConfig.UseClaudeModel
        ClaudeEndpoint                       = $Script:LocalConfig.ClaudeEndpoint
        ClaudeDeployment                     = $Script:LocalConfig.ClaudeDeployment
        ClaudeApiKey                         = $Script:LocalConfig.ClaudeApiKey
        ClaudeApiVersion                     = $Script:LocalConfig.ClaudeApiVersion
        DailyLookbackHours                   = $effectiveLookback
        SaveRunArtifacts                     = $Script:LocalConfig.SaveRunArtifacts
        GenerateWeeklyMergedReportOnWeekend  = $Script:LocalConfig.GenerateWeeklyMergedReportOnWeekend
        WeeklyMergeLookbackDays              = $Script:LocalConfig.WeeklyMergeLookbackDays
    }
}

<#
.SYNOPSIS
    ServiceNow Mobile Device Management Incident Categorization System
    
.DESCRIPTION
    Retrieves resolved incidents from ServiceNow, processes them via AI (Azure OpenAI or Anthropic Claude)
    for categorization and summarization, and saves output reports and category stats to Azure Storage/Table.
#>

#region Logging Configuration
$Script:LogConfig = @{
    EnableBlobLogging = $Script:EnableBlobLogging
    LogLevel          = $Script:LogLevel
    LogFilePrefix     = $Script:LogFilePrefix
    LogContainerName  = $Script:LogContainerName
    CurrentLogFile    = $null
    LogBuffer         = [System.Collections.Generic.List[string]]::new()
    StorageContext    = $null
}
#endregion

#region Enhanced Logging Functions

function Initialize-BlobLogging {
    [CmdletBinding()]
    param()
    
    if (-not $Script:LogConfig.EnableBlobLogging) { 
        Write-Host "Blob logging disabled by configuration" -ForegroundColor Yellow
        return 
    }
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $Script:LogConfig.CurrentLogFile = "$($Script:LogConfig.LogFilePrefix)-$timestamp.log"
        Write-Host "Initializing blob logging to: $($Script:LogConfig.CurrentLogFile)" -ForegroundColor Cyan
        
        $azContext = Get-AzContext
        if (-not $azContext) {
            Write-Host "Connecting with Managed Identity..." -ForegroundColor Yellow
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        }

        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $Script:BlobConfig.ResourceGroupName -Name $Script:BlobConfig.StorageAccountName)[0].Value
        $Script:LogConfig.StorageContext = New-AzStorageContext -StorageAccountName $Script:BlobConfig.StorageAccountName -StorageAccountKey $storageKey
        
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
    
    $logLevels = @{ 'Debug' = 0; 'Info' = 1; 'Success' = 1; 'Warning' = 2; 'Error' = 3 }
    $currentLevel = $logLevels[$Script:LogConfig.LogLevel]
    $messageLevel = $logLevels[$Level]
    
    if ($messageLevel -lt $currentLevel) { return }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [$Category] $Message"
    
    $Script:LogConfig.LogBuffer.Add($logEntry)
    
    if ($Script:LogConfig.LogBuffer.Count -gt 50) {
        Write-LogBufferToBlob
    }
}

function Write-LogBufferToBlob {
    [CmdletBinding()]
    param()
    
    if (-not $Script:LogConfig.EnableBlobLogging -or $Script:LogConfig.LogBuffer.Count -eq 0) { return }
    
    try {
        $logContent = $Script:LogConfig.LogBuffer -join "`n"
        $existingBlob = Get-AzStorageBlob -Container $Script:LogConfig.LogContainerName -Blob $Script:LogConfig.CurrentLogFile -Context $Script:LogConfig.StorageContext -ErrorAction SilentlyContinue
        
        if ($existingBlob) {
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Get-AzStorageBlobContent -Container $Script:LogConfig.LogContainerName -Blob $Script:LogConfig.CurrentLogFile -Destination $tempFile -Context $Script:LogConfig.StorageContext -Force | Out-Null
                Add-Content -Path $tempFile -Value "`n$logContent" -Encoding UTF8
                Set-AzStorageBlobContent -File $tempFile -Container $Script:LogConfig.LogContainerName -Blob $Script:LogConfig.CurrentLogFile -Context $Script:LogConfig.StorageContext -Force | Out-Null
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        } else {
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tempFile -Value $logContent -Encoding UTF8
                Set-AzStorageBlobContent -File $tempFile -Container $Script:LogConfig.LogContainerName -Blob $Script:LogConfig.CurrentLogFile -Context $Script:LogConfig.StorageContext | Out-Null
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
        
        $Script:LogConfig.LogBuffer.Clear()
        
    } catch {
        Write-Host "Failed to write logs to blob storage: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Complete-BlobLogging {
    [CmdletBinding()]
    param(
        [string]$FinalMessage = "Execution completed successfully"
    )
    
    if (-not $Script:LogConfig.EnableBlobLogging) { return }
    
    try {
        $Script:LogConfig.LogBuffer.Add("")
        $Script:LogConfig.LogBuffer.Add("=" * 80)
        $Script:LogConfig.LogBuffer.Add("$FinalMessage")
        $Script:LogConfig.LogBuffer.Add("Execution Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $Script:LogConfig.LogBuffer.Add("Total Processed Tickets: $($Script:ProcessedTickets.Count)")
        $Script:LogConfig.LogBuffer.Add("=== End of Log ===")
        
        Write-LogBufferToBlob
        
        Write-Host "✓ Log file saved to blob storage: $($Script:LogConfig.CurrentLogFile)" -ForegroundColor Green
        Write-Host "  Container: $($Script:LogConfig.LogContainerName)" -ForegroundColor Gray
        Write-Host "  Storage Account: $($Script:BlobConfig.StorageAccountName)" -ForegroundColor Gray
        
    } catch {
        Write-Host "Failed to complete blob logging: $($_.Exception.Message)" -ForegroundColor Red
    }
}

#endregion

#region Log Analytics Heartbeat

function Send-LogAnalyticsHeartbeat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Started','Completed','Failed')][string]$Status,
        [int]$ProcessedCount = 0,
        [int]$ErrorCount = 0,
        [string]$Message = ''
    )

    try {
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
        $keyBytes        = [Convert]::FromBase64String($workspaceKey)
        $hmac           = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key       = $keyBytes
        $encodedHash    = [Convert]::ToBase64String($hmac.ComputeHash($bytesToHash))
        $signature      = "SharedKey ${workspaceId}:${encodedHash}"
        $uri            = "https://${workspaceId}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"

        $headers = @{
            'Authorization'        = $signature
            'Log-Type'             = $logType
            'x-ms-date'            = $rfc1123date
            'time-generated-field' = 'timestamp'
        }

        Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null
        Write-Host "Heartbeat sent: $Status" -ForegroundColor Cyan
    } catch {
        Write-Host "Heartbeat failed ($Status): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

#endregion

#region Core Utility Functions

function Get-StorageContext {
    [CmdletBinding()]
    param()
    
    try {
        $azContext = Get-AzContext
        if (-not $azContext) {
            Write-ScriptLog "No Azure context found, connecting with managed identity..." -Level Info
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        }
        
        if ($Script:BlobConfig.SubscriptionId) {
            Set-AzContext -SubscriptionId $Script:BlobConfig.SubscriptionId -ErrorAction Stop | Out-Null
        }
        
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
            $localPath = ".\Templates\$FileName"
            if (Test-Path $localPath) {
                Write-ScriptLog "Loading local template: $localPath" -Level Info
                $content = Get-Content $localPath -Raw -Encoding UTF8
                if ([string]::IsNullOrWhiteSpace($content)) {
                    throw "Local template file is empty: $localPath"
                }
                $retrievedMessage = 'Successfully retrieved ' + $FileName
                $retrievedMessage += ' (' + [string]$content.Length + ' characters)'
                Write-ScriptLog $retrievedMessage -Level Success
                return $content
            } else {
                throw "Local template file not found: $localPath"
            }
        }

        $azContext = Get-AzContext
        if (-not $azContext) {
            Write-ScriptLog "No Azure context found, connecting with managed identity..." -Level Warning
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
            Write-ScriptLog "Successfully authenticated with managed identity" -Level Success
        }

        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $Script:BlobConfig.ResourceGroupName -Name $Script:BlobConfig.StorageAccountName)[0].Value
        $Context = New-AzStorageContext -StorageAccountName $Script:BlobConfig.StorageAccountName -StorageAccountKey $storageKey

        $blob = Get-AzStorageBlob -Container $Script:BlobConfig.PromptContainerName -Blob $FileName -Context $Context -ErrorAction SilentlyContinue
        
        if (-not $blob) {
            Write-ScriptLog "Blob '$FileName' not found in container '$($Script:BlobConfig.PromptContainerName)'" -Level Warning
            throw "Markdown file '$FileName' not found in container '$($Script:BlobConfig.PromptContainerName)'"
        }
        
        $tempFile = [System.IO.Path]::GetTempFileName()
        
        try {
            Get-AzStorageBlobContent -Container $Script:BlobConfig.PromptContainerName -Blob $FileName -Destination $tempFile -Context $Context -Force -ErrorAction Stop | Out-Null
            
            if (-not (Test-Path $tempFile)) {
                throw "Failed to download blob - temporary file not created"
            }
            
            $content = Get-Content -Path $tempFile -Raw -Encoding UTF8
            
            if ([string]::IsNullOrWhiteSpace($content)) {
                throw "Downloaded file is empty or contains only whitespace"
            }
            
            $retrievedMessage = 'Successfully retrieved ' + $FileName
            $retrievedMessage += ' (' + [string]$content.Length + ' characters)'
            Write-ScriptLog $retrievedMessage -Level Success
            return $content
            
        } finally {
            if (Test-Path $tempFile) {
                Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        
    } catch {
        Write-ScriptLog "Failed to get markdown file '$FileName': $($_.Exception.Message)" -Level Error
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
    
    switch ($Level) {
        'Debug'   { Write-Host $logEntry -ForegroundColor DarkGray }
        'Info'    { Write-Host $logEntry -ForegroundColor Cyan }
        'Success' { Write-Host $logEntry -ForegroundColor Green }
        'Warning' { Write-Host $logEntry -ForegroundColor Yellow }
        'Error'   { Write-Host $logEntry -ForegroundColor Red }
    }
    
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
        'Json' { return $Text.Trim() }
        'Plain' { return $Text.Trim() }
    }
}

#endregion

#region Authentication and API Functions

function Get-AIEndpoint {
    [CmdletBinding()]
    param()
    
    if ($Script:Constants.UseClaudeModel) {
        return $Script:Constants.ClaudeEndpoint
    } else {
        return "$($Script:Constants.AzureOpenAIBaseUrl)/openai/deployments/$($Script:Constants.AzureOpenAIDeployment)/chat/completions?api-version=$($Script:Constants.AzureOpenAIApiVersion)"
    }
}

function Get-AzureOpenAIEndpoint {
    [CmdletBinding()]
    param()
    return Get-AIEndpoint
}

function Get-AccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TokenUrl,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [string]$Scope
    )
    
    try {
        Write-ScriptLog "Requesting OAuth token for API authentication" -Level Info
        
        $authBody = @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
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
        [Parameter(Mandatory)][string]$Url,
        [string]$AccessToken,
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')][string]$Method = 'GET',
        [object]$RequestBody,
        [int]$TimeoutSeconds = 300,
        [string]$ApiKey,
        [switch]$IsClaudeApi
    )
    
    try {
        if ($ApiKey) {
            if ($IsClaudeApi -or $Script:Constants.UseClaudeModel) {
                $headers = @{
                    "x-api-key"         = $ApiKey
                    "anthropic-version" = $Script:Constants.ClaudeApiVersion
                }
            } else {
                $headers = @{ "api-key" = $ApiKey }
            }
        } else {
            $headers = @{ Authorization = "Bearer $AccessToken" }
        }
        
        $requestParams = @{
            Method      = $Method
            Uri         = $Url
            Headers     = $headers
            TimeoutSec  = $TimeoutSeconds
            ErrorAction = 'Stop'
            ContentType = 'application/json; charset=utf-8'
        }
        
        if ($RequestBody -and $Method -in @('POST', 'PUT')) {
            $requestBodyJson = if ($RequestBody -is [string]) { $RequestBody } else { $RequestBody | ConvertTo-Json -Depth 10 -Compress }
            $requestParams.Body = [System.Text.Encoding]::UTF8.GetBytes($requestBodyJson)
        }
        
        $response = Invoke-RestMethod @requestParams
        Write-ScriptLog "$Method API request completed successfully" -Level Success
        
        return $response
        
    } catch {
        Write-ScriptLog "API Call Error: $($_.Exception.Message)" -Level Error
        
        if ($_.Exception.Response) {
            try {
                $statusCode = [int]$_.Exception.Response.StatusCode
                $statusDescription = $_.Exception.Response.StatusDescription
                Write-ScriptLog "HTTP Status: $statusCode - $statusDescription" -Level Error
                
                $responseStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($responseStream)
                $responseBody = $reader.ReadToEnd()
                $reader.Close()
                $responseStream.Close()
                
                Write-ScriptLog "API Error Response: $responseBody" -Level Error
            } catch {
                Write-ScriptLog "Could not read error response: $($_.Exception.Message)" -Level Warning
            }
        }
        
        throw
    }
}

#endregion

#region AI Processing Functions

function New-AiRequestBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SystemPrompt,
        [Parameter(Mandatory)][string]$UserContent,
        [ValidateSet('Cleanup', 'Summary', 'Category')][string]$TaskType = 'Summary'
    )
    
    if ($Script:Constants.UseClaudeModel) {
        return @{
            model       = $Script:Constants.ClaudeDeployment
            max_tokens  = $Script:Config.AI.MaxTokens
            temperature = $Script:Config.AI.Temperature.$TaskType
            system      = $SystemPrompt
            messages    = @( @{ role = "user"; content = $UserContent } )
        }
    } else {
        return @{
            messages = @(
                @{ role = "system"; content = $SystemPrompt },
                @{ role = "user";   content = $UserContent }
            )
            model                 = $Script:Constants.AzureOpenAIDeployment
            temperature           = $Script:Config.AI.Temperature.$TaskType
            max_completion_tokens = $Script:Config.AI.MaxTokens
            top_p                 = $Script:Config.AI.TopP
            frequency_penalty     = $Script:Config.AI.FrequencyPenalty
            presence_penalty      = $Script:Config.AI.PresencePenalty
            stop                  = $null
        }
    }
}

function Get-CleanedWorkNotes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Incident)
    
    $workNotesData = @{
        work_notes  = $Incident.work_notes
        close_notes = $Incident.close_notes
    }
    $workNotesJson = $workNotesData | ConvertTo-Json -Depth 5 -Compress
    $requestBody = New-AiRequestBody -SystemPrompt $Script:PromptTemplates.WorkNotesCleanup -UserContent $workNotesJson -TaskType 'Cleanup'
    
    $apiKey = if ($Script:Constants.UseClaudeModel) { $Script:Constants.ClaudeApiKey } else { $Script:Constants.AzureOpenAIApiKey }
    $aiResponse = Invoke-AuthenticatedApiCall -Url (Get-AIEndpoint) -Method POST -RequestBody $requestBody -ApiKey $apiKey -IsClaudeApi:$Script:Constants.UseClaudeModel
    
    $cleanedNotes = if ($Script:Constants.UseClaudeModel) {
        $aiResponse.content[0].text | Invoke-TextCleanup -ProcessingType Markdown
    } else {
        $aiResponse.choices[0].message.content | Invoke-TextCleanup -ProcessingType Markdown
    }
    
    $truncatedNotes = if ($cleanedNotes.Length -gt 500) { $cleanedNotes.Substring(0, 500) + "..." } else { $cleanedNotes }
    Write-ScriptLog "Cleaned work notes for $($Incident.number): $truncatedNotes" -Level Info -Category "WorkNotes"
    
    return $cleanedNotes
}

function Get-IncidentSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CleanedNotes,
        [Parameter(Mandatory)][string]$IncidentNumber
    )
    
    $systemPrompt = $Script:PromptTemplates.WorkNotesSummary + "`n`n" + $Script:PromptTemplates.IntuneEnvironmentContext
    $requestBody = New-AiRequestBody -SystemPrompt $systemPrompt -UserContent $CleanedNotes -TaskType 'Summary'
    
    $apiKey = if ($Script:Constants.UseClaudeModel) { $Script:Constants.ClaudeApiKey } else { $Script:Constants.AzureOpenAIApiKey }
    $aiResponse = Invoke-AuthenticatedApiCall -Url (Get-AIEndpoint) -Method POST -RequestBody $requestBody -ApiKey $apiKey -IsClaudeApi:$Script:Constants.UseClaudeModel
    
    $summary = if ($Script:Constants.UseClaudeModel) {
        $aiResponse.content[0].text | Invoke-TextCleanup -ProcessingType Markdown
    } else {
        $aiResponse.choices[0].message.content | Invoke-TextCleanup -ProcessingType Markdown
    }
    
    Write-ScriptLog "Generated summary for ${IncidentNumber}: $summary" -Level Info -Category "AISummary"
    
    return $summary
}

function Get-IncidentCategory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$IncidentData)
    
    try {
$additionalPrompt = 'Require exact Possible Root Cause and Detailed Root Cause labels, and write Reasoning as 3-5 sentences of plain-language incident narrative with no field labels or bullets.'

        $systemPrompt = $Script:PromptTemplates.TicketCategorisation + "`n`n" +
                $Script:PromptTemplates.EnvironmentContext + "`n`n" +
                "## REFERENCE: Subcategory (Sub-Symptom) Labels`n" +
                $Script:PromptTemplates.TrendSubCategorisation + "`n`n" +
                "## REFERENCE: Possible Root Cause Labels`n" +
                $Script:PromptTemplates.PossibleRootCause + "`n`n" +
                "## REFERENCE: Detailed Root Cause Entries`n" +
                $Script:PromptTemplates.DetailedRootCause + "`n`n" +
                $additionalPrompt
        
        $incidentJson = $IncidentData | ConvertTo-Json -Depth 4 -Compress
        
        try {
            $null = $incidentJson | ConvertFrom-Json
        } catch {
            Write-ScriptLog "WARNING: Incident JSON validation failed: $($_.Exception.Message)" -Level Warning -Category "Categorization"
            throw "Invalid JSON generated from incident data"
        }
        
        $requestBody = New-AiRequestBody -SystemPrompt $systemPrompt -UserContent $incidentJson -TaskType 'Category'
        
        $apiKey = if ($Script:Constants.UseClaudeModel) { $Script:Constants.ClaudeApiKey } else { $Script:Constants.AzureOpenAIApiKey }
        $aiResponse = Invoke-AuthenticatedApiCall -Url (Get-AIEndpoint) -Method POST -RequestBody $requestBody -ApiKey $apiKey -IsClaudeApi:$Script:Constants.UseClaudeModel
        
        $responseText = if ($Script:Constants.UseClaudeModel) {
            $aiResponse.content[0].text
        } else {
            $aiResponse.choices[0].message.content
        }
        
        $categoryInfo = ConvertFrom-AiCategoryResponse -ResponseText $responseText
        
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
    
    $patterns = @{
        'primary_category'     = "(?s)\*{0,2}Primary Category:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Exclusion|\n\*{0,2}Sub-symptom|\n\*{0,2}Confidence|\n\*{0,2}Issue|\n\*{0,2}Root Cause Narrative|\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'exclusion_reason'     = "(?s)\*{0,2}Exclusion Reason:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Sub-symptom|\n\*{0,2}Confidence|\n\*{0,2}Issue|\n\*{0,2}Root Cause Narrative|\n\*{0,2}Reasoning|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'sub_symptom'          = "(?s)\*{0,2}Sub-symptom:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Confidence|\n\*{0,2}Issue|\n\*{0,2}Root Cause Narrative|\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'confidence_level'     = "(?s)\*{0,2}Confidence Level:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Issue|\n\*{0,2}Root Cause Narrative|\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\n\*{0,2}Resolution|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'issue'                = "(?s)\*{0,2}Issue:\*{0,2}\s*(.+?)(?=\n\*{0,2}Root Cause Narrative|\n\*{0,2}Confidence|\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\n\*{0,2}Resolution|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
        'root_cause_narrative' = "(?s)\*{0,2}Root Cause Narrative:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Confidence|\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\n\*{0,2}Resolution|\n\*{0,2}Possible Root|\n\*{0,2}Detailed Root|\Z)"
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
            $value = $value -replace '\*{2,}$', ''
            $result[$key] = $value.Trim()
        }
    }
    
    return [PSCustomObject]$result
}

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

        $askPrc = if ($NeedPrc -and $PrcAllowlist -and $PrcAllowlist.Count -gt 0) { "`nValid possible root cause labels for Category '$Category':`n$prcLines" } else { '' }

        $askDrc = if ($NeedDrc -and $DrcAllowlist -and $DrcAllowlist.Count -gt 0) { "`nValid detailed root cause headings for Category '$Category':`n$drcLines" } else { '' }

        $systemPrompt = 'You are a strict classification mapper. Pick the single best matching label from each provided list. Copy labels exactly as written. Return Unknown only if nothing reasonably matches.' +
            "`nCategory: $Category`nSubcategory: $Subcategory" + $askPrc + $askDrc +
            "`nRespond in exactly this format:`nPossibleRootCause: one label copied verbatim from the PRC list`nDetailedRootCause: one heading copied verbatim from the DRC list"

        $cleanWorkNotes = ($WorkNotes -replace '\s+', ' ')
        if ($cleanWorkNotes.Length -gt 2000) { $cleanWorkNotes = $cleanWorkNotes.Substring(0, 2000) }
        $userContent = "Short Description: $ShortDescription`n`nAnalyst Summary: $AnalystSummary`n`nCleaned Work Notes (truncated):`n$cleanWorkNotes"

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
    param([Parameter(Mandatory)][array]$Incidents)
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $fileName = "incidents_$timestamp.json"
        $jsonContent = $Incidents | ConvertTo-Json -Depth 10 -Compress
        
        if ($Script:IsAzureAutomation) {
            Write-ScriptLog "Saving incident data to blob storage..." -Level Info
            $storageContext = Get-StorageContext
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tempFile -Value $jsonContent -Encoding UTF8
                Set-AzStorageBlobContent -File $tempFile -Container $Script:BlobConfig.DataContainerName -Blob $fileName -Context $storageContext -Force | Out-Null
                Write-ScriptLog "Raw incident data saved to blob: $fileName" -Level Success
                return $fileName
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        } else {
            $dataDir = ".\data"
            if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
            $filePath = Join-Path $dataDir $fileName
            Set-Content -Path $filePath -Value $jsonContent -Encoding UTF8
            Write-ScriptLog "Raw incident data saved locally: $filePath" -Level Success
            return $filePath
        }
    } catch {
        Write-ScriptLog "Failed to save incident data: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-StoredIncidents {
    [CmdletBinding()]
    param([string]$FileName = $null)
    
    try {
        if ($Script:IsAzureAutomation) {
            Write-ScriptLog "Loading stored incident data from blob storage..." -Level Info
            $storageContext = Get-StorageContext
            
            if ($FileName) {
                $blobName = $FileName
            } else {
                $blobs = Get-AzStorageBlob -Container $Script:BlobConfig.DataContainerName -Context $storageContext -Prefix "incidents_" | Sort-Object LastModified -Descending
                if ($blobs.Count -eq 0) { throw "No incident files found in blob container: $($Script:BlobConfig.DataContainerName)" }
                $blobName = $blobs[0].Name
            }
            
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Get-AzStorageBlobContent -Container $Script:BlobConfig.DataContainerName -Blob $blobName -Destination $tempFile -Context $storageContext -Force | Out-Null
                $jsonContent = Get-Content -Path $tempFile -Raw -Encoding UTF8
                $incidents = $jsonContent | ConvertFrom-Json
                Write-ScriptLog "Successfully loaded $($incidents.Count) incidents from blob: $blobName" -Level Success
                return $incidents
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        } else {
            $dataDir = ".\data"
            if (-not (Test-Path $dataDir)) { throw "Data directory does not exist: $dataDir" }
            
            if ($FileName) {
                $filePath = Join-Path $dataDir $FileName
                if (-not (Test-Path $filePath)) { throw "Specified incident file not found: $filePath" }
            } else {
                $incidentFiles = Get-ChildItem -Path $dataDir -Filter "incidents_*.json" | Sort-Object LastWriteTime -Descending
                if ($incidentFiles.Count -eq 0) { throw "No incident files found in $dataDir" }
                $filePath = $incidentFiles[0].FullName
            }
            
            $jsonContent = Get-Content -Path $filePath -Raw -Encoding UTF8
            $incidents = $jsonContent | ConvertFrom-Json
            Write-ScriptLog "Successfully loaded $($incidents.Count) incidents from: $filePath" -Level Success
            return $incidents
        }
    } catch {
        Write-ScriptLog "Failed to load stored incident data: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-AvailableIncidentFiles {
    [CmdletBinding()]
    param()
    
    try {
        if ($Script:IsAzureAutomation) {
            $storageContext = Get-StorageContext
            $blobs = Get-AzStorageBlob -Container $Script:BlobConfig.DataContainerName -Context $storageContext -Prefix "incidents_" -ErrorAction SilentlyContinue | Sort-Object LastModified -Descending
            return $blobs
        } else {
            $dataDir = ".\data"
            if (Test-Path $dataDir) {
                return Get-ChildItem -Path $dataDir -Filter "incidents_*.json" | Sort-Object LastWriteTime -Descending
            }
            return @()
        }
    } catch {
        Write-ScriptLog "Failed to list incident files: $($_.Exception.Message)" -Level Warning
        return @()
    }
}

function Save-RunProcessingArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$DetailedSummaries,
        [string]$ReportPeriod,
        [string]$DataSource = "Live API"
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $fileName = "run_artifact_$timestamp.json"

        $artifactWeekNumber = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
            (Get-Date),
            [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
            [System.DayOfWeek]::Monday
        )
        $artifactYear = (Get-Date).Year
        $artifactYearWeek = "{0:D4}-W{1:D2}" -f $artifactYear, $artifactWeekNumber

        $artifact = [PSCustomObject]@{
            RunGeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
            YearWeek          = $artifactYearWeek
            ReportPeriod      = $ReportPeriod
            DataSource        = $DataSource
            ProcessedTickets  = @($Script:ProcessedTickets)
            DetailedSummaries = @($DetailedSummaries)
        }

        $jsonContent = $artifact | ConvertTo-Json -Depth 15 -Compress

        if ($Script:IsAzureAutomation) {
            $storageContext = Get-StorageContext
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tempFile -Value $jsonContent -Encoding UTF8
                Set-AzStorageBlobContent -File $tempFile -Container $Script:BlobConfig.DataContainerName -Blob $fileName -Context $storageContext -Force | Out-Null
                Write-ScriptLog "Run artifact saved to blob: $fileName" -Level Success
                return $fileName
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        } else {
            $artifactDir = ".\data"
            if (-not (Test-Path $artifactDir)) { New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null }
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
    param([int]$LookbackDays = 7)

    try {
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
            $blobs = Get-AzStorageBlob -Container $Script:BlobConfig.DataContainerName -Context $storageContext -Prefix "run_artifact_" -ErrorAction SilentlyContinue | Sort-Object LastModified

            foreach ($blob in $blobs) {
                if ($blob.LastModified.UtcDateTime -lt $cutoffUtc) { continue }

                $tempFile = [System.IO.Path]::GetTempFileName()
                try {
                    Get-AzStorageBlobContent -Container $Script:BlobConfig.DataContainerName -Blob $blob.Name -Destination $tempFile -Context $storageContext -Force | Out-Null
                    $artifact = (Get-Content -Path $tempFile -Raw -Encoding UTF8) | ConvertFrom-Json
                    
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
                    
                    if ($artifactYearWeek -and $artifactYearWeek -ne $currentYearWeek) {
                        continue
                    }
                    
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
                    
                    if ($artifactYearWeek -and $artifactYearWeek -ne $currentYearWeek) {
                        continue
                    }
                    
                    $artifacts += $artifact
                }
            }
        }

        if ($artifacts.Count -eq 0) {
            return [PSCustomObject]@{
                ProcessedTickets  = [System.Collections.Generic.List[TicketAnalysis]]::new()
                DetailedSummaries = @()
            }
        }

        $ticketMap = @{}
        $summaryMap = @{}

        foreach ($artifact in $artifacts) {
            foreach ($ticket in @($artifact.ProcessedTickets)) {
                if (-not $ticket.Number) { continue }

                $converted = [TicketAnalysis]::new([string]$ticket.Number)
                $converted.Category            = [string]$ticket.Category
                $converted.SubSymptom          = [string]$ticket.SubSymptom
                $converted.Subcategory        = [string]$ticket.Subcategory
                $converted.PossibleRootCause  = [string]$ticket.PossibleRootCause
                $converted.DetailedRootCause  = [string]$ticket.DetailedRootCause
                $converted.Service            = if ([string]::IsNullOrWhiteSpace([string]$ticket.Service)) { 'Productivity Tools' } else { [string]$ticket.Service }
                $converted.Misrouted          = [bool]($converted.Category -eq 'Excluded')
                $converted.ExclusionReason    = [string]$ticket.ExclusionReason
                $converted.Confidence         = [string]$ticket.Confidence
                $converted.Issue              = [string]$ticket.Issue
                $converted.RootCauseNarrative = [string]$ticket.RootCauseNarrative
                $converted.Reasoning          = [string]$ticket.Reasoning
                $converted.Evidence           = [string]$ticket.Evidence
                $converted.Resolution         = [string]$ticket.Resolution
                $converted.Type               = [string]$ticket.Type
                $converted.KnowledgeBase       = [string]$ticket.KnowledgeBase
                $converted.OriginalDescription= [string]$ticket.OriginalDescription
                $converted.ResolvedAt         = [string]$ticket.ResolvedAt

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
                    IncidentNumber  = [string]$summary.IncidentNumber
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
            ProcessedTickets  = $mergedTickets
            DetailedSummaries = $mergedSummaries
            YearWeek          = $currentYearWeek
        }
    } catch {
        Write-ScriptLog "Failed to merge weekly run artifacts: $($_.Exception.Message)" -Level Warning
        return [PSCustomObject]@{
            ProcessedTickets  = [System.Collections.Generic.List[TicketAnalysis]]::new()
            DetailedSummaries = @()
            YearWeek          = $null
        }
    }
}

function Filter-IncidentsByResolvedWindow {
    [CmdletBinding()]
    param(
        [array]$Incidents = @(),
        [int]$LookbackHours = 26
    )

    if ($LookbackHours -le 0) { return $Incidents }

    $cutoff = (Get-Date).AddHours(-1 * $LookbackHours)
    $filtered = [System.Collections.Generic.List[object]]::new()

    foreach ($incident in $Incidents) {
        [DateTime]$resolvedAt = [DateTime]::MinValue
        if ([DateTime]::TryParse([string]$incident.resolved_at, [ref]$resolvedAt)) {
            if ($resolvedAt -ge $cutoff) {
                $filtered.Add($incident)
            }
        } else {
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
    param([Parameter(Mandatory)][object]$Incident)
    
    $ticketType = if ($Incident.number.StartsWith("INC")) { "Incident" } elseif ($Incident.number.StartsWith("SCTASK")) { "Service Request" } else { "Unknown" }
    
    Write-ScriptLog "Processing $ticketType $($Incident.number): $($Incident.short_description)" -Level Info -Category "TicketData"
    
    try {
        $cleanedNotes = Get-CleanedWorkNotes -Incident $Incident
        $summary = Get-IncidentSummary -CleanedNotes $cleanedNotes -IncidentNumber $Incident.number
        $incidentData = [PSCustomObject]@{
            IncidentNumber           = $Incident.number
            "User Description"        = $Incident.description
            "User Short Description"  = $Incident.short_description
            "User Work Notes"        = $cleanedNotes
            "Incident Duration"      = $Incident.calendar_duration
            "Incident Close Code"     = $Incident.close_code
            "Incident Opened At"     = $Incident.opened_at
            "Incident Resolved At"   = $Incident.resolved_at
            "AI Summary"             = $summary
        }
        $categoryInfo = Get-IncidentCategory -IncidentData $incidentData
        
        $ticket = [TicketAnalysis]::new($Incident.number)
        
        $rawCategory = $categoryInfo.primary_category
        if ($rawCategory -and $rawCategory.Length -gt 100) {
            $rawCategory = ($rawCategory -split "`n")[0].Trim()
        }
        $rawCategory = $rawCategory -replace '\*+', ''
        $rawCategory = Get-CanonicalAlias -Field 'Category' -Product '' -Raw $rawCategory
        
        $canonicalCategory = Get-CanonicalLabel -Raw $rawCategory -Allowlist $Script:CanonicalLabels.Categories -Fallback 'Other / Miscellaneous'
        $ticket.Category = $canonicalCategory

        $rawSubSymptom = [string]$categoryInfo.sub_symptom
        if ($rawSubSymptom) {
            $rawSubSymptom = ($rawSubSymptom -split "`n")[0].Trim()
            $rawSubSymptom = $rawSubSymptom -replace '\*+', ''
        }
        $rawSubSymptom = Get-CanonicalAlias -Field 'Subcategory' -Product $canonicalCategory -Raw $rawSubSymptom
        $ticket.SubSymptom = $rawSubSymptom

        $subAllowlist = Get-AllowlistForProduct -Map $Script:CanonicalLabels.Subcategories -Product $canonicalCategory
        $ticket.Subcategory = Get-CanonicalLabel -Raw $rawSubSymptom -Allowlist $subAllowlist -Fallback ''
        if ([string]::IsNullOrWhiteSpace($ticket.Subcategory)) {
            $ticket.Subcategory = Get-CanonicalFallbackLabel -Field Subcategory -Product $canonicalCategory -Allowlist $subAllowlist
        }

        $prcAllowlist = Get-AllowlistForProduct -Map $Script:CanonicalLabels.PossibleRootCauses -Product $canonicalCategory
        $rawPrc = Get-CanonicalAlias -Field 'PossibleRootCause' -Product $canonicalCategory -Raw ([string]$categoryInfo.possible_root_cause)
        $ticket.PossibleRootCause = Get-CanonicalLabel -Raw $rawPrc -Allowlist $prcAllowlist -Fallback ''
        if ([string]::IsNullOrWhiteSpace($ticket.PossibleRootCause)) {
            $ticket.PossibleRootCause = Get-CanonicalFallbackLabel -Field PossibleRootCause -Product $canonicalCategory -Allowlist $prcAllowlist
        }

        $drcAllowlist = Get-AllowlistForProduct -Map $Script:CanonicalLabels.DetailedRootCauses -Product $canonicalCategory
        $rawDrc = Get-CanonicalAlias -Field 'DetailedRootCause' -Product $canonicalCategory -Raw ([string]$categoryInfo.detailed_root_cause)
        $ticket.DetailedRootCause = Get-CanonicalLabel -Raw $rawDrc -Allowlist $drcAllowlist -Fallback ''
        if ([string]::IsNullOrWhiteSpace($ticket.DetailedRootCause)) {
            $ticket.DetailedRootCause = Get-CanonicalFallbackLabel -Field DetailedRootCause -Product $canonicalCategory -Allowlist $drcAllowlist
        }

        $needPrcRescue = ([string]::IsNullOrWhiteSpace($ticket.PossibleRootCause) -and $prcAllowlist -and $prcAllowlist.Count -gt 0)
        $needDrcRescue = ([string]::IsNullOrWhiteSpace($ticket.DetailedRootCause) -and $drcAllowlist -and $drcAllowlist.Count -gt 0)
        if ($Script:Config.Rescue.Enabled -and ($needPrcRescue -or $needDrcRescue)) {
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
                    $ticket.PossibleRootCause = $coerced
                } else {
                    $ticket.PossibleRootCause = Get-CanonicalFallbackLabel -Field PossibleRootCause -Product $canonicalCategory -Allowlist $prcAllowlist
                }
            }
            if ($needDrcRescue -and $rescue.DetailedRootCause) {
                $coerced = Get-CanonicalLabel -Raw $rescue.DetailedRootCause -Allowlist $drcAllowlist -Fallback ''
                if (-not [string]::IsNullOrWhiteSpace($coerced)) {
                    $ticket.DetailedRootCause = $coerced
                } else {
                    $ticket.DetailedRootCause = Get-CanonicalFallbackLabel -Field DetailedRootCause -Product $canonicalCategory -Allowlist $drcAllowlist
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($ticket.PossibleRootCause)) {
            $ticket.PossibleRootCause = Get-CanonicalFallbackLabel -Field PossibleRootCause -Product $canonicalCategory -Allowlist $prcAllowlist
        }
        if ([string]::IsNullOrWhiteSpace($ticket.DetailedRootCause)) {
            $ticket.DetailedRootCause = Get-CanonicalFallbackLabel -Field DetailedRootCause -Product $canonicalCategory -Allowlist $drcAllowlist
        }

        $ticket.Service   = 'Productivity Tools'
        $ticket.Misrouted = ($ticket.Category -eq 'Excluded')
        $ticket.ExclusionReason = $categoryInfo.exclusion_reason

        $rootCausesKnown = (-not [string]::IsNullOrWhiteSpace($ticket.PossibleRootCause) -and -not [string]::IsNullOrWhiteSpace($ticket.DetailedRootCause))
        $ticket.Confidence = Get-NormalizedConfidence -Raw ([string]$categoryInfo.confidence_level) -RootCausesKnown $rootCausesKnown

        if ([string]::IsNullOrWhiteSpace([string]$categoryInfo.issue)) {
            $ticket.Issue = [string]$Incident.short_description
        } else {
            $ticket.Issue = [string]$categoryInfo.issue
        }

        if ([string]::IsNullOrWhiteSpace([string]$categoryInfo.root_cause_narrative)) {
            $ticket.RootCauseNarrative = if (-not [string]::IsNullOrWhiteSpace($ticket.PossibleRootCause)) {
                "Root cause not documented beyond the catalog classification of $($ticket.PossibleRootCause)."
            } else {
                'Root cause not documented in the available work notes.'
            }
        } else {
            $ticket.RootCauseNarrative = [string]$categoryInfo.root_cause_narrative
        }

        if ([string]::IsNullOrWhiteSpace([string]$categoryInfo.reasoning)) {
            $ticket.Reasoning = $null
        } else {
            $ticket.Reasoning = [string]$categoryInfo.reasoning
        }

        if (Test-ReasoningNeedsReanalysis -Text ([string]$ticket.Reasoning)) {
            $reanalysis = Invoke-ReasoningReanalysis -Ticket $ticket -CategoryInfo $categoryInfo
            if (-not [string]::IsNullOrWhiteSpace($reanalysis)) {
                $ticket.Reasoning = $reanalysis
            }
        }

        if (Test-ReasoningNeedsReanalysis -Text ([string]$ticket.Reasoning)) {
            $ticket.Reasoning = Get-StructuredReasoningNarrative -Ticket $ticket -CategoryInfo $categoryInfo
        }
        
        $ticket.Evidence            = $categoryInfo.key_evidence
        $ticket.Resolution          = $categoryInfo.resolution_summary
        $ticket.Type                = $categoryInfo.how_do_i_or_error
        $ticket.KnowledgeBase       = $categoryInfo.kb_provided
        $ticket.OriginalDescription = $Incident.short_description
        $ticket.ResolvedAt          = [string]$Incident.resolved_at
        
        $null = Ensure-TicketAiFields -Ticket $ticket -CategoryInfo $categoryInfo
        $Script:ProcessedTickets.Add($ticket)
        
        Write-ScriptLog "Successfully processed $ticketType $($Incident.number) - Category: $($ticket.Category)" -Level Success -Category "Processing"
        
        return [PSCustomObject]@{
            IncidentNumber  = $Incident.number
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
        [Parameter(Mandatory)][object]$Incident,
        [string]$FailureReason = ''
    )

    $ticket = [TicketAnalysis]::new([string]$Incident.number)
    
    $ticket.Category          = 'Other / Miscellaneous'
    $ticket.SubSymptom         = 'Unclassified'
    $ticket.Subcategory        = 'Unclassified'
    $ticket.PossibleRootCause  = 'Usage Guidance (How Do I)'
    $ticket.DetailedRootCause  = 'Automated fallback classification'
    $ticket.Service            = 'Productivity Tools'
    $ticket.Misrouted          = $false
    $ticket.ExclusionReason    = ''
    $ticket.Confidence         = 'Low'

    $short = ([string]$Incident.short_description).Trim()
    if ([string]::IsNullOrWhiteSpace($short)) { $short = ([string]$Incident.description).Trim() }
    if ([string]::IsNullOrWhiteSpace($short)) { $short = 'No incident summary available from source payload.' }

    $failureNote = if ([string]::IsNullOrWhiteSpace($FailureReason)) { 'the AI categorization call did not return a usable response' } else { $FailureReason }
    
    $ticket.Reasoning = "The user reached out because '$short'. During analysis, the runbook could not complete the normal AI categorization flow because $failureNote. The engineer-side automation therefore applied a safe fallback categorization so reporting could continue without dropping this incident from weekly trends. Available notes do not provide enough verified evidence to describe a precise root-cause chain for this ticket. User-response confirmation is not explicitly captured in the fallback path, so a manual follow-up review is recommended before relying on this entry for deep root-cause conclusions."
    $ticket.Evidence = 'AI categorization did not complete successfully'
    $ticket.Resolution = 'Manual review recommended for proper categorization'
    $ticket.Type = 'Not Determined'
    $ticket.KnowledgeBase = ''
    $ticket.OriginalDescription = [string]$Incident.short_description
    $ticket.ResolvedAt = [string]$Incident.resolved_at

    $null = Ensure-TicketAiFields -Ticket $ticket
    
    return $ticket
}

function Get-CategoryStatistics {
    [CmdletBinding()]
    param()
    
    if ($Script:ProcessedTickets.Count -eq 0) {
        Write-ScriptLog "No processed tickets found - returning empty category statistics" -Level Warning
        return @()
    }
    
    $ticketsWithDisplayCategory = $Script:ProcessedTickets | ForEach-Object {
        [PSCustomObject]@{
            Number          = $_.Number
            DisplayCategory = $_.Category
        }
    }
    
    $statistics = $ticketsWithDisplayCategory | 
                  Group-Object -Property DisplayCategory | 
                  Select-Object Name, Count, @{Name='Tickets'; Expression={$_.Group.Number}} |
                  Sort-Object Count -Descending
    
    if ($null -eq $statistics) { return @() }
    
    return $statistics
}

#endregion

#region Azure Table Storage Functions for Statistics

function Initialize-StatisticsTable {
    [CmdletBinding()]
    param()
    
    try {
        $storageContext = Get-StorageContext
        $tableName = $Script:BlobConfig.StatisticsTableName
        
        $table = Get-AzStorageTable -Name $tableName -Context $storageContext -ErrorAction SilentlyContinue
        
        if (-not $table) {
            Write-ScriptLog "ERROR: Statistics table '$tableName' does not exist!" -Level Error
            return $null
        }
        
        return $table.CloudTable
        
    } catch {
        Write-ScriptLog "Failed to access statistics table: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Save-CategoryStatisticsToTable {
    [CmdletBinding()]
    param(
        [array]$CategoryData = @(),
        [DateTime]$ReportDate = (Get-Date),
        [string]$ReportBlobName = ""
    )
    
    if (-not $Script:IsAzureAutomation) {
        Write-ScriptLog "Skipping Azure Table storage in local environment" -Level Info
        return
    }
    
    if ($Script:ProcessedTickets.Count -eq 0) {
        Write-ScriptLog "No processed tickets to save to table" -Level Warning
        return
    }
    
    try {
        $cloudTable = Initialize-StatisticsTable
        if (-not $cloudTable) { return }
        
        $fallbackDateString = $ReportDate.ToString("yyyy-MM-dd")
        $fallbackYear = $ReportDate.Year
        $fallbackWeekNumber = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
            $ReportDate, 
            [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, 
            [System.DayOfWeek]::Monday
        )
        $fallbackYearWeek = "{0:D4}-W{1:D2}" -f $fallbackYear, $fallbackWeekNumber
        
        $savedCount = 0
        $errorCount = 0
        
        foreach ($ticket in $Script:ProcessedTickets) {
            try {
                $null = Ensure-TicketAiFields -Ticket $ticket

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
                
                $entityProperties = @{
                    "Category"          = [string]$ticket.Category
                    "Subcategory"       = [string]$ticket.Subcategory
                    "PossibleRootCause" = [string]$ticket.PossibleRootCause
                    "RootCause"         = [string]$ticket.PossibleRootCause
                    "DetailedRootCause" = [string]$ticket.DetailedRootCause
                    "TopRootCause"      = [string]$ticket.PossibleRootCause
                    "Service"           = [string]$ticket.Service
                    "Misrouted"         = [bool]$ticket.Misrouted
                    "Date"              = [string]$dateString
                    "YearWeek"          = [string]$yearWeekString
                    "Year"              = [int]$year
                    "WeekNumber"        = [int]$weekNumber
                    "ReportBlobName"    = [string]$ReportBlobName
                    "AnalysisStatus"    = [string]$ticket.AnalysisStatus
                    "AIAnalysis"        = $(
                        $structuredAnalysis = Format-StructuredAiAnalysis -Ticket $ticket
                        if ($structuredAnalysis.Length -gt 4000) { $structuredAnalysis.Substring(0, 4000) + '...' } else { $structuredAnalysis }
                    )
                    "Confidence"        = [string]$ticket.Confidence
                }
                
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
        
        Write-ScriptLog "Successfully saved $savedCount incident records to Azure Table" -Level Success
        if ($errorCount -gt 0 -or $savedCount -ne $Script:ProcessedTickets.Count) {
            throw "Statistics table save incomplete: saved $savedCount of $($Script:ProcessedTickets.Count) processed tickets with $errorCount table write errors."
        }
        
    } catch {
        Write-ScriptLog "Failed to save statistics to Azure Table: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-StatisticsRestApiInfo {
    [CmdletBinding()]
    param()
    
    $storageAccount = $Script:BlobConfig.StorageAccountName
    $tableName = $Script:BlobConfig.StatisticsTableName
    $tableUrl = 'https://' + $storageAccount + '.table.core.windows.net/' + $tableName
    
    return @{
        BaseUrl = $tableUrl
        SampleQueries = @{
            "AllIncidents" = $tableUrl + '()'
            "ByWeek"       = $tableUrl + '()?`$filter=PartitionKey%20eq%20''2026-W06'''
            "ByCategory"   = $tableUrl + '()?`$filter=Category%20eq%20''Hardware%20Issues'''
        }
    }
}

#endregion

#region Report Generation Functions

function New-HtmlTicketReport {
    [CmdletBinding()]
    param(
        [array]$CategoryData = @(),
        [array]$DetailedSummaries = @()
    )
    
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
    
    return $htmlTemplate
}

function New-CategoryTableHtml {
    [CmdletBinding()]
    param([array]$CategoryData)
    
    $tableRows = foreach ($category in $CategoryData) {
        $ticketArray = if ($category.Tickets -is [array]) { $category.Tickets } else { @($category.Tickets) }
        $ticketLinks = ($ticketArray | ForEach-Object {
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
        [ValidateSet('Incident', 'ServiceRequest')][string]$TicketType = 'Incident',
        [array]$ProcessedTicketsData = @()
    )
    
    if ($DetailedSummaries.Count -eq 0) { return "" }
    
    $filteredSummaries = $DetailedSummaries | Where-Object { 
        if ($TicketType -eq 'Incident') {
            $_.IncidentNumber.StartsWith("INC")
        } else {
            $_.IncidentNumber.StartsWith("SCTASK")
        }
    }
    
    if ($filteredSummaries.Count -eq 0) { return "" }
    
    $detailRows = foreach ($summary in $filteredSummaries) {
        $category = if ($CategoryLookup.ContainsKey($summary.IncidentNumber) -and -not [string]::IsNullOrWhiteSpace([string]$CategoryLookup[$summary.IncidentNumber])) { $CategoryLookup[$summary.IncidentNumber] } else { 'Unknown' }
        $ticketRecord = if ($ProcessedTicketsData.Count -gt 0) {
            $ProcessedTicketsData | Where-Object { $_.Number -eq $summary.IncidentNumber } | Select-Object -First 1
        } else { $null }

        if ($category -eq 'Excluded' -and $ticketRecord -and $ticketRecord.ExclusionReason) {
            $category = "Excluded<br><span style='font-weight:normal;font-size:11px;color:#6c757d;'>$($ticketRecord.ExclusionReason)</span>"
        } elseif ($ticketRecord -and $ticketRecord.SubSymptom) {
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
        
        if ($ProcessedTicketsData.Count -gt 0) {
            $ticketAnalysis = $ProcessedTicketsData | Where-Object { $_.Number -eq $summary.IncidentNumber } | Select-Object -First 1
            if ($ticketAnalysis -and $ticketAnalysis.Reasoning) {
                $confidenceLevel = Get-NormalizedConfidence -Raw ([string]$ticketAnalysis.Confidence) -RootCausesKnown $true
                $reasoning = $ticketAnalysis.Reasoning
                
                $confidenceColor = switch ($confidenceLevel) {
                    "High"    { "#28a745" }
                    "Medium"  { "#ffc107" }
                    "Low"     { "#dc3545" }
                    default   { "#6c757d" }
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
        
        $serviceNowUrl = if ($summary.IncidentNumber.StartsWith("INC")) {
            "https://intel.service-now.com/nav_to.do?uri=incident.do?sysparm_query=number=$($summary.IncidentNumber)"
        } elseif ($summary.IncidentNumber.StartsWith("SCTASK")) {
            "https://intel.service-now.com/sc_task.do?sys_id=$($summary.IncidentNumber)"
        } else {
            "#"
        }
        
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
    
    $sectionTitle = if ($TicketType -eq 'Incident') { "Detailed EUC Incident Analysis" } else { "Detailed EUC Service Request Analysis" }
    $headerLabel = if ($TicketType -eq 'Incident') { "INCIDENT" } else { "SERVICE REQUEST" }
    
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
        [Parameter(Mandatory)][string]$WebhookUrl,
        [Parameter(Mandatory)][string]$HtmlContent,
        [string]$Subject = $Script:Config.Webhook.DefaultSubject,
        [int]$TimeoutSeconds = $Script:Config.Webhook.TimeoutSeconds,
        [int]$RetryAttempts = $Script:Config.Webhook.RetryAttempts
    )
    
    if (-not ($WebhookUrl -match "^https://")) { throw "Invalid webhook URL format - must start with https://" }
    
    $payload = @{
        subject     = $Subject
        htmlContent = $HtmlContent
        timestamp   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        contentSize = $HtmlContent.Length
    } | ConvertTo-Json -Depth 5 -Compress
    
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
        'User-Agent'   = 'PowerShell-MDM-Reporter/1.2'
    }
    
    $attempt = 0
    do {
        $attempt++
        try {
            Invoke-RestMethod -Uri $WebhookUrl -Method POST -Body $payload -Headers $headers -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            Write-ScriptLog "EUC report sent successfully via webhook" -Level Success
            return @{ Status = "Success"; TimeSent = Get-Date; Subject = $Subject; AttemptsUsed = $attempt }
        } catch {
            Write-ScriptLog "Webhook delivery attempt $attempt failed: $($_.Exception.Message)" -Level Warning
            if ($attempt -lt $RetryAttempts) {
                $waitTime = [Math]::Pow(2, $attempt) * 2
                Start-Sleep -Seconds $waitTime
            }
        }
    } while ($attempt -lt $RetryAttempts)
    
    throw "Failed to send webhook after $RetryAttempts attempts"
}

#endregion

#region Configuration & Prompt Loading

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

#region Canonical MD Allowlists Parsing

function Get-CanonicalLabelsFromTemplates {
    [CmdletBinding()]
    param()

    $result = @{
        Categories          = New-Object System.Collections.Generic.List[string]
        Subcategories       = @{}
        SubcategoryAliasMap = @{}
        PossibleRootCauses  = @{}
        DetailedRootCauses  = @{}
    }

    $catText = [string]$Script:PromptTemplates.TicketCategorisation
    foreach ($m in [regex]::Matches($catText, '(?m)^\*\*([^*\n]+? Issues)\*\*\s*$')) {
        $label = $m.Groups[1].Value.Trim()
        if (-not $result.Categories.Contains($label)) { $result.Categories.Add($label) }
    }
    if (-not $result.Categories.Contains('Excluded'))               { $result.Categories.Add('Excluded') }
    if (-not $result.Categories.Contains('Other / Miscellaneous')) { $result.Categories.Add('Other / Miscellaneous') }

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

function Get-NormalizedConfidence {
    [CmdletBinding()]
    param(
        [string]$Raw,
        [bool]$RootCausesKnown = $true
    )
    if (-not [string]::IsNullOrWhiteSpace($Raw)) {
        $clean = ($Raw -replace '\*+', '').Trim()
        if ($clean -imatch '\bhigh\b')                       { return 'High' }
        if ($clean -imatch '\bmedium\b|\bmoderate\b|\bmed\b') { return 'Medium' }
        if ($clean -imatch '\blow\b')                         { return 'Low' }
    }
    if ($RootCausesKnown) { return 'Medium' }
    return 'Low'
}

function Get-PlainLanguageFallbackReasoning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Ticket,
        [object]$CategoryInfo,
        [switch]$Expanded
    )

    $short = ([string]$Ticket.OriginalDescription).Trim()
    if ([string]::IsNullOrWhiteSpace($short)) { $short = 'the user reported a service issue in the ticket' }

    $symptom = ([string]$Ticket.Subcategory).Trim()
    if ([string]::IsNullOrWhiteSpace($symptom) -or $symptom -match '^(Unknown|Unclassified|Unable)$') {
        $symptom = 'the exact symptom category was not clearly captured'
    }

    $prc = ([string]$Ticket.PossibleRootCause).Trim()
    if ([string]::IsNullOrWhiteSpace($prc) -or $prc -eq 'Unknown') { $prc = 'the root cause was not explicitly confirmed in structured fields' }

    $drc = ([string]$Ticket.DetailedRootCause).Trim()
    if ([string]::IsNullOrWhiteSpace($drc) -or $drc -eq 'Unknown') { $drc = '' }

    $resolution = ([string]$CategoryInfo.resolution_summary).Trim()
    if ([string]::IsNullOrWhiteSpace($resolution)) { $resolution = ([string]$Ticket.Resolution).Trim() }

    $evidence = ([string]$CategoryInfo.key_evidence).Trim()
    if ([string]::IsNullOrWhiteSpace($evidence)) { $evidence = ([string]$Ticket.Evidence).Trim() }

    $responseContext = ((@([string]$CategoryInfo.resolution_summary, [string]$CategoryInfo.how_do_i_or_error, [string]$Ticket.Resolution, [string]$Ticket.Type) -join ' ')).ToLowerInvariant()
    $userResponseSentence = if ($responseContext -match 'no response|did not respond|no reply|unresponsive|auto.?close') {
        'User follow-up appears incomplete in the notes, with closure likely driven by no response.'
    } elseif ($responseContext -match 'confirmed|resolved|working|fixed|happy|satisfied') {
        'The notes suggest the user confirmed the fix and accepted closure.'
    } else {
        'The ticket notes do not clearly state whether the user responded after the fix, so final confirmation status is uncertain.'
    }

    $analysis = "The user reached out because $short. Based on the recorded troubleshooting trail, the issue aligns most closely with '$symptom' under the '$($Ticket.Category)' category. Engineer investigation points to $prc"
    if (-not [string]::IsNullOrWhiteSpace($drc)) {
        $analysis += ", with additional detail indicating $drc"
    }
    $analysis += '. '

    if (-not [string]::IsNullOrWhiteSpace($resolution)) {
        $analysis += "The engineer-provided solution was: $resolution. "
    } else {
        $analysis += 'The exact engineer remediation steps are not fully documented in the structured summary fields. '
    }

    if (-not [string]::IsNullOrWhiteSpace($evidence)) {
        $analysis += "Key ticket evidence supports this interpretation: $evidence. "
    }

    $analysis += $userResponseSentence

    if ($Expanded) {
        $analysis += ' This narrative was generated to preserve readability for operations reviews, so future readers can quickly understand why the user contacted support, what actions were taken, and what outcome was recorded.'
    }

    return $analysis.Trim()
}

function Get-EnhancedFallbackReasoning {
    [CmdletBinding()]
    param([object]$Ticket, [object]$CategoryInfo)
    return (Get-StructuredReasoningNarrative -Ticket $Ticket -CategoryInfo $CategoryInfo)
}

function Test-NotesInsufficient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Ticket,
        [object]$CategoryInfo
    )

    $candidateFields = @(
        [string]$Ticket.OriginalDescription
        [string]$Ticket.Issue
        [string]$Ticket.RootCauseNarrative
        [string]$Ticket.Evidence
        [string]$Ticket.Resolution
        [string]$CategoryInfo.issue
        [string]$CategoryInfo.key_evidence
        [string]$CategoryInfo.resolution_summary
        [string]$CategoryInfo.how_do_i_or_error
    )

    $meaningfulFields = @()
    foreach ($fieldValue in $candidateFields) {
        $cleanValue = ([string]$fieldValue).Trim()
        if ([string]::IsNullOrWhiteSpace($cleanValue)) { continue }
        if ($cleanValue -match '(?im)^(not documented|unknown|unclassified|unable to determine|not identified|automated fallback|no incident summary available)') { continue }
        if ($cleanValue.Length -lt 25) { continue }
        $meaningfulFields += $cleanValue
    }

    $meaningfulText = ($meaningfulFields -join ' ').Trim()
    if ($meaningfulFields.Count -lt 2) { return $true }
    if ($meaningfulText.Length -lt 140) { return $true }

    return $false
}

function Get-InsufficientNotesReasoning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Ticket,
        [object]$CategoryInfo
    )

    $category = ([string]$Ticket.Category).Trim()
    if ([string]::IsNullOrWhiteSpace($category)) { $category = 'Unclassified' }

    $subcategory = ([string]$Ticket.Subcategory).Trim()
    if ([string]::IsNullOrWhiteSpace($subcategory)) { $subcategory = 'Unclassified' }

    $possibleRootCause = ([string]$Ticket.PossibleRootCause).Trim()
    if ([string]::IsNullOrWhiteSpace($possibleRootCause)) { $possibleRootCause = 'Unknown' }

    $detailRootCause = ([string]$Ticket.DetailedRootCause).Trim()
    if ([string]::IsNullOrWhiteSpace($detailRootCause)) { $detailRootCause = 'Unknown' }

    $analysis = "Insufficient notes: the available work notes do not support a confident narrative without inventing details. The ticket remains categorized as '$category' / '$subcategory' with root cause '$possibleRootCause' and detailed root cause '$detailRootCause'."

    $resolution = ([string]$CategoryInfo.resolution_summary).Trim()
    if (-not [string]::IsNullOrWhiteSpace($resolution)) {
        $analysis += " Recorded resolution context: $resolution."
    }

    $evidence = ([string]$CategoryInfo.key_evidence).Trim()
    if (-not [string]::IsNullOrWhiteSpace($evidence)) {
        $analysis += " Key evidence: $evidence."
    }

    return $analysis.Trim()
}

function Test-ReasoningNeedsReanalysis {
    [CmdletBinding()]
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $true }

    $clean = $Text.Trim()
    if ($clean.Length -lt 120) { return $true }

    # Re-run if output contains CSS/HTML fragments.
    $htmlCssPattern = '(?is)<style|</?[a-z][^>]*>|\{\s*text-decoration\s*:|\btr\s+th\b|\bcolor\s*:\s*#[0-9a-fA-F]{3,6}'
    if ($clean -match $htmlCssPattern) { return $true }

    # Re-run any reasoning that still looks like labels or a fallback template.
    $labelPattern = '(?im)(^|\n)\s*(category|symptom|possible root cause|detailed root cause|ai analysis)\s*:'
    $fallbackPattern = '(?im)(generic fallback|fallback classification|the ticket notes do not clearly state|not documented in the available work notes|not documented beyond the catalog classification)'
    return [bool]($clean -match $labelPattern -or $clean -match $fallbackPattern)
}

function Sanitize-AiNarrativeText {
    [CmdletBinding()]
    param(
        [string]$Text,
        [int]$MaxLength = 2000
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $clean = [string]$Text
    $clean = $clean -replace '(?is)<style[^>]*>.*?</style>', ' '
    $clean = $clean -replace '(?is)<script[^>]*>.*?</script>', ' '
    $clean = $clean -replace '(?is)<[^>]+>', ' '
    $clean = $clean -replace '(?is)\b[a-z][a-z0-9\s\.#:_\-]*\{[^{}]*\}', ' '
    $clean = $clean -replace '(?im)^\s*(corrected\s+ai\s+analysis|ai\s+analysis|medium\s+confidence|high\s+confidence|low\s+confidence)\s*:?\s*', ''
    $clean = $clean | Invoke-TextCleanup -ProcessingType Markdown
    $clean = $clean -replace '[\r\n]+', ' '
    $clean = $clean -replace '\s{2,}', ' '
    $clean = $clean.Trim(' ', '.', ',', ';', ':')

    if ($clean.Length -gt $MaxLength) { $clean = $clean.Substring(0, $MaxLength).Trim() + '...' }
    return $clean
}

function Invoke-ReasoningReanalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Ticket,
        [object]$CategoryInfo = $null
    )

    try {
        # Reanalysis should be evidence-driven, not label-driven.
        $systemPrompt = @"
You are reanalyzing a Productivity Tools incident.
Write a fresh incident analysis in 3 to 5 sentences.
Use the supplied ticket fields and notes only.
Do not output labels, bullets, headings, or fallback phrases.
Focus on what happened, why it happened, what remediation or outcome was recorded, and the evidence that supports that conclusion.
If the notes are incomplete, say that clearly, but still produce the best evidence-based analysis.
"@

        $userContent = @"
Incident Number: $([string]$Ticket.Number)
Category: $([string]$Ticket.Category)
Subcategory: $([string]$Ticket.Subcategory)
Possible Root Cause: $([string]$Ticket.PossibleRootCause)
Detailed Root Cause: $([string]$Ticket.DetailedRootCause)
Issue: $([string]$Ticket.Issue)
Root Cause Narrative: $([string]$Ticket.RootCauseNarrative)
Resolution: $([string]$Ticket.Resolution)
Evidence: $([string]$Ticket.Evidence)
Knowledge Base: $([string]$Ticket.KnowledgeBase)
Original Description: $([string]$Ticket.OriginalDescription)
Category Summary: $([string]$CategoryInfo.issue)
Key Evidence: $([string]$CategoryInfo.key_evidence)
Resolution Summary: $([string]$CategoryInfo.resolution_summary)
How Do I or Error: $([string]$CategoryInfo.how_do_i_or_error)
"@

        $requestBody = New-AiRequestBody -SystemPrompt $systemPrompt -UserContent $userContent -TaskType 'Category'
        $apiKey = if ($Script:Constants.UseClaudeModel) { $Script:Constants.ClaudeApiKey } else { $Script:Constants.AzureOpenAIApiKey }
        $aiResponse = Invoke-AuthenticatedApiCall -Url (Get-AIEndpoint) -Method POST -RequestBody $requestBody -ApiKey $apiKey -IsClaudeApi:$Script:Constants.UseClaudeModel

        $responseText = if ($Script:Constants.UseClaudeModel) { $aiResponse.content[0].text } else { $aiResponse.choices[0].message.content }
        $responseText = ([string]$responseText).Trim()

        if (Test-ReasoningNeedsReanalysis -Text $responseText) {
            Write-ScriptLog "Reanalysis returned a weak reasoning result for $([string]$Ticket.Number); keeping the structured safety-net narrative." -Level Warning -Category "Categorization"
            return $null
        }

        return $responseText
    } catch {
        Write-ScriptLog "Reasoning reanalysis failed for $([string]$Ticket.Number): $($_.Exception.Message)" -Level Warning -Category "Categorization"
        return $null
    }
}

function Get-StructuredReasoningNarrative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Ticket,
        [object]$CategoryInfo
    )

    $engineTicket = [pscustomobject]@{
        Issue               = [string]$Ticket.OriginalDescription
        SupportActions      = [string]$Ticket.RootCauseNarrative
        Investigation       = [string]$Ticket.Evidence
        Communications      = [string]$CategoryInfo.key_evidence
        ClassificationChanges = "$([string]$Ticket.Category) / $([string]$Ticket.Subcategory)"
        FinalResolution     = [string]$Ticket.Resolution
        RootCauseStatus     = if ([string]::IsNullOrWhiteSpace([string]$Ticket.RootCauseNarrative)) { 'Not Identified' } else { 'Identified' }
        Confidence          = [string]$Ticket.Confidence
    }

    $analysisConfig = New-AiAnalysisEngineConfig -ServiceOfferingName 'Productivity Tools'
    $analysis = Get-AiAnalysisExecutiveAnalysis -Ticket $engineTicket -Config $analysisConfig
    return $analysis.ExecutiveAnalysis
}

function Get-FallbackReasoning {
    [CmdletBinding()]
    param([object]$Ticket, [object]$CategoryInfo)
    return (Get-StructuredReasoningNarrative -Ticket $Ticket -CategoryInfo $CategoryInfo)
}

function Format-StructuredAiAnalysis {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ticket)

    $issue      = if ([string]::IsNullOrWhiteSpace([string]$Ticket.Issue)) { 'Not documented.' } else { Sanitize-AiNarrativeText -Text ([string]$Ticket.Issue) -MaxLength 600 }
    $rootCause  = if ([string]::IsNullOrWhiteSpace([string]$Ticket.RootCauseNarrative)) { 'Not documented.' } else { Sanitize-AiNarrativeText -Text ([string]$Ticket.RootCauseNarrative) -MaxLength 900 }
    $resolution = if ([string]::IsNullOrWhiteSpace([string]$Ticket.Resolution)) { 'Not documented in work notes.' } else { Sanitize-AiNarrativeText -Text ([string]$Ticket.Resolution) -MaxLength 900 }
    $evidence   = if ([string]::IsNullOrWhiteSpace([string]$Ticket.Evidence)) { 'Not documented in work notes.' } else { Sanitize-AiNarrativeText -Text ([string]$Ticket.Evidence) -MaxLength 900 }
    $confidence = if ([string]::IsNullOrWhiteSpace([string]$Ticket.Confidence)) { 'Unknown' } else { [string]$Ticket.Confidence }
    $reasoning  = Sanitize-AiNarrativeText -Text ([string]$Ticket.Reasoning) -MaxLength 2200

    return (
        "Problem: $issue`n" +
        "Root Cause: $rootCause`n" +
        "Resolution: $resolution`n" +
        "Evidence: $evidence`n" +
        "AI Analysis ($confidence Confidence): $reasoning"
    )
}

function Test-LabelStyleReasoning {
    [CmdletBinding()]
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $pattern = '(?im)(\*\*\s*category\s*:\s*|\*\*\s*symptom/subcategory\s*:\s*|\*\*\s*possible root cause\s*:\s*|\*\*\s*detailed root cause\s*:\s*|^\s*category\s*:\s*|^\s*symptom\s*:\s*|^\s*possible root cause\s*:\s*|^\s*detailed root cause\s*:\s*)'
    return [bool]($Text -match $pattern)
}

function Ensure-TicketAiFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Ticket,
        [object]$CategoryInfo = $null
    )

    $rootCausesKnown = (
        -not [string]::IsNullOrWhiteSpace([string]$Ticket.PossibleRootCause) -and
        -not [string]::IsNullOrWhiteSpace([string]$Ticket.DetailedRootCause)
    )
    $Ticket.Confidence = Get-NormalizedConfidence -Raw ([string]$Ticket.Confidence) -RootCausesKnown $rootCausesKnown

    if ([string]::IsNullOrWhiteSpace([string]$Ticket.Issue)) {
        $Ticket.Issue = if (-not [string]::IsNullOrWhiteSpace([string]$Ticket.OriginalDescription)) { [string]$Ticket.OriginalDescription } else { 'Not documented.' }
    }
    if ([string]::IsNullOrWhiteSpace([string]$Ticket.RootCauseNarrative)) {
        $Ticket.RootCauseNarrative = if (-not [string]::IsNullOrWhiteSpace([string]$Ticket.PossibleRootCause)) {
            "Root cause not documented beyond the catalog classification of $($Ticket.PossibleRootCause)."
        } else {
            'Root cause not documented in the available work notes.'
        }
    }

    $fallbackInfo = if ($CategoryInfo) { $CategoryInfo } else { [PSCustomObject]@{ resolution_summary = [string]$Ticket.Resolution } }
    $notesInsufficient = Test-NotesInsufficient -Ticket $Ticket -CategoryInfo $fallbackInfo

    if ([string]::IsNullOrWhiteSpace([string]$Ticket.Reasoning)) {
        $Ticket.Reasoning = Get-FallbackReasoning -Ticket $Ticket -CategoryInfo $fallbackInfo
    } elseif (Test-LabelStyleReasoning -Text ([string]$Ticket.Reasoning)) {
        $Ticket.Reasoning = Get-EnhancedFallbackReasoning -Ticket $Ticket -CategoryInfo $fallbackInfo
    }

    $Ticket.Reasoning = Sanitize-AiNarrativeText -Text ([string]$Ticket.Reasoning) -MaxLength 2200
    if ([string]::IsNullOrWhiteSpace([string]$Ticket.Reasoning)) {
        if ($notesInsufficient) {
            $Ticket.AnalysisStatus = 'Insufficient notes'
            $Ticket.Reasoning = Get-InsufficientNotesReasoning -Ticket $Ticket -CategoryInfo $fallbackInfo
        }
    } elseif ($notesInsufficient) {
        $Ticket.AnalysisStatus = 'Insufficient notes'
    }

    return $Ticket
}

function Test-ExistingAiAnalysisUsable {
    [CmdletBinding()]
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    $clean = ([string]$Text) -replace '\*\*', ''
    if ($clean -match '(?is)<style|</?[a-z][^>]*>|\{\s*text-decoration\s*:|\btr\s+th\b|\bcolor\s*:\s*#[0-9a-fA-F]{3,6}') { return $false }

    if ($clean -notmatch '(?im)^\s*Problem\s*:') { return $false }
    if ($clean -notmatch '(?im)^\s*Root\s*Cause\s*:') { return $false }
    if ($clean -notmatch '(?im)^\s*Resolution\s*:') { return $false }
    if ($clean -notmatch '(?im)^\s*Evidence\s*:') { return $false }
    if ($clean -notmatch '(?im)^\s*AI\s*Analysis\s*(?:\([^)]*\))?\s*:') { return $false }

    $problem = ([regex]::Match($clean, '(?ims)^\s*Problem\s*:\s*(.*?)\s*(?=\n\s*Root\s*Cause\s*:|\z)').Groups[1].Value -replace '\s+', ' ').Trim(' ', '.', ',', ';', ':')
    $analysis = ([regex]::Match($clean, '(?ims)^\s*AI\s*Analysis\s*(?:\([^)]*\))?\s*:\s*(.*?)\s*$').Groups[1].Value -replace '\s+', ' ').Trim(' ', '.', ',', ';', ':')

    if ([string]::IsNullOrWhiteSpace($problem)) { return $false }
    if ([string]::IsNullOrWhiteSpace($analysis)) { return $false }
    if ($problem -match '^(not documented|unknown|n/?a)$') { return $false }
    if ($analysis.Length -lt 60) { return $false }
    return $true
}

function Normalize-CanonicalText {
    [CmdletBinding()]
    param([string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    $s = $Raw -replace '[\u2010\u2011\u2012\u2013\u2014\u2015]', '-'
    $s = $s -replace '\*+', ''
    $s = $s -replace '^\["\s]+|["\]\s]+$', ''
    $s = $s -replace '\s+', ' '
    return $s.Trim().ToLowerInvariant()
}

function Get-CanonicalAlias {
    [CmdletBinding()]
    param(
        [ValidateSet('Category','Subcategory','PossibleRootCause','DetailedRootCause')][string]$Field,
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
        [ValidateSet('Subcategory','PossibleRootCause','DetailedRootCause')][string]$Field,
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

    foreach ($lbl in $Allowlist) {
        if ($lbl -ieq $Raw) { return $lbl }
        if ((Normalize-CanonicalText -Raw $lbl) -eq $clean) { return $lbl }
    }
    foreach ($lbl in $Allowlist) {
        $nLbl = Normalize-CanonicalText -Raw $lbl
        if ($clean -like "*$nLbl*" -or $nLbl -like "*$clean*") { return $lbl }
    }
    return $Fallback
}

function Get-AllowlistForProduct {
    [CmdletBinding()]
    param(
        [hashtable]$Map,
        [string]$Product
    )
    if (-not $Map -or -not $Product) { return $null }
    if ($Map.ContainsKey($Product))  { return $Map[$Product] }
    foreach ($k in $Map.Keys) {
        if ($k -ieq $Product)                { return $Map[$k] }
        if ($Product -like "*$k*" -or $k -like "*$Product*") { return $Map[$k] }
    }

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
        Temperature = @{ Cleanup = 0.3; Summary = 0.2; Category = 0 }
        MaxTokens = 8192
        TopP = 1.0
        FrequencyPenalty = 0
        PresencePenalty = 0
    }
    Rescue = @{ Enabled = $true }
    Webhook = @{ TimeoutSeconds = 300; RetryAttempts = 3; DefaultSubject = "EUC Resolved Ticket AI Strict Categorization Report" }
    Logging = @{ EnableDebug = $true; TimestampFormat = "yyyy-MM-dd HH:mm:ss" }
}

class TicketAnalysis {
    [string]$Number
    [string]$TicketType
    [string]$Category
    [string]$SubSymptom
    [string]$Subcategory
    [string]$PossibleRootCause
    [string]$DetailedRootCause
    [string]$Service
    [bool]$Misrouted
    [string]$ExclusionReason
    [string]$Confidence
    [string]$Issue
    [string]$RootCauseNarrative
    [string]$Reasoning
    [string]$Evidence
    [string]$Resolution
    [string]$Type
    [string]$KnowledgeBase
    [string]$OriginalDescription
    [string]$ResolvedAt
    [string]$AnalysisStatus
    [datetime]$Processed = (Get-Date)
    
    TicketAnalysis([string]$ticketNumber) {
        $this.Number = $ticketNumber
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

if (-not $Script:Constants) { throw "Missing required configuration object: Constants" }
if (-not $Script:PromptTemplates) { throw "Missing required configuration object: PromptTemplates" }

Write-ScriptLog "ServiceNow EUC Ticket Categorization System v1.2" -Level Info
$aiModel = if ($Script:Constants.UseClaudeModel) { "Claude Sonnet 4.5 ($($Script:Constants.ClaudeDeployment))" } else { "Azure OpenAI ($($Script:Constants.AzureOpenAIDeployment))" }
Write-ScriptLog "AI Model: $aiModel" -Level Info

if ($env:RUNBOOK_LOAD_ONLY -eq '1') {
    Write-Host "RUNBOOK_LOAD_ONLY=1 detected; skipping orchestration." -ForegroundColor Yellow
    return
}

try {
    Initialize-BlobLogging
    Send-LogAnalyticsHeartbeat -Status 'Started' -Message 'EUC ticket processing workflow started'
    Write-ScriptLog "=== STARTING EUC TICKET PROCESSING WORKFLOW ===" -Level Info
    
    # Data Retrieval Phase
    if ($Script:Constants.UseStoredIncidents) {
        Write-ScriptLog "=== LOADING STORED INCIDENT DATA ===" -Level Info
        Get-AvailableIncidentFiles | Out-Null
        $incidents = Get-StoredIncidents -FileName $Script:Constants.StoredDataFileName
        
        $yesterday = (Get-Date).AddDays(-1)
        $today = Get-Date
        $Script:reportperiod = "Stored Data Analysis - $($yesterday.ToString('yyyy-MM-dd HH:mm')) to $($today.ToString('yyyy-MM-dd HH:mm'))"
    } else {
        Write-ScriptLog "=== AUTHENTICATION PHASE ===" -Level Info
        $serviceNowToken = Get-AccessToken -TokenUrl $Script:Constants.TokenUrl -ClientId $Script:Constants.ServiceNowIncidentsClientID -ClientSecret $Script:Constants.ServiceNowIncidentsClientSecret -Scope $Script:Constants.ServiceNowIncidentsScope
        
        Write-ScriptLog "=== SERVICENOW INCIDENT DATA RETRIEVAL ===" -Level Info
        $yesterday = (Get-Date).AddDays(-1)
        $today = Get-Date
        $Script:reportperiod = "$($yesterday.ToString('yyyy-MM-dd HH:mm'))" + " to " + "$($today.ToString('yyyy-MM-dd HH:mm'))"

        $incidentsResponse = Invoke-AuthenticatedApiCall -Url $Script:Constants.ServicenowIncidentsURL -AccessToken $serviceNowToken -Method GET
        $incidents = if ($incidentsResponse -and $null -ne $incidentsResponse.result) { @($incidentsResponse.result) } else { @() }
        if ($incidents.Count -eq 0) {
            Write-ScriptLog "ServiceNow returned no incidents for the current request window." -Level Warning
        }

        $lookbackHours = if ($null -ne $Script:Constants.DailyLookbackHours -and -not [string]::IsNullOrWhiteSpace([string]$Script:Constants.DailyLookbackHours)) { [int]$Script:Constants.DailyLookbackHours } else { 26 }
        $incidents = Filter-IncidentsByResolvedWindow -Incidents $incidents -LookbackHours $lookbackHours
        
        Write-ScriptLog "Retrieved $($incidents.Count) resolved incidents for processing" -Level Success
        
        if ($Script:Constants.SaveRawDataLocally -and -not $Script:IsAzureAutomation) {
            Save-IncidentsData -Incidents $incidents | Out-Null
        } elseif ($Script:IsAzureAutomation -and $incidents.Count -gt 0) {
            Save-IncidentsData -Incidents $incidents | Out-Null
        }
    }
    
    $requests = @()

    if ($incidents.count -eq 0) {
        Write-ScriptLog "No incidents found to process - exiting without generating report" -Level Warning
        Complete-BlobLogging -FinalMessage "No incidents found to process"
        return
    }
    
    # Processing Phase
    Write-ScriptLog "=== AI PROCESSING PHASE ===" -Level Info
    $allsummarisednotes = [System.Collections.Generic.List[PSCustomObject]]::new()
    $processedIncidentCount = 0
    $totalIncidents = $incidents.Count

    Write-ScriptLog "Processing $totalIncidents incidents..." -Level Info

    $existingRowsByWeek = @{}
    $dedupTable = $null
    try { $dedupTable = Initialize-StatisticsTable } catch { $dedupTable = $null }
    $skippedAlreadyStored = 0

    foreach ($incident in $incidents) {
        if ($dedupTable -and $incident.number) {
            $rdt = [DateTime]::MinValue
            if ([DateTime]::TryParse([string]$incident.resolved_at, [ref]$rdt)) {
                $wn = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear($rdt, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
                $wk = '{0:D4}-W{1:D2}' -f $rdt.Year, $wn
                if (-not $existingRowsByWeek.ContainsKey($wk)) {
                    $map = @{}
                    try {
                        $rows = Get-AzTableRow -Table $dedupTable -PartitionKey $wk -ErrorAction Stop
                        foreach ($r in @($rows)) {
                            if ($r.RowKey) {
                                $map[[string]$r.RowKey] = [string]$r.AIAnalysis
                            }
                        }
                    } catch {
                        Write-ScriptLog "Dedup: could not load existing keys for ${wk}: $($_.Exception.Message)" -Level Warning
                    }
                    $existingRowsByWeek[$wk] = $map
                }

                $incidentKey = [string]$incident.number
                if ($existingRowsByWeek[$wk].ContainsKey($incidentKey)) {
                    $existingAi = [string]$existingRowsByWeek[$wk][$incidentKey]
                    if (Test-ExistingAiAnalysisUsable -Text $existingAi) {
                        $skippedAlreadyStored++
                        continue
                    }
                    Write-ScriptLog "Dedup: reprocessing $incidentKey in $wk because existing AIAnalysis is incomplete or malformed." -Level Warning
                }
            }
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
            } catch {
                $retryCount++
                $errorMessage = $_.Exception.Message
                
                if ($errorMessage -match "429" -or $errorMessage -match "Too Many Requests") {
                    $waitTime = [math]::Min(30, [math]::Pow(2, $retryCount) * 5)
                    Write-ScriptLog "Rate limit hit for incident $($incident.number). Waiting $waitTime seconds before retry $retryCount/$maxRetries" -Level Warning
                    Start-Sleep -Seconds $waitTime
                } elseif ($retryCount -ge $maxRetries) {
                    Write-ScriptLog "Failed to process incident $($incident.number) after $maxRetries attempts: $errorMessage" -Level Warning

                    $fallbackTicket = New-FallbackTicketAnalysis -Incident $incident -FailureReason $errorMessage
                    $Script:ProcessedTickets.Add($fallbackTicket)
                    $allsummarisednotes.Add([PSCustomObject]@{
                        IncidentNumber  = $incident.number
                        SummarisedNotes = "Fallback summary generated because AI categorization failed after retries."
                    })
                    $processedIncidentCount++
                    $success = $true
                } else {
                    Start-Sleep -Seconds 2
                }
            }
        }
        
        Start-Sleep -Seconds 3
    }

    Write-ScriptLog "Completed incident processing: $processedIncidentCount/$totalIncidents successful (skipped $skippedAlreadyStored already-categorized incidents)" -Level Success

    if ($Script:ProcessedTickets.Count -eq 0 -and $skippedAlreadyStored -eq 0) {
        Write-ScriptLog "ERROR: No incidents were successfully processed - check AI authentication and API endpoints" -Level Error
        Complete-BlobLogging -FinalMessage "Processing failed - no incidents successfully processed"
        return
    }

    $dataSource = if ($Script:Constants.UseStoredIncidents -and -not $Script:IsAzureAutomation) { "Stored Data" } else { "Live API" }

    $backfillYearWeek = $null
    try {
        $bfVar = Get-AutomationVariable -Name 'BackfillYearWeek' -ErrorAction SilentlyContinue
        if ($bfVar -and $bfVar -match '^\d{4}-W\d{2}$') { $backfillYearWeek = $bfVar }
    } catch { }

    $saveRunArtifacts = if ($null -ne $Script:Constants.SaveRunArtifacts -and -not [string]::IsNullOrWhiteSpace([string]$Script:Constants.SaveRunArtifacts)) { [bool]$Script:Constants.SaveRunArtifacts } else { $true }
    if (-not $backfillYearWeek -and $saveRunArtifacts -and $allsummarisednotes.Count -gt 0) {
        Save-RunProcessingArtifact -DetailedSummaries $allsummarisednotes -ReportPeriod $Script:reportperiod -DataSource $dataSource | Out-Null
    }

    $lookbackDays = if ($null -ne $Script:Constants.WeeklyMergeLookbackDays -and -not [string]::IsNullOrWhiteSpace([string]$Script:Constants.WeeklyMergeLookbackDays)) { [int]$Script:Constants.WeeklyMergeLookbackDays } else { 7 }
    $mergedData = if ($backfillYearWeek) { @{ ProcessedTickets = @(); DetailedSummaries = @(); YearWeek = $backfillYearWeek } } else { Get-MergedWeeklyRunData -LookbackDays $lookbackDays }
    
    if ($mergedData.ProcessedTickets.Count -gt 0) {
        $Script:ProcessedTickets = $mergedData.ProcessedTickets
        $allsummarisednotes = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($summary in $mergedData.DetailedSummaries) {
            $allsummarisednotes.Add([PSCustomObject]@{
                IncidentNumber  = $summary.IncidentNumber
                SummarisedNotes = $summary.SummarisedNotes
            })
        }
        $dataSource = "Merged Weekly ($($Script:ProcessedTickets.Count) incidents)"
    }

    # Report & Statistics Phase
    Write-ScriptLog "=== REPORT GENERATION ===" -Level Info
    $CategoryData = Get-CategoryStatistics
    # Downstream HTML generation expects arrays, not $null, even when a week is sparse.
    if ($null -eq $CategoryData) { $CategoryData = @() }
    if ($null -eq $allsummarisednotes) { $allsummarisednotes = @() }
    $htmlcontent = New-HtmlTicketReport -CategoryData $CategoryData -DetailedSummaries $allsummarisednotes
    $totalProcessedTickets = $Script:ProcessedTickets.Count

    if ($mergedData.YearWeek) {
        $reportYearWeek = $mergedData.YearWeek
    } else {
        $reportYear = (Get-Date).Year
        $reportWeekNumber = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear((Get-Date), [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
        $reportYearWeek = "{0:D4}-W{1:D2}" -f $reportYear, $reportWeekNumber
    }
    
    $reportBlobName = "EUC_Weekly_Report_$reportYearWeek.html"
    
    Write-ScriptLog "=== SAVING STATISTICS TO AZURE TABLE ===" -Level Info
    $reportDateForTable = Get-Date
    if ($reportYearWeek -match '^(\d{4})-W(\d{2})$') {
        $ywYear = [int]$Matches[1]
        $ywWeek = [int]$Matches[2]
        $currentWeekNum = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear((Get-Date), [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
        if ($ywWeek -ne $currentWeekNum -or $ywYear -ne (Get-Date).Year) {
            $jan4 = [DateTime]::new($ywYear, 1, 4)
            $jan4Monday = $jan4.AddDays(-([int]$jan4.DayOfWeek + 6) % 7)
            $reportDateForTable = $jan4Monday.AddDays(($ywWeek - 1) * 7 + 3)
        }
    }
    Save-CategoryStatisticsToTable -CategoryData $CategoryData -ReportDate $reportDateForTable -ReportBlobName $reportBlobName
    
    if ($Script:IsAzureAutomation) {
        try {
            $storageContext = Get-StorageContext
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tempFile -Value $htmlcontent -Encoding UTF8
                Set-AzStorageBlobContent -File $tempFile -Container $Script:BlobConfig.ResultsContainerName -Blob $reportBlobName -Context $storageContext -Force | Out-Null
                Write-ScriptLog "Report saved to blob: $reportBlobName" -Level Success
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        } catch {
            Write-ScriptLog "Failed to save report to blob storage: $($_.Exception.Message)" -Level Error
        }
    } else {
        $resultsDir = ".\results"
        if (-not (Test-Path $resultsDir)) { New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null }
        $filePath = Join-Path $resultsDir $reportBlobName
        Set-Content -Path $filePath -Value $htmlcontent -Encoding UTF8
        Write-ScriptLog "Report saved locally: $filePath" -Level Success
    }

    # Dashboard Regeneration Phase
    Write-ScriptLog "=== DASHBOARD REGENERATION ===" -Level Info
    try {
        $storageContext = Get-StorageContext
        $sas = New-AzStorageTableSASToken -Name $Script:BlobConfig.StatisticsTableName -Permission 'r' -ExpiryTime (Get-Date).AddMinutes(30) -Protocol HttpsOnly -Context $storageContext

        $tableUri = "https://$($Script:BlobConfig.StorageAccountName).table.core.windows.net/$($Script:BlobConfig.StatisticsTableName)()?`$filter=PartitionKey eq '$reportYearWeek'&$sas"

        $tableRows = @()
        $nextUri = $tableUri
        while ($nextUri) {
            $resp = Invoke-WebRequest -Uri $nextUri -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
            $tableRows += ($resp.Content | ConvertFrom-Json).value
            $npk = $resp.Headers['x-ms-continuation-NextPartitionKey']
            $nrk = $resp.Headers['x-ms-continuation-NextRowKey']
            if ($npk) {
                $nextUri = $tableUri + '&NextPartitionKey=' + [Uri]::EscapeDataString([string]$npk)
                if ($nrk) { $nextUri += '&NextRowKey=' + [Uri]::EscapeDataString([string]$nrk) }
            } else { $nextUri = $null }
        }

        if ($tableRows.Count -gt 0) {
            function HtmlEsc { param([string]$s) if ($null -eq $s) { return '' } [System.Net.WebUtility]::HtmlEncode($s) }

            $categoryColors = @{
                'Microsoft OneDrive Issues'               = '#005a9e'
                'Microsoft Excel Issues'                  = '#107c41'
                'Microsoft Word Issues'                   = '#2b579a'
                'Microsoft PowerPoint Issues'             = '#b7472a'
                'Microsoft 365 Copilot Issues'            = '#464feb'
                'Microsoft 365 Apps for Enterprise Issues'= '#0078d4'
                'Microsoft OneNote Issues'                = '#7719aa'
                'Microsoft Forms Issues'                  = '#6264a7'
                'Microsoft Loop Issues'                   = '#00bcf2'
                'Microsoft Project Issues'                = '#ba141a'
                'Microsoft 365 Planner / To Do Issues'    = '#0078d4'
                'Shared File Service (Share Drives) Issues'= '#ff9800'
                'Google Workspace Issues'                 = '#4285f4'
                'Smartsheet Issues'                       = '#00a868'
                'Rejoin / Account Lifecycle Access Issues' = '#8bc34a'
                'How Do I / User Education'               = '#f39c12'
                'Other / Miscellaneous'                   = '#78909c'
                'Excluded'                                = '#90a4ae'
            }
            function ColorFor { param([string]$c) if ($categoryColors.ContainsKey($c)) { $categoryColors[$c] } else { '#5b6abf' } }

            $total      = $tableRows.Count
            $excluded   = ($tableRows | Where-Object { $_.Category -eq 'Excluded' }).Count
            $inScope    = $total - $excluded
            $byCategory = $tableRows | Group-Object Category | Sort-Object Count -Descending
            $topCat     = if ($byCategory.Count -gt 0) { $byCategory[0].Name } else { 'N/A' }

            $istStart = ''; $istEnd = ''
            if ($reportYearWeek -match '^(?<y>\d{4})-W(?<w>\d{1,2})$') {
                $y = [int]$Matches['y']; $w = [int]$Matches['w']
                $jan4     = [DateTime]::new($y, 1, 4)
                $jan4Mon  = $jan4.AddDays(-(([int]$jan4.DayOfWeek + 6) % 7))
                $monDt    = $jan4Mon.AddDays(($w - 1) * 7)
                $sunDt    = $monDt.AddDays(6)
                $istOffset = [TimeSpan]::FromHours(5.5)
                $istStart = ($monDt + $istOffset).ToString('d MMM')
                $istEnd   = ($sunDt  + $istOffset).ToString('d MMM yyyy')
            }

            $kpiHtml = @"
<div class="kpi-grid">
  <div class="kpi-card"><div class="kpi-value">$total</div><div class="kpi-label">Total Incidents</div></div>
  <div class="kpi-card"><div class="kpi-value">$inScope</div><div class="kpi-label">In-Scope</div></div>
  <div class="kpi-card"><div class="kpi-value">$excluded</div><div class="kpi-label">Excluded</div></div>
  <div class="kpi-card"><div class="kpi-value" style="font-size:16px;">$(HtmlEsc $topCat)</div><div class="kpi-label">Top Category</div></div>
</div>
"@

            $catRows = ($byCategory | ForEach-Object {
                $pct = [math]::Round(($_.Count / $total) * 100, 1)
                $clr = ColorFor $_.Name
                "<tr><td><span class='cat-dot' style='background:$clr'></span>$(HtmlEsc $_.Name)</td><td class='num'>$($_.Count)</td><td class='num'>$pct%</td></tr>"
            }) -join "`n"

            $detailRows = ($tableRows | Sort-Object Date -Descending | ForEach-Object {
                $clr  = ColorFor $_.Category
                $aiHtml = if ($_.AIAnalysis) { "<div class='ai-analysis'>$(HtmlEsc $_.AIAnalysis)</div>" } else { '' }
                @"
<tr>
  <td class='inc-num'><a href='https://intel.service-now.com/nav_to.do?uri=incident.do?sysparm_query=number=$(HtmlEsc $_.RowKey)' target='_blank'>$(HtmlEsc $_.RowKey)</a></td>
  <td>$(HtmlEsc $_.Date)</td>
  <td><span class='cat-badge' style='background:$clr'>$(HtmlEsc $_.Category)</span></td>
  <td>$(HtmlEsc $_.Subcategory)</td>
  <td>$(HtmlEsc $_.RootCause)</td>
  <td>$(HtmlEsc $_.DetailedRootCause)</td>
  <td class='conf-$(($_.Confidence -replace '\s','').ToLower())'>$(HtmlEsc $_.Confidence)</td>
  <td>$aiHtml</td>
</tr>
"@
            }) -join "`n"

            $ptDashboardHtml = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>Productivity Tools – $reportYearWeek</title>
<style>
  body{margin:0;padding:0;background:#f0f2f5;font-family:'Segoe UI',sans-serif;font-size:13px;}
  .topbar{background:#0071c5;color:#fff;padding:16px 28px;display:flex;align-items:center;justify-content:space-between;}
  .topbar h1{margin:0;font-size:20px;font-weight:400;}
  .topbar .meta{font-size:12px;opacity:.85;}
  .content{padding:24px 28px;}
  .kpi-grid{display:flex;gap:16px;margin-bottom:24px;flex-wrap:wrap;}
  .kpi-card{background:#fff;border-radius:8px;padding:18px 24px;flex:1;min-width:140px;box-shadow:0 2px 6px rgba(0,0,0,.08);}
  .kpi-value{font-size:32px;font-weight:700;color:#0071c5;}
  .kpi-label{font-size:11px;color:#666;text-transform:uppercase;letter-spacing:.8px;margin-top:4px;}
  .card{background:#fff;border-radius:8px;box-shadow:0 2px 6px rgba(0,0,0,.08);margin-bottom:24px;overflow:hidden;}
  .card-title{padding:14px 20px;border-bottom:1px solid #eee;font-weight:600;font-size:14px;color:#333;}
  table{width:100%;border-collapse:collapse;}
  th{background:#f8f9fa;padding:10px 14px;text-align:left;font-size:11px;letter-spacing:.6px;text-transform:uppercase;color:#555;border-bottom:2px solid #dee2e6;}
  td{padding:10px 14px;border-bottom:1px solid #f0f0f0;vertical-align:top;}
  tr:hover td{background:#fafbfc;}
  .num{text-align:right;}
  .cat-dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;}
  .cat-badge{color:#fff;padding:2px 8px;border-radius:12px;font-size:11px;white-space:nowrap;}
  .inc-num a{color:#0071c5;text-decoration:none;font-weight:600;}
  .ai-analysis{font-size:12px;color:#444;line-height:1.5;max-width:400px;}
  .conf-high{color:#107c10;font-weight:600;}
  .conf-medium{color:#c67c00;font-weight:600;}
  .conf-low{color:#c50f1f;font-weight:600;}
</style></head><body>
<div class="topbar">
  <h1>Productivity Tools Weekly Report – $reportYearWeek</h1>
  <div class="meta">$istStart – $istEnd &nbsp;|&nbsp; Generated $(Get-Date -Format 'dd MMM yyyy HH:mm') IST</div>
</div>
<div class="content">
  $kpiHtml
  <div class="card">
    <div class="card-title">Category Breakdown</div>
    <table><thead><tr><th>Category</th><th class="num">Count</th><th class="num">%</th></tr></thead>
    <tbody>$catRows</tbody></table>
  </div>
  <div class="card">
    <div class="card-title">Incident Details</div>
    <table><thead><tr>
      <th>Incident</th><th>Date</th><th>Category</th><th>Subcategory</th>
      <th>Possible Root Cause</th><th>Detailed Root Cause</th><th>Confidence</th><th>AI Analysis</th>
    </tr></thead><tbody>$detailRows</tbody></table>
  </div>
</div></body></html>
"@

            $ptBlobName = "ProductivityTools_Weekly_Report_$reportYearWeek.html"
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Set-Content -Path $tempFile -Value $ptDashboardHtml -Encoding UTF8
                Set-AzStorageBlobContent -File $tempFile -Container $Script:BlobConfig.ResultsContainerName -Blob $ptBlobName -Context $storageContext -Force | Out-Null
                Write-ScriptLog "Dashboard saved: $ptBlobName ($($tableRows.Count) incidents)" -Level Success
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
    } catch {
        Write-ScriptLog "Failed to regenerate dashboard: $($_.Exception.Message)" -Level Error
    }

    Send-LogAnalyticsHeartbeat -Status 'Completed' -ProcessedCount $totalProcessedTickets -Message "Execution completed successfully ($dataSource)"
    Complete-BlobLogging -FinalMessage "Execution completed successfully - $totalProcessedTickets incidents processed ($dataSource)"
    
} catch {
    Write-ScriptLog "EUC workflow execution failed: $($_.Exception.Message)" -Level Error
    Send-LogAnalyticsHeartbeat -Status 'Failed' -ErrorCount 1 -Message $_.Exception.Message
    Complete-BlobLogging -FinalMessage "Execution failed with error: $($_.Exception.Message)"
    throw
}

#endregion