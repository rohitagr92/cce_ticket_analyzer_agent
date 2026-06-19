<#
.SYNOPSIS
    Daily ServiceNow vs table reconciliation with auto-heal for Productivity Tools.

.DESCRIPTION
    This runbook compares ServiceNow resolved/closed counts (state IN 6,7) to
    IncidentsCategoryStats table row counts per work week. If mismatch exceeds
    threshold, it can auto-heal by running week backfill logic (via analyzer runbook)
    and then re-check counts.

        It also writes a health-status JSON artifact for dashboard freshness in the
        results container (not in the incident weekly table partitions).

.NOTES
    Expected Automation Variables:
      Incidents_analyzer_StorageAccountName
      Incidents_analyzer_ResourceGroupName
      Incidents_analyzer_SubscriptionId
      ServiceNowIncidentsClientID
      ServiceNowIncidentsClientSecret
      ServiceNowIncidentsScope
      TokenUrl
      ServiceNowIncidentsURL
      LogicAppSendAIEmailWebHookURL (optional)

    Optional Automation Variables (defaults used when missing):
      PT_BusinessServiceId               default a1de2ff2db8f50108062531dd3961911
      PT_ServiceOfferingId               default fcb18407dbcf50108062531dd39619c4
      PT_TrendTableName                  default IncidentsCategoryStats
      PT_ReconcileWeeksToCheck           default 2
      PT_ReconcileDeltaThreshold         default 0
      PT_ReconcileEnableAutoHeal         default True
      PT_ReconcileMaxHealPerWeekPerDay   default 1
      PT_ReconcileAutoHealState          default {}
#>

[CmdletBinding()]
param(
    [string]$TargetYearWeek = '',
    [int]$WeeksToCheck = 0,
    [int]$DeltaThreshold = -1,
    [bool]$EnableAutoHeal = $true,
    [bool]$SendAlertOnMismatch = $true,
    [int]$MaxAutoHealPerWeekPerDay = 0,
    [string]$ResourceGroupName = 'OPSW-Ticket-Analyzer',
    [string]$AutomationAccountName = 'OPSW-ProductivityTools-account',
    [string]$AnalyzerRunbookName = 'incident-analyzer-rb-prodtools',
    [string]$AutoHealRunbookName = 'incident-trend-backfill-rb-prodtools',
    [int]$AutoHealLookbackDays = 21
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param(
        [Parameter(Mandatory)][string]$Message
    )
    Write-Output ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Get-OptVar {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Default
    )
    try {
        $value = Get-AutomationVariable -Name $Name -ErrorAction Stop
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return $Default }
        return $value
    }
    catch {
        return $Default
    }
}

function ConvertTo-BoolSafe {
    param(
        [Parameter(Mandatory)]$Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }

    $s = ([string]$Value).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($s)) { return $Default }
    if ($s -in @('1', 'true', 'yes', 'y', 'on')) { return $true }
    if ($s -in @('0', 'false', 'no', 'n', 'off')) { return $false }
    return $Default
}

function ConvertTo-HtmlEncodedText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return ([string]$Text).
        Replace('&', '&amp;').
        Replace('<', '&lt;').
        Replace('>', '&gt;').
        Replace('"', '&quot;').
        Replace("'", '&#39;')
}

function Get-YearWeekFromDate {
    param([Parameter(Mandatory)][datetime]$Date)
    $d = $Date.Date
    $year = $d.Year
    $jan1 = (Get-Date -Year $year -Month 1 -Day 1).Date
    $week1Sun = $jan1.AddDays(-1 * [int]$jan1.DayOfWeek)
    $days = [math]::Floor(($d - $week1Sun).TotalDays)
    $wk = [int]([math]::Floor($days / 7) + 1)
    return ('{0}-W{1:00}' -f $year, $wk)
}

function Get-YearWeekWindowUtc {
    param([Parameter(Mandatory)][string]$YearWeek)

    if ($YearWeek -notmatch '^(?<y>\d{4})-W(?<w>\d{1,2})$') {
        throw "Invalid YearWeek format: $YearWeek"
    }

    $year = [int]$Matches.y
    $wk = [int]$Matches.w
    $jan1 = (Get-Date -Year $year -Month 1 -Day 1).Date
    $week1Sun = $jan1.AddDays(-1 * [int]$jan1.DayOfWeek)
    $weekStartIst = $week1Sun.AddDays(($wk - 1) * 7)
    $weekEndIst = $weekStartIst.AddDays(7).AddSeconds(-1)

    $istOffset = New-TimeSpan -Hours 5 -Minutes 30
    $startUtc = $weekStartIst - $istOffset
    $endUtc = $weekEndIst - $istOffset

    return [PSCustomObject]@{
        YearWeek = $YearWeek
        StartUtc = $startUtc
        EndUtc = $endUtc
        StartFilter = $startUtc.ToString('yyyy-MM-dd HH:mm:ss')
        EndFilter = $endUtc.ToString('yyyy-MM-dd HH:mm:ss')
    }
}

function Get-ServiceNowToken {
    param([Parameter(Mandatory)][hashtable]$Config)
    $body = @{
        grant_type = 'client_credentials'
        client_id = $Config.ServiceNowIncidentsClientID
        client_secret = $Config.ServiceNowIncidentsClientSecret
        scope = $Config.ServiceNowIncidentsScope
    }
    $resp = Invoke-RestMethod -Method Post -Uri $Config.TokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded'
    if (-not $resp.access_token) { throw 'ServiceNow token request did not return access_token.' }
    return [string]$resp.access_token
}

function Get-ServiceNowCountForWeek {
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$BusinessServiceId,
        [Parameter(Mandatory)][string]$ServiceOfferingId,
        [Parameter(Mandatory)][object]$Window
    )

    $startEnc = $Window.StartFilter -replace ' ', '%20'
    $endEnc = $Window.EndFilter -replace ' ', '%20'
    $query = "business_service=$BusinessServiceId^service_offering=$ServiceOfferingId^stateIN6,7^resolved_at>=$startEnc^resolved_at<=$endEnc"
    $url = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$query&sysparm_display_value=true&sysparm_limit=2000"

    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
    $resp = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -TimeoutSec 120
    return @($resp.result).Count
}

function Get-TableWeekCount {
    param(
        [Parameter(Mandatory)]$CloudTable,
        [Parameter(Mandatory)][string]$YearWeek
    )

    $rows = @(Get-AzTableRow -Table $CloudTable -PartitionKey $YearWeek -ErrorAction SilentlyContinue)
    return $rows.Count
}

function Invoke-WeekAutoHeal {
    param(
        [Parameter(Mandatory)][string]$YearWeek,
        [Parameter(Mandatory)][string]$BusinessServiceId,
        [Parameter(Mandatory)][string]$ServiceOfferingId,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$AutomationAccount,
        [Parameter(Mandatory)][string]$AnalyzerRunbook,
        [Parameter(Mandatory)][string]$AutoHealRunbook,
        [int]$BackfillLookbackDays = 21
    )

    $status = 'Unknown'
    $jobId = ''

    $jobParams = @{
        LookbackDays = [Math]::Max(1, $BackfillLookbackDays)
    }

    # Use the incremental backfill runbook as auto-heal so this runbook does not
    # require Automation Variable write permission.
    $job = Start-AzAutomationRunbook -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Name $AutoHealRunbook -Parameters $jobParams
    $jobId = [string]$job.JobId
    Write-Step "Auto-heal started for $YearWeek via $AutoHealRunbook (JobId: $jobId, LookbackDays=$($jobParams.LookbackDays))"

    $maxPoll = 240
    for ($i = 0; $i -lt $maxPoll; $i++) {
        $j = Get-AzAutomationJob -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Id $jobId
        $status = [string]$j.Status
        if ($status -in @('Completed', 'Failed', 'Stopped', 'Suspended')) { break }
        Start-Sleep -Seconds 30
    }

    return [PSCustomObject]@{
        YearWeek = $YearWeek
        JobId = $jobId
        FinalStatus = $status
    }
}

function Send-ReconcileAlert {
    param(
        [Parameter(Mandatory)][string]$WebhookUrl,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$BodyText
    )

    if ([string]::IsNullOrWhiteSpace($WebhookUrl)) { return $false }
    if (-not ($WebhookUrl -match '^https://')) { return $false }

        $html = '<pre style="font-family:Consolas,monospace;white-space:pre-wrap;">' +
            (ConvertTo-HtmlEncodedText -Text $BodyText) +
            '</pre>'
    $payload = @{
        subject = $Subject
        htmlContent = $html
        timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
    } | ConvertTo-Json -Depth 4 -Compress

    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -Headers @{ 'Content-Type' = 'application/json; charset=utf-8' } -TimeoutSec 30 | Out-Null
    return $true
}

function Get-HealthArtifact {
    param(
        [Parameter(Mandatory)][string]$ContainerName,
        [Parameter(Mandatory)]$StorageContext,
        [string]$BlobName = 'health-status.json'
    )

    try {
        $tmp = Join-Path $env:TEMP ("health_" + [guid]::NewGuid().ToString('N') + '.json')
        Get-AzStorageBlobContent -Container $ContainerName -Blob $BlobName -Context $StorageContext -Destination $tmp -Force -ErrorAction Stop | Out-Null
        $json = Get-Content -Path $tmp -Raw -Encoding UTF8
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($json)) { return $null }
        return ($json | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        return $null
    }
}

function Set-HealthArtifact {
    param(
        [Parameter(Mandatory)][string]$ContainerName,
        [Parameter(Mandatory)]$StorageContext,
        [Parameter(Mandatory)][hashtable]$HealthPayload,
        [string]$BlobName = 'health-status.json'
    )

    $tmp = Join-Path $env:TEMP ("health_" + [guid]::NewGuid().ToString('N') + '.json')
    $HealthPayload | ConvertTo-Json -Depth 8 | Set-Content -Path $tmp -Encoding UTF8
    Set-AzStorageBlobContent -Container $ContainerName -Blob $BlobName -Context $StorageContext -File $tmp -Force | Out-Null
    Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
}

Write-Step 'Loading configuration and variables...'
$cfg = @{
    StorageAccountName = Get-AutomationVariable -Name 'Incidents_analyzer_StorageAccountName'
    StorageResourceGroup = Get-AutomationVariable -Name 'Incidents_analyzer_ResourceGroupName'
    SubscriptionId = Get-AutomationVariable -Name 'Incidents_analyzer_SubscriptionId'
    ServiceNowIncidentsClientID = Get-AutomationVariable -Name 'ServiceNowIncidentsClientID'
    ServiceNowIncidentsClientSecret = Get-AutomationVariable -Name 'ServiceNowIncidentsClientSecret'
    ServiceNowIncidentsScope = Get-AutomationVariable -Name 'ServiceNowIncidentsScope'
    TokenUrl = Get-AutomationVariable -Name 'TokenUrl'
    ResultsContainerName = [string](Get-OptVar -Name 'Incidents_analyzer_ResultsContainerName' -Default 'results')
    WebhookUrl = Get-AutomationVariable -Name 'LogicAppSendAIEmailWebHookURL' -ErrorAction SilentlyContinue
}

$businessServiceId = [string](Get-OptVar -Name 'PT_BusinessServiceId' -Default 'a1de2ff2db8f50108062531dd3961911')
$serviceOfferingId = [string](Get-OptVar -Name 'PT_ServiceOfferingId' -Default 'fcb18407dbcf50108062531dd39619c4')
$tableName = [string](Get-OptVar -Name 'PT_TrendTableName' -Default 'IncidentsCategoryStats')
if ($WeeksToCheck -le 0) {
    $WeeksToCheck = [int](Get-OptVar -Name 'PT_ReconcileWeeksToCheck' -Default 2)
}
if ($DeltaThreshold -lt 0) {
    $DeltaThreshold = [int](Get-OptVar -Name 'PT_ReconcileDeltaThreshold' -Default 0)
}
if ($PSBoundParameters.ContainsKey('EnableAutoHeal') -eq $false) {
    $EnableAutoHeal = ConvertTo-BoolSafe -Value (Get-OptVar -Name 'PT_ReconcileEnableAutoHeal' -Default $true) -Default $true
}
if ($MaxAutoHealPerWeekPerDay -le 0) {
    $MaxAutoHealPerWeekPerDay = [int](Get-OptVar -Name 'PT_ReconcileMaxHealPerWeekPerDay' -Default 1)
}
$autoHealStateVarName = 'PT_ReconcileAutoHealState'

Write-Step 'Connecting to Azure with managed identity...'
Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
Set-AzContext -Subscription $cfg.SubscriptionId -ErrorAction Stop | Out-Null

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $cfg.StorageResourceGroup -Name $cfg.StorageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $cfg.StorageAccountName -StorageAccountKey $storageKey

if (-not (Get-Module -ListAvailable -Name AzTable)) {
    throw 'AzTable module is required in the Automation Account runtime.'
}
if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
    throw 'Az.Storage module is required in the Automation Account runtime.'
}
Import-Module AzTable -Force
Import-Module Az.Storage -Force
$cloudTable = (Get-AzStorageTable -Name $tableName -Context $ctx -ErrorAction Stop).CloudTable

$existingHealth = Get-HealthArtifact -ContainerName $cfg.ResultsContainerName -StorageContext $ctx
$priorLastIngestionUtc = if ($existingHealth -and $existingHealth.lastSuccessfulIngestionUtc) { [string]$existingHealth.lastSuccessfulIngestionUtc } else { '' }

$targetWeeks = @()
if (-not [string]::IsNullOrWhiteSpace($TargetYearWeek)) {
    $targetWeeks = @($TargetYearWeek)
}
else {
    $istNow = (Get-Date).ToUniversalTime().AddHours(5).AddMinutes(30)
    for ($i = 0; $i -lt $WeeksToCheck; $i++) {
        $d = $istNow.AddDays(-7 * $i)
        $targetWeeks += (Get-YearWeekFromDate -Date $d)
    }
}
$targetWeeks = $targetWeeks | Select-Object -Unique
Write-Step ('Weeks to check: ' + ($targetWeeks -join ', '))

$token = Get-ServiceNowToken -Config $cfg
$healAttemptsByWeek = @{}

$results = New-Object System.Collections.Generic.List[object]
$anyAutoHealTriggered = $false
$anyMismatchRemaining = $false
$autoHealRunUtc = ''

foreach ($yw in $targetWeeks) {
    Write-Step "Reconciling $yw..."
    $window = Get-YearWeekWindowUtc -YearWeek $yw

    $snCount = Get-ServiceNowCountForWeek -Token $token -BusinessServiceId $businessServiceId -ServiceOfferingId $serviceOfferingId -Window $window
    $tableCountBefore = Get-TableWeekCount -CloudTable $cloudTable -YearWeek $yw
    $deltaBefore = $snCount - $tableCountBefore

    $healAttempted = $false
    $healStatus = ''
    $tableCountAfter = $tableCountBefore
    $deltaAfter = $deltaBefore

    if ([math]::Abs($deltaBefore) -gt $DeltaThreshold -and $EnableAutoHeal) {
        $usedToday = 0
        if ($healAttemptsByWeek.ContainsKey($yw)) { $usedToday = [int]$healAttemptsByWeek[$yw] }

        if ($usedToday -lt $MaxAutoHealPerWeekPerDay) {
            $healAttempted = $true
            try {
                $healResult = Invoke-WeekAutoHeal -YearWeek $yw -BusinessServiceId $businessServiceId -ServiceOfferingId $serviceOfferingId -ResourceGroup $ResourceGroupName -AutomationAccount $AutomationAccountName -AnalyzerRunbook $AnalyzerRunbookName -AutoHealRunbook $AutoHealRunbookName -BackfillLookbackDays $AutoHealLookbackDays
                $healStatus = [string]$healResult.FinalStatus
                $anyAutoHealTriggered = $true
                $autoHealRunUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                $healAttemptsByWeek[$yw] = $usedToday + 1

                $tableCountAfter = Get-TableWeekCount -CloudTable $cloudTable -YearWeek $yw
                $deltaAfter = $snCount - $tableCountAfter
            }
            catch {
                $msg = [string]$_.Exception.Message
                if ($msg -match 'automationAccounts/jobs/write|AuthorizationFailed|does not have authorization') {
                    $healStatus = 'Skipped:AutoHealUnauthorized'
                    Write-Warning "Auto-heal skipped for $yw due to missing jobs/write permission."
                }
                else {
                    $healStatus = 'Failed:AutoHealError'
                    Write-Warning ("Auto-heal failed for {0}: {1}" -f $yw, $msg)
                }
            }
        }
        else {
            $healStatus = 'Skipped:DailyLimitReached'
        }
    }

    if ([math]::Abs($deltaAfter) -gt $DeltaThreshold) { $anyMismatchRemaining = $true }

    $results.Add([PSCustomObject]@{
        YearWeek = $yw
        ServiceNowCount = $snCount
        TableCountBefore = $tableCountBefore
        DeltaBefore = $deltaBefore
        HealAttempted = $healAttempted
        HealStatus = $healStatus
        TableCountAfter = $tableCountAfter
        DeltaAfter = $deltaAfter
    }) | Out-Null
}

$overallStatus = if ($anyMismatchRemaining) { 'Mismatch' } else { 'Healthy' }
$lastIngestionUtc = if ($overallStatus -eq 'Healthy') {
    (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
elseif (-not [string]::IsNullOrWhiteSpace($priorLastIngestionUtc)) {
    $priorLastIngestionUtc
}
else {
    ''
}

$latest = $results | Select-Object -First 1
$summary = if ($overallStatus -eq 'Healthy') {
    'Reconciliation passed. ServiceNow and table counts are aligned.'
} else {
    'Reconciliation mismatch detected. One or more weeks still have non-zero delta.'
}

$engineerSignals = @($results | Where-Object { $_.HealStatus -in @('Skipped:AutoHealUnauthorized', 'Failed:AutoHealError') })
$state = 'Healthy'
if ($overallStatus -eq 'Mismatch') { $state = 'Mismatch' }
if ($engineerSignals.Count -gt 0) { $state = 'Investigating' }

$freshnessDelayHours = [int](Get-OptVar -Name 'PT_ReconcileDelayHours' -Default 30)
$nowUtc = (Get-Date).ToUniversalTime()
$freshnessAgeHours = $null
if (-not [string]::IsNullOrWhiteSpace($lastIngestionUtc)) {
    try {
        $ing = [datetime]$lastIngestionUtc
        $freshnessAgeHours = [Math]::Round(($nowUtc - $ing).TotalHours, 2)
    }
    catch {
        $freshnessAgeHours = $null
    }
}
if ($state -eq 'Healthy' -and $null -ne $freshnessAgeHours -and $freshnessAgeHours -gt $freshnessDelayHours) {
    $state = 'Delayed'
}

$headline = ''
$detail = ''
switch ($state) {
    'Healthy' {
        $headline = ('Data is up to date as of {0} UTC.' -f $nowUtc.ToString('HH:mm'))
        $detail = 'Incident counts are aligned with ServiceNow for the checked weeks.'
    }
    'Delayed' {
        $lastLabel = if ([string]::IsNullOrWhiteSpace($lastIngestionUtc)) { 'an unknown time' } else { $lastIngestionUtc }
        $headline = 'Data refresh is delayed.'
        $detail = ('Last successful ingestion was at {0}. Dashboard may lag behind current incident flow.' -f $lastLabel)
    }
    'Mismatch' {
        $headline = 'We found a data mismatch in the latest reconciliation.'
        $detail = 'Counts between ServiceNow and dashboard data do not fully align yet.'
    }
    'Investigating' {
        $headline = 'Data checks are running with limited auto-heal access.'
        $detail = 'Dashboard data is visible, but automatic correction could not be completed in this run.'
    }
}

$healthPayload = @{
    service = 'Productivity Tools'
    displayState = $state
    headline = $headline
    detailMessage = $detail
    lastCheckedUtc = $nowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
    lastSuccessfulIngestionUtc = $lastIngestionUtc
    recommendedAction = if ($state -eq 'Healthy') { 'Continue normal operations.' } else { 'Use Engineer View for technical details and follow-up.' }
    engineer = @{
        overallStatus = $overallStatus
        latestCheckedWeek = [string]$latest.YearWeek
        latestDelta = [int]$latest.DeltaAfter
        latestServiceNowCount = [int]$latest.ServiceNowCount
        latestTableCount = [int]$latest.TableCountAfter
        deltaThreshold = [int]$DeltaThreshold
        autoHealEnabled = [bool]$EnableAutoHeal
        autoHealTriggered = [bool]$anyAutoHealTriggered
        autoHealLastRunUtc = [string]$autoHealRunUtc
        summary = $summary
        weekChecks = $results
        freshnessAgeHours = $freshnessAgeHours
    }
}

Set-HealthArtifact -ContainerName $cfg.ResultsContainerName -StorageContext $ctx -HealthPayload $healthPayload
Write-Step ('Health artifact updated in blob container {0} (health-status.json).' -f $cfg.ResultsContainerName)

if ($anyMismatchRemaining -and $SendAlertOnMismatch -and -not [string]::IsNullOrWhiteSpace([string]$cfg.WebhookUrl)) {
    $lines = @()
    $lines += 'Incident Reconciliation Alert: Productivity Tools'
    $lines += ''
    foreach ($r in $results) {
        $healLabel = if ([string]::IsNullOrWhiteSpace([string]$r.HealStatus)) { 'No' } else { [string]$r.HealStatus }
        $lines += ('{0}: SN={1}, TABLE(before)={2}, TABLE(after)={3}, DELTA(after)={4}, HEAL={5}' -f $r.YearWeek, $r.ServiceNowCount, $r.TableCountBefore, $r.TableCountAfter, $r.DeltaAfter, $healLabel)
    }
    $lines += ''
    $lines += ('Threshold={0}, AutoHealEnabled={1}' -f $DeltaThreshold, $EnableAutoHeal)

    try {
        $sent = Send-ReconcileAlert -WebhookUrl ([string]$cfg.WebhookUrl) -Subject '[Incident Analyzer] Reconciliation mismatch detected' -BodyText ($lines -join "`n")
        if ($sent) { Write-Step 'Mismatch alert sent via webhook.' }
    }
    catch {
        Write-Warning ('Failed to send webhook alert: ' + $_.Exception.Message)
    }
}

Write-Step ('Reconciliation completed. OverallStatus=' + $overallStatus)
$results | Format-Table -AutoSize | Out-String | Write-Output
