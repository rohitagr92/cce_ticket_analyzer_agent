param(
    [Parameter(Mandatory)][string]$JobId,
    [int]$PollSeconds = 30,
    [int]$TimeoutMinutes = 120
)

$ErrorActionPreference = 'Stop'
$rg = 'OPSW-Ticket-Analyzer'
$aa = 'OPSW-ProductivityTools-account'

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$lastStatus = ''
while ((Get-Date) -lt $deadline) {
    $job = Get-AzAutomationJob -ResourceGroupName $rg -AutomationAccountName $aa -Id $JobId
    if ($job.Status -ne $lastStatus) {
        Write-Host ("[{0:HH:mm:ss}] Status: {1}" -f (Get-Date), $job.Status)
        $lastStatus = $job.Status
    }
    if ($job.Status -in @('Completed', 'Failed', 'Stopped', 'Suspended')) {
        Write-Host ("Final status: {0}  StartTime: {1}  EndTime: {2}" -f $job.Status, $job.StartTime, $job.EndTime)
        return $job.Status
    }
    Start-Sleep -Seconds $PollSeconds
}
Write-Host "Timeout after $TimeoutMinutes minutes (status=$lastStatus)"
return $lastStatus
