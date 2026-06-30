<#
.SYNOPSIS
    Re-run AI categorization for incidents in a specified YearWeek range and
    update the IncidentsCategoryStats table with corrected AI Analysis/PRC/DRC.

.NOTES
    Top-of-file configuration (required):
      - ServiceOfferingId: ServiceNow service offering identifier to scope fetches
      - StartYearWeek:     First YearWeek to process (e.g. 2026-W25)
      - EndYearWeek:       Last YearWeek to process  (e.g. 2026-W26)

    Usage example:
      .\tools\fix_ai_analysis_by_week.ps1 -ServiceOfferingId 'fcb18407dbcf50108062531dd39619c4' -StartYearWeek '2026-W25' -EndYearWeek '2026-W26'

    This script follows repository policy: it does not modify the canonical
    runbooks and instead calls AI and updates the results table directly.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)][string]$ServiceOfferingId = '',
    [Parameter(Mandatory=$true)][string]$StartYearWeek,
    [Parameter(Mandatory=$true)][string]$EndYearWeek,
    [int]$MaxPerWeek = 0,
    [switch]$UseLocalInput,
    [switch]$DryRun,
    [switch]$ForceRealAI,
    [switch]$OnlyPending  # Only process incidents whose AIAnalysis contains 'Pending' (skip already-analyzed)
)

Set-StrictMode -Version Latest

# Define logging functions early
function Write-Info { param($m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Warn { param($m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "[ERR]  $m" -ForegroundColor Red }

# Load local configuration + secrets (same pattern as runbooks)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $ScriptDir
$configPath  = "..\Config\LocalConfig-ProductivityTools.psd1"
$secretsPath = "..\Config\LocalSecrets-ProductivityTools.psd1"
if (-not (Test-Path $configPath)) { throw "$configPath not found - create it for local runs." }
$LocalConfig = Import-PowerShellDataFile -Path $configPath
if (Test-Path $secretsPath) { $secrets = Import-PowerShellDataFile -Path $secretsPath; foreach ($k in $secrets.Keys) { $LocalConfig[$k] = $secrets[$k] } }

# Resolve credentials: prefer LocalConfig, then env vars, then optional Key Vault
try {
    # Azure OpenAI API Key
    $AzureOpenAIApiKey = $null
    if ($LocalConfig.PSObject.Properties.Name -contains 'AzureOpenAIApiKey' -and -not [string]::IsNullOrWhiteSpace($LocalConfig.AzureOpenAIApiKey)) {
        $AzureOpenAIApiKey = $LocalConfig.AzureOpenAIApiKey
        Write-Info 'Azure OpenAI key loaded from LocalConfig'
    } elseif ($env:AZURE_OPENAI_APIKEY) {
        $AzureOpenAIApiKey = $env:AZURE_OPENAI_APIKEY
        Write-Info 'Azure OpenAI key loaded from environment variable'
    } elseif ($LocalConfig.PSObject.Properties.Name -contains 'KeyVaultName' -and $LocalConfig.PSObject.Properties.Name -contains 'AzureOpenAIKeySecretName') {
        try {
            Write-Info 'Attempting to retrieve Azure OpenAI key from Key Vault'
            $secret = Get-AzKeyVaultSecret -VaultName $LocalConfig.KeyVaultName -Name $LocalConfig.AzureOpenAIKeySecretName -ErrorAction Stop
            $AzureOpenAIApiKey = $secret.SecretValueText
            Write-Info 'Azure OpenAI key retrieved from Key Vault'
        } catch {
            Write-Warn 'Failed to retrieve Azure OpenAI key from Key Vault; proceeding without it.'
        }
    }

    # ServiceNow client secret
    if (($LocalConfig.PSObject.Properties.Name -contains 'ServiceNowIncidentsClientSecret') -and -not [string]::IsNullOrWhiteSpace($LocalConfig.ServiceNowIncidentsClientSecret)) {
        $ServiceNowClientSecret = $LocalConfig.ServiceNowIncidentsClientSecret
        Write-Info 'ServiceNow client secret loaded from LocalConfig'
    } elseif ($env:SERVICENOW_CLIENT_SECRET) {
        $ServiceNowClientSecret = $env:SERVICENOW_CLIENT_SECRET
        Write-Info 'ServiceNow client secret loaded from environment variable'
    } elseif ($LocalConfig.PSObject.Properties.Name -contains 'KeyVaultName' -and $LocalConfig.PSObject.Properties.Name -contains 'ServiceNowClientSecretName') {
        try {
            Write-Info 'Attempting to retrieve ServiceNow client secret from Key Vault'
            $s = Get-AzKeyVaultSecret -VaultName $LocalConfig.KeyVaultName -Name $LocalConfig.ServiceNowClientSecretName -ErrorAction Stop
            $ServiceNowClientSecret = $s.SecretValueText
            Write-Info 'ServiceNow client secret retrieved from Key Vault'
        } catch {
            Write-Warn 'Failed to retrieve ServiceNow client secret from Key Vault; proceeding without it.'
        }
    }

    # Propagate resolved keys back into LocalConfig for use by other functions
    if ($AzureOpenAIApiKey) { $LocalConfig.AzureOpenAIApiKey = $AzureOpenAIApiKey }
    if ($ServiceNowClientSecret) { $LocalConfig.ServiceNowIncidentsClientSecret = $ServiceNowClientSecret }
} catch {
    Write-Warn ( 'Credential resolution failed: {0}' -f $_.Exception.Message )
}
# Default ServiceOfferingId if not provided on command-line
if ([string]::IsNullOrWhiteSpace($ServiceOfferingId)) {
    if ($LocalConfig.ContainsKey('PT_ServiceOfferingId') -and -not [string]::IsNullOrWhiteSpace($LocalConfig.PT_ServiceOfferingId)) {
        $ServiceOfferingId = $LocalConfig.PT_ServiceOfferingId
    } else {
        # legacy default used across runbooks
        $ServiceOfferingId = 'fcb18407dbcf50108062531dd39619c4'
    }
    Write-Host "[INFO] ServiceOfferingId not provided - defaulting: $ServiceOfferingId" -ForegroundColor Cyan
}

# Derived settings
$StorageAccountName = $LocalConfig.PSD_AI_Automations_StorageAccountName
$SubscriptionId     = $LocalConfig.Incidents_analyzer_SubscriptionId
$PromptContainer    = $LocalConfig.PSD_AI_Automations_PromptTemplateContainerName
$TableName          = 'IncidentsCategoryStats'

# --- Helper: ISO Week -> Date (Monday) ---
function Get-IsoWeekStartDate {
    param([int]$Year, [int]$Week)
    # ISO week algorithm: Week 1 contains Jan 4th. Find Monday of week 1 then add weeks.
    $jan4 = [datetime]::new($Year,1,4)
    $dayOfWeek = [int]$jan4.DayOfWeek
    # Convert DayOfWeek: Sunday=0..Saturday=6; Monday should be 1
    $mondayOfWeek1 = $jan4.AddDays(-1 * (($dayOfWeek + 6) % 7))
    return $mondayOfWeek1.AddDays(($Week - 1) * 7)
}

function Parse-YearWeek {
    param([string]$yw)
    if ($yw -notmatch '^(\d{4})-W(\d{1,2})$') { throw "Invalid YearWeek format: $yw" }
    return @{ Year = [int]$matches[1]; Week = [int]$matches[2] }
}

# --- Azure storage/table setup (uses Az module to retrieve key) ---
Write-Info 'Auth to Azure (managed identity or logged-in user)'
if (-not $UseLocalInput) {
    Try { Connect-AzAccount -ErrorAction Stop | Out-Null; Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null } catch { Write-Warn 'Azure login may not be available; if running locally ensure az login or provide storage key.' }
} else {
    Write-Info 'Using local incident store (dry/local mode) — skipping Azure login and table access.'
}

if (-not $UseLocalInput) {
    Write-Info ( 'Retrieving storage key for {0}' -f $StorageAccountName )
    try {
        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $LocalConfig.PSD_AI_Automations_ResourceGroupName -Name $StorageAccountName -ErrorAction Stop)[0].Value
        Add-Type -AssemblyName 'Microsoft.WindowsAzure.Storage'
        $connectionString = 'DefaultEndpointsProtocol=https;AccountName={0};AccountKey={1};EndpointSuffix=core.windows.net' -f $StorageAccountName, $storageKey
        $cloudTable = [Microsoft.WindowsAzure.Storage.CloudStorageAccount]::Parse($connectionString).CreateCloudTableClient().GetTableReference($TableName)
    } catch {
        Write-Warn ( 'Unable to retrieve storage key or initialize table client: {0}. Continuing with table writes disabled.' -f $_.Exception.Message )
        $cloudTable = $null
    }
} else {
    Write-Info 'Local mode: skipping Azure storage/table setup.'
    $cloudTable = $null
}

function Get-TableEntitiesForPartition {
    param([string]$Partition)
    $result = @()
    try {
        $partitionFilter = [Microsoft.WindowsAzure.Storage.Table.TableQuery]::GenerateFilterCondition('PartitionKey',[Microsoft.WindowsAzure.Storage.Table.QueryComparisons]::Equal,$Partition)
        $query = [Microsoft.WindowsAzure.Storage.Table.TableQuery]::new()
        $query.FilterString = $partitionFilter
        $token = $null
        do {
            $segment = $cloudTable.ExecuteQuerySegmentedAsync($query, $token).GetAwaiter().GetResult()
            $result += $segment.Results
            $token = $segment.ContinuationToken
        } while ($null -ne $token)
    } catch {
        Write-Warn ( 'Failed to query table for partition {0}: {1}' -f $Partition, $_.Exception.Message )
    }
    return $result
}

# --- ServiceNow helpers ---
function Get-ServiceNowToken {
    $body = @{ grant_type='client_credentials'; client_id=$LocalConfig.ServiceNowIncidentsClientID; client_secret=$LocalConfig.ServiceNowIncidentsClientSecret; scope=$LocalConfig.ServiceNowIncidentsScope }
    try { return (Invoke-RestMethod -Method Post -Uri $LocalConfig.TokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop).access_token } catch { throw "ServiceNow token failed: $($_.Exception.Message)" }
}

function Get-IncidentByNumber {
    param([string]$Number, [string]$Token)
    $q = "number=$Number"
    $url = 'https://apis.intel.com/itsm/api/now/table/incident?sysparm_query={0}&sysparm_display_value=true&sysparm_limit=1' -f [uri]::EscapeDataString($q)
    try { $resp = Invoke-RestMethod -Method Get -Uri $url -Headers @{ Authorization = "Bearer $Token" } -ErrorAction Stop; return @($resp.result)[0] } catch { Write-Warn ( 'ServiceNow fetch failed for {0}: {1}' -f $Number, $_.Exception.Message ); return $null }
}

# --- AI invocation (uses local templates) ---
function Read-LocalTemplate { param([string]$Name) $path = Join-Path "..\templates" "$Name.md"; if (Test-Path $path) { return Get-Content -Path $path -Raw -Encoding UTF8 } else { throw "Template not found: $path" } }

# --- Canonical template parsing & coercion ---
function Load-CanonicalCatalog {
    param()
    $repoTemplates = Join-Path $ScriptDir "..\templates"
    $trendPath = Join-Path $repoTemplates 'TrendSubCategorisation_ProductivityTools.md'
    $prcPath   = Join-Path $repoTemplates 'PossibleRootCause_ProductivityTools.md'
    $catalog = [ordered]@{ Categories = @(); SubSymptoms = @{}; PRC = @{} }

    if (Test-Path $trendPath) {
        $lines = Get-Content -Path $trendPath -Raw -Encoding UTF8 -ErrorAction Stop -split "\r?\n"
        $curCategory = ''
        foreach ($ln in $lines) {
            if ($ln -match '^####\s+(.*\S)') {
                $curCategory = $matches[1].Trim()
                if (-not ($catalog.Categories -contains $curCategory)) { $catalog.Categories += $curCategory }
                if (-not $catalog.SubSymptoms.ContainsKey($curCategory)) { $catalog.SubSymptoms[$curCategory] = @() }
                continue
            }
            if ($curCategory -and $ln -match '^\*\*(.+?)\*\*') {
                $group = $matches[1].Trim()
                $catalog.SubSymptoms[$curCategory] += $group
            }
        }
    }

    if (Test-Path $prcPath) {
        $text = Get-Content -Path $prcPath -Raw -Encoding UTF8 -ErrorAction Stop
        # split by section headers like '## 1. Microsoft OneDrive Issues'
        $sections = $text -split '(?m)^##\s+' | Where-Object { $_ -match '\S' }
        foreach ($sec in $sections) {
            if ($sec -match '^(?:\d+\.\s*)?(?<cat>[^\r\n]+)') {
                $catName = $matches['cat'].Trim()
                # remove leading numbering if present
                $catName = $catName -replace '^\d+\.\s*',''
                if (-not $catalog.PRC.ContainsKey($catName)) { $catalog.PRC[$catName] = @() }
                # find bold labels **Label** in this section
                $lbls = [regex]::Matches($sec,'\*\*(.+?)\*\*') | ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ -ne '' }
                foreach ($l in $lbls) { if (-not ($catalog.PRC[$catName] -contains $l)) { $catalog.PRC[$catName] += $l } }
            }
        }
    }

    return $catalog
}

function Coerce-PrimaryCategory { param([string]$candidate, $catalog)
    if ([string]::IsNullOrWhiteSpace($candidate)) { return 'Unknown' }
    foreach ($c in $catalog.Categories) { if ($candidate.Trim().ToLowerInvariant() -eq $c.Trim().ToLowerInvariant()) { return $c } }
    # try contains match
    foreach ($c in $catalog.Categories) { if ($candidate.ToLowerInvariant().Contains($c.ToLowerInvariant().Split(' ')[0])) { return $c } }
    return 'Unknown'
}

function Coerce-SubSymptom { param([string]$category, [string]$candidate, $catalog)
    if ([string]::IsNullOrWhiteSpace($candidate)) { return 'Unknown' }
    if (-not $catalog.SubSymptoms.ContainsKey($category)) { return 'Unknown' }
    foreach ($s in $catalog.SubSymptoms[$category]) { if ($candidate.Trim().ToLowerInvariant() -eq $s.Trim().ToLowerInvariant()) { return $s } }
    # try fuzzy: if candidate contains any token from sub symptom
    foreach ($s in $catalog.SubSymptoms[$category]) { if ($s -and ($candidate.ToLowerInvariant().Split(' ') | Where-Object { $s.ToLowerInvariant().Contains($_) }).Count -gt 0) { return $s } }
    return 'Unknown'
}

function Coerce-PRC { param([string]$category, [string]$candidate, $catalog)
    if ([string]::IsNullOrWhiteSpace($candidate)) { return 'Unknown' }
    if (-not $catalog.PRC.ContainsKey($category)) { return 'Unknown' }
    foreach ($p in $catalog.PRC[$category]) { if ($candidate.Trim().ToLowerInvariant() -eq $p.Trim().ToLowerInvariant()) { return $p } }
    # try contains
    foreach ($p in $catalog.PRC[$category]) { if ($candidate.ToLowerInvariant().Contains($p.ToLowerInvariant())) { return $p } }
    return 'Unknown'
}

function Invoke-AIForIncident {
    param([object]$Incident)
    $cat = Read-LocalTemplate -Name 'TicketCategorisation_ProductivityTools'
    $env = Read-LocalTemplate -Name 'EnvironmentContext_ProductivityTools'
    $outputInstruction = @'
## REQUIRED OUTPUT FORMAT (STRICT)

You MUST end your response with exactly these five labeled lines, in this order, each on its own line, with no markdown, headers, or extra commentary after them:

Primary Category: <one of the bold category names defined above, or "Excluded">
Sub-symptom: <the most specific sub-symptom label from the matching category's bullet list, <= 80 characters>
Possible Root Cause: <one concise sentence describing the underlying technical cause>
AI Analysis: <2-3 sentence summary: what happened, what fixed it, and any notable evidence>
Confidence: <High|Medium|Low>

Rules:
- Each label must appear verbatim followed by a colon.
- Use plain ASCII. No bullets, asterisks, or quotation marks around the values.
- If unknown, write "Unknown".
- Keep each value on a single line.
'@
    $systemPrompt = $cat + "`n`n" + $env + $outputInstruction

    $workNotes = [string]$Incident.work_notes; if ($workNotes.Length -gt 3000) { $workNotes = $workNotes.Substring(0,3000) + '... [truncated]' }
    $closeNotes = [string]$Incident.close_notes; if ($closeNotes.Length -gt 1500) { $closeNotes = $closeNotes.Substring(0,1500) + '... [truncated]' }
    # Build compact payload to avoid oversized requests
    $payload = [PSCustomObject]@{
        IncidentNumber = $Incident.number
        Description     = ([string]$Incident.description).Trim()
        ShortDescription= ([string]$Incident.short_description).Trim()
        WorkNotes       = $workNotes
        CloseNotes      = $closeNotes
        CloseCode       = ([string]$Incident.close_code)
        ResolutionCategory = if ($Incident.u_resolution_category -and $Incident.u_resolution_category.display_value) { [string]$Incident.u_resolution_category.display_value } else { '' }
        BusinessService    = if ($Incident.business_service -and $Incident.business_service.display_value) { [string]$Incident.business_service.display_value } else { '' }
        CommentsAndWorkNotes = if ($Incident.comments_and_work_notes) { ($Incident.comments_and_work_notes -split "\r?\n" | Select-Object -First 20) -join '`n' } else { '' }
        OpenedAt        = [string]$Incident.opened_at
        ResolvedAt      = [string]$Incident.resolved_at
    }
    $incidentJson = $payload | ConvertTo-Json -Depth 4 -Compress

    $maxTokens = 800
    $body = [PSCustomObject]@{
        messages = @(
            @{ role='system'; content=$systemPrompt },
            @{ role='user'; content=$incidentJson }
        ); max_completion_tokens=$maxTokens
    } | ConvertTo-Json -Depth 10 -Compress

    if ($DryRun -and -not $ForceRealAI) {
        # DryRun without forcing real AI: use fake local heuristic
        return Invoke-FakeAI -Incident $Incident
    }
    if ([string]::IsNullOrWhiteSpace($LocalConfig.AzureOpenAIApiKey)) {
        throw 'AzureOpenAIApiKey is not set in LocalConfig-ProductivityTools.psd1. Set the key or remove -ForceRealAI to run in DryRun with the fake heuristic.'
    }
    $url = "$($LocalConfig.AzureOpenAIBaseUrl)/openai/deployments/$($LocalConfig.AzureOpenAIDeployment)/chat/completions?api-version=$($LocalConfig.AzureOpenAIApiVersion)"
    $headers = @{ 'api-key' = $LocalConfig.AzureOpenAIApiKey; 'Content-Type' = 'application/json' }
    try {
        $resp = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body -TimeoutSec 180
        return $resp.choices[0].message.content
    } catch {
        $err = $_.Exception
        $detail = $err.Message
        try { $detailResponse = $err.Response.Content.ReadAsStringAsync().Result; if ($detailResponse) { $detail = $detail + " | Response: " + $detailResponse } } catch {}
        throw $detail
    }
}

# Simple heuristic-based 'fake' AI for dry runs: extracts fields from incident JSON
function Invoke-FakeAI { param([object]$Incident)
    $rc = 'Unknown'
    if ($Incident.u_resolution_category -and $Incident.u_resolution_category.display_value) { $rc = [string]$Incident.u_resolution_category.display_value }
    elseif ($Incident.business_service -and $Incident.business_service.display_value) { $rc = [string]$Incident.business_service.display_value }
    if ($rc -match '\s-\s') { $rc = ($rc -split '\s-\s')[0].Trim() }

    $sub = 'Unknown'
    if ($null -ne $Incident.subcategory -and -not [string]::IsNullOrWhiteSpace([string]$Incident.subcategory)) { $sub = [string]$Incident.subcategory }

    $root = 'Unknown'
    if ($Incident.close_notes) { $root = (($Incident.close_notes -split '\r?\n' | Where-Object { $_ -match '\w' } | Select-Object -First 1) -join ' ').Trim() }
    if (($root -eq 'Unknown' -or [string]::IsNullOrWhiteSpace($root)) -and $Incident.comments_and_work_notes) { $root = (($Incident.comments_and_work_notes -split '\r?\n' | Where-Object { $_ -match '\w' } | Select-Object -First 1) -join ' ').Trim() }

    $analysis = 'No meaningful work notes available.'
    if ($Incident.comments_and_work_notes) { $analysis = (($Incident.comments_and_work_notes -split '\r?\n' | Where-Object { $_ -match '\w' } | Select-Object -First 2) -join ' ').Trim() }

    $confidence = 'Medium'
    if ($Incident.close_notes -or ($Incident.u_resolution_category -and $Incident.u_resolution_category.display_value)) { $confidence = 'High' }

    $out = "Primary Category: $rc`nSub-symptom: $sub`nPossible Root Cause: $root`nAI Analysis: $analysis`nConfidence: $confidence"
    return $out
}

# --- Field parsing (copied from canonical runbook) ---
function Get-FieldFromResponse { param([string]$Text, [string[]]$Labels, [string[]]$StopLabels)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $escapedLabels = @()
    foreach ($l in $Labels) { $escapedLabels += [regex]::Escape($l) }
    $labelAlt = $escapedLabels -join '|'
    $escapedStops = @()
    foreach ($s in $StopLabels) { $escapedStops += [regex]::Escape($s) }
    $stopAlt = $escapedStops -join '|'
    $pattern = "(?im)^\s*\*{0,2}(?:$labelAlt)\*{0,2}\s*[:\-]\s*(.+?)\s*(?=\r?\n\s*\*{0,2}(?:$stopAlt)\*{0,2}\s*[:\-]|\Z)"
    if ($Text -match $pattern) { $val = $matches[1]; $val = [regex]::Replace($val, '\r?\n', ' '); $val = $val.Trim() -replace '\*+', ''; return $val.Trim() }
    return ''
}

# Return YearWeek string for a given date (object with YearWeek property to match callers)
function Get-YearWeekFromDate { param([datetime]$Date)
    $d = $Date.Date
    $year = $d.Year
    $jan1 = (Get-Date -Year $year -Month 1 -Day 1).Date
    $week1Sun = $jan1.AddDays(-1 * [int]$jan1.DayOfWeek)
    $days = [math]::Floor(($d - $week1Sun).TotalDays)
    $wk = [int]([math]::Floor($days / 7) + 1)
    return [PSCustomObject]@{ YearWeek = ('{0}-W{1:00}' -f $year, $wk) }
}

function Get-StructuredFields { param([string]$Text)
    $All = @('Primary Category','Sub-symptom','Subcategory','Sub symptom','Possible Root Cause','Root Cause','AI Analysis','Analysis','Confidence')
    return [PSCustomObject]@{
        Category = (Get-FieldFromResponse -Text $Text -Labels @('Primary Category') -StopLabels $All)
        Subcategory = (Get-FieldFromResponse -Text $Text -Labels @('Sub-symptom','Subcategory','Sub symptom') -StopLabels $All)
        RootCause = (Get-FieldFromResponse -Text $Text -Labels @('Possible Root Cause','Root Cause') -StopLabels $All)
        Confidence = (Get-FieldFromResponse -Text $Text -Labels @('Confidence','Confidence Level') -StopLabels $All)
        Analysis = (Get-FieldFromResponse -Text $Text -Labels @('AI Analysis','Analysis') -StopLabels $All)
    }
}

function Set-CloudTableEntity {
    param($Table, [string]$PartitionKey, [string]$RowKey, [hashtable]$Properties)
    if (-not $Table) { Write-Info ( 'DryRun/local mode - skipping table write for {0}/{1}' -f $PartitionKey, $RowKey ); return }
    $entity = [Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity]::new($PartitionKey, $RowKey)
    foreach ($propertyName in $Properties.Keys) {
        $value = $Properties[$propertyName]
        if ($value -is [int]) { $entity.Properties[$propertyName] = [Microsoft.WindowsAzure.Storage.Table.EntityProperty]::GeneratePropertyForInt([int]$value) }
        else { $entity.Properties[$propertyName] = [Microsoft.WindowsAzure.Storage.Table.EntityProperty]::GeneratePropertyForString([string]$value) }
    }
    $operation = [Microsoft.WindowsAzure.Storage.Table.TableOperation]::InsertOrMerge($entity)
    $Table.ExecuteAsync($operation).GetAwaiter().GetResult() | Out-Null
}

# --- Main processing loop over YearWeeks ---
$start = Parse-YearWeek -yw $StartYearWeek
$end   = Parse-YearWeek -yw $EndYearWeek
$startDate = Get-IsoWeekStartDate -Year $start.Year -Week $start.Week
$endDate   = Get-IsoWeekStartDate -Year $end.Year -Week $end.Week

Write-Info ( 'Processing YearWeeks from {0} to {1} (approx dates {2} -> {3})' -f $StartYearWeek, $EndYearWeek, $startDate.ToString('yyyy-MM-dd'), $endDate.ToString('yyyy-MM-dd') )

$snToken = Get-ServiceNowToken

$cur = $startDate
while ($cur -le $endDate) {
    $yw = (Get-YearWeekFromDate -Date $cur).YearWeek
    Write-Info ( 'Scanning table partition: {0}' -f $yw )
    if ($UseLocalInput) {
        # Load local incidents and filter by ServiceOfferingId and YearWeek
        $localPath = Join-Path $ScriptDir "..\local-input\pt_incidents_6m.json"
        if (-not (Test-Path $localPath)) { Write-Warn ( 'Local incident file not found: {0}' -f $localPath ); break }
        $ldata = Get-Content -Path $localPath -Raw | ConvertFrom-Json
        $entities = @()
        foreach ($inc in $ldata.incidents) {
            $resolved = $null
            if ($inc.resolved_at) { $resolved = [datetime]::Parse($inc.resolved_at) }
            elseif ($inc.closed_at) { $resolved = [datetime]::Parse($inc.closed_at) }
            elseif ($inc.opened_at) { $resolved = [datetime]::Parse($inc.opened_at) }
            if (-not $resolved) { continue }
            $ry = (Get-YearWeekFromDate -Date $resolved).YearWeek
            if ($ry -ne $yw) { continue }
            if ($inc.service_offering -and ($inc.service_offering.link -or $inc.service_offering.display_value)) {
                if ($inc.service_offering.link -and ($inc.service_offering.link -match $ServiceOfferingId) -or ($inc.service_offering.display_value -eq 'Productivity Tools')) {
                    $entities += [PSCustomObject]@{ RowKey = $inc.number; Incident = $inc }
                }
            }
        }
    } else {
        $entities = Get-TableEntitiesForPartition -Partition $yw
    }
    Write-Info ( '  Found {0} rows in {1}' -f $($entities.Count), $yw )
    if ($MaxPerWeek -gt 0 -and $entities.Count -gt $MaxPerWeek) { $entities = $entities | Select-Object -First $MaxPerWeek }

    foreach ($e in $entities) {
        $num = $e.RowKey
        # When -OnlyPending is set, skip incidents that already have real AI analysis
        if ($OnlyPending -and -not $UseLocalInput) {
            $curAnalysis = ''
            if ($e.Properties.ContainsKey('AIAnalysis')) { $curAnalysis = [string]$e.Properties['AIAnalysis'].StringValue }
            # Skip only if analysis exists AND is not a placeholder
            if (-not [string]::IsNullOrWhiteSpace($curAnalysis) -and $curAnalysis -notlike '*Pending*') {
                Write-Info ( '  Skipping {0} (already analyzed)' -f $num )
                continue
            }
        }
        Write-Info ( '  Reprocessing incident {0}' -f $num )
        if ($UseLocalInput) {
            $incident = $e.Incident
        } else {
            $incident = Get-IncidentByNumber -Number $num -Token $snToken
        }
        if (-not $incident) { Write-Warn ( '    Incident {0} not retrievable - skipping' -f $num ); continue }
        $aiText = ''
        try { $aiText = Invoke-AIForIncident -Incident $incident } catch { $err = $_ | Out-String; Write-Warn ( '    AI call failed for {0}: {1}' -f $num, $err.Trim() ) }
        $fields = Get-StructuredFields -Text $aiText
        $category = if ($fields.Category) { $fields.Category } else { 'Unknown' }
        $subcat = $fields.Subcategory
        $root = $fields.RootCause
        $anal = $fields.Analysis
        $conf = if ($fields.Confidence) { $fields.Confidence } else { 'Medium' }

        $props = @{
            'Category' = [string]$category; 'Subcategory' = [string]$subcat; 'RootCause' = [string]$root;
            'AIAnalysis' = [string]$anal; 'Confidence' = [string]$conf
        }
        try {
            Set-CloudTableEntity -Table $cloudTable -PartitionKey $yw -RowKey $num -Properties $props
            Write-Info ( '    Updated table for {0} ({1})' -f $num, $yw )
        } catch { Write-Warn ( '    Table update failed for {0}: {1}' -f $num, $_.Exception.Message ) }
    }

    $cur = $cur.AddDays(7)
}

Write-Info 'Processing complete.'
