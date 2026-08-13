[CmdletBinding()]
param(
    [int]$WeeksToCheck = 0,
    [int]$DeltaThreshold = -1,
    [switch]$AutoHeal
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message, [string]$Level = 'INFO')
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
}

function Get-OptVar {
    param([string]$Name, $Default)
    try {
        $v = Get-AutomationVariable -Name $Name -ErrorAction Stop
        if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) { return $Default }
        return $v
    } catch {
        return $Default
    }
}

function Get-BooleanValue {
    param($Value, [bool]$Default = $false)
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }
    $s = ([string]$Value).Trim().ToLowerInvariant()
    if ($s -in @('true','1','yes','y')) { return $true }
    if ($s -in @('false','0','no','n')) { return $false }
    return $Default
}

function Get-YearWeekFromDate {
    param([Parameter(Mandatory)][DateTime]$Date)
    $localDate = $Date.Date
    $yearStart = [DateTime]::new($localDate.Year, 1, 1)
    $week1Start = $yearStart.AddDays(-[int]$yearStart.DayOfWeek)
    $wn = [int][Math]::Floor(($localDate - $week1Start).TotalDays / 7) + 1
    return ('{0:D4}-W{1:D2}' -f $localDate.Year, $wn)
}

function Get-RecentYearWeeks {
    param([int]$Count)
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $weeks = @()
    for ($i = 0; $i -lt ($Count + 1); $i++) {
        $d = (Get-Date).ToUniversalTime().AddDays(-7 * $i)
        $yw = Get-YearWeekFromDate -Date $d
        if ($set.Add($yw)) { $weeks += $yw }
    }
    return $weeks
}

function Get-WeekUtcWindow {
    param([Parameter(Mandatory)][string]$YearWeek)

    if ($YearWeek -notmatch '^(?<y>\d{4})-W(?<w>\d{1,2})$') { throw "Invalid YearWeek: $YearWeek" }
    $year = [int]$Matches.y
    $wk = [int]$Matches.w

    $jan1 = (Get-Date -Year $year -Month 1 -Day 1).Date
    $dow = [int]$jan1.DayOfWeek
    $week1Sun = $jan1.AddDays(-1 * $dow)
    $weekStartIst = $week1Sun.AddDays(($wk - 1) * 7)
    $weekEndIst = $weekStartIst.AddDays(7).AddSeconds(-1)

    $istOffset = New-TimeSpan -Hours 5 -Minutes 30
    $startUtc = ($weekStartIst - $istOffset)
    $endUtc = ($weekEndIst - $istOffset)

    return [PSCustomObject]@{
        StartUtc = $startUtc
        EndUtc = $endUtc
        StartEncoded = $startUtc.ToString('yyyy-MM-dd HH:mm:ss') -replace ' ', '%20'
        EndEncoded = $endUtc.ToString('yyyy-MM-dd HH:mm:ss') -replace ' ', '%20'
    }
}

function Get-ServiceNowToken {
    param([hashtable]$Config)

    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $Config.ServiceNowIncidentsClientID
        client_secret = $Config.ServiceNowIncidentsClientSecret
        scope         = $Config.ServiceNowIncidentsScope
    }

    $token = Invoke-RestMethod -Method Post -Uri $Config.TokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded'
    return [string]$token.access_token
}

function Get-ScopedServiceNowUrl {
    param(
        [Parameter(Mandatory)][string]$YearWeek,
        [Parameter(Mandatory)][string]$BusinessServiceId,
        [Parameter(Mandatory)][string]$ServiceOfferingId
    )

    $w = Get-WeekUtcWindow -YearWeek $YearWeek
    $query = "business_service=$BusinessServiceId^service_offering=$ServiceOfferingId^stateIN6,7^resolved_at>=$($w.StartEncoded)^resolved_at<=$($w.EndEncoded)^ORDERBYDESCresolved_at"
    return "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=$query&sysparm_display_value=true&sysparm_limit=2000"
}

function Get-ServiceNowIncidentIdsForWeek {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$AccessToken,
        [Parameter(Mandatory)][string]$YearWeek
    )

    $url = Get-ScopedServiceNowUrl -YearWeek $YearWeek -BusinessServiceId $Config.PT_BusinessServiceId -ServiceOfferingId $Config.PT_ServiceOfferingId
    $headers = @{ Authorization = "Bearer $AccessToken"; Accept = 'application/json' }
    $resp = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -TimeoutSec 180

    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in @($resp.result)) {
        $n = [string]$r.number
        if (-not [string]::IsNullOrWhiteSpace($n)) { $null = $ids.Add($n.Trim()) }
    }
    return $ids
}

function Get-TableRowsForWeek {
    param(
        [Parameter(Mandatory)][object]$StorageContext,
        [Parameter(Mandatory)][string]$StorageAccount,
        [Parameter(Mandatory)][string]$TableName,
        [Parameter(Mandatory)][string]$YearWeek
    )

    $sas = New-AzStorageTableSASToken -Name $TableName -Permission 'r' -ExpiryTime (Get-Date).AddMinutes(20) -Protocol HttpsOnly -Context $StorageContext
    $baseUri = "https://$StorageAccount.table.core.windows.net/$TableName()?`$filter=PartitionKey eq '$YearWeek'&$sas"

    $rows = @()
    $next = $baseUri
    while ($next) {
        $r = Invoke-WebRequest -Uri $next -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
        $rows += ((ConvertFrom-Json $r.Content).value)
        $npk = $r.Headers['x-ms-continuation-NextPartitionKey']
        $nrk = $r.Headers['x-ms-continuation-NextRowKey']
        if ($npk) {
            $next = $baseUri + '&NextPartitionKey=' + [Uri]::EscapeDataString([string]$npk)
            if ($nrk) { $next += '&NextRowKey=' + [Uri]::EscapeDataString([string]$nrk) }
        } else {
            $next = $null
        }
    }
    return @($rows)
}

function Get-SectionValue {
    param([string]$Source, [string]$Label, [string]$NextLabel)

    if ([string]::IsNullOrWhiteSpace($Source)) { return '' }
    $pattern = "(?ims)^\s*$([regex]::Escape($Label))\s*:\s*(.*?)\s*(?=\n\s*$([regex]::Escape($NextLabel))\s*:|$)"
    $m = [regex]::Match($Source, $pattern)
    if (-not $m.Success) { return '' }
    return ($m.Groups[1].Value -replace '\s+', ' ').Trim(' ', '.', ',', ';', ':')
}

function Test-BadQualityText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    $v = ($Value -replace '\s+', ' ').Trim().ToLowerInvariant()
    if ($v.Length -lt 12) { return $true }
    if ($v -match '^(not documented|unknown|n/?a|nil|null|none|na)$') { return $true }
    if ($v -match '^(issue|root cause|resolution|evidence|ai analysis)\s*:?$') { return $true }
    if ($v -match 'manual review recommended for proper categorization') { return $true }
    if ($v -match 'safe fallback categorization') { return $true }
    return $false
}

function Get-BadQualityRowIds {
    param([array]$Rows)

    $bad = @()
    foreach ($row in @($Rows)) {
        $ai = [string]$row.AIAnalysis
        $problem = Get-SectionValue -Source $ai -Label 'Problem' -NextLabel 'Root Cause'
        $root = Get-SectionValue -Source $ai -Label 'Root Cause' -NextLabel 'Resolution'
        $resolution = Get-SectionValue -Source $ai -Label 'Resolution' -NextLabel 'Evidence'
        $evidence = Get-SectionValue -Source $ai -Label 'Evidence' -NextLabel 'AI Analysis'
        $analysisMatch = [regex]::Match($ai, '(?ims)^\s*AI\s*Analysis\s*(?:\([^)]*\))?\s*:\s*(.*?)\s*$')
        $analysis = if ($analysisMatch.Success) { ($analysisMatch.Groups[1].Value -replace '\s+', ' ').Trim(' ', '.', ',', ';', ':') } else { '' }

        if ((Test-BadQualityText -Value $problem) -or
            (Test-BadQualityText -Value $root) -or
            (Test-BadQualityText -Value $resolution) -or
            (Test-BadQualityText -Value $evidence) -or
            (Test-BadQualityText -Value $analysis)) {
            $bad += [string]$row.RowKey
        }
    }
    return @($bad | Sort-Object -Unique)
}

function Get-AutoHealState {
    param([string]$VariableName)

    $raw = [string](Get-OptVar -Name $VariableName -Default '{"date":"","attempts":{}}')
    try {
        $obj = $raw | ConvertFrom-Json -Depth 8
        return [PSCustomObject]@{
            date = [string]$obj.date
            attempts = if ($obj.attempts) { $obj.attempts } else { @{} }
        }
    } catch {
        return [PSCustomObject]@{ date = ''; attempts = @{} }
    }
}

function Save-AutoHealState {
    param(
        [string]$ResourceGroupName,
        [string]$AutomationAccountName,
        [string]$VariableName,
        [string]$DateKey,
        [hashtable]$Attempts
    )

    $json = [PSCustomObject]@{ date = $DateKey; attempts = $Attempts } | ConvertTo-Json -Depth 8 -Compress
    Set-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $VariableName -Value $json -Encrypted $false | Out-Null
}

function Invoke-WeekAutoHeal {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$YearWeek,
        [Parameter(Mandatory)][int]$MaxPollMinutes
    )

    $newUrl = Get-ScopedServiceNowUrl -YearWeek $YearWeek -BusinessServiceId $Config.PT_BusinessServiceId -ServiceOfferingId $Config.PT_ServiceOfferingId
    $origUrlVar = Get-AzAutomationVariable -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Name 'ServiceNowIncidentsURL' -ErrorAction Stop
    $origLookVar = Get-AzAutomationVariable -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Name 'DailyLookbackHours' -ErrorAction SilentlyContinue
    $origBfVar = Get-AzAutomationVariable -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Name 'BackfillYearWeek' -ErrorAction SilentlyContinue

    try {
        Set-AzAutomationVariable -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Name 'ServiceNowIncidentsURL' -Value $newUrl -Encrypted $false | Out-Null
        Set-AzAutomationVariable -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Name 'DailyLookbackHours' -Value '0' -Encrypted $false | Out-Null
        if ($origBfVar) {
            Set-AzAutomationVariable -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Name 'BackfillYearWeek' -Value $YearWeek -Encrypted $false | Out-Null
        } else {
            New-AzAutomationVariable -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Name 'BackfillYearWeek' -Value $YearWeek -Encrypted $false | Out-Null
        }

        Write-Step "Auto-heal started for $YearWeek via incident-analyzer-rb-prodtools." 'WARN'
        $job = Start-AzAutomationRunbook -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Name 'incident-analyzer-rb-prodtools'
        $jobId = $job.JobId
        $maxIter = [int](($MaxPollMinutes * 60) / 30)

        for ($i = 0; $i -lt $maxIter; $i++) {
            $j = Get-AzAutomationJob -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Id $jobId
            Write-Step "Auto-heal job $jobId status: $($j.Status)"
            if ($j.Status -in @('Completed','Failed','Stopped','Suspended')) {
                return ($j.Status -eq 'Completed')
            }
            Start-Sleep -Seconds 30
        }

        Write-Step "Auto-heal timeout for $YearWeek" 'ERROR'
        return $false
    }
    finally {
        try {
            Set-AzAutomationVariable -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Name 'ServiceNowIncidentsURL' -Value $origUrlVar.Value -Encrypted $false | Out-Null
            if ($origLookVar) {
                Set-AzAutomationVariable -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Name 'DailyLookbackHours' -Value $origLookVar.Value -Encrypted $false | Out-Null
            }
            Set-AzAutomationVariable -ResourceGroupName $Config.ResourceGroupName -AutomationAccountName $Config.AutomationAccountName -Name 'BackfillYearWeek' -Value '' -Encrypted $false | Out-Null
            Write-Step 'Restored ServiceNowIncidentsURL/DailyLookbackHours/BackfillYearWeek after auto-heal.'
        } catch {
            Write-Step "Failed to restore automation variables after auto-heal: $($_.Exception.Message)" 'ERROR'
        }
    }
}

Write-Step 'Starting Productivity Tools quality guard runbook.'

Disable-AzContextAutosave -Scope Process | Out-Null
$null = Connect-AzAccount -Identity -ErrorAction Stop

$config = @{
    SubscriptionId                  = [string](Get-OptVar -Name 'Incidents_analyzer_SubscriptionId' -Default '')
    ResourceGroupName               = [string](Get-OptVar -Name 'Incidents_analyzer_ResourceGroupName' -Default '')
    AutomationAccountName           = [string](Get-OptVar -Name 'Incidents_analyzer_AutomationAccountName' -Default 'OPSW-ProductivityTools-account')
    StorageAccountName              = [string](Get-OptVar -Name 'Incidents_analyzer_StorageAccountName' -Default '')
    TableName                       = [string](Get-OptVar -Name 'PT_TrendTableName' -Default 'IncidentsCategoryStats')
    PT_BusinessServiceId            = [string](Get-OptVar -Name 'PT_BusinessServiceId' -Default 'a1de2ff2db8f50108062531dd3961911')
    PT_ServiceOfferingId            = [string](Get-OptVar -Name 'PT_ServiceOfferingId' -Default 'fcb18407dbcf50108062531dd39619c4')
    ServiceNowIncidentsClientID     = [string](Get-OptVar -Name 'ServiceNowIncidentsClientID' -Default '')
    ServiceNowIncidentsClientSecret = [string](Get-OptVar -Name 'ServiceNowIncidentsClientSecret' -Default '')
    ServiceNowIncidentsScope        = [string](Get-OptVar -Name 'ServiceNowIncidentsScope' -Default '')
    TokenUrl                        = [string](Get-OptVar -Name 'TokenUrl' -Default '')
}

if ([string]::IsNullOrWhiteSpace($config.SubscriptionId)) { throw 'Incidents_analyzer_SubscriptionId is required.' }
if ([string]::IsNullOrWhiteSpace($config.ResourceGroupName)) { throw 'Incidents_analyzer_ResourceGroupName is required.' }
if ([string]::IsNullOrWhiteSpace($config.StorageAccountName)) { throw 'Incidents_analyzer_StorageAccountName is required.' }
if ([string]::IsNullOrWhiteSpace($config.ServiceNowIncidentsClientID) -or
    [string]::IsNullOrWhiteSpace($config.ServiceNowIncidentsClientSecret) -or
    [string]::IsNullOrWhiteSpace($config.ServiceNowIncidentsScope) -or
    [string]::IsNullOrWhiteSpace($config.TokenUrl)) {
    throw 'ServiceNow auth variables are required.'
}

$null = Set-AzContext -Subscription $config.SubscriptionId -ErrorAction Stop
$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $config.ResourceGroupName -Name $config.StorageAccountName)[0].Value
$storageContext = New-AzStorageContext -StorageAccountName $config.StorageAccountName -StorageAccountKey $storageKey

if ($WeeksToCheck -le 0) { $WeeksToCheck = [int](Get-OptVar -Name 'PT_ReconcileWeeksToCheck' -Default 2) }
if ($DeltaThreshold -lt 0) { $DeltaThreshold = [int](Get-OptVar -Name 'PT_ReconcileDeltaThreshold' -Default 0) }
$enableAutoHeal = if ($AutoHeal.IsPresent) { $true } else { Get-BooleanValue (Get-OptVar -Name 'PT_ReconcileEnableAutoHeal' -Default $true) $true }
$maxHealPerWeek = [int](Get-OptVar -Name 'PT_ReconcileMaxHealPerWeekPerDay' -Default 1)
$stateVarName = 'PT_ReconcileAutoHealState'
$todayKey = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')

$state = Get-AutoHealState -VariableName $stateVarName
$attempts = @{}
if ($state.date -eq $todayKey) {
    foreach ($p in $state.attempts.PSObject.Properties) {
        $attempts[[string]$p.Name] = [int]$p.Value
    }
}

Write-Step "Config: WeeksToCheck=$WeeksToCheck DeltaThreshold=$DeltaThreshold AutoHeal=$enableAutoHeal MaxHealPerWeekPerDay=$maxHealPerWeek"

$token = Get-ServiceNowToken -Config $config
$targetWeeks = Get-RecentYearWeeks -Count $WeeksToCheck

$hasFailures = $false
foreach ($week in $targetWeeks) {
    Write-Step "Validating $week"

    $sourceIds = Get-ServiceNowIncidentIdsForWeek -Config $config -AccessToken $token -YearWeek $week
    $rows = Get-TableRowsForWeek -StorageContext $storageContext -StorageAccount $config.StorageAccountName -TableName $config.TableName -YearWeek $week

    $tableIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($rows)) {
        $rk = [string]$row.RowKey
        if (-not [string]::IsNullOrWhiteSpace($rk)) { $null = $tableIds.Add($rk.Trim()) }
    }

    $missing = @()
    foreach ($sid in $sourceIds) {
        if (-not $tableIds.Contains([string]$sid)) { $missing += [string]$sid }
    }

    $sourceMinusTable = $sourceIds.Count - $tableIds.Count
    $deltaAbs = [Math]::Abs($sourceMinusTable)
    $sourceShortfall = [Math]::Max(0, $sourceMinusTable)
    $tableExcess = [Math]::Max(0, -1 * $sourceMinusTable)
    $badRows = Get-BadQualityRowIds -Rows $rows

    Write-Step ("Week {0}: source={1} table={2} deltaAbs={3} shortfall={4} tableExcess={5} missing={6} badQuality={7}" -f $week, $sourceIds.Count, $tableIds.Count, $deltaAbs, $sourceShortfall, $tableExcess, $missing.Count, $badRows.Count)

    # Fail only when the source has incidents that are missing from table output,
    # or when mandatory structured analysis quality is violated.
    $weekFailed = ($sourceShortfall -gt $DeltaThreshold) -or ($missing.Count -gt 0) -or ($badRows.Count -gt 0)

    if ($weekFailed -and $enableAutoHeal) {
        $attemptCount = if ($attempts.ContainsKey($week)) { [int]$attempts[$week] } else { 0 }
        if ($attemptCount -lt $maxHealPerWeek) {
            $attempts[$week] = $attemptCount + 1
                Save-AutoHealState -ResourceGroupName $config.ResourceGroupName -AutomationAccountName $config.AutomationAccountName -VariableName $stateVarName -DateKey $todayKey -Attempts $attempts

            $healed = Invoke-WeekAutoHeal -Config $config -YearWeek $week -MaxPollMinutes 120
            if ($healed) {
                Write-Step "Re-validating $week after auto-heal."
                $sourceIds = Get-ServiceNowIncidentIdsForWeek -Config $config -AccessToken $token -YearWeek $week
                $rows = Get-TableRowsForWeek -StorageContext $storageContext -StorageAccount $config.StorageAccountName -TableName $config.TableName -YearWeek $week

                $tableIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($row in @($rows)) {
                    $rk = [string]$row.RowKey
                    if (-not [string]::IsNullOrWhiteSpace($rk)) { $null = $tableIds.Add($rk.Trim()) }
                }
                $missing = @()
                foreach ($sid in $sourceIds) {
                    if (-not $tableIds.Contains([string]$sid)) { $missing += [string]$sid }
                }
                $sourceMinusTable = $sourceIds.Count - $tableIds.Count
                $deltaAbs = [Math]::Abs($sourceMinusTable)
                $sourceShortfall = [Math]::Max(0, $sourceMinusTable)
                $tableExcess = [Math]::Max(0, -1 * $sourceMinusTable)
                $badRows = Get-BadQualityRowIds -Rows $rows
                $weekFailed = ($sourceShortfall -gt $DeltaThreshold) -or ($missing.Count -gt 0) -or ($badRows.Count -gt 0)

                Write-Step ("Post-heal {0}: source={1} table={2} deltaAbs={3} shortfall={4} tableExcess={5} missing={6} badQuality={7}" -f $week, $sourceIds.Count, $tableIds.Count, $deltaAbs, $sourceShortfall, $tableExcess, $missing.Count, $badRows.Count)
                if ($missing.Count -gt 0) {
                    Write-Step ("Missing IDs for {0}: {1}" -f $week, ($missing -join ',')) 'WARN'
                }
                if ($badRows.Count -gt 0) {
                    Write-Step ("Bad-quality IDs for {0}: {1}" -f $week, ($badRows -join ',')) 'WARN'
                }
            } else {
                Write-Step "Auto-heal job did not complete successfully for $week." 'ERROR'
            }
        } else {
            Write-Step "Auto-heal skipped for $week (attempt limit reached for $todayKey)." 'WARN'
        }
    }

    if ($weekFailed) {
        $hasFailures = $true
        if ($missing.Count -gt 0) {
            Write-Step ("Final missing IDs for {0}: {1}" -f $week, ($missing -join ',')) 'ERROR'
        }
        if ($badRows.Count -gt 0) {
            Write-Step ("Final bad-quality IDs for {0}: {1}" -f $week, ($badRows -join ',')) 'ERROR'
        }
    }
}

if ($hasFailures) {
    throw 'Quality guard failed: reconciliation mismatch and/or AIAnalysis quality violations remain after auto-heal.'
}

Write-Step 'Quality guard passed for all checked weeks.' 'SUCCESS'
