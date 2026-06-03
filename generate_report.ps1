$analysisPath = "local-output/productivity-tools-analysis/2026-05-21_13-15-55/analysis/incident_analyses.json"
$rawPath = "local-output/productivity-tools-analysis/2026-05-21_13-15-55/raw/selected_incidents.json"
$outputPath = "local-output/productivity-tools-analysis/2026-05-21_13-15-55/Resolved_Tickets_AI_Categorization_WW21.md"

$analysis = Get-Content $analysisPath -Raw | ConvertFrom-Json
$raw = Get-Content $rawPath -Raw | ConvertFrom-Json

$rawMap = @{}
foreach ($item in $raw) { $rawMap[$item.number] = $item }

$report = New-Object System.Collections.Generic.List[string]
$report.Add("# Resolved Tickets AI Categorization Analysis")
$report.Add("WW21 (May 18, 2026 - May 24, 2026)")
$report.Add("")
$report.Add("## Resolved Tickets Processed")
$report.Add("Total tickets processed: $($analysis.Count) (matches previous report count).")
$report.Add("")

$groups = $analysis | Group-Object -Property application_or_area, primary_category | Select-Object Name, Count, @{Name='Area'; Expression={$_.Group[0].application_or_area}}, @{Name='Cat'; Expression={$_.Group[0].primary_category}}, @{Name='Group'; Expression={$_.Group}} | Sort-Object @{Expression='Count'; Descending=$true}, @{Expression='Area'; Descending=$false}, @{Expression='Cat'; Descending=$false}

$report.Add("## Strict Category and Subcategory Summary")
$report.Add("| Strict Category | Strict Subcategory | Count | Ticket Numbers (ServiceNow Links) |")
$report.Add("| :--- | :--- | :--- | :--- |")

foreach ($g in $groups) {
    $links = $g.Group | Sort-Object incident_number | ForEach-Object {
        $incidentNumber = [string]$_.incident_number
        $r = $rawMap[$incidentNumber]
        "[$incidentNumber](https://intel.service-now.com/nav_to.do?uri=incident.do?sys_id=$($r.sys_id))"
    }
    $report.Add("| $($g.Area) | $($g.Cat) | $($g.Count) | $($links -join ', ') |")
}
$report.Add("")

$report.Add("## Detailed Incident Analysis")
$report.Add("| Incident | Strict Category | Strict Subcategory | Detailed Summary | ServiceNow Link |")
$report.Add("| :--- | :--- | :--- | :--- | :--- |")

$sortedAnalysis = $analysis | Sort-Object @{ Expression = {
    $rawEntry = $rawMap[[string]$_.incident_number]
    try { [datetime](Get-Date ([string]$rawEntry.resolved_at)) } catch { [datetime]::MinValue }
}; Descending = $true }

foreach ($item in $sortedAnalysis) {
    $incidentNumber = [string]$item.incident_number
    $r = $rawMap[$incidentNumber]
    $link = "https://intel.service-now.com/nav_to.do?uri=incident.do?sys_id=$($r.sys_id)"
    
    $wnSource = $r.work_notes
    if ([string]::IsNullOrWhiteSpace($wnSource)) { $wnSource = $r.comments_and_work_notes }
    $wnLines = @()
    if (-not [string]::IsNullOrWhiteSpace($wnSource)) {
        $wnLines = ($wnSource -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 2)
    }
    $wn = ($wnLines -join ' ') -replace '\|', '&#124;' -replace '\r|\n', ' '
    
    $actions = ($item.what_was_done -join ' | ') -replace '\|', '&#124;'
    $signals = ($item.evidence_signals -join ' | ') -replace '\|', '&#124;'
    $summary = $item.issue_summary -replace '\|', '&#124;'
    $ql = $item.quick_look -replace '\|', '&#124;'
    
    $detail = "<b>Problem:</b> $summary<br><b>Key Actions:</b> $actions<br><b>Critical Details:</b> $signals<br><b>Work Notes:</b> $wn<br><b>AI Analysis:</b> $ql<br><b>Confidence Level:</b> $($item.confidence)"
    
    $report.Add("| [$incidentNumber]($link) | $($item.application_or_area) | $($item.primary_category) | $detail | [Link]($link) |")
}

$report.Add("")
$report.Add("Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")

$report | Out-File -FilePath $outputPath -Encoding UTF8 -Force

Write-Host "Output file: $outputPath"
Write-Host "Total incident count: $($analysis.Count)"
Write-Host "Top 5 category/subcategory rows:"
$groups | Select-Object -First 5 | ForEach-Object { "$($_.Area), $($_.Cat): $($_.Count)" }
