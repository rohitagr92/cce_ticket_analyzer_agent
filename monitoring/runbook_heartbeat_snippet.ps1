# Runbook heartbeat snippet — call at job start and job end/failure
# Requires: $WorkspaceId, $WorkspaceKey (Log Analytics workspace) configured as Automation variables or retrieved securely

function Send-LogAnalyticsHeartbeat {
    param(
        [Parameter(Mandatory=$true)][string]$WorkspaceId,
        [Parameter(Mandatory=$true)][string]$WorkspaceKey,
        [Parameter(Mandatory=$true)][string]$LogType, # e.g. 'IncidentAnalyzerHeartbeat'
        [Parameter(Mandatory=$true)][hashtable]$Body
    )

    $customerId = $WorkspaceId
    $sharedKey = $WorkspaceKey
    $logType = $LogType
    $json = ($Body | ConvertTo-Json -Depth 5)
    $contentLength = $json.Length
    $rfc1123date = (Get-Date).ToUniversalTime().ToString('r')

    $stringToHash = "POST\n$contentLength\napplication/json\nx-ms-date:$rfc1123date\n/api/logs"
    $bytesToHash = [System.Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)
    $hmacsha256 = New-Object System.Security.Cryptography.HMACSHA256 $keyBytes
    $calculatedHash = $hmacsha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $signature = "SharedKey $customerId:$encodedHash"

    $uri = "https://$customerId.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"

    $headers = @{
        'Authorization' = $signature
        'Log-Type'      = $logType
        'x-ms-date'     = $rfc1123date
        'time-generated-field' = (Get-Date).ToString('o')
        'Content-Type'  = 'application/json'
    }

    try {
        Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $json -ContentType 'application/json' -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to send heartbeat to Log Analytics: $($_.Exception.Message)"
    }
}

# Example usage inside runbook:
# $LAWorkspaceId = Get-AutomationVariable -Name 'LAWorkspaceId'
# $LAWorkspaceKey = Get-AutomationVariable -Name 'LAWorkspaceKey'
# $startBody = @{ jobId = $($env:JOB_ID); jobName = 'incident-analyzer-rb-prodtools'; status = 'Started'; startTime = (Get-Date).ToString('o') }
# Send-LogAnalyticsHeartbeat -WorkspaceId $LAWorkspaceId -WorkspaceKey $LAWorkspaceKey -LogType 'IncidentAnalyzerHeartbeat' -Body $startBody

# On completion:
# $endBody = @{ jobId = $($env:JOB_ID); jobName = 'incident-analyzer-rb-prodtools'; status = 'Completed'; startTime = $startTime; endTime = (Get-Date).ToString('o'); processedCount = $ProcessedTickets.Count; errorCount = $ErrorCount }
# Send-LogAnalyticsHeartbeat -WorkspaceId $LAWorkspaceId -WorkspaceKey $LAWorkspaceKey -LogType 'IncidentAnalyzerHeartbeat' -Body $endBody
