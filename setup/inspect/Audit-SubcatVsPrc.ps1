<#
.SYNOPSIS
    Cross-check: which subcategories from TrendSubCategorisation lack a clearly
    matching label in PossibleRootCause? Helps find template coverage gaps.
#>
[CmdletBinding()] param()

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$tmpl = Join-Path $here '..\templates'
$subText = Get-Content (Join-Path $tmpl 'TrendSubCategorisation_ProductivityTools.md') -Raw -Encoding UTF8
$prcText = Get-Content (Join-Path $tmpl 'PossibleRootCause_ProductivityTools.md') -Raw -Encoding UTF8

# Parse subcategories per product
$subMap = [ordered]@{}
$sections = [regex]::Split($subText, '(?m)^####\s+') | Where-Object { $_ -match '\S' }
foreach ($sec in $sections) {
    $prod = (($sec -split "`n", 2)[0]).Trim()
    if ($prod -match '^(Cross-Category|Output Format|Sub-Category Guidelines)') { continue }
    $subs = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($sec, '(?m)^\s*-\s+(.+?)\s*$')) {
        $v = $m.Groups[1].Value.Trim()
        # Skip group headers, instructions, JSON-like lines
        if ($v -match '^(Use a descriptive|The IncidentNumber|The SubCategory|The Justification|If no listed|Return ONLY)') { continue }
        if ($v -match '^\*\*') { continue }
        if (-not $subs.Contains($v)) { $subs.Add($v) }
    }
    if ($subs.Count -gt 0) { $subMap[$prod] = $subs }
}

# Parse PRC labels per product
$prcMap = [ordered]@{}
$psecs = [regex]::Split($prcText, '(?m)^##\s+\d+\.\s+') | Where-Object { $_ -match '\S' }
foreach ($sec in $psecs) {
    $prod = (($sec -split "`n", 2)[0]).Trim()
    $labels = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($sec, '\|\s*\d+\.\d+\s*\|\s*\*\*([^*|]+?)\*\*\s*\|')) {
        $labels.Add($m.Groups[1].Value.Trim())
    }
    if ($labels.Count -gt 0) { $prcMap[$prod] = $labels }
}

function Try-Match {
    param([string]$Product, [string]$Sub, [hashtable]$Map)
    # Try direct + substring lookup against PRC keys
    $candidates = @()
    foreach ($k in $Map.Keys) {
        if ($Product -like "*$k*" -or $k -like "*$Product*" -or ($Product -replace ' Issues$','') -like "*$($k -replace ' Issues$','')*") {
            $candidates += $Map[$k]
        }
    }
    if ($candidates.Count -eq 0) { return $null }

    # Tokenize sub-category
    $stop = @('issue','issues','the','a','an','of','for','and','to','in','on','not','with','from')
    $tok = { param($s) [regex]::Split($s.ToLower(), '[^a-z0-9]+') | Where-Object { $_ -and $_ -notin $stop } }
    $sTok = & $tok $Sub
    if ($sTok.Count -eq 0) { return $null }

    $best = $null; $bestScore = 0
    foreach ($lab in $candidates) {
        $lTok = & $tok $lab
        $shared = @($sTok | Where-Object { $lTok -contains $_ }).Count
        if ($shared -gt $bestScore) { $bestScore = $shared; $best = $lab }
    }
    if ($bestScore -ge 1) { return [PSCustomObject]@{ Match=$best; Score=$bestScore } }
    return $null
}

Write-Host ""
Write-Host "=== Coverage summary ===" -ForegroundColor Cyan
$summary = foreach ($p in $subMap.Keys) {
    $cnt   = $subMap[$p].Count
    $prcCnt = 0
    foreach ($k in $prcMap.Keys) {
        if ($p -like "*$k*" -or $k -like "*$p*" -or ($p -replace ' Issues$','') -like "*$($k -replace ' Issues$','')*") {
            $prcCnt = [Math]::Max($prcCnt, $prcMap[$k].Count)
        }
    }
    [PSCustomObject]@{ Product=$p; Subcategories=$cnt; PRC_Labels=$prcCnt }
}
$summary | Format-Table -AutoSize

# PRC sections with no matching subcat section
$subProducts = @($subMap.Keys)
Write-Host "=== PRC sections that have NO Subcategory section ===" -ForegroundColor Yellow
foreach ($k in $prcMap.Keys) {
    $hit = $false
    foreach ($p in $subProducts) {
        if ($p -like "*$k*" -or $k -like "*$p*" -or ($p -replace ' Issues$','') -like "*$($k -replace ' Issues$','')*") { $hit = $true; break }
    }
    if (-not $hit) { Write-Host "  - $k (PRC labels: $($prcMap[$k].Count))" -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "=== Subcategories WITHOUT a clear PRC label (gaps) ===" -ForegroundColor Red
foreach ($p in $subMap.Keys) {
    $missing = @()
    foreach ($s in $subMap[$p]) {
        $m = Try-Match -Product $p -Sub $s -Map $prcMap
        if (-not $m) { $missing += $s }
    }
    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "$p" -ForegroundColor Magenta
        foreach ($x in $missing) { Write-Host "  - $x" }
    }
}
