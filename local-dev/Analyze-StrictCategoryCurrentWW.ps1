[CmdletBinding()]
param(
    [int]$MaxIncidents = 0,
    [switch]$ForceRefreshIncidents,
    [int]$SnapshotMaxAgeHours = 8,
    [string]$TargetBusinessService = 'End-User Collaboration',
    [string]$TargetServiceOffering = 'Productivity Tools',
    [string]$TargetBusinessServiceId = 'a1de2ff2db8f50108062531dd3961911',
    [string]$TargetServiceOfferingId = 'fcb18407dbcf50108062531dd39619c4',
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $script:RepoRoot 'local-output\strict-category-current-ww'
}

function Write-Step {
    param(
        [string]$Message,
        [string]$Color = 'Cyan'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host ([string]::Format('[{0}] {1}', $timestamp, $Message)) -ForegroundColor $Color
}

function Get-IstDateTime {
    try {
        $istTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')
        return [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $istTimeZone)
    } catch {
        return Get-Date
    }
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
        'ServiceNowIncidentsURL',
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

function Escape-Html {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    return ([string]$Value).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function Get-WeekStartMonday {
    param([DateTime]$DateValue)

    if ($null -eq $DateValue) {
        return $null
    }

    return $DateValue.Date.AddDays(-1 * (([int]$DateValue.DayOfWeek + 6) % 7))
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
        [int]$LookbackDaysValue = 10
    )

    Write-Step 'Requesting ServiceNow OAuth token...'
    $token = Get-ServiceNowAccessToken -Config $Config
    $headers = @{
        Authorization = 'Bearer ' + $token
        Accept = 'application/json'
    }

    $incidentUrl = [string]$Config.ServiceNowIncidentsURL
    $incidentUrl = $incidentUrl -replace 'assignment_group=[^^]+\^', ''
    $incidentUrl = $incidentUrl -replace '\^state=6\^ORstate=7', ''

    if ($incidentUrl -match 'sysparm_query=([^&]*)') {
        $existingQuery = $Matches[1].Trim('^')

        if ($existingQuery -notmatch 'stateIN6,7') {
            $existingQuery = if ([string]::IsNullOrWhiteSpace($existingQuery)) { 'stateIN6,7' } else { [string]::Format('{0}^stateIN6,7', $existingQuery) }
        }

        if (-not [string]::IsNullOrWhiteSpace($TargetBusinessServiceId) -and $existingQuery -notmatch 'business_service=') {
            $existingQuery = [string]::Format('{0}^business_service={1}', $existingQuery, $TargetBusinessServiceId)
        }
        if (-not [string]::IsNullOrWhiteSpace($TargetServiceOfferingId) -and $existingQuery -notmatch 'service_offering=') {
            $existingQuery = [string]::Format('{0}^service_offering={1}', $existingQuery, $TargetServiceOfferingId)
        }

        if ($existingQuery -notmatch 'sys_updated_on>=javascript:gs\.daysAgoStart\(') {
            $existingQuery = [string]::Format('{0}^sys_updated_on>=javascript:gs.daysAgoStart({1})', $existingQuery, [Math]::Max($LookbackDaysValue, 1))
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

    Write-Step 'Fetching incident feed from ServiceNow...' 'DarkCyan'

    do {
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
        Write-Step ([string]::Format('Fetched {0} incidents (running total: {1})', $batch.Count, $allIncidents.Count)) 'DarkCyan'
    } while ($batch.Count -eq 1000)

    return @($allIncidents.ToArray())
}

function Get-IncidentDateValue {
    param([psobject]$Incident)

    foreach ($fieldName in @('resolved_at', 'sys_updated_on', 'closed_at', 'opened_at')) {
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

function Resolve-StrictCategory {
    param([psobject]$Incident)

    $shortDescription = ([string]$Incident.short_description).ToLowerInvariant()
    $resolutionCategory = ([string](Get-DisplayValue $Incident.u_resolution_category)).ToLowerInvariant()
    $combined = [string]::Format('{0} {1}', $shortDescription, $resolutionCategory)

    if ($combined -match 'vpn|wifi|wi-fi|network|latency|dns|ethernet|connectivity|cannot connect|unable to connect') {
        return 'Network and Connectivity Issues'
    }
    if ($combined -match 'password|mfa|signin|sign in|login|credential|account|access denied|permission') {
        return 'Account and Access Issues'
    }
    if ($combined -match 'outlook|mailbox|email|exchange') {
        return 'Email and Outlook Issues'
    }
    if ($combined -match 'teams|sharepoint|onedrive|meeting|channel|chat') {
        return 'Collaboration Tools Issues'
    }
    if ($combined -match 'excel|word|powerpoint|onenote|office|macro|addin|add-in') {
        return 'Office Apps Issues'
    }
    if ($combined -match 'copilot|ai') {
        return 'Copilot and AI Issues'
    }
    if ($combined -match 'fan|battery|screen|display|keyboard|mouse|dock|usb|speaker|mic|headset|camera|hardware|motherboard|overheat') {
        return 'Hardware Issues'
    }
    if ($combined -match 'laptop|desktop|pc' -and $combined -notmatch 'onedrive|sharepoint|teams|outlook|excel|word|powerpoint|office') {
        return 'Hardware Issues'
    }
    if ($combined -match 'install|update|upgrade|patch|deployment|configure|configuration') {
        return 'Install and Configuration Issues'
    }
    if ($combined -match 'slow|performance|lag|hang|freeze|crash') {
        return 'Performance Issues'
    }
    if ($combined -match 'security|defender|antivirus|compliance|policy|blocked') {
        return 'Security and Policy Issues'
    }

    return 'Other / Needs Review'
}

function Get-ServiceNowViewLink {
    param([psobject]$Incident)

    $incidentNumber = [string]$Incident.number
    if ([string]::IsNullOrWhiteSpace($incidentNumber)) {
        return 'https://intel.service-now.com/nav_to.do?uri=incident_list.do'
    }

    return [string]::Format('https://intel.service-now.com/nav_to.do?uri=incident.do?sysparm_query=number={0}', [Uri]::EscapeDataString($incidentNumber))
}

function Get-AIEndpoint {
    param([hashtable]$Config)

    return ([string]::Format('{0}/openai/responses?api-version={1}', $Config.AzureOpenAIBaseUrl.TrimEnd('/'), $Config.AzureOpenAIApiVersion))
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
        [int]$MaxOutputTokens = 1300
    )

    $headers = @{
        'api-key' = $Config.AzureOpenAIApiKey
        'Content-Type' = 'application/json'
    }

    $body = @{
        model = $Config.AzureOpenAIModel
        instructions = $Instructions
        input = $Prompt
        max_output_tokens = $MaxOutputTokens
        store = $false
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Method Post -Uri (Get-AIEndpoint -Config $Config) -Headers $headers -Body $body
    $responseText = Get-AIResponseText -Response $response
    return Convert-TextToJsonObject -Text $responseText
}

function Invoke-StrictIncidentAnalysis {
    param(
        [hashtable]$Config,
        [psobject]$Incident,
        [string]$StrictCategory
    )

    $instructions = @'
You are an EUC incident analyst.
Return valid JSON only.
Do not use markdown wrappers.
Use only facts from the ticket payload.
Keep language concise and operational.
Return this exact JSON shape:
{
  "problem_statement": "string",
  "key_actions": ["string"],
  "critical_details": ["string"],
  "ai_analysis": "string",
  "confidence": "High|Medium|Low"
}
'@

    $promptPayload = [PSCustomObject]@{
        incident_number = [string]$Incident.number
        strict_category = $StrictCategory
        short_description = [string]$Incident.short_description
        category = [string](Get-DisplayValue $Incident.category)
        subcategory = [string](Get-DisplayValue $Incident.subcategory)
        resolution_category = [string](Get-DisplayValue $Incident.u_resolution_category)
        work_notes = Get-IncidentWorkText -Incident $Incident -MaxLength 9000
    }

    try {
        $analysis = Invoke-AzureJsonAnalysis -Config $Config -Instructions $instructions -Prompt ($promptPayload | ConvertTo-Json -Depth 8) -MaxOutputTokens 1100
        return [PSCustomObject]@{
            ProblemStatement = [string]$analysis.problem_statement
            KeyActions = @($analysis.key_actions)
            CriticalDetails = @($analysis.critical_details)
            AiAnalysis = [string]$analysis.ai_analysis
            Confidence = [string]$analysis.confidence
        }
    } catch {
        return [PSCustomObject]@{
            ProblemStatement = [string]$Incident.short_description
            KeyActions = @('Reviewed available ticket notes and captured current known troubleshooting context.')
            CriticalDetails = @('AI-generated detailed reasoning was unavailable for this ticket in this run.')
            AiAnalysis = [string]::Format('Fallback summary used due to AI error: {0}', $_.Exception.Message)
            Confidence = 'Low'
        }
    }
}

function New-StrictCategoryHtmlReport {
    param(
        [array]$CategoryRows,
        [array]$IncidentRows,
        [DateTime]$WeekStart,
        [DateTime]$ReportTimeIst
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html><html><head><meta charset="UTF-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine('<title>Strict Category Analysis - Current Work Week</title>')
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine('body{font-family:Segoe UI,Arial,sans-serif;background:#f8fafc;color:#0f172a;margin:0;padding:18px;}')
    [void]$sb.AppendLine('.wrap{max-width:1400px;margin:0 auto;} .hero{background:#0f172a;color:#fff;padding:16px 18px;border-radius:12px;margin-bottom:16px;}')
    [void]$sb.AppendLine('.hero h1{margin:0 0 6px;font-size:22px;} .hero p{margin:0;font-size:13px;color:#cbd5e1;}')
    [void]$sb.AppendLine('.card{background:#fff;border:1px solid #e2e8f0;border-radius:12px;box-shadow:0 1px 3px rgba(15,23,42,.06);margin-bottom:16px;overflow:hidden;}')
    [void]$sb.AppendLine('.card h2{margin:0;padding:12px 14px;background:#f1f5f9;font-size:16px;border-bottom:1px solid #e2e8f0;}')
    [void]$sb.AppendLine('table{width:100%;border-collapse:collapse;} th,td{padding:10px 12px;border-bottom:1px solid #f1f5f9;vertical-align:top;} th{background:#f8fafc;text-align:left;font-size:12px;text-transform:uppercase;color:#334155;letter-spacing:.05em;}')
    [void]$sb.AppendLine('tr:last-child td{border-bottom:none;} .incs a{display:inline-block;margin:2px 6px 2px 0;padding:3px 7px;border:1px solid #cbd5e1;border-radius:999px;text-decoration:none;color:#1d4ed8;font-size:12px;}')
    [void]$sb.AppendLine('.incs a:hover{background:#eff6ff;} .sn-btn{display:inline-block;background:#2563eb;color:#fff;padding:7px 10px;border-radius:8px;text-decoration:none;font-size:12px;font-weight:600;}')
    [void]$sb.AppendLine('.sn-btn:hover{background:#1d4ed8;} .details p{margin:0 0 8px;} .details .label{font-weight:700;color:#0f172a;} .details ul{margin:4px 0 8px 18px;padding:0;} .details li{margin:4px 0;} .mono{font-family:Consolas,monospace;font-size:12px;}')
    [void]$sb.AppendLine('</style></head><body><div class="wrap">')

    [void]$sb.AppendLine('<div class="hero">')
    [void]$sb.AppendLine('<h1>Strict Category Analysis Summary - Current Work Week</h1>')
    [void]$sb.AppendLine(([string]::Format('<p>Work week (IST): {0} to {1} | Generated (IST): {2}</p>', $WeekStart.ToString('dd MMM yyyy'), $ReportTimeIst.ToString('dd MMM yyyy HH:mm:ss'), $ReportTimeIst.ToString('dd MMM yyyy HH:mm:ss'))))
    [void]$sb.AppendLine('</div>')

    [void]$sb.AppendLine('<div class="card"><h2>1. Category-wise Incident Count and Incident Numbers</h2>')
    [void]$sb.AppendLine('<table><thead><tr><th>Strict Category</th><th>Count</th><th>Incident Numbers</th></tr></thead><tbody>')
    foreach ($row in @($CategoryRows)) {
        [void]$sb.AppendLine('<tr>')
        [void]$sb.AppendLine(([string]::Format('<td>{0}</td>', (Escape-Html ([string]$row.StrictCategory)))))
        [void]$sb.AppendLine(([string]::Format('<td>{0}</td>', [int]$row.Count)))
        [void]$sb.AppendLine('<td class="incs">')
        foreach ($inc in @($row.Incidents)) {
            [void]$sb.AppendLine(([string]::Format('<a href="#inc-{0}">{0}</a>', (Escape-Html ([string]$inc)))))
        }
        [void]$sb.AppendLine('</td></tr>')
    }
    [void]$sb.AppendLine('</tbody></table></div>')

    [void]$sb.AppendLine('<div class="card"><h2>2. Detailed EUC Incident Analysis</h2>')
    [void]$sb.AppendLine('<table><thead><tr><th>Incident</th><th>Strict Category</th><th>Detailed Summary</th><th>ServiceNow Link</th></tr></thead><tbody>')
    foreach ($row in @($IncidentRows)) {
        [void]$sb.AppendLine(([string]::Format('<tr id="inc-{0}">', (Escape-Html ([string]$row.IncidentNumber)))))
        [void]$sb.AppendLine(([string]::Format('<td class="mono">{0}</td>', (Escape-Html ([string]$row.IncidentNumber)))))
        [void]$sb.AppendLine(([string]::Format('<td>{0}</td>', (Escape-Html ([string]$row.StrictCategory)))))
        [void]$sb.AppendLine('<td class="details">')
        [void]$sb.AppendLine(([string]::Format('<p><span class="label">Problem:</span> {0}</p>', (Escape-Html ([string]$row.ProblemStatement)))))
        [void]$sb.AppendLine('<p><span class="label">Key Actions:</span></p><ul>')
        foreach ($item in @($row.KeyActions)) {
            [void]$sb.AppendLine(([string]::Format('<li>{0}</li>', (Escape-Html ([string]$item)))))
        }
        [void]$sb.AppendLine('</ul>')
        [void]$sb.AppendLine('<p><span class="label">Critical Details:</span></p><ul>')
        foreach ($item in @($row.CriticalDetails)) {
            [void]$sb.AppendLine(([string]::Format('<li>{0}</li>', (Escape-Html ([string]$item)))))
        }
        [void]$sb.AppendLine('</ul>')
        [void]$sb.AppendLine('<p><span class="label">Work Notes:</span></p><ul>')
        foreach ($note in @($row.WorkNotes)) {
            [void]$sb.AppendLine(([string]::Format('<li>"{0}"</li>', (Escape-Html ([string]$note)))))
        }
        [void]$sb.AppendLine('</ul>')
        [void]$sb.AppendLine(([string]::Format('<p><span class="label">AI Analysis ({0} Confidence):</span> {1}</p>', (Escape-Html ([string]$row.Confidence)), (Escape-Html ([string]$row.AiAnalysis)))))
        [void]$sb.AppendLine('</td>')
        [void]$sb.AppendLine(([string]::Format('<td><a class="sn-btn" href="{0}" target="_blank" rel="noopener">View in ServiceNow</a></td>', (Escape-Html ([string]$row.ServiceNowLink)))))
        [void]$sb.AppendLine('</tr>')
    }
    [void]$sb.AppendLine('</tbody></table></div>')

    [void]$sb.AppendLine('</div></body></html>')
    return $sb.ToString()
}

Write-Step 'Starting strict category current work week report generation...' 'Green'

$config = Load-LocalConfiguration
$reportTimeIst = Get-IstDateTime
$weekStartIst = Get-WeekStartMonday -DateValue $reportTimeIst

# Fetch enough data to always cover current work week in IST.
$lookbackDays = [int]([Math]::Max(2, [Math]::Ceiling(($reportTimeIst.Date - $weekStartIst.Date).TotalDays + 1)))

$runStamp = $reportTimeIst.ToString('yyyy-MM-dd_HH-mm-ss')
$runDirectory = Get-OutputDirectory -PathName $runStamp
$analysisDirectory = Get-OutputDirectory -PathName (Join-Path $runStamp 'analysis')
$rawDirectory = Get-OutputDirectory -PathName (Join-Path $runStamp 'raw')

Write-Step ([string]::Format('Output directory: {0}', $runDirectory)) 'Green'

$rawIncidents = Get-ServiceNowIncidents -Config $config -LookbackDaysValue $lookbackDays
$rawPath = Join-Path $rawDirectory 'raw_incidents.json'
Save-JsonFile -Data $rawIncidents -Path $rawPath
Write-Step ([string]::Format('Saved raw incidents to {0}', $rawPath)) 'Green'

$selected = @($rawIncidents | Where-Object {
    $incidentDate = Get-IncidentDateValue -Incident $_
    if (-not $incidentDate) { return $false }

    # Interpret incident timestamps in IST for current work week filtering.
    $incidentIst = try {
        $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')
        [System.TimeZoneInfo]::ConvertTimeFromUtc($incidentDate.ToUniversalTime(), $tz)
    } catch {
        $incidentDate
    }

    $serviceOffering = Get-DisplayValue $_.service_offering
    $businessService = Get-DisplayValue $_.business_service
    $inScope = ($serviceOffering -eq $TargetServiceOffering -and $businessService -eq $TargetBusinessService)

    $inScope -and $incidentIst.Date -ge $weekStartIst.Date -and $incidentIst.Date -le $reportTimeIst.Date
})

$selected = @($selected | Sort-Object -Property @{ Expression = { Get-IncidentDateValue -Incident $_ }; Descending = $true })
if ($MaxIncidents -gt 0 -and $selected.Count -gt $MaxIncidents) {
    $selected = @($selected | Select-Object -First $MaxIncidents)
}

if ($selected.Count -eq 0) {
    throw 'No incidents found for current work week and Productivity Tools scope.'
}

$selectedPath = Join-Path $rawDirectory 'selected_current_ww_incidents.json'
Save-JsonFile -Data $selected -Path $selectedPath
Write-Step ([string]::Format('Selected {0} incidents for strict category analysis.', $selected.Count)) 'Green'

$incidentRows = New-Object System.Collections.Generic.List[object]
foreach ($incident in @($selected)) {
    $strictCategory = Resolve-StrictCategory -Incident $incident
    Write-Step ([string]::Format('Analyzing {0} ({1})...', $incident.number, $strictCategory)) 'DarkCyan'
    $analysis = Invoke-StrictIncidentAnalysis -Config $config -Incident $incident -StrictCategory $strictCategory

    $rawWorkNotes = [string]$incident.comments_and_work_notes
    $workNotesPreview = @()
    if (-not [string]::IsNullOrWhiteSpace($rawWorkNotes)) {
        $workNotesPreview = @($rawWorkNotes -split '(\r\n|\n)' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 3)
    }
    if (@($workNotesPreview).Count -eq 0) {
        $workNotesPreview = @('No concise work-note lines available in this ticket payload.')
    }

    $incidentRows.Add([PSCustomObject]@{
        IncidentNumber = [string]$incident.number
        StrictCategory = $strictCategory
        ProblemStatement = [string]$analysis.ProblemStatement
        KeyActions = @($analysis.KeyActions)
        CriticalDetails = @($analysis.CriticalDetails)
        WorkNotes = @($workNotesPreview)
        AiAnalysis = [string]$analysis.AiAnalysis
        Confidence = if ([string]::IsNullOrWhiteSpace([string]$analysis.Confidence)) { 'Medium' } else { [string]$analysis.Confidence }
        ServiceNowLink = Get-ServiceNowViewLink -Incident $incident
        IncidentDate = Get-IncidentDateValue -Incident $incident
    })
}

$incidentRowsArray = @($incidentRows.ToArray())

$categoryRows = @($incidentRowsArray |
    Group-Object StrictCategory |
    Sort-Object Count -Descending |
    ForEach-Object {
        [PSCustomObject]@{
            StrictCategory = [string]$_.Name
            Count = [int]$_.Count
            Incidents = @($_.Group | Select-Object -ExpandProperty IncidentNumber)
        }
    })

$analysisJsonPath = Join-Path $analysisDirectory 'strict_category_incident_analysis.json'
Save-JsonFile -Data $incidentRowsArray -Path $analysisJsonPath
Write-Step ([string]::Format('Saved strict category incident analysis to {0}', $analysisJsonPath)) 'Green'

$summaryJsonPath = Join-Path $analysisDirectory 'strict_category_summary.json'
Save-JsonFile -Data $categoryRows -Path $summaryJsonPath
Write-Step ([string]::Format('Saved strict category summary to {0}', $summaryJsonPath)) 'Green'

$html = New-StrictCategoryHtmlReport -CategoryRows $categoryRows -IncidentRows $incidentRowsArray -WeekStart $weekStartIst -ReportTimeIst $reportTimeIst
$htmlPath = Join-Path $runDirectory 'Strict_Category_Current_Work_Week_Report.html'
Set-Content -Path $htmlPath -Value $html -Encoding UTF8
Write-Step ([string]::Format('Saved HTML report to {0}', $htmlPath)) 'Green'

Write-Host ''
Write-Host 'Run complete.' -ForegroundColor Green
Write-Host ([string]::Format('Selected incidents: {0}', $selectedPath)) -ForegroundColor Green
Write-Host ([string]::Format('Analysis JSON: {0}', $analysisJsonPath)) -ForegroundColor Green
Write-Host ([string]::Format('Summary JSON: {0}', $summaryJsonPath)) -ForegroundColor Green
Write-Host ([string]::Format('HTML report: {0}', $htmlPath)) -ForegroundColor Green
