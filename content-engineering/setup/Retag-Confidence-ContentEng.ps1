# Retag-Confidence-ContentEng.ps1
#
# Re-calculates and writes the Confidence field for Content Engineering table rows
# using the exact Booster/Reducer logic from TicketCategorisation_ContentEngineering.md.
#
# ONLY the Confidence column is written. Nothing else is changed.
#
# Usage:
#   .\Retag-Confidence-ContentEng.ps1                          # dry-run (default)
#   .\Retag-Confidence-ContentEng.ps1 -Apply                   # write changes
#   .\Retag-Confidence-ContentEng.ps1 -PartitionKey 2026-W26 -Apply

[CmdletBinding()]
param(
    [string]$ResourceGroup  = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccount = 'opswcontentenggblob',
    [string]$TableName      = 'IncidentsCategoryStats',
    [string]$PartitionKey   = '',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

# CE-specific terminology boosters (from template)
$ceTerms = @(
    'AEM', 'Sitecore', 'DAM', 'SSO', 'SPO', 'publishing pipeline',
    'workflow approval', 'workflow', 'SharePoint Online', 'SharePoint On-Prem',
    'Teams add-in', 'CMS', 'content management', 'taxonomy', 'metadata',
    'broken link', '404', 'search index', 'permission denied', 'role assignment',
    'site collection', 'recycle bin', 'access denied'
)

function Get-ConfidenceScore {
    param([object]$Row)

    $category  = ([string]$Row.Category).Trim()
    $subcat    = ([string]$Row.Subcategory).Trim()
    $prc       = ([string]$Row.PossibleRootCause).Trim()
    $aiText    = ([string]$Row.AIAnalysis).Trim()

    $score = 50   # base

    # ── BOOSTERS ──────────────────────────────────────────────────────────────

    # +25  Application/platform clearly identified (Category not blank/Unknown)
    $catIsKnown = (-not [string]::IsNullOrWhiteSpace($category)) -and
                  ($category -notin @('Unknown / Unclear', 'Other / Miscellaneous'))
    if ($catIsKnown) { $score += 25 }

    # +15  Specific error/symptom captured (Subcategory populated and not generic)
    $subIsKnown = (-not [string]::IsNullOrWhiteSpace($subcat)) -and
                  ($subcat -notin @('Unclassified', 'Insufficient Information', 'Out of Scope'))
    if ($subIsKnown) { $score += 15 }

    # +5   KB number present (guardrail: max +5, never drives confidence alone)
    if ($aiText -match '\bKB\d{4,}\b') { $score += 5 }

    # +10  CE-specific terminology in AIAnalysis
    $hasCeTerm = $ceTerms | Where-Object { $aiText -match [regex]::Escape($_) }
    if ($hasCeTerm) { $score += 10 }

    # +15  Resolution clearly documented (PossibleRootCause populated and not Unknown)
    $prcIsKnown = (-not [string]::IsNullOrWhiteSpace($prc)) -and
                  ($prc -notin @('Unknown', '-', 'Unclassified'))
    if ($prcIsKnown) { $score += 15 }

    # ── REDUCERS ──────────────────────────────────────────────────────────────
    # Per template: absent fields simply earn no booster — do NOT double-penalise.
    # Only two conditions warrant a score reduction:

    # -20  Application/platform unclear, ambiguous, or contradictory
    if (-not $catIsKnown) { $score -= 20 }

    # -10  Vague or generic language — "issue resolved" with no documented steps
    #      Proxy: AIAnalysis blank or < 80 chars
    if ([string]::IsNullOrWhiteSpace($aiText) -or $aiText.Length -lt 80) { $score -= 10 }

    # ── MAP TO LABEL ──────────────────────────────────────────────────────────
    if     ($score -ge 90) { return 'High'   }
    elseif ($score -ge 70) { return 'Medium' }
    else                   { return 'Low'    }
}

# ── Module check ──────────────────────────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name AzTable)) {
    Write-Host 'Installing AzTable module...' -ForegroundColor Yellow
    Install-Module -Name AzTable -Scope CurrentUser -Force -AllowClobber
}
Import-Module AzTable -ErrorAction Stop

# ── Connect ───────────────────────────────────────────────────────────────────
Write-Host "Connecting to $StorageAccount / $TableName..." -ForegroundColor Cyan
$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx        = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $storageKey
$cloudTable = (Get-AzStorageTable -Name $TableName -Context $ctx -ErrorAction Stop).CloudTable

# ── Load rows ─────────────────────────────────────────────────────────────────
if (-not [string]::IsNullOrWhiteSpace($PartitionKey)) {
    $rows = @(Get-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -ErrorAction Stop)
} else {
    $rows = @(Get-AzTableRow -Table $cloudTable -ErrorAction Stop)
}
Write-Host "Rows loaded: $($rows.Count)" -ForegroundColor Gray

$checked = 0; $changed = 0; $same = 0; $errors = 0

foreach ($r in $rows) {
    $checked++
    $pk = [string]$r.PartitionKey
    $rk = [string]$r.RowKey

    $currentConf = ([string]$r.Confidence).Trim()
    $newConf     = Get-ConfidenceScore -Row $r

    if ($currentConf -eq $newConf) {
        $same++
        continue
    }

    $changed++

    if (-not $Apply) {
        Write-Host ("[DRY-RUN] {0}/{1}  Confidence: '{2}' -> '{3}'" -f $pk, $rk, $currentConf, $newConf) -ForegroundColor DarkGray
        continue
    }

    try {
        $row = Get-AzTableRow -Table $cloudTable -PartitionKey $pk -RowKey $rk -ErrorAction Stop
        if ($null -eq ($row.PSObject.Properties['Confidence'])) {
            Add-Member -InputObject $row -MemberType NoteProperty -Name 'Confidence' -Value '' -Force
        }
        $row.Confidence = $newConf
        $null = $row | Update-AzTableRow -Table $cloudTable
        Write-Host ("  Updated: {0}/{1}  '{2}' -> '{3}'" -f $pk, $rk, $currentConf, $newConf) -ForegroundColor Green
    } catch {
        $errors++
        Write-Host ("  ERROR {0}/{1}: {2}" -f $pk, $rk, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '=== Summary ===' -ForegroundColor Cyan
Write-Host "Rows checked    : $checked"
Write-Host "Unchanged       : $same"
if ($Apply) {
    Write-Host "Updated         : $changed" -ForegroundColor Green
    if ($errors -gt 0) { Write-Host "Errors          : $errors" -ForegroundColor Red }
} else {
    Write-Host "Would update    : $changed" -ForegroundColor Yellow
    if ($changed -gt 0) {
        Write-Host 'Re-run with -Apply to write changes.' -ForegroundColor Yellow
    }
}
