[CmdletBinding()]
param(
    [int]$MaxIncidents = 0,
    [int]$LookbackDays = 21,
    [int]$TargetYear = 0,
    [int]$TargetWeek = 0,
    [switch]$IncludeAllStates,
    [switch]$IncludeAssignmentGroupCriteria,
    [string]$TargetBusinessService = 'End-User Collaboration',
    [string]$TargetServiceOffering = 'Productivity Tools',
    [string]$TargetBusinessServiceId = 'a1de2ff2db8f50108062531dd3961911',
    [string]$TargetServiceOfferingId = 'fcb18407dbcf50108062531dd39619c4',
    [switch]$UseStoredIncidents,
    [string]$StoredIncidentsPath,
    [switch]$ForceRefreshIncidents = $true,
    [int]$SnapshotMaxAgeHours = 1,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $script:RepoRoot 'local-output\productivity-tools-analysis'
}

$script:TemplateFileMap = @{
    Environment          = 'templates\new_template\RootCause_EnvironmentContext.md'
    WorkNotesSummary     = 'templates\new_template\RootCause_WorkNotesSummary.md'
    WorkNotesCleanup     = 'templates\ProductivityTools_WorkNotesCleanup.md'
    TicketCategorisation = 'templates\new_template\RootCause_TicketCategorisation.md'
    PortfolioSummary     = 'templates\new_template\RootCause_PortfolioSummary.md'
}

function Write-Step {
    param(
        [string]$Message,
        [string]$Color = 'Cyan'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host ([string]::Format('[{0}] {1}', $timestamp, $Message)) -ForegroundColor $Color
}

function Get-DisplayValue {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value }
    if ($Value.PSObject.Properties['display_value']) { return [string]$Value.display_value }
    if ($Value.PSObject.Properties['value']) { return [string]$Value.value }
    return [string]$Value
}

function Merge-Hashtable {
    param(
        [hashtable]$Base,
        [hashtable]$Override
    )

    $merged = @{}
    foreach ($key in $Base.Keys) {
        $merged[$key] = $Base[$key]
    }
    foreach ($key in $Override.Keys) {
        $merged[$key] = $Override[$key]
    }
    return $merged
}

function Load-LocalConfiguration {
    $configPath = Join-Path $script:RepoRoot 'config\LocalConfig.psd1'
    $secretsPath = Join-Path $script:RepoRoot 'config\LocalSecrets.psd1'

    if (-not (Test-Path $configPath)) {
        throw 'Missing config/LocalConfig.psd1.'
    }

    if (-not (Test-Path $secretsPath)) {
        throw 'Missing config/LocalSecrets.psd1.'
    }

    $config = Import-PowerShellDataFile -Path $configPath
    $secrets = Import-PowerShellDataFile -Path $secretsPath
    $merged = Merge-Hashtable -Base $config -Override $secrets

    $requiredKeys = @(
        'ServiceNowIncidentsClientID',
        'ServiceNowIncidentsClientSecret',
        'ServiceNowIncidentsScope',
        'TokenUrl',
        'ServiceNowIncidentsURL'
    )

    $requiredKeys += @(
        'AzureOpenAIBaseUrl',
        'AzureOpenAIModel',
        'AzureOpenAIApiKey',
        'AzureOpenAIApiVersion'
    )

    foreach ($requiredKey in $requiredKeys) {
        if (-not $merged.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace([string]$merged[$requiredKey])) {
            throw ([string]::Format('Configuration value {0} is missing.', $requiredKey))
        }
    }

    return $merged
}

function Get-OutputDirectory {
    param([string]$PathName)

    $directoryPath = if ([string]::IsNullOrWhiteSpace($PathName)) {
        $OutputRoot
    } else {
        Join-Path $OutputRoot $PathName
    }

    if (-not (Test-Path $directoryPath)) {
        New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null
    }

    return $directoryPath
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory)]
        [object]$Data,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $json = $Data | ConvertTo-Json -Depth 20
    Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Get-IncidentSnapshotCachePath {
    $cacheDirectory = Join-Path $script:RepoRoot 'local-output\cache'
    if (-not (Test-Path $cacheDirectory)) {
        New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
    }

    return (Join-Path $cacheDirectory 'productivitytools_incidents_snapshot.json')
}

function Try-LoadIncidentSnapshot {
    param(
        [int]$RequestedLookbackDays,
        [int]$MaxAgeHours
    )

    $cachePath = Get-IncidentSnapshotCachePath
    if (-not (Test-Path $cachePath)) {
        return $null
    }

    try {
        $snapshot = Get-Content -Path $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $snapshot -or $null -eq $snapshot.incidents) {
            return $null
        }

        if ($snapshot.lookback_days -lt $RequestedLookbackDays) {
            return $null
        }

        if ($MaxAgeHours -gt 0) {
            $savedAt = Get-Date ([string]$snapshot.saved_at_utc)
            $ageHours = ((Get-Date).ToUniversalTime() - $savedAt.ToUniversalTime()).TotalHours
            if ($ageHours -gt $MaxAgeHours) {
                return $null
            }
        }

        Write-Step ([string]::Format('Using cached incident snapshot: {0}', $cachePath)) 'Yellow'
        return @($snapshot.incidents)
    } catch {
        Write-Step ([string]::Format('Incident snapshot cache could not be read. Falling back to live fetch. Error: {0}', $_.Exception.Message)) 'Yellow'
        return $null
    }
}

function Save-IncidentSnapshot {
    param(
        [array]$Incidents,
        [int]$LookbackDaysValue
    )

    $cachePath = Get-IncidentSnapshotCachePath
    $payload = [PSCustomObject]@{
        saved_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        lookback_days = $LookbackDaysValue
        incident_count = @($Incidents).Count
        incidents = @($Incidents)
    }

    Save-JsonFile -Data $payload -Path $cachePath
    Write-Step ([string]::Format('Updated incident snapshot cache: {0}', $cachePath)) 'Yellow'
}

function Get-TemplateText {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,
        [string]$FallbackText = ''
    )

    $templatePath = Join-Path $script:RepoRoot $RelativePath
    if (Test-Path $templatePath) {
        return (Get-Content -Path $templatePath -Raw -Encoding UTF8)
    }

    if (-not [string]::IsNullOrWhiteSpace($FallbackText)) {
        return $FallbackText
    }

    return ''
}

function Get-TemplateBundle {
    [CmdletBinding()]
    param()

    return @{
        Environment = Get-TemplateText -RelativePath $script:TemplateFileMap.Environment
        WorkNotesSummary = Get-TemplateText -RelativePath $script:TemplateFileMap.WorkNotesSummary
        WorkNotesCleanup = Get-TemplateText -RelativePath $script:TemplateFileMap.WorkNotesCleanup
        TicketCategorisation = Get-TemplateText -RelativePath $script:TemplateFileMap.TicketCategorisation
        PortfolioSummary = Get-TemplateText -RelativePath $script:TemplateFileMap.PortfolioSummary
    }
}

function Limit-TextLength {
    param(
        [string]$Text,
        [int]$MaxLength = 4000
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    if ($Text.Length -le $MaxLength) {
        return $Text
    }

    return $Text.Substring(0, $MaxLength)
}

function Get-ServiceNowAccessToken {
    param([hashtable]$Config)

    $tokenBody = @{
        grant_type = 'client_credentials'
        client_id = $Config.ServiceNowIncidentsClientID
        client_secret = $Config.ServiceNowIncidentsClientSecret
        scope = $Config.ServiceNowIncidentsScope
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri $Config.TokenUrl -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'
    return $tokenResponse.access_token
}

function Get-ServiceNowIncidents {
    param(
        [hashtable]$Config,
        [int]$LookbackDaysValue = 21,
        [int]$TargetYearValue = 0,
        [int]$TargetWeekValue = 0
    )

    Write-Step 'Requesting ServiceNow OAuth token...'
    $token = Get-ServiceNowAccessToken -Config $Config
    $headers = @{
        Authorization = 'Bearer ' + $token
        Accept = 'application/json'
    }

    $incidentUrl = [string]$Config.ServiceNowIncidentsURL
    if (-not $IncludeAssignmentGroupCriteria) {
        $incidentUrl = $incidentUrl -replace 'assignment_group=[^^]+\^', ''
        Write-Step 'Assignment group restriction removed from fetch URL (service-based filtering only).' 'Yellow'
    }
    if ($IncludeAllStates) {
        $incidentUrl = $incidentUrl -replace '\^state=6\^ORstate=7', ''
        Write-Step 'IncludeAllStates is enabled: fetching incidents without state=6/7 restriction.' 'Yellow'
    } else {
        $incidentUrl = $incidentUrl -replace '\^state=6\^ORstate=7', ''
        if ($incidentUrl -match 'sysparm_query=([^&]*)') {
            $existingQuery = $Matches[1]
            if ($existingQuery -notmatch 'stateIN6,7') {
                $existingQuery = if ([string]::IsNullOrWhiteSpace($existingQuery)) { 'stateIN6,7' } else { [string]::Format('{0}^stateIN6,7', $existingQuery.Trim('^')) }
            }
            $incidentUrl = ($incidentUrl -replace 'sysparm_query=([^&]*)', ([string]::Format('sysparm_query={0}', $existingQuery)))
        }
    }

    if ($incidentUrl -match 'sysparm_query=([^&]*)') {
        $existingQuery = $Matches[1].Trim('^')
        if (-not [string]::IsNullOrWhiteSpace($TargetBusinessServiceId) -and $existingQuery -notmatch 'business_service=') {
            $existingQuery = [string]::Format('{0}^{1}', $existingQuery, [string]::Format('business_service={0}', $TargetBusinessServiceId))
        }
        if (-not [string]::IsNullOrWhiteSpace($TargetServiceOfferingId) -and $existingQuery -notmatch 'service_offering=') {
            $existingQuery = [string]::Format('{0}^{1}', $existingQuery, [string]::Format('service_offering={0}', $TargetServiceOfferingId))
        }

        # Add server-side date filter so we only fetch the required window.
        $fetchDays = if ($TargetYearValue -gt 0 -and $TargetWeekValue -gt 0) { [Math]::Max($LookbackDaysValue, 21) } else { [Math]::Max($LookbackDaysValue, 1) }
        if ($existingQuery -notmatch 'sys_updated_on>=javascript:gs\.daysAgoStart\(') {
            $existingQuery = [string]::Format('{0}^{1}', $existingQuery, [string]::Format('sys_updated_on>=javascript:gs.daysAgoStart({0})', $fetchDays))
            Write-Step ([string]::Format('Applying server-side lookback filter: last {0} day(s).', $fetchDays)) 'Yellow'
        }

        $incidentUrl = ($incidentUrl -replace 'sysparm_query=([^&]*)', ([string]::Format('sysparm_query={0}', $existingQuery)))
    }

    $incidentUrl = if ($incidentUrl -match 'sysparm_limit=') {
        ($incidentUrl -replace 'sysparm_limit=\d+', 'sysparm_limit=1000')
    } else {
        $separator = if ($incidentUrl -match '\?') { '&' } else { '?' }
        [string]::Format('{0}{1}sysparm_limit=1000', $incidentUrl, $separator)
    }

    $allIncidents = New-Object System.Collections.Generic.List[object]
    $offset = 0
    $pageNumber = 0
    $maxPages = 200

    Write-Step 'Fetching Productivity Tools incident feed from ServiceNow (paginated, pre-filtered by date)...'

    do {
        $pageNumber += 1
        $pageUrl = if ($incidentUrl -match 'sysparm_offset=') {
            ($incidentUrl -replace 'sysparm_offset=\d+', [string]::Format('sysparm_offset={0}', $offset))
        } else {
            [string]::Format('{0}&sysparm_offset={1}', $incidentUrl, $offset)
        }

        $response = Invoke-RestMethod -Method Get -Uri $pageUrl -Headers $headers
        $batch = @($response.result)
        foreach ($incident in $batch) {
            $allIncidents.Add($incident)
        }

        $offset += 1000
        Write-Step ([string]::Format('Fetched page {0}: {1} records (total: {2})', $pageNumber, $batch.Count, $allIncidents.Count)) 'DarkCyan'
    } while ($batch.Count -eq 1000 -and $pageNumber -lt $maxPages)

    if ($pageNumber -ge $maxPages) {
        Write-Step ([string]::Format('Reached pagination safety cap ({0} pages). Returning partial results.', $maxPages)) 'Yellow'
    }

    return @($allIncidents.ToArray())
}

function Get-IsoWeekNumber {
    param([DateTime]$DateValue)

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $calendar = $culture.Calendar
    return $calendar.GetWeekOfYear($DateValue, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
}

function Get-WeekStartMonday {
    param([DateTime]$DateValue)

    if ($null -eq $DateValue) {
        return $null
    }

    return $DateValue.Date.AddDays(-1 * (([int]$DateValue.DayOfWeek + 6) % 7))
}

function Get-IsoWeekYear {
    param([DateTime]$DateValue)

    if ($null -eq $DateValue) {
        return 0
    }

    return $DateValue.Date.AddDays(3).Year
}

function Get-IstDateTime {
    try {
        $istTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')
        return [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $istTimeZone)
    } catch {
        return Get-Date
    }
}

function Get-ReportWeekContext {
    param([DateTime]$DateValue = ([DateTime]::MinValue))

    if ($DateValue -eq [DateTime]::MinValue) {
        $DateValue = Get-IstDateTime
    }

    $today = $DateValue.Date
    $calendarCurrentWeekStart = Get-WeekStartMonday -DateValue $today
    $calendarCurrentWeekEnd = $calendarCurrentWeekStart.AddDays(6)
    $useCurrentWeekAnalysis = $today.DayOfWeek -in @([System.DayOfWeek]::Thursday, [System.DayOfWeek]::Friday, [System.DayOfWeek]::Saturday, [System.DayOfWeek]::Sunday)
    $analysisWeekStart = if ($useCurrentWeekAnalysis) { $calendarCurrentWeekStart } else { $calendarCurrentWeekStart.AddDays(-7) }
    $analysisWeekEnd = $analysisWeekStart.AddDays(6)
    $previousWeekStart = $analysisWeekStart.AddDays(-7)
    $previousWeekEnd = $analysisWeekStart.AddDays(-1)
    $olderWeekStart = $analysisWeekStart.AddDays(-14)
    $olderWeekEnd = $analysisWeekStart.AddDays(-8)

    return [PSCustomObject]@{
        UseCurrentWeekAnalysis = $useCurrentWeekAnalysis
        AnalysisLabel = if ($useCurrentWeekAnalysis) { 'Current Week Analysis' } else { 'Last Completed Week Analysis' }
        AnalysisWeekStart = $analysisWeekStart
        AnalysisWeekEnd = $analysisWeekEnd
        PreviousWeekStart = $previousWeekStart
        PreviousWeekEnd = $previousWeekEnd
        OlderWeekStart = $olderWeekStart
        OlderWeekEnd = $olderWeekEnd
        AnalysisWW = Get-IsoWeekNumber -DateValue $analysisWeekStart
        AnalysisYear = Get-IsoWeekYear -DateValue $analysisWeekStart
        PreviousWW = Get-IsoWeekNumber -DateValue $previousWeekStart
        OlderWW = Get-IsoWeekNumber -DateValue $olderWeekStart
        CalendarCurrentWW = Get-IsoWeekNumber -DateValue $calendarCurrentWeekStart
        CalendarCurrentWeekStart = $calendarCurrentWeekStart
        CalendarCurrentWeekEnd = $calendarCurrentWeekEnd
        WindowStart = $previousWeekStart
        WindowEnd = $today
    }
}

function Escape-Html {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $normalized = Normalize-DisplayText -Value $Value
    return $normalized.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function Normalize-DisplayText {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $builder = New-Object System.Text.StringBuilder
    foreach ($ch in ([string]$Value).ToCharArray()) {
        $code = [int][char]$ch

        if ($code -eq 9 -or $code -eq 10 -or $code -eq 13 -or ($code -ge 32 -and $code -le 126)) {
            [void]$builder.Append($ch)
            continue
        }

        switch ($code) {
            8211 { [void]$builder.Append('-'); continue } # en dash
            8212 { [void]$builder.Append('-'); continue } # em dash
            8216 { [void]$builder.Append("'"); continue } # left single quote
            8217 { [void]$builder.Append("'"); continue } # right single quote
            8220 { [void]$builder.Append('"'); continue } # left double quote
            8221 { [void]$builder.Append('"'); continue } # right double quote
            8230 { [void]$builder.Append('...'); continue } # ellipsis
            9650 { [void]$builder.Append('^'); continue } # black up-pointing triangle
            9660 { [void]$builder.Append('v'); continue } # black down-pointing triangle
            9656 { [void]$builder.Append('>'); continue } # black right-pointing small triangle
            default { continue }
        }
    }

    return $builder.ToString()
}

function Get-IncidentDateValue {
    param([psobject]$Incident)

    $candidateFields = @('resolved_at', 'sys_updated_on', 'closed_at', 'opened_at')
    foreach ($fieldName in $candidateFields) {
        $rawValue = $Incident.$fieldName
        if ([string]::IsNullOrWhiteSpace([string]$rawValue)) {
            continue
        }

        try {
            return [DateTime](Get-Date $rawValue)
        } catch {
        }
    }

    return $null
}

function Get-IncidentResolvedDate {
    param([psobject]$Incident)

    $rawValue = [string]$Incident.resolved_at
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        return $null
    }

    try {
        return [DateTime](Get-Date $rawValue)
    } catch {
        return $null
    }
}

function Normalize-ComparisonText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    return ([Regex]::Replace($Value.ToLowerInvariant(), '[^a-z0-9]+', ' ')).Trim()
}

function Test-TextEquivalent {
    param(
        [string]$Left,
        [string]$Right
    )

    return (Normalize-ComparisonText -Value $Left) -eq (Normalize-ComparisonText -Value $Right)
}

function Get-IncidentWorkText {
    param(
        [psobject]$Incident,
        [int]$MaxLength = 12000
    )

    $parts = @()
    foreach ($fieldName in @('description', 'close_notes', 'comments_and_work_notes', 'work_notes', 'comments', 'overview')) {
        $value = $Incident.$fieldName
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            $parts += ([string]::Format('{0}:{1}{1}{2}', $fieldName, [Environment]::NewLine, [string]$value))
        }
    }

    $text = $parts -join ([Environment]::NewLine + [Environment]::NewLine)
    if ($text.Length -gt $MaxLength) {
        return $text.Substring(0, $MaxLength)
    }

    return $text
}

function Get-IncidentCombinedText {
    param([psobject]$Incident)

    $parts = @()
    foreach ($fieldName in @('description', 'close_notes', 'comments_and_work_notes', 'work_notes', 'comments', 'overview', 'short_description')) {
        $value = [string]$Incident.$fieldName
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $parts += $value
        }
    }

    return ($parts -join ([Environment]::NewLine + [Environment]::NewLine))
}

function Get-IncidentUrls {
    param([psobject]$Incident)

    $text = Get-IncidentCombinedText -Incident $Incident
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }

    $urlPattern = 'https?://[^\s"''<>)]+'
    $matches = [System.Text.RegularExpressions.Regex]::Matches($text, $urlPattern)
    if ($null -eq $matches -or $matches.Count -eq 0) {
        return @()
    }

    $urls = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches) {
        $candidate = ([string]$match.Value).Trim()
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $urls.Add($candidate)
        }
    }

    return @($urls | Select-Object -Unique)
}

function Select-ProductivityToolsIncidents {
    param(
        [array]$Incidents,
        [int]$TakeCount,
        [int]$LookbackDaysValue,
        [int]$TargetYearValue = 0,
        [int]$TargetWeekValue = 0,
        [string]$TargetBusinessServiceValue = 'End-User Collaboration',
        [string]$TargetServiceOfferingValue = 'Productivity Tools',
        [bool]$UseAssignmentGroupCriteria = $false
    )

    $filtered = foreach ($incident in $Incidents) {
        $assignmentGroup = Get-DisplayValue $incident.assignment_group
        $serviceOffering = Get-DisplayValue $incident.service_offering
        $businessService = Get-DisplayValue $incident.business_service

        $matchesServiceScope = (
            (Test-TextEquivalent -Left $serviceOffering -Right $TargetServiceOfferingValue) -and
            (Test-TextEquivalent -Left $businessService -Right $TargetBusinessServiceValue)
        )

        $matchesAssignmentScope = ((Normalize-ComparisonText -Value $assignmentGroup) -like 'productivity tools*')

        if ($matchesServiceScope -or ($UseAssignmentGroupCriteria -and $matchesAssignmentScope)) {
            $incident
        }
    }

    if ($LookbackDaysValue -gt 0) {
        $cutoff = (Get-Date).AddDays(-1 * $LookbackDaysValue)
        $filtered = @($filtered | Where-Object {
            $incidentDate = Get-IncidentResolvedDate $_
            $incidentDate -and $incidentDate -ge $cutoff
        })
    }

    if ($TargetYearValue -gt 0 -and $TargetWeekValue -gt 0) {
        $filtered = @($filtered | Where-Object {
            $incidentDate = Get-IncidentResolvedDate $_
            if (-not $incidentDate) { return $false }
            $weekNumber = Get-IsoWeekNumber -DateValue $incidentDate
            $weekYear = Get-IsoWeekYear -DateValue $incidentDate
            ($weekYear -eq $TargetYearValue) -and ($weekNumber -eq $TargetWeekValue)
        })
    }

    $sorted = @($filtered | Sort-Object -Property @{ Expression = {
        $resolvedDate = Get-IncidentResolvedDate $_
        if ($resolvedDate) { return $resolvedDate }
        return (Get-IncidentDateValue $_)
    } ; Descending = $true })
    if ($TakeCount -gt 0 -and $sorted.Count -gt $TakeCount) {
        return @($sorted | Select-Object -First $TakeCount)
    }

    return @($sorted)
}

function Get-AzureResponsesEndpoint {
    param([hashtable]$Config)

    return ([string]::Format('{0}/openai/responses?api-version={1}', $Config.AzureOpenAIBaseUrl.TrimEnd('/'), $Config.AzureOpenAIApiVersion))
}

function Get-AIEndpoint {
    param([hashtable]$Config)

    return (Get-AzureResponsesEndpoint -Config $Config)
}

function Get-AIResponseText {
    param([object]$Response)

    if ($null -eq $Response) { return $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$Response.output_text)) {
        return [string]$Response.output_text
    }

    if ($Response.output) {
        $segments = New-Object System.Collections.Generic.List[string]
        foreach ($outputItem in @($Response.output)) {
            if (-not $outputItem.content) { continue }
            foreach ($contentItem in @($outputItem.content)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$contentItem.text)) {
                    $segments.Add([string]$contentItem.text)
                }
            }
        }

        if ($segments.Count -gt 0) {
            return ($segments -join [Environment]::NewLine)
        }
    }

    return $null
}

function Convert-TextToJsonObject {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw 'AI response was empty.'
    }

    try {
        return ($Text | ConvertFrom-Json)
    } catch {
        $startIndex = $Text.IndexOf('{')
        $endIndex = $Text.LastIndexOf('}')
        if ($startIndex -ge 0 -and $endIndex -gt $startIndex) {
            $jsonSlice = $Text.Substring($startIndex, ($endIndex - $startIndex + 1))
            return ($jsonSlice | ConvertFrom-Json)
        }
        throw
    }
}

function Invoke-AzureJsonAnalysis {
    param(
        [hashtable]$Config,
        [string]$Instructions,
        [string]$Prompt,
        [int]$MaxOutputTokens = 1400
    )

    $headers = @{
        'api-key' = $Config.AzureOpenAIApiKey
        'Content-Type' = 'application/json; charset=utf-8'
    }

    # PowerShell 5.1 ConvertTo-Json does not escape bare \r (carriage return) characters,
    # which produces invalid JSON. Strip them here so only \n remains as the line separator.
    $cleanInstructions = $Instructions -replace "`r", ''
    $cleanPrompt       = $Prompt       -replace "`r", ''

    $body = @{
        model = $Config.AzureOpenAIModel
        instructions = $cleanInstructions
        input = $cleanPrompt
        max_output_tokens = $MaxOutputTokens
        store = $false
    } | ConvertTo-Json -Depth 10

    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $response = Invoke-RestMethod -Method Post -Uri (Get-AIEndpoint -Config $Config) -Headers $headers -Body $bodyBytes

    $responseText = Get-AIResponseText -Response $response
    return Convert-TextToJsonObject -Text $responseText
}

function Invoke-AzureTextResponse {
    param(
        [hashtable]$Config,
        [string]$Instructions,
        [string]$Prompt,
        [int]$MaxOutputTokens = 1400
    )

    $headers = @{
        'api-key' = $Config.AzureOpenAIApiKey
        'Content-Type' = 'application/json; charset=utf-8'
    }

    $cleanInstructions = $Instructions -replace "`r", ''
    $cleanPrompt       = $Prompt       -replace "`r", ''

    $body = @{
        model = $Config.AzureOpenAIModel
        instructions = $cleanInstructions
        input = $cleanPrompt
        max_output_tokens = $MaxOutputTokens
        store = $false
    } | ConvertTo-Json -Depth 10

    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $response = Invoke-RestMethod -Method Post -Uri (Get-AIEndpoint -Config $Config) -Headers $headers -Body $bodyBytes

    return (Get-AIResponseText -Response $response)
}

function Invoke-WorkNotesCleanup {
    param(
        [hashtable]$Config,
        [psobject]$Incident,
        [hashtable]$TemplateBundle
    )

    if (-not $TemplateBundle -or [string]::IsNullOrWhiteSpace([string]$TemplateBundle.WorkNotesCleanup)) {
        return $null
    }

    $rawNotes = [string]$Incident.work_notes
    if ([string]::IsNullOrWhiteSpace($rawNotes)) {
        $rawNotes = [string]$Incident.comments_and_work_notes
    }
    if ([string]::IsNullOrWhiteSpace($rawNotes)) { return $null }

    $rawNotes = Limit-TextLength -Text $rawNotes -MaxLength 12000

    $instructions = (Limit-TextLength -Text $TemplateBundle.WorkNotesCleanup -MaxLength 4000)
    $prompt = [string]::Format('Incident: {0}{1}{1}Service Desk Notes:{1}{1}{2}', [string]$Incident.number, [Environment]::NewLine, $rawNotes)

    try {
        $text = Invoke-AzureTextResponse -Config $Config -Instructions $instructions -Prompt $prompt -MaxOutputTokens 1200
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        # Strip ServiceNow-style [code]...[/code] wrappers and HTML markup that the LLM preserves verbatim.
        $text = [regex]::Replace($text, '(?is)\[code\](.*?)\[/code\]', '$1')
        $text = [regex]::Replace($text, '(?is)<style\b[^>]*>.*?</style>', ' ')
        $text = [regex]::Replace($text, '(?is)<script\b[^>]*>.*?</script>', ' ')
        $text = [regex]::Replace($text, '<[^>]+>', ' ')
        $text = [System.Net.WebUtility]::HtmlDecode($text)
        $text = [regex]::Replace($text, '[ \t]+', ' ')
        $text = [regex]::Replace($text, '(?m)^[ \t]+', '')
        $text = [regex]::Replace($text, '\n{3,}', "`n`n")
        return $text.Trim()
    } catch {
        Write-Step ([string]::Format('Work notes cleanup failed for {0}: {1}', [string]$Incident.number, $_.Exception.Message)) 'Yellow'
        return $null
    }
}

function New-IncidentPrompt {
    param(
        [psobject]$Incident,
        [int]$MaxDetailLength = 12000
    )

    $incidentDate = Get-IncidentDateValue -Incident $Incident
    $payload = [PSCustomObject]@{
        incident_number = [string]$Incident.number
        short_description = [string]$Incident.short_description
        service_offering = Get-DisplayValue $Incident.service_offering
        assignment_group = Get-DisplayValue $Incident.assignment_group
        business_service = Get-DisplayValue $Incident.business_service
        resolution_category = [string]$Incident.u_resolution_category
        category = [string]$Incident.category
        subcategory = [string]$Incident.subcategory
        resolved_at = if ($incidentDate) { $incidentDate.ToString('s') } else { $null }
        details = Get-IncidentWorkText -Incident $Incident -MaxLength $MaxDetailLength
        evidence_context = [PSCustomObject]@{
            url_count = @(Get-IncidentUrls -Incident $Incident).Count
            sample_urls = @((Get-IncidentUrls -Incident $Incident) | Select-Object -First 5)
        }
    }

    return ($payload | ConvertTo-Json -Depth 10)
}

function New-FallbackIncidentAnalysis {
    param(
        [psobject]$Incident,
        [string]$FailureReason
    )

    return [PSCustomObject]@{
        incident_number = [string]$Incident.number
        application_or_area = if ([string]::IsNullOrWhiteSpace((Get-DisplayValue $Incident.service_offering))) { 'Productivity Tools' } else { (Get-DisplayValue $Incident.service_offering) }
        primary_category = 'Uncategorized'
        issue_summary = [string]$Incident.short_description
        what_was_done = @(
            'Ticket context was captured locally, but AI analysis could not complete for the full payload.',
            'Review raw incident content in the local output folder for manual follow-up.'
        )
        quick_look = 'This incident needs a lighter-weight follow-up because the available ticket content was too large or invalid for the current AI request.'
        what_can_be_improved = @(
            'Trim or structure long work notes before model submission.',
            'Capture a concise closure note so the final action is easier to summarize.'
        )
        probable_root_cause = [string]::Format('AI analysis fallback used. Original error: {0}', $FailureReason)
        confidence = 'Low'
        evidence_signals = @(
            'Incident metadata and notes were captured, but structured AI assessment failed.'
        )
        unknowns = @(
            'Root cause could not be assessed due to AI processing failure.',
            'Remediation completeness needs manual validation in raw ticket notes.'
        )
        service_offering = Get-DisplayValue $Incident.service_offering
        assignment_group = Get-DisplayValue $Incident.assignment_group
        short_description = [string]$Incident.short_description
        resolved_at = [string]$Incident.resolved_at
        sys_updated_on = [string]$Incident.sys_updated_on
    }
}

function Get-StrictProductivityCategory {
    param(
        [string]$Area,
        [string]$RawCategory,
        [string]$ShortDescription,
        [string]$IssueSummary
    )

    $text = ((@($Area, $RawCategory, $ShortDescription, $IssueSummary)) -join ' ').ToLowerInvariant()
    if ($text -match '\bcopilot\b') { return 'Microsoft 365 Copilot Issues' }
    if ($text -match '\bonenote\b') { return 'Microsoft OneNote Issues' }
    if ($text -match 'share file service|\bshare drives?\b|\bshared drives?\b|mapped network drives?|\\\\[a-z0-9._-]+\\') { return 'Shared File Service (Share Drives) Issues' }
    if ($text -match '\bonedrive\b|\bsharepoint\b') { return 'Microsoft OneDrive Issues' }
    if ($text -match '\bexcel\b') { return 'Microsoft Excel Issues' }
    if ($text -match '\bpowerpoint\b') { return 'Microsoft PowerPoint Issues' }
    if ($text -match '\bword\b|ivo add-in') { return 'Microsoft Word Issues' }
    if ($text -match '\boutlook\b') { return 'Microsoft Outlook Issues' }
    if ($text -match '\bforms\b') { return 'Microsoft Forms Issues' }
    if ($text -match '\bvisio\b') { return 'Microsoft Visio Issues' }
    if ($text -match '\bms project\b|microsoft project') { return 'Microsoft Project Issues' }
    if ($text -match '\bloop\b') { return 'Microsoft Loop Issues' }
    if ($text -match '\bsmartsheet\b') { return 'Smartsheet Issues' }
    if ($text -match '\bgoogle\b') { return 'Google Workspace Issues' }
    if ($text -match 'microsoft 365 apps|m365 apps|office profile|office apps') { return 'Microsoft 365 Apps for Enterprise Issues' }
    return 'Microsoft 365 Apps for Enterprise Issues'
}

function Get-StrictProductivitySubCategory {
    param(
        [string]$ParentCategory,
        [string]$RawSubCategory,
        [string]$IssueSummary,
        [string]$ShortDescription,
        [string]$WorkNotes
    )

    $t = ((@($RawSubCategory, $IssueSummary, $ShortDescription, $WorkNotes)) -join ' ').ToLowerInvariant()

    switch ($ParentCategory) {
        'Microsoft OneDrive Issues' {
            if ($t -match 'rejoin|removed and added back|re-?added|site collection') { return 'Rejoin access issue' }
            if ($t -match 'permission not applied|access granted but|permission not effective') { return 'Permission not applied' }
            if ($t -match 'shared file|shared folder|share point shortcut|sharepoint shortcut|shared site|cannot open the sharepoint|unable to access shared|access shared|shared file access') { return 'Shared file access issue' }
            if ($t -match 'data migration|new laptop|migrate data|data backup') { return 'Data migration failure' }
            if ($t -match 'sync conflict|two versions|conflicting') { return 'Sync conflict issue' }
            if ($t -match 'sync stuck|sync delay|slow sync|sync stalled') { return 'Sync stuck / delayed' }
            if ($t -match 'sync fail|not syncing|sync error|upload not|unable to upload|backup.*onedrive|sync issue') { return 'OneDrive sync failure' }
            if ($t -match 'storage quota|quota exceeded|storage full') { return 'Storage quota exceeded' }
            if ($t -match 'offline files|files offline') { return 'Offline files not available' }
            if ($t -match 'missing files|files missing|files disappear') { return 'Missing files after refresh' }
            if ($t -match 'onedrive client|onedrive not running|client crash') { return 'OneDrive client not running' }
            if ($t -match 'file open|open file|won.t open|cannot open|unable to open|file explorer|copy paste') { return 'File open error (desktop)' }
            return 'Shared file access issue'
        }
        'Microsoft Excel Issues' {
            if ($t -match 'freezing|hanging|hang|not responding|crash') { return 'Excel freezing / hanging' }
            if ($t -match 'save fail|cannot save|unable to save|save error') { return 'File save failure' }
            if ($t -match 'add-?in|addin') { return 'Add-in failure' }
            if ($t -match 'data refresh|refresh data|power query|connection refresh') { return 'Data refresh issue' }
            if ($t -match 'license|activation') { return 'Excel license issue' }
            if ($t -match 'large file|performance|slow|big file') { return 'Large file performance issue' }
            if ($t -match 'file open|open file|won.t open|cannot open|unable to open|file not opening') { return 'File not opening' }
            return 'File not opening'
        }
        'Microsoft PowerPoint Issues' {
            if ($t -match 'crash|freezing|hang|not responding') { return 'PowerPoint crashing / freezing' }
            if ($t -match 'format') { return 'Formatting issue' }
            if ($t -match 'corrupt|corruption') { return 'File corruption issue' }
            if ($t -match 'license|activation') { return 'License activation issue' }
            if ($t -match 'open|won.t open|cannot open|unable to open') { return 'Presentation not opening' }
            return 'Presentation not opening'
        }
        'Microsoft Word Issues' {
            if ($t -match 'add-?in|addin|ivo') { return 'Add-in failure' }
            if ($t -match 'crash|freezing|hang|not responding') { return 'Word crashing / freezing' }
            if ($t -match 'format') { return 'Formatting issue' }
            if ($t -match 'corrupt|corruption') { return 'File corruption issue' }
            if ($t -match 'open|won.t open|cannot open|unable to open') { return 'Document not opening' }
            return 'Document not opening'
        }
        'Microsoft Outlook Issues' {
            if ($t -match 'launch|not launching|won.t start|will not open') { return 'Outlook not launching' }
            if ($t -match 'mailbox|inbox access') { return 'Mailbox access issue' }
            if ($t -match 'send|receive') { return 'Email send/receive failure' }
            if ($t -match 'add-?in|addin') { return 'Add-in missing (Teams/Copilot)' }
            if ($t -match 'profile|configuration') { return 'Profile configuration issue' }
            return 'Mailbox access issue'
        }
        'Microsoft 365 Apps for Enterprise Issues' {
            if ($t -match 'install fail|installation fail|reinstall|company portal|deploy') { return 'Installation failure' }
            if ($t -match 'crash|instability|not responding') { return 'App crash / instability' }
            if ($t -match 'update') { return 'Update-related issue' }
            if ($t -match 'license|activation|sign.?in|authentic|identity|credential|profile corruption') { return 'License activation issue' }
            if ($t -match 'feature enablement|provisioning|guidance|how to|configuration|setup|access details|environment') { return 'License activation issue' }
            if ($t -match 'office apps not opening|apps not opening|won.t open|cannot open') { return 'Office apps not opening' }
            return 'License activation issue'
        }
        'Microsoft 365 Copilot Issues' {
            if ($t -match 'teams facilitator|facilitator agent|facilitator') { return 'Teams facilitator not available' }
            if ($t -match 'not visible|missing|disappear') { return 'Copilot not visible' }
            if ($t -match 'license|licensing') { return 'Copilot license missing' }
            if ($t -match 'partial|partially enabled|some features') { return 'Copilot partially enabled' }
            if ($t -match 'feature rollout|rollout|enablement') { return 'Feature rollout issue' }
            if ($t -match 'how to|usage|guidance|query|question') { return 'Usage guidance query' }
            return 'Copilot not visible'
        }
        'Microsoft Forms Issues' {
            if ($t -match 'polls?|teams poll') { return 'Polls not working (Teams)' }
            if ($t -match 'creation|create form|cannot create') { return 'Form creation failure' }
            if ($t -match 'feature disabled|disabled') { return 'Forms feature disabled' }
            if ($t -match 'not accessible|cannot access|unable to access|access') { return 'Forms not accessible' }
            return 'Forms not accessible'
        }
        'Microsoft OneNote Issues' {
            if ($t -match 'sync fail|sync error|not syncing|sync issue') { return 'Notebook sync failure' }
            if ($t -match 'missing notes|notes missing|content missing') { return 'Missing notes issue' }
            if ($t -match 'not responding|hang|crash|freeze') { return 'OneNote not responding' }
            if ($t -match 'new laptop|new device|device change|data not available|migrate|notebook contents were not visible') { return 'Data not available after device change' }
            return 'Notebook sync failure'
        }
        'Microsoft Visio Issues' {
            if ($t -match 'license expired') { return 'License expired issue' }
            if ($t -match 'activation') { return 'Activation failure' }
            if ($t -match 'install') { return 'Installation issue' }
            if ($t -match 'open|save') { return 'File open / save failure' }
            return 'Installation issue'
        }
        'Microsoft Project Issues' {
            if ($t -match 'license|activation') { return 'License activation issue' }
            if ($t -match 'install') { return 'Installation failure' }
            if ($t -match 'open|save') { return 'File open / save failure' }
            if ($t -match 'schedule|plan corrupt') { return 'Schedule / plan corruption' }
            if ($t -match 'hang|crash|slow|performance') { return 'Performance / hang issue' }
            return 'License activation issue'
        }
        'Shared File Service (Share Drives) Issues' {
            if ($t -match 'mapped|reconnect|mapped network|drive letter|samba|unc') { return 'Mapped drive not connecting' }
            if ($t -match 'quota|storage') { return 'Quota / storage issue' }
            if ($t -match 'missing folder|missing file|file not found') { return 'Missing folder / file' }
            if ($t -match 'sync') { return 'Drive sync failure' }
            return 'Access permission issue'
        }
        'Microsoft Loop Issues' {
            if ($t -match 'workspace') { return 'Workspace not loading' }
            if ($t -match 'integration|m365 group') { return 'Integration issue (M365 group)' }
            return 'Loop content missing'
        }
        'Smartsheet Issues' {
            if ($t -match 'external sharing|external user') { return 'External sharing issue' }
            if ($t -match 'sync') { return 'Data sync issue' }
            if ($t -match 'import|export') { return 'Import/export failure' }
            return 'Access permission issue'
        }
        'Google Workspace Issues' {
            if ($t -match 'provision|account') { return 'Account provisioning issue' }
            if ($t -match 'permission') { return 'Permission issue' }
            return 'Access issue'
        }
        default { return $RawSubCategory }
    }
}

function Invoke-IncidentAnalysis {
    param(
        [hashtable]$Config,
        [psobject]$Incident,
        [hashtable]$TemplateBundle
    )

    $instructionsParts = New-Object System.Collections.Generic.List[string]
    $instructionsParts.Add('You are a senior IT operations analyst for Productivity Tools incidents.')
    $instructionsParts.Add('Return valid JSON only. Do not use markdown wrappers.')
    $instructionsParts.Add('Use evidence-only reasoning: do not infer facts that are not explicitly present in the incident payload.')
    $instructionsParts.Add('If evidence is missing, state "Not enough evidence in ticket notes." and lower confidence.')
    $instructionsParts.Add('Keep language precise and operational. Avoid broad claims such as tenant-wide impact unless explicitly stated in the ticket.')
    $instructionsParts.Add('If URL evidence exists in the payload (url_count > 0 or sample_urls present), do not recommend collecting/capturing URLs again.')
    $instructionsParts.Add('For issue_summary, describe only the user problem and impact. Do not mention status words like resolved, fixed, closed, pending, or escalated.')
    if ($TemplateBundle -and -not [string]::IsNullOrWhiteSpace([string]$TemplateBundle.WorkNotesSummary)) {
        $instructionsParts.Add((Limit-TextLength -Text $TemplateBundle.WorkNotesSummary -MaxLength 3000))
    }
    if ($TemplateBundle -and -not [string]::IsNullOrWhiteSpace([string]$TemplateBundle.TicketCategorisation)) {
        $instructionsParts.Add((Limit-TextLength -Text $TemplateBundle.TicketCategorisation -MaxLength 3500))
    }
    $instructionsParts.Add(@'
Return this exact JSON shape:
{
  "incident_number": "string",
  "application_or_area": "string",
  "primary_category": "string",
  "issue_summary": "string",
  "what_was_done": ["string"],
  "quick_look": "string",
  "what_can_be_improved": ["string"],
  "probable_root_cause": "string",
    "confidence": "High|Medium|Low",
    "evidence_signals": ["string"],
    "unknowns": ["string"]
}
'@)
    $instructions = ($instructionsParts -join ([Environment]::NewLine + [Environment]::NewLine))

    $detailLengths = @(12000, 8000, 5000, 3000)
    $lastErrorMessage = $null

    foreach ($detailLength in $detailLengths) {
        try {
            $prompt = New-IncidentPrompt -Incident $Incident -MaxDetailLength $detailLength
            if ($TemplateBundle -and -not [string]::IsNullOrWhiteSpace([string]$TemplateBundle.Environment)) {
                $prompt = [string]::Format("Environment Context:{0}{0}{1}{0}{0}Incident Data:{0}{0}{2}", [Environment]::NewLine, (Limit-TextLength -Text $TemplateBundle.Environment -MaxLength 2500), $prompt)
            }
            $analysis = Invoke-AzureJsonAnalysis -Config $Config -Instructions $instructions -Prompt $prompt -MaxOutputTokens 1200

            if (-not $analysis.issue_summary) {
                throw ([string]::Format('Incident analysis for {0} did not return expected fields.', $Incident.number))
            }

            $incidentUrls = @(Get-IncidentUrls -Incident $Incident)
            $filteredImprovements = @($analysis.what_can_be_improved)
            $filteredUnknowns = @($analysis.unknowns)

            if ($incidentUrls.Count -gt 0) {
                $filteredImprovements = @($filteredImprovements | Where-Object {
                    $text = [string]$_
                    $text -and -not ($text -match '(?i)(capture|collect|gather).*(url|link)')
                })

                $filteredUnknowns = @($filteredUnknowns | Where-Object {
                    $text = [string]$_
                    $text -and -not ($text -match '(?i)(not enough evidence).*(url|link)')
                })
            }

            $evidenceSignals = @($analysis.evidence_signals)
            if ($incidentUrls.Count -gt 0) {
                $preferredUrl = @($incidentUrls | Where-Object { ([string]$_) -match '(?i)sharepoint|onedrive' } | Select-Object -First 1)
                $sampleUrl = if (@($preferredUrl).Count -gt 0) { [string]$preferredUrl[0] } else { [string]$incidentUrls[0] }
                $evidenceSignals = @($evidenceSignals + ([string]::Format('Ticket notes include {0} URL(s); sample: {1}', $incidentUrls.Count, $sampleUrl)))
            }

            $rawLlmCategory = [string]$analysis.primary_category
            $workNotesForTaxonomy = Get-IncidentWorkText -Incident $Incident -MaxLength 12000
            $strictCategory = Get-StrictProductivityCategory -Area ([string]$analysis.application_or_area) -RawCategory $rawLlmCategory -ShortDescription ([string]$Incident.short_description) -IssueSummary ([string]$analysis.issue_summary)
            $strictSubCategory = Get-StrictProductivitySubCategory -ParentCategory $strictCategory -RawSubCategory $rawLlmCategory -IssueSummary ([string]$analysis.issue_summary) -ShortDescription ([string]$Incident.short_description) -WorkNotes $workNotesForTaxonomy

            return [PSCustomObject]@{
                incident_number = [string]$analysis.incident_number
                application_or_area = [string]$analysis.application_or_area
                primary_category = $strictCategory
                sub_category = $strictSubCategory
                llm_primary_category = $rawLlmCategory
                issue_summary = [string]$analysis.issue_summary
                what_was_done = @($analysis.what_was_done)
                quick_look = [string]$analysis.quick_look
                what_can_be_improved = @($filteredImprovements)
                probable_root_cause = [string]$analysis.probable_root_cause
                confidence = [string]$analysis.confidence
                evidence_signals = @($evidenceSignals)
                unknowns = @($filteredUnknowns)
                work_notes_clean = (Invoke-WorkNotesCleanup -Config $Config -Incident $Incident -TemplateBundle $TemplateBundle)
                service_offering = Get-DisplayValue $Incident.service_offering
                assignment_group = Get-DisplayValue $Incident.assignment_group
                short_description = [string]$Incident.short_description
                resolved_at = [string]$Incident.resolved_at
                sys_updated_on = [string]$Incident.sys_updated_on
            }
        } catch {
            $lastErrorMessage = $_.Exception.Message
            Write-Step ([string]::Format('Retrying {0} with reduced context ({1} chars) after AI error: {2}', $Incident.number, $detailLength, $lastErrorMessage)) 'Yellow'
        }
    }

    return (New-FallbackIncidentAnalysis -Incident $Incident -FailureReason $lastErrorMessage)
}

function New-FallbackPortfolioSummary {
    param([array]$IncidentAnalyses)

    $count = @($IncidentAnalyses).Count
    $categoryCounts = @{}
    $confidenceCounts = @{}
    $improvementPool = New-Object System.Collections.Generic.List[string]

    foreach ($item in @($IncidentAnalyses)) {
        $category = [string]$item.primary_category
        if ([string]::IsNullOrWhiteSpace($category)) { $category = 'Uncategorized' }
        if (-not $categoryCounts.ContainsKey($category)) { $categoryCounts[$category] = 0 }
        $categoryCounts[$category] += 1

        $confidence = [string]$item.confidence
        if ([string]::IsNullOrWhiteSpace($confidence)) { $confidence = 'Unknown' }
        if (-not $confidenceCounts.ContainsKey($confidence)) { $confidenceCounts[$confidence] = 0 }
        $confidenceCounts[$confidence] += 1

        foreach ($improvement in @($item.what_can_be_improved)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$improvement)) {
                $improvementPool.Add(([string]$improvement).Trim())
            }
        }
    }

    $topCategory = 'Uncategorized'
    if ($categoryCounts.Keys.Count -gt 0) {
        $topCategory = ($categoryCounts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1).Key
    }

    $quickLook = New-Object System.Collections.Generic.List[string]
    $quickLook.Add(([string]::Format('Total incidents assessed: {0}.', $count)))
    $quickLook.Add(([string]::Format('Top category by frequency: {0}.', $topCategory)))
    foreach ($entry in ($confidenceCounts.GetEnumerator() | Sort-Object -Property Name)) {
        $quickLook.Add(([string]::Format('Confidence distribution: {0}={1}.', $entry.Key, $entry.Value)))
    }

    $themes = New-Object System.Collections.Generic.List[string]
    if ($count -le 1) {
        $themes.Add('Limited sample size (1 incident); recurring themes cannot be established with confidence.')
    } else {
        foreach ($entry in ($categoryCounts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 3)) {
            $themes.Add(([string]::Format('{0}: {1} incidents.', $entry.Key, $entry.Value)))
        }
    }

    $improvements = @($improvementPool | Select-Object -Unique | Select-Object -First 8)
    if (@($improvements).Count -eq 0) {
        $improvements = @('Capture clearer remediation evidence in ticket updates so closure quality can be verified.')
    }

    return [PSCustomObject]@{
        executive_summary = if ($count -le 1) {
            'Assessment generated from a limited sample of one incident. Use this output as a case-level assessment, not a trend conclusion.'
        } else {
            ([string]::Format('Assessment generated from {0} incidents with evidence-first aggregation.', $count))
        }
        quick_look = @($quickLook)
        recurring_themes = @($themes)
        improvement_opportunities = @($improvements)
    }
}

function Resolve-CategorySubcategory {
    # Strictly maps incidents to categories and subcategories defined in the templates:
    # - templates/ProductivityTools_TrendSubCategorisation.md
    # - templates/ProductivityTools_TicketCategorisation.md
    # No categories or subcategories outside those templates are used.
    param([psobject]$Incident)

    $resolutionCategoryRaw = (Get-DisplayValue $Incident.u_resolution_category).Trim()
    $shortDescriptionRaw = ([string]$Incident.short_description).Trim()
    $rc = $resolutionCategoryRaw.ToLowerInvariant()
    $sd = $shortDescriptionRaw.ToLowerInvariant()

    # ── Microsoft 365 Copilot ────────────────────────────────────────────────
    if ($rc -match 'copilot' -or $sd -match '\bcopilot\b') {
        if ($rc -match 'license|entitlement|provision' -or $sd -match 'license|entitlement') {
            if ($rc -match 'expire|expired') { return [PSCustomObject]@{ Category = 'Microsoft 365 Copilot'; Subcategory = 'License expired issue' } }
            if ($rc -match 'entitlement|not provisioned|provision') { return [PSCustomObject]@{ Category = 'Microsoft 365 Copilot'; Subcategory = 'Entitlement not provisioned' } }
            return [PSCustomObject]@{ Category = 'Microsoft 365 Copilot'; Subcategory = 'Copilot license missing' }
        }
        if ($rc -match 'facilitator|meeting ai|teams facilitator' -or $sd -match 'facilitator|meeting ai') {
            if ($rc -match 'meeting ai|missing' -or $sd -match 'meeting ai') { return [PSCustomObject]@{ Category = 'Microsoft 365 Copilot'; Subcategory = 'Meeting AI feature missing' } }
            return [PSCustomObject]@{ Category = 'Microsoft 365 Copilot'; Subcategory = 'Facilitator not available' }
        }
        if ($rc -match 'partial|inconsisten' -or $sd -match 'partial|inconsisten') { return [PSCustomObject]@{ Category = 'Microsoft 365 Copilot'; Subcategory = 'Copilot partially enabled' } }
        if ($rc -match 'rollout|feature.*not available' -or $sd -match 'rollout') { return [PSCustomObject]@{ Category = 'Microsoft 365 Copilot'; Subcategory = 'Feature rollout issue' } }
        if ($rc -match 'not visible|cannot see|missing.*icon' -or $sd -match 'not visible|cannot see copilot') { return [PSCustomObject]@{ Category = 'Microsoft 365 Copilot'; Subcategory = 'Copilot not visible' } }
        if ($rc -match 'how to|query|usage' -or $sd -match 'how to use|usage query') { return [PSCustomObject]@{ Category = 'Microsoft 365 Copilot'; Subcategory = 'Copilot usage query' } }
        return [PSCustomObject]@{ Category = 'Microsoft 365 Copilot'; Subcategory = 'Feature inconsistency issue' }
    }

    # ── Microsoft OneDrive ───────────────────────────────────────────────────
    if ($rc -match 'onedrive' -or $sd -match '\bonedrive\b') {
        # Sync Issues
        if ($rc -match 'sync error|cannot sync|sync fail' -or $sd -match 'sync.*fail|sync.*error') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'OneDrive sync failure' } }
        if ($rc -match 'stop syncing|sync.*stop|not syncing' -or $sd -match 'not syncing|sync.*stop') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Sync stuck issue' } }
        if ($rc -match 'cross.device|delay|slow sync' -or $sd -match 'cross.device|sync.*delay') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Cross-device sync delay' } }
        if ($rc -match 'conflict' -or $sd -match 'sync.*conflict|conflict.*sync') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Sync conflict error' } }
        if ($rc -match 'limitation|file type|cannot sync some') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Sync stuck issue' } }
        # Access & Permission Issues
        if ($rc -match 'shared.*access|access.*shared' -or $sd -match 'shared.*file.*access|access.*shared') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Shared file access issue' } }
        if ($rc -match 'file permission|permission|access denied' -or $sd -match 'permission|access denied') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Permission not applied' } }
        if ($rc -match 'rejoin|re-join|access to another' -or $sd -match 'rejoin') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Rejoin access issue' } }
        # Data Migration / Device Change
        if ($rc -match 'pc refresh|new pc|device change|data transfer' -or $sd -match 'new pc|new laptop|old pc|data transfer') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Missing files after refresh' } }
        if ($rc -match 'data migrat' -or $sd -match 'data migrat') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Data migration failure' } }
        if ($rc -match 'old device|retrieve.*data' -or $sd -match 'old device') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Old device data retrieval issue' } }
        # File Handling Issues
        if ($rc -match 'file.*open|unable to open|open.*file' -or $sd -match 'file.*open|open.*file') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'File open issue (desktop)' } }
        if ($rc -match 'web.*desktop|desktop.*web|mismatch' -or $sd -match 'web.*desktop|desktop.*web') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Web vs desktop mismatch' } }
        if ($rc -match 'data restore|file restore|deletion|recycle' -or $sd -match 'restore|deleted.*file') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Missing files after refresh' } }
        # Application / Client Issues
        if ($rc -match 'client not running|not running|login.*connect|connect.*login' -or $sd -match 'client not running|not running') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'OneDrive client not running' } }
        if ($rc -match 'login|sign.in|connect' -or $sd -match 'login|sign.in|connect') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Login/connectivity issue' } }
        # Storage & Backup Issues
        if ($rc -match 'storage|quota|full' -or $sd -match 'storage.*full|quota') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Storage quota exceeded' } }
        if ($rc -match 'backup|offline' -or $sd -match 'backup|offline files') { return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'Offline files issue' } }
        return [PSCustomObject]@{ Category = 'Microsoft OneDrive'; Subcategory = 'File access inconsistency' }
    }

    # ── Microsoft Excel ──────────────────────────────────────────────────────
    if ($rc -match '\bexcel\b' -or ($sd -match '\bexcel\b' -and $sd -notmatch 'powerpoint|word|onenote')) {
        if ($rc -match 'unable to open|load|file specific|blank file|corrupt' -or $sd -match 'not open|unable to open|blank|corrupt') {
            if ($rc -match 'corrupt' -or $sd -match 'corrupt') { return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'File corruption issue' } }
            if ($rc -match 'blank' -or $sd -match 'blank') { return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'Blank file issue' } }
            return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'File not opening' }
        }
        if ($rc -match 'slow|performance|large file' -or $sd -match 'slow|performance|large file') {
            if ($rc -match 'large' -or $sd -match 'large') { return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'Large file slowness' } }
            return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'Excel performance issue' }
        }
        if ($rc -match 'save.*fail|update.*inconsisten|shared.*sync' -or $sd -match 'save.*fail|not.*saving') { return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'File save failure' } }
        if ($rc -match 'update.*inconsisten' -or $sd -match 'update.*inconsisten') { return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'File update inconsistency' } }
        if ($rc -match 'shared.*sync' -or $sd -match 'shared.*sync') { return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'Shared file sync issue' } }
        if ($rc -match 'add.in|addin|feature|refresh|integrat' -or $sd -match 'add.in|addin|refresh') {
            if ($rc -match 'refresh' -or $sd -match 'refresh') { return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'Data refresh failure' } }
            if ($rc -match 'integrat' -or $sd -match 'integrat') { return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'Integration issue' } }
            return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'Add-in failure' }
        }
        if ($rc -match 'license|activat' -or $sd -match 'license|activat') {
            if ($rc -match 'activat' -or $sd -match 'activat') { return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'Activation failure' } }
            return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'Excel license issue' }
        }
        return [PSCustomObject]@{ Category = 'Microsoft Excel'; Subcategory = 'File not opening' }
    }

    # ── Microsoft PowerPoint ────────────────────────────────────────────────
    if ($rc -match 'microsoft powerpoint|\bpowerpoint\b|\bppt\b' -or ($sd -match '\bpowerpoint\b|\bppt\b' -and $sd -notmatch 'excel|word|onenote|onedrive')) {
        if ($rc -match 'unable to open|load|blank file|corrupt' -or $sd -match 'not open|unable to open|blank|corrupt') {
            if ($rc -match 'corrupt' -or $sd -match 'corrupt') { return [PSCustomObject]@{ Category = 'Microsoft PowerPoint'; Subcategory = 'File corruption issue' } }
            if ($rc -match 'blank' -or $sd -match 'blank') { return [PSCustomObject]@{ Category = 'Microsoft PowerPoint'; Subcategory = 'Blank file issue' } }
            return [PSCustomObject]@{ Category = 'Microsoft PowerPoint'; Subcategory = 'Presentation not opening' }
        }
        if ($rc -match 'slow|performance|large file|freez|hang|crash' -or $sd -match 'slow|performance|large presentation|freez|hang|crash') {
            if ($rc -match 'large' -or $sd -match 'large') { return [PSCustomObject]@{ Category = 'Microsoft PowerPoint'; Subcategory = 'Large file slowness' } }
            return [PSCustomObject]@{ Category = 'Microsoft PowerPoint'; Subcategory = 'PowerPoint performance issue' }
        }
        if ($rc -match 'format|layout|structure|render|slide|media|video|audio|animation|feature' -or $sd -match 'format|layout|structure|render|slide|media|video|audio|animation') {
            if ($rc -match 'layout|structure|render|slide' -or $sd -match 'layout|structure|render|slide') { return [PSCustomObject]@{ Category = 'Microsoft PowerPoint'; Subcategory = 'Layout/structure issue' } }
            if ($rc -match 'media|video|audio|animation' -or $sd -match 'media|video|audio|animation') { return [PSCustomObject]@{ Category = 'Microsoft PowerPoint'; Subcategory = 'Media feature issue' } }
            return [PSCustomObject]@{ Category = 'Microsoft PowerPoint'; Subcategory = 'Formatting issue' }
        }
        if ($rc -match 'license|activat' -or $sd -match 'license|activat') {
            if ($rc -match 'activat' -or $sd -match 'activat') { return [PSCustomObject]@{ Category = 'Microsoft PowerPoint'; Subcategory = 'Activation failure' } }
            return [PSCustomObject]@{ Category = 'Microsoft PowerPoint'; Subcategory = 'PowerPoint license issue' }
        }
        return [PSCustomObject]@{ Category = 'Microsoft PowerPoint'; Subcategory = 'Presentation not opening' }
    }

    # ── Microsoft 365 Apps for Enterprise ───────────────────────────────────
    if ($rc -match 'apps for enterprise|m365 apps|office apps|microsoft 365 apps' -or
        $sd -match 'apps for enterprise|m365 apps|office apps|microsoft 365 apps') {
        if ($rc -match 'license' -or $sd -match 'license') {
            if ($rc -match 'not assigned|missing' -or $sd -match 'not assigned|missing') { return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'License not assigned' } }
            if ($rc -match 'expire' -or $sd -match 'expire') { return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'License expired issue' } }
            return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'Activation issue' }
        }
        if ($rc -match 'activat' -or $sd -match 'activat') { return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'Activation issue' } }
        if ($rc -match 'install' -or $sd -match 'install') {
            if ($rc -match 'missing|not installed' -or $sd -match 'missing') { return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'Missing app issue' } }
            return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'Installation failure' }
        }
        if ($rc -match 'shortcut|icon') { return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'Missing app issue' } }
        if ($rc -match 'crash|instab|unstable' -or $sd -match 'crash|instab') { return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'App instability issue' } }
        if ($rc -match 'performance|degrad|slow' -or $sd -match 'performance|slow') { return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'Performance degradation' } }
        if ($rc -match 'not open|login fail|app.*login' -or $sd -match 'not open|login') {
            if ($rc -match 'login' -or $sd -match 'login') { return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'App login failure' } }
            return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'Office apps not opening' }
        }
        if ($rc -match 'compat' -or $sd -match 'compat') { return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'Compatibility issue' } }
        return [PSCustomObject]@{ Category = 'Microsoft 365 Apps for Enterprise'; Subcategory = 'File operation error' }
    }

    # ── Microsoft Visio Professional Client ─────────────────────────────────
    if ($rc -match 'visio' -or $sd -match '\bvisio\b') {
        if ($rc -match 'install' -or $sd -match 'install') { return [PSCustomObject]@{ Category = 'Microsoft Visio Professional Client'; Subcategory = 'Visio install failure' } }
        if ($rc -match 'trial' -or $sd -match 'trial') { return [PSCustomObject]@{ Category = 'Microsoft Visio Professional Client'; Subcategory = 'Trial expired issue' } }
        if ($rc -match 'license|expire' -or $sd -match 'license|expire') { return [PSCustomObject]@{ Category = 'Microsoft Visio Professional Client'; Subcategory = 'License expired issue' } }
        return [PSCustomObject]@{ Category = 'Microsoft Visio Professional Client'; Subcategory = 'Activation failure' }
    }

    # ── Microsoft OneNote ────────────────────────────────────────────────────
    if ($rc -match 'onenote' -or $sd -match '\bonenote\b') {
        if ($rc -match 'sync|open' -or $sd -match 'sync') { return [PSCustomObject]@{ Category = 'Microsoft OneNote'; Subcategory = 'Notebook sync failure' } }
        if ($rc -match 'missing|loss|lost|data' -or $sd -match 'missing|lost|data') {
            if ($rc -match 'refresh|device' -or $sd -match 'refresh|device') { return [PSCustomObject]@{ Category = 'Microsoft OneNote'; Subcategory = 'Data loss after refresh' } }
            return [PSCustomObject]@{ Category = 'Microsoft OneNote'; Subcategory = 'Missing notes issue' }
        }
        if ($rc -match 'render|ui|display' -or $sd -match 'render|display') { return [PSCustomObject]@{ Category = 'Microsoft OneNote'; Subcategory = 'UI rendering issue' } }
        return [PSCustomObject]@{ Category = 'Microsoft OneNote'; Subcategory = 'OneNote not responding' }
    }

    # ── Microsoft Word ───────────────────────────────────────────────────────
    if ($rc -match 'microsoft word|\bword\b' -or ($sd -match '\bword\b' -and $sd -notmatch 'excel|powerpoint|onenote|onedrive')) {
        if ($rc -match 'unable to open|load|content|corrupt' -or $sd -match 'not open|unable to open|content') {
            if ($rc -match 'content' -or $sd -match 'content') { return [PSCustomObject]@{ Category = 'Microsoft Word'; Subcategory = 'File content issue' } }
            return [PSCustomObject]@{ Category = 'Microsoft Word'; Subcategory = 'Document not opening' }
        }
        if ($rc -match 'slow|performance' -or $sd -match 'slow|performance') { return [PSCustomObject]@{ Category = 'Microsoft Word'; Subcategory = 'Word performance issue' } }
        if ($rc -match 'layout|structure' -or $sd -match 'layout|structure') { return [PSCustomObject]@{ Category = 'Microsoft Word'; Subcategory = 'Layout/structure issue' } }
        return [PSCustomObject]@{ Category = 'Microsoft Word'; Subcategory = 'Formatting issue' }
    }

    # ── Microsoft Loop ───────────────────────────────────────────────────────
    if ($rc -match '\bloop\b' -or $sd -match 'microsoft loop|\bloop\b') {
        if ($rc -match 'integrat' -or $sd -match 'integrat') { return [PSCustomObject]@{ Category = 'Microsoft Loop'; Subcategory = 'Loop integration issue' } }
        if ($rc -match 'missing|content' -or $sd -match 'missing|content') { return [PSCustomObject]@{ Category = 'Microsoft Loop'; Subcategory = 'Missing workspace content' } }
        return [PSCustomObject]@{ Category = 'Microsoft Loop'; Subcategory = 'Workspace not loading' }
    }

    # ── Microsoft Outlook for M365 ───────────────────────────────────────────
    if ($rc -match 'outlook' -or $sd -match '\boutlook\b') {
        if ($rc -match 'login|auth|sign.in|access' -or $sd -match 'login|auth|sign.in|access') { return [PSCustomObject]@{ Category = 'Microsoft Outlook for M365'; Subcategory = 'Login/authentication failure' } }
        if ($rc -match 'slow|performance' -or $sd -match 'slow|performance') { return [PSCustomObject]@{ Category = 'Microsoft Outlook for M365'; Subcategory = 'Outlook performance issue' } }
        if ($rc -match 'not open|not launch' -or $sd -match 'not open|not launch') { return [PSCustomObject]@{ Category = 'Microsoft Outlook for M365'; Subcategory = 'Outlook not opening' } }
        return [PSCustomObject]@{ Category = 'Microsoft Outlook for M365'; Subcategory = 'Outlook not accessible' }
    }

    # ── Google Workspace ────────────────────────────────────────────────────
    if ($rc -match 'g suite|gsuite|google workspace|gemini' -or $sd -match 'g suite|gsuite|google workspace|gemini') {
        if ($rc -match 'provision|account' -or $sd -match 'provision|account') { return [PSCustomObject]@{ Category = 'Google Workspace'; Subcategory = 'Account provisioning issue' } }
        if ($rc -match 'integrat|tool' -or $sd -match 'integrat') { return [PSCustomObject]@{ Category = 'Google Workspace'; Subcategory = 'Tool integration issue' } }
        if ($rc -match 'permission' -or $sd -match 'permission') { return [PSCustomObject]@{ Category = 'Google Workspace'; Subcategory = 'Permission setup issue' } }
        return [PSCustomObject]@{ Category = 'Google Workspace'; Subcategory = 'Google access issue' }
    }

    # ── Smartsheet ───────────────────────────────────────────────────────────
    if ($rc -match 'smartsheet' -or $sd -match '\bsmartsheet\b') {
        if ($rc -match 'import|export' -or $sd -match 'import|export') { return [PSCustomObject]@{ Category = 'Smartsheet'; Subcategory = 'Import/export issue' } }
        if ($rc -match 'data sync|sync' -or $sd -match 'data sync|sync') { return [PSCustomObject]@{ Category = 'Smartsheet'; Subcategory = 'Data sync issue' } }
        if ($rc -match 'permission' -or $sd -match 'permission') { return [PSCustomObject]@{ Category = 'Smartsheet'; Subcategory = 'Permission setup issue' } }
        return [PSCustomObject]@{ Category = 'Smartsheet'; Subcategory = 'Smartsheet access issue' }
    }

    # ── Microsoft Forms ──────────────────────────────────────────────────────
    if ($rc -match 'microsoft forms|\bforms\b' -or $sd -match 'microsoft forms|forms.*poll|poll.*teams|\bforms\b') {
        if ($rc -match 'disabled|feature.*missing|missing.*feature' -or $sd -match 'disabled|feature.*missing') {
            if ($rc -match 'poll' -or $sd -match 'poll') { return [PSCustomObject]@{ Category = 'Microsoft Forms'; Subcategory = 'Poll feature disabled' } }
            return [PSCustomObject]@{ Category = 'Microsoft Forms'; Subcategory = 'Forms feature missing' }
        }
        if ($rc -match 'poll|creating poll' -or $sd -match 'poll') { return [PSCustomObject]@{ Category = 'Microsoft Forms'; Subcategory = 'Polls not working' } }
        if ($rc -match 'creat.*fail|fail.*creat' -or $sd -match 'creat.*fail|fail.*creat') { return [PSCustomObject]@{ Category = 'Microsoft Forms'; Subcategory = 'Form creation failure' } }
        if ($rc -match 'unable to access|access|disabled' -or $sd -match 'access|cannot access') { return [PSCustomObject]@{ Category = 'Microsoft Forms'; Subcategory = 'Forms access issue' } }
        return [PSCustomObject]@{ Category = 'Microsoft Forms'; Subcategory = 'Forms disabled issue' }
    }

    # ── Fallback ─────────────────────────────────────────────────────────────
    if (-not [string]::IsNullOrWhiteSpace($resolutionCategoryRaw)) {
        return [PSCustomObject]@{ Category = 'Resolution Category Not Mapped'; Subcategory = $resolutionCategoryRaw }
    }

    return [PSCustomObject]@{ Category = 'Resolution Category Not Mapped'; Subcategory = 'Missing Resolution Category' }
}

function Resolve-HelpIntent {
    param(
        [psobject]$Incident,
        [string]$Category,
        [string]$Subcategory
    )

    # Strict classification from ServiceNow Category only (no text inference).
    $serviceNowCategory = (Get-DisplayValue $Incident.category)
    if ([string]::IsNullOrWhiteSpace($serviceNowCategory)) {
        return 'Unknown'
    }

    $normalizedCategory = $serviceNowCategory.Trim().ToLowerInvariant()
    if ($normalizedCategory -eq 'how do i') { return 'How Do I' }
    if ($normalizedCategory -eq 'incident') { return 'Incident' }
    return $serviceNowCategory.Trim()
}

function Get-WowStatusLabel {
    param([int]$CurrentCount, [int]$PreviousCount)

    $delta = $CurrentCount - $PreviousCount
    $percentage = if ($PreviousCount -gt 0) { (($delta * 100.0) / $PreviousCount) } else { if ($CurrentCount -gt 0) { 100.0 } else { 0.0 } }

    if ($delta -ge 5 -or ($delta -ge 3 -and $percentage -ge 50.0)) { return 'Significant Increase' }
    if ($delta -ge 2) { return 'Increase' }
    if ($delta -le -2) { return 'Decrease' }
    return 'Stable'
}

function Get-WowStatusClass {
    param([string]$Status)

    switch ($Status) {
        'Significant Increase' { return 'sig' }
        'Increase' { return 'inc' }
        'Stable' { return 'stb' }
        'Decrease' { return 'dec' }
        default { return 'stb' }
    }
}

function Convert-DurationTextToMinutes {
    param([string]$DurationText)

    if ([string]::IsNullOrWhiteSpace($DurationText)) {
        return $null
    }

    $text = $DurationText.Trim()
    if ($text -match '(?i)^unknown$') {
        return $null
    }

    $totalMinutes = 0
    $hasMatch = $false

    if ($text -match '(?i)(\d+)\s*day') {
        $totalMinutes += ([int]$Matches[1] * 1440)
        $hasMatch = $true
    }
    if ($text -match '(?i)(\d+)\s*hour') {
        $totalMinutes += ([int]$Matches[1] * 60)
        $hasMatch = $true
    }
    if ($text -match '(?i)(\d+)\s*minute') {
        $totalMinutes += [int]$Matches[1]
        $hasMatch = $true
    }

    if (-not $hasMatch) {
        return $null
    }

    return [int]$totalMinutes
}

function Format-MinutesAsDuration {
    param([Nullable[int]]$Minutes)

    $minuteValue = $null
    if ($null -ne $Minutes) {
        if ($Minutes -is [Nullable[int]]) {
            $minuteValue = $Minutes.Value
        } else {
            $minuteValue = [int]$Minutes
        }
    }
    
    if ($null -eq $minuteValue -or $minuteValue -le 0) {
        return 'n/a'
    }

    $total = $minuteValue
    $days = [Math]::Floor($total / 1440)
    $remaining = $total % 1440
    $hours = [Math]::Floor($remaining / 60)
    $mins = $remaining % 60

    $parts = New-Object System.Collections.Generic.List[string]
    if ($days -gt 0) { $parts.Add([string]::Format('{0}d', $days)) }
    if ($hours -gt 0) { $parts.Add([string]::Format('{0}h', $hours)) }
    if ($mins -gt 0 -or $parts.Count -eq 0) { $parts.Add([string]::Format('{0}m', $mins)) }
    return ($parts -join ' ')
}

function Get-IncidentMetricsFromTimestamps {
    param([psobject]$Incident)

    $mttrMinutes = $null
    
    try {
        $createdTime = $null
        $closedTime = $null
        
        if (-not [string]::IsNullOrWhiteSpace([string]$Incident.sys_created_on)) {
            $createdTime = [DateTime]::Parse([string]$Incident.sys_created_on, [Globalization.CultureInfo]::InvariantCulture)
        }
        
        if (-not [string]::IsNullOrWhiteSpace([string]$Incident.closed_at)) {
            $closedTime = [DateTime]::Parse([string]$Incident.closed_at, [Globalization.CultureInfo]::InvariantCulture)
        }
        
        if ($null -eq $closedTime -and -not [string]::IsNullOrWhiteSpace([string]$Incident.resolved_at)) {
            $closedTime = [DateTime]::Parse([string]$Incident.resolved_at, [Globalization.CultureInfo]::InvariantCulture)
        }
        
        if ($null -eq $createdTime -and -not [string]::IsNullOrWhiteSpace([string]$Incident.opened_at)) {
            $createdTime = [DateTime]::Parse([string]$Incident.opened_at, [Globalization.CultureInfo]::InvariantCulture)
        }
        
        if ($null -ne $createdTime -and $null -ne $closedTime -and $closedTime -gt $createdTime) {
            $timeSpan = $closedTime - $createdTime
            $mttrMinutes = [Math]::Round($timeSpan.TotalMinutes, 0)
            
            if ($mttrMinutes -le 0) {
                $mttrMinutes = $null
            }
        }
    } catch {
    }
    
    return [PSCustomObject]@{
        MTTRMinutes = $mttrMinutes
    }
}

function Get-UserSentiment {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return 'Neutral'
    }

    $normalized = $Text.ToLowerInvariant()

    $positivePatterns = @(
        'resolved', 'fixed', 'working', 'issue is resolved', 'thank you', 'closure provided', 'confirmed', 'solved'
    )
    $negativePatterns = @(
        'unable', 'cannot', 'can not', 'not working', 'error', 'failed', 'struggling', 'blocked', 'escalat', 'urgent'
    )

    $positiveScore = 0
    foreach ($pattern in $positivePatterns) {
        if ($normalized -match [Regex]::Escape($pattern)) { $positiveScore += 1 }
    }

    $negativeScore = 0
    foreach ($pattern in $negativePatterns) {
        if ($normalized -match [Regex]::Escape($pattern)) { $negativeScore += 1 }
    }

    if ($negativeScore -gt $positiveScore) { return 'Negative' }
    if ($positiveScore -gt $negativeScore) { return 'Positive' }
    return 'Neutral'
}

function Get-TextWindow {
    param(
        [string]$Text,
        [int]$MaxChars = 1200,
        [ValidateSet('Start', 'End')]
        [string]$From = 'Start'
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $normalized = [Regex]::Replace($Text, '\s+', ' ').Trim()
    if ($normalized.Length -le $MaxChars) {
        return $normalized
    }

    if ($From -eq 'End') {
        return $normalized.Substring($normalized.Length - $MaxChars, $MaxChars)
    }

    return $normalized.Substring(0, $MaxChars)
}

function Get-SentimentShiftLabel {
    param(
        [string]$InitialSentiment,
        [string]$ClosureSentiment
    )

    $rank = @{ 'Negative' = 0; 'Neutral' = 1; 'Positive' = 2 }
    $initialRank = if ($rank.ContainsKey($InitialSentiment)) { [int]$rank[$InitialSentiment] } else { 1 }
    $closureRank = if ($rank.ContainsKey($ClosureSentiment)) { [int]$rank[$ClosureSentiment] } else { 1 }

    if ($closureRank -gt $initialRank) { return 'Improved' }
    if ($closureRank -lt $initialRank) { return 'Worsened' }
    return 'No Change'
}

function Get-UserSentimentJourney {
    param(
        [string]$ShortDescription,
        [string]$Description,
        [string]$CommentsAndWorkNotes,
        [string]$CloseNotes
    )

    $earlyNotes = Get-TextWindow -Text $CommentsAndWorkNotes -From Start
    $lateNotes = Get-TextWindow -Text $CommentsAndWorkNotes -From End

    $initialText = [string]::Format('{0} {1} {2}', [string]$ShortDescription, [string]$Description, $earlyNotes)
    $closureText = [string]::Format('{0} {1}', [string]$CloseNotes, $lateNotes)

    $initialSentiment = Get-UserSentiment -Text $initialText
    $closureSentiment = if ([string]::IsNullOrWhiteSpace($closureText)) {
        $initialSentiment
    } else {
        Get-UserSentiment -Text $closureText
    }

    [PSCustomObject]@{
        InitialSentiment = $initialSentiment
        ClosureSentiment = $closureSentiment
        SentimentShift = Get-SentimentShiftLabel -InitialSentiment $initialSentiment -ClosureSentiment $closureSentiment
    }
}

function New-WeeklyDashboardData {
    param(
        [array]$Incidents,
        [psobject]$PortfolioSummary,
        [psobject]$ReportContext = $null,
        [int]$TopCategories = 15,
        [int]$MaxSubcategories = 4
    )

    if ($null -eq $ReportContext) {
        $ReportContext = Get-ReportWeekContext -DateValue (Get-Date)
    }

    $currentWeekStart = $ReportContext.AnalysisWeekStart
    $currentWeekEnd = $ReportContext.AnalysisWeekEnd
    $previousWeekStart = $ReportContext.PreviousWeekStart
    $previousWeekEnd = $ReportContext.PreviousWeekEnd
    $currentWeekNumber = $ReportContext.AnalysisWW
    $previousWeekNumber = $ReportContext.PreviousWW

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($incident in @($Incidents)) {
        $incidentDate = Get-IncidentDateValue -Incident $incident
        if (-not $incidentDate -or $incidentDate.Date -lt $previousWeekStart -or $incidentDate.Date -gt $ReportContext.WindowEnd) {
            continue
        }

        $mapped = Resolve-CategorySubcategory -Incident $incident
        $category = [string]$mapped.Category
        $subcategory = [string]$mapped.Subcategory
        $serviceNowCategory = [string](Get-DisplayValue $incident.category)
        $assignmentGroup = [string](Get-DisplayValue $incident.assignment_group)
        $reassignmentCount = 0
        if (-not [int]::TryParse(([string](Get-DisplayValue $incident.reassignment_count)), [ref]$reassignmentCount)) {
            $reassignmentCount = 0
        }
        $escalationOrder = [string](Get-DisplayValue $incident.u_escalation_order)
        $escalationReason = [string](Get-DisplayValue $incident.u_escalation_reason)
        $timeToAssignment = [string](Get-DisplayValue $incident.u_time_to_assignment)
        $businessDuration = [string](Get-DisplayValue $incident.business_duration)
        $timeToAssignmentMinutes = Convert-DurationTextToMinutes -DurationText $timeToAssignment
        
        $incidentMetrics = Get-IncidentMetricsFromTimestamps -Incident $incident
        $mttrMinutes = $incidentMetrics.MTTRMinutes
        
        if ($null -eq $mttrMinutes) {
            $mttrMinutes = Convert-DurationTextToMinutes -DurationText $businessDuration
        }
        
        $sentimentJourney = Get-UserSentimentJourney `
            -ShortDescription ([string]$incident.short_description) `
            -Description ([string]$incident.description) `
            -CommentsAndWorkNotes ([string]$incident.comments_and_work_notes) `
            -CloseNotes ([string]$incident.close_notes)
        $helpIntent = Resolve-HelpIntent -Incident $incident -Category $category -Subcategory $subcategory

        $rows.Add([PSCustomObject]@{
            number = [string]$incident.number
            incident_date = $incidentDate
            category = $category
            subcategory = $subcategory
            service_now_category = $serviceNowCategory
            assignment_group = $assignmentGroup
            help_intent = $helpIntent
            reassignment_count = $reassignmentCount
            escalation_order = $escalationOrder
            escalation_reason = $escalationReason
            time_to_assignment_minutes = $timeToAssignmentMinutes
            business_duration_minutes = $mttrMinutes
            user_sentiment = $sentimentJourney.InitialSentiment
            initial_user_sentiment = $sentimentJourney.InitialSentiment
            closure_user_sentiment = $sentimentJourney.ClosureSentiment
            sentiment_shift = $sentimentJourney.SentimentShift
            is_incorrect_classification = (
                $category -eq 'Resolution Category Not Mapped' -or
                $helpIntent -eq 'Unknown' -or
                [string]::IsNullOrWhiteSpace($serviceNowCategory)
            )
            is_misrouted = (
                ($escalationReason -match '(?i)misroute|wrong queue|reroute|re-route')
            )
            is_l3_escalation = (
                ($escalationOrder -match '(?i)level\s*3|\bl3\b|l\s*3') -or
                ($escalationReason -match '(?i)level\s*3|\bl3\b|l\s*3')
            )
            short_desc = [string]$incident.short_description
        })
    }

    $data = @($rows.ToArray())
    if ($data.Count -eq 0) {
        throw 'No incidents found for weekly comparison dashboard.'
    }

    $currentWeekData = @($data | Where-Object { $_.incident_date.Date -ge $currentWeekStart -and $_.incident_date.Date -le $currentWeekEnd })
    $previousWeekData = @($data | Where-Object { $_.incident_date.Date -ge $previousWeekStart -and $_.incident_date.Date -le $previousWeekEnd })
    $topGroups = @($data | Group-Object category | Sort-Object Count -Descending | Select-Object -First $TopCategories)
    $totalCurrentWeek = $currentWeekData.Count
    $totalPreviousWeek = $previousWeekData.Count
    $weekOverWeekDelta = $totalCurrentWeek - $totalPreviousWeek
    $totalTwoWeekIncidents = @($data).Count
    $taxonomyGapCount = @($data | Where-Object { $_.category -eq 'Resolution Category Not Mapped' }).Count

    $statusCounts = @{ 'Significant Increase' = 0; 'Increase' = 0; 'Stable' = 0; 'Decrease' = 0 }
    $categoryRows = New-Object System.Collections.Generic.List[object]

    foreach ($group in $topGroups) {
        $categoryName = $group.Name
        $categoryItems = @($group.Group)
        $previousCount = @($categoryItems | Where-Object { $_.incident_date.Date -ge $previousWeekStart -and $_.incident_date.Date -le $previousWeekEnd }).Count
        $currentCount = @($categoryItems | Where-Object { $_.incident_date.Date -ge $currentWeekStart -and $_.incident_date.Date -le $currentWeekEnd }).Count
        $delta = $currentCount - $previousCount
        $status = Get-WowStatusLabel -CurrentCount $currentCount -PreviousCount $previousCount
        $statusCounts[$status] += 1

        $subRows = New-Object System.Collections.Generic.List[object]
        foreach ($subGroup in @($categoryItems | Group-Object subcategory | Sort-Object Count -Descending | Select-Object -First $MaxSubcategories)) {
            $subPreviousCount = @($subGroup.Group | Where-Object { $_.incident_date.Date -ge $previousWeekStart -and $_.incident_date.Date -le $previousWeekEnd }).Count
            $subCurrentCount = @($subGroup.Group | Where-Object { $_.incident_date.Date -ge $currentWeekStart -and $_.incident_date.Date -le $currentWeekEnd }).Count
            $subRows.Add([PSCustomObject]@{
                Name = [string]$subGroup.Name
                Prev = [int]$subPreviousCount
                Curr = [int]$subCurrentCount
                Delta = [int]($subCurrentCount - $subPreviousCount)
            })
        }

        $categoryRows.Add([PSCustomObject]@{
            Category = $categoryName
            TotalCurrentWeek = $currentCount
            Share = [Math]::Round(($currentCount * 100.0) / [Math]::Max($totalCurrentWeek, 1), 1)
            PreviousWW = $previousCount
            CurrentWW = $currentCount
            Delta = $delta
            Status = $status
            StatusClass = Get-WowStatusClass -Status $status
            Items = $categoryItems
            Subs = @($subRows.ToArray())
        })
    }

    $categoryRowsArray = @($categoryRows.ToArray() | Sort-Object TotalCurrentWeek -Descending)
    $significantCategories = @($categoryRowsArray | Where-Object { $_.Status -eq 'Significant Increase' } | Sort-Object Delta -Descending)
    $intentRows = New-Object System.Collections.Generic.List[object]
    foreach ($categoryRow in $categoryRowsArray) {
        $currentCategoryRows = @($currentWeekData | Where-Object { $_.category -eq $categoryRow.Category })
        $howDoICount = @($currentCategoryRows | Where-Object { $_.help_intent -eq 'How Do I' }).Count
        $technicalCount = @($currentCategoryRows | Where-Object { $_.help_intent -eq 'Incident' }).Count
        $howDoINumbers = @($currentCategoryRows | Where-Object { $_.help_intent -eq 'How Do I' } | ForEach-Object { [string]$_.number })
        $technicalNumbers = @($currentCategoryRows | Where-Object { $_.help_intent -eq 'Incident' } | ForEach-Object { [string]$_.number })
        $categoryTotal = $currentCategoryRows.Count
        $howDoIPercentage = if ($categoryTotal -gt 0) { [Math]::Round(($howDoICount * 100.0) / $categoryTotal, 1) } else { 0.0 }

        $intentRows.Add([PSCustomObject]@{
            Category = $categoryRow.Category
            HowDoI = $howDoICount
            Technical = $technicalCount
            Total = $categoryTotal
            HowPct = $howDoIPercentage
            HowDoINumbers = $howDoINumbers
            TechnicalNumbers = $technicalNumbers
        })
    }

    $intentRowsArray = @($intentRows.ToArray() | Sort-Object -Property @{ Expression = 'HowDoI'; Descending = $true }, @{ Expression = 'Total'; Descending = $true })
    $overallHowDoI = @($currentWeekData | Where-Object { $_.help_intent -eq 'How Do I' }).Count
    $overallTechnical = @($currentWeekData | Where-Object { $_.help_intent -eq 'Incident' }).Count
    $overallTotal = $currentWeekData.Count
    $overallHowDoIPercentage = if ($overallTotal -gt 0) { [Math]::Round(($overallHowDoI * 100.0) / $overallTotal, 1) } else { 0.0 }
    $topHowDoIIssues = @($currentWeekData | Where-Object { $_.help_intent -eq 'How Do I' } | Group-Object short_desc | Sort-Object Count -Descending | Select-Object -First 5)

    $incorrectClassificationCount = @($currentWeekData | Where-Object { $_.is_incorrect_classification }).Count
    $misroutedCount = @($currentWeekData | Where-Object { $_.is_misrouted }).Count

    $misroutePathRows = @(
        $currentWeekData |
        Where-Object { $_.is_misrouted } |
        ForEach-Object {
            $targetGroup = if ([string]::IsNullOrWhiteSpace([string]$_.assignment_group)) { 'Unknown Target Group' } else { [string]$_.assignment_group }
            [PSCustomObject]@{
                Route = [string]::Format('OSD L1 -> {0}', $targetGroup)
                IncidentNumber = [string]$_.number
                Category = [string]$_.category
            }
        } |
        Group-Object Route |
        ForEach-Object {
            [PSCustomObject]@{
                Route = [string]$_.Name
                Count = @($_.Group).Count
                IncidentNumbers = @($_.Group | Select-Object -ExpandProperty IncidentNumber)
            }
        } |
        Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Route'; Descending = $false }
    )

    $categoryTurnaroundRows = @(
        $currentWeekData |
        Where-Object { $_.is_l3_escalation -and $null -ne $_.time_to_assignment_minutes -and $_.time_to_assignment_minutes -gt 0 } |
        Group-Object category |
        ForEach-Object {
            $minutesList = @($_.Group | ForEach-Object { [int]$_.time_to_assignment_minutes })
            $avgMinutes = if ($minutesList.Count -gt 0) { [Math]::Round((($minutesList | Measure-Object -Average).Average), 0) } else { $null }
            [PSCustomObject]@{
                Category = [string]$_.Name
                L3EscalatedIncidents = @($_.Group).Count
                AvgTurnaroundMinutes = $avgMinutes
                AvgTurnaroundDisplay = Format-MinutesAsDuration -Minutes $avgMinutes
            }
        } |
        Sort-Object -Property @{ Expression = 'L3EscalatedIncidents'; Descending = $true }, @{ Expression = 'Category'; Descending = $false }
    )

    $osdToCollabBaseRows = @(
        $currentWeekData |
        Where-Object {
            $_.is_l3_escalation -and
            $_.assignment_group -match '(?i)collaboration\s*ops\s*spt' -and
            $null -ne $_.time_to_assignment_minutes -and
            $_.time_to_assignment_minutes -gt 0
        }
    )

    $osdToCollabEscalationMetric = [PSCustomObject]@{
        EscalatedIncidents = @($osdToCollabBaseRows).Count
        AvgMinutes = if (@($osdToCollabBaseRows).Count -gt 0) { [Math]::Round(((@($osdToCollabBaseRows | ForEach-Object { [int]$_.time_to_assignment_minutes }) | Measure-Object -Average).Average), 0) } else { $null }
        AvgDisplay = if (@($osdToCollabBaseRows).Count -gt 0) {
            $avg = [Math]::Round(((@($osdToCollabBaseRows | ForEach-Object { [int]$_.time_to_assignment_minutes }) | Measure-Object -Average).Average), 0)
            (Format-MinutesAsDuration -Minutes $avg)
        } else {
            'n/a'
        }
    }

    $osdToCollabByCategoryRows = @(
        $osdToCollabBaseRows |
        Group-Object category |
        ForEach-Object {
            $minutesList = @($_.Group | ForEach-Object { [int]$_.time_to_assignment_minutes })
            $avgMinutes = if ($minutesList.Count -gt 0) { [Math]::Round((($minutesList | Measure-Object -Average).Average), 0) } else { $null }
            [PSCustomObject]@{
                Category = [string]$_.Name
                IncidentCount = @($_.Group).Count
                AvgMinutes = $avgMinutes
                AvgDisplay = Format-MinutesAsDuration -Minutes $avgMinutes
            }
        } |
        Sort-Object -Property @{ Expression = 'IncidentCount'; Descending = $true }, @{ Expression = 'Category'; Descending = $false }
    )

    # L1 to L3 escalation count and average time (from ticket creation to L3 escalation)
    $l1ToL3EscalationCount = @($currentWeekData | Where-Object { $_.is_l3_escalation }).Count
    $l1ToL3EscalationWithTimeRows = @($currentWeekData | Where-Object { $_.is_l3_escalation -and $null -ne $_.time_to_assignment_minutes -and $_.time_to_assignment_minutes -gt 0 })
    $l1ToL3AvgDisplay = if (@($l1ToL3EscalationWithTimeRows).Count -gt 0) {
        $avg = [Math]::Round(((@($l1ToL3EscalationWithTimeRows | ForEach-Object { [int]$_.time_to_assignment_minutes }) | Measure-Object -Average).Average), 0)
        Format-MinutesAsDuration -Minutes $avg
    } else { 'n/a' }

    $categoryMttrRows = @(
        $currentWeekData |
        Group-Object category |
        ForEach-Object {
            $minutesList = @($_.Group | Where-Object { $null -ne $_.business_duration_minutes -and $_.business_duration_minutes -gt 0 } | ForEach-Object { [int]$_.business_duration_minutes })
            $avgMinutes = if ($minutesList.Count -gt 0) { [Math]::Round((($minutesList | Measure-Object -Average).Average), 0) } else { $null }
            [PSCustomObject]@{
                Category = [string]$_.Name
                IncidentCount = @($_.Group).Count
                MeanResolutionMinutes = $avgMinutes
                MeanResolutionDisplay = Format-MinutesAsDuration -Minutes $avgMinutes
            }
        } |
        Sort-Object -Property @{ Expression = 'IncidentCount'; Descending = $true }, @{ Expression = 'Category'; Descending = $false } |
        Select-Object -First 12
    )

    $categorySentimentRows = @(
        $currentWeekData |
        Group-Object category |
        ForEach-Object {
            $positiveGroup  = @($_.Group | Where-Object { $_.user_sentiment -eq 'Positive' })
            $negativeGroup  = @($_.Group | Where-Object { $_.user_sentiment -eq 'Negative' })
            $neutralGroup   = @($_.Group | Where-Object { $_.user_sentiment -eq 'Neutral' })
            $improvedGroup  = @($_.Group | Where-Object { $_.sentiment_shift -eq 'Improved' })
            $noChangeGroup  = @($_.Group | Where-Object { $_.sentiment_shift -eq 'No Change' })
            $worsenedGroup  = @($_.Group | Where-Object { $_.sentiment_shift -eq 'Worsened' })
            $positive = $positiveGroup.Count
            $negative = $negativeGroup.Count
            $neutral  = $neutralGroup.Count
            $dominant = if ($negative -gt $positive -and $negative -gt $neutral) { 'Negative' } elseif ($positive -gt $negative -and $positive -gt $neutral) { 'Positive' } else { 'Neutral' }
            [PSCustomObject]@{
                Category          = [string]$_.Name
                Positive          = $positive
                Neutral           = $neutral
                Negative          = $negative
                DominantSentiment = $dominant
                PositiveNumbers   = @($positiveGroup | Select-Object -ExpandProperty number)
                NeutralNumbers    = @($neutralGroup  | Select-Object -ExpandProperty number)
                NegativeNumbers   = @($negativeGroup | Select-Object -ExpandProperty number)
                Improved          = @($improvedGroup).Count
                NoChange          = @($noChangeGroup).Count
                Worsened          = @($worsenedGroup).Count
                ImprovedNumbers   = @($improvedGroup | Select-Object -ExpandProperty number)
                NoChangeNumbers   = @($noChangeGroup | Select-Object -ExpandProperty number)
                WorsenedNumbers   = @($worsenedGroup | Select-Object -ExpandProperty number)
            }
        } |
        Sort-Object -Property @{ Expression = 'Category'; Descending = $false }
    )

    $trendIssueRows = New-Object System.Collections.Generic.List[object]
    foreach ($categoryRow in @($categoryRowsArray)) {
        foreach ($subRow in @($categoryRow.Subs)) {
            if ($subRow.Delta -le 0) { continue }

            $trendIssueRows.Add([PSCustomObject]@{
                Category = [string]$categoryRow.Category
                Subcategory = [string]$subRow.Name
                PreviousWW = [int]$subRow.Prev
                CurrentWW = [int]$subRow.Curr
                Delta = [int]$subRow.Delta
            })
        }
    }

    $trendTopIssues = @($trendIssueRows.ToArray() | Sort-Object -Property @{ Expression = 'Delta'; Descending = $true }, @{ Expression = 'CurrentWW'; Descending = $true }, @{ Expression = 'Category'; Descending = $false } | Select-Object -First 5)
    if ($trendTopIssues.Count -eq 0) {
        $trendTopIssues = @(
            $currentWeekData |
            Group-Object category, subcategory |
            Sort-Object Count -Descending |
            Select-Object -First 5 |
            ForEach-Object {
                $first = @($_.Group | Select-Object -First 1)[0]
                [PSCustomObject]@{
                    Category = [string]$first.category
                    Subcategory = [string]$first.subcategory
                    PreviousWW = 0
                    CurrentWW = [int]$_.Count
                    Delta = [int]$_.Count
                }
            }
        )
    }

    $actionPlan = New-Object System.Collections.Generic.List[string]
    $misroutePct = [Math]::Round(($misroutedCount * 100.0) / [Math]::Max($totalCurrentWeek, 1), 1)
    $gapPct = [Math]::Round(($taxonomyGapCount * 100.0) / [Math]::Max($totalCurrentWeek, 1), 1)

    if (@($trendTopIssues).Count -gt 0) {
        $topTrend = $trendTopIssues[0]
        $actionPlan.Add([string]::Format('TREND ACTION: Reduce "{0} > {1}" from {2} to <= {3} incidents next work week by publishing a focused runbook/KB and routing guide.', $topTrend.Category, $topTrend.Subcategory, $topTrend.CurrentWW, [Math]::Max($topTrend.CurrentWW - $topTrend.Delta, 0)))
    }

    $actionPlan.Add([string]::Format('ROUTING ACTION: Cut misrouted incidents from {0}% to <= {1}% by enforcing queue rules for known wrong-queue patterns.', $misroutePct, [Math]::Max($misroutePct - 3, 1)))
    $actionPlan.Add([string]::Format('DATA QUALITY ACTION: Reduce unmapped resolution-category tickets from {0}% to <= {1}% by updating strict category/subcategory mapping for top misses.', $gapPct, [Math]::Max($gapPct - 5, 2)))

    $overallResolveMinutesList = @($currentWeekData | Where-Object { $null -ne $_.business_duration_minutes -and $_.business_duration_minutes -gt 0 } | ForEach-Object { [int]$_.business_duration_minutes })
    $overallResolveAvgMinutes = if ($overallResolveMinutesList.Count -gt 0) { [Math]::Round((($overallResolveMinutesList | Measure-Object -Average).Average), 0) } else { $null }

    return [PSCustomObject]@{
        AnalysisLabel = [string]$ReportContext.AnalysisLabel
        CurrentWeekStart = $currentWeekStart
        CurrentWeekEnd = $currentWeekEnd
        PreviousWeekStart = $previousWeekStart
        PreviousWeekEnd = $previousWeekEnd
        CurrentWW = $currentWeekNumber
        PreviousWW = $previousWeekNumber
        TotalPreviousWeek = $totalPreviousWeek
        WeekOverWeekDelta = $weekOverWeekDelta
        CalendarCurrentWW = $ReportContext.CalendarCurrentWW
        CalendarCurrentWeekStart = $ReportContext.CalendarCurrentWeekStart
        CalendarCurrentWeekEnd = $ReportContext.CalendarCurrentWeekEnd
        TotalTwoWeekIncidents = $totalTwoWeekIncidents
        TotalCurrentWeek = $totalCurrentWeek
        TaxonomyGapCount = $taxonomyGapCount
        StatusCounts = [PSCustomObject]$statusCounts
        CategoryRows = $categoryRowsArray
        SignificantCategories = $significantCategories
        IntentRows = $intentRowsArray
        OverallHowDoI = $overallHowDoI
        OverallTechnical = $overallTechnical
        OverallTotal = $overallTotal
        OverallHowDoIPct = $overallHowDoIPercentage
        IncorrectClassificationCount = $incorrectClassificationCount
        MisroutedCount = $misroutedCount
        MisroutePathRows = $misroutePathRows
        CategoryTurnaroundRows = $categoryTurnaroundRows
        OSDToCollabEscalationMetric = $osdToCollabEscalationMetric
        OSDToCollabByCategoryRows = $osdToCollabByCategoryRows
        L1ToL3EscalationCount = $l1ToL3EscalationCount
        L1ToL3AvgDisplay = $l1ToL3AvgDisplay
        OverallResolveAvgDisplay = Format-MinutesAsDuration -Minutes $overallResolveAvgMinutes
        CategoryMttrRows = $categoryMttrRows
        CategorySentimentRows = $categorySentimentRows
        TopHowDoIIssues = $topHowDoIIssues
        ActionPlan = @($actionPlan.ToArray())
        TrendTopIssues = $trendTopIssues
        ServiceNowPortalBase = 'https://intel.service-now.com/nav_to.do?uri=incident.do?sysparm_query=number='
    }
}

function ConvertTo-StrictHtmlText {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Value)
}

function New-StrictCategoryReportHtml {
    param(
        [array]$IncidentAnalyses,
        [array]$RawIncidents,
        [psobject]$ReportContext
    )

    $rawMap = @{}
    foreach ($r in @($RawIncidents)) {
        if ($null -ne $r -and -not [string]::IsNullOrWhiteSpace([string]$r.number)) {
            $rawMap[[string]$r.number] = $r
        }
    }

    $analyses = @($IncidentAnalyses)
    $strictCategoryCount = (@($analyses | Select-Object -ExpandProperty primary_category | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)).Count

    $wwLabel = 'Current Work Week'
    $periodText = 'Current Work Week'
    if ($null -ne $ReportContext) {
        $wwLabel = [string]$ReportContext.AnalysisLabel
        try {
            $periodText = [string]::Format('{0} ({1:MMM d, yyyy} - {2:MMM d, yyyy})', $wwLabel, [datetime]$ReportContext.AnalysisWeekStart, [datetime]$ReportContext.AnalysisWeekEnd)
        } catch {
            $periodText = $wwLabel
        }
    }

    $groups = @($analyses | Group-Object primary_category | Sort-Object @{Expression='Count';Descending=$true}, @{Expression='Name';Descending=$false})

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<!DOCTYPE html>`r`n")
    [void]$sb.Append('<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Resolved Tickets AI Categorization</title>')
    [void]$sb.Append('<style>')
    [void]$sb.Append('body{font-family:Segoe UI,Arial,sans-serif;margin:0;padding:20px;background:#f5f7fa;color:#1f2937;}')
    [void]$sb.Append('.container{max-width:1400px;margin:0 auto;}')
    [void]$sb.Append('.hero{background:linear-gradient(135deg,#0071c5,#1e40af);color:#fff;padding:22px 26px;border-radius:12px;margin-bottom:18px;box-shadow:0 4px 12px rgba(0,0,0,0.08);}')
    [void]$sb.Append('.hero h1{margin:0 0 6px;font-size:24px;}.hero p{margin:0;font-size:13px;color:#dbeafe;}')
    [void]$sb.Append('.stats{display:flex;gap:16px;flex-wrap:wrap;margin-bottom:18px;}')
    [void]$sb.Append('.stat{background:#fff;border:1px solid #e5e7eb;border-radius:10px;padding:14px 22px;min-width:180px;box-shadow:0 1px 3px rgba(0,0,0,0.05);}')
    [void]$sb.Append('.stat .v{font-size:28px;font-weight:700;color:#0071c5;}.stat .l{font-size:12px;color:#6b7280;margin-top:4px;text-transform:uppercase;letter-spacing:.04em;}')
    [void]$sb.Append('.card{background:#fff;border:1px solid #e5e7eb;border-radius:12px;margin-bottom:18px;box-shadow:0 2px 4px rgba(0,0,0,0.04);overflow:hidden;}')
    [void]$sb.Append('.card h2{margin:0;padding:14px 18px;background:#f1f5f9;font-size:16px;color:#0f172a;border-bottom:1px solid #e2e8f0;}')
    [void]$sb.Append('table{width:100%;border-collapse:collapse;font-size:13px;}')
    [void]$sb.Append('th{background:#0071c5;color:#fff;padding:10px 12px;text-align:left;font-size:12px;text-transform:uppercase;letter-spacing:.04em;}')
    [void]$sb.Append('td{padding:10px 12px;border-bottom:1px solid #eef2f7;vertical-align:top;}tr:hover td{background:#f8fafc;}')
    [void]$sb.Append('.tickets a{display:inline-block;margin:2px 4px 2px 0;padding:3px 8px;background:#eff6ff;color:#1d4ed8;border:1px solid #bfdbfe;border-radius:999px;text-decoration:none;font-size:12px;font-weight:600;}')
    [void]$sb.Append('.tickets a:hover{background:#dbeafe;}.count{font-weight:700;color:#0071c5;text-align:center;}')
    [void]$sb.Append('.sn-btn{display:inline-block;background:#0071c5;color:#fff;padding:6px 10px;border-radius:6px;text-decoration:none;font-size:12px;font-weight:600;}.sn-btn:hover{background:#1e40af;}')
    [void]$sb.Append('.detail{font-size:12.5px;line-height:1.5;}.detail .label{font-weight:700;color:#0f172a;}.detail .block{margin-bottom:6px;}.detail ul{margin:4px 0 6px 18px;padding:0;}.detail li{margin:2px 0;}')
    [void]$sb.Append('.conf-High{color:#065f46;background:#d1fae5;padding:2px 8px;border-radius:999px;font-size:11px;font-weight:700;}')
    [void]$sb.Append('.conf-Medium{color:#92400e;background:#fef3c7;padding:2px 8px;border-radius:999px;font-size:11px;font-weight:700;}')
    [void]$sb.Append('.conf-Low{color:#991b1b;background:#fee2e2;padding:2px 8px;border-radius:999px;font-size:11px;font-weight:700;}')
    [void]$sb.Append('.inc-link{font-family:Consolas,monospace;color:#0071c5;text-decoration:none;font-weight:700;}.inc-link:hover{text-decoration:underline;}')
    [void]$sb.Append('.detail .ai-card{margin-top:10px;border:1px solid #d6e4f3;border-radius:10px;overflow:hidden;background:linear-gradient(180deg,#f5f9ff 0%, #ffffff 100%);box-shadow:0 1px 2px rgba(20,40,80,0.05);}')
    [void]$sb.Append('.detail .ai-card .ai-head{padding:8px 12px;background:linear-gradient(90deg,#1f4e79 0%, #2d6cb0 100%);color:#fff;font-weight:600;font-size:13px;letter-spacing:0.3px;}')
    [void]$sb.Append('.detail .ai-card .ai-body{padding:10px 12px;}.detail .ai-card .ai-row{display:flex;gap:10px;align-items:flex-start;margin:6px 0;}')
    [void]$sb.Append('.detail .ai-card .ai-tag{flex:0 0 170px;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;padding:3px 8px;border-radius:12px;color:#fff;text-align:center;line-height:1.4;}')
    [void]$sb.Append('.detail .ai-card .tag-sum{background:#2d6cb0;}.detail .ai-card .tag-rc{background:#b85c00;}.detail .ai-card .tag-impr{background:#2e8b57;}')
    [void]$sb.Append('.detail .ai-card .ai-text{flex:1;color:#1f2a36;line-height:1.5;font-size:13px;}.detail .ai-card .ai-list{margin:2px 0 2px 18px;padding:0;}')
    [void]$sb.Append('html{scroll-behavior:smooth;}.tickets a.pill-anchor{cursor:pointer;}.tickets a.pill-anchor::after{content:" \2193";opacity:0.65;font-size:0.85em;}')
    [void]$sb.Append(':target.detail-row, tr:target{background:#fff7d6 !important;transition:background 0.6s ease;}')
    [void]$sb.Append('.detail .wn-list{margin:4px 0 6px 0;padding:0 0 0 18px;}.detail .wn-list li{margin:3px 0;line-height:1.45;}')
    [void]$sb.Append('.detail .wn-list .wn-date{display:inline-block;font-family:Consolas,monospace;font-size:11px;color:#0071c5;background:#eff6ff;border:1px solid #bfdbfe;border-radius:4px;padding:0 5px;margin-right:6px;font-weight:600;}')
    [void]$sb.Append('.footer{margin-top:18px;text-align:center;font-size:11px;color:#6b7280;}')
    [void]$sb.Append('</style></head><body><div class="container">')

    [void]$sb.Append('<div class="hero"><h1>Resolved Tickets AI Categorization Analysis</h1><p>Analysis Period: ' + (ConvertTo-StrictHtmlText $periodText) + ' | Service Offering: Productivity Tools | Business Service: End-User Collaboration</p></div>')
    [void]$sb.Append('<div class="stats"><div class="stat"><div class="v">' + $analyses.Count + '</div><div class="l">Resolved Tickets Processed</div></div><div class="stat"><div class="v">' + $strictCategoryCount + '</div><div class="l">Strict Categories</div></div><div class="stat"><div class="v">' + (ConvertTo-StrictHtmlText $wwLabel) + '</div><div class="l">Analysis Work Week</div></div></div>')

    [void]$sb.Append('<div class="card"><h2>1. Strict Category Summary</h2><div class="body"><table><thead><tr><th style="width:38%;">Strict Category</th><th style="width:8%;text-align:center;">Count</th><th style="width:54%;">Ticket Numbers (ServiceNow)</th></tr></thead><tbody>')
    foreach ($g in $groups) {
        $pillHtml = ''
        foreach ($a in (@($g.Group) | Sort-Object incident_number)) {
            $n = ConvertTo-StrictHtmlText ([string]$a.incident_number)
            $pillHtml += ('<a href="#inc-' + $n + '" class="pill-anchor">' + $n + '</a>')
        }
        [void]$sb.Append('<tr><td>' + (ConvertTo-StrictHtmlText ([string]$g.Name)) + '</td><td class="count">' + $g.Count + '</td><td class="tickets">' + $pillHtml + '</td></tr>')
    }
    [void]$sb.Append('</tbody></table></div></div>')

    [void]$sb.Append('<div class="card"><h2>2. Detailed Incident Analysis</h2><div class="body"><table><thead><tr><th style="width:10%;">Incident</th><th style="width:14%;">Strict Category</th><th style="width:14%;">Strict Subcategory</th><th style="width:54%;">Detailed Summary</th><th style="width:8%;text-align:center;">Link</th></tr></thead><tbody>')

    $sortedAnalyses = @($analyses | Sort-Object @{ Expression = {
        $val = [string]$_.resolved_at
        try { [datetime]::Parse($val, [Globalization.CultureInfo]::InvariantCulture) } catch { [datetime]::MinValue }
    }; Descending = $true })

    foreach ($a in $sortedAnalyses) {
        $num = [string]$a.incident_number
        $raw = $null
        if ($rawMap.ContainsKey($num)) { $raw = $rawMap[$num] }
        $sysId = ''
        if ($null -ne $raw) { $sysId = [string]$raw.sys_id }
        $link = '#'
        if (-not [string]::IsNullOrWhiteSpace($sysId)) {
            $link = 'https://intel.service-now.com/nav_to.do?uri=incident.do?sys_id=' + $sysId
        }

        $cat = [string]$a.primary_category
        $sub = [string]$a.sub_category
        if ([string]::IsNullOrWhiteSpace($sub)) { $sub = [string]$a.llm_primary_category }

        $actionsHtml = ''
        if ($null -ne $a.what_was_done) {
            foreach ($item in @($a.what_was_done)) {
                $t = [string]$item
                if (-not [string]::IsNullOrWhiteSpace($t)) { $actionsHtml += '<li>' + (ConvertTo-StrictHtmlText $t) + '</li>' }
            }
        }
        $signalsHtml = ''
        if ($null -ne $a.evidence_signals) {
            foreach ($item in @($a.evidence_signals)) {
                $t = [string]$item
                if (-not [string]::IsNullOrWhiteSpace($t)) { $signalsHtml += '<li>' + (ConvertTo-StrictHtmlText $t) + '</li>' }
            }
        }
        $imprHtml = ''
        if ($null -ne $a.what_can_be_improved) {
            foreach ($item in @($a.what_can_be_improved)) {
                $t = [string]$item
                if (-not [string]::IsNullOrWhiteSpace($t)) { $imprHtml += '<li>' + (ConvertTo-StrictHtmlText $t) + '</li>' }
            }
        }

        $wnHtml = ''
        $cleanNotes = [string]$a.work_notes_clean
        if (-not [string]::IsNullOrWhiteSpace($cleanNotes)) {
            $entryCount = 0
            foreach ($line in ($cleanNotes -split "`r?`n")) {
                $t = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($t)) { continue }
                if ($t -match '^(?:[-*]|\d+\.)\s+(.*)$') { $t = $Matches[1].Trim() }
                if ($t -match '(?i)^(?:\*\*)?timeline of key events(?:\*\*)?\s*:?\s*$') { continue }
                if ($t.Length -lt 2) { continue }
                if ($entryCount -ge 12) { break }
                $datePrefix = ''
                if ($t -match '^\*\*\[([^\]]+)\]\*\*\s*-?\s*(.*)$') {
                    $datePrefix = '<span class="wn-date">[' + (ConvertTo-StrictHtmlText $Matches[1]) + ']</span> '
                    $t = $Matches[2].Trim()
                } elseif ($t -match '^\[([^\]]+)\]\s*-?\s*(.*)$') {
                    $datePrefix = '<span class="wn-date">[' + (ConvertTo-StrictHtmlText $Matches[1]) + ']</span> '
                    $t = $Matches[2].Trim()
                }
                $t = $t -replace '\*\*([^*]+)\*\*', '<strong>$1</strong>'
                $wnHtml += '<li>' + $datePrefix + (ConvertTo-StrictHtmlText $t).Replace('&lt;strong&gt;', '<strong>').Replace('&lt;/strong&gt;', '</strong>') + '</li>'
                $entryCount++
            }
        }
        if ([string]::IsNullOrWhiteSpace($wnHtml) -and $null -ne $raw -and -not [string]::IsNullOrWhiteSpace([string]$raw.work_notes)) {
            $currentDate = ''
            $entryCount = 0
            foreach ($line in (([string]$raw.work_notes) -split "`r?`n")) {
                $t = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($t)) { continue }
                if ($t -match '^(\d{4}-\d{2}-\d{2})\s+\d{2}:\d{2}:\d{2}\s*-') {
                    $currentDate = $Matches[1]
                    continue
                }
                if ($entryCount -ge 8) { break }
                $datePrefix = ''
                if (-not [string]::IsNullOrWhiteSpace($currentDate)) {
                    $datePrefix = '<span class="wn-date">[' + $currentDate + ']</span> '
                }
                $wnHtml += '<li>' + $datePrefix + (ConvertTo-StrictHtmlText $t) + '</li>'
                $entryCount++
            }
        }

        $aiBody = ''
        $qlText = [string]$a.quick_look
        if (-not [string]::IsNullOrWhiteSpace($qlText)) {
            $aiBody += '<div class="ai-row"><div class="ai-tag tag-sum">Summary</div><div class="ai-text">' + (ConvertTo-StrictHtmlText $qlText) + '</div></div>'
        }
        $rcText = [string]$a.probable_root_cause
        if (-not [string]::IsNullOrWhiteSpace($rcText)) {
            $aiBody += '<div class="ai-row"><div class="ai-tag tag-rc">Probable Root Cause</div><div class="ai-text">' + (ConvertTo-StrictHtmlText $rcText) + '</div></div>'
        }
        if ($imprHtml) {
            $aiBody += '<div class="ai-row"><div class="ai-tag tag-impr">Improvement Opportunities</div><div class="ai-text"><ul class="ai-list">' + $imprHtml + '</ul></div></div>'
        }

        $conf = [string]$a.confidence
        if ([string]::IsNullOrWhiteSpace($conf)) { $conf = 'Medium' }
        $confClass = 'conf-Medium'
        if ($conf -eq 'High' -or $conf -eq 'Medium' -or $conf -eq 'Low') { $confClass = 'conf-' + $conf }

        $detail = ''
        $issueText = [string]$a.issue_summary
        if (-not [string]::IsNullOrWhiteSpace($issueText)) {
            $detail += '<div class="block"><span class="label">Problem:</span> ' + (ConvertTo-StrictHtmlText $issueText) + '</div>'
        }
        if ($actionsHtml) {
            $detail += '<div class="block"><span class="label">Key Actions:</span><ul>' + $actionsHtml + '</ul></div>'
        }
        if ($signalsHtml) {
            $detail += '<div class="block"><span class="label">Critical Details:</span><ul>' + $signalsHtml + '</ul></div>'
        }
        if ($wnHtml) {
            $detail += '<div class="block"><span class="label">Work Notes:</span><ul class="wn-list">' + $wnHtml + '</ul></div>'
        }
        if ($aiBody) {
            $detail += '<div class="ai-card"><div class="ai-head">&#9889; AI Analysis</div><div class="ai-body">' + $aiBody + '</div></div>'
        }
        $detail += '<div class="block"><span class="label">Confidence Level:</span> <span class="' + $confClass + '">' + (ConvertTo-StrictHtmlText $conf) + '</span></div>'

        $numEnc = ConvertTo-StrictHtmlText $num
        $linkEnc = ConvertTo-StrictHtmlText $link
        [void]$sb.Append('<tr id="inc-' + $numEnc + '" class="detail-row"><td><a class="inc-link" href="' + $linkEnc + '" target="_blank" rel="noopener">' + $numEnc + '</a></td><td>' + (ConvertTo-StrictHtmlText $cat) + '</td><td>' + (ConvertTo-StrictHtmlText $sub) + '</td><td class="detail">' + $detail + '</td><td style="text-align:center;"><a class="sn-btn" href="' + $linkEnc + '" target="_blank" rel="noopener">Open</a></td></tr>')
    }
    [void]$sb.Append('</tbody></table></div></div>')
    [void]$sb.Append('<div class="footer">Generated at ' + (ConvertTo-StrictHtmlText ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))) + '</div>')
    [void]$sb.Append('</div></body></html>')

    return $sb.ToString()
}

function New-WeeklyDashboardHtml {
    param(
        [psobject]$DashboardData,
        [int]$TopCategories = 15
    )

    $maxTotal = ($DashboardData.CategoryRows | Measure-Object TotalCurrentWeek -Maximum).Maximum
    if ($maxTotal -lt 1) {
        $maxTotal = 1
    }

    $stringBuilder = New-Object System.Text.StringBuilder
    [void]$stringBuilder.AppendLine('<!DOCTYPE html>')
    [void]$stringBuilder.AppendLine('<html lang="en">')
    [void]$stringBuilder.AppendLine('<head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>')
    [void]$stringBuilder.AppendLine(('<title>Productivity Tools - WW{0} vs WW{1} Weekly Dashboard</title>' -f $DashboardData.PreviousWW, $DashboardData.CurrentWW))
    [void]$stringBuilder.AppendLine('<style>')
    [void]$stringBuilder.AppendLine('*{box-sizing:border-box}')
    [void]$stringBuilder.AppendLine(':root{--navy:#0f172a;--slate:#334155;--muted:#64748b;--line:#e2e8f0;--bg:#f1f5f9;--sig-bg:#fef2f2;--sig-border:#fca5a5;--sig-text:#991b1b;--inc-bg:#fffbeb;--inc-border:#fcd34d;--inc-text:#92400e;--stb-bg:#f0f9ff;--stb-border:#7dd3fc;--stb-text:#0c4a6e;--dec-bg:#f0fdf4;--dec-border:#86efac;--dec-text:#14532d;}')
    [void]$stringBuilder.AppendLine('body{margin:0;font-family:"Segoe UI",system-ui,Arial,sans-serif;background:var(--bg);color:var(--navy);font-size:14px;}')
    [void]$stringBuilder.AppendLine('.page{max-width:1480px;margin:0 auto;padding:20px 24px 40px;}')
    [void]$stringBuilder.AppendLine('.hero{background:linear-gradient(135deg,#0f172a 0%,#1e3a5f 100%);color:#fff;border-radius:16px;padding:24px 28px;margin-bottom:20px;box-shadow:0 8px 24px rgba(15,23,42,.3);}')
    [void]$stringBuilder.AppendLine('.hero h1{margin:0 0 4px;font-size:24px;font-weight:700;letter-spacing:-.3px;}')
    [void]$stringBuilder.AppendLine('.hero .sub{color:#cbd5e1;font-size:13px;margin:4px 0 0;}')
    [void]$stringBuilder.AppendLine('.hero .ww{margin-top:10px;background:rgba(255,255,255,.08);border-radius:8px;padding:8px 14px;display:inline-block;font-size:13px;color:#e2e8f0;}')
    [void]$stringBuilder.AppendLine('.hero .ai-note{margin-top:12px;padding:10px 12px;border:1px solid rgba(125,211,252,.35);background:rgba(15,23,42,.25);border-radius:10px;color:#e2e8f0;line-height:1.45;}')
    [void]$stringBuilder.AppendLine('.kpi-row{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px;margin-bottom:20px;}')
    [void]$stringBuilder.AppendLine('.kpi{background:#fff;border:1px solid var(--line);border-radius:12px;padding:14px 16px;box-shadow:0 1px 4px rgba(15,23,42,.05);}')
    [void]$stringBuilder.AppendLine('.kpi .v{font-size:28px;font-weight:800;line-height:1.1;color:var(--navy);}')
    [void]$stringBuilder.AppendLine('.kpi .l{font-size:11px;text-transform:uppercase;letter-spacing:.07em;color:var(--muted);margin-top:4px;}')
    [void]$stringBuilder.AppendLine('.sec{margin-bottom:28px;} .sec-hdr{display:flex;align-items:center;gap:10px;margin-bottom:12px;} .sec-hdr h2{margin:0;font-size:17px;font-weight:700;color:var(--navy);} .sec-num{background:var(--navy);color:#fff;border-radius:50%;width:26px;height:26px;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:700;flex-shrink:0;}')
    [void]$stringBuilder.AppendLine('.pill{display:inline-flex;align-items:center;gap:4px;font-weight:600;padding:3px 9px;border-radius:999px;font-size:11px;white-space:nowrap;} .pill.sig{background:var(--sig-bg);color:var(--sig-text);border:1px solid var(--sig-border);} .pill.inc{background:var(--inc-bg);color:var(--inc-text);border:1px solid var(--inc-border);} .pill.stb{background:var(--stb-bg);color:var(--stb-text);border:1px solid var(--stb-border);} .pill.dec{background:var(--dec-bg);color:var(--dec-text);border:1px solid var(--dec-border);}')
    [void]$stringBuilder.AppendLine('.card{background:#fff;border:1px solid var(--line);border-radius:12px;overflow:hidden;box-shadow:0 1px 4px rgba(15,23,42,.05);} table{width:100%;border-collapse:collapse;} th{background:#f8fafc;color:var(--slate);font-size:12px;text-transform:uppercase;letter-spacing:.05em;padding:10px 12px;border-bottom:1px solid var(--line);text-align:left;white-space:nowrap;} td{padding:9px 12px;border-bottom:1px solid #f1f5f9;vertical-align:middle;} tr:last-child td{border-bottom:none;} tr:hover td{background:#f8fafc;} .rank{font-size:11px;font-weight:700;color:var(--muted);width:28px;} .cat-name{font-weight:600;font-size:13px;} .vol-bar{height:6px;border-radius:3px;background:#3b82f6;display:inline-block;vertical-align:middle;margin-right:6px;} .vol-num{font-size:12px;color:var(--slate);} .delta-up{color:#dc2626;font-weight:700;} .delta-dn{color:#16a34a;font-weight:700;} .delta-fl{color:var(--muted);} .ww-nums{font-size:13px;color:var(--slate);} .sub-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(380px,1fr));gap:12px;} .sub-card{background:#fff;border:1px solid var(--line);border-radius:12px;overflow:hidden;box-shadow:0 1px 4px rgba(15,23,42,.05);} .sub-card .sc2-hdr{padding:10px 14px;background:#f8fafc;border-bottom:1px solid var(--line);font-weight:700;font-size:13px;display:flex;justify-content:space-between;align-items:center;} .sub-card .total-badge{background:#e0f2fe;color:#0369a1;border-radius:999px;padding:2px 8px;font-size:11px;}')
    [void]$stringBuilder.AppendLine('.sig-section{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:14px;} .sig-card{background:#fff;border:1px solid var(--line);border-radius:12px;overflow:hidden;box-shadow:0 1px 4px rgba(15,23,42,.05);} .sig-card .sh{display:flex;justify-content:space-between;align-items:center;padding:12px 16px;border-bottom:2px solid var(--sig-border);background:var(--sig-bg);} .sig-card .title{font-weight:700;font-size:14px;color:var(--sig-text);} .sig-card .ww-info{font-size:12px;color:var(--sig-text);background:rgba(255,255,255,.6);border-radius:6px;padding:3px 8px;} .driver{margin:10px 14px;border:1px solid #fee2e2;border-left:4px solid #ef4444;border-radius:8px;overflow:hidden;} .driver .dh{display:flex;justify-content:space-between;align-items:center;padding:8px 12px;background:#fff7f7;} .driver .dname{font-weight:600;font-size:13px;color:var(--slate);flex:1;} .driver .dstats{font-size:12px;color:var(--muted);white-space:nowrap;} .driver .dex{padding:6px 12px 8px;background:#fff;} .driver .ex-row{display:flex;gap:6px;margin:4px 0;font-size:12px;color:var(--muted);line-height:1.4;} .driver .ex-row::before{content:"\25B8";color:#fca5a5;flex-shrink:0;} .no-drivers{padding:12px 16px;font-size:13px;color:var(--muted);} .top5-block{padding:10px 14px 4px;border-bottom:1px solid #f1f5f9;} .t5-lbl{font-size:11px;text-transform:uppercase;letter-spacing:.07em;color:var(--muted);font-weight:600;margin-bottom:8px;} .t5-row{display:flex;align-items:center;gap:8px;margin:5px 0;} .t5-rank{font-size:11px;font-weight:700;color:var(--muted);width:16px;flex-shrink:0;text-align:right;} .t5-bar-wrap{flex:1;background:#f1f5f9;border-radius:4px;height:8px;overflow:hidden;} .t5-bar{height:8px;border-radius:4px;background:linear-gradient(90deg,#3b82f6,#6366f1);} .t5-name{font-size:12px;color:var(--slate);min-width:0;flex:2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;} .t5-count{font-size:12px;font-weight:700;color:var(--navy);white-space:nowrap;}')
    [void]$stringBuilder.AppendLine('.intent-summary{display:flex;gap:14px;flex-wrap:wrap;margin-bottom:10px;} .intent-chip{background:#fff;border:1px solid var(--line);border-radius:10px;padding:10px 12px;min-width:180px;} .intent-chip .k{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.06em;} .intent-chip .v{font-size:22px;font-weight:800;color:var(--navy);} .smart-controls{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:10px 0 12px;} .smart-controls input,.smart-controls select{border:1px solid var(--line);border-radius:8px;padding:7px 10px;font-size:12px;background:#fff;} .smart-note{font-size:12px;color:var(--muted);} .smart-insight{background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:10px 12px;margin-bottom:10px;font-size:12px;color:#0f172a;} .plan{background:#fff;border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin-top:12px;box-shadow:0 1px 4px rgba(15,23,42,.05);} .plan h3{margin:0 0 8px;font-size:14px;color:var(--navy);} .plan ul{margin:0;padding-left:18px;color:var(--slate);} .plan li{margin:6px 0;line-height:1.45;} .highlight-list{background:#fff;border:1px solid var(--line);border-radius:12px;padding:14px 16px;box-shadow:0 1px 4px rgba(15,23,42,.05);} .highlight-list ul{margin:0;padding-left:18px;} .highlight-list li{margin:6px 0;line-height:1.45;color:var(--slate);}
.inc-toggle{cursor:pointer;color:#2563eb;font-weight:600;text-decoration:none;white-space:nowrap;font-size:12px;border:none;background:none;padding:0;}
.inc-toggle:hover{text-decoration:underline;}
.inc-list{display:none;margin-top:4px;padding:4px 0 0 0;list-style:none;}
.inc-list li{font-size:11px;color:var(--slate);padding:2px 0;}
.inc-list.open{display:block;}
.inc-link{color:#2563eb;text-decoration:none;font-size:11px;font-weight:600;padding:1px 4px;border-radius:4px;border:1px solid #dbeafe;background:#eff6ff;white-space:nowrap;}
.inc-link:hover{background:#dbeafe;border-color:#93c5fd;}
.misroute-row{background:#fff;}
.misroute-row:nth-child(even){background:#fafbfc;}
.misroute-row:hover{background:#f0f6fb !important;}
.quality-table-wrapper{margin-bottom:16px;border-radius:12px;overflow:hidden;}
.quality-table-metric{background:#f8fafc;font-weight:600;color:var(--navy);padding:10px 12px !important;}
.sentiment-row{transition:background-color 150ms ease;}
.sentiment-row:hover{background:#f8fafc !important;}
.sentiment-row td:nth-child(2),.sentiment-row td:nth-child(3),.sentiment-row td:nth-child(4){text-align:center;font-weight:600;}
.smart-controls{border-bottom:1px solid #e2e8f0;padding-bottom:12px;margin-bottom:12px;}
.smart-controls input{min-width:240px;transition:border-color 150ms ease;}
.smart-controls input:focus,.smart-controls select:focus{outline:none;border-color:#3b82f6;box-shadow:0 0 0 3px rgba(59,130,246,.1);}
.smart-controls select{min-width:180px;cursor:pointer;}
.smart-note{display:inline-block;margin-left:8px;padding:0 4px;background:#f0fdf4;color:#166534;border-radius:4px;border-left:2px solid #22c55e;}
.badge-pos{display:inline-block;padding:3px 10px;border-radius:999px;font-size:12px;font-weight:700;background:#dcfce7;color:#14532d;border:1px solid #86efac;}
.badge-neg{display:inline-block;padding:3px 10px;border-radius:999px;font-size:12px;font-weight:700;background:#fee2e2;color:#7f1d1d;border:1px solid #fca5a5;}
.badge-neu{display:inline-block;padding:3px 10px;border-radius:999px;font-size:12px;font-weight:700;background:#f1f5f9;color:#334155;border:1px solid #cbd5e1;}
.mttr-val{font-weight:700;color:#0369a1;}
.mttr-na{color:#94a3b8;font-style:italic;font-size:12px;}
')
    [void]$stringBuilder.AppendLine('</style></head><body><div class="page">')
    [void]$stringBuilder.AppendLine('<script>function toggleInc(btn,id){var l=document.getElementById(id);l.classList.toggle("open");btn.textContent=l.classList.contains("open")?"hide incidents":btn.getAttribute("data-label");}function filterIntentRows(){var q=(document.getElementById("intentFilter").value||"").toLowerCase();var focus=document.getElementById("intentFocus").value;var rows=document.querySelectorAll(".intent-row");var visible=0;rows.forEach(function(r){var c=(r.getAttribute("data-category")||"").toLowerCase();var h=parseFloat(r.getAttribute("data-howpct")||"0");var t=parseInt(r.getAttribute("data-total")||"0",10);var show=c.indexOf(q)!==-1;if(show&&focus==="how-heavy"){show=h>=60;}if(show&&focus==="incident-heavy"){show=h<40;}if(show&&focus==="high-volume"){show=t>=5;}r.style.display=show?"":"none";if(show){visible++;}});var n=document.getElementById("intentVisibleCount");if(n){n.textContent=visible+" categories shown";}}function filterMisrouteRows(){var q=(document.getElementById("misrouteFilter").value||"").toLowerCase();var rows=document.querySelectorAll(".misroute-row");rows.forEach(function(r){var route=(r.getAttribute("data-route")||"").toLowerCase();r.style.display=(route.indexOf(q)!==-1)?"":"none";});}function filterSentimentRows(){var s=document.getElementById("sentimentFocus").value;var rows=document.querySelectorAll(".sentiment-row");rows.forEach(function(r){var d=(r.getAttribute("data-dominant")||"");r.style.display=(s==="all"||d===s)?"":"none";});}document.addEventListener("DOMContentLoaded",function(){if(document.getElementById("intentFilter")){filterIntentRows();}if(document.getElementById("misrouteFilter")){filterMisrouteRows();}if(document.getElementById("sentimentFocus")){filterSentimentRows();}});</script>')

    [void]$stringBuilder.AppendLine('<div class="hero">')
    [void]$stringBuilder.AppendLine(('<h1>Productivity Tools - Weekly Dashboard   WW{0} vs WW{1}</h1>' -f $DashboardData.PreviousWW, $DashboardData.CurrentWW))
    [void]$stringBuilder.AppendLine(('<p class="sub">Analysis Focus: {0} | WW{1} ({2} - {3}) | EUC Productivity Tools | Resolved and Closed Incidents</p>' -f (Escape-Html $DashboardData.AnalysisLabel), $DashboardData.CurrentWW, $DashboardData.CurrentWeekStart.ToString('MMM dd'), $DashboardData.CurrentWeekEnd.ToString('MMM dd, yyyy')))
    [void]$stringBuilder.AppendLine(('<div class="ww">Comparison window: <b>WW{0}</b> and <b>WW{1}</b> | Total incidents across both weeks: <b>{2}</b></div>' -f $DashboardData.PreviousWW, $DashboardData.CurrentWW, $DashboardData.TotalTwoWeekIncidents))
    [void]$stringBuilder.AppendLine('</div>')

    [void]$stringBuilder.AppendLine('<div class="kpi-row">')
    $weeklyDeltaLabel = if ($DashboardData.WeekOverWeekDelta -gt 0) { '+' + $DashboardData.WeekOverWeekDelta } elseif ($DashboardData.WeekOverWeekDelta -lt 0) { [string]$DashboardData.WeekOverWeekDelta } else { '0' }
    [void]$stringBuilder.AppendLine(('<div class="kpi"><div class="v">{0}</div><div class="l">Current Work Week (WW{1})</div></div>' -f $DashboardData.TotalCurrentWeek, $DashboardData.CurrentWW))
    [void]$stringBuilder.AppendLine(('<div class="kpi"><div class="v">{0}</div><div class="l">Last Work Week (WW{1})</div></div>' -f $DashboardData.TotalPreviousWeek, $DashboardData.PreviousWW))
    [void]$stringBuilder.AppendLine(('<div class="kpi"><div class="v">{0}</div><div class="l">Delta (Current vs Last WW)</div></div>' -f $weeklyDeltaLabel))
    [void]$stringBuilder.AppendLine(('<div class="kpi"><div class="v">{0}</div><div class="l">Incorrect Classification</div></div>' -f $DashboardData.IncorrectClassificationCount))
    [void]$stringBuilder.AppendLine(('<div class="kpi"><div class="v">{0}</div><div class="l">Misrouted Incidents</div></div>' -f $DashboardData.MisroutedCount))
    [void]$stringBuilder.AppendLine(('<div class="kpi"><div class="v">{0}</div><div class="l">L1 -&gt; L3 Escalations (WW{1})</div></div>' -f $DashboardData.L1ToL3EscalationCount, $DashboardData.CurrentWW))
    [void]$stringBuilder.AppendLine(('<div class="kpi"><div class="v">{0}</div><div class="l">Avg L3 Escalation Time</div></div>' -f (Escape-Html ([string]$DashboardData.L1ToL3AvgDisplay))))
    [void]$stringBuilder.AppendLine(('<div class="kpi"><div class="v">{0}</div><div class="l">Avg Time to Resolve</div></div>' -f (Escape-Html ([string]$DashboardData.OverallResolveAvgDisplay))))
    [void]$stringBuilder.AppendLine(('<div class="kpi"><div class="v">{0}</div><div class="l">Unmapped Resolution Category</div></div>' -f $DashboardData.TaxonomyGapCount))
    [void]$stringBuilder.AppendLine('</div>')

    [void]$stringBuilder.AppendLine('<div class="sec"><div class="sec-hdr"><div class="sec-num">1</div><h2>AI Highlights - Top 5 Trend Issues</h2></div><div class="highlight-list"><ul>')
    if (@($DashboardData.TrendTopIssues).Count -gt 0) {
        foreach ($trendIssue in @($DashboardData.TrendTopIssues)) {
            $deltaLabel = if ($trendIssue.Delta -gt 0) { '+' + $trendIssue.Delta } else { [string]$trendIssue.Delta }
            [void]$stringBuilder.AppendLine(('<li><b>{0} > {1}</b>: WW{2} {3} to WW{4} {5} (Delta {6})</li>' -f (Escape-Html ([string]$trendIssue.Category)), (Escape-Html ([string]$trendIssue.Subcategory)), $DashboardData.PreviousWW, $trendIssue.PreviousWW, $DashboardData.CurrentWW, $trendIssue.CurrentWW, $deltaLabel))
        }
    } else {
        [void]$stringBuilder.AppendLine('<li>No trend issues available for the selected week.</li>')
    }
    [void]$stringBuilder.AppendLine('</ul></div></div>')

    [void]$stringBuilder.AppendLine('<div class="sec"><div class="sec-hdr"><div class="sec-num">2</div><h2>Classification and Operations Quality</h2></div>')
    [void]$stringBuilder.AppendLine('<div class="card quality-table-wrapper"><table><thead><tr style="background:#f0f4f8;"><th style="color:#0f172a;font-weight:700;">Metric</th><th style="color:#0f172a;font-weight:700;">Value (WW Current)</th><th style="color:#0f172a;font-weight:700;">Definition</th></tr></thead><tbody>')
    [void]$stringBuilder.AppendLine(('<tr class="quality-table-metric"><td>Incorrect Classification</td><td>{0}</td><td>Tickets with unmapped resolution category, unknown intent, or missing ServiceNow category values.</td></tr>' -f $DashboardData.IncorrectClassificationCount))
    [void]$stringBuilder.AppendLine(('<tr><td>Total Misrouted Incidents</td><td>{0}</td><td>Tickets where escalation reason explicitly indicates misroute, wrong queue, reroute, or re-route.</td></tr>' -f $DashboardData.MisroutedCount))
    [void]$stringBuilder.AppendLine(('<tr><td>L1 -&gt; L3 Escalations</td><td style="font-weight:600;color:#991b1b;">{0}</td><td>Count of tickets in current work week flagged as escalated to L3 (via escalation_order or escalation_reason).</td></tr>' -f $DashboardData.L1ToL3EscalationCount))
    [void]$stringBuilder.AppendLine(('<tr><td>Avg Escalation Time (L1 -&gt; L3)</td><td style="font-weight:600;color:#0c4a6e;">{0}</td><td>Average time from ticket creation to L3 escalation (measured via time_to_assignment) for all L1-&gt;L3 escalated tickets in current week.</td></tr>' -f (Escape-Html ([string]$DashboardData.L1ToL3AvgDisplay))))
    [void]$stringBuilder.AppendLine('</tbody></table></div>')

    [void]$stringBuilder.AppendLine('<div class="smart-controls"><input id="misrouteFilter" type="text" placeholder="Search misroute path..." oninput="filterMisrouteRows()" /><span class="smart-note">From -> To assignment group</span></div>')
    [void]$stringBuilder.AppendLine('<div class="card quality-table-wrapper"><table><thead><tr style="background:#f0f4f8;"><th style="color:#0f172a;font-weight:700;">Misroute Path</th><th style="color:#0f172a;font-weight:700;">Count</th><th style="color:#0f172a;font-weight:700;">Incidents</th></tr></thead><tbody>')
    if (@($DashboardData.MisroutePathRows).Count -eq 0) {
        [void]$stringBuilder.AppendLine('<tr><td colspan="3">No misrouted incidents detected in current week.</td></tr>')
    } else {
        $mrIdx = 0
        foreach ($row in @($DashboardData.MisroutePathRows)) {
            $mrIdx++
            $mrId = [string]::Format('misroute-{0}', $mrIdx)
            $mrLabel = [string]::Format('show incidents ({0})', $row.Count)
            $mrNums = (($row.IncidentNumbers | ForEach-Object { [string]::Format('<li><a class="inc-link" href="{0}{1}" target="_blank">{1}</a></li>', $DashboardData.ServiceNowPortalBase, (Escape-Html $_)) }) -join '')
            $mrCell = [string]::Format('<button class="inc-toggle" data-label="{0}" onclick="toggleInc(this,&apos;{1}&apos;)">{0}</button><ul class="inc-list" id="{1}">{2}</ul>', (Escape-Html $mrLabel), $mrId, $mrNums)
            [void]$stringBuilder.AppendLine(('<tr class="misroute-row" data-route="{0}"><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f (Escape-Html ([string]$row.Route)), $row.Count, $mrCell))
        }
    }
    [void]$stringBuilder.AppendLine('</tbody></table></div>')

    [void]$stringBuilder.AppendLine('<div class="card quality-table-wrapper" style="margin-top:12px;"><table><thead><tr style="background:#f0f4f8;"><th style="color:#0f172a;font-weight:700;">Category</th><th style="color:#0f172a;font-weight:700;">Incidents</th><th style="color:#0f172a;font-weight:700;">Avg Escalation Time</th></tr></thead><tbody>')
    if (@($DashboardData.OSDToCollabByCategoryRows).Count -eq 0) {
        [void]$stringBuilder.AppendLine('<tr><td colspan="3" style="color:#64748b;text-align:center;padding:14px 12px;">No OSD L1 -> Collaboration Ops Spt escalation data available.</td></tr>')
    } else {
        foreach ($row in @($DashboardData.OSDToCollabByCategoryRows)) {
            [void]$stringBuilder.AppendLine(('<tr><td style="font-weight:600;">{0}</td><td style="text-align:center;font-weight:600;">{1}</td><td style="color:#0c4a6e;font-weight:600;">{2}</td></tr>' -f (Escape-Html ([string]$row.Category)), $row.IncidentCount, (Escape-Html ([string]$row.AvgDisplay))))
        }
    }
    [void]$stringBuilder.AppendLine('</tbody></table></div>')

    [void]$stringBuilder.AppendLine('<div class="card quality-table-wrapper" style="margin-top:12px;"><table><thead><tr style="background:#f0f4f8;"><th style="color:#0f172a;font-weight:700;">Category</th><th style="color:#0f172a;font-weight:700;">Incident Count</th><th style="color:#0f172a;font-weight:700;">Avg Time to Resolve</th></tr></thead><tbody>')
    if (@($DashboardData.CategoryMttrRows).Count -eq 0) {
        [void]$stringBuilder.AppendLine('<tr><td colspan="3" style="color:#64748b;text-align:center;padding:14px 12px;">No resolution-duration data available.</td></tr>')
    } else {
        foreach ($row in @($DashboardData.CategoryMttrRows)) {
            $mttrCell = if ([string]$row.MeanResolutionDisplay -eq 'n/a' -or [string]::IsNullOrWhiteSpace($row.MeanResolutionDisplay)) { '<span class="mttr-na">Not available</span>' } else { '<span class="mttr-val">' + (Escape-Html ([string]$row.MeanResolutionDisplay)) + '</span>' }
            [void]$stringBuilder.AppendLine(('<tr><td style="font-weight:600;">{0}</td><td style="text-align:center;font-weight:600;">{1}</td><td>{2}</td></tr>' -f (Escape-Html ([string]$row.Category)), $row.IncidentCount, $mttrCell))
        }
    }
    [void]$stringBuilder.AppendLine('</tbody></table></div>')

    [void]$stringBuilder.AppendLine('<div class="sec" style="margin-top:18px;"><div class="sec-hdr"><div class="sec-num" style="background:#166534;">3</div><h2>User Sentiment Analysis by Category</h2></div>')
    [void]$stringBuilder.AppendLine('<div class="smart-controls"><select id="sentimentFocus" onchange="filterSentimentRows()" style="min-width:200px;"><option value="all">All Sentiments</option><option value="Positive">+ Positive</option><option value="Neutral">~ Neutral</option><option value="Negative">- Negative</option></select><span class="smart-note">Initial user tone + journey shift (Improved / No Change / Worsened)</span></div>')
    [void]$stringBuilder.AppendLine('<div class="card quality-table-wrapper"><table><thead><tr style="background:#f0f4f8;"><th style="color:#0f172a;font-weight:700;">Category</th><th style="color:#166534;font-weight:700;text-align:center;">Positive</th><th style="color:#334155;font-weight:700;text-align:center;">Neutral</th><th style="color:#991b1b;font-weight:700;text-align:center;">Negative</th><th style="color:#0f172a;font-weight:700;text-align:center;">Dominant</th><th style="color:#166534;font-weight:700;text-align:center;">Improved</th><th style="color:#334155;font-weight:700;text-align:center;">No Change</th><th style="color:#991b1b;font-weight:700;text-align:center;">Worsened</th></tr></thead><tbody>')
    if (@($DashboardData.CategorySentimentRows).Count -eq 0) {
        [void]$stringBuilder.AppendLine('<tr><td colspan="8">No sentiment data available for current week.</td></tr>')
    } else {
        foreach ($row in @($DashboardData.CategorySentimentRows)) {
            $dominantBadge = if ($row.DominantSentiment -eq 'Positive') { '<span class="badge-pos">Positive</span>' } elseif ($row.DominantSentiment -eq 'Negative') { '<span class="badge-neg">Negative</span>' } else { '<span class="badge-neu">Neutral</span>' }
            $sentIdx = [array]::IndexOf(@($DashboardData.CategorySentimentRows), $row)
            $posId  = [string]::Format('spos-{0}',  $sentIdx)
            $neuId  = [string]::Format('sneu-{0}',  $sentIdx)
            $negId  = [string]::Format('sneg-{0}',  $sentIdx)
            $impId  = [string]::Format('simp-{0}',  $sentIdx)
            $sameId = [string]::Format('ssame-{0}', $sentIdx)
            $worId  = [string]::Format('swor-{0}',  $sentIdx)
            $posNums = if ($row.Positive -gt 0)  { (($row.PositiveNumbers  | ForEach-Object { [string]::Format('<li><a class="inc-link" href="{0}{1}" target="_blank">{1}</a></li>', $DashboardData.ServiceNowPortalBase, (Escape-Html $_)) }) -join '') } else { '' }
            $neuNums = if ($row.Neutral  -gt 0)  { (($row.NeutralNumbers   | ForEach-Object { [string]::Format('<li><a class="inc-link" href="{0}{1}" target="_blank">{1}</a></li>', $DashboardData.ServiceNowPortalBase, (Escape-Html $_)) }) -join '') } else { '' }
            $negNums = if ($row.Negative -gt 0)  { (($row.NegativeNumbers  | ForEach-Object { [string]::Format('<li><a class="inc-link" href="{0}{1}" target="_blank">{1}</a></li>', $DashboardData.ServiceNowPortalBase, (Escape-Html $_)) }) -join '') } else { '' }
            $impNums = if ($row.Improved -gt 0)  { (($row.ImprovedNumbers  | ForEach-Object { [string]::Format('<li><a class="inc-link" href="{0}{1}" target="_blank">{1}</a></li>', $DashboardData.ServiceNowPortalBase, (Escape-Html $_)) }) -join '') } else { '' }
            $sameNums = if ($row.NoChange -gt 0) { (($row.NoChangeNumbers  | ForEach-Object { [string]::Format('<li><a class="inc-link" href="{0}{1}" target="_blank">{1}</a></li>', $DashboardData.ServiceNowPortalBase, (Escape-Html $_)) }) -join '') } else { '' }
            $worNums = if ($row.Worsened -gt 0)  { (($row.WorsenedNumbers  | ForEach-Object { [string]::Format('<li><a class="inc-link" href="{0}{1}" target="_blank">{1}</a></li>', $DashboardData.ServiceNowPortalBase, (Escape-Html $_)) }) -join '') } else { '' }
            $posCell = if ($row.Positive -gt 0)  { [string]::Format('<button class="inc-toggle" data-label="show ({0})" onclick="toggleInc(this,&apos;{1}&apos;)">{0}</button><ul class="inc-list" id="{1}">{2}</ul>', $row.Positive, $posId, $posNums) } else { '0' }
            $neuCell = if ($row.Neutral  -gt 0)  { [string]::Format('<button class="inc-toggle" data-label="show ({0})" onclick="toggleInc(this,&apos;{1}&apos;)">{0}</button><ul class="inc-list" id="{1}">{2}</ul>', $row.Neutral,  $neuId, $neuNums) } else { '0' }
            $negCell = if ($row.Negative -gt 0)  { [string]::Format('<button class="inc-toggle" data-label="show ({0})" onclick="toggleInc(this,&apos;{1}&apos;)">{0}</button><ul class="inc-list" id="{1}">{2}</ul>', $row.Negative, $negId, $negNums) } else { '0' }
            $impCell = if ($row.Improved -gt 0)  { [string]::Format('<button class="inc-toggle" data-label="show ({0})" onclick="toggleInc(this,&apos;{1}&apos;)">{0}</button><ul class="inc-list" id="{1}">{2}</ul>', $row.Improved, $impId, $impNums) } else { '0' }
            $sameCell = if ($row.NoChange -gt 0) { [string]::Format('<button class="inc-toggle" data-label="show ({0})" onclick="toggleInc(this,&apos;{1}&apos;)">{0}</button><ul class="inc-list" id="{1}">{2}</ul>', $row.NoChange, $sameId, $sameNums) } else { '0' }
            $worCell = if ($row.Worsened -gt 0)  { [string]::Format('<button class="inc-toggle" data-label="show ({0})" onclick="toggleInc(this,&apos;{1}&apos;)">{0}</button><ul class="inc-list" id="{1}">{2}</ul>', $row.Worsened, $worId, $worNums) } else { '0' }
            [void]$stringBuilder.AppendLine(('<tr class="sentiment-row" data-dominant="{4}"><td style="font-weight:600;">{0}</td><td style="color:#166534;text-align:center;">{1}</td><td style="color:#334155;text-align:center;">{2}</td><td style="color:#991b1b;text-align:center;">{3}</td><td style="text-align:center;">{5}</td><td style="color:#166534;text-align:center;">{6}</td><td style="color:#334155;text-align:center;">{7}</td><td style="color:#991b1b;text-align:center;">{8}</td></tr>' -f (Escape-Html ([string]$row.Category)), $posCell, $neuCell, $negCell, (Escape-Html ([string]$row.DominantSentiment)), $dominantBadge, $impCell, $sameCell, $worCell))
        }
    }
    [void]$stringBuilder.AppendLine('</tbody></table></div></div>')
    [void]$stringBuilder.AppendLine('</div>')

    [void]$stringBuilder.AppendLine(('<div class="sec"><div class="sec-hdr"><div class="sec-num">3</div><h2>Category Overview - WW{0} vs WW{1} (Top {2})</h2></div><div class="card"><table><thead><tr><th>#</th><th>Category</th><th>Volume (WW{1})</th><th>Share %</th><th>WW{0} (Prev)</th><th>WW{1} (Curr)</th><th>Delta</th><th>Trend</th></tr></thead><tbody>' -f $DashboardData.PreviousWW, $DashboardData.CurrentWW, $TopCategories))
    $rank = 0
    foreach ($row in @($DashboardData.CategoryRows)) {
        $rank += 1
        $barWidth = [Math]::Round(($row.TotalCurrentWeek * 100.0) / $maxTotal)
        $deltaLabel = if ($row.Delta -gt 0) { '+' + $row.Delta } elseif ($row.Delta -lt 0) { [string]$row.Delta } else { '0' }
        $deltaClass = if ($row.Delta -gt 0) { 'delta-up' } elseif ($row.Delta -lt 0) { 'delta-dn' } else { 'delta-fl' }
        [void]$stringBuilder.AppendLine(('<tr><td class="rank">{0}</td><td class="cat-name">{1}</td><td><span class="vol-bar" style="width:{2}%"></span><span class="vol-num">{3}</span></td><td>{4}%</td><td class="ww-nums">{5}</td><td class="ww-nums">{6}</td><td class="{7}">{8}</td><td><span class="pill {9}">{10}</span></td></tr>' -f $rank, (Escape-Html $row.Category), $barWidth, $row.TotalCurrentWeek, $row.Share, $row.PreviousWW, $row.CurrentWW, $deltaClass, $deltaLabel, $row.StatusClass, (Escape-Html $row.Status)))
    }
    [void]$stringBuilder.AppendLine('</tbody></table></div></div>')

    [void]$stringBuilder.AppendLine(('<div class="sec"><div class="sec-hdr"><div class="sec-num">4</div><h2>Subcategory Breakdown - WW{0} vs WW{1}</h2></div><div class="sub-grid">' -f $DashboardData.PreviousWW, $DashboardData.CurrentWW))
    foreach ($row in @($DashboardData.CategoryRows)) {
        [void]$stringBuilder.AppendLine(('<div class="sub-card"><div class="sc2-hdr"><span>{0}</span><span class="total-badge">{1} incidents</span></div><table><thead><tr><th>Subcategory</th><th>WW{2} (Prev)</th><th>WW{3} (Curr)</th><th>Delta</th></tr></thead><tbody>' -f (Escape-Html $row.Category), $row.TotalCurrentWeek, $DashboardData.PreviousWW, $DashboardData.CurrentWW))
        foreach ($subRow in @($row.Subs)) {
            $subDeltaLabel = if ($subRow.Delta -gt 0) { '<span class="delta-up">+' + $subRow.Delta + '</span>' } elseif ($subRow.Delta -lt 0) { '<span class="delta-dn">' + $subRow.Delta + '</span>' } else { '<span class="delta-fl">0</span>' }
            [void]$stringBuilder.AppendLine(('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td></tr>' -f (Escape-Html $subRow.Name), $subRow.Prev, $subRow.Curr, $subDeltaLabel))
        }
        [void]$stringBuilder.AppendLine('</tbody></table></div>')
    }
    [void]$stringBuilder.AppendLine('</div></div>')

    [void]$stringBuilder.AppendLine(('<div class="sec"><div class="sec-hdr"><div class="sec-num">5</div><h2>Detailed Analysis - Significant Increase Categories (WW{0} to WW{1})</h2></div>' -f $DashboardData.PreviousWW, $DashboardData.CurrentWW))
    if (@($DashboardData.SignificantCategories).Count -eq 0) {
        [void]$stringBuilder.AppendLine('<div class="card no-drivers">No categories met the Significant Increase threshold in the compared weeks.</div>')
    } else {
        [void]$stringBuilder.AppendLine('<div class="sig-section">')
        foreach ($row in @($DashboardData.SignificantCategories)) {
            [void]$stringBuilder.AppendLine(('<div class="sig-card"><div class="sh"><div class="title">{0}</div><div class="ww-info">Prev {1} to Curr {2}   +{3}</div></div>' -f (Escape-Html $row.Category), $row.PreviousWW, $row.CurrentWW, $row.Delta))
            $topIssues = @($row.Items | Group-Object short_desc | Sort-Object Count -Descending | Select-Object -First 5)
            $topIssuesMax = if ($topIssues.Count -gt 0) { [int]$topIssues[0].Count } else { 1 }
            [void]$stringBuilder.AppendLine(('<div class="top5-block"><div class="t5-lbl">Top 5 Issues (WW{0} + WW{1})</div>' -f $DashboardData.PreviousWW, $DashboardData.CurrentWW))
            $topIssueRank = 0
            foreach ($issue in @($topIssues)) {
                $topIssueRank += 1
                $issueName = [string]$issue.Name
                $shortName = if ($issueName.Length -gt 70) { $issueName.Substring(0, 67) + '...' } else { $issueName }
                $issueWidth = [Math]::Round(($issue.Count * 100.0) / [Math]::Max($topIssuesMax, 1))
                [void]$stringBuilder.AppendLine(('<div class="t5-row"><span class="t5-rank">{0}</span><span class="t5-name" title="{1}">{2}</span><div class="t5-bar-wrap"><div class="t5-bar" style="width:{3}%"></div></div><span class="t5-count">{4}</span></div>' -f $topIssueRank, (Escape-Html $issueName), (Escape-Html $shortName), $issueWidth, $issue.Count))
            }
            [void]$stringBuilder.AppendLine('</div>')

            $driverRows = New-Object System.Collections.Generic.List[object]
            foreach ($subGroup in @($row.Items | Group-Object subcategory)) {
                $subPrevious = @($subGroup.Group | Where-Object { $_.incident_date.Date -ge $DashboardData.PreviousWeekStart -and $_.incident_date.Date -le $DashboardData.PreviousWeekEnd }).Count
                $subCurrent = @($subGroup.Group | Where-Object { $_.incident_date.Date -ge $DashboardData.CurrentWeekStart -and $_.incident_date.Date -le $DashboardData.CurrentWeekEnd }).Count
                $driverRows.Add([PSCustomObject]@{ Name = $subGroup.Name; Delta = $subCurrent - $subPrevious; Current = $subCurrent; Previous = $subPrevious; Items = @($subGroup.Group) })
            }
            $topDrivers = @($driverRows.ToArray() | Where-Object { $_.Delta -gt 0 } | Sort-Object -Property @{ Expression = 'Delta'; Descending = $true }, @{ Expression = 'Current'; Descending = $true } | Select-Object -First 4)
            if ($topDrivers.Count -eq 0) {
                $topDrivers = @($driverRows.ToArray() | Sort-Object -Property @{ Expression = 'Current'; Descending = $true } | Select-Object -First 2)
            }

            foreach ($driver in @($topDrivers)) {
                $driverDelta = if ($driver.Delta -gt 0) { '+' + $driver.Delta } else { [string]$driver.Delta }
                [void]$stringBuilder.AppendLine(('<div class="driver"><div class="dh"><div class="dname">{0}</div><div class="dstats">Prev {1} to Curr {2}   <b style="color:#dc2626">{3}</b></div></div>' -f (Escape-Html $driver.Name), $driver.Previous, $driver.Current, $driverDelta))
                $examples = @($driver.Items | Where-Object { $_.incident_date.Date -ge $DashboardData.CurrentWeekStart -and $_.incident_date.Date -le $DashboardData.CurrentWeekEnd } | Select-Object -First 3)
                if ($examples.Count -gt 0) {
                    [void]$stringBuilder.AppendLine('<div class="dex">')
                    foreach ($example in @($examples)) {
                        $exampleText = [string]$example.short_desc
                        if ($exampleText.Length -gt 130) {
                            $exampleText = $exampleText.Substring(0, 127) + '...'
                        }
                        [void]$stringBuilder.AppendLine(('<div class="ex-row">{0}</div>' -f (Escape-Html $exampleText)))
                    }
                    [void]$stringBuilder.AppendLine('</div>')
                }
                [void]$stringBuilder.AppendLine('</div>')
            }
            [void]$stringBuilder.AppendLine('</div>')
        }
        [void]$stringBuilder.AppendLine('</div>')
    }
    [void]$stringBuilder.AppendLine('</div>')

    [void]$stringBuilder.AppendLine(('<div class="sec"><div class="sec-hdr"><div class="sec-num">6</div><h2>Intent Split by Category - WW{0}</h2></div>' -f $DashboardData.CurrentWW))
    [void]$stringBuilder.AppendLine('<div class="intent-summary">')
    [void]$stringBuilder.AppendLine(('<div class="intent-chip"><div class="k">How Do I</div><div class="v">{0}</div></div>' -f $DashboardData.OverallHowDoI))
    [void]$stringBuilder.AppendLine(('<div class="intent-chip"><div class="k">Incident</div><div class="v">{0}</div></div>' -f $DashboardData.OverallTechnical))
    [void]$stringBuilder.AppendLine(('<div class="intent-chip"><div class="k">How Do I Share</div><div class="v">{0}%</div></div>' -f $DashboardData.OverallHowDoIPct))
    [void]$stringBuilder.AppendLine('</div>')
    $smartSkew = @($DashboardData.IntentRows | Where-Object { $_.Total -gt 0 } | Sort-Object -Property @{ Expression = { [Math]::Abs([double]$_.HowPct - 50.0) }; Descending = $true } | Select-Object -First 1)
    if ($smartSkew.Count -gt 0) {
        $smartRow = $smartSkew[0]
        $smartDirection = if ([double]$smartRow.HowPct -ge 50.0) { 'How Do I leaning' } else { 'Incident leaning' }
        [void]$stringBuilder.AppendLine(('<div class="smart-insight"><b>Smart insight:</b> Most skewed intent mix is <b>{0}</b> at <b>{1}%</b> How Do I ({2}).</div>' -f (Escape-Html $smartRow.Category), $smartRow.HowPct, $smartDirection))
    }
    [void]$stringBuilder.AppendLine('<div class="smart-controls"><input id="intentFilter" type="text" placeholder="Filter category..." oninput="filterIntentRows()" /><select id="intentFocus" onchange="filterIntentRows()"><option value="all">All categories</option><option value="how-heavy">How Do I heavy (>=60%)</option><option value="incident-heavy">Incident heavy (<40% How Do I)</option><option value="high-volume">High volume (Total >=5)</option></select><span id="intentVisibleCount" class="smart-note"></span></div>')
    [void]$stringBuilder.AppendLine('<div class="card"><table><thead><tr><th>Category</th><th>How Do I</th><th>Incident</th><th>Total</th><th>How Do I %</th></tr></thead><tbody>')
    $intentIdx = 0
    foreach ($intentRow in @($DashboardData.IntentRows)) {
        if ($intentRow.Total -le 0) {
            continue
        }
        $intentIdx++
        $howId = [string]::Format('how-{0}', $intentIdx)
        $techId = [string]::Format('tech-{0}', $intentIdx)

        $howDoICell = if ($intentRow.HowDoI -gt 0) {
            $howLabel = [string]::Format('show incidents ({0})', $intentRow.HowDoI)
            $howNums = (($intentRow.HowDoINumbers | ForEach-Object { [string]::Format('<li><a class="inc-link" href="{0}{1}" target="_blank">{1}</a></li>', $DashboardData.ServiceNowPortalBase, (Escape-Html $_)) }) -join '')
            [string]::Format('{0}<br/><button class="inc-toggle" data-label="{1}" onclick="toggleInc(this,&apos;{2}&apos;)">{1}</button><ul class="inc-list" id="{2}">{3}</ul>', $intentRow.HowDoI, (Escape-Html $howLabel), $howId, $howNums)
        } else { '0' }

        $techCell = if ($intentRow.Technical -gt 0) {
            $techLabel = [string]::Format('show incidents ({0})', $intentRow.Technical)
            $techNums = (($intentRow.TechnicalNumbers | ForEach-Object { [string]::Format('<li><a class="inc-link" href="{0}{1}" target="_blank">{1}</a></li>', $DashboardData.ServiceNowPortalBase, (Escape-Html $_)) }) -join '')
            [string]::Format('{0}<br/><button class="inc-toggle" data-label="{1}" onclick="toggleInc(this,&apos;{2}&apos;)">{1}</button><ul class="inc-list" id="{2}">{3}</ul>', $intentRow.Technical, (Escape-Html $techLabel), $techId, $techNums)
        } else { '0' }

        [void]$stringBuilder.AppendLine(('<tr class="intent-row" data-category="{0}" data-howpct="{1}" data-total="{2}"><td>{0}</td><td>{3}</td><td>{4}</td><td>{2}</td><td>{1}%</td></tr>' -f (Escape-Html $intentRow.Category), $intentRow.HowPct, $intentRow.Total, $howDoICell, $techCell))
    }
    [void]$stringBuilder.AppendLine('</tbody></table></div>')
    [void]$stringBuilder.AppendLine('<div class="plan"><h3>Action Plan</h3><ul>')
    foreach ($planItem in @($DashboardData.ActionPlan)) {
        $itemText = Escape-Html ([string]$planItem)
        # Style the leading tag (TREND OBSERVED:, AUTOMATION OPPORTUNITY:, etc.)
        $itemText = [System.Text.RegularExpressions.Regex]::Replace($itemText, '^(TREND OBSERVED|SIGNIFICANT SPIKE|POSITIVE SIGNAL|AUTOMATION OPPORTUNITY|REPEAT PATTERN[^:]*|OPS IMPROVEMENT|WEEK-ON-WEEK KPI)(:)', '<b style="color:#0f172a">$1$2</b>')
        [void]$stringBuilder.AppendLine(('<li>{0}</li>' -f $itemText))
    }
    if (@($DashboardData.TopHowDoIIssues).Count -gt 0) {
        $themeText = ((@($DashboardData.TopHowDoIIssues | ForEach-Object { ('{0} ({1})' -f $_.Name, $_.Count) }) -join '; '))
        [void]$stringBuilder.AppendLine(('<li>Top recurring How Do I themes this week: {0}</li>' -f (Escape-Html $themeText)))
    }
    [void]$stringBuilder.AppendLine('</ul></div></div>')

    [void]$stringBuilder.AppendLine('</div></body></html>')
    return $stringBuilder.ToString()
}

function New-PortfolioPromptData {
    param([array]$IncidentAnalyses)

    $condensed = foreach ($item in @($IncidentAnalyses)) {
        [PSCustomObject]@{
            incident_number = [string]$item.incident_number
            application_or_area = [string]$item.application_or_area
            primary_category = [string]$item.primary_category
            issue_summary = [string]$item.issue_summary
            probable_root_cause = [string]$item.probable_root_cause
            confidence = [string]$item.confidence
            evidence_signals = @($item.evidence_signals)
            unknowns = @($item.unknowns)
            what_can_be_improved = @($item.what_can_be_improved)
        }
    }

    return [PSCustomObject]@{
        total_incidents = @($IncidentAnalyses).Count
        incidents = @($condensed)
    }
}

function Invoke-PortfolioSummary {
    param(
        [hashtable]$Config,
        [array]$IncidentAnalyses,
        [hashtable]$TemplateBundle
    )

    $instructionsParts = New-Object System.Collections.Generic.List[string]
    $instructionsParts.Add('You are a senior IT operations analyst for Productivity Tools portfolios.')
    $instructionsParts.Add('Return valid JSON only. Do not use markdown wrappers.')
    $instructionsParts.Add('Base conclusions strictly on the provided incident analyses only. Do not introduce external assumptions.')
    $instructionsParts.Add('When incident count is small (especially 1), explicitly avoid claiming recurrence and label it as limited sample evidence.')
    $instructionsParts.Add('Be concise and operational. Keep executive_summary under 120 words. Keep each bullet under 28 words. Return at most 5 quick_look items, 5 recurring_themes items, and 6 improvement_opportunities items.')
    if ($TemplateBundle -and -not [string]::IsNullOrWhiteSpace([string]$TemplateBundle.PortfolioSummary)) {
        $instructionsParts.Add((Limit-TextLength -Text $TemplateBundle.PortfolioSummary -MaxLength 3000))
    }
    $instructionsParts.Add(@'
Return this exact JSON shape:
{
  "executive_summary": "string",
  "quick_look": ["string"],
  "recurring_themes": ["string"],
  "improvement_opportunities": ["string"]
}
'@)
    $instructions = ($instructionsParts -join ([Environment]::NewLine + [Environment]::NewLine))

    $promptPayload = New-PortfolioPromptData -IncidentAnalyses $IncidentAnalyses

    $promptOptions = @(
        @{
            Prompt = ($promptPayload | ConvertTo-Json -Depth 10)
            MaxOutputTokens = 1600
        },
        @{
            Prompt = (([PSCustomObject]@{
                total_incidents = $promptPayload.total_incidents
                incidents = @($promptPayload.incidents | Select-Object -First 12)
            }) | ConvertTo-Json -Depth 10)
            MaxOutputTokens = 1200
        }
    )

    foreach ($option in $promptOptions) {
        try {
            $summary = Invoke-AzureJsonAnalysis -Config $Config -Instructions $instructions -Prompt $option.Prompt -MaxOutputTokens $option.MaxOutputTokens
            return [PSCustomObject]@{
                executive_summary = [string]$summary.executive_summary
                quick_look = @($summary.quick_look)
                recurring_themes = @($summary.recurring_themes)
                improvement_opportunities = @($summary.improvement_opportunities)
            }
        } catch {
            Write-Step ([string]::Format('Portfolio AI summary retry needed: {0}', $_.Exception.Message)) 'Yellow'
        }
    }

    Write-Step 'Portfolio AI summary failed after retries. Using deterministic fallback summary.' 'Yellow'
    return (New-FallbackPortfolioSummary -IncidentAnalyses $IncidentAnalyses)
}

function New-MarkdownSummary {
    param(
        [array]$IncidentAnalyses,
        [psobject]$PortfolioSummary,
        [psobject]$DashboardData,
        [int]$LookbackDaysValue,
        [int]$RequestedCount,
        [int]$TargetYearValue = 0,
        [int]$TargetWeekValue = 0
    )

    $formatCell = {
        param(
            [string]$Value,
            [int]$MaxLength = 140
        )

        $text = Normalize-DisplayText -Value $Value
        $text = ($text -replace '\|', '/') -replace '[\r\n]+', ' '
        $text = ([Regex]::Replace($text, '\s+', ' ')).Trim()
        if ($text.Length -gt $MaxLength) {
            return ($text.Substring(0, $MaxLength - 3) + '...')
        }
        return $text
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Productivity Tools Weekly Incident Report')
    $lines.Add('')
    $lines.Add('## Executive Snapshot')
    $lines.Add('')
    $lines.Add(([string]::Format('- Generated At: {0}', (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))))
    $lines.Add(([string]::Format('- Incidents Analyzed: {0}', $IncidentAnalyses.Count)))
    if ($TargetYearValue -gt 0 -and $TargetWeekValue -gt 0) {
        $lines.Add(([string]::Format('- Selection Window: WW{0} {1}', $TargetWeekValue, $TargetYearValue)))
    } elseif ($LookbackDaysValue -gt 0) {
        $lines.Add(([string]::Format('- Lookback Window: last {0} days', $LookbackDaysValue)))
    } else {
        $lines.Add(([string]::Format('- Selection Rule: latest {0} Productivity Tools incidents', $RequestedCount)))
    }

    if ($DashboardData) {
        $lines.Add(([string]::Format('- Analysis Week: WW{0} ({1} - {2})', $DashboardData.CurrentWW, $DashboardData.CurrentWeekStart.ToString('MMM dd'), $DashboardData.CurrentWeekEnd.ToString('MMM dd, yyyy'))))
        $lines.Add(([string]::Format('- Prior Week: WW{0} ({1} - {2})', $DashboardData.PreviousWW, $DashboardData.PreviousWeekStart.ToString('MMM dd'), $DashboardData.PreviousWeekEnd.ToString('MMM dd, yyyy'))))
        $lines.Add(([string]::Format('- Week-over-Week Delta: {0}', $DashboardData.WeekOverWeekDelta)))
        $lines.Add(([string]::Format('- How Do I vs Incident: {0} vs {1} ({2}% How Do I)', $DashboardData.OverallHowDoI, $DashboardData.OverallTechnical, $DashboardData.OverallHowDoIPct)))
    }

    $lines.Add('')
    $lines.Add('## Incident Register (Report Format)')
    $lines.Add('')
    $lines.Add('| Incident | Product Area | Category | Problem Statement | AI Summary | Confidence |')
    $lines.Add('|---|---|---|---|---|---|')

    foreach ($analysis in $IncidentAnalyses) {
        $problemStatement = if (-not [string]::IsNullOrWhiteSpace([string]$analysis.issue_summary)) {
            [string]$analysis.issue_summary
        } else {
            [string]$analysis.short_description
        }
        $aiSummary = if (-not [string]::IsNullOrWhiteSpace([string]$analysis.quick_look)) {
            [string]$analysis.quick_look
        } else {
            [string]$analysis.probable_root_cause
        }

        $lines.Add(([string]::Format('| {0} | {1} | {2} | {3} | {4} | {5} |',
            (& $formatCell ([string]$analysis.incident_number) 30),
            (& $formatCell ([string]$analysis.application_or_area) 40),
            (& $formatCell ([string]$analysis.primary_category) 45),
            (& $formatCell $problemStatement 150),
            (& $formatCell $aiSummary 150),
            (& $formatCell ([string]$analysis.confidence) 12)
        )))
    }

    $lines.Add('')
    $lines.Add('## Detailed Incident Narratives')
    $lines.Add('')

    foreach ($analysis in $IncidentAnalyses) {
        $problemStatement = if (-not [string]::IsNullOrWhiteSpace([string]$analysis.issue_summary)) {
            [string]$analysis.issue_summary
        } else {
            [string]$analysis.short_description
        }
        $aiSummary = if (-not [string]::IsNullOrWhiteSpace([string]$analysis.quick_look)) {
            [string]$analysis.quick_look
        } else {
            [string]$analysis.probable_root_cause
        }

        $lines.Add(([string]::Format('### {0} - {1}', (& $formatCell ([string]$analysis.incident_number) 30), (& $formatCell ([string]$analysis.application_or_area) 60))))
        $lines.Add('')
        $lines.Add(([string]::Format('- Category: {0}', (& $formatCell ([string]$analysis.primary_category) 120))))
        $lines.Add(([string]::Format('- Problem Statement: {0}', (& $formatCell $problemStatement 400))))
        $lines.Add(([string]::Format('- AI Summary: {0}', (& $formatCell $aiSummary 400))))
        $lines.Add('- Area of Improvement:')
        $improvementCount = 0
        foreach ($improvement in @($analysis.what_can_be_improved)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$improvement)) {
                $lines.Add(([string]::Format('  - {0}', (& $formatCell ([string]$improvement) 300))))
                $improvementCount += 1
                if ($improvementCount -ge 3) { break }
            }
        }
        if ($improvementCount -eq 0) {
            $lines.Add('  - Add clearer closure validation and evidence in ticket notes.')
        }
        $lines.Add(([string]::Format('- Confidence: {0}', (& $formatCell ([string]$analysis.confidence) 20))))
        $lines.Add('')
    }

    return ($lines -join [Environment]::NewLine)
}

function Resolve-EmailRecipients {
    param([object[]]$Values)

    $recipients = @()
    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }

        foreach ($part in ([string]$value -split '[,;]')) {
            $email = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($email)) {
                $recipients += $email
            }
        }
    }

    return @($recipients | Select-Object -Unique)
}

function New-DashboardEmailSummaryHtml {
        param(
                [psobject]$DashboardData,
                [string]$DashboardPath
        )

        $currentWW = if ($DashboardData) { [string]$DashboardData.CurrentWW } else { '' }
        $previousWW = if ($DashboardData) { [string]$DashboardData.PreviousWW } else { '' }
        $totalCurrentWeek = if ($DashboardData) { [int]$DashboardData.TotalCurrentWeek } else { 0 }
        $totalTwoWeekIncidents = if ($DashboardData) { [int]$DashboardData.TotalTwoWeekIncidents } else { 0 }
        $howDoI = if ($DashboardData) { [int]$DashboardData.OverallHowDoI } else { 0 }
        $incident = if ($DashboardData) { [int]$DashboardData.OverallTechnical } else { 0 }
        $howDoIPct = if ($DashboardData) { [string]$DashboardData.OverallHowDoIPct } else { '0' }
        $topCategory = if ($DashboardData -and @($DashboardData.CategoryRows).Count -gt 0) { [string]$DashboardData.CategoryRows[0].Category } else { 'N/A' }
        $analysisLabel = if ($DashboardData) { [string]$DashboardData.AnalysisLabel } else { 'Weekly Analysis' }

        return @"
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="font-family:Segoe UI,Arial,sans-serif;color:#0f172a;line-height:1.5;">
    <p>Hello,</p>
    <p>The Productivity Tools weekly analyzer run has completed.</p>
    <p>
        Analysis focus: <b>$(Escape-Html $analysisLabel)</b><br/>
        Week comparison: <b>WW$previousWW vs WW$currentWW</b><br/>
        2-week window: <b>WW$previousWW and WW$currentWW</b> with <b>$totalTwoWeekIncidents</b> total incidents<br/>
        Analysis week volume: <b>$totalCurrentWeek</b><br/>
        Intent split: <b>How Do I $howDoI</b> and <b>Incident $incident</b> ($howDoIPct% How Do I)<br/>
        Top category this week: <b>$(Escape-Html $topCategory)</b>
    </p>
    <p>The full dashboard is attached as an HTML file.</p>
    <p style="font-size:12px;color:#475569;">Report path: $(Escape-Html $DashboardPath)</p>
    <p>Thanks.</p>
</body>
</html>
"@
}

function Send-DashboardEmail {
    param(
        [hashtable]$Config,
        [string]$HtmlContent,
        [string]$DashboardPath,
        [psobject]$DashboardData
    )

    $recipient = [string]$Config.RecipientEmail
    $webhookUrl = [string]$Config.WebhookUrl
    $recipients = @(Resolve-EmailRecipients -Values @($recipient))
    $smtpServer = if ([string]::IsNullOrWhiteSpace([string]$Config.EmailSmtpServer)) { 'smtp.intel.com' } else { [string]$Config.EmailSmtpServer }
    $smtpPort = if ($null -eq $Config.EmailSmtpPort -or [string]::IsNullOrWhiteSpace([string]$Config.EmailSmtpPort)) { 25 } else { [int]$Config.EmailSmtpPort }
    $sender = if ([string]::IsNullOrWhiteSpace([string]$Config.EmailSender)) {
        if ($recipients.Count -gt 0) { [string]$recipients[0] } else { '' }
    } else {
        [string]$Config.EmailSender
    }

    $currentWW = if ($DashboardData) { [string]$DashboardData.CurrentWW } else { (Get-IsoWeekNumber -DateValue (Get-Date)).ToString() }
    $subject = [string]::Format('Productivity Tools Weekly Dashboard - WW{0} {1}', $currentWW, (Get-Date -Format 'yyyy'))
    $summaryHtml = New-DashboardEmailSummaryHtml -DashboardData $DashboardData -DashboardPath $DashboardPath

    # Prefer Logic App webhook if configured
    if (-not [string]::IsNullOrWhiteSpace($webhookUrl)) {
        Write-Step 'Sending report via webhook...' 'Cyan'
        $payload = @{
            subject     = $subject
            to          = $recipient
            htmlContent = $summaryHtml
            timestamp   = (Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json -Depth 5 -Compress

        $headers = @{ 'Content-Type' = 'application/json; charset=utf-8' }
        try {
            Invoke-RestMethod -Uri $webhookUrl -Method POST -Body $payload -Headers $headers -TimeoutSec 60 -ErrorAction Stop
            Write-Step ([string]::Format('Report sent via webhook to {0}', $recipient)) 'Green'
        } catch {
            Write-Step ([string]::Format('Webhook send failed: {0}', $_.Exception.Message)) 'Red'
        }
        return
    }

    # Fallback: SMTP via Send-MailMessage (requires accessible SMTP relay)
    if ($recipients.Count -eq 0) {
        Write-Step 'Email skipped: RecipientEmail not configured.' 'Yellow'
        return
    }

    if ([string]::IsNullOrWhiteSpace($sender) -or [string]::IsNullOrWhiteSpace($smtpServer)) {
        Write-Step 'Email skipped: email sender or SMTP server not configured.' 'Yellow'
        return
    }

    Write-Step ([string]::Format('Sending report email to {0} via {1}:{2}...', ($recipients -join ', '), $smtpServer, $smtpPort)) 'Cyan'
    try {
        $mailParams = @{
            To         = $recipients
            From       = $sender
            Subject    = $subject
            Body       = $summaryHtml
            BodyAsHtml = $true
            SmtpServer = $smtpServer
            Port       = $smtpPort
            Encoding   = [System.Text.Encoding]::UTF8
        }
        if (-not [string]::IsNullOrWhiteSpace($DashboardPath) -and (Test-Path $DashboardPath)) {
            $mailParams.Attachments = @($DashboardPath)
        }
        Send-MailMessage @mailParams -ErrorAction Stop
        Write-Step ([string]::Format('Report email sent to {0}', ($recipients -join ', '))) 'Green'
    } catch {
        Write-Step ([string]::Format('Email send failed: {0}', $_.Exception.Message)) 'Red'
    }
}


$config = Load-LocalConfiguration
$templateBundle = Get-TemplateBundle
$reportContext = if ($TargetYear -gt 0 -and $TargetWeek -gt 0) { $null } else { Get-ReportWeekContext -DateValue (Get-IstDateTime) }
$effectiveTargetYear = if ($TargetYear -gt 0 -and $TargetWeek -gt 0) { $TargetYear } elseif ($reportContext) { [int]$reportContext.AnalysisYear } else { 0 }
$effectiveTargetWeek = if ($TargetYear -gt 0 -and $TargetWeek -gt 0) { $TargetWeek } elseif ($reportContext) { [int]$reportContext.AnalysisWW } else { 0 }


$runStamp = (Get-IstDateTime).ToString('yyyy-MM-dd_HH-mm-ss')
$runDirectory = Get-OutputDirectory -PathName $runStamp
$rawDirectory = Get-OutputDirectory -PathName (Join-Path $runStamp 'raw')
$analysisDirectory = Get-OutputDirectory -PathName (Join-Path $runStamp 'analysis')

Write-Step ([string]::Format('Output directory: {0}', $runDirectory)) 'Green'

if ($UseStoredIncidents) {
    if ([string]::IsNullOrWhiteSpace($StoredIncidentsPath)) {
        throw 'UseStoredIncidents was specified, but StoredIncidentsPath was not provided.'
    }
    Write-Step ([string]::Format('Loading stored incidents from {0}', $StoredIncidentsPath))
    $rawIncidents = @(Get-Content -Path $StoredIncidentsPath -Raw -Encoding UTF8 | ConvertFrom-Json)
} else {
    $rawIncidents = $null
    if (-not $ForceRefreshIncidents) {
        $rawIncidents = Try-LoadIncidentSnapshot -RequestedLookbackDays $LookbackDays -MaxAgeHours $SnapshotMaxAgeHours
    }

    if ($null -eq $rawIncidents -or @($rawIncidents).Count -eq 0) {
        Write-Step 'Fetching fresh incidents from ServiceNow (cache miss or refresh requested)...' 'Yellow'
        $rawIncidents = Get-ServiceNowIncidents -Config $config -LookbackDaysValue $LookbackDays -TargetYearValue $effectiveTargetYear -TargetWeekValue $effectiveTargetWeek
        Save-IncidentSnapshot -Incidents $rawIncidents -LookbackDaysValue $LookbackDays
    }

    $rawPath = Join-Path $rawDirectory 'raw_incidents.json'
    Save-JsonFile -Data $rawIncidents -Path $rawPath
    Write-Step ([string]::Format('Saved raw incident payload to {0}', $rawPath)) 'Green'
}

$selectedIncidents = @(Select-ProductivityToolsIncidents -Incidents $rawIncidents -TakeCount $MaxIncidents -LookbackDaysValue $LookbackDays -TargetYearValue $effectiveTargetYear -TargetWeekValue $effectiveTargetWeek -TargetBusinessServiceValue $TargetBusinessService -TargetServiceOfferingValue $TargetServiceOffering -UseAssignmentGroupCriteria $IncludeAssignmentGroupCriteria.IsPresent)
if ($selectedIncidents.Count -eq 0) {
    throw 'No Productivity Tools incidents matched the current selection criteria.'
}

$selectedPath = Join-Path $rawDirectory 'selected_incidents.json'
Save-JsonFile -Data $selectedIncidents -Path $selectedPath
Write-Step ([string]::Format('Selected {0} incidents for AI analysis.', $selectedIncidents.Count)) 'Green'

$incidentAnalyses = New-Object System.Collections.Generic.List[object]
foreach ($incident in $selectedIncidents) {
    $providerLabel = [string]::Format('AI model ({0})', [string]$config.AzureOpenAIModel)
    Write-Step ([string]::Format('Analyzing {0} with {1}...', $incident.number, $providerLabel))
    $analysis = Invoke-IncidentAnalysis -Config $config -Incident $incident -TemplateBundle $templateBundle
    $incidentAnalyses.Add($analysis)
}

$analysisPath = Join-Path $analysisDirectory 'incident_analyses.json'
Save-JsonFile -Data $incidentAnalyses -Path $analysisPath
Write-Step ([string]::Format('Saved incident analyses to {0}', $analysisPath)) 'Green'

$portfolioSummary = Invoke-PortfolioSummary -Config $config -IncidentAnalyses $incidentAnalyses -TemplateBundle $templateBundle
$portfolioPath = Join-Path $analysisDirectory 'portfolio_summary.json'
Save-JsonFile -Data $portfolioSummary -Path $portfolioPath
Write-Step ([string]::Format('Saved portfolio summary to {0}', $portfolioPath)) 'Green'

$dashboardData = New-WeeklyDashboardData -Incidents $rawIncidents -PortfolioSummary $portfolioSummary -ReportContext $reportContext
$dashboardPath = Join-Path $runDirectory 'ProductivityTools_Weekly_Dashboard.html'
$dashboardHtml = New-WeeklyDashboardHtml -DashboardData $dashboardData
Set-Content -Path $dashboardPath -Value $dashboardHtml -Encoding UTF8
Write-Step ([string]::Format('Saved weekly dashboard to {0}', $dashboardPath)) 'Green'

$dashboardJsonPath = Join-Path $analysisDirectory 'weekly_dashboard_data.json'
Save-JsonFile -Data $dashboardData -Path $dashboardJsonPath
Write-Step ([string]::Format('Saved weekly dashboard data to {0}', $dashboardJsonPath)) 'Green'

$strictReportPath = Join-Path $runDirectory 'Resolved_Tickets_AI_Categorization.html'
$strictReportHtml = New-StrictCategoryReportHtml -IncidentAnalyses $incidentAnalyses -RawIncidents $selectedIncidents -ReportContext $reportContext
Set-Content -Path $strictReportPath -Value $strictReportHtml -Encoding UTF8
Write-Step ([string]::Format('Saved strict category report to {0}', $strictReportPath)) 'Green'

$markdownSummary = New-MarkdownSummary -IncidentAnalyses $incidentAnalyses -PortfolioSummary $portfolioSummary -DashboardData $dashboardData -LookbackDaysValue $LookbackDays -RequestedCount $MaxIncidents -TargetYearValue $effectiveTargetYear -TargetWeekValue $effectiveTargetWeek
$markdownPath = Join-Path $runDirectory 'summary.md'
Set-Content -Path $markdownPath -Value $markdownSummary -Encoding UTF8
Write-Step ([string]::Format('Saved Markdown summary to {0}', $markdownPath)) 'Green'

Send-DashboardEmail -Config $config -HtmlContent $dashboardHtml -DashboardPath $dashboardPath -DashboardData $dashboardData

# Auto-open the dashboard in the default browser
Write-Step ([string]::Format('Opening dashboard: {0}', $dashboardPath)) 'Cyan'
Start-Process $dashboardPath

Write-Host ''
Write-Host 'Run complete.' -ForegroundColor Green
Write-Host ([string]::Format('Summary: {0}', $markdownPath)) -ForegroundColor Green
Write-Host ([string]::Format('Dashboard: {0}', $dashboardPath)) -ForegroundColor Green
Write-Host ([string]::Format('Strict Category Report: {0}', $strictReportPath)) -ForegroundColor Green
Write-Host ([string]::Format('Portfolio JSON: {0}', $portfolioPath)) -ForegroundColor Green
Write-Host ([string]::Format('Incident Analyses JSON: {0}', $analysisPath)) -ForegroundColor Green