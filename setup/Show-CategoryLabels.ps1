# Compatibility wrapper. Forward to new setup structure.
$target = Join-Path $PSScriptRoot 'inspect\Show-CategoryLabels.ps1'
if (-not (Test-Path $target)) { throw "Target script not found: $target" }
$forward = @($MyInvocation.UnboundArguments)
& $target @forward
exit $LASTEXITCODE

