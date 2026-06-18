# Local smoke test for canonical-label parser.
# Loads the 4 MD files from disk and runs the parser logic from the runbook.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$templates = @{
    TicketCategorisation   = Get-Content (Join-Path $repoRoot 'templates\TicketCategorisation_ProductivityTools.md')   -Raw
    TrendSubCategorisation = Get-Content (Join-Path $repoRoot 'templates\TrendSubCategorisation_ProductivityTools.md') -Raw
    PossibleRootCause      = Get-Content (Join-Path $repoRoot 'templates\PossibleRootCause_ProductivityTools.md')      -Raw
    DetailedRootCause      = Get-Content (Join-Path $repoRoot 'templates\DetailedRootCause_ProductivityTools.md')      -Raw
}

# Extract Get-CanonicalLabelsFromTemplates function from the runbook
$runbook = Get-Content (Join-Path $repoRoot 'runbooks\incident-analyzer-rb-prodtools.ps1') -Raw
$start = $runbook.IndexOf('function Get-CanonicalLabelsFromTemplates')
$end = $runbook.IndexOf("`n}", $runbook.IndexOf('return $result', $start)) + 2
$funcSrc = $runbook.Substring($start, $end - $start)
# Replace $Script:PromptTemplates with $templates
$funcSrc = $funcSrc -replace '\$Script:PromptTemplates', '$templates'
Invoke-Expression $funcSrc

$labels = Get-CanonicalLabelsFromTemplates

Write-Host "`n=== Categories ($($labels.Categories.Count)) ===" -ForegroundColor Cyan
$labels.Categories | ForEach-Object { "  $_" }

Write-Host "`n=== Subcategory groups ($($labels.Subcategories.Count)) ===" -ForegroundColor Cyan
foreach ($k in $labels.Subcategories.Keys) {
    "  $k ($($labels.Subcategories[$k].Count) labels)"
    $labels.Subcategories[$k] | Select-Object -First 3 | ForEach-Object { "    - $_" }
}

Write-Host "`n=== Possible Root Cause groups ($($labels.PossibleRootCauses.Count)) ===" -ForegroundColor Cyan
foreach ($k in $labels.PossibleRootCauses.Keys) {
    "  $k ($($labels.PossibleRootCauses[$k].Count) labels)"
    $labels.PossibleRootCauses[$k] | Select-Object -First 3 | ForEach-Object { "    - $_" }
}

Write-Host "`n=== Detailed Root Cause groups ($($labels.DetailedRootCauses.Count)) ===" -ForegroundColor Cyan
foreach ($k in $labels.DetailedRootCauses.Keys) {
    "  $k ($($labels.DetailedRootCauses[$k].Count) entries)"
    $labels.DetailedRootCauses[$k] | Select-Object -First 3 | ForEach-Object { "    - $_" }
}
