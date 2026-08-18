$ErrorActionPreference = 'Stop'

$subId = '1c6d384e-bc83-4b02-859c-76eeb87f7676'
$rg = 'OPSW-Ticket-Analyzer'
$aa = 'OPSW-ProductivityTools-account'
$week = '2026-W33'

Connect-AzAccount -Subscription $subId | Out-Null
Set-AzContext -Subscription $subId | Out-Null

Write-Host "Authenticated subscription: $((Get-AzContext).Subscription.Name) / $((Get-AzContext).Subscription.Id)"

$origBackfill = Get-AzAutomationVariable -ResourceGroupName $rg -AutomationAccountName $aa -Name 'BackfillYearWeek' -ErrorAction SilentlyContinue
$origUrl = Get-AzAutomationVariable -ResourceGroupName $rg -AutomationAccountName $aa -Name 'ServiceNowIncidentsURL' -ErrorAction Stop
$origLook = Get-AzAutomationVariable -ResourceGroupName $rg -AutomationAccountName $aa -Name 'DailyLookbackHours' -ErrorAction SilentlyContinue

try {
    Set-AzAutomationVariable -ResourceGroupName $rg -AutomationAccountName $aa -Name 'BackfillYearWeek' -Value $week -Encrypted $false | Out-Null
    Set-AzAutomationVariable -ResourceGroupName $rg -AutomationAccountName $aa -Name 'ServiceNowIncidentsURL' -Value 'https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=assignment_group=bf2ca1dddb639c105447610ed39619dc^service_offering=fcb18407dbcf50108062531dd39619c4^business_service=a1de2ff2db8f50108062531dd3961911^state=6^ORstate=7^resolved_atONTHISWEEK^ORDERBYDESCresolved_at&sysparm_display_value=true&sysparm_limit=1000' -Encrypted $false | Out-Null
    Set-AzAutomationVariable -ResourceGroupName $rg -AutomationAccountName $aa -Name 'DailyLookbackHours' -Value '0' -Encrypted $false | Out-Null

    Write-Host "Starting WW33 repair runbook..."
    $job = Start-AzAutomationRunbook -ResourceGroupName $rg -AutomationAccountName $aa -Name 'incident-trend-backfill-rb-prodtools'
    Write-Host "JobId=$($job.JobId)"

    $finalStatus = ''
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 30
        $j = Get-AzAutomationJob -ResourceGroupName $rg -AutomationAccountName $aa -Id $job.JobId
        Write-Host "Status=$($j.Status)"
        if ($j.Status -in @('Completed','Failed','Stopped','Suspended')) {
            $finalStatus = $j.Status
            break
        }
    }

    if (-not $finalStatus) {
        throw 'Runbook timed out after 22.5 minutes.'
    }

    Write-Host "FinalStatus=$finalStatus"
}
finally {
    if ($origBackfill) {
        Set-AzAutomationVariable -ResourceGroupName $rg -AutomationAccountName $aa -Name 'BackfillYearWeek' -Value $origBackfill.Value -Encrypted $false | Out-Null
    }
    else {
        Set-AzAutomationVariable -ResourceGroupName $rg -AutomationAccountName $aa -Name 'BackfillYearWeek' -Value '' -Encrypted $false | Out-Null
    }

    Set-AzAutomationVariable -ResourceGroupName $rg -AutomationAccountName $aa -Name 'ServiceNowIncidentsURL' -Value $origUrl.Value -Encrypted $false | Out-Null

    if ($origLook) {
        Set-AzAutomationVariable -ResourceGroupName $rg -AutomationAccountName $aa -Name 'DailyLookbackHours' -Value $origLook.Value -Encrypted $false | Out-Null
    }
}
