<#
.SYNOPSIS
    Fetch Content Engineering incidents for WW26 + WW27, run AI analysis,
    and generate TrendSubCategorisation + PossibleRootCause markdown report files.

.PARAMETER WeekList
    Comma-separated ISO week numbers (e.g. "26,27"). Default: "26,27".

.PARAMETER Year
    Year for the week numbers. Default: current year.

.PARAMETER SkipAI
    Fetch and save raw JSON only; skip the AI categorisation step.

.PARAMETER OutputRoot
    Where to write output files. Default: local-output\content-engineering-analysis\

.EXAMPLE
    .\Analyze-ContentEngIncidents.ps1
    .\Analyze-ContentEngIncidents.ps1 -WeekList "26,27" -SkipAI
#>
param(
    [string]$WeekList   = '26,27',
    [int]   $Year       = (Get-Date).Year,
    [switch]$SkipAI,
    [switch]$StrictMode,
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configPath  = Join-Path $PSScriptRoot '..\config\LocalConfig-ContentEngineering.psd1'
$secretsPath = Join-Path $PSScriptRoot '..\config\LocalSecrets-ContentEngineering.psd1'
$templateDir = Join-Path $PSScriptRoot '..\templates'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'local-output\content-engineering-analysis'
}
if (-not (Test-Path $OutputRoot)) { New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null }

$config  = Import-PowerShellDataFile $configPath
$secrets = Import-PowerShellDataFile $secretsPath

function Write-Step {
    param([string]$Msg, [string]$Color = 'Cyan')
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Msg" -ForegroundColor $Color
}

function Get-ISOWeekWindow {
    param([int]$WeekYear, [int]$WeekNum)
    $jan4   = [datetime]::new($WeekYear, 1, 4)
    $dow    = [int]$jan4.DayOfWeek; if ($dow -eq 0) { $dow = 7 }
    $ww1Mon = $jan4.AddDays(1 - $dow)
    $start  = $ww1Mon.AddDays(($WeekNum - 1) * 7)
    return @{
        Start = $start
        End   = $start.AddDays(7).AddSeconds(-1)
        Label = ('{0}-W{1:00}' -f $WeekYear, $WeekNum)
    }
}

function Get-OAuthToken {
    $resp = Invoke-RestMethod -Uri $config.TokenUrl -Method Post -ErrorAction Stop `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{
            grant_type    = 'client_credentials'
            client_id     = $config.ServiceNowClientID
            client_secret = $secrets.ServiceNowClientSecret
            scope         = $config.ServiceNowScope
        }
    return $resp.access_token
}

function Invoke-OpenAI {
    param([string]$SystemPrompt, [string]$UserMessage)
    $apiKey = $secrets.AzureOpenAIApiKey
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "AzureOpenAIApiKey is empty in LocalSecrets-ContentEngineering.psd1."
    }
    $url = '{0}/openai/deployments/{1}/chat/completions?api-version={2}' -f `
        $config.AzureOpenAIBaseUrl, $config.AzureOpenAIDeployment, $config.AzureOpenAIApiVersion
    $body = @{
        messages              = @(
            @{ role = 'system'; content = $SystemPrompt }
            @{ role = 'user';   content = $UserMessage }
        )
        max_completion_tokens = 3000
    } | ConvertTo-Json -Depth 10
    $headers = @{ 'api-key' = $apiKey; 'Content-Type' = 'application/json' }
    $resp = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -ErrorAction Stop
    return $resp.choices[0].message.content
}

# Extract the exact bold labels defined for a given category section in a template.
# Used to build the per-category ALLOWED label lists for Steps 2 and 3.
function Get-LabelsForCategory {
    param([string]$Category, [string]$TemplateContent)
    $escaped = [regex]::Escape($Category)
    if ($TemplateContent -match "(?ms)###\s+$escaped\s*\r?\n(.+?)(?=\n###|\z)") {
        $section = $matches[1]
        $labels  = [regex]::Matches($section, '\*\*([^*]+)\*\*') | ForEach-Object { $_.Groups[1].Value.Trim() }
        return $labels
    }
    return @()
}

# parse week list
$weeks = $WeekList -split ',' | ForEach-Object { [int]$_.Trim() }

Write-Step '=== Content Engineering Incident Analyser ===' 'Yellow'
Write-Step ('Weeks: {0}  Year: {1}' -f ($weeks -join ', '), $Year)

# OAuth
Write-Step 'Acquiring OAuth token...'
$snToken   = Get-OAuthToken
$snHeaders = @{ Authorization = "Bearer $snToken" }
Write-Step 'Token acquired.' 'Green'

$snBase   = 'https://apis.intel.com/itsm/api/now/table/incident'
$snFields = 'number,short_description,description,work_notes,category,subcategory,state,resolved_at,opened_at,business_service,service_offering,assignment_group'

$allIncidents  = [System.Collections.Generic.List[psobject]]::new()
$weekSummaries = @{}

foreach ($wkNum in $weeks) {
    $window = Get-ISOWeekWindow -WeekYear $Year -WeekNum $wkNum
    $lbl    = $window.Label
    Write-Step ('Fetching {0}  ({1} to {2})...' -f $lbl, $window.Start.ToString('yyyy-MM-dd'), $window.End.ToString('yyyy-MM-dd'))

    $query = 'business_service={0}^service_offering={1}^stateIN6,7^resolved_at>={2}^resolved_at<={3}^ORDERBYDESCresolved_at' -f `
        $config.BusinessServiceId, $config.ServiceOfferingId,
        $window.Start.ToString('yyyy-MM-dd HH:mm:ss'),
        $window.End.ToString('yyyy-MM-dd HH:mm:ss')

    $enc  = [uri]::EscapeDataString($query)
    $url  = ('{0}?sysparm_query={1}&sysparm_display_value=true&sysparm_fields={2}&sysparm_limit=500' -f $snBase, $enc, $snFields)
    $resp = Invoke-RestMethod -Uri $url -Headers $snHeaders -Method Get -ErrorAction Stop
    $incs = @($resp.result)
    Write-Step ('  {0}: {1} incident(s)' -f $lbl, $incs.Count) 'Green'

    foreach ($inc in $incs) {
        $inc | Add-Member -NotePropertyName 'YearWeek' -NotePropertyValue $lbl -Force
        foreach ($prop in 'business_service','service_offering','assignment_group','resolved_at','opened_at') {
            if ($inc.$prop -is [psobject] -and $inc.$prop.PSObject.Properties['display_value']) {
                $inc.$prop = [string]$inc.$prop.display_value
            }
        }
        $allIncidents.Add($inc)
    }

    $weekSummaries[$lbl] = $incs.Count
    $rawPath = Join-Path $OutputRoot ('{0}_raw_incidents.json' -f $lbl)
    $incs | ConvertTo-Json -Depth 10 | Set-Content -Path $rawPath -Encoding UTF8
    Write-Step ('  Saved raw JSON: {0}' -f $rawPath) 'DarkGray'
}

Write-Step ('Total incidents fetched: {0}' -f $allIncidents.Count) 'Green'

if ($allIncidents.Count -eq 0) {
    Write-Step 'No incidents found. Exiting.' 'Yellow'; exit 0
}

if (-not $PSBoundParameters.ContainsKey('StrictMode')) {
    $StrictMode = $true
}

if ($SkipAI) {
    Write-Step 'SkipAI flag set - skipping AI steps.' 'Yellow'
    Write-Step '=== Fetch complete ===' 'Yellow'
    foreach ($kv in $weekSummaries.GetEnumerator() | Sort-Object Key) {
        Write-Step ('  {0}: {1} incidents' -f $kv.Key, $kv.Value) 'White'
    }
    exit 0
}

# load templates
$tplTicket = Get-Content (Join-Path $templateDir 'TicketCategorisation_ContentEngineering.md') -Raw -Encoding UTF8
$tplEnv    = Get-Content (Join-Path $templateDir 'EnvironmentContext_ContentEngineering.md')    -Raw -Encoding UTF8
$tplTrend  = Get-Content (Join-Path $templateDir 'TrendSubCategorisation_ContentEngineering.md') -Raw -Encoding UTF8
$tplRoot   = Get-Content (Join-Path $templateDir 'PossibleRootCause_ContentEngineering.md') -Raw -Encoding UTF8

# Combined system prompt used for per-ticket full analysis
$fullSystemPrompt = $tplTicket + "`n`n" + $tplEnv + "`n`n" +
    "## REFERENCE: Symptom Labels by Product`n" + $tplTrend + "`n`n" +
    "## REFERENCE: Root Cause Labels by Product`n" + $tplRoot + @'


## REQUIRED OUTPUT FORMAT (STRICT)
Respond with exactly these nine lines — no markdown, no bullets, no extra text:

Primary Category: <exact bold product name from the taxonomy above — e.g. "Microsoft Teams", "SharePoint On-Premises", "SharePoint Online". Use "Unknown / Unclear" only if nothing fits.>
Sub-symptom: <exact bold symptom label from the SAME product section as Primary Category — e.g. if category is "SharePoint Online" you MUST pick from: Permission Denied, Site Administration Request, File / Item Recovery, SPO How-To / User Education. Never use a label from a different product section. Do NOT invent.>
Possible Root Cause: <exact bold root cause label from the SAME product section as Primary Category in the Root Cause reference. Never use a label from a different product section. Do NOT invent.>
Confidence Level: <Apply the CONFIDENCE CALCULATION FRAMEWORK from the template. Start at 70% baseline. Add: +25% if application/platform is clearly identified and matches the category; +15% if a specific error message, error code, or permission/role name is present; +5% if a KB number or KB link is cited; +10% if the agent used Content-Engineering-specific terminology (AEM, Sitecore, DAM, SSO, SPO permissions, publishing pipeline, workflow approval); +15% if the resolution matches the category examples exactly. Subtract: -20% if platform is unclear/ambiguous/contradictory; -10% if only user symptom language is present with no agent technical detail; -10% if multiple categories apply equally; -25% if description, work notes, and close notes contradict each other. Final score above 89% = High; 70-89% = Medium; below 70% = Low. If Primary Category is Unknown / Unclear, always output Low.>
Issue: <Describe the actual issue and observed impact using only ServiceNow work notes, close notes, and investigation notes. Do not repeat the category or symptom label as the answer.>
Root Cause Detail: <Describe the actual underlying cause from investigation notes and engineer updates. Do not output only the root cause label.>
Resolution Detail: <Describe the exact corrective or recovery action taken to resolve the incident.>
Evidence Detail: <Describe the concrete findings, checks, logs, or validation evidence that support the diagnosis and resolution.>
AI Analysis: <3–5 plain sentences summarizing the incident using only validated ServiceNow details from work notes and close notes.>

Rules: Each label appears verbatim followed by a colon. Plain ASCII only. One line per field.
'@

function Get-StructuredProblemAnalysis {
    param([object]$Incident)

    $confidence = if ($Incident.ai_confidence) { [string]$Incident.ai_confidence } else { 'Low' }

    return @(
        'Problem:',
        "Issue: $([string]$Incident.ai_issue)",
        "Root Cause: $([string]$Incident.ai_rootcause_detail)",
        "Resolution: $([string]$Incident.ai_resolution_detail)",
        "Evidence: $([string]$Incident.ai_evidence_detail)",
        '',
        "AI Analysis ($confidence confidence): $([string]$Incident.ai_analysis)"
    ) -join "`n"
}

# Step 1: categorise each incident with full analysis
Write-Step ('Step 1/3 - Categorising {0} incidents with full analysis...' -f $allIncidents.Count) 'Cyan'
$categorised = [System.Collections.Generic.List[psobject]]::new()

foreach ($inc in $allIncidents) {
    function Sanitize-Text {
        param([string]$Text)
        if ([string]::IsNullOrEmpty($Text)) { return '' }
        $clean = $Text -replace "[\x00-\x08\x0B\x0C\x0E-\x1F]", ' '
        $clean = $clean -replace '[^\u0009\u000A\u000D\u0020-\u007E]', ' '
        $clean = $clean -replace '\s+', ' '
        return $clean.Trim()
    }

    $rawWorkNotes = Sanitize-Text -Text ([string]$inc.work_notes)
    $rawCloseNotes = Sanitize-Text -Text ([string]$inc.close_notes)
    $shortDescription = Sanitize-Text -Text ([string]$inc.short_description)

    function New-IncidentPrompt {
        param([int]$WorkNotesMaxChars)
        $workNotes = $rawWorkNotes
        if ($workNotes.Length -gt $WorkNotesMaxChars) {
            $workNotes = $workNotes.Substring(0, $WorkNotesMaxChars) + '...[truncated]'
        }
        $closeNotes = $rawCloseNotes
        if ($closeNotes.Length -gt 1500) {
            $closeNotes = $closeNotes.Substring(0, 1500) + '...[truncated]'
        }
        return @"
Incident: $($inc.number)
Short description: $shortDescription
Work notes: $workNotes
Close notes: $closeNotes
Close code: $($inc.close_code)
Resolved at: $($inc.resolved_at)
"@
    }
    try {
        $raw = $null; $cat = $null; $sub = $null; $rc = $null; $conf = $null; $issue = $null; $rootDetail = $null; $resolutionDetail = $null; $evidenceDetail = $null; $anal = $null
        $parsedOk = $false
        $attemptLimits = @(4000, 2200, 1000)
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $userMsg = New-IncidentPrompt -WorkNotesMaxChars $attemptLimits[$attempt - 1]
            $raw = Invoke-OpenAI -SystemPrompt $fullSystemPrompt -UserMessage $userMsg
            $cat  = if ($raw -match '(?im)^Primary Category:\s*(.+)$')   { $matches[1].Trim() -replace '\*','' } else { '' }
            $sub  = if ($raw -match '(?im)^Sub-symptom:\s*(.+)$')          { $matches[1].Trim() -replace '\*','' } else { '' }
            $rc   = if ($raw -match '(?im)^Possible Root Cause:\s*(.+)$')  { $matches[1].Trim() -replace '\*','' } else { '' }
            $conf = if ($raw -match '(?im)^Confidence Level:\s*(High|Medium|Low)') { $matches[1].Trim() } else { '' }
            $issue = if ($raw -match '(?im)^Issue:\s*(.+)$')               { $matches[1].Trim() } else { '' }
            $rootDetail = if ($raw -match '(?im)^Root Cause Detail:\s*(.+)$') { $matches[1].Trim() } else { '' }
            $resolutionDetail = if ($raw -match '(?im)^Resolution Detail:\s*(.+)$') { $matches[1].Trim() } else { '' }
            $evidenceDetail = if ($raw -match '(?im)^Evidence Detail:\s*(.+)$') { $matches[1].Trim() } else { '' }
            $anal = if ($raw -match '(?im)^AI Analysis:\s*(.+)$')           { $matches[1].Trim() } else { '' }

            $parsedOk = -not [string]::IsNullOrWhiteSpace($cat) -and
                        -not [string]::IsNullOrWhiteSpace($sub) -and
                        -not [string]::IsNullOrWhiteSpace($rc) -and
                        -not [string]::IsNullOrWhiteSpace($conf) -and
                        -not [string]::IsNullOrWhiteSpace($issue) -and
                        -not [string]::IsNullOrWhiteSpace($rootDetail) -and
                        -not [string]::IsNullOrWhiteSpace($resolutionDetail) -and
                        -not [string]::IsNullOrWhiteSpace($evidenceDetail) -and
                        -not [string]::IsNullOrWhiteSpace($anal) -and
                        ($anal -notmatch '(?i)fallback|automated fallback')
            if ($parsedOk) { break }
            Write-Step ("  {0}: retrying AI parse attempt {1}/3" -f $inc.number, $attempt) 'Yellow'
        }

        if (-not $parsedOk -and $StrictMode) {
            throw "Strict mode: missing or fallback AI fields after retries"
        }

        if ([string]::IsNullOrWhiteSpace($cat))  { $cat = 'Unknown / Unclear' }
        if ([string]::IsNullOrWhiteSpace($sub))  { $sub = 'Insufficient Information' }
        if ([string]::IsNullOrWhiteSpace($rc))   { $rc = 'Unknown' }
        if ([string]::IsNullOrWhiteSpace($conf)) { $conf = if ($cat -eq 'Unknown / Unclear') { 'Low' } else { 'Medium' } }
        if ([string]::IsNullOrWhiteSpace($anal)) { $anal = '' }
        $inc | Add-Member -NotePropertyName 'ai_category'    -NotePropertyValue $cat  -Force
        $inc | Add-Member -NotePropertyName 'ai_subcategory' -NotePropertyValue $sub  -Force
        $inc | Add-Member -NotePropertyName 'ai_rootcause'   -NotePropertyValue $rc   -Force
        $inc | Add-Member -NotePropertyName 'ai_confidence'  -NotePropertyValue $conf -Force
        $inc | Add-Member -NotePropertyName 'ai_issue'       -NotePropertyValue $issue -Force
        $inc | Add-Member -NotePropertyName 'ai_rootcause_detail' -NotePropertyValue $rootDetail -Force
        $inc | Add-Member -NotePropertyName 'ai_resolution_detail' -NotePropertyValue $resolutionDetail -Force
        $inc | Add-Member -NotePropertyName 'ai_evidence_detail' -NotePropertyValue $evidenceDetail -Force
        $inc | Add-Member -NotePropertyName 'ai_analysis'    -NotePropertyValue $anal -Force
        Write-Host ('    {0}  [{1}] {2} / {3}' -f $inc.number, $cat, $sub, $rc) -ForegroundColor DarkGray
    } catch {
        if ($StrictMode) {
            throw ("Strict mode failure for {0}: {1}" -f $inc.number, $_.Exception.Message)
        }
        $inc | Add-Member -NotePropertyName 'ai_category'    -NotePropertyValue 'Unknown / Unclear'        -Force
        $inc | Add-Member -NotePropertyName 'ai_subcategory' -NotePropertyValue 'Insufficient Information'  -Force
        $inc | Add-Member -NotePropertyName 'ai_rootcause'   -NotePropertyValue 'Unknown'                  -Force
        $inc | Add-Member -NotePropertyName 'ai_confidence'  -NotePropertyValue 'Low'                      -Force
        $inc | Add-Member -NotePropertyName 'ai_issue'       -NotePropertyValue ''                         -Force
        $inc | Add-Member -NotePropertyName 'ai_rootcause_detail' -NotePropertyValue ''                    -Force
        $inc | Add-Member -NotePropertyName 'ai_resolution_detail' -NotePropertyValue ''                   -Force
        $inc | Add-Member -NotePropertyName 'ai_evidence_detail' -NotePropertyValue ''                     -Force
        $inc | Add-Member -NotePropertyName 'ai_analysis'    -NotePropertyValue ''                         -Force
        Write-Step ('  {0}: failed - {1}' -f $inc.number, $_.Exception.Message) 'Yellow'
    }
    $categorised.Add($inc)
}

$catPath = Join-Path $OutputRoot ('categorised_incidents_{0}.json' -f (Get-Date -Format 'yyyy-MM-dd'))
$categorised | ConvertTo-Json -Depth 10 | Set-Content -Path $catPath -Encoding UTF8
Write-Step ('Categorised JSON saved: {0}' -f $catPath) 'Green'

# Step 2: trend sub-categorisation
Write-Step 'Step 2/3 - Building trend sub-categorisation report...' 'Cyan'
$grouped  = $categorised | Group-Object ai_category
$trendSb  = [System.Text.StringBuilder]::new()
$null = $trendSb.AppendLine('## Incident Sub-Categorisation for Trend Analysis -- Content Engineering')
$null = $trendSb.AppendLine('')
$null = $trendSb.AppendLine(('**Period:** WW{0}  |  **Total incidents:** {1}' -f ($weeks -join ' + WW'), $allIncidents.Count))
$null = $trendSb.AppendLine('')

foreach ($grp in ($grouped | Sort-Object Count -Descending)) {
    $cat  = $grp.Name
    $incs = @($grp.Group)
    $list = ($incs | ForEach-Object { '- {0}: {1}' -f $_.number, $_.short_description }) -join "`n"

    $allowedSubs = Get-LabelsForCategory -Category $cat -TemplateContent $tplTrend
    if ($allowedSubs.Count -eq 0) { $allowedSubs = @('Insufficient Ticket Detail', 'Out of Scope Incident') }
    $allowedSubsList = $allowedSubs -join "`n"

    $userMsg = @"
Category: $cat
Incidents ($($incs.Count) total):
$list

ALLOWED SUB-SYMPTOM LABELS FOR '$cat' (you MUST use exactly one of these — no other values are permitted, do not use labels from other categories):
$allowedSubsList

Assign exactly one label from the ALLOWED list above to each incident. Output must use exact label text.
Respond with JSON array only: [{"number":"INCxxx","sub_symptom":"<exact allowed label>"},...]
"@
    try {
        $raw     = Invoke-OpenAI -SystemPrompt $tplTrend -UserMessage $userMsg
        $raw     = $raw -replace '(?s)^```json\s*', '' -replace '(?s)```\s*$', ''
        $subsyms = $raw | ConvertFrom-Json
        foreach ($ss in $subsyms) {
            $m = $categorised | Where-Object { $_.number -eq $ss.number } | Select-Object -First 1
            if ($m) { $m | Add-Member -NotePropertyName 'sub_symptom' -NotePropertyValue ([string]$ss.sub_symptom) -Force }
        }
        $subCounts = $subsyms | Group-Object sub_symptom | Sort-Object Count -Descending
        $null = $trendSb.AppendLine(('### {0}  ({1} tickets)' -f $cat, $incs.Count))
        $null = $trendSb.AppendLine('')
        $null = $trendSb.AppendLine('| Sub-Symptom | Count |')
        $null = $trendSb.AppendLine('|---|---|')
        foreach ($sc in $subCounts) {
            $null = $trendSb.AppendLine(('| {0} | {1} |' -f $sc.Name, $sc.Count))
        }
        $null = $trendSb.AppendLine('')
        Write-Step ('  {0}: {1} incidents, {2} sub-symptoms' -f $cat, $incs.Count, $subCounts.Count) 'DarkGray'
    } catch {
        $null = $trendSb.AppendLine(('### {0}  ({1} tickets)' -f $cat, $incs.Count))
        $null = $trendSb.AppendLine('')
        $null = $trendSb.AppendLine(('_Sub-symptom analysis failed: {0}_' -f $_.Exception.Message))
        $null = $trendSb.AppendLine('')
        Write-Step ('  {0}: sub-symptom step failed - {1}' -f $cat, $_.Exception.Message) 'Yellow'
    }
}

$trendPath = Join-Path $OutputRoot 'blob-TrendSubCategorisation_ContentEngineering.md'
$trendSb.ToString() | Set-Content -Path $trendPath -Encoding UTF8
Write-Step ('Trend MD saved: {0}' -f $trendPath) 'Green'

# Step 3: possible root cause
Write-Step 'Step 3/3 - Generating possible root cause analysis...' 'Cyan'
$rootSb = [System.Text.StringBuilder]::new()
$null = $rootSb.AppendLine('## Possible Root Cause Analysis -- Content Engineering')
$null = $rootSb.AppendLine('')
$null = $rootSb.AppendLine(('**Period:** WW{0}  |  **Total incidents:** {1}' -f ($weeks -join ' + WW'), $allIncidents.Count))
$null = $rootSb.AppendLine('')

foreach ($grp in ($grouped | Sort-Object Count -Descending)) {
    $cat  = $grp.Name
    $incs = @($grp.Group)
    $list = ($incs | ForEach-Object { '- {0}: {1}' -f $_.number, $_.short_description }) -join "`n"

    $allowedRoots = Get-LabelsForCategory -Category $cat -TemplateContent $tplRoot
    if ($allowedRoots.Count -eq 0) { $allowedRoots = @('Root Cause Undetermined', 'External Dependency') }
    $allowedRootsList = $allowedRoots -join "`n"

    $userMsg = @"
Category: $cat
Incidents ($($incs.Count) total):
$list

ALLOWED ROOT CAUSE LABELS FOR '$cat' (you MUST use exactly one of these -- no other values are permitted, do not use labels from other categories):
$allowedRootsList

Using ONLY the root cause labels listed above, identify the top 1-3 most likely root causes. Do NOT use labels from other categories.
Respond with JSON only:
{"category":"$cat","root_causes":[{"label":"<exact allowed label>","count":<affected tickets>,"evidence":"<1 sentence>"},...]}
"@
    try {
        $raw    = Invoke-OpenAI -SystemPrompt $tplRoot -UserMessage $userMsg
        $raw    = $raw -replace '(?s)^```json\s*', '' -replace '(?s)```\s*$', ''
        $result = $raw | ConvertFrom-Json
        $null = $rootSb.AppendLine(('### {0}  ({1} tickets)' -f $cat, $incs.Count))
        $null = $rootSb.AppendLine('')
        foreach ($rc in $result.root_causes) {
            $null = $rootSb.AppendLine(('**{0}**  ({1} ticket(s))' -f $rc.label, $rc.count))
            $null = $rootSb.AppendLine('')
            $null = $rootSb.AppendLine(('> {0}' -f $rc.evidence))
            $null = $rootSb.AppendLine('')
        }
        Write-Step ('  {0}: {1} root cause(s) identified' -f $cat, $result.root_causes.Count) 'DarkGray'
    } catch {
        $null = $rootSb.AppendLine(('### {0}  ({1} tickets)' -f $cat, $incs.Count))
        $null = $rootSb.AppendLine('')
        $null = $rootSb.AppendLine(('_Root cause analysis failed: {0}_' -f $_.Exception.Message))
        $null = $rootSb.AppendLine('')
        Write-Step ('  {0}: root cause step failed - {1}' -f $cat, $_.Exception.Message) 'Yellow'
    }
}

$rootPath = Join-Path $OutputRoot 'blob-PossibleRootCause_ContentEngineering.md'
$rootSb.ToString() | Set-Content -Path $rootPath -Encoding UTF8
Write-Step ('Root cause MD saved: {0}' -f $rootPath) 'Green'

# ── Step 4: Write categorised rows to Azure Table (IncidentsCategoryStats) ────
Write-Step 'Step 4/4 - Writing rows to Azure Table (IncidentsCategoryStats)...' 'Cyan'
try {
    $saName = if ($config.StorageAccountName) { $config.StorageAccountName } else { 'opswcontentenggblob' }
    $saRg   = if ($config.ResourceGroupName)  { $config.ResourceGroupName  } else { 'OPSW-Ticket-Analyzer' }

    Import-Module Az.Accounts -MinimumVersion 2.0.0 -Force -ErrorAction Stop
    Import-Module Az.Storage  -MinimumVersion 2.0.0 -Force -ErrorAction Stop

    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) { Connect-AzAccount -ErrorAction Stop | Out-Null }

    if (-not (Get-Module -ListAvailable -Name AzTable)) {
        throw "AzTable module not installed. Run: Install-Module AzTable -Scope CurrentUser"
    }
    Import-Module AzTable -Force

    $saKey   = (Get-AzStorageAccountKey -ResourceGroupName $saRg -Name $saName)[0].Value
    $saCtx   = New-AzStorageContext -StorageAccountName $saName -StorageAccountKey $saKey
    $tbl     = Get-AzStorageTable -Name 'IncidentsCategoryStats' -Context $saCtx -ErrorAction Stop
    $cloud   = $tbl.CloudTable

    $written = 0; $skipped = 0
    foreach ($inc in $categorised) {
        $resolvedAt = [string]($inc.resolved_at -replace ' ', 'T')
        $weekLabel  = [string]$inc.YearWeek
        $rowKey     = [string]$inc.number

        $row = @{
            Category       = [string]$inc.ai_category
            Subcategory    = [string]$inc.ai_subcategory
            PossibleRootCause = if ($inc.ai_rootcause)   { [string]$inc.ai_rootcause }   else { 'Unknown' }
            DetailedRootCause = ''
            RootCause      = if ($inc.ai_rootcause)   { [string]$inc.ai_rootcause }   else { 'Unknown' }
            Confidence     = if ($inc.ai_confidence)  { [string]$inc.ai_confidence }  else { if ($inc.ai_category -eq 'Unknown / Unclear') { 'Low' } else { 'Medium' } }
            AIAnalysis     = Get-StructuredProblemAnalysis -Incident $inc
            Date           = $resolvedAt
            YearWeek       = $weekLabel
            Year           = [int]$Year
            WeekNumber     = [int](($weekLabel -split '-W')[1])
            Service        = 'Content Engineering'
            Misrouted      = $false
            OriginalDescription = [string]$inc.short_description
            ReportBlobName = 'local-analyze-script'
        }
        Add-AzTableRow -Table $cloud -PartitionKey $weekLabel -RowKey $rowKey -Property $row -UpdateExisting | Out-Null
        $written++
    }
    Write-Step ("  Azure Table: $written rows written, $skipped already existed") 'Green'
} catch {
    Write-Step ("  [WARN] Azure Table write skipped: $($_.Exception.Message)") 'Yellow'
}

# summary
Write-Step '' 'White'
Write-Step '=== Complete ===' 'Yellow'
Write-Step ('Output folder: {0}' -f $OutputRoot) 'White'
foreach ($kv in $weekSummaries.GetEnumerator() | Sort-Object Key) {
    Write-Step ('  {0}: {1} incidents' -f $kv.Key, $kv.Value) 'White'
}
Write-Step ('  Categorised JSON : {0}' -f $catPath) 'White'
Write-Step ('  Trend MD         : {0}' -f $trendPath) 'White'
Write-Step ('  Root Cause MD    : {0}' -f $rootPath) 'White'
