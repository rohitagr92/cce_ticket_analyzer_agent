<#
.SYNOPSIS
    Backfills the IncidentsCategoryStats Azure Table with historical Productivity Tools
    incidents so the Trends dashboard has multi-week data without waiting for the daily runbook.

.DESCRIPTION
    For each calendar day in the requested window, the script:
      1. Queries ServiceNow for incidents resolved that day (state=6 OR 7, Productivity Tools).
      2. Categorizes every incident via Azure OpenAI using the existing prompt template.
      3. Writes one row per incident to the Azure Table:
            PartitionKey = YearWeek of the incident's resolved_at  (e.g. "2026-W22")
            RowKey       = Incident number
            Category, Date, Year, WeekNumber, ReportBlobName="backfill"

    Designed to be safe to re-run: existing rows are overwritten (-UpdateExisting).
    Does NOT touch the daily runbook, schedules, or HTML report generation.

.PARAMETER Days
    Number of days to back-fill. Default 15.

.PARAMETER DryRun
    Skip the AI call and the Azure Table write; only fetch and print incident counts per day.

.PARAMETER MaxPerDay
    Optional cap on incidents categorized per day (useful for testing).

.EXAMPLE
    .\setup\backfill\Backfill-TrendData.ps1 -Days 15
.EXAMPLE
    .\setup\backfill\Backfill-TrendData.ps1 -Days 3 -MaxPerDay 5 -DryRun
#>

[CmdletBinding()]
param(
    [int]$Days = 15,
    [int]$MaxPerDay = 0,
    [string]$SubscriptionId = '1c6d384e-bc83-4b02-859c-76eeb87f7676',  # OPSW Resources (storage + table)
    # End-User Collaboration / Productivity Tools - matches local-dev\Analyze-StrictCategoryCurrentWW.ps1
    [string]$BusinessServiceId = 'a1de2ff2db8f50108062531dd3961911',
    [string]$ServiceOfferingId = 'fcb18407dbcf50108062531dd39619c4',
    # When true, skip any incident whose RowKey already exists in its YearWeek partition.
    # Cuts AI cost on daily incremental runs to (new tickets only).
    [switch]$SkipExisting,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# -------- Load config + secrets --------
$cfg     = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'config\LocalConfig-ProductivityTools.psd1')
$secrets = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'config\LocalSecrets-ProductivityTools.psd1')
foreach ($k in $secrets.Keys) { $cfg[$k] = $secrets[$k] }

$rgName   = $cfg.PSD_AI_Automations_ResourceGroupName
$saName   = $cfg.PSD_AI_Automations_StorageAccountName
$tableNm  = 'IncidentsCategoryStats'

# -------- Load prompt templates --------
$catTemplate = Get-Content -Path (Join-Path $repoRoot 'templates\TicketCategorisation_ProductivityTools.md') -Raw -Encoding UTF8
$envTemplate = Get-Content -Path (Join-Path $repoRoot 'templates\EnvironmentContext_ProductivityTools.md') -Raw -Encoding UTF8

# Strict, machine-parseable output format. Appended after the existing template so the
# downstream parser can extract Subcategory, Root Cause, and AI Analysis reliably.
$outputFormatInstruction = @'


## REQUIRED OUTPUT FORMAT (STRICT)

You MUST end your response with exactly these four labeled lines, in this order, each on its own line, with no markdown, headers, or extra commentary after them:

Primary Category: <one of the bold category names defined above, or "Excluded">
Sub-symptom: <the most specific sub-symptom label from the matching category''s bullet list, <= 80 characters>
Possible Root Cause: <one concise sentence describing the underlying technical cause>
AI Analysis: <2-3 sentence summary: what happened, what fixed it, and any notable evidence>

Rules:
- Each label must appear verbatim followed by a colon.
- Use plain ASCII. No bullets, asterisks, or quotation marks around the values.
- If unknown, write "Unknown".
- Keep each value on a single line.
'@

$systemPrompt = $catTemplate + "`n`n" + $envTemplate + $outputFormatInstruction

function Write-Step { param([string]$Msg, [string]$Color = 'Cyan') Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Msg" -ForegroundColor $Color }

# -------- ServiceNow OAuth --------
function Get-ServiceNowToken {
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $cfg.ServiceNowIncidentsClientID
        client_secret = $cfg.ServiceNowIncidentsClientSecret
        scope         = $cfg.ServiceNowIncidentsScope
    }
    (Invoke-RestMethod -Method Post -Uri $cfg.TokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded').access_token
}

# -------- Fetch incidents in a date window --------
function Get-IncidentsForDay {
    param(
        [string]$Token,
        [DateTime]$DayUtc   # local-midnight-anchored target day (interpreted as 00:00-23:59 UTC)
    )
    $startStr = $DayUtc.ToString('yyyy-MM-dd 00:00:00')
    $endStr   = $DayUtc.ToString('yyyy-MM-dd 23:59:59')

    # Filter on Productivity Tools service offering (and its business service) rather than the
    # narrow assignment_group used by the daily runbook URL - that group only owns ~5 incidents.
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
        Write-Warning "ServiceNow fetch failed for $startStr - $($_.Exception.Message)"
        return @()
    }
}

# -------- Azure OpenAI categorization --------
function Invoke-Categorize {
    param([object]$Incident)

    # Truncate work_notes to keep prompt size sane (raw notes can be massive)
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
    $headers = @{
        'api-key'      = $cfg.AzureOpenAIApiKey
        'Content-Type' = 'application/json'
    }
    $resp = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body -TimeoutSec 180
    return $resp.choices[0].message.content
}

function Get-CategoryFromResponse {
    param([string]$Text)
    if (-not $Text) { return 'Unknown' }
    $pattern = "(?s)\*{0,2}Primary Category:?\*{0,2}\s*(.+?)(?=\n\*{0,2}Exclusion|\n\*{0,2}Sub-symptom|\n\*{0,2}Confidence|\n\*{0,2}Reasoning|\n\*{0,2}Key Evidence|\Z)"
    if ($Text -match $pattern) {
        $cat = $matches[1].Trim() -replace '\*+', '' -replace '^"(.+)"$', '$1'
        # Keep only first line - some responses bleed
        $cat = ($cat -split "`n")[0].Trim()
        # Cap length defensively
        if ($cat.Length -gt 100) { $cat = $cat.Substring(0, 100) }
        return $cat
    }
    return 'Unknown'
}

# Generic single-line field extractor. Handles optional markdown bold around the label,
# accepts a few synonym labels, and stops at the next known field label or end-of-text.
function Get-FieldFromResponse {
    param(
        [string]$Text,
        [string[]]$Labels,    # accepted synonyms for this field, e.g. 'Sub-symptom','Subcategory','Sub symptom'
        [string[]]$StopLabels # labels that, if seen, end the value (the other known fields)
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $labelAlt = ($Labels | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $stopAlt  = ($StopLabels | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $pattern = "(?im)^\s*\*{0,2}(?:$labelAlt)\*{0,2}\s*[:\-]\s*(.+?)\s*(?=\r?\n\s*\*{0,2}(?:$stopAlt)\*{0,2}\s*[:\-]|\Z)"
    if ($Text -match $pattern) {
        $val = $matches[1] -replace '\r?\n', ' '            # collapse any soft wraps
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
    $safeCategory = if ([string]::IsNullOrWhiteSpace($Category)) { 'Other / Miscellaneous' } else { $Category }
    $safeSubcategory = if ([string]::IsNullOrWhiteSpace($Subcategory)) { 'the symptom was not explicitly documented' } else { $Subcategory }
    $safeRoot = if ([string]::IsNullOrWhiteSpace($RootCause)) { 'the exact root cause was not explicitly documented' } else { $RootCause }
    return "The user reported an issue that maps to '$safeSubcategory' within $safeCategory. Because the AI output for this row was incomplete, this narrative was reconstructed from structured ticket fields to preserve readability. Available troubleshooting context indicates $safeRoot as the most likely cause. The engineer resolution path should be reviewed in full work notes to confirm exact steps and user confirmation status before using this row for deep RCA decisions."
}

function Get-YearWeekFromDate {
    param([DateTime]$Date)
    $cal = [System.Globalization.CultureInfo]::CurrentCulture.Calendar
    $wn  = $cal.GetWeekOfYear($Date, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
    return [PSCustomObject]@{
        Year       = $Date.Year
        WeekNumber = $wn
        YearWeek   = ('{0:D4}-W{1:D2}' -f $Date.Year, $wn)
    }
}

# -------- Azure auth + table --------
Write-Step 'Connecting to Azure...' 'Yellow'
$ctxAz = Get-AzContext
if (-not $ctxAz) {
    Connect-AzAccount -Subscription $SubscriptionId | Out-Null
} elseif ($ctxAz.Subscription.Id -ne $SubscriptionId) {
    Set-AzContext -Subscription $SubscriptionId | Out-Null
}

if (-not (Get-Module -ListAvailable -Name AzTable)) {
    Write-Step 'Installing AzTable module (CurrentUser)...' 'Yellow'
    Install-Module -Name AzTable -Scope CurrentUser -Force -AllowClobber | Out-Null
}
Import-Module AzTable -Force

$saKey = (Get-AzStorageAccountKey -ResourceGroupName $rgName -Name $saName)[0].Value
$saCtx = New-AzStorageContext -StorageAccountName $saName -StorageAccountKey $saKey
$tbl   = Get-AzStorageTable -Name $tableNm -Context $saCtx -ErrorAction Stop
$cloudTable = $tbl.CloudTable

# Per-partition cache of existing RowKeys, populated lazily so we only query each YearWeek once.
$existingByPartition = @{}
function Get-ExistingRowKeys {
    param([string]$Partition)
    if ($existingByPartition.ContainsKey($Partition)) { return $existingByPartition[$Partition] }
    $set = [System.Collections.Generic.HashSet[string]]::new()
    try {
        $rows = Get-AzTableRow -Table $cloudTable -PartitionKey $Partition -ErrorAction Stop
        foreach ($r in @($rows)) { if ($r.RowKey) { [void]$set.Add([string]$r.RowKey) } }
    } catch {
        Write-Warning "  Could not load existing keys for ${Partition}: $($_.Exception.Message)"
    }
    $existingByPartition[$Partition] = $set
    return $set
}

# -------- Main loop --------
Write-Step "Fetching ServiceNow token..." 'Yellow'
$snToken = Get-ServiceNowToken

$today = (Get-Date).Date  # local midnight
$summary = @{}

for ($i = 1; $i -le $Days; $i++) {
    $day = $today.AddDays(-$i)
    Write-Step "Day $i/$Days  -  $($day.ToString('yyyy-MM-dd'))" 'Cyan'

    $incidents = Get-IncidentsForDay -Token $snToken -DayUtc $day
    Write-Host "  Fetched $($incidents.Count) incidents." -ForegroundColor Gray
    $summary[$day.ToString('yyyy-MM-dd')] = @{ fetched = $incidents.Count; saved = 0; errors = 0; skipped = 0 }

    if ($incidents.Count -eq 0) { continue }
    if ($MaxPerDay -gt 0 -and $incidents.Count -gt $MaxPerDay) {
        Write-Host "  Capping to $MaxPerDay incidents (MaxPerDay set)." -ForegroundColor DarkYellow
        $incidents = $incidents | Select-Object -First $MaxPerDay
    }

    foreach ($inc in $incidents) {
        $num = $inc.number
        if (-not $num) { continue }

        # Resolve the incident's own YearWeek from its resolved_at (fallback: opened_at, fallback: $day)
        $resolvedDt = $day
        if (-not [string]::IsNullOrWhiteSpace($inc.resolved_at)) {
            [DateTime]$tmp = [DateTime]::MinValue
            if ([DateTime]::TryParse([string]$inc.resolved_at, [ref]$tmp)) { $resolvedDt = $tmp }
        }
        $yw = Get-YearWeekFromDate -Date $resolvedDt

        # Incremental mode: skip incidents already categorized & stored
        if ($SkipExisting) {
            $existing = Get-ExistingRowKeys -Partition $yw.YearWeek
            if ($existing.Contains([string]$num)) {
                Write-Host ("  SKIP {0,-15} {1,-9} already in table" -f $num, $yw.YearWeek) -ForegroundColor DarkGray
                $summary[$day.ToString('yyyy-MM-dd')].skipped++
                continue
            }
        }

        if ($DryRun) {
            Write-Host "  [DRY] $num resolved=$($resolvedDt.ToString('yyyy-MM-dd')) -> $($yw.YearWeek)" -ForegroundColor DarkGray
            $summary[$day.ToString('yyyy-MM-dd')].skipped++
            continue
        }

        try {
            $aiText  = Invoke-Categorize -Incident $inc
            $fields  = Get-StructuredFields -Text $aiText
            $category = if ($fields.Category) { $fields.Category } else { (Get-CategoryFromResponse -Text $aiText) }
            if ([string]::IsNullOrWhiteSpace($category)) { $category = 'Unknown' }

            $subcat = if ($fields.Subcategory) { $fields.Subcategory } else { '' }
            $root   = if ($fields.RootCause)   { $fields.RootCause }   else { '' }
            $anal   = if ($fields.Analysis)    { $fields.Analysis }    else { '' }
            $conf   = if ($fields.Confidence)  { $fields.Confidence }  else { 'Medium' }
            if ([string]::IsNullOrWhiteSpace($anal) -or $anal.Length -lt 180) { $anal = New-FallbackAnalysisText -Category $category -Subcategory $subcat -RootCause $root }

            # Defensive caps (Azure Table string properties are <= 32 KB; we stay well below).
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
                'ReportBlobName' = 'backfill'
            }
            Add-AzTableRow -Table $cloudTable -PartitionKey $yw.YearWeek -RowKey $num -Property $props -UpdateExisting | Out-Null
            $subShort = if ($subcat.Length -gt 40) { $subcat.Substring(0,40) + '...' } else { $subcat }
            Write-Host ('  OK  {0,-15} {1,-9} {2,-45} {3}' -f $num, $yw.YearWeek, $category, $subShort) -ForegroundColor Green
            $summary[$day.ToString('yyyy-MM-dd')].saved++
        } catch {
            Write-Warning "  FAIL $num : $($_.Exception.Message)"
            $summary[$day.ToString('yyyy-MM-dd')].errors++
        }
    }
}

# -------- Summary --------
Write-Host ''
Write-Step '=== Backfill summary ===' 'Magenta'
$totalSaved = 0; $totalFetched = 0; $totalErrors = 0
$summary.Keys | Sort-Object | ForEach-Object {
    $s = $summary[$_]
    Write-Host ("  {0}  fetched={1,3}  saved={2,3}  errors={3,3}  skipped={4,3}" -f $_, $s.fetched, $s.saved, $s.errors, $s.skipped)
    $totalSaved   += $s.saved
    $totalFetched += $s.fetched
    $totalErrors  += $s.errors
}
Write-Host ("  ----------------------------------------------------------------")
Write-Host ("  TOTAL       fetched={0,3}  saved={1,3}  errors={2,3}" -f $totalFetched, $totalSaved, $totalErrors)
Write-Host ''
Write-Step "Total rows written: $totalSaved" 'Green'
if ($DryRun) { Write-Host "(Dry run - no rows were written.)" -ForegroundColor Yellow }
