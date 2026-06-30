# Minimal test to see where the runbook is getting stuck
# This will help us identify which section is causing the slowdown

Write-Host "===== MINIMAL RUNBOOK TEST =====" -ForegroundColor Cyan
Write-Host "Start time: $(Get-Date)" -ForegroundColor White

Write-Host ""
Write-Host "Attempting imports..." -ForegroundColor Yellow
try {
    Import-Module Az.Storage -ErrorAction Stop
    Write-Host "  Az.Storage: OK" -ForegroundColor Green
} catch {
    Write-Host "  Az.Storage: FAILED - $_" -ForegroundColor Red
}

try {
    Import-Module Az.Accounts -ErrorAction Stop
    Write-Host "  Az.Accounts: OK" -ForegroundColor Green
} catch {
    Write-Host "  Az.Accounts: FAILED - $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Checking file access..." -ForegroundColor Yellow
$testPaths = @(
    ".\config\LocalConfig-ProductivityTools.psd1",
    ".\runbooks\incident-analyzer-rb-prodtools.ps1",
    ".\setup\reporting\Build-WeeklyReports.ps1"
)

foreach ($path in $testPaths) {
    if (Test-Path $path) {
        Write-Host "  $path: EXISTS" -ForegroundColor Green
    } else {
        Write-Host "  $path: NOT FOUND" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Testing config load..." -ForegroundColor Yellow
try {
    $config = Import-PowerShellDataFile -Path ".\config\LocalConfig-ProductivityTools.psd1" -ErrorAction Stop
    Write-Host "  Config loaded: OK ($(($config.Keys).Count) keys)" -ForegroundColor Green
} catch {
    Write-Host "  Config load: FAILED - $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "End time: $(Get-Date)" -ForegroundColor White
Write-Host "Test completed" -ForegroundColor Green
