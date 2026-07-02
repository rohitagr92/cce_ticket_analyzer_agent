<#
.SYNOPSIS
    Daily incremental backfill of IncidentsCategoryStats for the Trends + Ops Report
    dashboards. Designed to run unattended in Azure Automation.

.DESCRIPTION
    For each calendar day in the lookback window (default 2 days), this runbook:
      1. Queries ServiceNow for Productivity Tools incidents resolved that day
         (business_service + service_offering scope; state 6 or 7).
      2. Looks up which incident numbers are ALREADY stored in the IncidentsCategoryStats
         table for that YearWeek partition. Already-stored incidents are skipped, so no
         AI cost is incurred for tickets we have already categorized.
      3. For each NEW incident, calls Azure OpenAI to classify it and parses
         Primary Category / Sub-symptom / Possible Root Cause / AI Analysis.
      4. Writes one row per new incident to the table:
            PartitionKey = YearWeek of resolved_at  (e.g. "2026-W22")
            RowKey       = Incident number
            Category, Subcategory, RootCause, AIAnalysis,
            Date, YearWeek, Year, WeekNumber, ReportBlobName="incremental-runbook"

    Idempotent. Cheap. Safe to schedule daily.

.NOTES
    Required Automation Variables:
      ContentEng_StorageAccountName, ContentEng_ResourceGroupName,
      ContentEng_PromptTemplateContainerName, ContentEng_SubscriptionId,
      ContentEng_ServiceNowClientID, ContentEng_ServiceNowClientSecret, ContentEng_ServiceNowScope,
      TokenUrl, AzureOpenAIBaseUrl, AzureOpenAIDeployment, AzureOpenAIApiKey, AzureOpenAIApiVersion
    Optional Automation Variables (have hard-coded defaults):
      ContentEng_BusinessServiceId   (default f81e6ce5c3f98b901d9832d605013164)
      ContentEng_ServiceOfferingId   (default f81e6ce5c3f98b901d9832d605013164)
      ContentEng_TrendTableName      (default IncidentsCategoryStats)
      ContentEng_TrendLookbackDays   (default 2)
#>

[CmdletBinding()]
param(
    [int]$LookbackDays = 0,   # 0 = read from Automation variable ContentEng_TrendLookbackDays (default 2)
    [int]$MaxPerDay    = 0    # 0 = no cap
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Msg, [string]$Color = 'Cyan') Write-Output "[$(Get-Date -Format 'HH:mm:ss')] $Msg" }

# -------- Load Automation variables --------
Write-Step 'Loading Automation variables...' 'Yellow'
$cfg = @{
    StorageAccountName              = Get-AutomationVariable -Name 'ContentEng_StorageAccountName'
    ResourceGroupName               = Get-AutomationVariable -Name 'ContentEng_ResourceGroupName'
    PromptContainerName             = Get-AutomationVariable -Name 'ContentEng_PromptTemplateContainerName'
    SubscriptionId                  = Get-AutomationVariable -Name 'ContentEng_SubscriptionId'
    ContentEng_ServiceNowClientID     = Get-AutomationVariable -Name 'ContentEng_ServiceNowClientID'
    ContentEng_ServiceNowClientSecret = Get-AutomationVariable -Name 'ContentEng_ServiceNowClientSecret'
    ContentEng_ServiceNowScope        = Get-AutomationVariable -Name 'ContentEng_ServiceNowScope'
    TokenUrl                        = Get-AutomationVariable -Name 'ContentEng_TokenUrl'
    AzureOpenAIBaseUrl              = Get-AutomationVariable -Name 'ContentEng_AzureOpenAIBaseUrl'
    AzureOpenAIDeployment           = Get-AutomationVariable -Name 'ContentEng_AzureOpenAIDeployment'
    AzureOpenAIApiKey               = Get-AutomationVariable -Name 'ContentEng_AzureOpenAIApiKey'
    AzureOpenAIApiVersion           = Get-AutomationVariable -Name 'ContentEng_AzureOpenAIApiVersion'
}
function Get-OptVar { param($n, $d) try { $v = Get-AutomationVariable -Name $n -ErrorAction Stop; if ($null -eq $v -or $v -eq '') { return $d } else { return $v } } catch { return $d } }
$BusinessServiceId = Get-OptVar 'ContentEng_BusinessServiceId' 'a1de2ff2db8f50108062531dd3961911'
$ServiceOfferingId = Get-OptVar 'ContentEng_ServiceOfferingId' 'ce614555dbeb5c105447610ed39619f8'
$TableName         = Get-OptVar 'ContentEng_TrendTableName'    'IncidentsCategoryStats'
if ($LookbackDays -le 0) { $LookbackDays = [int](Get-OptVar 'ContentEng_TrendLookbackDays' 2) }

Write-Output "Lookback days  : $LookbackDays"
Write-Output "Table          : $TableName"
Write-Output "Storage account: $($cfg.StorageAccountName)"
Write-Output "Subscription   : $($cfg.SubscriptionId)"

# -------- Azure auth (managed identity) --------
Write-Step 'Connecting to Azure with managed identity...' 'Yellow'
Disable-AzContextAutosave -Scope Process | Out-Null
$null = Connect-AzAccount -Identity -ErrorAction Stop
$null = Set-AzContext -Subscription $cfg.SubscriptionId -ErrorAction Stop

# -------- Storage context --------
$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $cfg.ResourceGroupName -Name $cfg.StorageAccountName)[0].Value
$saCtx      = New-AzStorageContext -StorageAccountName $cfg.StorageAccountName -StorageAccountKey $storageKey

# -------- AzTable module --------
if (-not (Get-Module -ListAvailable -Name AzTable)) {
    throw "AzTable module is not installed in this Automation Account. Add it via Modules gallery (AzTable, scope: PowerShell 7.2)."
}
Import-Module AzTable -Force
$tbl        = Get-AzStorageTable -Name $TableName -Context $saCtx -ErrorAction Stop
$cloudTable = $tbl.CloudTable

# -------- Load prompt templates from blob --------
Write-Step "Loading prompt templates from container '$($cfg.PromptContainerName)'..." 'Yellow'
function Read-TemplateBlob {
    param([string]$BlobName)
    $tmp = Join-Path $env:TEMP ("rb_" + [guid]::NewGuid().ToString('N') + "_" + $BlobName)
    Get-AzStorageBlobContent -Container $cfg.PromptContainerName -Blob $BlobName -Destination $tmp -Context $saCtx -Force -ErrorAction Stop | Out-Null
    $txt = Get-Content -Path $tmp -Raw -Encoding UTF8
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $txt
}
$catTemplate    = Read-TemplateBlob -BlobName 'TicketCategorisation_ContentEngineering.md'
$envTemplate    = Read-TemplateBlob -BlobName 'EnvironmentContext_ContentEngineering.md'
$subCatTemplate = Read-TemplateBlob -BlobName 'TrendSubCategorisation_ContentEngineering.md'
$prcTemplate    = Read-TemplateBlob -BlobName 'PossibleRootCause_ContentEngineering.md'

$outputFormatInstruction = @'


## REQUIRED OUTPUT FORMAT (STRICT)

You MUST end your response with exactly these four labeled lines, in this order, each on its own line, with no markdown, headers, or extra commentary after them:

Primary Category: <one of the bold category names defined above, or "Excluded">
Sub-symptom: <EXACT bold header label from the Sub-symptom reference above for the chosen category — e.g. "Sync Issues", "Licensing Issues". Do NOT invent or paraphrase.>
Possible Root Cause: <EXACT bold label from the chosen product table in the Possible Root Cause reference above. Copy verbatim. If no label fits, write "Unknown".>
AI Analysis: <2-3 sentence summary: what happened, what was the root cause, and what fixed it. Be specific about technical details.>

Rules:
- Each label must appear verbatim followed by a colon.
- Use plain ASCII. No bullets, asterisks, or quotation marks around the values.
- Sub-symptom MUST be an exact bold header from the Sub-symptom catalog (not a bullet description).
- Possible Root Cause MUST be an exact bold label from the Possible Root Cause catalog (not a sentence).
- If unknown, write "Unknown".
- Keep each value on a single line.
'@
# Build system prompt from all 4 canonical templates — same enforcement as incident-analyzer-rb-prodtools.ps1.
# This ensures Sub-symptom and Possible Root Cause are always strict labels from the template catalogs,
# not free-form AI-generated text that would fail compliance validation.
$systemPrompt = $catTemplate + "`n`n" + $envTemplate + "`n`n" +
    "## REFERENCE: Sub-symptom Labels`n" + $subCatTemplate + "`n`n" +
    "## REFERENCE: Possible Root Cause Labels`n" + $prcTemplate +
    $outputFormatInstruction

# -------- Per-partition existing-key cache --------
$existingByPartition = @{}
function Get-ExistingRowKeys {
    param([string]$Partition)
    if ($existingByPartition.ContainsKey($Partition)) { return $existingByPartition[$Partition] }
    $set = [System.Collections.Generic.HashSet[string]]::new()
    try {
        $rows = Get-AzTableRow -Table $cloudTable -PartitionKey $Partition -ErrorAction Stop
        foreach ($r in @($rows)) { if ($r.RowKey) { [void]$set.Add([string]$r.RowKey) } }
    } catch {
        Write-Warning "Could not load existing keys for ${Partition}: $($_.Exception.Message)"
    }
    $existingByPartition[$Partition] = $set
    return $set
}

# -------- ServiceNow --------
function Get-ServiceNowToken {
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $cfg.ContentEng_ServiceNowClientID
        client_secret = $cfg.ContentEng_ServiceNowClientSecret
        scope         = $cfg.ContentEng_ServiceNowScope
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
        return @($resp.result)
    } catch {
        Write-Warning "ServiceNow fetch failed for ${startStr}: $($_.Exception.Message)"
        return @()
    }
}

# -------- Azure OpenAI categorization --------
function Invoke-Categorize {
    param([object]$Incident)
    $workNotesRaw = [string]$Incident.work_notes
    if ($workNotesRaw.Length -gt 6000) { $workNotesRaw = $workNotesRaw.Substring(0, 6000) + '... [truncated]' }
    $closeNotesRaw = [string]$Incident.close_notes
    if ($closeNotesRaw.Length -gt 2000) { $closeNotesRaw = $closeNotesRaw.Substring(0, 2000) + '... [truncated]' }
    $payload = [PSCustomObject]@{
        IncidentNumber           = $Incident.number
        'User Description'       = [string]$Incident.description
        'User Short Description' = [string]$Incident.short_description
        'User Work Notes'        = $workNotesRaw
        'Close Notes'            = $closeNotesRaw
        'Close Code'             = [string]$Incident.close_code
        'Incident Opened At'     = [string]$Incident.opened_at
        'Incident Resolved At'   = [string]$Incident.resolved_at
    }
    $incidentJson = $payload | ConvertTo-Json -Depth 4 -Compress
    $body = @{
        messages = @(
            @{ role = 'system'; content = $systemPrompt },
            @{ role = 'user';   content = $incidentJson }
        )
        max_completion_tokens = 1600
    } | ConvertTo-Json -Depth 10 -Compress
    $url = "$($cfg.AzureOpenAIBaseUrl)/openai/deployments/$($cfg.AzureOpenAIDeployment)/chat/completions?api-version=$($cfg.AzureOpenAIApiVersion)"
    $headers = @{ 'api-key' = $cfg.AzureOpenAIApiKey; 'Content-Type' = 'application/json' }
    $resp = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body -TimeoutSec 180
    return $resp.choices[0].message.content
}

# -------- Field parser --------
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
    'Possible Root Cause', 'Root Cause', 'AI Analysis', 'Analysis',
    'Exclusion Reason', 'Confidence', 'Reasoning', 'Key Evidence'
)
function Get-StructuredFields {
    param([string]$Text)
    return [PSCustomObject]@{
        Category    = (Get-FieldFromResponse -Text $Text -Labels @('Primary Category') -StopLabels $AllFieldLabels)
        Subcategory = (Get-FieldFromResponse -Text $Text -Labels @('Sub-symptom','Subcategory','Sub symptom') -StopLabels $AllFieldLabels)
        RootCause   = (Get-FieldFromResponse -Text $Text -Labels @('Possible Root Cause','Root Cause') -StopLabels $AllFieldLabels)
        Confidence  = (Get-FieldFromResponse -Text $Text -Labels @('Confidence','Confidence Level') -StopLabels $AllFieldLabels)
        Analysis    = (Get-FieldFromResponse -Text $Text -Labels @('AI Analysis','Analysis') -StopLabels $AllFieldLabels)
    }
}

function New-FallbackAnalysisText {
    param(
        [string]$Category,
        [string]$Subcategory,
        [string]$RootCause
    )
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($Subcategory)) { $parts += "Symptom: $Subcategory" }
    if (-not [string]::IsNullOrWhiteSpace($RootCause))   { $parts += "Possible root cause: $RootCause" }
    if ($parts.Count -eq 0) {
        return "${Category}: fallback analysis generated because AI analysis text was missing in backfill output."
    }
    return "$Category :: " + ($parts -join '. ') + '.'
}

function Get-YearWeekFromDate {
    param([DateTime]$Date)
    $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
    $wn  = $cal.GetWeekOfYear($Date, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
    return [PSCustomObject]@{
        Year       = $Date.Year
        WeekNumber = $wn
        YearWeek   = ('{0:D4}-W{1:D2}' -f $Date.Year, $wn)
    }
}

# -------- Main loop --------
Write-Step 'Fetching ServiceNow token...' 'Yellow'
$snToken = Get-ServiceNowToken

$today = (Get-Date).ToUniversalTime().Date
$summary = @{}
$totalFetched = 0; $totalSaved = 0; $totalErrors = 0; $totalSkipped = 0

for ($i = 1; $i -le $LookbackDays; $i++) {
    $day = $today.AddDays(-$i)
    $key = $day.ToString('yyyy-MM-dd')
    Write-Step "Day $i/$LookbackDays - $key" 'Cyan'

    $incidents = Get-IncidentsForDay -Token $snToken -DayUtc $day
    Write-Output "  Fetched $($incidents.Count) incidents."
    $summary[$key] = @{ fetched = $incidents.Count; saved = 0; errors = 0; skipped = 0 }

    if ($incidents.Count -eq 0) { continue }
    if ($MaxPerDay -gt 0 -and $incidents.Count -gt $MaxPerDay) {
        $incidents = $incidents | Select-Object -First $MaxPerDay
    }

    foreach ($inc in $incidents) {
        $num = $inc.number
        if (-not $num) { continue }

        $resolvedDt = $day
        if (-not [string]::IsNullOrWhiteSpace($inc.resolved_at)) {
            [DateTime]$tmp = [DateTime]::MinValue
            if ([DateTime]::TryParse([string]$inc.resolved_at, [ref]$tmp)) { $resolvedDt = $tmp }
        }
        $yw = Get-YearWeekFromDate -Date $resolvedDt

        # Skip if already in table
        $existing = Get-ExistingRowKeys -Partition $yw.YearWeek
        if ($existing.Contains([string]$num)) {
            $summary[$key].skipped++
            continue
        }

        try {
            $aiText  = Invoke-Categorize -Incident $inc
            $fields  = Get-StructuredFields -Text $aiText
            $category = if ($fields.Category) { $fields.Category } else { 'Unknown' }
            $subcat = $fields.Subcategory
            $root   = $fields.RootCause
            $anal   = $fields.Analysis
            $conf   = $fields.Confidence
            if ([string]::IsNullOrWhiteSpace($conf)) { $conf = 'Medium' }
            if ([string]::IsNullOrWhiteSpace($anal)) { $anal = New-FallbackAnalysisText -Category $category -Subcategory $subcat -RootCause $root }
            if ($subcat.Length -gt 200)  { $subcat = $subcat.Substring(0, 200) }
            if ($root.Length   -gt 1000) { $root   = $root.Substring(0, 1000) + '...' }
            if ($anal.Length   -gt 1500) { $anal   = $anal.Substring(0, 1500) + '...' }

            $props = @{
                'Category'       = [string]$category
                'Subcategory'    = [string]$subcat
                'RootCause'      = [string]$root
                'AIAnalysis'     = [string]$anal
                'Confidence'     = [string]$conf
                'Date'           = [string]$resolvedDt.ToString('yyyy-MM-dd')
                'YearWeek'       = [string]$yw.YearWeek
                'Year'           = [int]$yw.Year
                'WeekNumber'     = [int]$yw.WeekNumber
                'ReportBlobName' = 'incremental-runbook'
            }
            Add-AzTableRow -Table $cloudTable -PartitionKey $yw.YearWeek -RowKey $num -Property $props -UpdateExisting | Out-Null

            # Cache so a same-incident appearance in another loop day doesn't double-process
            [void]$existing.Add([string]$num)
            Write-Output ("  OK   {0,-15} {1,-9} {2}" -f $num, $yw.YearWeek, $category)
            $summary[$key].saved++
        } catch {
            Write-Warning "  FAIL ${num}: $($_.Exception.Message)"
            $summary[$key].errors++
        }
    }
}

# -------- Summary --------
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
Write-Output "Rows newly written: $totalSaved (skipped $totalSkipped already in table)"
