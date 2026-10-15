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
    [int]$MaxPerDay    = 0,   # 0 = no cap
    [string]$StartDate = '',
    [string]$EndDate = '',
    [string[]]$IncidentNumbers = @(),
    [switch]$ForceReanalyze,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Msg, [string]$Color = 'Cyan') Write-Output "[$(Get-Date -Format 'HH:mm:ss')] $Msg" }

function Get-ContentEngSecretOrVar {
    param(
        [Parameter(Mandatory = $true)][string]$LegacyVariableName,
        [Parameter(Mandatory = $true)][string]$SecretNameVariable,
        [string]$DefaultSecretName
    )

    $vaultName = Get-AutomationVariable -Name 'ContentEng_KeyVaultName' -ErrorAction SilentlyContinue
    $secretName = Get-AutomationVariable -Name $SecretNameVariable -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($secretName)) { $secretName = $DefaultSecretName }

    if (-not [string]::IsNullOrWhiteSpace($vaultName) -and -not [string]::IsNullOrWhiteSpace($secretName)) {
        try {
            $secretObj = Get-AzKeyVaultSecret -VaultName $vaultName -Name $secretName -ErrorAction Stop
            if ($secretObj -and $secretObj.SecretValue) { return ($secretObj.SecretValue | ConvertFrom-SecureString -AsPlainText) }
        } catch {
            Write-Warning "Key Vault read failed for $secretName. Falling back to automation variable $LegacyVariableName."
        }
    }

    return (Get-AutomationVariable -Name $LegacyVariableName -ErrorAction SilentlyContinue)
}

# -------- Load Automation variables --------
Write-Step 'Loading Automation variables...' 'Yellow'
$cfg = @{
    StorageAccountName              = Get-AutomationVariable -Name 'ContentEng_StorageAccountName'
    ResourceGroupName               = Get-AutomationVariable -Name 'ContentEng_ResourceGroupName'
    PromptContainerName             = Get-AutomationVariable -Name 'ContentEng_PromptTemplateContainerName'
    SubscriptionId                  = Get-AutomationVariable -Name 'ContentEng_SubscriptionId'
    ContentEng_ServiceNowClientID     = Get-AutomationVariable -Name 'ContentEng_ServiceNowClientID'
    ContentEng_ServiceNowClientSecret = $null
    ContentEng_ServiceNowScope        = Get-AutomationVariable -Name 'ContentEng_ServiceNowScope'
    TokenUrl                        = Get-AutomationVariable -Name 'ContentEng_TokenUrl'
    AzureOpenAIBaseUrl              = Get-AutomationVariable -Name 'ContentEng_AzureOpenAIBaseUrl'
    AzureOpenAIDeployment           = Get-AutomationVariable -Name 'ContentEng_AzureOpenAIDeployment'
    AzureOpenAIApiKey               = $null
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
Import-Module Az.KeyVault -Force -ErrorAction SilentlyContinue

# Resolve sensitive values from Key Vault with fallback to legacy automation variables.
$cfg.ContentEng_ServiceNowClientSecret = Get-ContentEngSecretOrVar -LegacyVariableName 'ContentEng_ServiceNowClientSecret' -SecretNameVariable 'ContentEng_ServiceNowClientSecretName' -DefaultSecretName 'ContentEng-ServiceNowClientSecret'
$cfg.AzureOpenAIApiKey = Get-ContentEngSecretOrVar -LegacyVariableName 'ContentEng_AzureOpenAIApiKey' -SecretNameVariable 'ContentEng_AzureOpenAIApiKeySecretName' -DefaultSecretName 'ContentEng-AzureOpenAIApiKey'

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
$cleanupTemplate = Read-TemplateBlob -BlobName 'WorkNotesCleanup_ContentEngineering.md'
$subCatTemplate = Read-TemplateBlob -BlobName 'TrendSubCategorisation_ContentEngineering.md'
$prcTemplate    = Read-TemplateBlob -BlobName 'PossibleRootCause_ContentEngineering.md'
$drcTemplate    = Read-TemplateBlob -BlobName 'DetailedRootCause_ContentEngineering.md'
$referenceMap   = Read-TemplateBlob -BlobName 'ReferenceMap_ContentEngineering.md'

$outputFormatInstruction = @'
## REQUIRED OUTPUT (JSON ONLY)
Return exactly one JSON object with IncidentNumber, PrimaryCategory, SubCategory, PossibleRootCause, DetailedRootCause (exact catalog heading), DetailedRootCauseExplanation (an evidence-based explanation of at most 50 words), Issue, RootCauseNarrative, Resolution, Evidence, HDI (Yes or No), ExclusionReason, References (array of strings), AIAnalysis (2-3 evidence-based sentences), and Confidence (High, Medium, or Low).
Issue must state the observed problem. RootCauseNarrative must explain what the notes establish, or state that no cause was established. Resolution must describe the documented outcome, including unresolved/closed without a fix. Evidence must cite concrete facts from the work or close notes. Do not copy a symptom label as the narrative or invent a fix.
Use neutral roles instead of personal names, email addresses, phone numbers, or employee IDs in every narrative field. Preserve product names, error text and incident/KB references.
If the notes confirm a cause or product limitation, do not choose a DetailedRootCause heading that says the cause is not evidenced. Choose the exact heading whose Possible Root Cause matches your selected label.
For every in-scope ticket, the DetailedRootCause heading's Possible Root Cause must exactly match PossibleRootCause. Use the product-specific Unknown heading only when PossibleRootCause is Unknown; otherwise never select an Unknown heading. Always return HDI as Yes or No, Confidence as High, Medium, or Low, and a non-empty AIAnalysis.
Never include source email addresses, phone numbers, or employee IDs in any response field, including Evidence; redact contact values and refer to the person's role. Before returning JSON, verify that the selected DRC's adjacent Possible Root Cause exactly matches PossibleRootCause.
Use only the seven products declared in scope in the reference files, including Microsoft Planner Issues. For another product, use PrimaryCategory "Excluded", SubCategory "Out of Scope", PossibleRootCause "Out-of-scope Service Offering", and the exact Excluded detailed heading. Never categorize Power Apps, Power Automate, or CMS as an in-scope product.
Microsoft 365 group message moderation and approval email delivery are not Viva Engage community administration; classify those issues as Excluded unless a CE-owned product failure is documented.
Copy all four classification labels verbatim from their product sections in the references. A symptom is not a cause; do not invent a cause when evidence is missing. Never use a different product's root cause or a placeholder analysis.
'@
# Build system prompt from all 4 canonical templates — same enforcement as incident-analyzer-rb-prodtools.ps1.
# This ensures Sub-symptom and Possible Root Cause are always strict labels from the template catalogs,
# not free-form AI-generated text that would fail compliance validation.
$systemPrompt = $catTemplate + "`n`n" + $envTemplate + "`n`n" +
    "## PRIVACY: Cleaned Work Notes Rules`n" + $cleanupTemplate + "`n`n" +
    "## REFERENCE: Sub-symptom Labels`n" + $subCatTemplate + "`n`n" +
    "## REFERENCE: Possible Root Cause Labels`n" + $prcTemplate + "`n`n" +
    "## REFERENCE: Detailed Root Cause Headings`n" + $drcTemplate + "`n`n" + $referenceMap +
    $outputFormatInstruction

$allowedProducts = @(
    'SharePoint Online Issues', 'SharePoint Subscription Edition (SSE) Issues',
    'Viva Engage (Yammer) Issues', 'Guest Onboarding Tool Issues',
    'Collaboration Workspace Management Tool (WMT) Issues', 'Microsoft Teams Issues',
    'Microsoft Planner Issues'
)
$allowedCategories = @($allowedProducts) + 'Excluded'
function Get-ProductSections {
    param([string]$Text, [string]$HeadingPattern, [string]$LabelPattern)
    $catalog = @{}
    foreach ($section in [regex]::Matches($Text, $HeadingPattern)) {
        $heading = $section.Groups['heading'].Value.Trim()
        $labels = @([regex]::Matches($section.Groups['body'].Value, $LabelPattern) | ForEach-Object { $_.Groups['label'].Value.Trim() })
        $catalog[$heading] = $labels
    }
    return $catalog
}
$sectionPattern = '(?ms)^###\s+(?<heading>[^\r\n]+)\r?\n(?<body>.*?)(?=^###\s+|^##\s+|\z)'
$symptoms = Get-ProductSections -Text $subCatTemplate -HeadingPattern $sectionPattern -LabelPattern '(?m)^-\s+\*\*(?<label>[^*]+)\*\*'
$causes = Get-ProductSections -Text $prcTemplate -HeadingPattern $sectionPattern -LabelPattern '(?m)^\|\s*\d+\s*\|\s*\*\*(?<label>[^*]+)\*\*'
$details = Get-ProductSections -Text $drcTemplate -HeadingPattern '(?ms)^##\s+(?<heading>[^\r\n]+)\r?\n(?<body>.*?)(?=^##\s+|\z)' -LabelPattern '(?m)^###\s+(?<label>[^\r\n]+)'
foreach ($category in $allowedCategories) {
    $causeHeading = $category -replace ' Issues$', ''
    if (-not $symptoms.ContainsKey($category) -or -not $causes.ContainsKey($causeHeading) -or -not $details.ContainsKey($category)) {
        throw "CE taxonomy is incomplete for '$category'. Fix the uploaded templates before backfill."
    }
}

function ConvertFrom-ValidatedClassification {
    param([string]$Text, [string]$IncidentNumber)
    $json = $Text.Trim() -replace '(?s)^```(?:json)?\s*|\s*```$', ''
    $result = $json | ConvertFrom-Json -ErrorAction Stop
    $category = [string]$result.PrimaryCategory
    $symptom = [string]$result.SubCategory
    $cause = [string]$result.PossibleRootCause
    $detail = ([string]$result.DetailedRootCause -replace '^###\s*', '').Trim()
    $result.DetailedRootCause = $detail
    $causeHeading = $category -replace ' Issues$', ''
    if ([string]$result.IncidentNumber -ne $IncidentNumber -or $category -notin $allowedCategories) {
        throw "Invalid incident number or category for $IncidentNumber."
    }
    $unevidencedDetail = $detail -in @($details[$category]) -and $detail -match '(?i)(?:issue|cause) is not evidenced$'
    $unevidencedCause = $cause -eq 'Unknown' -and $unevidencedDetail -and $category -ne 'Excluded'
    if ($cause -ne 'Unknown' -and $unevidencedDetail) {
        throw "CE cause and detailed heading contradict each other for $IncidentNumber ($category / $cause / $detail)."
    }
    if ($cause -eq 'Unknown' -and -not $unevidencedCause) {
        throw "Unknown CE cause lacks the matching unevidenced DRC for $IncidentNumber."
    }
    if ($symptom -notin @($symptoms[$category]) -or ($cause -notin @($causes[$causeHeading]) -and -not $unevidencedCause) -or $detail -notin @($details[$category])) {
        throw "Invalid CE symptom/root/detailed cause for $IncidentNumber ($category / $symptom / $cause / $detail)."
    }
    if ($result.HDI -notin @('Yes','No') -or $result.Confidence -notin @('High','Medium','Low') -or [string]::IsNullOrWhiteSpace([string]$result.AIAnalysis)) {
        throw "Missing or invalid CE analysis fields for $IncidentNumber."
    }
    foreach ($field in @('Issue','RootCauseNarrative','Resolution','Evidence','DetailedRootCauseExplanation')) {
        $value = ([string]$result.$field).Trim()
        if ([string]::IsNullOrWhiteSpace($value) -or $value -in @('Unknown','N/A','Not documented','Not separately documented in this record.','Not documented in source incident notes') -or
            ($field -in @('RootCauseNarrative','Resolution','Evidence') -and $value -in @($category,$symptom,$cause,$detail))) {
            throw "Missing CE $field for $IncidentNumber."
        }
    }
    foreach ($field in @('Issue','RootCauseNarrative','Resolution','Evidence','DetailedRootCauseExplanation','AIAnalysis')) {
        if ([string]$result.$field -match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' -or [string]$result.$field -match '(?<!\w)\+\d[\d\s-]{9,}') {
            throw "CE $field contains personal contact details for $IncidentNumber."
        }
    }
    $detailWords = @(([string]$result.DetailedRootCauseExplanation).Trim() -split '\s+' | Where-Object { $_ })
    if ($detailWords.Count -gt 50) { throw "CE DRC explanation exceeds 50 words for $IncidentNumber." }
    if ($category -eq 'Excluded' -and [string]::IsNullOrWhiteSpace([string]$result.ExclusionReason)) {
        throw "Missing exclusion reason for $IncidentNumber."
    }
    return $result
}

# -------- Per-partition existing-row cache --------
$existingByPartition = @{}
function Get-ExistingRowsByKey {
    param([string]$Partition)
    if ($existingByPartition.ContainsKey($Partition)) { return $existingByPartition[$Partition] }
    $map = @{}
    try {
        $rows = Get-AzTableRow -Table $cloudTable -PartitionKey $Partition -ErrorAction Stop
        foreach ($r in @($rows)) { if ($r.RowKey) { $map[[string]$r.RowKey] = $r } }
    } catch {
        Write-Warning "Could not load existing keys for ${Partition}: $($_.Exception.Message)"
    }
    $existingByPartition[$Partition] = $map
    return $map
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
        throw "ServiceNow fetch failed for ${startStr}: $($_.Exception.Message)"
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
        max_completion_tokens = 2600
    } | ConvertTo-Json -Depth 10 -Compress
    $url = "$($cfg.AzureOpenAIBaseUrl)/openai/deployments/$($cfg.AzureOpenAIDeployment)/chat/completions?api-version=$($cfg.AzureOpenAIApiVersion)"
    $headers = @{ 'api-key' = $cfg.AzureOpenAIApiKey; 'Content-Type' = 'application/json' }
        $resp = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 180
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

function Get-YearWeekFromDate {
    param([DateTime]$Date)
    $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
    $wn  = $cal.GetWeekOfYear($Date, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
    $isoYear = $Date.Year
    if ($Date.Month -eq 1 -and $wn -ge 52) { $isoYear = $Date.Year - 1 }
    elseif ($Date.Month -eq 12 -and $wn -eq 1) { $isoYear = $Date.Year + 1 }
    return [PSCustomObject]@{
        Year       = $isoYear
        WeekNumber = $wn
        YearWeek   = ('{0:D4}-W{1:D2}' -f $isoYear, $wn)
    }
}

# -------- Main loop --------
Write-Step 'Fetching ServiceNow token...' 'Yellow'
$snToken = Get-ServiceNowToken

$today = (Get-Date).ToUniversalTime().Date
$dateFormat = [Globalization.CultureInfo]::InvariantCulture
if ($StartDate -or $EndDate) {
    if (-not $StartDate -or -not $EndDate) { throw 'StartDate and EndDate must be provided together in yyyy-MM-dd format.' }
    $rangeStart = [DateTime]::ParseExact($StartDate,'yyyy-MM-dd',$dateFormat).Date
    $rangeEnd = [DateTime]::ParseExact($EndDate,'yyyy-MM-dd',$dateFormat).Date
    if ($rangeEnd -lt $rangeStart) { throw 'EndDate must be on or after StartDate.' }
} else {
    $rangeEnd = $today.AddDays(-1)
    $rangeStart = $today.AddDays(-1 * $LookbackDays)
}
$dateCount = ($rangeEnd - $rangeStart).Days + 1
$summary = @{}
$totalFetched = 0; $totalSaved = 0; $totalErrors = 0; $totalSkipped = 0; $totalWouldSave = 0

$dayIndex = 0
for ($day = $rangeStart; $day -le $rangeEnd; $day = $day.AddDays(1)) {
    $dayIndex++
    $key = $day.ToString('yyyy-MM-dd')
    Write-Step "Day $dayIndex/$dateCount - $key" 'Cyan'

    $incidents = Get-IncidentsForDay -Token $snToken -DayUtc $day
    Write-Output "  Fetched $($incidents.Count) incidents."
    $summary[$key] = @{ fetched = $incidents.Count; saved = 0; errors = 0; skipped = 0; wouldSave = 0 }

    if ($incidents.Count -eq 0) { continue }
    if ($MaxPerDay -gt 0 -and $incidents.Count -gt $MaxPerDay) {
        $incidents = $incidents | Select-Object -First $MaxPerDay
    }

    foreach ($inc in $incidents) {
      try {
        $num = [string]$inc.number
        if ([string]::IsNullOrWhiteSpace($num)) { continue }
        if ($IncidentNumbers.Count -gt 0 -and $num -notin $IncidentNumbers) {
            $summary[$key].skipped++
            continue
        }

        $resolvedDt = $day
        $resolvedStr = [string]$inc.resolved_at
        if (-not [string]::IsNullOrWhiteSpace($resolvedStr)) {
            [DateTime]$tmp = [DateTime]::MinValue
            if ([DateTime]::TryParse($resolvedStr, [ref]$tmp)) { $resolvedDt = $tmp }
        }
        if (($StartDate -or $EndDate) -and ($resolvedDt.Date -lt $rangeStart -or $resolvedDt.Date -gt $rangeEnd)) {
            $summary[$key].skipped++
            continue
        }
        $yw = Get-YearWeekFromDate -Date $resolvedDt

        # Skip only when an existing row is complete and usable.
        $existingRows = Get-ExistingRowsByKey -Partition $yw.YearWeek
        if (-not $ForceReanalyze -and $existingRows.ContainsKey($num)) {
            $existingRow = $existingRows[$num]
            $hasAnalysis = -not [string]::IsNullOrWhiteSpace([string]$existingRow.AIAnalysis)
            $hasProblemData = (-not [string]::IsNullOrWhiteSpace([string]$existingRow.Subcategory)) -or (-not [string]::IsNullOrWhiteSpace([string]$existingRow.OriginalDescription))
            $existingRoot = [string]$existingRow.PossibleRootCause
            $hasUsableCategory = -not [string]::IsNullOrWhiteSpace([string]$existingRow.Category) -and [string]$existingRow.Category -notmatch '^(?i:unknown(?:\s*/\s*unclear)?)$'
            $hasUsableRoot = -not [string]::IsNullOrWhiteSpace($existingRoot) -and $existingRoot -notmatch '^(?i:unknown(?:\s*/\s*unclear)?|root cause undetermined)$'
            if ($hasAnalysis -and $hasProblemData -and $hasUsableCategory -and $hasUsableRoot) {
                $summary[$key].skipped++
                continue
            }
        }

        try {
            $aiText  = Invoke-Categorize -Incident $inc
            $fields  = ConvertFrom-ValidatedClassification -Text $aiText -IncidentNumber $num
            $category = [string]$fields.PrimaryCategory
            $subcat = [string]$fields.SubCategory
            $root = [string]$fields.PossibleRootCause
            $shortDrc = [string]$fields.DetailedRootCause
            $anal = @(
                'Problem:',
                "Issue: $($fields.Issue)",
                "Root Cause: $($fields.RootCauseNarrative)",
                "Resolution: $($fields.Resolution)",
                "Evidence: $($fields.Evidence)",
                '',
                "AI Analysis ($($fields.Confidence) confidence): $($fields.AIAnalysis)"
            ) -join "`n"
            $conf = [string]$fields.Confidence

            $props = @{
                'Category'           = [string]$category
                'Subcategory'        = [string]$subcat
                # Preserve canonical PossibleRootCause for downstream canonical lookups
                'PossibleRootCause'  = [string]$root
                'DetailedRootCause'  = [string]$shortDrc
                'DetailedRootCauseExplanation' = [string]$fields.DetailedRootCauseExplanation
                'Resolution'         = [string]$fields.Resolution
                'Evidence'           = [string]$fields.Evidence
                'RootCause'          = [string]$root
                'AIAnalysis'         = [string]$anal
                'Confidence'         = [string]$conf
                'HDI'                = [bool]($fields.HDI -eq 'Yes')
                'ExclusionReason'    = [string]$fields.ExclusionReason
                'References'         = [string](@($fields.References) -join ', ')
                'Date'               = [string]$resolvedDt.ToString('yyyy-MM-dd')
                'YearWeek'           = [string]$yw.YearWeek
                'Year'               = [int]$yw.Year
                'WeekNumber'         = [int]$yw.WeekNumber
                'Service'            = 'Content Engineering'
                'Misrouted'          = [bool]($category -eq 'Excluded')
                'OriginalDescription'= [string]$inc.short_description
                'ReportBlobName'     = 'incremental-runbook'
            }
            if ($DryRun) {
                $summary[$key].wouldSave++
                Write-Output ("  DRY  {0,-15} {1,-9} {2}" -f $num, $yw.YearWeek, $category)
                continue
            }
            Add-AzTableRow -Table $cloudTable -PartitionKey $yw.YearWeek -RowKey $num -Property $props -UpdateExisting -ErrorAction Stop | Out-Null

            # Cache update so same-incident appearances in this run are treated as complete.
            $existingRows[[string]$num] = [pscustomobject]@{
                RowKey = [string]$num
                AIAnalysis = [string]$anal
                Subcategory = [string]$subcat
                OriginalDescription = [string]$inc.short_description
            }
            Write-Output ("  OK   {0,-15} {1,-9} {2}" -f $num, $yw.YearWeek, $category)
            $summary[$key].saved++
        } catch {
            Write-Warning "  FAIL ${num}: $($_.Exception.Message)"
            $summary[$key].errors++
        }
      } catch {
          Write-Warning "  OUTER FAIL $($inc.number): $($_.Exception.Message)"
          $summary[$key].errors++
      }
    }
}

# -------- Summary --------
Write-Output ''
Write-Step '=== Incremental backfill summary ===' 'Magenta'
$summary.Keys | Sort-Object | ForEach-Object {
    $s = $summary[$_]
    Write-Output ("  {0}  fetched={1,3}  saved={2,3}  wouldSave={3,3}  skipped={4,3}  errors={5,3}" -f $_, $s.fetched, $s.saved, $s.wouldSave, $s.skipped, $s.errors)
    $totalFetched += $s.fetched; $totalSaved += $s.saved; $totalSkipped += $s.skipped; $totalErrors += $s.errors
    $totalWouldSave += $s.wouldSave
}
Write-Output ("  -----------------------------------------------------------------")
Write-Output ("  TOTAL       fetched={0,3}  saved={1,3}  wouldSave={2,3}  skipped={3,3}  errors={4,3}" -f $totalFetched, $totalSaved, $totalWouldSave, $totalSkipped, $totalErrors)
if ($DryRun) { Write-Output 'Dry run complete; no table rows were written.' }
Write-Output ''
Write-Output "Rows newly written: $totalSaved (skipped $totalSkipped already in table)"
