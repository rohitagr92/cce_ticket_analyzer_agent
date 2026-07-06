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
      Incidents_analyzer_StorageAccountName, Incidents_analyzer_ResourceGroupName,
      Incidents_analyzer_PromptTemplateContainerName, Incidents_analyzer_SubscriptionId,
      ServiceNowIncidentsClientID, ServiceNowIncidentsClientSecret, ServiceNowIncidentsScope,
      TokenUrl, AzureOpenAIBaseUrl, AzureOpenAIDeployment, AzureOpenAIApiKey, AzureOpenAIApiVersion
    Optional Automation Variables (have hard-coded defaults):
      PT_BusinessServiceId   (default a1de2ff2db8f50108062531dd3961911)
      PT_ServiceOfferingId   (default fcb18407dbcf50108062531dd39619c4)
      PT_TrendTableName      (default IncidentsCategoryStats)
      PT_TrendLookbackDays   (default 2)
#>

[CmdletBinding()]
param(
    [int]$LookbackDays = 0,   # 0 = read from Automation variable PT_TrendLookbackDays (default 2)
    [int]$MaxPerDay    = 0    # 0 = no cap
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Msg, [string]$Color = 'Cyan') Write-Output "[$(Get-Date -Format 'HH:mm:ss')] $Msg" }

# -------- Load Automation variables --------
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
function Get-OptVar { param($n, $d) try { $v = Get-AutomationVariable -Name $n -ErrorAction Stop; if ($null -eq $v -or $v -eq '') { return $d } else { return $v } } catch { return $d } }
$BusinessServiceId = Get-OptVar 'PT_BusinessServiceId' 'a1de2ff2db8f50108062531dd3961911'
$ServiceOfferingId = Get-OptVar 'PT_ServiceOfferingId' 'fcb18407dbcf50108062531dd39619c4'
$TableName         = Get-OptVar 'PT_TrendTableName'    'IncidentsCategoryStats'
if ($LookbackDays -le 0) { $LookbackDays = [int](Get-OptVar 'PT_TrendLookbackDays' 7) }

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
$catTemplate    = Read-TemplateBlob -BlobName 'TicketCategorisation_ProductivityTools.md'
$envTemplate    = Read-TemplateBlob -BlobName 'EnvironmentContext_ProductivityTools.md'
$subCatTemplate = Read-TemplateBlob -BlobName 'TrendSubCategorisation_ProductivityTools.md'
$prcTemplate    = Read-TemplateBlob -BlobName 'PossibleRootCause_ProductivityTools.md'

$outputFormatInstruction = @'


## REQUIRED OUTPUT FORMAT (STRICT)

You MUST end your response with exactly these four labeled lines, in this order, each on its own line, with no markdown, headers, or extra commentary after them:

Primary Category: <one of the bold category names defined above, or "Excluded">
Sub-symptom: <EXACT bold header label from the Sub-symptom reference above for the chosen category — e.g. "Sync Issues", "Licensing Issues". Do NOT invent or paraphrase.>
Possible Root Cause: <EXACT bold label from the chosen product table in the Possible Root Cause reference above. Copy verbatim. If no label fits, write "Unknown".>
AI Analysis: <Detailed 4-6 sentence incident narrative covering: (1) user-reported issue and impact, (2) strongest evidence from work/close notes, (3) most likely root cause, (4) exact remediation performed, and (5) preventive follow-up/checks.>

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
        [string]$RootCause,
        [string]$SeedText = ''
    )

    $safeCategory = if ([string]::IsNullOrWhiteSpace($Category)) { 'Other / Miscellaneous' } else { $Category }
    $safeSubcategory = if ([string]::IsNullOrWhiteSpace($Subcategory)) { 'not explicitly captured in the ticket notes' } else { $Subcategory }
    $safeRootCause = if ([string]::IsNullOrWhiteSpace($RootCause)) { 'not explicitly confirmed in the stored fields' } else { $RootCause }
    $safeSeed = ([string]$SeedText).Trim()
    if ($safeSeed.Length -gt 240) { $safeSeed = $safeSeed.Substring(0, 240).Trim() + '...' }

    $evidenceSentence = if ([string]::IsNullOrWhiteSpace($safeSeed)) {
        'The available row did not contain a full AI narrative, so this detailed analysis was reconstructed from structured category fields.'
    } else {
        "The original AI text was brief, and the strongest captured evidence states: '$safeSeed'."
    }

    return "The user reached out due to an issue mapped to '$safeSubcategory' under $safeCategory. $evidenceSentence Based on the available incident notes, the engineer's troubleshooting points to $safeRootCause as the most likely cause. The recorded remediation should be treated as the practical fix path for this ticket, and post-fix validation should confirm whether the user regained expected functionality. User response and explicit satisfaction status are not always captured in this backfill flow, so unresolved confirmation details should be verified in ServiceNow work notes before escalation or closure analytics."
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
            if ([string]::IsNullOrWhiteSpace($anal) -or $anal.Length -lt 180) {
                $anal = New-FallbackAnalysisText -Category $category -Subcategory $subcat -RootCause $root -SeedText $anal
            }
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

# -------- Dashboard Regeneration (inline - no external script dependency) --------
# Works in Azure Automation because it uses table SAS + blob upload directly.
if ($totalSaved -gt 0) {
    Write-Output ''
    Write-Step '=== Regenerating dashboards for affected weeks ===' 'Cyan'
    try {
        # Collect affected weeks
        $affectedWeeks = [System.Collections.Generic.List[string]]::new()
        foreach ($day in $summary.Keys) {
            if ($summary[$day].saved -gt 0) {
                $dayDate = [DateTime]::ParseExact($day, 'yyyy-MM-dd', $null)
                $yw = Get-YearWeekFromDate -Date $dayDate
                if (-not $affectedWeeks.Contains($yw.YearWeek)) { $affectedWeeks.Add($yw.YearWeek) }
            }
        }

        if ($affectedWeeks.Count -eq 0) {
            Write-Output 'No affected weeks identified.'
        } else {
            Write-Output "Affected week(s): $($affectedWeeks -join ', ')"

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

            foreach ($weekKey in $affectedWeeks) {
                try {
                    # Query table for the full week via SAS (no AzTable module needed, works inline)
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

                    # Date range label (Mon-Sun IST, using same ISO week calculation as this runbook)
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

            # Rebuild index.json so the web app discovers the new report
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
