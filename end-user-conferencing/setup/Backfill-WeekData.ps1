[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$YearWeek,
    [ValidateSet('Both','Messaging','Rooms')]
    [string]$Offering = 'Both',
    [int]$LimitPerOffering = 10,
    [string]$SubscriptionId = '1c6d384e-bc83-4b02-859c-76eeb87f7676',
    [string]$ResourceGroupName = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccountName = 'opswconferblob',
    [string]$TableName = 'IncidentsCategoryStats',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configPath = Join-Path $repoRoot 'end-user-conferencing\config\LocalConfig-EndUserConferencing.psd1'
$secretsPath = Join-Path $repoRoot 'end-user-conferencing\config\LocalSecrets-EndUserConferencing.psd1'
$corePath = Join-Path $repoRoot 'end-user-conferencing\runbooks\_shared\EucRunbookCore.ps1'

if (-not (Test-Path $configPath)) { throw "Config not found: $configPath" }
if (-not (Test-Path $secretsPath)) { throw "Secrets not found: $secretsPath" }
if (-not (Test-Path $corePath)) { throw "Shared runbook core not found: $corePath" }

. $corePath

$config = Import-PowerShellDataFile -Path $configPath
$secrets = Import-PowerShellDataFile -Path $secretsPath

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Color = 'Cyan'
    )
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Escape-Html {
        param([string]$Text)
        if ($null -eq $Text) { return '' }
        return [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Get-ReportBlobName {
        param(
                [Parameter(Mandatory)][string]$OfferingName,
                [Parameter(Mandatory)][string]$YearWeek
        )

        $slug = if ($OfferingName -like 'Messaging*') { 'Messaging' } elseif ($OfferingName -like 'Meetings*') { 'Rooms' } else { ($OfferingName -replace '[^A-Za-z0-9]+', '') }
        return "EUC_${slug}_Weekly_Report_$YearWeek.html"
}

function Build-WeeklyReportHtml {
        param(
                [Parameter(Mandatory)][string]$OfferingName,
                [Parameter(Mandatory)][object[]]$Rows,
                [Parameter(Mandatory)][object]$WeekWindow
        )

        $sortedRows = @($Rows) | Sort-Object Date -Descending
        $total = $sortedRows.Count
        $misrouted = ($sortedRows | Where-Object { $_.Category -eq 'Excluded' -or $_.Misrouted -eq $true }).Count
        $inScope = $total - $misrouted
        $byCategory = $sortedRows | Group-Object Category | Sort-Object Count -Descending
        $topCat = if ($byCategory.Count -gt 0) { $byCategory[0] } else { $null }
        $topCategoryName = if ($topCat) { Escape-Html $topCat.Name } else { '-' }
        $topCategoryCount = if ($topCat) { $topCat.Count } else { 0 }

        $weekLabel = if ($WeekWindow -and $WeekWindow.YearWeek) { $WeekWindow.YearWeek } else { 'Unknown Week' }
        $dateRange = ''
        if ($WeekWindow -and $WeekWindow.IstStart -and $WeekWindow.IstEnd) {
                $dateRange = '{0} -> {1} (IST)' -f $WeekWindow.IstStart.ToString('ddd dd MMM yyyy'), $WeekWindow.IstEnd.ToString('ddd dd MMM yyyy')
        }

        $catRows = ($byCategory | ForEach-Object {
                $cat = Escape-Html $_.Name
                $count = $_.Count
                $pct = if ($total -gt 0) { [math]::Round(($count / $total) * 100, 1) } else { 0 }
                "<tr><td>$cat</td><td style='text-align:right;'>$count</td><td style='text-align:right;'>$pct%</td></tr>"
        }) -join "`n"

        $incidentRows = ($sortedRows | ForEach-Object {
                $num = Escape-Html $_.RowKey
                $cat = Escape-Html $_.Category
                $sub = Escape-Html $_.Subcategory
                $rc = Escape-Html $_.PossibleRootCause
                $ai = Escape-Html $_.AIAnalysis
                $conf = Escape-Html $_.Confidence
                $date = Escape-Html $_.Date
                $snowUrl = "https://intel.service-now.com/nav_to.do?uri=incident.do?sysparm_query=number=$num"
                "<tr><td><a href='$snowUrl' target='_blank' rel='noopener'>$num</a></td><td>$date</td><td>$cat</td><td>$sub</td><td>$rc</td><td>$conf</td><td>$ai</td></tr>"
        }) -join "`n"

        $startLabel = if ($WeekWindow -and $WeekWindow.IstStart) { $WeekWindow.IstStart.ToString('dddd, dd MMM yyyy') } else { '' }
        $endLabel = if ($WeekWindow -and $WeekWindow.IstEnd) { $WeekWindow.IstEnd.ToString('dddd, dd MMM yyyy') } else { '' }

        return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>$OfferingName Weekly Report $weekLabel</title>
<style>
    :root { --intel:#003C71; --blue:#0071C5; --bg:#f4f7fb; --card:#fff; --text:#1a2433; --muted:#5b6b7f; --border:#dde4ee; }
    * { box-sizing:border-box; }
    body { margin:0; font-family:'Segoe UI',Tahoma,sans-serif; background:var(--bg); color:var(--text); }
    header { background:linear-gradient(135deg,var(--intel),var(--blue)); color:#fff; padding:28px 32px; }
    header h1 { margin:0 0 6px 0; font-size:1.7rem; }
    header .sub { color:rgba(255,255,255,0.92); }
    main { max-width:1400px; margin:0 auto; padding:24px 32px 40px; }
    .stats { display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:14px; margin-bottom:20px; }
    .stat { background:var(--card); border:1px solid var(--border); border-radius:12px; padding:16px 18px; }
    .stat .num { font-size:1.8rem; font-weight:700; color:var(--intel); }
    .stat .label { color:var(--muted); font-size:0.85rem; }
    .section { background:var(--card); border:1px solid var(--border); border-radius:12px; padding:18px 20px; margin-bottom:20px; }
    h2 { margin:0 0 14px 0; font-size:1.08rem; color:var(--intel); }
    table { width:100%; border-collapse:collapse; font-size:0.9rem; }
    th, td { text-align:left; padding:9px 10px; border-bottom:1px solid var(--border); vertical-align:top; }
    th { background:#eef5fb; color:var(--intel); }
    a { color:var(--blue); text-decoration:none; }
    a:hover { text-decoration:underline; }
    .muted { color:var(--muted); }
</style>
</head>
<body>
<header>
    <h1>$OfferingName Weekly Report</h1>
    <div class="sub"><strong>Week:</strong> $weekLabel &nbsp; <strong>Range:</strong> $startLabel -> $endLabel &nbsp; (IST)</div>
</header>
<main>
    <div class="stats">
        <div class="stat"><div class="num">$total</div><div class="label">Total incidents</div></div>
        <div class="stat"><div class="num">$inScope</div><div class="label">In scope</div></div>
        <div class="stat"><div class="num">$misrouted</div><div class="label">Misrouted</div></div>
        <div class="stat"><div class="num">$topCategoryCount</div><div class="label">Top category: $topCategoryName</div></div>
    </div>
    <div class="section">
        <h2>Category Breakdown</h2>
        <table>
            <thead><tr><th>Category</th><th style='text-align:right;'>Count</th><th style='text-align:right;'>Share</th></tr></thead>
            <tbody>
$catRows
            </tbody>
        </table>
    </div>
    <div class="section">
        <h2>Incident Details</h2>
        <table>
            <thead><tr><th>Incident</th><th>Resolved</th><th>Category</th><th>Subcategory</th><th>Root Cause</th><th>Confidence</th><th>AI Analysis</th></tr></thead>
            <tbody>
$incidentRows
            </tbody>
        </table>
    </div>
</main>
</body>
</html>
"@
}

function Publish-WeeklyReportBlob {
        param(
                [Parameter(Mandatory)][object]$StorageContext,
                [Parameter(Mandatory)][string]$ContainerName,
                [Parameter(Mandatory)][string]$OfferingName,
                [Parameter(Mandatory)][string]$YearWeek,
                [Parameter(Mandatory)][object[]]$Rows,
                [Parameter(Mandatory)][object]$WeekWindow
        )

        $blobName = Get-ReportBlobName -OfferingName $OfferingName -YearWeek $YearWeek
        $html = Build-WeeklyReportHtml -OfferingName $OfferingName -Rows $Rows -WeekWindow $WeekWindow
        $tmp = Join-Path $env:TEMP $blobName
        Set-Content -Path $tmp -Value $html -Encoding UTF8
        Set-AzStorageBlobContent -File $tmp -Container $ContainerName -Blob $blobName -Context $StorageContext -Properties @{ ContentType = 'text/html; charset=utf-8' } -Force | Out-Null
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return $blobName
}

function Get-YearWeekWindow {
    param([Parameter(Mandatory)][string]$InputYearWeek)

    if ($InputYearWeek -notmatch '^(?<Year>\d{4})-W(?<Week>\d{1,2})$') {
        throw "Invalid YearWeek: $InputYearWeek"
    }

    $year = [int]$Matches.Year
    $week = [int]$Matches.Week
    $jan1 = (Get-Date -Year $year -Month 1 -Day 1).Date
    $week1Sun = $jan1.AddDays(-1 * [int]$jan1.DayOfWeek)
    $weekStart = $week1Sun.AddDays(($week - 1) * 7)
    $weekEnd = $weekStart.AddDays(7).AddSeconds(-1)

    [pscustomobject]@{
        Year      = $year
        Week      = $week
        YearWeek  = $InputYearWeek
        IstStart  = $weekStart
        IstEnd    = $weekEnd
        UtcStart  = $weekStart.AddHours(-5).AddMinutes(-30)
        UtcEnd    = $weekEnd.AddHours(-5).AddMinutes(-30)
    }
}

function Get-LocalServiceNowToken {
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $config.ServiceNowClientID
        client_secret = $secrets.ServiceNowClientSecret
        scope         = $config.ServiceNowScope
    }

    $response = Invoke-RestMethod -Method Post -Uri $config.TokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded'
    return [string]$response.access_token
}

function Invoke-LocalEucAnalysis {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$TemplateContent,
        [Parameter(Mandatory)][string]$IncidentJson
    )

    $url = '{0}/openai/deployments/{1}/chat/completions?api-version={2}' -f $Context.AzureOpenAIBaseUrl, $Context.AzureOpenAIDeployment, $Context.AzureOpenAIApiVersion
    $body = @{
        messages = @(
            @{ role = 'system'; content = $TemplateContent },
            @{ role = 'user'; content = $IncidentJson }
        )
        max_completion_tokens = 1600
    } | ConvertTo-Json -Depth 10

    $headers = @{
        'api-key' = $secrets.AzureOpenAIApiKey
        'Content-Type' = 'application/json'
    }

    $response = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body -TimeoutSec 180
    return [string]$response.choices[0].message.content
}

function Get-OfferingDefinitions {
    switch ($Offering) {
        'Messaging' {
            @(@{ Name = 'Messaging - Teams Chat and Audio'; Id = $config.MessagingServiceOfferingId })
        }
        'Rooms' {
            @(@{ Name = 'Meetings - Rooms and Hardware'; Id = $config.RoomsServiceOfferingId })
        }
        default {
            @(
                @{ Name = 'Messaging - Teams Chat and Audio'; Id = $config.MessagingServiceOfferingId },
                @{ Name = 'Meetings - Rooms and Hardware'; Id = $config.RoomsServiceOfferingId }
            )
        }
    }
}

function Get-WeekIncidentUrl {
    param(
        [Parameter(Mandatory)][string]$BusinessServiceId,
        [Parameter(Mandatory)][string]$ServiceOfferingId,
        [Parameter(Mandatory)][datetime]$StartUtc,
        [Parameter(Mandatory)][datetime]$EndUtc,
        [int]$Limit = 2000
    )

    $query = 'business_service={0}^service_offering={1}^stateIN6,7^resolved_at>={2}^resolved_at<={3}' -f `
        $BusinessServiceId,
        $ServiceOfferingId,
        $StartUtc.ToString('yyyy-MM-dd HH:mm:ss'),
        $EndUtc.ToString('yyyy-MM-dd HH:mm:ss')

    'https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=' + [uri]::EscapeDataString($query) + '&sysparm_display_value=true&sysparm_limit=' + [int]([math]::Max($Limit, 1))
}

function Get-TableRowProperties {
    param(
        [Parameter(Mandatory)][object]$Incident,
        [Parameter(Mandatory)][object]$Fields,
        [Parameter(Mandatory)][object]$WeekWindow,
        [Parameter(Mandatory)][string]$OfferingName,
        [string]$RawResponse = ''
    )

    $resolvedDate = [datetime]::Parse([string]$Incident.resolved_at)
    $category = if ($Fields.PrimaryCategory) { $Fields.PrimaryCategory.Trim() } else { 'Unknown' }
    $subcategory = if ($Fields.Subsymptom) { $Fields.Subsymptom.Trim() } else { '' }
    $rootCause = if ($Fields.PossibleRootCause) { $Fields.PossibleRootCause.Trim() } else { '' }
    $analysis = Format-EucStructuredAiAnalysis -Fields $Fields -RawResponse $RawResponse
    $confidence = Get-EucNormalizedConfidence -Raw ([string]$Fields.ConfidenceLevel)
    $misrouted = $false

    if ($category -eq 'Excluded' -or $category -eq 'Out of Scope') {
        $misrouted = $true
    }

    @{ 
        Category          = $category
        Subcategory       = $subcategory
        PossibleRootCause = $rootCause
        RootCause         = $rootCause
        DetailedRootCause = $rootCause
        AIAnalysis        = $analysis
        Confidence        = $confidence
        Date              = $resolvedDate.ToString('yyyy-MM-dd')
        YearWeek          = $WeekWindow.YearWeek
        Year              = [int]$WeekWindow.Year
        WeekNumber        = [int]$WeekWindow.Week
        ReportBlobName    = 'backfill'
        Service           = $OfferingName
        Misrouted         = [bool]$misrouted
        OfferingName      = $OfferingName
    }
}

if (-not (Get-Module -ListAvailable -Name Az.Accounts)) { throw 'Az.Accounts is required.' }
if (-not (Get-Module -ListAvailable -Name Az.Storage)) { throw 'Az.Storage is required.' }
if (-not (Get-Module -ListAvailable -Name AzTable)) {
    Write-Log 'Installing AzTable module...' 'Yellow'
    Install-Module -Name AzTable -Scope CurrentUser -Force -AllowClobber | Out-Null
}

Import-Module Az.Accounts -Force
Import-Module Az.Storage -Force
Import-Module AzTable -Force

$weekWindow = Get-YearWeekWindow -InputYearWeek $YearWeek
$serviceDefs = Get-OfferingDefinitions

Write-Log "Backfilling End User Conferencing for $YearWeek" 'Cyan'
Write-Log ("IST window: {0:yyyy-MM-dd} -> {1:yyyy-MM-dd}" -f $weekWindow.IstStart, $weekWindow.IstEnd) 'DarkGray'

$ctx = Get-AzContext
if (-not $ctx) {
    Connect-AzAccount -Subscription $SubscriptionId | Out-Null
} elseif ($ctx.Subscription.Id -ne $SubscriptionId) {
    Set-AzContext -Subscription $SubscriptionId | Out-Null
}

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageKey
$tableInfo = Get-AzStorageTable -Name $TableName -Context $storageContext -ErrorAction SilentlyContinue
if (-not $tableInfo) {
    Write-Log "Creating missing table '$TableName' in '$StorageAccountName'..." 'Yellow'
    $tableInfo = New-AzStorageTable -Name $TableName -Context $storageContext
}
$table = $tableInfo.CloudTable

$token = Get-LocalServiceNowToken
$weeklySummary = [ordered]@{}

foreach ($serviceDef in $serviceDefs) {
    $offeringName = $serviceDef.Name
    $offeringId = [string]$serviceDef.Id
    if ([string]::IsNullOrWhiteSpace($offeringId) -or $offeringId.StartsWith('<fill-in')) {
        throw "Service offering sys_id missing for $offeringName in LocalConfig-EndUserConferencing.psd1."
    }

    $context = [pscustomobject]@{
        ServiceName               = 'End User Conferencing'
        OfferingName              = $offeringName
        StorageAccountName        = $config.StorageAccountName
        KeyVaultName              = $config.KeyVaultName
        ResourceGroupName         = $ResourceGroupName
        TableName                 = $TableName
        TemplateContainer         = $config.PromptTemplateContainerName
        DataContainer             = $config.DataContainerName
        LogsContainer             = $config.PromptTemplateContainerName
        ResultsContainer          = $config.ResultsContainerName
        BusinessServiceId         = $config.BusinessServiceId
        MessagingOfferingId       = $config.MessagingServiceOfferingId
        RoomsOfferingId           = $config.RoomsServiceOfferingId
        ServiceNowClientId        = $config.ServiceNowClientID
        ServiceNowScope           = $config.ServiceNowScope
        ServiceNowTokenUrl        = $config.TokenUrl
        MessagingServiceNowIncidentsUrl = ''
        RoomsServiceNowIncidentUrl = ''
        AzureOpenAIBaseUrl        = $config.AzureOpenAIBaseUrl
        AzureOpenAIDeployment     = $config.AzureOpenAIDeployment
        AzureOpenAIApiVersion     = $config.AzureOpenAIApiVersion
        ServiceNowClientSecretName = $config.ServiceNowClientSecretName
        AzureOpenAIApiKeySecretName = $config.AzureOpenAIApiKeySecretName
    }

    $templateSuffix = if ($offeringName -like 'Messaging*') { 'Messaging' } else { 'Rooms' }
    $templates = @(
        "TicketCategorisation_EndUserConferencing_${templateSuffix}.md",
        "EnvironmentContext_EndUserConferencing_${templateSuffix}.md",
        "TrendSubCategorisation_EndUserConferencing_${templateSuffix}.md",
        "PossibleRootCause_EndUserConferencing_${templateSuffix}.md"
    )

    $templateContent = ($templates | ForEach-Object { Get-EucTemplateContent -Context $context -FileName $_ }) -join "`n`n"

    Write-Log "Fetching incidents for $offeringName..." 'Yellow'
    $incidentUrl = Get-WeekIncidentUrl -BusinessServiceId $config.BusinessServiceId -ServiceOfferingId $offeringId -StartUtc $weekWindow.UtcStart -EndUtc $weekWindow.UtcEnd -Limit $LimitPerOffering
    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
    $response = Invoke-RestMethod -Method Get -Uri $incidentUrl -Headers $headers -TimeoutSec 180
    $incidents = @($response.result)
    $exclusionResult = Apply-EucOfferingIncidentExclusions -OfferingName $offeringName -Incidents $incidents
    $incidents = @($exclusionResult.Included)
    $reportRows = New-Object System.Collections.Generic.List[object]
    $reportBlobName = Get-ReportBlobName -OfferingName $offeringName -YearWeek $weekWindow.YearWeek

    Write-Log ("Fetched {0} incident(s) for {1} (limit {2})." -f ($incidents.Count + $exclusionResult.ExcludedCount), $offeringName, $LimitPerOffering) 'Green'
    if ($exclusionResult.ExcludedCount -gt 0) {
        Write-Log ("Excluded {0} incident(s) for {1} where Channel='Proactive System Alert' and Assigned To is empty." -f $exclusionResult.ExcludedCount, $offeringName) 'Yellow'
    }
    $weeklySummary[$offeringName] = [ordered]@{ fetched = $incidents.Count; saved = 0; skipped = 0; errors = 0; reportBlob = $reportBlobName }

    foreach ($incident in $incidents) {
        if ([string]::IsNullOrWhiteSpace([string]$incident.number)) { continue }

        try {
            $incidentJson = [pscustomobject]@{
                number            = $incident.number
                short_description = $incident.short_description
                description       = $incident.description
                work_notes        = $incident.work_notes
                close_notes       = $incident.close_notes
                category          = $incident.category
                subcategory       = $incident.subcategory
                state             = $incident.state
                resolved_at       = $incident.resolved_at
                opened_at         = $incident.opened_at
                assignment_group  = $incident.assignment_group
            } | ConvertTo-Json -Depth 6 -Compress

            $analysisText = Invoke-LocalEucAnalysis -Context $context -TemplateContent $templateContent -IncidentJson $incidentJson
            $fields = Get-EucAnalysisFields -Text $analysisText
            $props = Get-TableRowProperties -Incident $incident -Fields $fields -WeekWindow $weekWindow -OfferingName $offeringName -RawResponse $analysisText
            $props.ReportBlobName = $reportBlobName

            if ($DryRun) {
                Write-Host ("[DRY] {0} -> {1} | {2} / {3}" -f $incident.number, $weekWindow.YearWeek, $props.Category, $props.Subcategory) -ForegroundColor DarkGray
                $weeklySummary[$offeringName].skipped++
                continue
            }

            Add-AzTableRow -Table $table -PartitionKey $weekWindow.YearWeek -RowKey $incident.number -Property $props -UpdateExisting | Out-Null
            [void]$reportRows.Add([pscustomobject]@{
                RowKey            = $incident.number
                Date              = $props.Date
                Category          = $props.Category
                Subcategory       = $props.Subcategory
                PossibleRootCause = $props.PossibleRootCause
                DetailedRootCause = $props.DetailedRootCause
                AIAnalysis        = $props.AIAnalysis
                Confidence        = $props.Confidence
                Misrouted         = $props.Misrouted
            })
            $weeklySummary[$offeringName].saved++
            Write-Host ("  OK {0,-15} {1,-9} {2,-40} {3}" -f $incident.number, $weekWindow.YearWeek, $props.Category, $props.Subcategory) -ForegroundColor Green
        } catch {
            $weeklySummary[$offeringName].errors++
            Write-Warning ("Failed on {0}: {1}" -f $incident.number, $_.Exception.Message)
        }
    }

    if (-not $DryRun -and $reportRows.Count -gt 0) {
        Write-Log "Uploading report blob $reportBlobName..." 'Yellow'
        $published = Publish-WeeklyReportBlob -StorageContext $storageContext -ContainerName 'results' -OfferingName $offeringName -YearWeek $weekWindow.YearWeek -Rows $reportRows.ToArray() -WeekWindow $weekWindow
        Write-Log "Uploaded report blob $published" 'Green'
    }
}

Write-Host ''
Write-Log 'WW summary' 'Magenta'
foreach ($offeringName in $weeklySummary.Keys) {
    $summary = $weeklySummary[$offeringName]
    Write-Host ("  {0}  fetched={1,3}  saved={2,3}  skipped={3,3}  errors={4,3}" -f $offeringName, $summary.fetched, $summary.saved, $summary.skipped, $summary.errors)
}

if ($DryRun) {
    Write-Log 'Dry run completed. No table rows were written.' 'Yellow'
} else {
    Write-Log 'Backfill completed.' 'Green'
}