# Detect execution environment
$Script:IsAzureAutomation = $env:AUTOMATION_ASSET_ACCOUNTID -or $PSPrivateMetadata.JobId

if ($Script:IsAzureAutomation) {
    Write-Host "Running in Azure Automation environment" -ForegroundColor Green
    Import-Module -Name Az.Storage -Force -ErrorAction Stop
    Import-Module -Name Az.Accounts -Force -ErrorAction Stop

    $Script:LogFilePrefix = "AI-TrendAnalysis"
    $Script:LogContainerName = "logs"
    $Script:LogLevel = "Info"
    $Script:EnableBlobLogging = $true

    $Script:BlobConfig = @{
        StorageAccountName            = Get-AutomationVariable -Name "Incidents_analyzer_StorageAccountName"
        PromptContainerName           = Get-AutomationVariable -Name "Incidents_analyzer_PromptTemplateContainerName"
        ResourceGroupName             = Get-AutomationVariable -Name "Incidents_analyzer_ResourceGroupName"
        DataContainerName             = Get-AutomationVariable -Name "Incidents_analyzer_DataContainerName"
        ResultsContainerName          = Get-AutomationVariable -Name "Incidents_analyzer_ResultsContainerName"
        SubscriptionId                = Get-AutomationVariable -Name "Incidents_analyzer_SubscriptionId"
        StatisticsTableName           = "IncidentsCategoryStats"
    }

    $Script:Constants = @{
        AzureOpenAIBaseUrl       = Get-AutomationVariable -Name "AzureOpenAIBaseUrl"
        AzureOpenAIDeployment    = Get-AutomationVariable -Name "AzureOpenAIDeployment"
        AzureOpenAIApiKey        = Get-AutomationVariable -Name "AzureOpenAIApiKey"
        AzureOpenAIApiVersion    = Get-AutomationVariable -Name "AzureOpenAIApiVersion"
        UseClaudeModel           = Get-AutomationVariable -Name "UseClaudeModel" -ErrorAction SilentlyContinue
        ClaudeEndpoint           = Get-AutomationVariable -Name "ClaudeEndpoint" -ErrorAction SilentlyContinue
        ClaudeDeployment         = Get-AutomationVariable -Name "ClaudeDeployment" -ErrorAction SilentlyContinue
        ClaudeApiKey             = Get-AutomationVariable -Name "ClaudeApiKey" -ErrorAction SilentlyContinue
        ClaudeApiVersion         = Get-AutomationVariable -Name "ClaudeApiVersion" -ErrorAction SilentlyContinue
        TrendSignificanceThreshold = Get-AutomationVariable -Name "TrendSignificanceThreshold" -ErrorAction SilentlyContinue
        TrendMinIncidentCount      = Get-AutomationVariable -Name "TrendMinIncidentCount" -ErrorAction SilentlyContinue
        LogicAppSendAIEmailWebHookURL = Get-AutomationVariable -Name "LogicAppSendAIEmailWebHookURL" -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "Running in local development environment" -ForegroundColor Yellow
    $Script:LogLevel = "Debug"
    $Script:EnableBlobLogging = $false

    $Script:ScriptDirectory = $PSScriptRoot
    Set-Location $Script:ScriptDirectory
    $configPath  = ".\Config\LocalConfig-ProductivityTools.psd1"
    $secretsPath = ".\Config\LocalSecrets-ProductivityTools.psd1"
    if (Test-Path $configPath) {
        Write-Host "Loading Productivity Tools configuration from $configPath" -ForegroundColor Green
        $Script:LocalConfig = Import-PowerShellDataFile -Path $configPath
    } else {
        throw "$configPath not found. Please create it for local development."
    }
    if (Test-Path $secretsPath) {
        Write-Host "Merging Productivity Tools secrets from $secretsPath" -ForegroundColor Green
        $secrets = Import-PowerShellDataFile -Path $secretsPath
        foreach ($k in $secrets.Keys) { $Script:LocalConfig[$k] = $secrets[$k] }
    } else {
        Write-Host "WARNING: $secretsPath not found - ClientSecret / API key will be null" -ForegroundColor Yellow
    }

    $Script:BlobConfig = @{
        StorageAccountName       = $Script:LocalConfig.PSD_AI_Automations_StorageAccountName
        PromptContainerName      = $Script:LocalConfig.PSD_AI_Automations_PromptTemplateContainerName
        ResourceGroupName        = $Script:LocalConfig.PSD_AI_Automations_ResourceGroupName
        DataContainerName        = "data"
        ResultsContainerName     = "results"
        SubscriptionId           = $Script:LocalConfig.Incidents_analyzer_SubscriptionId
        StatisticsTableName      = "IncidentsCategoryStats"
    }

    $Script:Constants = @{
        AzureOpenAIBaseUrl       = $Script:LocalConfig.AzureOpenAIBaseUrl
        AzureOpenAIDeployment    = $Script:LocalConfig.AzureOpenAIDeployment
        AzureOpenAIApiKey        = $Script:LocalConfig.AzureOpenAIApiKey
        AzureOpenAIApiVersion    = $Script:LocalConfig.AzureOpenAIApiVersion
        UseClaudeModel           = $Script:LocalConfig.UseClaudeModel
        ClaudeEndpoint           = $Script:LocalConfig.ClaudeEndpoint
        ClaudeDeployment         = $Script:LocalConfig.ClaudeDeployment
        ClaudeApiKey             = $Script:LocalConfig.ClaudeApiKey
        ClaudeApiVersion         = $Script:LocalConfig.ClaudeApiVersion
        TrendSignificanceThreshold = $null
        TrendMinIncidentCount      = $null
        LogicAppSendAIEmailWebHookURL = $null
    }
}

<#
.SYNOPSIS
    Weekly Trend Analysis Runbook for EUC Incident Reports

.DESCRIPTION
    Compares the current week's incident category counts against the previous week,
    detects categories with significant increases, then uses AI to sub-categorize
    the incidents in those categories to identify what specific issue types are driving
    the increase.

    Designed to run daily after the incident-analyzer-rb runbook completes.

    Uses rolling 7-day windows instead of ISO weeks to ensure fair comparison:
    - Current period: last 7 days of incidents
    - Previous period: 7 days before that (days 8-14 ago)
    This avoids the problem of comparing a partial current week against a full previous week.

.NOTES
    Version: 1.1
    Requires: Run artifacts from incident-analyzer-rb.ps1 (run_artifact_*.json)
#>

#region Configuration

$Script:TrendConfig = @{
    # A category must increase by at least this percentage to be flagged
    SignificanceThresholdPercent = if ($Script:Constants.TrendSignificanceThreshold) { [int]$Script:Constants.TrendSignificanceThreshold } else { 30 }
    # A category must have at least this many incidents in the current week to be flagged
    MinIncidentCount            = if ($Script:Constants.TrendMinIncidentCount) { [int]$Script:Constants.TrendMinIncidentCount } else { 5 }
    # Categories to exclude from trend analysis (not actionable for trend detection)
    ExcludedCategories          = @("Excluded", "How Do I / User Education")
    # Number of days to look back for run artifacts
    ArtifactLookbackDays        = 14
    # AI configuration
    AI = @{
        MaxTokens        = 4096
        Temperature      = 0.1
        TopP             = 0.95
        FrequencyPenalty = 0
        PresencePenalty  = 0
    }
}

#endregion

#region Logging

function Write-ScriptLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Debug', 'Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info',
        [string]$Category = 'General'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{ Debug = 'Gray'; Info = 'White'; Success = 'Green'; Warning = 'Yellow'; Error = 'Red' }
    Write-Host "[$timestamp] [$Level] [$Category] $Message" -ForegroundColor $colors[$Level]
}

#endregion

#region Storage Helpers

function Get-StorageContext {
    [CmdletBinding()]
    param()

    if ($Script:IsAzureAutomation) {
        $azContext = Get-AzContext
        if (-not $azContext) {
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        }
        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $Script:BlobConfig.ResourceGroupName -Name $Script:BlobConfig.StorageAccountName)[0].Value
        return New-AzStorageContext -StorageAccountName $Script:BlobConfig.StorageAccountName -StorageAccountKey $storageKey
    } else {
        return $null
    }
}

function Get-PromptTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName
    )

    if ($Script:IsAzureAutomation) {
        $storageContext = Get-StorageContext
        $blobName = "$TemplateName.md"
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            Get-AzStorageBlobContent -Container $Script:BlobConfig.PromptContainerName `
                -Blob $blobName -Destination $tempFile -Context $storageContext -Force | Out-Null
            return Get-Content -Path $tempFile -Raw -Encoding UTF8
        } finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        }
    } else {
        $localPath = Join-Path ".\Templates" "$TemplateName.md"
        if (Test-Path $localPath) {
            return Get-Content -Path $localPath -Raw -Encoding UTF8
        }
        throw "Template not found: $localPath"
    }
}

#endregion

#region AI Functions

function Get-AIEndpoint {
    [CmdletBinding()]
    param()

    if ($Script:Constants.UseClaudeModel) {
        return $Script:Constants.ClaudeEndpoint
    } else {
        $base = $Script:Constants.AzureOpenAIBaseUrl.TrimEnd('/')
        return "$base/openai/deployments/$($Script:Constants.AzureOpenAIDeployment)/chat/completions?api-version=$($Script:Constants.AzureOpenAIApiVersion)"
    }
}

function Invoke-AIRequest {
    <#
    .SYNOPSIS
        Sends a request to the AI endpoint (OpenAI or Claude) and returns the text response.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SystemPrompt,

        [Parameter(Mandatory)]
        [string]$UserContent,

        [int]$MaxTokens = $Script:TrendConfig.AI.MaxTokens
    )

    $url = Get-AIEndpoint
    $isClaudeApi = [bool]$Script:Constants.UseClaudeModel

    if ($isClaudeApi) {
        $requestBody = @{
            model      = $Script:Constants.ClaudeDeployment
            max_tokens = $MaxTokens
            temperature = $Script:TrendConfig.AI.Temperature
            system     = $SystemPrompt
            messages   = @(
                @{ role = "user"; content = $UserContent }
            )
        }
        $headers = @{
            "x-api-key"            = $Script:Constants.ClaudeApiKey
            "anthropic-version"    = $Script:Constants.ClaudeApiVersion
            "Content-Type"         = "application/json"
        }
    } else {
        $requestBody = @{
            messages    = @(
                @{ role = "system"; content = $SystemPrompt },
                @{ role = "user";   content = $UserContent }
            )
            model       = $Script:Constants.AzureOpenAIDeployment
            temperature = $Script:TrendConfig.AI.Temperature
            max_completion_tokens = $MaxTokens
            top_p       = $Script:TrendConfig.AI.TopP
        }
        $headers = @{
            "api-key"      = $Script:Constants.AzureOpenAIApiKey
            "Content-Type" = "application/json"
        }
    }

    $jsonBody = $requestBody | ConvertTo-Json -Depth 10 -Compress

    $maxRetries = 3
    $retryDelay = 5
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $response = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $jsonBody -TimeoutSec 120
            if ($isClaudeApi) {
                return $response.content[0].text
            } else {
                return $response.choices[0].message.content
            }
        } catch {
            if ($attempt -eq $maxRetries) { throw }
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 429 -or $statusCode -ge 500) {
                Write-ScriptLog "AI request attempt $attempt failed (HTTP $statusCode), retrying in ${retryDelay}s..." -Level Warning
                Start-Sleep -Seconds $retryDelay
                $retryDelay *= 2
            } else {
                throw
            }
        }
    }
}

#endregion

#region Data Loading

function Get-DateRangeLabel {
    <#
    .SYNOPSIS
        Returns a human-readable label for a date range (e.g., "Mar 05 - Mar 11").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [DateTime]$StartDate,
        [Parameter(Mandatory)]
        [DateTime]$EndDate
    )
    return "$($StartDate.ToString('MMM dd')) - $($EndDate.ToString('MMM dd'))"
}

function Get-ArtifactDateUtc {
    <#
    .SYNOPSIS
        Extracts the UTC date from a run artifact's RunGeneratedAtUtc field or filename.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Artifact,
        [string]$FileName = ""
    )

    if ($Artifact.RunGeneratedAtUtc) {
        return ([DateTime]::Parse($Artifact.RunGeneratedAtUtc)).ToUniversalTime().Date
    }
    # Fallback: extract date from filename like run_artifact_2026-03-09_09-12-15.json
    if ($FileName -match 'run_artifact_(\d{4}-\d{2}-\d{2})') {
        return ([DateTime]::Parse($matches[1])).Date
    }
    return $null
}

function Get-MergedDateRangeData {
    <#
    .SYNOPSIS
        Loads and merges all run artifacts whose date falls within a specific date range.
    .DESCRIPTION
        Scans run_artifact_*.json files (from blob or local), filters by date range,
        and deduplicates tickets by incident number (keeping the latest version).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [DateTime]$StartDateUtc,

        [Parameter(Mandatory)]
        [DateTime]$EndDateUtc
    )

    $artifacts = @()
    # Use a wider cutoff for file filtering (go back further to be safe)
    $fileCutoffUtc = $StartDateUtc.AddDays(-2)

    if ($Script:IsAzureAutomation) {
        $storageContext = Get-StorageContext
        $blobs = Get-AzStorageBlob -Container $Script:BlobConfig.DataContainerName `
            -Context $storageContext -Prefix "run_artifact_" -ErrorAction SilentlyContinue |
            Sort-Object LastModified

        foreach ($blob in $blobs) {
            if ($blob.LastModified.UtcDateTime -lt $fileCutoffUtc) { continue }
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Get-AzStorageBlobContent -Container $Script:BlobConfig.DataContainerName `
                    -Blob $blob.Name -Destination $tempFile -Context $storageContext -Force | Out-Null
                $artifact = (Get-Content -Path $tempFile -Raw -Encoding UTF8) | ConvertFrom-Json
                $artifactDate = Get-ArtifactDateUtc -Artifact $artifact -FileName $blob.Name
                if ($artifactDate -and $artifactDate -ge $StartDateUtc.Date -and $artifactDate -le $EndDateUtc.Date) {
                    $artifacts += $artifact
                }
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
    } else {
        $dataDir = ".\data"
        if (Test-Path $dataDir) {
            $files = Get-ChildItem -Path $dataDir -Filter "run_artifact_*.json" | Sort-Object Name
            foreach ($file in $files) {
                $artifact = (Get-Content -Path $file.FullName -Raw -Encoding UTF8) | ConvertFrom-Json
                $artifactDate = Get-ArtifactDateUtc -Artifact $artifact -FileName $file.Name
                if ($artifactDate -and $artifactDate -ge $StartDateUtc.Date -and $artifactDate -le $EndDateUtc.Date) {
                    $artifacts += $artifact
                }
            }
        }
    }

    # Deduplicate: keep latest version of each ticket
    $ticketMap = @{}
    $summaryMap = @{}
    foreach ($artifact in $artifacts) {
        foreach ($ticket in $artifact.ProcessedTickets) {
            $ticketMap[$ticket.Number] = $ticket
        }
        if ($artifact.DetailedSummaries) {
            foreach ($summary in $artifact.DetailedSummaries) {
                $summaryMap[$summary.IncidentNumber] = $summary
            }
        }
    }

    $label = Get-DateRangeLabel -StartDate $StartDateUtc -EndDate $EndDateUtc
    return @{
        Label             = $label
        StartDate         = $StartDateUtc
        EndDate           = $EndDateUtc
        ProcessedTickets  = @($ticketMap.Values)
        DetailedSummaries = @($summaryMap.Values)
        ArtifactCount     = $artifacts.Count
    }
}

#endregion

#region Trend Detection

function Compare-WeeklyCategories {
    <#
    .SYNOPSIS
        Compares category counts between two weeks and identifies significant increases.
    .OUTPUTS
        Array of objects with: Category, CurrentCount, PreviousCount, Increase, PercentIncrease
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$CurrentWeekTickets,

        [Parameter(Mandatory)]
        [array]$PreviousWeekTickets
    )

    # Group by category
    $currentGroups = $CurrentWeekTickets | Group-Object -Property Category
    $previousGroups = $PreviousWeekTickets | Group-Object -Property Category

    $previousCounts = @{}
    foreach ($g in $previousGroups) {
        $previousCounts[$g.Name] = $g.Count
    }

    $trends = @()
    foreach ($g in $currentGroups) {
        $category = $g.Name
        $currentCount = $g.Count
        $previousCount = if ($previousCounts.ContainsKey($category)) { $previousCounts[$category] } else { 0 }
        $increase = $currentCount - $previousCount

        if ($increase -le 0) { continue }

        $percentIncrease = if ($previousCount -gt 0) {
            [math]::Round(($increase / $previousCount) * 100, 1)
        } else {
            # New category that didn't exist last week
            100.0
        }

        $trends += [PSCustomObject]@{
            Category        = $category
            CurrentCount    = $currentCount
            PreviousCount   = $previousCount
            Increase        = $increase
            PercentIncrease = $percentIncrease
        }
    }

    # Sort by absolute increase descending
    return $trends | Sort-Object Increase -Descending
}

function Get-SignificantIncreases {
    <#
    .SYNOPSIS
        Filters trends to only those meeting the significance threshold.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Trends
    )

    $threshold = $Script:TrendConfig.SignificanceThresholdPercent
    $minCount = $Script:TrendConfig.MinIncidentCount

    return $Trends | Where-Object {
        $_.PercentIncrease -ge $threshold -and $_.CurrentCount -ge $minCount
    }
}

#endregion

#region AI Sub-Categorization

function Get-SubCategoryAnalysis {
    <#
    .SYNOPSIS
        Uses AI to sub-categorize incidents within a specific parent category.
    .DESCRIPTION
        Sends incident details (number, description, reasoning, resolution) to the AI
        with the TrendSubCategorisation prompt to get specific sub-categories.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ParentCategory,

        [Parameter(Mandatory)]
        [array]$Tickets,

        [array]$DetailedSummaries
    )

    $promptTemplate = Get-PromptTemplate -TemplateName "TrendSubCategorisation_ProductivityTools"

    # Build a concise representation of each ticket for the AI
    $summaryLookup = @{}
    if ($DetailedSummaries) {
        foreach ($s in $DetailedSummaries) {
            $summaryLookup[$s.IncidentNumber] = $s.SummarisedNotes
        }
    }

    $ticketDescriptions = @()
    foreach ($ticket in $Tickets) {
        $summary = if ($summaryLookup.ContainsKey($ticket.Number)) {
            $summaryLookup[$ticket.Number]
        } else { "" }

        # Truncate long fields to stay within token limits
        $reasoning = if ($ticket.Reasoning.Length -gt 300) { $ticket.Reasoning.Substring(0, 300) + "..." } else { $ticket.Reasoning }
        $resolution = if ($ticket.Resolution) { $ticket.Resolution } else { "" }
        $description = if ($ticket.OriginalDescription) { $ticket.OriginalDescription } else { "" }
        $summaryTrunc = if ($summary.Length -gt 400) { $summary.Substring(0, 400) + "..." } else { $summary }

        $ticketDescriptions += [PSCustomObject]@{
            IncidentNumber = $ticket.Number
            Description    = $description
            Resolution     = $resolution
            Reasoning      = $reasoning
            Summary        = $summaryTrunc
        }
    }

    # Process in batches of 30 to stay within token limits
    $batchSize = 30
    $allSubCategories = @()

    for ($i = 0; $i -lt $ticketDescriptions.Count; $i += $batchSize) {
        $batch = $ticketDescriptions[$i..[math]::Min($i + $batchSize - 1, $ticketDescriptions.Count - 1)]

        $userContent = "Parent Category: $ParentCategory`n`nIncidents:`n" + ($batch | ConvertTo-Json -Depth 5 -Compress)

        Write-ScriptLog "Sub-categorizing $($batch.Count) '$ParentCategory' incidents (batch $([math]::Floor($i / $batchSize) + 1))..." -Level Info -Category "SubCategorize"

        try {
            $aiResponse = Invoke-AIRequest -SystemPrompt $promptTemplate -UserContent $userContent -MaxTokens 4096

            # Clean response — strip markdown fencing if present
            $cleaned = $aiResponse.Trim()
            if ($cleaned -match '(?s)```(?:json)?\s*(.+?)```') {
                $cleaned = $matches[1].Trim()
            }

            $parsed = $cleaned | ConvertFrom-Json
            $allSubCategories += $parsed

            # Rate limit courtesy
            if ($i + $batchSize -lt $ticketDescriptions.Count) {
                Start-Sleep -Seconds 3
            }
        } catch {
            Write-ScriptLog "Failed to sub-categorize batch: $($_.Exception.Message)" -Level Warning -Category "SubCategorize"
            # Add fallback entries for this batch
            foreach ($t in $batch) {
                $allSubCategories += [PSCustomObject]@{
                    IncidentNumber = $t.IncidentNumber
                    SubCategory    = "Uncategorized"
                    Justification  = "AI sub-categorization failed"
                }
            }
        }
    }

    return $allSubCategories
}

function Compare-SubCategories {
    <#
    .SYNOPSIS
        Compares sub-category counts between current and previous week for a given parent category.
    .OUTPUTS
        Array of objects showing sub-category changes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$CurrentSubCategories,

        [array]$PreviousSubCategories
    )

    $currentGroups = $CurrentSubCategories | Group-Object -Property SubCategory
    $previousGroups = @{}
    if ($PreviousSubCategories) {
        foreach ($g in ($PreviousSubCategories | Group-Object -Property SubCategory)) {
            $previousGroups[$g.Name] = $g.Count
        }
    }

    $comparison = @()
    foreach ($g in $currentGroups) {
        $subCat = $g.Name
        $currentCount = $g.Count
        $previousCount = if ($previousGroups.ContainsKey($subCat)) { $previousGroups[$subCat] } else { 0 }
        $increase = $currentCount - $previousCount

        $percentIncrease = if ($previousCount -gt 0) {
            [math]::Round(($increase / $previousCount) * 100, 1)
        } elseif ($increase -gt 0) {
            100.0
        } else {
            0
        }

        $comparison += [PSCustomObject]@{
            SubCategory     = $subCat
            CurrentCount    = $currentCount
            PreviousCount   = $previousCount
            Increase        = $increase
            PercentIncrease = $percentIncrease
            Incidents       = @($g.Group.IncidentNumber)
        }
    }

    return $comparison | Sort-Object Increase -Descending
}

#endregion

#region Report Generation

function New-TrendReportHtml {
    <#
    .SYNOPSIS
        Generates an HTML trend analysis report.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentLabel,

        [Parameter(Mandatory)]
        [string]$PreviousLabel,

        [Parameter(Mandatory)]
        [array]$AllTrends,

        [array]$SignificantTrends = @(),

        [Parameter(Mandatory)]
        [hashtable]$SubCategoryResults,

        [int]$CurrentTotal,
        [int]$PreviousTotal
    )

    $totalChange = $CurrentTotal - $PreviousTotal
    $totalChangePercent = if ($PreviousTotal -gt 0) { [math]::Round(($totalChange / $PreviousTotal) * 100, 1) } else { 0 }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>EUC Trend Analysis - $CurrentLabel vs $PreviousLabel</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; color: #333; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: #0071c5; border-bottom: 3px solid #0071c5; padding-bottom: 10px; }
        h2 { color: #0071c5; margin-top: 30px; }
        h3 { color: #333; margin-top: 20px; }
        .stats-bar { display: flex; gap: 20px; margin: 20px 0; flex-wrap: wrap; }
        .stat-card { background: white; padding: 15px 25px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; min-width: 150px; }
        .stat-card .value { font-size: 28px; font-weight: bold; color: #0071c5; }
        .stat-card .label { font-size: 12px; color: #666; margin-top: 5px; }
        .increase { color: #dc3545; }
        .decrease { color: #28a745; }
        .neutral { color: #6c757d; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background: #0071c5; color: white; padding: 12px 15px; text-align: left; font-size: 13px; }
        td { padding: 10px 15px; border-bottom: 1px solid #eee; font-size: 13px; }
        tr:hover { background: #f8f9fa; }
        .badge { display: inline-block; padding: 3px 10px; border-radius: 12px; font-size: 11px; font-weight: 600; }
        .badge-danger { background: #f8d7da; color: #721c24; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-info { background: #d1ecf1; color: #0c5460; }
        .trend-arrow { font-size: 14px; margin-right: 4px; }
        .category-section { background: white; border-radius: 8px; padding: 20px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); border-left: 4px solid #dc3545; }
        .no-significant { background: white; border-radius: 8px; padding: 20px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); border-left: 4px solid #28a745; }
        .key-finding { background: #fff3cd; border-left: 4px solid #ffc107; padding: 12px 15px; margin: 10px 0; border-radius: 4px; font-size: 13px; }
        .footer { margin-top: 30px; padding-top: 15px; border-top: 1px solid #ddd; font-size: 11px; color: #666; text-align: center; }
        .incident-list { font-size: 11px; color: #666; word-break: break-all; }
    </style>
</head>
<body>
<div class="container">
    <h1>EUC Weekly Trend Analysis</h1>
    <p style="color:#666;">Comparing <strong>$CurrentLabel</strong> (last 7 days) vs <strong>$PreviousLabel</strong> (previous 7 days)</p>

    <div class="stats-bar">
        <div class="stat-card">
            <div class="value">$CurrentTotal</div>
            <div class="label">$CurrentLabel Incidents</div>
        </div>
        <div class="stat-card">
            <div class="value">$PreviousTotal</div>
            <div class="label">$PreviousLabel Incidents</div>
        </div>
        <div class="stat-card">
            <div class="value $(if ($totalChange -gt 0) {'increase'} elseif ($totalChange -lt 0) {'decrease'} else {'neutral'})">$(if ($totalChange -gt 0) {"+$totalChange"} else {"$totalChange"})</div>
            <div class="label">Change ($(if ($totalChange -gt 0) {"+"}  )$totalChangePercent%)</div>
        </div>
        <div class="stat-card">
            <div class="value increase">$($SignificantTrends.Count)</div>
            <div class="label">Categories with Significant Increase</div>
        </div>
    </div>

    <h2>Category Overview (All Changes)</h2>
    <table>
        <tr>
            <th>Category</th>
            <th style="text-align:center;">$PreviousLabel</th>
            <th style="text-align:center;">$CurrentLabel</th>
            <th style="text-align:center;">Change</th>
            <th style="text-align:center;">% Change</th>
            <th>Status</th>
        </tr>
"@

    foreach ($trend in $AllTrends) {
        $changeClass = if ($trend.Increase -gt 0) { "increase" } elseif ($trend.Increase -lt 0) { "decrease" } else { "neutral" }
        $arrow = if ($trend.Increase -gt 0) { "&#9650;" } elseif ($trend.Increase -lt 0) { "&#9660;" } else { "&#9644;" }
        $changeSign = if ($trend.Increase -gt 0) { "+" } else { "" }

        $isSignificant = $SignificantTrends | Where-Object { $_.Category -eq $trend.Category }
        $badgeHtml = if ($isSignificant) {
            "<span class='badge badge-danger'>SIGNIFICANT INCREASE</span>"
        } elseif ($trend.Increase -gt 0) {
            "<span class='badge badge-warning'>Increase</span>"
        } elseif ($trend.Increase -lt 0) {
            "<span class='badge badge-success'>Decrease</span>"
        } else {
            "<span class='badge badge-info'>Stable</span>"
        }

        $html += @"
        <tr>
            <td style="font-weight:600;">$($trend.Category)</td>
            <td style="text-align:center;">$($trend.PreviousCount)</td>
            <td style="text-align:center;">$($trend.CurrentCount)</td>
            <td style="text-align:center;" class="$changeClass"><span class="trend-arrow">$arrow</span>${changeSign}$($trend.Increase)</td>
            <td style="text-align:center;" class="$changeClass">${changeSign}$($trend.PercentIncrease)%</td>
            <td>$badgeHtml</td>
        </tr>
"@
    }

    $html += "</table>"

    # Significant increase sections with sub-category breakdown
    if ($SignificantTrends.Count -eq 0) {
        $html += @"
    <div class="no-significant">
        <h3>No Significant Increases Detected</h3>
        <p>No category showed an increase of $($Script:TrendConfig.SignificanceThresholdPercent)% or more with at least $($Script:TrendConfig.MinIncidentCount) incidents this week.</p>
    </div>
"@
    } else {
        $html += "<h2>Detailed Sub-Category Analysis for Significant Increases</h2>"

        foreach ($trend in $SignificantTrends) {
            $category = $trend.Category
            $html += @"
    <div class="category-section">
        <h3>$category</h3>
        <p>$($trend.PreviousCount) ($PreviousLabel) &rarr; $($trend.CurrentCount) ($CurrentLabel) &mdash; <strong class="increase">+$($trend.Increase) incidents (+$($trend.PercentIncrease)%)</strong></p>
"@

            if ($SubCategoryResults.ContainsKey($category)) {
                $subResult = $SubCategoryResults[$category]
                $subComparison = $subResult.Comparison

                # Identify the top driver
                $topDriver = $subComparison | Select-Object -First 1
                if ($topDriver -and $topDriver.Increase -gt 0) {
                    $driverPercent = if ($trend.Increase -gt 0) { [math]::Round(($topDriver.Increase / $trend.Increase) * 100, 0) } else { 0 }
                    $html += @"
        <div class="key-finding">
            <strong>Key Driver:</strong> "$($topDriver.SubCategory)" accounts for <strong>$($topDriver.Increase)</strong> of the +$($trend.Increase) increase (~${driverPercent}% of the growth).
            ${PreviousLabel}: $($topDriver.PreviousCount) &rarr; ${CurrentLabel}: $($topDriver.CurrentCount)
        </div>
"@
                }

                $html += @"
        <table>
            <tr>
                <th>Sub-Category</th>
                <th style="text-align:center;">$PreviousLabel</th>
                <th style="text-align:center;">$CurrentLabel</th>
                <th style="text-align:center;">Change</th>
                <th style="text-align:center;">% Change</th>
                <th>Incident Numbers</th>
            </tr>
"@
                foreach ($sub in $subComparison) {
                    $subChangeClass = if ($sub.Increase -gt 0) { "increase" } elseif ($sub.Increase -lt 0) { "decrease" } else { "neutral" }
                    $subArrow = if ($sub.Increase -gt 0) { "&#9650;" } elseif ($sub.Increase -lt 0) { "&#9660;" } else { "&#9644;" }
                    $subSign = if ($sub.Increase -gt 0) { "+" } else { "" }

                    $incidentLinks = ($sub.Incidents | ForEach-Object { $_ }) -join ", "

                    $html += @"
            <tr>
                <td style="font-weight:600;">$($sub.SubCategory)</td>
                <td style="text-align:center;">$($sub.PreviousCount)</td>
                <td style="text-align:center;">$($sub.CurrentCount)</td>
                <td style="text-align:center;" class="$subChangeClass"><span class="trend-arrow">$subArrow</span>${subSign}$($sub.Increase)</td>
                <td style="text-align:center;" class="$subChangeClass">${subSign}$($sub.PercentIncrease)%</td>
                <td class="incident-list">$incidentLinks</td>
            </tr>
"@
                }

                $html += "</table>"
            }

            $html += "</div>"
        }
    }

    $html += @"
    <div class="footer">
        <p>Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC | Significance threshold: $($Script:TrendConfig.SignificanceThresholdPercent)% increase with minimum $($Script:TrendConfig.MinIncidentCount) incidents</p>
    </div>
</div>
</body>
</html>
"@

    return $html
}

#endregion

#region Artifact Storage for Trend Data

function Save-TrendArtifact {
    <#
    .SYNOPSIS
        Saves the trend analysis results as a JSON artifact for historical reference.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TrendData
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $fileName = "trend_artifact_$timestamp.json"
    $jsonContent = $TrendData | ConvertTo-Json -Depth 15 -Compress

    if ($Script:IsAzureAutomation) {
        $storageContext = Get-StorageContext
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -Path $tempFile -Value $jsonContent -Encoding UTF8
            Set-AzStorageBlobContent -File $tempFile `
                -Container $Script:BlobConfig.DataContainerName `
                -Blob $fileName -Context $storageContext -Force | Out-Null
            Write-ScriptLog "Trend artifact saved to blob: $fileName" -Level Success
        } finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        }
    } else {
        $dataDir = ".\data"
        if (-not (Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        $filePath = Join-Path $dataDir $fileName
        Set-Content -Path $filePath -Value $jsonContent -Encoding UTF8
        Write-ScriptLog "Trend artifact saved locally: $filePath" -Level Success
    }
}

function Get-PreviousTrendArtifact {
    <#
    .SYNOPSIS
        Loads the most recent trend artifact for the same date range comparison.
        Used to retrieve previous sub-categorization results to avoid re-running AI.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentLabel,

        [Parameter(Mandatory)]
        [string]$PreviousLabel
    )

    $latestArtifact = $null

    if ($Script:IsAzureAutomation) {
        $storageContext = Get-StorageContext
        $blobs = Get-AzStorageBlob -Container $Script:BlobConfig.DataContainerName `
            -Context $storageContext -Prefix "trend_artifact_" -ErrorAction SilentlyContinue |
            Sort-Object LastModified -Descending

        foreach ($blob in $blobs) {
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Get-AzStorageBlobContent -Container $Script:BlobConfig.DataContainerName `
                    -Blob $blob.Name -Destination $tempFile -Context $storageContext -Force | Out-Null
                $artifact = (Get-Content -Path $tempFile -Raw -Encoding UTF8) | ConvertFrom-Json
                if ($artifact.CurrentLabel -eq $CurrentLabel -and $artifact.PreviousLabel -eq $PreviousLabel) {
                    $latestArtifact = $artifact
                    break
                }
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
    } else {
        $dataDir = ".\data"
        if (Test-Path $dataDir) {
            $files = Get-ChildItem -Path $dataDir -Filter "trend_artifact_*.json" | Sort-Object Name -Descending
            foreach ($file in $files) {
                $artifact = (Get-Content -Path $file.FullName -Raw -Encoding UTF8) | ConvertFrom-Json
                if ($artifact.CurrentLabel -eq $CurrentLabel -and $artifact.PreviousLabel -eq $PreviousLabel) {
                    $latestArtifact = $artifact
                    break
                }
            }
        }
    }

    return $latestArtifact
}

#endregion

#region Main Execution

try {
    Write-ScriptLog "=== EUC ROLLING 7-DAY TREND ANALYSIS STARTING ===" -Level Info
    Write-ScriptLog "Significance Threshold: $($Script:TrendConfig.SignificanceThresholdPercent)%, Min Incidents: $($Script:TrendConfig.MinIncidentCount)" -Level Info

    # Step 1: Define rolling 7-day windows
    $today = (Get-Date).Date
    $currentEnd   = $today.AddDays(-1)   # yesterday (last complete day)
    $currentStart = $today.AddDays(-7)   # 7 days back from today
    $previousEnd  = $today.AddDays(-8)   # day before current window
    $previousStart = $today.AddDays(-14) # 14 days back from today

    $currentLabel  = Get-DateRangeLabel -StartDate $currentStart -EndDate $currentEnd
    $previousLabel = Get-DateRangeLabel -StartDate $previousStart -EndDate $previousEnd

    Write-ScriptLog "Current period: $currentLabel ($currentStart to $currentEnd)" -Level Info
    Write-ScriptLog "Previous period: $previousLabel ($previousStart to $previousEnd)" -Level Info

    # Step 2: Load data for both 7-day windows
    Write-ScriptLog "Loading current period ($currentLabel) data..." -Level Info
    $currentData = Get-MergedDateRangeData -StartDateUtc $currentStart -EndDateUtc $currentEnd
    Write-ScriptLog "Current period: $($currentData.ProcessedTickets.Count) tickets from $($currentData.ArtifactCount) artifacts" -Level Info

    Write-ScriptLog "Loading previous period ($previousLabel) data..." -Level Info
    $previousData = Get-MergedDateRangeData -StartDateUtc $previousStart -EndDateUtc $previousEnd
    Write-ScriptLog "Previous period: $($previousData.ProcessedTickets.Count) tickets from $($previousData.ArtifactCount) artifacts" -Level Info

    # Filter out excluded categories
    $excludedCats = $Script:TrendConfig.ExcludedCategories
    $currentFiltered  = @($currentData.ProcessedTickets  | Where-Object { $_.Category -notin $excludedCats })
    $previousFiltered = @($previousData.ProcessedTickets | Where-Object { $_.Category -notin $excludedCats })
    Write-ScriptLog "After filtering excluded categories ($($excludedCats -join ', ')): Current=$($currentFiltered.Count), Previous=$($previousFiltered.Count)" -Level Info

    if ($currentFiltered.Count -eq 0) {
        Write-ScriptLog "No tickets found for current period $currentLabel. Nothing to analyze." -Level Warning
        return
    }

    if ($previousFiltered.Count -eq 0) {
        Write-ScriptLog "No tickets found for previous period $previousLabel. Cannot compute trends (first period of data)." -Level Warning
        return
    }

    # Step 3: Compare categories between weeks
    Write-ScriptLog "=== COMPARING CATEGORIES ===" -Level Info
    $allTrends = Compare-WeeklyCategories -CurrentWeekTickets $currentFiltered -PreviousWeekTickets $previousFiltered

    # Build complete list including stable/decreased categories for the overview table
    $currentGroups = $currentFiltered | Group-Object -Property Category
    $previousGroups = $previousFiltered | Group-Object -Property Category
    $allCategories = @($currentGroups.Name) + @($previousGroups.Name) | Select-Object -Unique

    $allCategoryTrends = @()
    $prevCounts = @{}
    foreach ($g in $previousGroups) { $prevCounts[$g.Name] = $g.Count }
    $curCounts = @{}
    foreach ($g in $currentGroups) { $curCounts[$g.Name] = $g.Count }

    foreach ($cat in $allCategories) {
        $cur = if ($curCounts.ContainsKey($cat)) { $curCounts[$cat] } else { 0 }
        $prev = if ($prevCounts.ContainsKey($cat)) { $prevCounts[$cat] } else { 0 }
        $inc = $cur - $prev
        $pct = if ($prev -gt 0) { [math]::Round(($inc / $prev) * 100, 1) } elseif ($inc -gt 0) { 100.0 } else { 0 }
        $allCategoryTrends += [PSCustomObject]@{
            Category        = $cat
            CurrentCount    = $cur
            PreviousCount   = $prev
            Increase        = $inc
            PercentIncrease = $pct
        }
    }
    $allCategoryTrends = $allCategoryTrends | Sort-Object Increase -Descending

    foreach ($t in $allCategoryTrends) {
        $sign = if ($t.Increase -gt 0) { "+" } else { "" }
        Write-ScriptLog "  $($t.Category): $($t.PreviousCount) -> $($t.CurrentCount) (${sign}$($t.Increase), ${sign}$($t.PercentIncrease)%)" -Level Info
    }

    # Step 4: Filter for significant increases
    $significantTrends = @(Get-SignificantIncreases -Trends $allTrends)
    Write-ScriptLog "$($significantTrends.Count) categories with significant increases detected" -Level Info

    foreach ($s in $significantTrends) {
        Write-ScriptLog "  SIGNIFICANT: $($s.Category) - $($s.PreviousCount) -> $($s.CurrentCount) (+$($s.Increase), +$($s.PercentIncrease)%)" -Level Warning
    }

    # Step 5: AI sub-categorization for significant categories
    $subCategoryResults = @{}

    if ($significantTrends.Count -gt 0) {
        Write-ScriptLog "=== AI SUB-CATEGORIZATION ===" -Level Info

        # Check for existing trend artifact to reuse previous period's sub-categories
        $existingArtifact = Get-PreviousTrendArtifact -CurrentLabel $currentLabel -PreviousLabel $previousLabel

        foreach ($trend in $significantTrends) {
            $category = $trend.Category

            # Get current week tickets for this category
            $currentTickets = $currentData.ProcessedTickets | Where-Object { $_.Category -eq $category }
            Write-ScriptLog "Sub-categorizing $($currentTickets.Count) current week '$category' tickets..." -Level Info
            $currentSubCats = Get-SubCategoryAnalysis -ParentCategory $category -Tickets $currentTickets -DetailedSummaries $currentData.DetailedSummaries

            # Get previous week sub-categories — reuse from artifact if available, otherwise run AI
            $previousSubCats = @()
            if ($existingArtifact -and $existingArtifact.SubCategoryResults.$category) {
                Write-ScriptLog "Reusing previous sub-categorization for '$category' from existing artifact" -Level Info
                $previousSubCats = @($existingArtifact.SubCategoryResults.$category.PreviousSubCategories)
            } else {
                $previousTickets = $previousData.ProcessedTickets | Where-Object { $_.Category -eq $category }
                if ($previousTickets.Count -gt 0) {
                    Write-ScriptLog "Sub-categorizing $($previousTickets.Count) previous week '$category' tickets..." -Level Info
                    $previousSubCats = Get-SubCategoryAnalysis -ParentCategory $category -Tickets $previousTickets -DetailedSummaries $previousData.DetailedSummaries
                }
            }

            # Compare sub-categories
            $comparison = Compare-SubCategories -CurrentSubCategories $currentSubCats -PreviousSubCategories $previousSubCats

            $subCategoryResults[$category] = @{
                CurrentSubCategories  = $currentSubCats
                PreviousSubCategories = $previousSubCats
                Comparison            = $comparison
            }

            # Log top sub-category drivers
            $topDrivers = $comparison | Where-Object { $_.Increase -gt 0 } | Select-Object -First 3
            foreach ($driver in $topDrivers) {
                Write-ScriptLog "  Sub-category driver: $($driver.SubCategory) - $($driver.PreviousCount) -> $($driver.CurrentCount) (+$($driver.Increase))" -Level Info
            }
        }
    }

    # Step 6: Generate HTML report
    Write-ScriptLog "=== GENERATING TREND REPORT ===" -Level Info

    $htmlContent = New-TrendReportHtml `
        -CurrentLabel $currentLabel `
        -PreviousLabel $previousLabel `
        -AllTrends $allCategoryTrends `
        -SignificantTrends $significantTrends `
        -SubCategoryResults $subCategoryResults `
        -CurrentTotal $currentFiltered.Count `
        -PreviousTotal $previousFiltered.Count

    # Name by ISO week so daily runs within the same week overwrite the same report
    $isoWeek = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
        (Get-Date), [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
    $isoYear = (Get-Date).Year
    $reportBlobName = "EUC_Trend_Analysis_${isoYear}-W$($isoWeek.ToString('D2')).html"

    if ($Script:IsAzureAutomation) {
        $storageContext = Get-StorageContext
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -Path $tempFile -Value $htmlContent -Encoding UTF8
            Set-AzStorageBlobContent -File $tempFile `
                -Container $Script:BlobConfig.ResultsContainerName `
                -Blob $reportBlobName -Context $storageContext -Force | Out-Null
            Write-ScriptLog "Trend report saved to blob: $reportBlobName" -Level Success
            Write-Host "`u{2713} Trend report saved: $reportBlobName" -ForegroundColor Green
        } finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        }
    } else {
        $resultsDir = ".\results"
        if (-not (Test-Path $resultsDir)) {
            New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
        }
        $filePath = Join-Path $resultsDir $reportBlobName
        Set-Content -Path $filePath -Value $htmlContent -Encoding UTF8
        Write-ScriptLog "Trend report saved locally: $filePath" -Level Success
        Write-Host "`u{2713} Trend report saved: $filePath" -ForegroundColor Green
    }

    # Step 7: Save trend artifact for reuse
    $trendArtifact = @{
        GeneratedAtUtc     = (Get-Date).ToUniversalTime().ToString("o")
        CurrentLabel       = $currentLabel
        PreviousLabel      = $previousLabel
        CurrentStartDate   = $currentStart.ToString("yyyy-MM-dd")
        CurrentEndDate     = $currentEnd.ToString("yyyy-MM-dd")
        PreviousStartDate  = $previousStart.ToString("yyyy-MM-dd")
        PreviousEndDate    = $previousEnd.ToString("yyyy-MM-dd")
        CurrentTotal       = $currentFiltered.Count
        PreviousTotal      = $previousFiltered.Count
        SignificantTrends  = @($significantTrends)
        AllCategoryTrends  = @($allCategoryTrends)
        SubCategoryResults = $subCategoryResults
        ReportBlobName     = $reportBlobName
    }
    Save-TrendArtifact -TrendData $trendArtifact

    # Summary
    Write-ScriptLog "=== TREND ANALYSIS COMPLETE ===" -Level Success
    Write-ScriptLog "Total: $($previousFiltered.Count) ($previousLabel) -> $($currentFiltered.Count) ($currentLabel)" -Level Info
    Write-ScriptLog "Significant increases: $($significantTrends.Count) categories" -Level Info
    Write-Host "`n=== Trend Analysis Complete ===" -ForegroundColor Green

} catch {
    Write-ScriptLog "Trend analysis failed: $($_.Exception.Message)" -Level Error
    Write-ScriptLog "Stack trace: $($_.ScriptStackTrace)" -Level Error
    throw
}

#endregion
