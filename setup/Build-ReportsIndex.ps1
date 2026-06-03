<#
.SYNOPSIS
    Build and upload index.json for the Static Web App dashboard.

.DESCRIPTION
    Scans the 'results' blob container for HTML reports, groups them by
    work-week (YYYY-Wnn), and uploads a manifest the web/index.html consumes.
#>
[CmdletBinding()]
param(
    [string]$ResourceGroupName   = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccountName  = 'opswprodtoolsblob',
    [string]$ContainerName       = 'results'
)

$ErrorActionPreference = 'Stop'

$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $key

$blobs = Get-AzStorageBlob -Container $ContainerName -Context $ctx | Where-Object { $_.Name -like '*.html' }
Write-Host "Found $($blobs.Count) HTML blobs in '$ContainerName'."

$reports = @()
$trends  = @()
$runs    = @{}
foreach ($b in $blobs) {
    if ($b.Name -notmatch '(\d{4})-W(\d{2})') { continue }
    $weekKey = "$($matches[1])-W$($matches[2])"
    $label   = "WW$($matches[2]) $($matches[1])"
    $generated = $b.LastModified.UtcDateTime.ToString('o')
    $sizeKb = [Math]::Round($b.Length / 1KB, 1)

    $entry = [ordered]@{
        week_label   = $label
        run_id       = $weekKey
        generated_at = $generated
        blob         = $b.Name
        size_kb      = $sizeKb
    }

    if ($b.Name -match 'Trend_Analysis') {
        $trends += [pscustomobject]$entry
    } elseif ($b.Name -match 'Weekly_Report|Weekly_Dashboard|Detailed') {
        $reports += [pscustomobject]$entry
    } else {
        $reports += [pscustomobject]$entry
    }

    # legacy combined view kept for backward compatibility
    if (-not $runs.ContainsKey($weekKey)) {
        $runs[$weekKey] = [ordered]@{
            week_label         = $label
            run_id             = $weekKey
            generated_at       = $generated
            ticket_count       = 0
            dashboard_blob     = $null
            strict_report_blob = $null
        }
    }
    $r = $runs[$weekKey]
    if ($b.Name -match 'Trend_Analysis') {
        $r.strict_report_blob = $b.Name
    } else {
        $r.dashboard_blob = $b.Name
        $r.generated_at   = $generated
    }
}

$index = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    reports      = @($reports | Sort-Object run_id -Descending)
    trends       = @($trends  | Sort-Object run_id -Descending)
    runs         = @($runs.Values | Sort-Object { $_.run_id } -Descending)
}

$tmp = Join-Path $env:TEMP 'index.json'
$index | ConvertTo-Json -Depth 5 | Out-File -FilePath $tmp -Encoding UTF8 -NoNewline

$null = Set-AzStorageBlobContent -File $tmp -Container $ContainerName -Blob 'index.json' -Context $ctx -Properties @{ ContentType = 'application/json' } -Force
Write-Host "Uploaded index.json ($($runs.Count) runs)." -ForegroundColor Green
Get-Content $tmp
