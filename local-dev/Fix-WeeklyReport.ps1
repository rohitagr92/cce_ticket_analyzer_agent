<#
.SYNOPSIS
    Fixes the EUC_Weekly_Report_2026-W10.html to consolidate individual "Excluded" 
    rows into a single aggregated row in the summary table.

.DESCRIPTION
    The original report had a bug where each Excluded ticket got its own row in the 
    summary table (with the exclusion reason appended to the category name), creating 
    ~17 separate "Excluded" rows each with count=1. This inflated the category count 
    from 19 to 36 and skewed the report.

    This script:
    1. Merges all "Excluded\nExclusion Reason:..." rows into one "Excluded" row
    2. Fixes the "Strict Categories Applied" stat from 36 to the correct count
    3. In the detail table, moves exclusion reasons from the category column into 
       a styled sub-line for cleaner display
    4. Saves the corrected HTML file (overwrites in-place, with backup)

.EXAMPLE
    .\Fix-WeeklyReport.ps1
#>

$reportPath = Join-Path $PSScriptRoot "results\EUC_Weekly_Report_2026-W10.html"

if (-not (Test-Path $reportPath)) {
    Write-Host "ERROR: Report not found at $reportPath" -ForegroundColor Red
    exit 1
}

Write-Host "Reading report: $reportPath" -ForegroundColor Cyan

# Create backup
$backupPath = $reportPath -replace '\.html$', '_BACKUP.html'
Copy-Item -Path $reportPath -Destination $backupPath -Force
Write-Host "Backup saved: $backupPath" -ForegroundColor DarkGray

$html = Get-Content -Path $reportPath -Raw

# ============================================================
# STEP 1: Fix the summary table - consolidate Excluded rows
# ============================================================
Write-Host "`nStep 1: Consolidating Excluded rows in summary table..." -ForegroundColor Yellow

# Find all Excluded rows in the summary table and collect their ticket links
# Pattern: <tr><td ...>Excluded\nExclusion Reason: ...</td><td ...>1</td><td>TICKET_LINKS</td></tr>
$excludedRowPattern = "        <tr><td style='font-weight:600;color:#0071c5;'>Excluded\r?\nExclusion Reason:[^<]*</td><td style='text-align:center;color:#0071c5;font-weight:bold;'>1</td><td>(<a [^<]+</a>)</td></tr>"

$excludedMatches = [regex]::Matches($html, $excludedRowPattern)
$excludedCount = $excludedMatches.Count

if ($excludedCount -eq 0) {
    Write-Host "  No individual Excluded rows found - report may already be fixed." -ForegroundColor Green
    exit 0
}

Write-Host "  Found $excludedCount individual Excluded rows to merge" -ForegroundColor White

# Collect all ticket links from excluded rows
$ticketLinks = @()
foreach ($match in $excludedMatches) {
    $ticketLinks += $match.Groups[1].Value
}

$mergedTicketLinks = $ticketLinks -join " "

# Build the single consolidated Excluded row
$consolidatedRow = "        <tr><td style='font-weight:600;color:#0071c5;'>Excluded</td><td style='text-align:center;color:#0071c5;font-weight:bold;'>$excludedCount</td><td>$mergedTicketLinks</td></tr>"

# Remove all individual Excluded rows from the HTML
$html = [regex]::Replace($html, "        <tr><td style='font-weight:600;color:#0071c5;'>Excluded\r?\nExclusion Reason:[^<]*</td><td style='text-align:center;color:#0071c5;font-weight:bold;'>1</td><td><a [^<]+</a></td></tr>\r?\n", "")

# Insert the consolidated row before the total row
$totalRowPattern = "        <tr class=`"total-row`">"
$html = $html -replace [regex]::Escape($totalRowPattern), "$consolidatedRow`n$totalRowPattern"

Write-Host "  Merged $excludedCount Excluded rows into 1 row (count=$excludedCount)" -ForegroundColor Green

# ============================================================
# STEP 2: Fix the "Strict Categories Applied" stat
# ============================================================
Write-Host "`nStep 2: Fixing category count stat..." -ForegroundColor Yellow

# Count distinct categories in the updated summary table
# The old count was 36 (19 real categories + 17 separate excluded entries)
# After merging, it should be 19 (18 actual + 1 Excluded)
$categoryRowPattern = "<tr><td style='font-weight:600;color:#0071c5;'>"
$categoryCount = ([regex]::Matches($html, [regex]::Escape($categoryRowPattern))).Count

$html = $html -replace "<div class=""stat-value"">36</div>\s*<div class=""stat-label"">Strict Categories Applied</div>", "<div class=""stat-value"">$categoryCount</div>`n                <div class=""stat-label"">Strict Categories Applied</div>"

Write-Host "  Updated category count: 36 -> $categoryCount" -ForegroundColor Green

# ============================================================
# STEP 3: Fix detail table - clean up Excluded category display
# ============================================================
Write-Host "`nStep 3: Cleaning up Excluded category in detail table..." -ForegroundColor Yellow

# In the detail table, the category column shows "Excluded\nExclusion Reason: ..."
# Replace with styled sub-line format
$detailExcludedPattern = "(<td style=""font-weight:600;color:#0071c5;font-size:12px;"">)Excluded\r?\nExclusion Reason: ([^<]+)</td>"
$detailExcludedReplacement = '${1}Excluded<br><span style="font-weight:normal;font-size:11px;color:#6c757d;">$2</span></td>'

$detailFixCount = ([regex]::Matches($html, $detailExcludedPattern)).Count
$html = [regex]::Replace($html, $detailExcludedPattern, $detailExcludedReplacement)

Write-Host "  Fixed $detailFixCount Excluded entries in detail table" -ForegroundColor Green

# ============================================================
# STEP 4: Save the fixed report
# ============================================================
Write-Host "`nStep 4: Saving fixed report..." -ForegroundColor Yellow

Set-Content -Path $reportPath -Value $html -Encoding UTF8 -NoNewline
Write-Host "  Saved: $reportPath" -ForegroundColor Green

# Summary
Write-Host "`n== Fix Complete ==" -ForegroundColor Cyan
Write-Host "  - Consolidated $excludedCount individual Excluded rows into 1" -ForegroundColor White
Write-Host "  - Category count corrected: 36 -> $categoryCount" -ForegroundColor White
Write-Host "  - Detail table exclusion reasons reformatted: $detailFixCount entries" -ForegroundColor White
Write-Host "  - Backup at: $backupPath" -ForegroundColor DarkGray
