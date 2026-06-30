<#
.SYNOPSIS
    Fetch incidents missing from a given YearWeek partition in the table, by querying
    ServiceNow for all incidents resolved in that week and inserting any that are absent.

.DESCRIPTION
    1. Computes Monday-Sunday date range for the specified YearWeek.
    2. Queries ServiceNow for ALL Productivity Tools incidents resolved that week.
    3. Queries the IncidentsCategoryStats table for rows already present in that partition.
    4. Inserts (InsertOrMerge) only the missing ones with placeholder analysis.
    Run fix_ai_analysis_by_week.ps1 afterwards to populate real AI analysis.

.USAGE
    .\tools\fetch_and_populate_ww26_missing.ps1 [-YearWeek '2026-W26'] [-DryRun]
    .\tools\fetch_and_populate_ww26_missing.ps1 -YearWeek '2026-W27'

#>

param(
    [string]$YearWeek = '2026-W26',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $ScriptDir "..")

$configPath  = ".\Config\LocalConfig-ProductivityTools.psd1"
$secretsPath = ".\Config\LocalSecrets-ProductivityTools.psd1"

if (-not (Test-Path $configPath)) { 
    Write-Host "ERROR: $configPath not found" -ForegroundColor Red
    exit 1 
}

$LocalConfig = Import-PowerShellDataFile -Path $configPath
if (Test-Path $secretsPath) { 
    $secrets = Import-PowerShellDataFile -Path $secretsPath
    foreach ($k in $secrets.Keys) { $LocalConfig[$k] = $secrets[$k] }
}

$StorageAccountName  = $LocalConfig.PSD_AI_Automations_StorageAccountName
$ResourceGroup       = $LocalConfig.PSD_AI_Automations_ResourceGroupName
$SubscriptionId      = $LocalConfig.Incidents_analyzer_SubscriptionId
$TableName           = 'IncidentsCategoryStats'
$BusinessServiceId   = 'a1de2ff2db8f50108062531dd3961911'
$ServiceOfferingId   = 'fcb18407dbcf50108062531dd39619c4'

# --- Compute date range for the YearWeek (ISO: Monday to Sunday) ---
$wMatch = [regex]::Match($YearWeek, '^(\d{4})-W(\d{1,2})$')
if (-not $wMatch.Success) { Write-Host "ERROR: Invalid YearWeek '$YearWeek'. Expected format: 2026-W26" -ForegroundColor Red; exit 1 }
$yr  = [int]$wMatch.Groups[1].Value
$wk  = [int]$wMatch.Groups[2].Value
$jan4 = [datetime]::new($yr, 1, 4)
$mondayWeek1 = $jan4.AddDays(-1 * (([int]$jan4.DayOfWeek + 6) % 7))
$weekStart = $mondayWeek1.AddDays(($wk - 1) * 7)
$weekEnd   = $weekStart.AddDays(6)

Write-Host ""
Write-Host "====== FETCH MISSING $YearWeek INCIDENTS ======" -ForegroundColor Cyan
Write-Host "Date range: $($weekStart.ToString('yyyy-MM-dd')) (Mon) to $($weekEnd.ToString('yyyy-MM-dd')) (Sun)"
Write-Host ""

# Connect to Azure
Write-Host "[1/4] Connecting to Azure..." -ForegroundColor Cyan
try {
    Connect-AzAccount -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    Write-Host "      SUCCESS" -ForegroundColor Green
} catch {
    Write-Host "      ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize table
Write-Host "[2/4] Initializing table storage..." -ForegroundColor Cyan
try {
    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccountName -ErrorAction Stop)[0].Value
    Add-Type -AssemblyName 'Microsoft.WindowsAzure.Storage' -ErrorAction Stop
    $connectionString = 'DefaultEndpointsProtocol=https;AccountName={0};AccountKey={1};EndpointSuffix=core.windows.net' -f $StorageAccountName, $storageKey
    $cloudTable = [Microsoft.WindowsAzure.Storage.CloudStorageAccount]::Parse($connectionString).CreateCloudTableClient().GetTableReference($TableName)
    Write-Host "      SUCCESS" -ForegroundColor Green
} catch {
    Write-Host "      ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Fetch ServiceNow token
Write-Host "[3/4] Getting ServiceNow authentication token..." -ForegroundColor Cyan
try {
    $snBody = @{
        grant_type    = 'client_credentials'
        client_id     = $LocalConfig.ServiceNowIncidentsClientID
        client_secret = $LocalConfig.ServiceNowIncidentsClientSecret
        scope         = $LocalConfig.ServiceNowIncidentsScope
    }
    $snToken = (Invoke-RestMethod -Method Post -Uri $LocalConfig.TokenUrl -Body $snBody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop).access_token
    Write-Host "      SUCCESS" -ForegroundColor Green
} catch {
    Write-Host "      ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Step A: Query ServiceNow for ALL incidents resolved in this week ---
Write-Host "[4/4] Querying ServiceNow for all $YearWeek incidents and inserting missing..." -ForegroundColor Cyan

$startStr = $weekStart.ToString('yyyy-MM-dd') + ' 00:00:00'
$endStr   = $weekEnd.ToString('yyyy-MM-dd')   + ' 23:59:59'
$snQuery  = "business_service=$BusinessServiceId^service_offering=$ServiceOfferingId^stateIN6,7^resolved_at>=$startStr^resolved_at<=$endStr"
$snUrl    = 'https://apis.intel.com/itsm/api/now/table/incident?sysparm_query={0}&sysparm_display_value=true&sysparm_limit=1000' -f [uri]::EscapeDataString($snQuery)

try {
    $snResp     = Invoke-RestMethod -Method Get -Uri $snUrl -Headers @{ Authorization = "Bearer $snToken" } -ErrorAction Stop
    $snIncidents = @($snResp.result)
    Write-Host "      ServiceNow returned: $($snIncidents.Count) incidents for $YearWeek" -ForegroundColor White
} catch {
    Write-Host "      ERROR querying ServiceNow: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Step B: Get existing row keys from the table partition ---
$existingRowKeys = @{}
try {
    $partFilter = [Microsoft.WindowsAzure.Storage.Table.TableQuery]::GenerateFilterCondition(
        'PartitionKey', [Microsoft.WindowsAzure.Storage.Table.QueryComparisons]::Equal, $YearWeek
    )
    $tq = [Microsoft.WindowsAzure.Storage.Table.TableQuery]::new()
    $tq.FilterString = $partFilter
    $contToken = $null
    do {
        $seg = $cloudTable.ExecuteQuerySegmentedAsync($tq, $contToken).GetAwaiter().GetResult()
        foreach ($r in $seg.Results) { $existingRowKeys[$r.RowKey] = $true }
        $contToken = $seg.ContinuationToken
    } while ($null -ne $contToken)
    Write-Host "      Already in table ($YearWeek): $($existingRowKeys.Count) incidents" -ForegroundColor White
} catch {
    Write-Host "      WARN: Could not query table partition: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- Step C: Filter to only missing incidents ---
$missingIncidents = @($snIncidents | Where-Object {
    $_.number -and -not $existingRowKeys.ContainsKey([string]$_.number)
})
Write-Host "      Missing (to insert): $($missingIncidents.Count) incidents" -ForegroundColor $(if ($missingIncidents.Count -gt 0) { 'Yellow' } else { 'Green' })

if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN - would insert these $($missingIncidents.Count) incidents:" -ForegroundColor Yellow
    $missingIncidents | ForEach-Object { Write-Host "  $($_.number)  resolved=$($_.resolved_at)" -ForegroundColor Gray }
    exit 0
}

if ($missingIncidents.Count -eq 0) {
    Write-Host "      Nothing to insert - all ServiceNow incidents already in table." -ForegroundColor Green
    exit 0
}

# --- Step D: Insert each missing incident with placeholder analysis ---
$insertCount = 0
$errorCount  = 0

foreach ($inc in $missingIncidents) {
    try {
        $incNum = [string]$inc.number

        # Resolve date
        $resolvedRaw = if ($inc.resolved_at) { [string]$inc.resolved_at } `
                       elseif ($inc.closed_at) { [string]$inc.closed_at } `
                       else { [string]$inc.opened_at }
        # resolved_at with display_value=true may be "MM/dd/yyyy HH:mm:ss" or "yyyy-MM-dd HH:mm:ss"
        $resolvedDate = $null
        [datetime]$tmp = [datetime]::MinValue
        if ([datetime]::TryParse($resolvedRaw, [ref]$tmp)) { $resolvedDate = $tmp }
        if (-not $resolvedDate) { $resolvedDate = $weekStart }

        # Compute exact YearWeek for this incident (in case resolved_at crosses week boundary)
        $jan4r      = [datetime]::new($resolvedDate.Year, 1, 4)
        $mon1r      = $jan4r.AddDays(-1 * (([int]$jan4r.DayOfWeek + 6) % 7))
        $incWkNum   = [int][Math]::Floor(($resolvedDate - $mon1r).TotalDays / 7) + 1
        $incYW      = '{0}-W{1:D2}' -f $resolvedDate.Year, $incWkNum

        # Build entity using EntityProperty (correct SDK pattern)
        $entity = [Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity]::new($incYW, $incNum)
        $ep = [Microsoft.WindowsAzure.Storage.Table.EntityProperty]
        $entity.Properties['Category']       = $ep::GeneratePropertyForString('Unknown')
        $entity.Properties['Subcategory']    = $ep::GeneratePropertyForString('Other / Miscellaneous')
        $entity.Properties['RootCause']      = $ep::GeneratePropertyForString('')
        $entity.Properties['AIAnalysis']     = $ep::GeneratePropertyForString('Pending AI analysis. Run fix_ai_analysis_by_week.ps1 to generate detailed AI analysis.')
        $entity.Properties['Confidence']     = $ep::GeneratePropertyForString('Low')
        $entity.Properties['Date']           = $ep::GeneratePropertyForString($resolvedDate.ToString('yyyy-MM-dd'))
        $entity.Properties['YearWeek']       = $ep::GeneratePropertyForString($incYW)
        $entity.Properties['Year']           = $ep::GeneratePropertyForInt($resolvedDate.Year)
        $entity.Properties['WeekNumber']     = $ep::GeneratePropertyForInt($incWkNum)
        $entity.Properties['ReportBlobName'] = $ep::GeneratePropertyForString('batch-fetch-missing')

        $op = [Microsoft.WindowsAzure.Storage.Table.TableOperation]::InsertOrMerge($entity)
        $cloudTable.ExecuteAsync($op).GetAwaiter().GetResult() | Out-Null

        $insertCount++
        Write-Host "      Inserted: $incNum  ($incYW  $($resolvedDate.ToString('yyyy-MM-dd')))" -ForegroundColor Gray
    } catch {
        $errorCount++
        Write-Host "      ERROR: $($inc.number) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "====== SUMMARY ======" -ForegroundColor Cyan
Write-Host "ServiceNow total : $($snIncidents.Count)"
Write-Host "Already in table : $($existingRowKeys.Count)"
Write-Host "Newly inserted   : $insertCount" -ForegroundColor Green
if ($errorCount -gt 0) { Write-Host "Errors           : $errorCount" -ForegroundColor Red }
Write-Host ""
Write-Host "Next step - run AI analysis for all $YearWeek incidents:" -ForegroundColor Yellow
Write-Host "  .\tools\fix_ai_analysis_by_week.ps1 -StartYearWeek '$YearWeek' -EndYearWeek '$YearWeek' -ForceRealAI"
Write-Host ""
