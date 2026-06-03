$jobId = 'a1d3d6e2-28f9-4d3c-98c4-afd4be2af8d9'
$rg = 'OPSW-Ticket-Analyzer'
$aa = 'OPSW-ProductivityTools-account'

foreach ($s in 'Output','Error','Warning','Verbose','Progress','Debug','Any','Information') {
    try {
        $o = @(Get-AzAutomationJobOutput -ResourceGroupName $rg -AutomationAccountName $aa -Id $jobId -Stream $s -ErrorAction Stop)
        Write-Host "$s : $($o.Count) records"
        if ($o.Count -gt 0 -and $s -ne 'Progress') {
            $o | Select-Object -First 5 | ForEach-Object { "  > $($_.Summary)" }
        }
    } catch { Write-Host "$s : ERR $($_.Exception.Message)" -ForegroundColor Yellow }
}
