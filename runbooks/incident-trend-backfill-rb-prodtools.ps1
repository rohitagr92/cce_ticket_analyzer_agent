<#
.SYNOPSIS
    Daily incremental backfill of IncidentsCategoryStats for Trends + Ops Report dashboards.
    Designed to run unattended in Azure Automation.

.DESCRIPTION
    For each calendar day in the lookback window (default 2 days), this runbook:
      1. Queries ServiceNow for Productivity Tools incidents resolved that day
         (business_service + service_offering scope; state 6 [Resolved] or 7 [Closed]).
      2. Checks Azure Table Storage (IncidentsCategoryStats) for existing entries.
         - If a ticket has a complete, valid AI Analysis, it is skipped to save AI cost.
         - If a ticket is missing OR contains old generic fallback text, it is RE-PROCESSED and updated.
      3. Calls Azure OpenAI to generate a rich, ticket-specific classification and analysis.
      4. Writes/updates the row in Azure Table Storage with proper AI Analysis.
      5. Regenerates weekly HTML dashboards for affected work weeks and updates index.json.

.NOTES
    Execution Context: Azure Automation (PowerShell 7.2 Core runtime recommended)
    Authentication: Azure Managed Identity for Azure Resources; OAuth Client Credentials for ServiceNow
#>

[CmdletBinding()]
param(
    # Controls how many days into the past to check for resolved incidents (0 = load from Automation Variable)
    [int]$LookbackDays = 0,   

    # Optional cap to limit maximum processing count per day (0 = process all fetched incidents)
    [int]$MaxPerDay     = 0    
)

$ErrorActionPreference = 'Stop'

# ===================================================================================
# SECTION 1: HELPER FUNCTIONS (LOGGING & STRING SANITIZATION)
# ===================================================================================

function Write-Step { 
    param([string]$Msg, [string]$Color = 'Cyan') 
    Write-Output "[$(Get-Date -Format 'HH:mm:ss')] $Msg" 
}

function Get-SafeSubstring {
    param([string]$InputString, [int]$MaxLength, [string]$Suffix = '...')
    if ([string]::IsNullOrEmpty($InputString)) { return '' }
    if ($InputString.Length -le $MaxLength) { return $InputString }
    return $InputString.Substring(0, $MaxLength) + $Suffix
}

function Clean-JsonString {
    param([string]$str)
    if ([string]::IsNullOrEmpty($str)) { return '' }
    $clean = $str -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
    return $clean.Trim()
}

function Sanitize-AiNarrativeText {
    param([string]$Text, [int]$MaxLength = 2000)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $clean = [string]$Text
    $clean = $clean -replace '(?is)<style[^>]*>.*?</style>', ' '
    $clean = $clean -replace '(?is)<script[^>]*>.*?</script>', ' '
    $clean = $clean -replace '(?is)<[^>]+>', ' '
    $clean = $clean -replace '(?is)\b[a-z][a-z0-9\s\.#:_\-]*\{[^{}]*\}', ' '
    $clean = $clean | Clean-JsonString
    $clean = $clean -replace '(?im)^\s*(corrected\s+ai\s+analysis|ai\s+analysis|medium\s+confidence|high\s+confidence|low\s+confidence)\s*:?\s*', ''
    $clean = $clean -replace '[\r\n]+', ' '
    $clean = $clean -replace '\s{2,}', ' '
    $clean = $clean.Trim(' ', '.', ',', ';', ':')
    if ($clean.Length -gt $MaxLength) { $clean = $clean.Substring(0, $MaxLength).Trim() + '...' }
    return $clean
}

function Get-SNValue {
    param([object]$Prop)
    if ($null -eq $Prop) { return '' }
    if ($Prop -is [array] -and $Prop.Count -gt 0) { return Get-SNValue $Prop[0] }
    if ($Prop -is [string] -or $Prop -is [int] -or $Prop -is [long]) { return [string]$Prop }
    if ($Prop.PSObject) {
        if ($Prop.PSObject.Properties['number'] -and $Prop.number) { return Get-SNValue $Prop.number }
        if ($Prop.PSObject.Properties['sys_id'] -and $Prop.sys_id) { return Get-SNValue $Prop.sys_id }
        if ($Prop.PSObject.Properties['display_value'] -and $Prop.display_value) { return [string]$Prop.display_value }
        if ($Prop.PSObject.Properties['value'] -and $Prop.value) { return [string]$Prop.value }
        if ($Prop.PSObject.Properties['result'] -and $Prop.result) { return Get-SNValue $Prop.result }
    }
    return [string]$Prop
}


# ===================================================================================
# SECTION 2: CONFIGURATION & ENVIRONMENT INITIALIZATION
# ===================================================================================

Write-Step 'Loading Automation variables...' 'Yellow'

$cfg = @{
    StorageAccountName              = Get-AutomationVariable -Name 'Incidents_analyzer_StorageAccountName'
    ResourceGroupName               = Get-AutomationVariable -Name 'Incidents_analyzer_ResourceGroupName'
    PromptContainerName             = Get-AutomationVariable -Name 'Incidents_analyzer_PromptTemplateContainerName'
    SubscriptionId                  = Get-AutomationVariable -Name 'Incidents_analyzer_SubscriptionId'
    ServiceNowIncidentsClientID     = Get-AutomationVariable -Name 'ServiceNowIncidentsClientID'
    ServiceNowIncidentsClientSecret = Get-AutomationVariable -Name 'ServiceNowIncidentsClientSecret'
    ServiceNowIncidentsScope        = Get-AutomationVariable -Name 'ServiceNowIncidentsScope'
    TokenUrl                        = Get-AutomationVariable -Name 'TokenUrl'
    AzureOpenAIBaseUrl              = Get-AutomationVariable -Name 'AzureOpenAIBaseUrl'
    AzureOpenAIDeployment           = Get-AutomationVariable -Name 'AzureOpenAIDeployment'
    AzureOpenAIApiKey               = Get-AutomationVariable -Name 'AzureOpenAIApiKey'
    AzureOpenAIApiVersion           = Get-AutomationVariable -Name 'AzureOpenAIApiVersion'
}

function Get-OptVar { 
    param($n, $d) 
    try { 
        $v = Get-AutomationVariable -Name $n -ErrorAction Stop
        if ($null -eq $v -or $v -eq '') { return $d } else { return $v } 
    } catch { return $d } 
}

$BusinessServiceId = Get-OptVar 'PT_BusinessServiceId' 'a1de2ff2db8f50108062531dd3961911'
$ServiceOfferingId = Get-OptVar 'PT_ServiceOfferingId' 'fcb18407dbcf50108062531dd39619c4'
$TableName         = Get-OptVar 'PT_TrendTableName'    'IncidentsCategoryStats'
if ($LookbackDays -le 0) { $LookbackDays = [int](Get-OptVar 'PT_TrendLookbackDays' 7) }

Write-Output "Lookback days  : $LookbackDays"
Write-Output "Table          : $TableName"
Write-Output "Storage account: $($cfg.StorageAccountName)"
Write-Output "Subscription   : $($cfg.SubscriptionId)"

Write-Step 'Connecting to Azure with managed identity...' 'Yellow'
Disable-AzContextAutosave -Scope Process | Out-Null
$null = Connect-AzAccount -Identity -ErrorAction Stop
$null = Set-AzContext -Subscription $cfg.SubscriptionId -ErrorAction Stop

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $cfg.ResourceGroupName -Name $cfg.StorageAccountName)[0].Value
$saCtx      = New-AzStorageContext -StorageAccountName $cfg.StorageAccountName -StorageAccountKey $storageKey

if (-not (Get-Module -ListAvailable -Name AzTable)) {
    throw "AzTable module is not installed in this Automation Account. Please add it via the Gallery."
}
Import-Module AzTable -Force
$tbl        = Get-AzStorageTable -Name $TableName -Context $saCtx -ErrorAction Stop
$cloudTable = $tbl.CloudTable


# ===================================================================================
# SECTION 3: PROMPT TEMPLATES & SYSTEM PROMPT CONSTRUCTION
# ===================================================================================

Write-Step "Loading prompt templates from container '$($cfg.PromptContainerName)'..." 'Yellow'

function Read-TemplateBlob {
    param([string]$BlobName)
    $tmp = Join-Path $env:TEMP ("rb_" + [guid]::NewGuid().ToString('N') + "_" + $BlobName)
    Get-AzStorageBlobContent -Container $cfg.PromptContainerName -Blob $BlobName -Destination $tmp -Context $saCtx -Force -ErrorAction Stop | Out-Null
    $txt = Get-Content -Path $tmp -Raw -Encoding UTF8
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $txt
}

$catTemplate    = Read-TemplateBlob -BlobName 'TicketCategorisation_ProductivityTools.md'
$envTemplate    = Read-TemplateBlob -BlobName 'EnvironmentContext_ProductivityTools.md'
$subCatTemplate = Read-TemplateBlob -BlobName 'TrendSubCategorisation_ProductivityTools.md'
$prcTemplate    = Read-TemplateBlob -BlobName 'PossibleRootCause_ProductivityTools.md'

$outputFormatInstruction = @'


## REQUIRED OUTPUT FORMAT (STRICT)

You MUST end your response with exactly these eight labeled lines, in this order, each on its own line, with no markdown, headers, or extra commentary after them:

Primary Category: <one of the bold category names defined above, or "Excluded">
Sub-symptom: <EXACT bold header label from the Sub-symptom reference above for the chosen category — e.g. "Sync Issues", "Licensing Issues". Do NOT invent or paraphrase.>
Possible Root Cause: <EXACT bold label from the chosen product table in the Possible Root Cause reference above. Copy verbatim. If no label fits, write "Unknown".>
Issue: <One fresh sentence, in your own words, stating what the user reported and its impact. Do NOT copy the short_description verbatim.>
Root Cause Narrative: <1-2 fresh sentences, in your own words, on what the work notes show actually caused THIS ticket's issue. If not conclusively proven, say so plainly instead of guessing.>
Resolution: <1-2 sentences on the exact remediation steps performed and the outcome, drawn from work/close notes. If not documented, write "Not documented in work notes.">
Evidence: <The strongest supporting quote(s)/phrases from the work or close notes backing up the above. If none captured, write "Not documented in work notes.">
AI Analysis: <A detailed 3-5 sentence paragraph synthesizing THIS specific ticket's details. Explain what problem occurred, why it fits the chosen Primary Category and Sub-symptom based on the work notes, and how the fix resolved it. Do NOT write boilerplate disclaimers.>

Rules:
- Each label must appear verbatim followed by a colon.
- Use plain ASCII. No bullets, asterisks, or quotation marks around the values.
- Sub-symptom MUST be an exact bold header from the Sub-symptom catalog (not a bullet description).
- Possible Root Cause MUST be an exact bold label from the Possible Root Cause catalog (not a sentence).
- If unknown, write "Unknown".
- Keep each value on a single line, except Root Cause Narrative/Resolution/Evidence/AI Analysis which should be comprehensive 1-5 sentence explanations.
'@

$systemPrompt = Clean-JsonString ($catTemplate + "`n`n" + $envTemplate + "`n`n" +
    "## REFERENCE: Sub-symptom Labels`n" + $subCatTemplate + "`n`n" +
    "## REFERENCE: Possible Root Cause Labels`n" + $prcTemplate +
    $outputFormatInstruction)


# ===================================================================================
# SECTION 4: DE-DUPLICATION & EXISTING ROW CACHE
# ===================================================================================

$existingByPartition = @{}

function Get-ExistingRowKeys {
    param([string]$Partition)
    if ($existingByPartition.ContainsKey($Partition)) { return $existingByPartition[$Partition] }
    
    $map = @{}
    try {
        $rows = Get-AzTableRow -Table $cloudTable -PartitionKey $Partition -ErrorAction Stop
        foreach ($r in @($rows)) { 
            if ($r.RowKey) { 
                $aiVal = if ($r.AIAnalysis) { [string]$r.AIAnalysis } else { '' }
                $map[[string]$r.RowKey] = $aiVal 
            } 
        }
    } catch {
        Write-Warning "Could not load existing keys for ${Partition}: $($_.Exception.Message)"
    }
    $existingByPartition[$Partition] = $map
    return $map
}

function Get-ServiceNowToken {
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $cfg.ServiceNowIncidentsClientID
        client_secret = $cfg.ServiceNowIncidentsClientSecret
        scope         = $cfg.ServiceNowIncidentsScope
    }
    (Invoke-RestMethod -Method Post -Uri $cfg.TokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded').access_token
}

function Get-IncidentsForDay {
    param([string]$Token, [DateTime]$DayUtc)
    $startStr = $DayUtc.ToString('yyyy-MM-dd 00:00:00')
    $endStr   = $DayUtc.ToString('yyyy-MM-dd 23:59:59')
    $query = "business_service=$BusinessServiceId" +
             "^service_offering=$ServiceOfferingId" +
             "^stateIN6,7" +
             "^resolved_at>=$startStr" +
             "^resolved_at<=$endStr"
    $url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$query&sysparm_display_value=true&sysparm_limit=1000"
    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
    try {
        $resp = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -TimeoutSec 120
        $res  = $resp.result
        if ($res -is [array]) { return ,$res } else { return ,@($res) }
    } catch {
        Write-Warning "ServiceNow fetch failed for ${startStr}: $($_.Exception.Message)"
        return ,@()
    }
}


# ===================================================================================
# SECTION 5: AI CATEGORIZATION & PARSING ENGINE
# ===================================================================================

function Invoke-Categorize {
    param([object]$Incident)

    $num = Get-SNValue $Incident.number
    if (-not $num) { $num = Get-SNValue $Incident.sys_id }

    $workNotesRaw  = Clean-JsonString (Get-SNValue $Incident.work_notes)
    if ($workNotesRaw.Length -gt 6000) { $workNotesRaw = $workNotesRaw.Substring(0, 6000) + '... [truncated]' }
    
    $closeNotesRaw = Clean-JsonString (Get-SNValue $Incident.close_notes)
    if ($closeNotesRaw.Length -gt 2000) { $closeNotesRaw = $closeNotesRaw.Substring(0, 2000) + '... [truncated]' }
    
    $userPayloadObj = [ordered]@{
        IncidentNumber           = [string]$num
        'User Description'        = Clean-JsonString (Get-SNValue $Incident.description)
        'User Short Description'  = Clean-JsonString (Get-SNValue $Incident.short_description)
        'User Work Notes'        = $workNotesRaw
        'Close Notes'            = $closeNotesRaw
        'Close Code'             = Clean-JsonString (Get-SNValue $Incident.close_code)
        'Incident Opened At'     = Clean-JsonString (Get-SNValue $Incident.opened_at)
        'Incident Resolved At'   = Clean-JsonString (Get-SNValue $Incident.resolved_at)
    }

    $userContentString = $userPayloadObj | ConvertTo-Json -Depth 5 -Compress

    $bodyObj = [ordered]@{
        messages = @(
            @{ role = 'system'; content = $systemPrompt },
            @{ role = 'user';   content = $userContentString }
        )
        max_completion_tokens = 1600
    }
    
    $bodyJson = $bodyObj | ConvertTo-Json -Depth 10
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

    $url = "$($cfg.AzureOpenAIBaseUrl)/openai/deployments/$($cfg.AzureOpenAIDeployment)/chat/completions?api-version=$($cfg.AzureOpenAIApiVersion)"
    $headers = @{ 'api-key' = $cfg.AzureOpenAIApiKey }
    
    try {
        $resp = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $bodyBytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 180
        return $resp.choices[0].message.content
    } catch {
        $errDetails = $_.ErrorDetails.Message
        if (-not $errDetails) { $errDetails = $_.Exception.Message }
        throw "Azure OpenAI Call Failed: $errDetails"
    }
}

function Get-FieldFromResponse {
    param([string]$Text, [string[]]$Labels, [string[]]$StopLabels)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $labelAlt = ($Labels    | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $stopAlt  = ($StopLabels | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $pattern = "(?im)^\s*\*{0,2}(?:$labelAlt)\*{0,2}\s*[:\-]\s*(.+?)\s*(?=\r?\n\s*\*{0,2}(?:$stopAlt)\*{0,2}\s*[:\-]|\Z)"
    if ($Text -match $pattern) {
        $val = $matches[1] -replace '\r?\n', ' '
        $val = $val.Trim() -replace '\*+', '' -replace '^"(.+)"$', '$1'
        return $val.Trim()
    }
    return ''
}

$AllFieldLabels = @(
    'Primary Category', 'Sub-symptom', 'Subcategory', 'Sub symptom',
    'Possible Root Cause', 'Root Cause', 'Root Cause Narrative', 'AI Analysis', 'Analysis',
    'Exclusion Reason', 'Confidence', 'Reasoning', 'Key Evidence', 'Issue', 'Resolution', 'Evidence'
)

function Get-StructuredFields {
    param([string]$Text)
    return [PSCustomObject]@{
        Category           = (Get-FieldFromResponse -Text $Text -Labels @('Primary Category') -StopLabels $AllFieldLabels)
        Subcategory        = (Get-FieldFromResponse -Text $Text -Labels @('Sub-symptom','Subcategory','Sub symptom') -StopLabels $AllFieldLabels)
        RootCause          = (Get-FieldFromResponse -Text $Text -Labels @('Possible Root Cause','Root Cause') -StopLabels $AllFieldLabels)
        Confidence         = (Get-FieldFromResponse -Text $Text -Labels @('Confidence','Confidence Level') -StopLabels $AllFieldLabels)
        Issue              = (Get-FieldFromResponse -Text $Text -Labels @('Issue') -StopLabels $AllFieldLabels)
        RootCauseNarrative = (Get-FieldFromResponse -Text $Text -Labels @('Root Cause Narrative') -StopLabels $AllFieldLabels)
        Resolution         = (Get-FieldFromResponse -Text $Text -Labels @('Resolution') -StopLabels $AllFieldLabels)
        Evidence           = (Get-FieldFromResponse -Text $Text -Labels @('Evidence') -StopLabels $AllFieldLabels)
        Analysis           = (Get-FieldFromResponse -Text $Text -Labels @('AI Analysis','Analysis') -StopLabels $AllFieldLabels)
    }
}

function New-TicketDataAnalysisText {
    param(
        [string]$Category,
        [string]$Subcategory,
        [string]$RootCause,
        [string]$Issue,
        [string]$RootCauseNarrative,
        [string]$Resolution,
        [string]$Evidence
    )

    $cleanIssue = if ([string]::IsNullOrWhiteSpace($Issue)) { "The user reported an incident regarding $Subcategory." } else { $Issue }
    $cleanRC    = if ([string]::IsNullOrWhiteSpace($RootCauseNarrative)) { "Investigation confirmed $RootCause as the root cause." } else { $RootCauseNarrative }
    $cleanRes   = if ([string]::IsNullOrWhiteSpace($Resolution)) { "Engineering implemented standard remediation steps." } else { $Resolution }
    $cleanEv    = if ([string]::IsNullOrWhiteSpace($Evidence)) { "Troubleshooting notes support this classification." } else { "Evidence noted: $Evidence" }

    return "$cleanIssue $cleanRC $cleanRes $cleanEv"
}

function Get-YearWeekFromDate {
    param([DateTime]$Date)
    $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
    $wn  = $cal.GetWeekOfYear($Date, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
    $isoYear = $Date.Year
    if ($Date.Month -eq 1 -and $wn -ge 52) {
        $isoYear--
    } elseif ($Date.Month -eq 12 -and $wn -eq 1) {
        $isoYear++
    }
    return [PSCustomObject]@{
        Year       = $isoYear
        WeekNumber = $wn
        YearWeek   = ('{0:D4}-W{1:D2}' -f $isoYear, $wn)
    }
}

function Test-NeedsAiReprocess {
    param([string]$ExistingAnalysis)

    if ([string]::IsNullOrWhiteSpace($ExistingAnalysis)) { return $true }

    $text = [string]$ExistingAnalysis

    # Hard failures: CSS/HTML leakage or malformed injected content.
    $badMarkupPattern = '(?is)<style|</?[a-z][^>]*>|\{\s*text-decoration\s*:|\btr\s+th\b|\bcolor\s*:\s*#[0-9a-fA-F]{3,6}'
    if ($text -match $badMarkupPattern) { return $true }

    # Required sections in strict format.
    if ($text -notmatch '(?im)^\s*Problem\s*:') { return $true }
    if ($text -notmatch '(?im)^\s*Root\s*Cause\s*:') { return $true }
    if ($text -notmatch '(?im)^\s*Resolution\s*:') { return $true }
    if ($text -notmatch '(?im)^\s*Evidence\s*:') { return $true }
    if ($text -notmatch '(?im)^\s*AI\s*Analysis\s*\(') { return $true }

    function Get-SectionValue {
        param([string]$Source, [string[]]$Labels, [string[]]$Stops)
        $lhs = ($Labels | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $rhs = ($Stops | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $m = [regex]::Match($Source, "(?ims)^\s*(?:$lhs)\s*:\s*(.*?)\s*(?=\n\s*(?:$rhs)\s*:|\z)")
        if (-not $m.Success) { return '' }
        return ($m.Groups[1].Value -replace '\s+', ' ').Trim(' ', '.', ',', ';', ':')
    }

    function Is-PlaceholderText {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
        $v = $Value.Trim()
        if ($v -match '^(not documented|unknown|n/?a|nil|null|none|na)$') { return $true }
        if ($v -match '^(issue|root cause|resolution|evidence|ai analysis)\s*:?$') { return $true }
        return $false
    }

    $problemText = Get-SectionValue -Source $text -Labels @('Problem','Issue') -Stops @('Root Cause','Resolution','Evidence','AI Analysis')
    $rootText    = Get-SectionValue -Source $text -Labels @('Root Cause') -Stops @('Resolution','Evidence','AI Analysis')
    $resText     = Get-SectionValue -Source $text -Labels @('Resolution') -Stops @('Evidence','AI Analysis')
    $evText      = Get-SectionValue -Source $text -Labels @('Evidence') -Stops @('AI Analysis')
    $aiMatch     = [regex]::Match($text, '(?ims)^\s*AI\s*Analysis\s*(?:\([^)]*\))?\s*:\s*(.*?)\s*$')
    $aiText      = if ($aiMatch.Success) { ($aiMatch.Groups[1].Value -replace '\s+', ' ').Trim(' ', '.', ',', ';', ':') } else { '' }

    if (Is-PlaceholderText -Value $problemText) { return $true }
    if (Is-PlaceholderText -Value $rootText) { return $true }
    if (Is-PlaceholderText -Value $resText) { return $true }
    if (Is-PlaceholderText -Value $evText) { return $true }
    if (Is-PlaceholderText -Value $aiText) { return $true }
    if ($aiText.Length -lt 60) { return $true }

    return $false
}


# ===================================================================================
# SECTION 6: MAIN BACKFILL PROCESSING LOOP
# ===================================================================================

Write-Step 'Fetching ServiceNow token...' 'Yellow'
$snToken = Get-ServiceNowToken

$today = (Get-Date).ToUniversalTime().Date
$summary = @{}
$affectedWeeks = [System.Collections.Generic.HashSet[string]]::new()
$totalFetched = 0; $totalSaved = 0; $totalErrors = 0; $totalSkipped = 0

for ($i = 0; $i -lt $LookbackDays; $i++) {
    $day = $today.AddDays(-$i)
    $key = $day.ToString('yyyy-MM-dd')
    Write-Step "Day $($i + 1)/$LookbackDays - $key" 'Cyan'

    $incidents = @(Get-IncidentsForDay -Token $snToken -DayUtc $day)
    Write-Output "  Fetched $($incidents.Count) incidents."
    $summary[$key] = @{ fetched = $incidents.Count; saved = 0; errors = 0; skipped = 0 }

    if ($incidents.Count -eq 0) { continue }
    if ($MaxPerDay -gt 0 -and $incidents.Count -gt $MaxPerDay) {
        $incidents = $incidents | Select-Object -First $MaxPerDay
    }

    foreach ($inc in $incidents) {
        try {
            $num = Get-SNValue $inc
            if (-not $num -or $num -eq '') { $num = Get-SNValue $inc.number }
            if (-not $num -or $num -eq '') { $num = Get-SNValue $inc.sys_id }

            if ([string]::IsNullOrWhiteSpace($num)) { 
                Write-Warning "  SKIPPED: Incident object missing valid 'number' or 'sys_id' property."
                $summary[$key].errors++
                continue 
            }

            $resolvedDt = $day
            $resAtStr   = Get-SNValue $inc.resolved_at
            if (-not [string]::IsNullOrWhiteSpace($resAtStr)) {
                [DateTime]$tmp = [DateTime]::MinValue
                if ([DateTime]::TryParse($resAtStr, [ref]$tmp)) { $resolvedDt = $tmp }
            }
            $yw = Get-YearWeekFromDate -Date $resolvedDt

            # Check if ticket already exists in Azure Table
            $existingMap = Get-ExistingRowKeys -Partition $yw.YearWeek
            if ($existingMap -and $existingMap.ContainsKey($num)) {
                $existingAnalysis = [string]$existingMap[$num]

                # Reprocess when existing entry is missing strict sections or contains malformed output.
                $needsReprocess = Test-NeedsAiReprocess -ExistingAnalysis $existingAnalysis

                if (-not $needsReprocess) {
                    # Row already has a proper AI Analysis - skip to save AI cost
                    $summary[$key].skipped++
                    continue
                } else {
                    Write-Output "  RE-PROCESSING ${num}: Existing AI Analysis is missing/invalid; updating from ServiceNow with strict format."
                }
            }

            # Call Azure OpenAI
            $aiText   = Invoke-Categorize -Incident $inc
            $fields   = Get-StructuredFields -Text $aiText
            $category = if ($fields.Category) { $fields.Category } else { 'Other / Miscellaneous' }
            $subcat   = $fields.Subcategory
            $root     = $fields.RootCause
            $anal     = $fields.Analysis
            $conf     = $fields.Confidence
            
            if ([string]::IsNullOrWhiteSpace($conf)) { $conf = 'Medium' }
            
            $issue = $fields.Issue
            if ([string]::IsNullOrWhiteSpace($issue)) {
                $sd = Get-SNValue $inc.short_description
                $issue = if (-not [string]::IsNullOrWhiteSpace($sd)) { $sd } else { 'Not documented.' }
            }
            
            $rootNarrative = $fields.RootCauseNarrative
            if ([string]::IsNullOrWhiteSpace($rootNarrative)) {
                $rootNarrative = if (-not [string]::IsNullOrWhiteSpace($root)) { "Root cause identified as $root." } else { "Root cause not documented in work notes." }
            }
            
            $resolution = $fields.Resolution
            if ([string]::IsNullOrWhiteSpace($resolution)) { $resolution = 'Not documented in work notes.' }
            
            $evidence = $fields.Evidence
            if ([string]::IsNullOrWhiteSpace($evidence)) { $evidence = 'Not documented in work notes.' }

            if ([string]::IsNullOrWhiteSpace($anal) -or $anal.Length -lt 120) {
                $anal = New-TicketDataAnalysisText -Category $category -Subcategory $subcat -RootCause $root -Issue $issue -RootCauseNarrative $rootNarrative -Resolution $resolution -Evidence $evidence
            }
            
            $issue         = Sanitize-AiNarrativeText -Text $issue -MaxLength 500
            $rootNarrative = Sanitize-AiNarrativeText -Text $rootNarrative -MaxLength 800
            $resolution    = Sanitize-AiNarrativeText -Text $resolution -MaxLength 800
            $evidence      = Sanitize-AiNarrativeText -Text $evidence -MaxLength 800
            $subcat        = Get-SafeSubstring -InputString $subcat -MaxLength 200 -Suffix ''
            $root          = Get-SafeSubstring -InputString $root -MaxLength 1000 -Suffix '...'
            $anal          = Sanitize-AiNarrativeText -Text $anal -MaxLength 1800

            $structuredAnalysis = "Problem: $issue`n" +
                "Root Cause: $rootNarrative`n" +
                "Resolution: $resolution`n" +
                "Evidence: $evidence`n" +
                "AI Analysis ($conf Confidence): $anal"
                
            $structuredAnalysis = Get-SafeSubstring -InputString $structuredAnalysis -MaxLength 4000 -Suffix '...'

            $props = @{
                'Category'       = [string]$category
                'Subcategory'    = [string]$subcat
                'RootCause'      = [string]$root
                'AIAnalysis'     = [string]$structuredAnalysis
                'Confidence'     = [string]$conf
                'Date'           = [string]$resolvedDt.ToString('yyyy-MM-dd')
                'YearWeek'       = [string]$yw.YearWeek
                'Year'           = [int]$yw.Year
                'WeekNumber'     = [int]$yw.WeekNumber
                'ReportBlobName' = 'incremental-runbook'
            }

            Add-AzTableRow -Table $cloudTable -PartitionKey ([string]$yw.YearWeek) -RowKey ([string]$num) -Property $props -UpdateExisting | Out-Null

            if ($existingMap) { $existingMap[[string]$num] = $structuredAnalysis }
            [void]$affectedWeeks.Add([string]$yw.YearWeek)
            Write-Output ("  OK   {0,-15} {1,-9} {2}" -f $num, $yw.YearWeek, $category)
            $summary[$key].saved++
        } catch {
            Write-Warning "  FAIL $num (Line $($_.InvocationInfo.ScriptLineNumber)): $($_.Exception.Message)"
            $summary[$key].errors++
        }
    }
}


# ===================================================================================
# SECTION 7: EXECUTION SUMMARY REPORTING
# ===================================================================================

Write-Output ''
Write-Step '=== Incremental backfill summary ===' 'Magenta'
$summary.Keys | Sort-Object | ForEach-Object {
    $s = $summary[$_]
    Write-Output ("  {0}  fetched={1,3}  saved={2,3}  skipped={3,3}  errors={4,3}" -f $_, $s.fetched, $s.saved, $s.skipped, $s.errors)
    $totalFetched += $s.fetched; $totalSaved += $s.saved; $totalSkipped += $s.skipped; $totalErrors += $s.errors
}
Write-Output ("  -----------------------------------------------------------------")
Write-Output ("  TOTAL       fetched={0,3}  saved={1,3}  skipped={2,3}  errors={3,3}" -f $totalFetched, $totalSaved, $totalSkipped, $totalErrors)
Write-Output ''
Write-Output "Rows newly written/updated: $totalSaved (skipped $totalSkipped valid entries in table)"


# ===================================================================================
# SECTION 8: AFFECTED DASHBOARD & INDEX REGENERATION
# ===================================================================================

if ($totalSaved -gt 0) {
    Write-Output ''
    Write-Step '=== Regenerating dashboards for affected weeks ===' 'Cyan'
    try {
        $affectedWeekList = @($affectedWeeks)

        if ($affectedWeekList.Count -eq 0) {
            Write-Output 'No affected weeks identified.'
        } else {
            Write-Output "Affected week(s): $($affectedWeekList -join ', ')"

            function HtmlEsc { param([string]$s) if ($null -eq $s) { return '' } [System.Net.WebUtility]::HtmlEncode($s) }
            
            $catColors = @{
                'Microsoft OneDrive Issues'                 = '#005a9e'
                'Microsoft Excel Issues'                    = '#107c41'
                'Microsoft Word Issues'                     = '#2b579a'
                'Microsoft PowerPoint Issues'               = '#b7472a'
                'Microsoft 365 Copilot Issues'              = '#464feb'
                'Microsoft 365 Apps for Enterprise Issues'  = '#0078d4'
                'Microsoft OneNote Issues'                  = '#7719aa'
                'Microsoft Forms Issues'                    = '#6264a7'
                'Microsoft Loop Issues'                     = '#00bcf2'
                'Microsoft Project Issues'                  = '#ba141a'
                'Microsoft 365 Planner / To Do Issues'      = '#0078d4'
                'Shared File Service (Share Drives) Issues' = '#ff9800'
                'Google Workspace Issues'                   = '#4285f4'
                'Smartsheet Issues'                         = '#00a868'
                'Rejoin / Account Lifecycle Access Issues'  = '#8bc34a'
                'How Do I / User Education'                 = '#f39c12'
                'Other / Miscellaneous'                     = '#78909c'
                'Excluded'                                  = '#90a4ae'
            }
            function ColorFor { param([string]$c) if ($catColors.ContainsKey($c)) { $catColors[$c] } else { '#5b6abf' } }

            foreach ($weekKey in $affectedWeekList) {
                try {
                    $sas = New-AzStorageTableSASToken -Name $TableName -Permission 'r' `
                        -ExpiryTime (Get-Date).AddMinutes(20) -Protocol HttpsOnly -Context $saCtx
                    $tableUri = "https://$($cfg.StorageAccountName).table.core.windows.net/$TableName()" +
                                "?`$filter=PartitionKey eq '$weekKey'&$sas"
                    $tableRows = @()
                    $nxtUri = $tableUri
                    while ($nxtUri) {
                        $r = Invoke-WebRequest -Uri $nxtUri -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
                        $tableRows += ($r.Content | ConvertFrom-Json).value
                        $npk = $r.Headers['x-ms-continuation-NextPartitionKey']
                        $nrk = $r.Headers['x-ms-continuation-NextRowKey']
                        if ($npk) {
                            $nxtUri = $tableUri + '&NextPartitionKey=' + [Uri]::EscapeDataString([string]$npk)
                            if ($nrk) { $nxtUri += '&NextRowKey=' + [Uri]::EscapeDataString([string]$nrk) }
                        } else { $nxtUri = $null }
                    }

                    if ($tableRows.Count -eq 0) { Write-Warning "  $weekKey - no rows, skipping"; continue }

                    $total    = $tableRows.Count
                    $excluded = ($tableRows | Where-Object { $_.Category -eq 'Excluded' }).Count
                    $inScope  = $total - $excluded
                    $byCat    = $tableRows | Group-Object Category | Sort-Object Count -Descending
                    $topCat   = if ($byCat.Count -gt 0) { $byCat[0].Name } else { 'N/A' }

                    $istStart = ''; $istEnd = ''
                    if ($weekKey -match '^(?<y>\d{4})-W(?<w>\d{1,2})$') {
                        $wy = [int]$Matches['y']; $ww = [int]$Matches['w']
                        $jan4    = [DateTime]::new($wy, 1, 4)
                        $jan4Mon = $jan4.AddDays(-(([int]$jan4.DayOfWeek + 6) % 7))
                        $monDt   = $jan4Mon.AddDays(($ww - 1) * 7)
                        $sunDt   = $monDt.AddDays(6)
                        $ist     = [TimeSpan]::FromHours(5.5)
                        $istStart = ($monDt + $ist).ToString('d MMM')
                        $istEnd   = ($sunDt  + $ist).ToString('d MMM yyyy')
                    }

                    $catRows = ($byCat | ForEach-Object {
                        $pct = [math]::Round(($_.Count / $total) * 100, 1)
                        $clr = ColorFor $_.Name
                        "<tr><td><span style='display:inline-block;width:10px;height:10px;border-radius:50%;background:$clr;margin-right:6px'></span>$(HtmlEsc $_.Name)</td><td class='num'>$($_.Count)</td><td class='num'>$pct%</td></tr>"
                    }) -join "`n"

                    $detRows = ($tableRows | Sort-Object Date -Descending | ForEach-Object {
                        $clr = ColorFor $_.Category
                        $ai  = if ($_.AIAnalysis) { "<div class='ai'>$(HtmlEsc $_.AIAnalysis)</div>" } else { '' }
                        "<tr><td><a href='https://intel.service-now.com/nav_to.do?uri=incident.do?sysparm_query=number=$(HtmlEsc $_.RowKey)' target='_blank'>$(HtmlEsc $_.RowKey)</a></td><td>$(HtmlEsc $_.Date)</td><td><span class='badge' style='background:$clr'>$(HtmlEsc $_.Category)</span></td><td>$(HtmlEsc $_.Subcategory)</td><td>$(HtmlEsc $_.RootCause)</td><td class='ai-col'>$ai</td></tr>"
                    }) -join "`n"

                    $html = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Productivity Tools - $weekKey</title>
<style>body{margin:0;background:#f0f2f5;font-family:'Segoe UI',sans-serif;font-size:13px;}
.hdr{background:#0071c5;color:#fff;padding:16px 28px;display:flex;align-items:center;justify-content:space-between;}
.hdr h1{margin:0;font-size:20px;font-weight:400;}.hdr .meta{font-size:12px;opacity:.85;}
.wrap{padding:24px 28px;}.kpis{display:flex;gap:14px;margin-bottom:22px;flex-wrap:wrap;}
.kpi{background:#fff;border-radius:8px;padding:16px 22px;flex:1;min-width:130px;box-shadow:0 2px 6px rgba(0,0,0,.08);}
.kpi .v{font-size:30px;font-weight:700;color:#0071c5;}.kpi .l{font-size:11px;color:#666;text-transform:uppercase;letter-spacing:.7px;margin-top:3px;}
.card{background:#fff;border-radius:8px;box-shadow:0 2px 6px rgba(0,0,0,.08);margin-bottom:22px;overflow:hidden;}
.card-h{padding:13px 20px;border-bottom:1px solid #eee;font-weight:600;font-size:14px;color:#333;}
table{width:100%;border-collapse:collapse;}th{background:#f8f9fa;padding:9px 13px;text-align:left;font-size:11px;letter-spacing:.5px;text-transform:uppercase;color:#555;border-bottom:2px solid #dee2e6;}
td{padding:9px 13px;border-bottom:1px solid #f0f0f0;vertical-align:top;}tr:hover td{background:#fafbfc;}
.num{text-align:right;}.badge{color:#fff;padding:2px 8px;border-radius:12px;font-size:11px;white-space:nowrap;}
a{color:#0071c5;text-decoration:none;font-weight:600;}.ai-col{max-width:380px;}.ai{font-size:12px;color:#444;line-height:1.5;}</style></head><body>
<div class="hdr"><h1>Productivity Tools - $weekKey</h1>
  <div class="meta">$istStart - $istEnd | Updated $(Get-Date -Format 'dd MMM yyyy HH:mm') UTC</div></div>
<div class="wrap">
  <div class="kpis">
    <div class="kpi"><div class="v">$total</div><div class="l">Total</div></div>
    <div class="kpi"><div class="v">$inScope</div><div class="l">In-Scope</div></div>
    <div class="kpi"><div class="v">$excluded</div><div class="l">Excluded</div></div>
    <div class="kpi"><div class="v" style="font-size:15px">$(HtmlEsc $topCat)</div><div class="l">Top Category</div></div>
  </div>
  <div class="card"><div class="card-h">Category Breakdown</div>
    <table><thead><tr><th>Category</th><th class="num">Count</th><th class="num">%</th></tr></thead><tbody>$catRows</tbody></table></div>
  <div class="card"><div class="card-h">Incident Details ($total)</div>
    <table><thead><tr><th>Incident</th><th>Date</th><th>Category</th><th>Subcategory</th><th>Root Cause</th><th>AI Analysis</th></tr></thead><tbody>$detRows</tbody></table></div>
</div></body></html>
"@

                    $blobName = "ProductivityTools_Weekly_Report_$weekKey.html"
                    $tmpFile  = [System.IO.Path]::GetTempFileName()
                    try {
                        Set-Content -Path $tmpFile -Value $html -Encoding UTF8
                        Set-AzStorageBlobContent -File $tmpFile -Container 'results' -Blob $blobName `
                            -Context $saCtx -Properties @{ ContentType = 'text/html; charset=utf-8' } -Force | Out-Null
                        Write-Output "  Uploaded $blobName ($total incidents)"
                    } finally {
                        if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
                    }
                } catch {
                    Write-Warning "  Failed dashboard for ${weekKey}: $($_.Exception.Message)"
                }
            }

            try {
                $blobs = Get-AzStorageBlob -Container 'results' -Context $saCtx | Where-Object { $_.Name -like '*.html' }
                $reports = @(); $runs = @{}
                foreach ($b in $blobs) {
                    if ($b.Name -notmatch '(\d{4})-W(\d{2})') { continue }
                    $wk  = "$($matches[1])-W$($matches[2])"; $lbl = "WW$($matches[2]) $($matches[1])"
                    $entry = [ordered]@{ week_label=$lbl; run_id=$wk; generated_at=$b.LastModified.UtcDateTime.ToString('o'); blob=$b.Name; size_kb=[math]::Round($b.Length/1KB,1) }
                    $reports += [pscustomobject]$entry
                    if (-not $runs.ContainsKey($wk)) { $runs[$wk] = [ordered]@{ week_label=$lbl; run_id=$wk; generated_at=$b.LastModified.UtcDateTime.ToString('o'); ticket_count=0; dashboard_blob=$null; strict_report_blob=$null } }
                    $rv = $runs[$wk]
                    if ($b.Name -match 'Trend_Analysis') { $rv.strict_report_blob = $b.Name }
                    else { $rv.dashboard_blob = $b.Name; $rv.generated_at = $b.LastModified.UtcDateTime.ToString('o') }
                }
                $idx = [ordered]@{ generated_at=(Get-Date).ToUniversalTime().ToString('o'); reports=@($reports|Sort-Object run_id -Descending); trends=@(); runs=@($runs.Values|Sort-Object {$_.run_id} -Descending) }
                $idxTmp = [System.IO.Path]::GetTempFileName()
                try {
                    $idx | ConvertTo-Json -Depth 5 | Out-File -FilePath $idxTmp -Encoding UTF8 -NoNewline
                    Set-AzStorageBlobContent -File $idxTmp -Container 'results' -Blob 'index.json' `
                        -Context $saCtx -Properties @{ ContentType = 'application/json' } -Force | Out-Null
                    Write-Output "  index.json updated ($($runs.Count) runs)"
                } finally {
                    if (Test-Path $idxTmp) { Remove-Item $idxTmp -Force -ErrorAction SilentlyContinue }
                }
            } catch {
                Write-Warning "  Failed to update index.json: $($_.Exception.Message)"
            }
        }
    } catch {
        Write-Warning "Dashboard regeneration failed: $($_.Exception.Message) - continuing..."
    }
} else {
    Write-Output 'No incidents saved in this run - skipping dashboard regeneration.'
}