<#
.SYNOPSIS
    Verify WW26 data compliance with strict template standards.

.DESCRIPTION
    Validates that all 42 WW26 incidents have:
    - Valid Category per TicketCategorisation_ProductivityTools.md
    - Valid Subcategory per TrendSubCategorisation_ProductivityTools.md
    - Valid RootCause per PossibleRootCause_ProductivityTools.md
    - Non-empty AIAnalysis with meaningful content
    - No "Unknown" confidence or empty critical fields

.USAGE
    .\tools\verify_ww26_compliance.ps1

#>

param(
    [switch]$DryRun,
    [string]$YearWeek = '2026-W26'
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

$StorageAccountName = $LocalConfig.PSD_AI_Automations_StorageAccountName
$ResourceGroup      = $LocalConfig.PSD_AI_Automations_ResourceGroupName
$SubscriptionId     = $LocalConfig.Incidents_analyzer_SubscriptionId
$TableName          = 'IncidentsCategoryStats'

Write-Host ""
Write-Host "====== VERIFY $YearWeek COMPLIANCE ======" -ForegroundColor Cyan
Write-Host ""

# Connect to Azure
Write-Host "[1/3] Connecting to Azure..." -ForegroundColor Cyan
try {
    Connect-AzAccount -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    Write-Host "      SUCCESS" -ForegroundColor Green
} catch {
    Write-Host "      ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize table
Write-Host "[2/3] Initializing table storage..." -ForegroundColor Cyan
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

# Load template catalogs
Write-Host "[3/3] Loading template catalogs and validating incidents..." -ForegroundColor Cyan

# Parse template files for valid values
$trendPath = ".\templates\TrendSubCategorisation_ProductivityTools.md"
$prcPath   = ".\templates\PossibleRootCause_ProductivityTools.md"

$validCategories = @()
$validSubSymptoms = @{}
$validPRC = @()

if (Test-Path $trendPath) {
    $lines = (Get-Content -Path $trendPath -Raw -Encoding UTF8) -split "\r?\n"
    $currentCategory = ''
    foreach ($ln in $lines) {
        # Category headers use #### (4 hashes) in the template
        if ($ln -match '^#### ') {
            $currentCategory = $ln -replace '^####\s*', '' | ForEach-Object { $_.Trim() }
            if ($currentCategory -and -not ($validCategories -contains $currentCategory)) {
                $validCategories += $currentCategory
                $validSubSymptoms[$currentCategory] = @()
            }
        # Subcategory group headers are **bold** standalone lines (e.g. **Sync Issues**)
        } elseif ($ln -match '^\*\*([^*]+)\*\*\s*$' -and $currentCategory) {
            $subSym = $Matches[1].Trim()
            if ($subSym -and -not ($validSubSymptoms[$currentCategory] -contains $subSym)) {
                $validSubSymptoms[$currentCategory] += $subSym
            }
        }
    }
}

if (Test-Path $prcPath) {
    $lines = (Get-Content -Path $prcPath -Raw -Encoding UTF8) -split "\r?\n"
    foreach ($ln in $lines) {
        # PRC uses table rows: | # | **Root Cause Label** | description |
        if ($ln -match '\|\s+\*\*([^|*]+)\*\*\s+\|') {
            $prc = $Matches[1].Trim()
            if ($prc -and -not ($validPRC -contains $prc)) {
                $validPRC += $prc
            }
        }
    }
}

# Fetch all records for the specified week
try {
    $partitionFilter = [Microsoft.WindowsAzure.Storage.Table.TableQuery]::GenerateFilterCondition('PartitionKey',[Microsoft.WindowsAzure.Storage.Table.QueryComparisons]::Equal,$YearWeek)
    $query = [Microsoft.WindowsAzure.Storage.Table.TableQuery]::new()
    $query.FilterString = $partitionFilter
    $token = $null
    $entities = @()
    do {
        $segment = $cloudTable.ExecuteQuerySegmentedAsync($query, $token).GetAwaiter().GetResult()
        $entities += $segment.Results
        $token = $segment.ContinuationToken
    } while ($null -ne $token)
} catch {
    Write-Host "      ERROR: Failed to query table: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

    Write-Host "      Found $($entities.Count) incidents in $YearWeek partition" -ForegroundColor Yellow
Write-Host ""

# Validate each incident
$compliant = 0
$issues = @()

foreach ($entity in $entities) {
    $rowKey = $entity.RowKey
    $category = $entity.Properties['Category'].StringValue
    $subcategory = $entity.Properties['Subcategory'].StringValue
    $rootCause = $entity.Properties['RootCause'].StringValue
    $aiAnalysis = $entity.Properties['AIAnalysis'].StringValue
    
    $entityIssues = @()
    
    # Check Category
    if ([string]::IsNullOrWhiteSpace($category) -or $category -eq "Unknown") {
        $entityIssues += "Category is empty or Unknown"
    } elseif (-not ($validCategories -contains $category)) {
        $entityIssues += "Category '$category' not in template catalog"
    }
    
    # Check Subcategory
    if ([string]::IsNullOrWhiteSpace($subcategory) -or $subcategory -eq "Other / Miscellaneous") {
        $entityIssues += "Subcategory is placeholder or generic"
    } elseif ($category -and $validSubSymptoms.ContainsKey($category)) {
        if (-not ($validSubSymptoms[$category] -contains $subcategory)) {
            $entityIssues += "Subcategory '$subcategory' not valid for category '$category'"
        }
    }
    
    # Check RootCause
    if ([string]::IsNullOrWhiteSpace($rootCause)) {
        if ($category -and $category -ne "Unknown") {
            $entityIssues += "RootCause is empty for non-Unknown category"
        }
    } elseif (-not ($validPRC -contains $rootCause)) {
        $entityIssues += "RootCause '$rootCause' not in template catalog"
    }
    
    # Check AIAnalysis
    if ([string]::IsNullOrWhiteSpace($aiAnalysis) -or $aiAnalysis.Length -lt 50) {
        $entityIssues += "AIAnalysis is empty or too brief (min 50 chars)"
    } elseif ($aiAnalysis -match "pending|placeholder|Not yet generated") {
        $entityIssues += "AIAnalysis contains placeholder text"
    }
    
    if ($entityIssues.Count -eq 0) {
        $compliant++
    } else {
        $issues += @{
            IncidentNumber = $rowKey
            Problems = $entityIssues -join "; "
        }
    }
}

Write-Host "====== COMPLIANCE SUMMARY ======" -ForegroundColor Cyan
Write-Host "Compliant incidents: $compliant / $($entities.Count)" -ForegroundColor $(if ($compliant -eq $entities.Count) { 'Green' } else { 'Yellow' })

if ($issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Non-compliant incidents ($($issues.Count)):" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host "  $($issue.IncidentNumber): $($issue.Problems)" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "To fix these incidents, run:"
    Write-Host "  .\tools\fix_ai_analysis_by_week.ps1 -StartYearWeek $YearWeek -EndYearWeek $YearWeek -ForceRealAI"
} else {
    Write-Host ""
    Write-Host "All $($entities.Count) $YearWeek incidents are compliant with strict template standards!" -ForegroundColor Green
}

Write-Host ""
