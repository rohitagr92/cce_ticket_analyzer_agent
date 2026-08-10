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

function Get-EucFieldText {
    param([object]$Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return $Value }

    $displayValueProp = $Value.PSObject.Properties['display_value']
    if ($displayValueProp -and -not [string]::IsNullOrWhiteSpace([string]$displayValueProp.Value)) {
        return [string]$displayValueProp.Value
    }

    $valueProp = $Value.PSObject.Properties['value']
    if ($valueProp -and -not [string]::IsNullOrWhiteSpace([string]$valueProp.Value)) {
        return [string]$valueProp.Value
    }

    return [string]$Value
}

function Test-EucRoomsProactiveUnassignedIncident {
    param(
        [Parameter(Mandatory)][string]$OfferingName,
        [Parameter(Mandatory)][object]$Incident
    )

    if ($OfferingName -ne 'Meetings - Rooms and Hardware') {
        return $false
    }

    $channelCandidates = @(
        (Get-EucFieldText -Value $Incident.contact_type),
        (Get-EucFieldText -Value $Incident.u_channel),
        (Get-EucFieldText -Value $Incident.channel),
        (Get-EucFieldText -Value $Incident.u_contact_channel)
    )

    $channel = ($channelCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    $assignedTo = Get-EucFieldText -Value $Incident.assigned_to

    $isProactiveSystemAlert = [string]::Equals(([string]$channel).Trim(), 'Proactive System Alert', [System.StringComparison]::OrdinalIgnoreCase)
    $isAssignedToEmpty = [string]::IsNullOrWhiteSpace([string]$assignedTo)

    return ($isProactiveSystemAlert -and $isAssignedToEmpty)
}

function Apply-EucOfferingIncidentExclusions {
    param(
        [Parameter(Mandatory)][string]$OfferingName,
        [Parameter(Mandatory)][object[]]$Incidents
    )

    if ($OfferingName -ne 'Meetings - Rooms and Hardware') {
        return [pscustomobject]@{
            Included = @($Incidents)
            ExcludedCount = 0
        }
    }

    $included = New-Object System.Collections.Generic.List[object]
    $excludedCount = 0

    foreach ($incident in @($Incidents)) {
        if (Test-EucRoomsProactiveUnassignedIncident -OfferingName $OfferingName -Incident $incident) {
            $excludedCount++
            continue
        }

        [void]$included.Add($incident)
    }

    return [pscustomobject]@{
        Included = $included.ToArray()
        ExcludedCount = $excludedCount
    }
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

    $incidents = @()
    if (-not [string]::IsNullOrWhiteSpace($directUrl)) {
        $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
        if ($directUrl -match 'sysparm_query=') {
            $response = Invoke-RestMethod -Method Get -Uri $directUrl -Headers $headers -TimeoutSec 180
            $incidents = @($response.result)
        }

        elseif ($directUrl -match 'sys_id=([0-9a-fA-F]{32})') {
            $incidentSysId = $matches[1]
            $url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=sys_id=$incidentSysId&sysparm_display_value=true&sysparm_limit=1"
            $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -TimeoutSec 180
            $incidents = @($response.result)
        }

        if ($incidents.Count -gt 0) {
            $filtered = Apply-EucOfferingIncidentExclusions -OfferingName $Context.OfferingName -Incidents $incidents
            if ($filtered.ExcludedCount -gt 0) {
                Write-Output "Excluded $($filtered.ExcludedCount) incident(s) for $($Context.OfferingName) where Channel='Proactive System Alert' and Assigned To is empty."
            }
            return @($filtered.Included)
        }
    }

    if ([string]::IsNullOrWhiteSpace($Context.BusinessServiceId) -or [string]::IsNullOrWhiteSpace($serviceOfferingId)) {
        throw "Missing business service or service offering id for $($Context.OfferingName)."
    }

    $query = "business_service=$($Context.BusinessServiceId)^service_offering=$serviceOfferingId^stateIN6,7^resolved_at>=$startStr^resolved_at<=$endStr^ORDERBYDESCresolved_at"
    $url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$([uri]::EscapeDataString($query))&sysparm_display_value=true&sysparm_limit=1000"
    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
    $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -TimeoutSec 180
    $incidents = @($response.result)
    $filtered = Apply-EucOfferingIncidentExclusions -OfferingName $Context.OfferingName -Incidents $incidents
    if ($filtered.ExcludedCount -gt 0) {
        Write-Output "Excluded $($filtered.ExcludedCount) incident(s) for $($Context.OfferingName) where Channel='Proactive System Alert' and Assigned To is empty."
    }
    return @($filtered.Included)
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

function Get-EucSectionValue {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string[]]$AllLabels
    )

    $trimmed = ([string]$Text).Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return '' }

    $otherLabels = @($AllLabels | Where-Object { $_ -ne $Label })
    $escapedLabel = [regex]::Escape($Label)
    $nextPattern = if ($otherLabels.Count -gt 0) {
        ($otherLabels | ForEach-Object { [regex]::Escape($_) }) -join '|'
    } else {
        '$^'
    }

    $pattern = '(?is)(?:^|\n)\s*\*{0,2}' + $escapedLabel + '\*{0,2}\s*:\s*(?<value>.*?)(?=\n\s*\*{0,2}(?:' + $nextPattern + ')\*{0,2}\s*:|\z)'
    $match = [regex]::Match($trimmed, $pattern)
    if (-not $match.Success) { return '' }

    return $match.Groups['value'].Value.Trim()
}

function Get-EucNormalizedConfidence {
    param([string]$Raw)

    $v = ([string]$Raw).Trim().ToLowerInvariant()
    if ($v -match '\bhigh\b') { return 'High' }
    if ($v -match '\bmedium\b') { return 'Medium' }
    if ($v -match '\blow\b') { return 'Low' }
    return 'Medium'
}

function Convert-EucToAscii {
    param([string]$Text)

    $v = [string]$Text
    if ([string]::IsNullOrWhiteSpace($v)) { return '' }

    $v = $v -replace '[\u2018\u2019\u2032]', "'"
    $v = $v -replace '[\u201C\u201D\u2033]', '"'
    $v = $v -replace '[\u2013\u2014]', '-'
    $v = $v -replace '\u00A0', ' '
    $v = $v -replace '[^\x09\x0A\x0D\x20-\x7E]', ''

    return $v.Trim()
}

function Format-EucStructuredAiAnalysis {
    param(
        [Parameter(Mandatory)][object]$Fields,
        [string]$RawResponse = ''
    )

    $issue = ([string]$Fields.Issue).Trim()
    if ([string]::IsNullOrWhiteSpace($issue)) { $issue = ([string]$Fields.Subsymptom).Trim() }
    if ([string]::IsNullOrWhiteSpace($issue)) { $issue = 'Not documented in work notes.' }
    $issue = Convert-EucToAscii -Text $issue

    $rootCause = ([string]$Fields.RootCauseNarrative).Trim()
    if ([string]::IsNullOrWhiteSpace($rootCause)) { $rootCause = ([string]$Fields.PossibleRootCause).Trim() }
    if ([string]::IsNullOrWhiteSpace($rootCause)) { $rootCause = 'Not documented in work notes.' }
    $rootCause = Convert-EucToAscii -Text $rootCause

    $resolution = ([string]$Fields.Resolution).Trim()
    if ([string]::IsNullOrWhiteSpace($resolution)) { $resolution = 'Not documented in work notes.' }
    $resolution = Convert-EucToAscii -Text $resolution

    $evidence = ([string]$Fields.Evidence).Trim()
    if ([string]::IsNullOrWhiteSpace($evidence)) { $evidence = 'Not documented in work notes.' }
    $evidence = Convert-EucToAscii -Text $evidence

    $analysis = ([string]$Fields.AIAnalysis).Trim()
    if ([string]::IsNullOrWhiteSpace($analysis)) { $analysis = ([string]$RawResponse).Trim() }
    if ([string]::IsNullOrWhiteSpace($analysis)) { $analysis = 'Not documented in work notes.' }
    $analysis = Convert-EucToAscii -Text $analysis

    $confidence = Get-EucNormalizedConfidence -Raw ([string]$Fields.ConfidenceLevel)

    return @(
        'Problem:',
        "Issue: $issue",
        "Root Cause: $rootCause",
        "Resolution: $resolution",
        "Evidence: $evidence",
        "AI Analysis ($confidence Confidence): $analysis"
    ) -join "`n"
}

function Get-EucAnalysisFields {
    param([string]$Text)

    $result = [ordered]@{
        PrimaryCategory = ''
        Subsymptom = ''
        PossibleRootCause = ''
        ConfidenceLevel = ''
        Issue = ''
        RootCauseNarrative = ''
        Resolution = ''
        Evidence = ''
        AIAnalysis = ''
    }

    $labels = @(
        'Primary Category',
        'Sub-symptom',
        'Possible Root Cause',
        'Confidence Level',
        'Issue',
        'Root Cause',
        'Root Cause Narrative',
        'Resolution',
        'Evidence',
        'AI Analysis',
        'Reasoning',
        'Key Evidence',
        'Resolution Summary'
    )

    $result.PrimaryCategory = Get-EucSectionValue -Text $Text -Label 'Primary Category' -AllLabels $labels
    $result.Subsymptom = Get-EucSectionValue -Text $Text -Label 'Sub-symptom' -AllLabels $labels
    $result.PossibleRootCause = Get-EucSectionValue -Text $Text -Label 'Possible Root Cause' -AllLabels $labels
    $result.ConfidenceLevel = Get-EucSectionValue -Text $Text -Label 'Confidence Level' -AllLabels $labels
    $result.Issue = Get-EucSectionValue -Text $Text -Label 'Issue' -AllLabels $labels
    $result.RootCauseNarrative = Get-EucSectionValue -Text $Text -Label 'Root Cause' -AllLabels $labels
    if ([string]::IsNullOrWhiteSpace($result.RootCauseNarrative)) {
        $result.RootCauseNarrative = Get-EucSectionValue -Text $Text -Label 'Root Cause Narrative' -AllLabels $labels
    }
    $result.Resolution = Get-EucSectionValue -Text $Text -Label 'Resolution' -AllLabels $labels
    if ([string]::IsNullOrWhiteSpace($result.Resolution)) {
        $result.Resolution = Get-EucSectionValue -Text $Text -Label 'Resolution Summary' -AllLabels $labels
    }
    $result.Evidence = Get-EucSectionValue -Text $Text -Label 'Evidence' -AllLabels $labels
    if ([string]::IsNullOrWhiteSpace($result.Evidence)) {
        $result.Evidence = Get-EucSectionValue -Text $Text -Label 'Key Evidence' -AllLabels $labels
    }
    $result.AIAnalysis = Get-EucSectionValue -Text $Text -Label 'AI Analysis' -AllLabels $labels
    if ([string]::IsNullOrWhiteSpace($result.AIAnalysis)) {
        $result.AIAnalysis = Get-EucSectionValue -Text $Text -Label 'Reasoning' -AllLabels $labels
    }

    if ([string]::IsNullOrWhiteSpace($result.ConfidenceLevel)) {
        $confidenceFromAi = [regex]::Match([string]$Text, '(?is)AI\s*Analysis\s*\((?<conf>[^)]*?)\s*confidence\)')
        if ($confidenceFromAi.Success) {
            $result.ConfidenceLevel = $confidenceFromAi.Groups['conf'].Value.Trim()
        }
    }

    $result.ConfidenceLevel = Get-EucNormalizedConfidence -Raw ([string]$result.ConfidenceLevel)

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
        $structuredAi = Format-EucStructuredAiAnalysis -Fields $parsed -RawResponse $analysisText
        [pscustomobject]@{
            IncidentNumber     = $incident.number
            ShortDescription   = $incident.short_description
            OfferingName       = $OfferingName
            PrimaryCategory    = $parsed.PrimaryCategory
            Subsymptom         = $parsed.Subsymptom
            PossibleRootCause  = $parsed.PossibleRootCause
            ConfidenceLevel    = $parsed.ConfidenceLevel
            AIAnalysis         = $structuredAi
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
