if (Get-Module -ListAvailable -Name Az.Storage) {
    Import-Module Az.Storage -Force -ErrorAction SilentlyContinue
}
if (Get-Module -ListAvailable -Name Az.KeyVault) {
    Import-Module Az.KeyVault -Force -ErrorAction SilentlyContinue
}

function Get-EucAutomationValue {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Default = ''
    )

    try {
        $value = Get-AutomationVariable -Name $Name -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace([string]$value)) { return $Default }
        return [string]$value
    } catch {
        return $Default
    }
}

function Get-EucRunbookContext {
    param(
        [Parameter(Mandatory)]
        [string]$OfferingName,
        [Parameter(Mandatory)]
        [string]$Mode
    )

    [pscustomobject]@{
        ServiceName        = 'End User Conferencing'
        OfferingName       = $OfferingName
        Mode               = $Mode
        StorageAccountName = Get-EucAutomationValue -Name 'EUC_StorageAccountName' -Default 'opswconferblob'
        KeyVaultName       = Get-EucAutomationValue -Name 'EUC_KeyVaultName' -Default 'opswconferkeyvault'
        AutomationAccount  = Get-EucAutomationValue -Name 'EUC_AutomationAccountName' -Default 'opswconferautomation'
        ResourceGroupName  = Get-EucAutomationValue -Name 'EUC_ResourceGroupName' -Default 'OPSW-Ticket-Analyzer'
        TableName          = Get-EucAutomationValue -Name 'EUC_TrendTableName' -Default 'IncidentsCategoryStats'
        TemplateContainer  = Get-EucAutomationValue -Name 'EUC_PromptTemplateContainerName' -Default 'templates'
        DataContainer      = Get-EucAutomationValue -Name 'EUC_DataContainerName' -Default 'data'
        LogsContainer      = Get-EucAutomationValue -Name 'EUC_LogsContainerName' -Default 'logs'
        ResultsContainer   = Get-EucAutomationValue -Name 'EUC_ResultsContainerName' -Default 'results'
        BusinessServiceId  = Get-EucAutomationValue -Name 'EUC_BusinessServiceId' -Default ''
        MessagingOfferingId = Get-EucAutomationValue -Name 'EUC_MessagingServiceOfferingId' -Default ''
        RoomsOfferingId    = Get-EucAutomationValue -Name 'EUC_RoomsServiceOfferingId' -Default ''
        ServiceNowClientId = Get-EucAutomationValue -Name 'EUC_ServiceNowClientId' -Default ''
        ServiceNowScope    = Get-EucAutomationValue -Name 'EUC_ServiceNowScope' -Default ''
        ServiceNowTokenUrl = Get-EucAutomationValue -Name 'EUC_ServiceNowTokenUrl' -Default 'https://apis.intel.com/v1/auth/token'
        MessagingServiceNowIncidentsUrl = Get-EucAutomationValue -Name 'EUC_MessagingServiceNowIncidentsUrl' -Default ''
        RoomsServiceNowIncidentUrl = Get-EucAutomationValue -Name 'EUC_RoomsServiceNowIncidentUrl' -Default ''
        AzureOpenAIBaseUrl = Get-EucAutomationValue -Name 'EUC_AzureOpenAIBaseUrl' -Default 'https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com'
        AzureOpenAIDeployment = Get-EucAutomationValue -Name 'EUC_AzureOpenAIDeployment' -Default 'gpt-5.4-mini'
        AzureOpenAIApiVersion = Get-EucAutomationValue -Name 'EUC_AzureOpenAIApiVersion' -Default '2025-04-01-preview'
        ServiceNowClientSecretName = Get-EucAutomationValue -Name 'EUC_ServiceNowClientSecretName' -Default 'EndUserConferencing-ServiceNowClientSecret'
        AzureOpenAIApiKeySecretName = Get-EucAutomationValue -Name 'EUC_AzureOpenAIApiKeySecretName' -Default 'EndUserConferencing-AzureOpenAIApiKey'
        DailyLookbackDays  = [int](Get-EucAutomationValue -Name 'EUC_DailyLookbackDays' -Default '2')
        AnalyzerLookbackDays = [int](Get-EucAutomationValue -Name 'EUC_AnalyzerLookbackDays' -Default '7')
        SaveRunArtifacts   = [bool]([int](Get-EucAutomationValue -Name 'EUC_SaveRunArtifacts' -Default '1'))
    }
}

function Write-EucRunbookBanner {
    param([Parameter(Mandatory)] [object]$Context)

    Write-Output "[$(Get-Date -Format 'HH:mm:ss')] EUC runbook start"
    Write-Output "Service  : $($Context.ServiceName)"
    Write-Output "Offering : $($Context.OfferingName)"
    Write-Output "Mode     : $($Context.Mode)"
    Write-Output "Storage  : $($Context.StorageAccountName)"
    Write-Output "Vault    : $($Context.KeyVaultName)"
}

function Invoke-EucRunbook {
    param(
        [Parameter(Mandatory)]
        [string]$OfferingName,
        [Parameter(Mandatory)]
        [ValidateSet('TrendBackfill','Analyzer')]
        [string]$Mode,
        [string]$Notes = ''
    )

    return Invoke-EucRunbookReal -OfferingName $OfferingName -Mode $Mode
}

function Get-EucTemplateContent {
    param(
        [Parameter(Mandatory)]
        [object]$Context,
        [Parameter(Mandatory)]
        [string]$FileName
    )

    $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $localFolder = switch ($Context.OfferingName) {
        'Messaging - Teams Chat and Audio' { Join-Path $repoRoot 'end-user-conferencing\templates\messaging-teams-chat-audio' }
        'Meetings - Rooms and Hardware' { Join-Path $repoRoot 'end-user-conferencing\templates\meetings-rooms-hardware' }
        default { $null }
    }

    if ($localFolder) {
        $localPath = Join-Path $localFolder $FileName
        if (Test-Path $localPath) {
            return Get-Content -Path $localPath -Raw -Encoding UTF8
        }
    }

    $blobName = switch ($Context.OfferingName) {
        'Messaging - Teams Chat and Audio' { "messaging-teams-chat-audio/$FileName" }
        'Meetings - Rooms and Hardware' { "meetings-rooms-hardware/$FileName" }
        default { $FileName }
    }

    $storageAccountName = $Context.StorageAccountName
    $resourceGroupName = $Context.ResourceGroupName
    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName)[0].Value
    $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey
    $tempFile = Join-Path $env:TEMP ([guid]::NewGuid().ToString('N') + '_' + $FileName)
    Get-AzStorageBlobContent -Container $Context.TemplateContainer -Blob $blobName -Destination $tempFile -Context $storageContext -Force | Out-Null
    try {
        return Get-Content -Path $tempFile -Raw -Encoding UTF8
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-EucServiceNowToken {
    param([object]$Context)

    $clientSecret = $null
    $vaultName = Get-EucAutomationValue -Name 'EUC_KeyVaultName' -Default $Context.KeyVaultName
    if (-not [string]::IsNullOrWhiteSpace($vaultName)) {
        try {
            $secretObj = Get-AzKeyVaultSecret -VaultName $vaultName -Name $Context.ServiceNowClientSecretName -ErrorAction Stop
            if ($secretObj -and $secretObj.SecretValue) {
                $clientSecret = [System.Net.NetworkCredential]::new('', $secretObj.SecretValue).Password
            }
        } catch {
            $clientSecret = $null
        }
    }
    if ([string]::IsNullOrWhiteSpace($clientSecret)) {
        $clientSecret = Get-EucAutomationValue -Name $Context.ServiceNowClientSecretName -Default ''
    }
    if ([string]::IsNullOrWhiteSpace($clientSecret)) {
        throw "ServiceNow client secret is missing from automation variables or Key Vault."
    }

    $response = Invoke-RestMethod -Method Post -Uri $Context.ServiceNowTokenUrl -ContentType 'application/x-www-form-urlencoded' -Body @{
        grant_type    = 'client_credentials'
        client_id     = $Context.ServiceNowClientId
        client_secret = $clientSecret
        scope         = $Context.ServiceNowScope
    }

    return [string]$response.access_token
}

function Get-EucOpenAiApiKey {
    param([object]$Context)

    $apiKey = $null
    $vaultName = Get-EucAutomationValue -Name 'EUC_KeyVaultName' -Default $Context.KeyVaultName
    if (-not [string]::IsNullOrWhiteSpace($vaultName)) {
        try {
            $secretObj = Get-AzKeyVaultSecret -VaultName $vaultName -Name $Context.AzureOpenAIApiKeySecretName -ErrorAction Stop
            if ($secretObj -and $secretObj.SecretValue) {
                $apiKey = [System.Net.NetworkCredential]::new('', $secretObj.SecretValue).Password
            }
        } catch {
            $apiKey = $null
        }
    }
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        $apiKey = Get-EucAutomationValue -Name $Context.AzureOpenAIApiKeySecretName -Default ''
    }
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "Azure OpenAI API key is missing from automation variables or Key Vault."
    }

    return $apiKey
}

function Get-EucIncidents {
    param(
        [object]$Context,
        [string]$Token,
        [int]$LookbackDays
    )

    $endDate = (Get-Date).ToUniversalTime()
    $startDate = $endDate.AddDays(-([math]::Max($LookbackDays, 1)))
    $startStr = $startDate.ToString('yyyy-MM-dd HH:mm:ss')
    $endStr = $endDate.ToString('yyyy-MM-dd HH:mm:ss')
    $serviceOfferingId = switch ($Context.OfferingName) {
        'Messaging - Teams Chat and Audio' { $Context.MessagingOfferingId }
        'Meetings - Rooms and Hardware' { $Context.RoomsOfferingId }
        default { '' }
    }

    $directUrl = switch ($Context.OfferingName) {
        'Messaging - Teams Chat and Audio' { $Context.MessagingServiceNowIncidentsUrl }
        'Meetings - Rooms and Hardware' { $Context.RoomsServiceNowIncidentUrl }
        default { '' }
    }

    if (-not [string]::IsNullOrWhiteSpace($directUrl)) {
        $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
        if ($directUrl -match 'sysparm_query=') {
            $response = Invoke-RestMethod -Method Get -Uri $directUrl -Headers $headers -TimeoutSec 180
            return @($response.result)
        }

        if ($directUrl -match 'sys_id=([0-9a-fA-F]{32})') {
            $incidentSysId = $matches[1]
            $url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=sys_id=$incidentSysId&sysparm_display_value=true&sysparm_limit=1"
            $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -TimeoutSec 180
            return @($response.result)
        }
    }

    if ([string]::IsNullOrWhiteSpace($Context.BusinessServiceId) -or [string]::IsNullOrWhiteSpace($serviceOfferingId)) {
        throw "Missing business service or service offering id for $($Context.OfferingName)."
    }

    $query = "business_service=$($Context.BusinessServiceId)^service_offering=$serviceOfferingId^stateIN6,7^resolved_at>=$startStr^resolved_at<=$endStr^ORDERBYDESCresolved_at"
    $url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$([uri]::EscapeDataString($query))&sysparm_display_value=true&sysparm_limit=1000"
    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
    $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -TimeoutSec 180
    return @($response.result)
}

function Invoke-EucAnalysis {
    param(
        [object]$Context,
        [string]$IncidentJson,
        [string]$TemplateContent
    )

    $apiKey = Get-EucOpenAiApiKey -Context $Context
    $url = "$($Context.AzureOpenAIBaseUrl)/openai/deployments/$($Context.AzureOpenAIDeployment)/chat/completions?api-version=$($Context.AzureOpenAIApiVersion)"
    $messages = @(
        @{ role = 'system'; content = $TemplateContent },
        @{ role = 'user'; content = $IncidentJson }
    )
    $body = @{ messages = $messages; max_completion_tokens = 1600 } | ConvertTo-Json -Depth 10
    $headers = @{ 'api-key' = $apiKey; 'Content-Type' = 'application/json' }
    $response = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body -TimeoutSec 180
    return [string]$response.choices[0].message.content
}

function Get-EucAnalysisFields {
    param([string]$Text)

    $result = [ordered]@{
        PrimaryCategory = ''
        Subsymptom = ''
        PossibleRootCause = ''
        ConfidenceLevel = ''
        AIAnalysis = ''
    }

    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^(Primary Category|Sub-symptom|Possible Root Cause|Confidence Level|AI Analysis):\s*(.*)$') {
            $key = $matches[1]
            $value = $matches[2].Trim()
            switch ($key) {
                'Primary Category' { $result.PrimaryCategory = $value }
                'Sub-symptom' { $result.Subsymptom = $value }
                'Possible Root Cause' { $result.PossibleRootCause = $value }
                'Confidence Level' { $result.ConfidenceLevel = $value }
                'AI Analysis' { $result.AIAnalysis = $value }
            }
        }
    }

    return [pscustomobject]$result
}

function Invoke-EucRunbookReal {
    param(
        [string]$OfferingName,
        [string]$Mode
    )

    $context = Get-EucRunbookContext -OfferingName $OfferingName -Mode $Mode
    Write-EucRunbookBanner -Context $context

    $lookbackDays = if ($Mode -eq 'Analyzer') { $context.AnalyzerLookbackDays } else { $context.DailyLookbackDays }
    $templateFiles = switch ($OfferingName) {
        'Messaging - Teams Chat and Audio' {
            @(
                'TicketCategorisation_EndUserConferencing_Messaging.md',
                'EnvironmentContext_EndUserConferencing_Messaging.md',
                'TrendSubCategorisation_EndUserConferencing_Messaging.md',
                'PossibleRootCause_EndUserConferencing_Messaging.md'
            )
        }
        'Meetings - Rooms and Hardware' {
            @(
                'TicketCategorisation_EndUserConferencing_Rooms.md',
                'EnvironmentContext_EndUserConferencing_Rooms.md',
                'TrendSubCategorisation_EndUserConferencing_Rooms.md',
                'PossibleRootCause_EndUserConferencing_Rooms.md'
            )
        }
        default { @() }
    }

    $templateContent = ($templateFiles | ForEach-Object { Get-EucTemplateContent -Context $context -FileName $_ }) -join "`n`n"
    $token = Get-EucServiceNowToken -Context $context
    $incidents = Get-EucIncidents -Context $context -Token $token -LookbackDays $lookbackDays

    Write-Output "Fetched $($incidents.Count) incident(s) for $OfferingName in the last $lookbackDays day(s)."

    $results = foreach ($incident in $incidents) {
        $incidentJson = [pscustomobject]@{
            number = $incident.number
            short_description = $incident.short_description
            description = $incident.description
            work_notes = $incident.work_notes
            close_notes = $incident.close_notes
            category = $incident.category
            subcategory = $incident.subcategory
            state = $incident.state
            resolved_at = $incident.resolved_at
            opened_at = $incident.opened_at
            assignment_group = $incident.assignment_group
        } | ConvertTo-Json -Depth 6 -Compress

        $analysisText = Invoke-EucAnalysis -Context $context -IncidentJson $incidentJson -TemplateContent $templateContent
        $parsed = Get-EucAnalysisFields -Text $analysisText
        [pscustomobject]@{
            IncidentNumber     = $incident.number
            ShortDescription   = $incident.short_description
            OfferingName       = $OfferingName
            PrimaryCategory    = $parsed.PrimaryCategory
            Subsymptom         = $parsed.Subsymptom
            PossibleRootCause  = $parsed.PossibleRootCause
            ConfidenceLevel    = $parsed.ConfidenceLevel
            AIAnalysis         = $parsed.AIAnalysis
            RawResponse        = $analysisText
        }
    }

    if ($context.SaveRunArtifacts) {
        $artifactPath = Join-Path $env:TEMP ("euc_{0}_{1}.json" -f ($OfferingName -replace '\s','_'), (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $results | ConvertTo-Json -Depth 10 | Set-Content -Path $artifactPath -Encoding UTF8
        Write-Output "Saved analysis artifact: $artifactPath"
    }

    return $results
}
