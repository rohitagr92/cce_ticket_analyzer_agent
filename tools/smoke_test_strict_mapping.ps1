# Smoke test for Convert-ToStrictSubcategoryHeading
# Dot-source mapping functions from generate_fix_audit.ps1
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\generate_fix_audit.ps1"

$tests = @(
    @{ Parent='Productivity Tools'; Raw='Login issues'; ExpectContains='Login' },
    @{ Parent='Outlook'; Raw='Sync failed'; ExpectContains='Sync' }
)
$failures = @()
foreach ($t in $tests) {
    $mapped = Convert-ToStrictSubcategoryHeading -ParentCategory $t.Parent -RawSubCategory $t.Raw -ContextText ''
    if (-not ($mapped -and $mapped -match $t.ExpectContains)) { $failures += @{ Test=$t; Mapped=$mapped } }
}
if ($failures.Count -gt 0) { Write-Host "Smoke tests FAILED:"; $failures | ConvertTo-Json -Depth 5; exit 2 } else { Write-Host "Smoke tests PASSED"; exit 0 }
