$job = Start-AzAutomationRunbook -ResourceGroupName 'OPSW-Ticket-Analyzer' -AutomationAccountName 'OPSW-ProductivityTools-account' -Name 'incident-analyzer-rb-prodtools'
$jobId = $job.JobId
"JobId: $jobId"
for ($i=0; $i -lt 40; $i++) {
    $j = Get-AzAutomationJob -ResourceGroupName 'OPSW-Ticket-Analyzer' -AutomationAccountName 'OPSW-ProductivityTools-account' -Id $jobId
    Write-Host ("[{0}] Status: {1}" -f (Get-Date -Format HH:mm:ss), $j.Status)
    if ($j.Status -in 'Completed','Failed','Stopped','Suspended') { break }
    Start-Sleep -Seconds 20
}
if ($j.Exception) { Write-Host "Exception: $($j.Exception)" -ForegroundColor Red }
$jobId | Set-Content (Join-Path $PSScriptRoot 'last-job-id.txt')
