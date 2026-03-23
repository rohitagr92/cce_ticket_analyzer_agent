<#
.SYNOPSIS
    Generate direct access URLs for HTML reports in blob storage using SAS tokens.

.DESCRIPTION
    Creates time-limited SAS (Shared Access Signature) tokens for accessing HTML reports
    stored in the "results" blob container. Generates URLs that can be shared securely.

.NOTES
    This is the quickest way to view reports - no infrastructure deployment needed.
    
    Security: SAS tokens are time-limited and provide read-only access.
    URLs can be shared but will expire after the specified duration.
#>

param(
    [string]$ResourceGroupName = "Incidents-analyzer-rg",
    [string]$StorageAccountName = "incidentsanalyzersa",
    [string]$ContainerName = "results",
    
    [ValidateSet('1hour', '1day', '1week', '1month', '1year')]
    [string]$TokenDuration = '1month',
    
    [switch]$ListAll,
    [switch]$OpenInBrowser
)

Write-Host "=== Report Viewer - SAS URL Generator ===" -ForegroundColor Cyan
Write-Host ""

try {
    # Check authentication
    $azContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $azContext) {
        Write-Host "Authenticating to Azure..." -ForegroundColor Yellow
        Connect-AzAccount -DeviceCode -ErrorAction Stop
    }
    
    Write-Host "✓ Authenticated as: $($azContext.Account.Id)" -ForegroundColor Green
    Write-Host ""
    
    # Get storage context
    Write-Host "Connecting to storage account: $StorageAccountName..." -ForegroundColor Yellow
    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
    $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageKey
    Write-Host "✓ Connected to storage account" -ForegroundColor Green
    Write-Host ""
    
    # Get reports
    Write-Host "Retrieving reports from '$ContainerName' container..." -ForegroundColor Yellow
    $reports = Get-AzStorageBlob -Container $ContainerName -Context $ctx -ErrorAction Stop | 
        Where-Object { $_.Name -like "*.html" } |
        Sort-Object LastModified -Descending
    
    if ($reports.Count -eq 0) {
        Write-Host "⚠ No HTML reports found in container '$ContainerName'" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Note: Reports are saved to this container when the runbook runs without a webhook URL configured." -ForegroundColor Gray
        exit 0
    }
    
    Write-Host "✓ Found $($reports.Count) report(s)" -ForegroundColor Green
    Write-Host ""
    
    # Calculate expiry time
    $startTime = Get-Date
    $expiryTime = switch ($TokenDuration) {
        '1hour'  { $startTime.AddHours(1) }
        '1day'   { $startTime.AddDays(1) }
        '1week'  { $startTime.AddDays(7) }
        '1month' { $startTime.AddMonths(1) }
        '1year'  { $startTime.AddYears(1) }
    }
    
    # Generate container-level SAS token (works for all files)
    Write-Host "Generating SAS token (valid until: $($expiryTime.ToString('yyyy-MM-dd HH:mm')))..." -ForegroundColor Yellow
    $sasToken = New-AzStorageContainerSASToken -Name $ContainerName `
        -Context $ctx `
        -Permission r `
        -StartTime $startTime `
        -ExpiryTime $expiryTime
    
    Write-Host "✓ SAS token generated" -ForegroundColor Green
    Write-Host ""
    
    # Display reports
    Write-Host "=== Available Reports ===" -ForegroundColor Cyan
    Write-Host ""
    
    $reportList = @()
    $index = 1
    
    foreach ($report in $reports) {
        $url = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$($report.Name)$sasToken"
        
        $reportInfo = [PSCustomObject]@{
            Index = $index
            Name = $report.Name
            Date = $report.LastModified.LocalDateTime.ToString('yyyy-MM-dd HH:mm')
            Size = "$([math]::Round($report.Length/1KB, 1)) KB"
            URL = $url
        }
        
        $reportList += $reportInfo
        
        if ($ListAll -or $index -eq 1) {
            Write-Host "[$index] $($report.Name)" -ForegroundColor White
            Write-Host "    Date: $($reportInfo.Date)" -ForegroundColor Gray
            Write-Host "    Size: $($reportInfo.Size)" -ForegroundColor Gray
            Write-Host "    URL: $url" -ForegroundColor Cyan
            Write-Host ""
        }
        
        $index++
    }
    
    if (-not $ListAll -and $reports.Count -gt 1) {
        Write-Host "[2-$($reports.Count)] ... $($reports.Count - 1) more report(s) (use -ListAll to show)" -ForegroundColor Gray
        Write-Host ""
    }
    
    # Get latest report URL
    $latestUrl = $reportList[0].URL
    
    Write-Host "=== Quick Actions ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Latest Report URL (copied to clipboard):" -ForegroundColor Green
    Write-Host $latestUrl -ForegroundColor White
    Set-Clipboard -Value $latestUrl
    Write-Host "✓ URL copied to clipboard" -ForegroundColor Green
    Write-Host ""
    
    # Save all URLs to file
    $urlsFile = ".\report-urls.txt"
    $urlsContent = @"
MDM AI Analysis - Report URLs
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Valid Until: $($expiryTime.ToString('yyyy-MM-dd HH:mm:ss'))
Storage Account: $StorageAccountName
Container: $ContainerName

===== REPORTS =====

"@
    
    foreach ($report in $reportList) {
        $urlsContent += @"
[$($report.Index)] $($report.Name)
Date: $($report.Date) | Size: $($report.Size)
$($report.URL)

"@
    }
    
    $urlsContent | Set-Content -Path $urlsFile -Encoding UTF8
    Write-Host "✓ All URLs saved to: $urlsFile" -ForegroundColor Green
    Write-Host ""
    
    # Open in browser if requested
    if ($OpenInBrowser) {
        Write-Host "Opening latest report in browser..." -ForegroundColor Yellow
        Start-Process $latestUrl
        Write-Host "✓ Report opened in default browser" -ForegroundColor Green
        Write-Host ""
    }
    
    # Export to CSV for Excel
    $csvFile = ".\report-urls.csv"
    $reportList | Select-Object Index, Name, Date, Size, URL | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
    Write-Host "✓ Report list exported to CSV: $csvFile" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "=== Usage Instructions ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "View Latest Report:" -ForegroundColor White
    Write-Host "  1. Paste the URL from clipboard into your browser" -ForegroundColor Gray
    Write-Host "  OR" -ForegroundColor Gray
    Write-Host "  2. Run: .\Get-ReportUrls.ps1 -OpenInBrowser" -ForegroundColor Gray
    Write-Host ""
    Write-Host "View All Reports:" -ForegroundColor White
    Write-Host "  1. Open: $urlsFile" -ForegroundColor Gray
    Write-Host "  2. Click any URL to view that report" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Share Reports:" -ForegroundColor White
    Write-Host "  - URLs are valid until: $($expiryTime.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Gray
    Write-Host "  - Recipients need the full URL (including SAS token)" -ForegroundColor Gray
    Write-Host "  - No authentication required (read-only access)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Generate New Tokens:" -ForegroundColor White
    Write-Host "  .\Get-ReportUrls.ps1 -TokenDuration 1week" -ForegroundColor Gray
    Write-Host "  Options: 1hour, 1day, 1week, 1month, 1year" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "=== Security Notes ===" -ForegroundColor Yellow
    Write-Host "• SAS tokens provide time-limited, read-only access" -ForegroundColor Gray
    Write-Host "• URLs can be shared but will expire after $TokenDuration" -ForegroundColor Gray
    Write-Host "• No write or delete permissions - reports are safe" -ForegroundColor Gray
    Write-Host "• Regenerate tokens after expiry by re-running this script" -ForegroundColor Gray
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "=== ERROR ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Common Issues:" -ForegroundColor Yellow
    Write-Host "  - Container '$ContainerName' doesn't exist: Run .\Create-BlobContainers.ps1" -ForegroundColor Gray
    Write-Host "  - No permissions: Ensure you have Reader role on storage account" -ForegroundColor Gray
    Write-Host "  - Storage account not found: Check ResourceGroupName and StorageAccountName" -ForegroundColor Gray
    exit 1
}
