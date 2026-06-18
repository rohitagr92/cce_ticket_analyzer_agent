<#
.SYNOPSIS
    Local smoke test for Resolve-RootCauseRescue.

.DESCRIPTION
    Dot-sources the runbook in load-only mode (RUNBOOK_LOAD_ONLY=1) so all
    functions and canonical-label allowlists are populated without running the
    ServiceNow -> AI -> Storage workflow. Then it feeds the 8 known
    PRC=Unknown cases from the W23 run into Resolve-RootCauseRescue and prints
    the mapping the AI returns.

    This validates the rescue logic against live AOAI without touching Azure
    Automation, blob storage, or the table.

.NOTES
    Requires local-config + local-secrets to provide AzureOpenAIApiKey.
#>

[CmdletBinding()]
param(
    [string]$RunbookPath = "$PSScriptRoot\..\runbooks\incident-analyzer-rb-prodtools.ps1"
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Resolve-RootCauseRescue local smoke test ===" -ForegroundColor Cyan

# 1) Load runbook in non-executing mode
$env:RUNBOOK_LOAD_ONLY = '1'
try {
    . $RunbookPath
} finally {
    Remove-Item Env:RUNBOOK_LOAD_ONLY -ErrorAction SilentlyContinue
}

if (-not $Script:CanonicalLabels) {
    throw "CanonicalLabels not populated. Did template load fail?"
}

# 2) Build the 8 known Unknown cases from the most recent W23 run.
#    Each case provides: Category, AI's prior PRC free-text, short_description,
#    and a brief analyst summary so the narrow re-classifier has signal.
$cases = @(
    @{ Id='INC15392222'; Category='Microsoft Excel Issues';            PriorPrc='Excel desktop performance degradation';      Short='Excel slow / unresponsive when opening large workbook'; Summary='User reports Excel desktop client performance degradation on a large workbook; freezes and lag observed.' }
    @{ Id='INC15485074'; Category='Microsoft Word Issues';              PriorPrc='Word add-in not deployed by IT';             Short='Word add-in missing on user device';                    Summary='User cannot see required Word add-in. IT has not deployed/published the add-in to the device yet.' }
    @{ Id='INC15507102'; Category='Microsoft 365 Copilot Issues';       PriorPrc='Copilot license missing';                    Short='Copilot license missing for user';                      Summary='User cannot access Copilot features; investigation shows the M365 Copilot license is not assigned to the account.' }
    @{ Id='INC15511605'; Category='Microsoft 365 Copilot Issues';       PriorPrc='Copilot license missing';                    Short='Copilot license required';                              Summary='User reports Copilot inaccessible. Resolution required assignment of Copilot license.' }
    @{ Id='INC15510251'; Category='Google Issues';                      PriorPrc='Google access issue';                        Short='Google Workspace access issue';                         Summary='User unable to access Google Workspace resource; access/permission related.' }
    @{ Id='INC15513267'; Category='Shared File Access Issues';          PriorPrc='Access permission issue';                    Short='Shared file access denied';                             Summary='User cannot open shared file; resolution required granting/restoring the access permission.' }
    @{ Id='INC15515840'; Category='Microsoft 365 Apps for Enterprise Issues'; PriorPrc='Guidance request for cross-tenant collaboration'; Short='How-to question about cross-tenant collaboration';        Summary='User requested guidance on cross-tenant collaboration setup; informational, no defect.' }
    @{ Id='INC15515882'; Category='Microsoft Excel Issues';             PriorPrc='Underlying data permission missing (returns #N/A)'; Short='Excel formula returning #N/A due to data source';  Summary='User reports Excel returns #N/A; root cause traced to missing permission on the underlying data source the formula references.' }
)

# 3) Run each case through the rescue
$results = foreach ($c in $cases) {
    Write-Host ""
    Write-Host "--- $($c.Id) [$($c.Category)] ---" -ForegroundColor Yellow

    $prcAllow = Get-AllowlistForProduct -Map $Script:CanonicalLabels.PossibleRootCauses -Product $c.Category
    $drcAllow = Get-AllowlistForProduct -Map $Script:CanonicalLabels.DetailedRootCauses -Product $c.Category
    Write-Host "  PRC allowlist size: $($prcAllow.Count); DRC allowlist size: $($drcAllow.Count)" -ForegroundColor Gray

    if ($prcAllow.Count -eq 0) {
        Write-Host "  SKIP: no PRC allowlist found for this category" -ForegroundColor Red
        [PSCustomObject]@{ Id=$c.Id; Category=$c.Category; PriorPrc=$c.PriorPrc; RescuePrc='<no allowlist>'; RescueDrc='<no allowlist>' }
        continue
    }

    # Bundle the prior AI text into the summary so the rescue sees the same signal
    $augmentedSummary = "$($c.Summary)`n`nPrior classifier text for PossibleRootCause: $($c.PriorPrc)"

    $r = Resolve-RootCauseRescue `
        -Category          $c.Category `
        -Subcategory       '' `
        -AnalystSummary    $augmentedSummary `
        -ShortDescription  $c.Short `
        -WorkNotes         '' `
        -PrcAllowlist      $prcAllow `
        -DrcAllowlist      $drcAllow `
        -NeedPrc           $true `
        -NeedDrc           $true

    $rawPrc = $r.PossibleRootCause
    $rawDrc = $r.DetailedRootCause
    $coercedPrc = if ($rawPrc) { Get-CanonicalLabel -Raw $rawPrc -Allowlist $prcAllow -Fallback 'Unknown' } else { '<null>' }
    $coercedDrc = if ($rawDrc) { Get-CanonicalLabel -Raw $rawDrc -Allowlist $drcAllow -Fallback 'Unknown' } else { '<null>' }

    Write-Host "  Raw PRC  : $rawPrc"
    Write-Host "  Coerced  : $coercedPrc" -ForegroundColor $(if ($coercedPrc -eq 'Unknown') { 'Red' } else { 'Green' })
    Write-Host "  Raw DRC  : $rawDrc"
    Write-Host "  Coerced  : $coercedDrc" -ForegroundColor $(if ($coercedDrc -eq 'Unknown') { 'Red' } else { 'Green' })

    [PSCustomObject]@{
        Id          = $c.Id
        Category    = $c.Category
        PriorPrc    = $c.PriorPrc
        RescuePrc   = $coercedPrc
        RescueDrc   = $coercedDrc
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize
$resolved = ($results | Where-Object { $_.RescuePrc -ne 'Unknown' -and $_.RescuePrc -ne '<no allowlist>' }).Count
Write-Host "PRC resolved by rescue: $resolved / $($results.Count)" -ForegroundColor Cyan
