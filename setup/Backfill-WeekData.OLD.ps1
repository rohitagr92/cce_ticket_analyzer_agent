<#
.SYNOPSIS
    Backfills the IncidentsCategoryStats table for a specific work week (Sun-Sat in IST)
    using ServiceNow + Azure OpenAI categorization. Companion to Backfill-TrendData.ps1
    but week-anchored (not day-by-day).

.DESCRIPTION
    For -YearWeek "2026-W21":
      1. Computes the IST Sunday->Saturday window for that WW, converts to UTC for SN.
      2. Fetches all Productivity Tools incidents resolved in that UTC window
         (state IN 6 Resolved, 7 Closed).
      3. Optionally deletes existing rows in that partition first (-ClearExisting).
      4. For each incident: calls Azure OpenAI, parses Category/Subcategory/RootCause/Analysis,
         writes a row with PartitionKey = YearWeek.

.PARAMETER YearWeek
    Required, e.g. '2026-W21'. Defines the IST week (Sun 00:00 -> Sat 23:59:59 IST).

.PARAMETER ClearExisting
    Delete every row in the partition before re-categorizing. Use this when re-running
    with a corrected window definition (e.g. UTC -> IST change).

.PARAMETER SkipExisting
    Skip incidents whose RowKey already exists in the partition (cheap incremental mode).

.EXAMPLE
    .\setup\Backfill-WeekData.ps1 -YearWeek '2026-W21' -ClearExisting
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$YearWeek,
    [string]$BusinessServiceId = 'a1de2ff2db8f50108062531dd3961911',
    [string]$ServiceOfferingId = 'fcb18407dbcf50108062531dd39619c4',
    [string]$SubscriptionId    = '1c6d384e-bc83-4b02-859c-76eeb87f7676',
    [switch]$ClearExisting,
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

$rgName  = $cfg.PSD_AI_Automations_ResourceGroupName
$saName  = $cfg.PSD_AI_Automations_StorageAccountName
$tableNm = 'IncidentsCategoryStats'

# -------- Compute IST Sun-Sat window for the requested WW (US/Intel convention) --------
if ($YearWeek -notmatch '^(?<y>\d{4})-W(?<w>\d{1,2})$') { throw "Invalid YearWeek: $YearWeek" }
$year = [int]$Matches.y; $wk = [int]$Matches.w
$jan1 = (Get-Date -Year $year -Month 1 -Day 1).Date
$dow  = [int]$jan1.DayOfWeek            # Sun=0..Sat=6
$week1Sun  = $jan1.AddDays(-1 * $dow)
$weekStart = $week1Sun.AddDays(($wk - 1) * 7)       # IST Sun 00:00
$weekEnd   = $weekStart.AddDays(7).AddSeconds(-1)    # IST Sat 23:59:59
$istOffset = New-TimeSpan -Hours 5 -Minutes 30
$startUtc  = $weekStart - $istOffset
$endUtc    = $weekEnd   - $istOffset
$startStr  = $startUtc.ToString('yyyy-MM-dd HH:mm:ss')
$endStr    = $endUtc.ToString('yyyy-MM-dd HH:mm:ss')

Write-Host "=== Backfilling $YearWeek ===" -ForegroundColor Cyan
Write-Host "    IST window : $($weekStart.ToString('yyyy-MM-dd')) Sun -> $($weekEnd.ToString('yyyy-MM-dd')) Sat" -ForegroundColor Gray
Write-Host "    UTC filter : $startStr  ->  $endStr" -ForegroundColor DarkGray

# -------- Build system prompt (compact: context + embedded allowed-value lists) --------
# The full template files are loaded for reference/upload only.
# The AI prompt uses embedded lists in $outputFormatInstruction to keep the
# system prompt small enough to avoid content filter issues on long work notes.
$systemContext = @'
You are an expert IT support analyst for Intel's Productivity Tools service offering (Microsoft 365, OneDrive, SharePoint, Copilot, OneNote, Excel, Word, PowerPoint, Visio, Project, Loop, Forms, Google Workspace, Smartsheet, Shared File Service, Canva, M365 Groups/Planner/To Do).

You will receive a ServiceNow incident with description, work notes, close notes, and close code. Analyze the root cause and classify the incident using ONLY the allowed values listed below. Do NOT invent new category names, sub-symptoms, root causes, or detailed root cause labels unless truly no entry fits (in which case prefix with [NEW]).

Products in scope: Microsoft 365 Apps for Enterprise, Microsoft 365 Copilot, Microsoft OneDrive for Business, Microsoft SharePoint Online, Microsoft OneNote, Microsoft Loop, Microsoft Forms, Microsoft Visio Professional Client, Microsoft Project, Microsoft 365 Groups/Planner/To Do, Google Workspace (Docs/Sheets/Slides/Drive/Gemini), Smartsheet, Shared File Service (Share Drives), Canva.
Out of scope (use Excluded): PC hardware, OS rebuild, network/VPN, Outlook mail flow/Exchange routing, Teams calling/meetings, GitHub/developer tools, Microsoft Visual Studio, printer supplies, cellular.
'@
$outputFormatInstruction = @'


## REQUIRED OUTPUT FORMAT (STRICT - ALLOWED LISTS BELOW)

You MUST end your response with EXACTLY these five labeled lines, in this order, nothing after them:

Primary Category: <pick VERBATIM from ALLOWED PRIMARY CATEGORIES list below>
Sub-symptom: <pick VERBATIM from ALLOWED SUB-SYMPTOMS list below for that category>
Possible Root Cause: <pick VERBATIM from ALLOWED POSSIBLE ROOT CAUSE list below>
Detailed Root Cause: <pick VERBATIM from ALLOWED DETAILED ROOT CAUSE list below>
AI Analysis: <2-3 sentences: what happened, what fixed it, key evidence>

RULE: Every value MUST come verbatim from the allowed lists below. If no entry fits, prefix with [NEW].

---
### ALLOWED PRIMARY CATEGORIES (pick exactly one):
Microsoft Excel Issues
Microsoft Word Issues
Microsoft PowerPoint Issues
Microsoft OneNote Issues
Microsoft 365 Apps for Enterprise Issues
Microsoft 365 Copilot Issues
Microsoft Forms Issues
Microsoft Visio Issues
Microsoft Project Issues
Microsoft Loop Issues
Microsoft OneDrive Issues
SharePoint / Shared File Access Issues
Shared File Service (Share Drives) Issues
Smartsheet Issues
Google Workspace Issues
Microsoft 365 Groups / Planner / To Do Issues
Canva Issues
Other / Miscellaneous
Excluded

NOTE: "How Do I / User Education" is NOT a valid category. Route guidance/how-to questions to the relevant product category (e.g. Copilot usage query → Microsoft 365 Copilot Issues with sub-symptom "Copilot usage query").

---
### ALLOWED SUB-SYMPTOMS (pick the one matching your Primary Category):

Microsoft OneDrive Issues: OneDrive sync failure | Sync stuck issue | Cross-device sync delay | Sync conflict error | Shared file access issue | Permission not applied | Rejoin access issue | Missing files after refresh | Missing files or folder from downloads folder | File open issue (desktop) | Web vs desktop mismatch | File access inconsistency | OneDrive client not running | Login/connectivity issue | Storage quota exceeded | Backup not completing | Offline files issue

Microsoft Excel Issues: File not opening | Blank file issue | File corruption issue | Excel performance issue | Large file slowness | Excel Hang | Excel Crash | File save failure | File update inconsistency | Shared file sync issue | Add-in issue | Data refresh failure

Microsoft PowerPoint Issues: Presentation not opening | Blank file issue | File corruption issue | PowerPoint performance issue | Large file slowness | Powerpoint Hang | Powerpoint Crash | Formatting issue | Layout/structure issue | Media feature issue

Microsoft Word Issues: Document not opening | File corruption issue | Word performance issue | Word Hang | Word Crash | Formatting issue | Layout/structure issue

Microsoft OneNote Issues: Notebook sync failure | Missing notes issue | Data loss after PC refresh | OneNote not responding | OneNote not opening | OneNote Crash | OneNote Hang | OneNote Slowness | OneNote Features not working

Microsoft 365 Apps for Enterprise Issues: Office apps not opening | App login failure | App crash issue | License not assigned | License expired issue | Activation issue | Installation failure | Missing app issue | Compatibility issue

Microsoft 365 Copilot Issues: Copilot not visible | Feature rollout issue | Copilot license missing | License expired issue | Copilot partially enabled | Feature inconsistency issue | Copilot usage query | Copilot not responding | Copilot not opening | Copilot Crash | Copilot Hang | Copilot Slowness

Microsoft Forms Issues: Forms access issue | Forms Ownership Transfer issue | Forms feature missing | Poll feature disabled | Forms usage query

Microsoft Visio Issues: Visio install failure | License expired issue | Trial expired issue | Activation failure | Features missing | Visio Hang | Visio Crash

Microsoft Loop Issues: Workspace not loading | Missing workspace content | Unable to delete the workspace | Unable to share the workspace | Loop integration issue

Smartsheet Issues: Smartsheet access issue | Smartsheet Feature Issue

Google Workspace Issues: Google access issue | External sharing issue | Unable to access external application | Unable to access Gemini

Microsoft Project Issues: License activation issue | Installation failure

SharePoint / Shared File Access Issues: Access denied | Owner re-share required | Permission error on shared file | Stale share link | User removed during access review

Shared File Service (Share Drives) Issues: Mapped drive not connecting | Access permission issue | Missing folder or file | Drive sync failure | Quota issue

Microsoft 365 Groups / Planner / To Do Issues: M365 Group membership issue | Planner plan access issue | To Do list sync issue | Group provisioning failure

Canva Issues: Access / SSO sign-in issue | License / entitlement missing | Sharing / collaboration issue | Template / brand kit access issue | Export / download failure

---
### ALLOWED POSSIBLE ROOT CAUSE (pick the ### heading verbatim):
1.1 Rejoined user cannot access previous OneDrive / SharePoint content
1.2 Site permission did not reapply after rejoin
1.3 Access to a former employee's OneDrive data
2.1 License activation issue
2.2 Installation failure
2.3 Office apps not opening
2.4 App crash / instability (across multiple Office apps)
3.1 Sync failure (most common subcategory)
3.2 OneDrive client not working / stopped
3.3 File rename / path conflict
4.1 Copilot license missing (dominant root cause)
4.2 Feature rollout issue / ChunkLoadError
4.3 Usage guidance query (How Do I)
5.1 File not opening
5.2 Data refresh issue
5.3 Excel freezing / hanging
6.1 Data not available after device change (dominant in data set)
6.2 Notebook sync failure
6.3 OneNote not responding
7.1 Access denied / You need permission to access this item
7.2 Access denied / permission error on shared file
7.3 Access denied / permission issue on shared file (Excel content)
8.1 Mapped drive not connecting
8.2 Access permission issue on a shared / mapped drive path
8.3 Missing folder / file on a shared drive
9.1 General how-to / configuration
10.1 Forms not accessible
10.2 Polls not working (Teams / Outlook)
11.1 Add-in failure
12.1 PowerPoint crashing / freezing
12.2 Presentation not opening (path/location issue)
13.1 Project license missing (dominant root cause)
14.1 Permission issue

---
### ALLOWED DETAILED ROOT CAUSE (pick the ### heading verbatim):
OneDrive client stopped syncing
Long path or filename conflict
Cloud file provider error (0x80070194)
Files-On-Demand / selective sync exclusion
OneDrive client failed to launch
Former-employee OneDrive data request
Corrupted Office installation
Corrupted Office identity / cached credential
F3 license restriction
Activation endpoint unreachable
Click-to-Run installer hung in Company Portal
Click-to-Run error 30015-xx
Stale Office / Teams cached state
Copilot licence blackout (pool depleted)
Copilot SKU not provisioned for region / BU
Copilot licence assigned but not propagated
Copilot ChunkLoadError (stale browser / Teams cache)
Copilot phased rollout ring
Copilot usage / how-to question
Excel stuck in hung process
Stale Excel desktop cache
Excel desktop performance degradation
Corrupted Excel add-in
OLAP / Power BI data refresh slowness
Underlying data permission missing (returns #N/A)
Notebook not added on new device
Notebook hosted on inaccessible OneDrive
OneNote Windows 10 client compatibility
OneNote client launch failure
Stale share link / removed access entry
User removed during access review
Permission not inherited from parent
Office app cannot open file due to missing share
Drive remap required after PC change
Drive-letter / resource conflict
Missing AGS entitlement for share
Subfolder permission missing
File or folder deleted on share
Forms Creation Access entitlement missing
Outlook / Teams poll not loading
Word add-in not deployed by IT
Office Store disabled by tenant policy
PowerPoint desktop-only crash
Presentation path not reachable
Project install entitlement missing
Google Drive upload blocked by IT policy
Rehired with new account identity (PUID changed)
Previous OneDrive site not retained
PUID / URL mapping mismatch
Stale permission entry on old identity
Former-employee data within retention
Guidance request (configuration / usage)
Unsupported feature or account type
'@
$systemPrompt = $systemContext + $outputFormatInstruction

# -------- ServiceNow OAuth + fetch --------
function Get-SnToken {
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $cfg.ServiceNowIncidentsClientID
        client_secret = $cfg.ServiceNowIncidentsClientSecret
        scope         = $cfg.ServiceNowIncidentsScope
    }
    (Invoke-RestMethod -Method Post -Uri $cfg.TokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded').access_token
}

function Get-IncidentsForWindow {
    param([string]$Token, [string]$StartUtc, [string]$EndUtc)
    $query = "business_service=$BusinessServiceId^service_offering=$ServiceOfferingId^stateIN6,7^resolved_at>=$StartUtc^resolved_at<=$EndUtc"
    $url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$query&sysparm_display_value=true&sysparm_limit=2000"
    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
    $resp = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -TimeoutSec 180
    @($resp.result)
}

# -------- AI categorize + parse --------
function Remove-Pii {
    param([string]$s)
    $s = $s -replace '\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b', '[EMAIL]'
    $s = $s -replace '\\\\[^\s]+', '[PATH]'
    $s = $s -replace '[A-Za-z]:\\[^\s]+', '[PATH]'
    $s = $s -replace '\b(?:\d{1,3}\.){3}\d{1,3}\b', '[IP]'
    $s = $s -replace '\b[a-zA-Z0-9]{8}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{12}\b', '[GUID]'
    return $s
}

function Invoke-AzOpenAI {
    param([string]$Prompt, [string]$OverrideSystemPrompt = '')
    $sysContent = if ($OverrideSystemPrompt) { $OverrideSystemPrompt } else { $systemPrompt }
    $body = @{
        messages = @(
            @{ role = 'system'; content = $sysContent },
            @{ role = 'user';   content = $Prompt }
        )
        max_completion_tokens = 1800
    } | ConvertTo-Json -Depth 10 -Compress
    $url = "$($cfg.AzureOpenAIBaseUrl)/openai/deployments/$($cfg.AzureOpenAIDeployment)/chat/completions?api-version=$($cfg.AzureOpenAIApiVersion)"
    $headers = @{ 'api-key' = $cfg.AzureOpenAIApiKey; 'Content-Type' = 'application/json' }
    (Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body -TimeoutSec 180).choices[0].message.content
}

function Invoke-Categorize {
    param([object]$Incident)
    $wn = [string]$Incident.work_notes
    if ($wn.Length -gt 6000) { $wn = $wn.Substring(0, 6000) + '... [truncated]' }
    $cn = [string]$Incident.close_notes
    if ($cn.Length -gt 2000) { $cn = $cn.Substring(0, 2000) + '... [truncated]' }

    $payload = [PSCustomObject]@{
        IncidentNumber           = $Incident.number
        'User Description'       = [string]$Incident.description
        'User Short Description' = [string]$Incident.short_description
        'User Work Notes'        = $wn
        'Close Notes'            = $cn
        'Close Code'             = [string]$Incident.close_code
        'Incident Opened At'     = [string]$Incident.opened_at
        'Incident Resolved At'   = [string]$Incident.resolved_at
    }
    $prompt = $payload | ConvertTo-Json -Depth 4 -Compress

    try {
        return Invoke-AzOpenAI -Prompt $prompt
    } catch {
        $msg = $_.Exception.Message
        # Only retry on 400 (content filter). Let 429 propagate so caller handles it as a distinct error.
        if ($msg -notmatch '400') { throw }

        Write-Warning "    400 on full notes for $($Incident.number) - retry 1: sanitized close_notes only..."
        $cnSan = Remove-Pii $cn
        if ($cnSan.Length -gt 1500) { $cnSan = $cnSan.Substring(0, 1500) + '... [truncated]' }
        $sdSan = Remove-Pii ([string]$Incident.short_description)
        $p2 = [PSCustomObject]@{
            IncidentNumber           = $Incident.number
            'User Short Description' = $sdSan
            'Close Notes'            = $cnSan
            'Close Code'             = [string]$Incident.close_code
            'Incident Resolved At'   = [string]$Incident.resolved_at
            '_note'                  = 'Full work notes omitted due to content filter.'
        } | ConvertTo-Json -Depth 4 -Compress
        try { return Invoke-AzOpenAI -Prompt $p2 } catch {
            if ($_.Exception.Message -notmatch '400') { throw }
        }

        Write-Warning "    400 again for $($Incident.number) - retry 2: short description + minimal system prompt..."
        $minimalSysPrompt = @"
You are an IT support analyst. Classify this Productivity Tools incident. Reply with exactly these lines:
Primary Category: <Microsoft 365 Apps/OneDrive/OneNote/SharePoint/Copilot/Forms/Visio/Project/Loop/Groups/Planner/Google Workspace/Smartsheet/Shared File Service/How Do I/Excluded> Issues
Sub-symptom: <brief symptom label>
Possible Root Cause: <one sentence>
Detailed Root Cause: <one sentence>
AI Analysis: <2-3 sentences>
"@
        $p3 = [PSCustomObject]@{
            IncidentNumber           = $Incident.number
            'User Short Description' = $sdSan
            'Close Code'             = [string]$Incident.close_code
            'Incident Resolved At'   = [string]$Incident.resolved_at
        } | ConvertTo-Json -Depth 4 -Compress
        return Invoke-AzOpenAI -Prompt $p3 -OverrideSystemPrompt $minimalSysPrompt
    }
}

function Get-Field {
    param([string]$Text, [string[]]$Labels, [string[]]$Stops)
    if (-not $Text) { return '' }
    foreach ($lbl in $Labels) {
        $stopAlt = ($Stops | Where-Object { $_ -ne $lbl } | ForEach-Object { [Regex]::Escape($_) }) -join '|'
        $pat = "(?im)^\s*\*{0,2}$([Regex]::Escape($lbl))\*{0,2}\s*:\s*(?<v>.+?)(?=\n\s*\*{0,2}($stopAlt)\*{0,2}\s*:|\z)"
        $m = [Regex]::Match($Text, $pat, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($m.Success) { return ($m.Groups['v'].Value.Trim() -replace '^\*+|\*+$', '').Trim() }
    }
    return ''
}

function Get-StructuredFields {
    param([string]$Text)
    $all = 'Primary Category','Sub-symptom','Subcategory','Sub symptom','Possible Root Cause','Root Cause','Top Root Cause','Detailed Root Cause','AI Analysis','Analysis'
    [PSCustomObject]@{
        Category        = Get-Field -Text $Text -Labels @('Primary Category') -Stops $all
        Subcategory     = Get-Field -Text $Text -Labels @('Sub-symptom','Subcategory','Sub symptom') -Stops $all
        # "Possible Root Cause" is now the strict catalog bucket pick (from PossibleRootCause_ProductivityTools.md).
        # Stored in the existing TopRootCause column for backward-compat with the report layout.
        TopRootCause    = Get-Field -Text $Text -Labels @('Possible Root Cause','Top Root Cause','Root Cause') -Stops $all
        DetailedRC      = Get-Field -Text $Text -Labels @('Detailed Root Cause') -Stops $all
        RootCause       = ''  # no longer separately emitted; kept blank for schema compatibility
        Analysis        = Get-Field -Text $Text -Labels @('AI Analysis','Analysis') -Stops $all
    }
}

# -------- Azure auth + table --------
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
$ctxAz = Get-AzContext
if (-not $ctxAz) { Connect-AzAccount -Subscription $SubscriptionId | Out-Null }
elseif ($ctxAz.Subscription.Id -ne $SubscriptionId) { Set-AzContext -Subscription $SubscriptionId | Out-Null }

if (-not (Get-Module -ListAvailable -Name AzTable)) {
    Install-Module -Name AzTable -Scope CurrentUser -Force -AllowClobber | Out-Null
}
Import-Module AzTable -Force

$saKey = (Get-AzStorageAccountKey -ResourceGroupName $rgName -Name $saName)[0].Value
$saCtx = New-AzStorageContext -StorageAccountName $saName -StorageAccountKey $saKey
$cloudTable = (Get-AzStorageTable -Name $tableNm -Context $saCtx -ErrorAction Stop).CloudTable

# -------- Clear partition if requested --------
if ($ClearExisting) {
    Write-Host "Clearing existing rows in partition $YearWeek..." -ForegroundColor Yellow
    $existing = @(Get-AzTableRow -Table $cloudTable -PartitionKey $YearWeek -ErrorAction SilentlyContinue)
    $delCount = 0
    foreach ($r in $existing) {
        try { $r | Remove-AzTableRow -Table $cloudTable | Out-Null; $delCount++ } catch { Write-Warning "  Delete failed for $($r.RowKey): $_" }
    }
    Write-Host "  Removed $delCount rows." -ForegroundColor Gray
}

# Existing keys (for SkipExisting)
$existingKeys = [System.Collections.Generic.HashSet[string]]::new()
if ($SkipExisting -and -not $ClearExisting) {
    $rows = @(Get-AzTableRow -Table $cloudTable -PartitionKey $YearWeek -ErrorAction SilentlyContinue)
    foreach ($r in $rows) { if ($r.RowKey) { [void]$existingKeys.Add([string]$r.RowKey) } }
    Write-Host "Existing rows in partition: $($existingKeys.Count)" -ForegroundColor Gray
}

# -------- Fetch incidents --------
Write-Host "Fetching ServiceNow token..." -ForegroundColor Yellow
$snToken = Get-SnToken
Write-Host "Querying incidents..." -ForegroundColor Yellow
$incidents = Get-IncidentsForWindow -Token $snToken -StartUtc $startStr -EndUtc $endStr
$resolved = ($incidents | Where-Object { $_.state -eq 'Resolved' }).Count
$closed   = ($incidents | Where-Object { $_.state -eq 'Closed' }).Count
Write-Host ("Fetched {0} incidents  (Resolved={1}, Closed={2})" -f $incidents.Count, $resolved, $closed) -ForegroundColor Green

if ($DryRun) {
    Write-Host "DryRun - skipping AI + table writes." -ForegroundColor Yellow
    return
}

# -------- Categorize + write --------
$saved = 0; $skipped = 0; $errors = 0
foreach ($inc in $incidents) {
    $num = $inc.number
    if (-not $num) { continue }
    if ($SkipExisting -and $existingKeys.Contains([string]$num)) {
        Write-Host ("  SKIP {0}" -f $num) -ForegroundColor DarkGray
        $skipped++; continue
    }

    # Use resolved_at for Date column (display value, IST)
    $dateStr = ''
    if (-not [string]::IsNullOrWhiteSpace($inc.resolved_at)) {
        [DateTime]$tmp = [DateTime]::MinValue
        if ([DateTime]::TryParse([string]$inc.resolved_at, [ref]$tmp)) { $dateStr = $tmp.ToString('yyyy-MM-dd') }
    }
    if (-not $dateStr) { $dateStr = $weekStart.ToString('yyyy-MM-dd') }

    try {
        $aiText = Invoke-Categorize -Incident $inc
        $f = Get-StructuredFields -Text $aiText
        $category = if ($f.Category)    { $f.Category }    else { 'Unknown' }
        $subcat   = if ($f.Subcategory)  { $f.Subcategory } else { '' }
        $topRc    = if ($f.TopRootCause) { $f.TopRootCause } else { '' }
        $detRc    = if ($f.DetailedRC)   { $f.DetailedRC }   else { '' }
        $root     = if ($f.RootCause)    { $f.RootCause }    else { '' }
        $anal     = if ($f.Analysis)     { $f.Analysis }     else { '' }
        if ($subcat.Length -gt 200)  { $subcat = $subcat.Substring(0, 200) }
        if ($topRc.Length  -gt 200)  { $topRc  = $topRc.Substring(0, 200) }
        if ($detRc.Length  -gt 250)  { $detRc  = $detRc.Substring(0, 250) }
        if ($root.Length   -gt 1000) { $root   = $root.Substring(0, 1000) + '...' }
        if ($anal.Length   -gt 1500) { $anal   = $anal.Substring(0, 1500) + '...' }

        $props = @{
            'Category'           = [string]$category
            'Subcategory'        = [string]$subcat
            'PossibleRootCause'  = [string]$topRc
            'TopRootCause'       = [string]$topRc
            'DetailedRootCause'  = [string]$detRc
            'RootCause'          = [string]$root
            'AIAnalysis'         = [string]$anal
            'State'              = [string]$inc.state
            'Date'               = [string]$dateStr
            'YearWeek'           = [string]$YearWeek
            'Year'               = [int]$year
            'WeekNumber'         = [int]$wk
            'ReportBlobName'     = 'week-backfill'
        }
        Add-AzTableRow -Table $cloudTable -PartitionKey $YearWeek -RowKey $num -Property $props -UpdateExisting | Out-Null
        $sub = if ($subcat.Length -gt 40) { $subcat.Substring(0,40) + '...' } else { $subcat }
        Write-Host ('  OK  {0,-15} {1,-10} {2,-40} {3}' -f $num, $inc.state, $category, $sub) -ForegroundColor Green
        $saved++
    } catch {
        Write-Warning "  FAIL $num : $($_.Exception.Message)"
        # Write a placeholder row so the incident still appears in the weekly report.
        try {
            $sd = [string]$inc.short_description
            if ($sd.Length -gt 180) { $sd = $sd.Substring(0, 180) }
            $props = @{
                'Category'          = 'Unknown'
                'Subcategory'       = 'AI categorization unavailable'
                'PossibleRootCause' = 'Unknown'
                'TopRootCause'      = 'Client-Side Corruption / Stale State'
                'DetailedRootCause' = '[NEW] AI categorization rejected by content filter'
                'RootCause'         = $sd
                'AIAnalysis'        = 'Azure OpenAI request was rejected (likely content filter). Manual review required.'
                'State'             = [string]$inc.state
                'Date'              = [string]$dateStr
                'YearWeek'          = [string]$YearWeek
                'Year'              = [int]$year
                'WeekNumber'        = [int]$wk
                'ReportBlobName'    = 'week-backfill-fallback'
            }
            Add-AzTableRow -Table $cloudTable -PartitionKey $YearWeek -RowKey $num -Property $props -UpdateExisting | Out-Null
            Write-Host ('  FB  {0,-15} placeholder row written' -f $num) -ForegroundColor DarkYellow
        } catch {
            Write-Warning "  Could not write fallback row for ${num}: $($_.Exception.Message)"
        }
        $errors++
    }
}

Write-Host ""
Write-Host "=== Done $YearWeek ===" -ForegroundColor Magenta
Write-Host ("  Fetched: {0}   Saved: {1}   Skipped: {2}   Errors: {3}" -f $incidents.Count, $saved, $skipped, $errors) -ForegroundColor Green
