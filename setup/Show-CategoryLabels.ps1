[CmdletBinding()] param()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tmpl = Join-Path (Split-Path -Parent $here) 'templates'
$prcText = Get-Content (Join-Path $tmpl 'PossibleRootCause_ProductivityTools.md') -Raw -Encoding UTF8
$drcText = Get-Content (Join-Path $tmpl 'DetailedRootCause_ProductivityTools.md') -Raw -Encoding UTF8
function P([string]$Text, [string]$Marker) {
    $sec = [regex]::Split($Text, '(?m)^##\s+(?:\d+\.\s+)?') | Where-Object { $_ -match '\S' } | Where-Object { ($_ -split "`n",2)[0].Trim() -like "$Marker*" } | Select-Object -First 1
    if (-not $sec) { return @() }
    # collect bold labels and ### headings
    $labels = @()
    foreach ($m in [regex]::Matches($sec, '\|\s*\d+\.\d+\s*\|\s*\*\*([^*|]+?)\*\*\s*\|')) { $labels += "PRC: $($m.Groups[1].Value.Trim())" }
    foreach ($m in [regex]::Matches($sec, '(?m)^###\s+(.+?)\s*$'))                       { $labels += "DRC: $($m.Groups[1].Value.Trim())" }
    return $labels
}
foreach ($cat in 'Microsoft 365 Copilot','Google Workspace','Shared File Service','Microsoft 365 Apps for Enterprise','Microsoft Excel') {
    Write-Host ""
    Write-Host "=== $cat ===" -ForegroundColor Cyan
    P -Text $prcText -Marker $cat | ForEach-Object { Write-Host "  $_" }
    P -Text $drcText -Marker $cat | ForEach-Object { Write-Host "  $_" }
}
