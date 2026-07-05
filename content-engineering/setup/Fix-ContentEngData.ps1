<#
.SYNOPSIS
    One-shot fix script for Content Engineering data quality.

.DESCRIPTION
    1. Uploads all template files from content-engineering/templates/ to the
       opswcontentenggblob 'templates' container.
    2. Deletes the incorrect WW26/WW27 rows from IncidentsCategoryStats.
    3. Re-inserts correct rows from the locally generated
       categorised_incidents_<date>.json (no AI calls).
    4. Calls Build-WeeklyReports-ContentEng.ps1 to regenerate HTML reports.

.PARAMETER FlushWeeks
    YearWeek partition keys to flush. Default: 2026-W26 and 2026-W27.

.PARAMETER SourceJsonPath
    Absolute path to categorised_incidents_*.json. Defaults to most recent
    file under local-output\content-engineering-analysis\.

.PARAMETER SkipReports
    Skip regenerating HTML reports (table data only).

.EXAMPLE
    cd content-engineering\setup
    .\Fix-ContentEngData.ps1
    .\Fix-ContentEngData.ps1 -SkipReports
#>
[CmdletBinding()]
param(
    [string[]]$FlushWeeks     = @('2026-W26', '2026-W27'),
    [string]  $SourceJsonPath = '',
    [switch]  $SkipReports
)

$ErrorActionPreference = 'Stop'

$repoRoot           = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$templateDir        = Join-Path $repoRoot 'content-engineering\templates'
$outputDir          = Join-Path $repoRoot 'local-output\content-engineering-analysis'
$resourceGroup      = 'OPSW-Ticket-Analyzer'
$storageAccount     = 'opswcontentenggblob'
$templatesContainer = 'templates'
$tableName          = 'IncidentsCategoryStats'

function Write-Step {
    param([string]$Msg, [string]$Color = 'Cyan')
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Msg) -ForegroundColor $Color
}

# Resolve source JSON
if ([string]::IsNullOrWhiteSpace($SourceJsonPath)) {
    $candidate = Get-ChildItem -Path $outputDir -Filter 'categorised_incidents_*.json' |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $candidate) {
        throw "No categorised_incidents_*.json found in $outputDir. Run Analyze-ContentEngIncidents.ps1 first."
    }
    $SourceJsonPath = $candidate.FullName
}
if (-not (Test-Path $SourceJsonPath)) { throw "Source JSON not found: $SourceJsonPath" }

Write-Step ("Source JSON : {0}" -f $SourceJsonPath)
Write-Step ("Flush weeks : {0}" -f ($FlushWeeks -join ', '))

# Azure connection
Write-Step 'Checking Azure connection...' 'Yellow'
$azCtx = Get-AzContext -ErrorAction SilentlyContinue
if (-not $azCtx) {
    Write-Step 'Not connected - running Connect-AzAccount...' 'Yellow'
    Connect-AzAccount -ErrorAction Stop | Out-Null
}

# Storage context
Write-Step ("Connecting to storage account '{0}'..." -f $storageAccount) 'Yellow'
$saKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageAccount)[0].Value
$saCtx = New-AzStorageContext -StorageAccountName $storageAccount -StorageAccountKey $saKey

# -----------------------------------------------------------------------
# STEP 1 - Upload templates
# -----------------------------------------------------------------------
Write-Step 'STEP 1/4 - Uploading corrected templates to blob...' 'Yellow'
$tplFiles = Get-ChildItem -Path $templateDir -Filter '*.md'
foreach ($f in $tplFiles) {
    Set-AzStorageBlobContent -Container $templatesContainer -Blob $f.Name `
        -File $f.FullName -Context $saCtx -Force -ErrorAction Stop | Out-Null
    Write-Host ("  Uploaded: {0}" -f $f.Name) -ForegroundColor DarkGray
}
Write-Step ("  {0} template(s) uploaded." -f $tplFiles.Count) 'Green'

# -----------------------------------------------------------------------
# STEP 2 - Flush old rows
# -----------------------------------------------------------------------
Write-Step 'STEP 2/4 - Flushing old table rows...' 'Yellow'
if (-not (Get-Module -ListAvailable -Name AzTable)) {
    throw "AzTable module not installed. Run: Install-Module AzTable -Scope CurrentUser"
}
Import-Module AzTable -Force
$tbl        = Get-AzStorageTable -Name $tableName -Context $saCtx -ErrorAction Stop
$cloudTable = $tbl.CloudTable

$totalDeleted = 0
foreach ($week in $FlushWeeks) {
    $existing = Get-AzTableRow -Table $cloudTable -PartitionKey $week -ErrorAction SilentlyContinue
    $count = @($existing).Count
    if ($count -gt 0) {
        @($existing) | Remove-AzTableRow -Table $cloudTable -ErrorAction SilentlyContinue | Out-Null
        $totalDeleted += $count
        Write-Host ("  Deleted {0} rows for {1}" -f $count, $week) -ForegroundColor DarkGray
    } else {
        Write-Host ("  No rows found for {0} - skipped" -f $week) -ForegroundColor DarkGray
    }
}
Write-Step ("  {0} row(s) deleted." -f $totalDeleted) 'Green'

# -----------------------------------------------------------------------
# STEP 3 - Re-insert correct rows from local JSON
# -----------------------------------------------------------------------
Write-Step 'STEP 3/4 - Inserting corrected rows from local JSON...' 'Yellow'
$incidents = Get-Content -Path $SourceJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$written = 0
$skipped = 0

foreach ($inc in $incidents) {
    $weekLabel = [string]$inc.YearWeek
    if (-not ($FlushWeeks -contains $weekLabel)) { $skipped++; continue }

    $cat  = [string]$inc.ai_category
    $sub  = [string]$inc.ai_subcategory
    $rc   = if ($inc.ai_rootcause)  { [string]$inc.ai_rootcause }  else { 'Unknown' }
    $conf = if ($inc.ai_confidence) { [string]$inc.ai_confidence } else {
                if ($cat -eq 'Unknown / Unclear') { 'Low' } else { 'Medium' }
            }
    $anal  = if ($inc.ai_analysis) { [string]$inc.ai_analysis } else { '' }
    $date  = [string]($inc.resolved_at -replace ' ', 'T')
    $year  = $weekLabel -replace '-W\d+', ''
    $wkNum = ($weekLabel -split '-W')[1]

    $row = @{
        Category       = $cat
        Subcategory    = $sub
        RootCause      = $rc
        Confidence     = $conf
        AIAnalysis     = $anal
        Date           = $date
        YearWeek       = $weekLabel
        Year           = $year
        WeekNumber     = $wkNum
        ReportBlobName = 'local-fix-script'
    }
    Add-AzTableRow -Table $cloudTable `
        -PartitionKey $weekLabel -RowKey ([string]$inc.number) `
        -Property $row -ErrorAction Stop | Out-Null
    $written++
}
Write-Step ("{0} row(s) inserted, {1} incident(s) outside target weeks." -f $written, $skipped) 'Green'

# -----------------------------------------------------------------------
# STEP 4 - Rebuild HTML reports
# -----------------------------------------------------------------------
if ($SkipReports) {
    Write-Step 'STEP 4/4 - Skipped (SkipReports flag set).' 'Yellow'
} else {
    Write-Step 'STEP 4/4 - Rebuilding HTML reports for target weeks...' 'Yellow'
    $reportScript = Join-Path $PSScriptRoot 'Build-WeeklyReports-ContentEng.ps1'
    if (-not (Test-Path $reportScript)) {
        throw ("Build-WeeklyReports-ContentEng.ps1 not found at {0}" -f $reportScript)
    }
    & $reportScript -OnlyWeeks $FlushWeeks -ResourceGroup $resourceGroup -StorageAccount $storageAccount
    Write-Step 'HTML reports rebuilt and uploaded.' 'Green'
}

Write-Step '' 'White'
Write-Step '=== Fix-ContentEngData complete ===' 'Yellow'
Write-Step ("Table rows written   : {0}" -f $written) 'White'
Write-Step ("Templates uploaded   : {0}" -f $tplFiles.Count) 'White'
if (-not $SkipReports) {
    Write-Step ("HTML reports rebuilt : {0}" -f ($FlushWeeks -join ', ')) 'White'
}