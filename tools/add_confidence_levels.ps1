param([switch]$DryRun)

<#
.SYNOPSIS
    Add Confidence level to all WW26 incidents.
    
.DESCRIPTION
    Updates each incident with a Confidence field:
    - "High" for incidents with specific category (not Unknown)
    - "Low" for Unknown category (insufficient documentation)
    
.USAGE
    .\tools\add_confidence_levels.ps1
    .\tools\add_confidence_levels.ps1 -DryRun

#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $ScriptDir "..")

$configPath  = ".\Config\LocalConfig-ProductivityTools.psd1"
$secretsPath = ".\Config\LocalSecrets-ProductivityTools.psd1"

if (-not (Test-Path $configPath)) { 
    Write-Host "ERROR: $configPath not found" -ForegroundColor Red
    exit 1 
}

$LocalConfig = Import-PowerShellDataFile -Path $configPath
if (Test-Path $secretsPath) { 
    $secrets = Import-PowerShellDataFile -Path $secretsPath
    foreach ($k in $secrets.Keys) { $LocalConfig[$k] = $secrets[$k] }
}

$StorageAccountName = 'opswprodtoolsblob'
$ResourceGroup      = 'OPSW-Ticket-Analyzer'
$SubscriptionId     = $LocalConfig.Incidents_analyzer_SubscriptionId
$TableName          = 'IncidentsCategoryStats'

Write-Host "====== ADD CONFIDENCE LEVELS TO WW26 ======`n"

if ($DryRun) {
    Write-Host "DRY RUN: Would add Confidence field to all WW26 incidents:"
    Write-Host "  - High: Specific category (not Unknown)"
    Write-Host "  - Low: Unknown category (insufficient data)"
    Write-Host ""
    Write-Host "Run without -DryRun to apply changes."
    exit 0
}

Write-Host "[1/2] Connecting to Azure..."
Connect-AzAccount -Subscription $SubscriptionId -ErrorAction Stop | Out-Null
$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $key
$table = Get-AzStorageTable -Name $TableName -Context $ctx
Write-Host "SUCCESS`n"

Write-Host "[2/2] Adding Confidence levels..."
$rows = @(Get-AzTableRow -Table $table.CloudTable -PartitionKey "2026-W26")
Write-Host "Found $($rows.Count) incidents`n"

$updated = 0
$high = 0
$low = 0

foreach ($row in $rows) {
    # Determine confidence level
    $confLevel = if ($row.Category -eq 'Unknown') { 'Low' } else { 'High' }
    
    # Add or update Confidence property
    if ($row.PSObject.Properties['Confidence']) {
        $row.Confidence = $confLevel
    } else {
        $row | Add-Member -NotePropertyName 'Confidence' -NotePropertyValue $confLevel -Force
    }
    
    if ($row.Category -eq 'Unknown') {
        $low++
    } else {
        $high++
    }
    
    Update-AzTableRow -Table $table.CloudTable -Entity $row | Out-Null
    $updated++
    
    if ($updated % 10 -eq 0) {
        Write-Host "  Processed $updated / $($rows.Count)..."
    }
}

Write-Host "`nSummary:"
Write-Host "  High Confidence: $high"
Write-Host "  Low Confidence: $low"
Write-Host "  Total Updated: $updated / $($rows.Count)"

if ($updated -eq $rows.Count) {
    Write-Host "`n✅ SUCCESS: All incidents updated with Confidence levels"
    Write-Host "`nNext: Regenerate dashboard with:"
    Write-Host "  .\setup\reporting\Build-WeeklyReports.ps1 -OnlyWeeks '2026-W26'"
} else {
    Write-Host "`n⚠️  WARNING: Only $updated / $($rows.Count) updated"
}
