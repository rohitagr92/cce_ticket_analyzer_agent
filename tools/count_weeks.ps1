$j = Get-Content "$PSScriptRoot\..\local-input\pt_incidents_6m.json" -Raw | ConvertFrom-Json
$weeks = @()
foreach ($inc in $j.incidents) {
    if (-not $inc.resolved_at) { continue }
    $d = [DateTime]::ParseExact($inc.resolved_at,'yyyy-MM-dd HH:mm:ss',$null)
    $y = $d.Year
    $jan1 = (Get-Date -Year $y -Month 1 -Day 1).Date
    $week1Sun = $jan1.AddDays(-1 * [int]$jan1.DayOfWeek)
    $wkn = [int]([Math]::Floor((($d.Date - $week1Sun).TotalDays)/7) + 1)
    $weeks += ("{0}-W{1}" -f $y,$wkn)
}
$groups = $weeks | Group-Object | Sort-Object Count -Descending
$groups | Format-Table Name,Count -AutoSize
Write-Host "`nWW25 count:"; ($groups | Where-Object { $_.Name -eq '2026-W25' } | Select-Object -ExpandProperty Count)
Write-Host "WW26 count:"; ($groups | Where-Object { $_.Name -eq '2026-W26' } | Select-Object -ExpandProperty Count)
