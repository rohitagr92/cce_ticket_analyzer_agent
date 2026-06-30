<#
.SYNOPSIS
    Count incidents per work week from the local ServiceNow export file
    and display a sorted summary by week.

.DESCRIPTION
    Reads the raw JSON export from local-input/pt_incidents_6m.json and groups
    all incidents by their resolved_at date into ISO work-week buckets (YYYY-Www).
    Useful for verifying how many incidents ServiceNow has per week before
    comparing against the Azure Table counts.

.NOTES
    Requires: local-input/pt_incidents_6m.json (ServiceNow export file, not committed to repo).
    Read-only local utility — no Azure connection needed.

.USAGE
    .\tools\count_weeks.ps1
#>

# Load the local ServiceNow incident export (raw JSON from the SN API)
$j = Get-Content "$PSScriptRoot\..\local-input\pt_incidents_6m.json" -Raw | ConvertFrom-Json
# Group each incident into a YYYY-Www bucket based on its resolved_at date
$weeks = @()
foreach ($inc in $j.incidents) {
    if (-not $inc.resolved_at) { continue }
    $d = [DateTime]::ParseExact($inc.resolved_at, 'yyyy-MM-dd HH:mm:ss', $null)
    $y = $d.Year
    # ISO week calculation: find the Sunday before Jan 1 that anchors week 1
    $jan1     = (Get-Date -Year $y -Month 1 -Day 1).Date
    $week1Sun = $jan1.AddDays(-1 * [int]$jan1.DayOfWeek)
    $wkn      = [int]([Math]::Floor((($d.Date - $week1Sun).TotalDays) / 7) + 1)
    $weeks   += ("{0}-W{1}" -f $y, $wkn)
}

# Display all weeks sorted by incident count descending so the busiest weeks appear first
$groups = $weeks | Group-Object | Sort-Object Count -Descending
$groups | Format-Table Name, Count -AutoSize

# Highlight the two most recently tracked weeks for quick reference
Write-Host "`nWW25 count:"; ($groups | Where-Object { $_.Name -eq '2026-W25' } | Select-Object -ExpandProperty Count)
Write-Host "WW26 count:"; ($groups | Where-Object { $_.Name -eq '2026-W26' } | Select-Object -ExpandProperty Count)
