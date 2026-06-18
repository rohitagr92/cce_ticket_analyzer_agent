<#
.SYNOPSIS
    Standalone PS 5.1-compatible test for the Stage 2 rescue classifier.

.DESCRIPTION
    Replicates only the rescue path locally (without sourcing the PS7 runbook):
      - Parses canonical PRC + DRC allowlists from ./templates/*.md
      - Calls Azure OpenAI directly with the narrow per-category prompt
      - Coerces the AI response back to the allowlist
      - Prints results for the 8 known PRC=Unknown W23 cases

    Validates that the rescue prompt design + coercion eliminates Unknowns
    before publishing changes to Azure Automation.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$SecretsPath,
    [string]$TemplateDir
)

$ErrorActionPreference = 'Stop'

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ConfigPath)  { $ConfigPath  = Join-Path $here '..\config\LocalConfig-ProductivityTools.psd1' }
if (-not $SecretsPath) { $SecretsPath = Join-Path $here '..\config\LocalSecrets-ProductivityTools.psd1' }
if (-not $TemplateDir) { $TemplateDir = Join-Path $here '..\templates' }

$cfg = Import-PowerShellDataFile -Path $ConfigPath
$sec = Import-PowerShellDataFile -Path $SecretsPath
foreach ($k in $sec.Keys) { $cfg[$k] = $sec[$k] }

$endpoint = "$($cfg.AzureOpenAIBaseUrl)/openai/deployments/$($cfg.AzureOpenAIDeployment)/chat/completions?api-version=$($cfg.AzureOpenAIApiVersion)"
$apiKey   = $cfg.AzureOpenAIApiKey
if (-not $apiKey) { throw "AzureOpenAIApiKey is not set in LocalSecrets" }

# ---------- Canonical label parsers (copied from runbook, PS5-compatible) ----------

function Parse-PrcAllowlist {
    param([string]$Text)
    # Per-product sections: "## N. Product Issues", then "| N.M | **Label** | Description |"
    $map = @{}
    $sections = [regex]::Split($Text, '(?m)^##\s+\d+\.\s+') | Where-Object { $_ -match '\S' }
    foreach ($sec in $sections) {
        $firstLine = ($sec -split "`n", 2)[0].Trim()
        if (-not $firstLine) { continue }
        $product = $firstLine
        $labels = New-Object System.Collections.Generic.List[string]
        foreach ($m in [regex]::Matches($sec, '\|\s*\d+\.\d+\s*\|\s*\*\*([^*|]+?)\*\*\s*\|')) {
            $label = $m.Groups[1].Value.Trim()
            if (-not $labels.Contains($label)) { $labels.Add($label) }
        }
        if ($labels.Count -gt 0) { $map[$product] = $labels }
    }
    return $map
}

function Parse-DrcAllowlist {
    param([string]$Text)
    # Per-product sections: "## Product", then "### Heading"
    $map = @{}
    $sections = [regex]::Split($Text, '(?m)^##\s+(?!#)') | Where-Object { $_ -match '\S' }
    foreach ($sec in $sections) {
        $firstLine = ($sec -split "`n", 2)[0].Trim()
        if (-not $firstLine) { continue }
        $product = $firstLine
        $entries = New-Object System.Collections.Generic.List[string]
        foreach ($m in [regex]::Matches($sec, '(?m)^###\s+(.+?)\s*$')) {
            $h = $m.Groups[1].Value.Trim() -replace '^\d+\.\s*',''
            if ($h -and -not $entries.Contains($h)) { $entries.Add($h) }
        }
        if ($entries.Count -gt 0) { $map[$product] = $entries }
    }
    return $map
}

function Get-AllowlistForProductLocal {
    param([hashtable]$Map, [string]$Product)
    if (-not $Product) { return (New-Object System.Collections.Generic.List[string]) }
    if ($Map.ContainsKey($Product)) { return $Map[$Product] }
    foreach ($k in $Map.Keys) {
        if ($Product -like "*$k*" -or $k -like "*$Product*") { return $Map[$k] }
    }
    # Token-overlap fallback (matches runbook's improved logic)
    $stop = @('issues','microsoft','365','for','enterprise','the','and','of','a','an')
    $tokenize = {
        param([string]$s)
        $s = ($s -replace '\s*Issues\s*$','').ToLower()
        $raw = [regex]::Split($s, '[^a-z0-9]+') | Where-Object { $_ -and $_ -notin $stop }
        @($raw)
    }
    $pTokens = & $tokenize $Product
    if ($pTokens.Count -eq 0) { return (New-Object System.Collections.Generic.List[string]) }
    $best = $null; $bestScore = 0
    foreach ($k in $Map.Keys) {
        $kTokens = & $tokenize $k
        if ($kTokens.Count -eq 0) { continue }
        $shared = @($pTokens | Where-Object { $kTokens -contains $_ }).Count
        if ($shared -gt $bestScore) { $bestScore = $shared; $best = $k }
    }
    if ($best -and $bestScore -gt 0) { return $Map[$best] }
    return (New-Object System.Collections.Generic.List[string])
}

function Get-CanonicalLabelLocal {
    param([string]$Raw, [System.Collections.Generic.List[string]]$Allowlist, [string]$Fallback = 'Unknown')
    if (-not $Raw -or -not $Allowlist -or $Allowlist.Count -eq 0) { return $Fallback }
    $rawClean = ($Raw -replace '\*+','').Trim()
    foreach ($l in $Allowlist) { if ($rawClean -ieq $l) { return $l } }
    foreach ($l in $Allowlist) { if ($rawClean -ilike "*$l*" -or $l -ilike "*$rawClean*") { return $l } }
    return $Fallback
}

# ---------- The rescue function being tested (logic mirrors the runbook) ----------

function Invoke-RescueLocal {
    param(
        [string]$Category,
        [string]$ShortDescription,
        [string]$AnalystSummary,
        [System.Collections.Generic.List[string]]$PrcAllowlist,
        [System.Collections.Generic.List[string]]$DrcAllowlist
    )
    $prcLines = ($PrcAllowlist | ForEach-Object { "- $_" }) -join "`n"
    $drcLines = ($DrcAllowlist | ForEach-Object { "- $_" }) -join "`n"

    $systemPrompt = @"
You are a strict classification mapper. The ticket has already been confirmed to belong to the Category below. Your job is to pick the SINGLE BEST matching label from each provided list.

Rules:
1. You MUST pick a label from the list whenever any reasonable semantic match exists. Partial matches are acceptable - pick the closest one.
2. Copy the chosen label EXACTLY as written, including capitalization, punctuation, parentheses, and special characters.
3. Only output 'Unknown' if the ticket evidence is genuinely unrelated to every label in the list (rare - the ticket already belongs to this Category).
4. Tie-breaker priority: prefer the most specific label over the most generic.

Category: $Category

VALID POSSIBLE ROOT CAUSE LABELS (pick the BEST matching one):
$prcLines

VALID DETAILED ROOT CAUSE HEADINGS (pick the BEST matching one):
$drcLines

Respond in EXACTLY this format, no preamble, no explanation, no markdown:
PossibleRootCause: <one label copied verbatim from the PRC list>
DetailedRootCause: <one heading copied verbatim from the DRC list>
"@

    $userContent = @"
Short Description: $ShortDescription

Analyst Summary: $AnalystSummary
"@

    $body = @{
        messages = @(
            @{ role = 'system'; content = $systemPrompt }
            @{ role = 'user';   content = $userContent  }
        )
        model = $cfg.AzureOpenAIDeployment
        temperature = 0
        max_completion_tokens = 2048
        top_p = 1.0
    } | ConvertTo-Json -Depth 10 -Compress

    $headers = @{ 'api-key' = $apiKey; 'Content-Type' = 'application/json' }
    $resp = Invoke-RestMethod -Uri $endpoint -Method POST -Headers $headers -Body $body -TimeoutSec 120
    $text = [string]$resp.choices[0].message.content

    $prc = $null; $drc = $null
    if ($text -match '(?im)^\s*PossibleRootCause:\s*(.+?)\s*$') { $prc = ($matches[1].Trim() -replace '\*+','') }
    if ($text -match '(?im)^\s*DetailedRootCause:\s*(.+?)\s*$')  { $drc = ($matches[1].Trim() -replace '\*+','') }

    return [PSCustomObject]@{ Prc = $prc; Drc = $drc; Raw = $text }
}

# ---------- Load templates ----------

Write-Host "Loading templates from $TemplateDir" -ForegroundColor Cyan
$prcText = Get-Content -Path (Join-Path $TemplateDir 'PossibleRootCause_ProductivityTools.md') -Raw -Encoding UTF8
$drcText = Get-Content -Path (Join-Path $TemplateDir 'DetailedRootCause_ProductivityTools.md') -Raw -Encoding UTF8
$prcMap  = Parse-PrcAllowlist -Text $prcText
$drcMap  = Parse-DrcAllowlist -Text $drcText
Write-Host "  PRC products: $($prcMap.Keys.Count); DRC products: $($drcMap.Keys.Count)" -ForegroundColor Gray

# Show what keys we parsed (for debugging the substring lookup)
Write-Host "  PRC keys: $(($prcMap.Keys | Sort-Object) -join ' | ')" -ForegroundColor DarkGray

# ---------- Test cases (the 8 PRC=Unknown rows from W23 run at 12:13 UTC) ----------

# Summaries deliberately include the level of detail the real runbook's
# Get-IncidentSummary produces (action taken + cause keywords from work-notes),
# so the rescue test reflects production conditions rather than thin stubs.
$cases = @(
    @{ Id='INC15392222'; Category='Microsoft Excel Issues';            PriorPrc='Excel desktop performance degradation';      Short='Excel slow / unresponsive when opening large workbook'; Summary='Excel desktop is very slow opening a large workbook with many formulas and external data. Analyst observed high CPU and slow recalc; performance issue, not a hang or a corrupt add-in. Closed after performance-tuning guidance and disabling auto-calc on the workbook.' }
    @{ Id='INC15485074'; Category='Microsoft Word Issues';              PriorPrc='Word add-in not deployed by IT';             Short='Word add-in missing on user device';                    Summary='User expects the corporate Word add-in but it does not appear in the ribbon. Analyst confirmed the add-in was not deployed/published to the user via centralized add-in management. Resolution: requested IT deploy the corporate add-in.' }
    @{ Id='INC15507102'; Category='Microsoft 365 Copilot Issues';       PriorPrc='Copilot license missing';                    Short='Copilot license missing for user';                      Summary='User cannot launch Copilot. Analyst verified in Entra/admin center that the Microsoft 365 Copilot SKU is not provisioned/assigned to the user account. Resolution: requested Copilot license assignment for the user.' }
    @{ Id='INC15511605'; Category='Microsoft 365 Copilot Issues';       PriorPrc='Copilot license missing';                    Short='Copilot license required';                              Summary='User reports Copilot inaccessible. Verified the Copilot license is not assigned in the licensing portal. Resolution: assigned/requested assignment of the Copilot license; user gained access after propagation.' }
    @{ Id='INC15510251'; Category='Google Workspace Issues';            PriorPrc='Google access issue';                        Short='Google Drive upload blocked';                            Summary='User trying to upload files to Google Drive received an error. Analyst confirmed corporate DLP / IT policy is blocking Google Drive uploads from corporate devices. No quota issue. Resolution: explained the policy restriction.' }
    @{ Id='INC15513267'; Category='Shared File Service (Share Drives) Issues'; PriorPrc='Access permission issue';              Short='Cannot access subfolder on shared drive';                Summary='User can reach the shared drive root but is denied on a specific subfolder. Analyst verified ACL on the subfolder did not include the user; requested AGS group be granted subfolder permission. Not a mapping issue, not a deletion, not entitlement to the share itself.' }
    @{ Id='INC15515840'; Category='Microsoft 365 Apps for Enterprise Issues'; PriorPrc='Guidance request for cross-tenant collaboration'; Short='How-to question about M365 Apps';                       Summary='User asked a how-to / usage question about M365 Apps. No error encountered, no licensing issue, no install/activation defect. Provided guidance and KB link.' }
    @{ Id='INC15515882'; Category='Microsoft Excel Issues';             PriorPrc='Underlying data permission missing (returns #N/A)'; Short='Excel formula returning #N/A due to data source';  Summary='Excel workbook returns #N/A from a formula that pulls from an OLAP / Power BI dataset. Analyst traced root cause to the user lacking permission on the underlying data source the query references. Not a hung process, not a corrupt add-in, not a stale cache.' }
)

$results = foreach ($c in $cases) {
    Write-Host ""
    Write-Host "--- $($c.Id) [$($c.Category)] ---" -ForegroundColor Yellow

    $prcAllow = Get-AllowlistForProductLocal -Map $prcMap -Product $c.Category
    $drcAllow = Get-AllowlistForProductLocal -Map $drcMap -Product $c.Category
    Write-Host "  Allowlists: PRC=$($prcAllow.Count), DRC=$($drcAllow.Count)" -ForegroundColor Gray

    if ($prcAllow.Count -eq 0) {
        Write-Host "  SKIP: no PRC allowlist found" -ForegroundColor Red
        [PSCustomObject]@{ Id=$c.Id; Category=$c.Category; PriorPrc=$c.PriorPrc; RescuePrc='<no allowlist>'; RescueDrc='<no allowlist>' }
        continue
    }

    $augSummary = "$($c.Summary)`n`nPrior classifier output for PossibleRootCause field: $($c.PriorPrc)"
    try {
        $r = Invoke-RescueLocal -Category $c.Category -ShortDescription $c.Short -AnalystSummary $augSummary -PrcAllowlist $prcAllow -DrcAllowlist $drcAllow
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        [PSCustomObject]@{ Id=$c.Id; Category=$c.Category; PriorPrc=$c.PriorPrc; RescuePrc='<error>'; RescueDrc='<error>' }
        continue
    }

    $coercedPrc = Get-CanonicalLabelLocal -Raw $r.Prc -Allowlist $prcAllow -Fallback 'Unknown'
    $coercedDrc = Get-CanonicalLabelLocal -Raw $r.Drc -Allowlist $drcAllow -Fallback 'Unknown'

    Write-Host "  AI raw PRC : $($r.Prc)"
    Write-Host "  Coerced    : $coercedPrc" -ForegroundColor $(if ($coercedPrc -eq 'Unknown') { 'Red' } else { 'Green' })
    Write-Host "  AI raw DRC : $($r.Drc)"
    Write-Host "  Coerced    : $coercedDrc" -ForegroundColor $(if ($coercedDrc -eq 'Unknown') { 'Red' } else { 'Green' })

    [PSCustomObject]@{
        Id        = $c.Id
        Category  = $c.Category
        PriorPrc  = $c.PriorPrc
        RescuePrc = $coercedPrc
        RescueDrc = $coercedDrc
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize
$resolved = ($results | Where-Object { $_.RescuePrc -ne 'Unknown' -and $_.RescuePrc -notlike '<*>' }).Count
Write-Host "PRC resolved by rescue: $resolved / $($results.Count)" -ForegroundColor Cyan
