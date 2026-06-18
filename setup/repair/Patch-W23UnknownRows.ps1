<#
.SYNOPSIS
    One-off patch: update the 8 W23 PRC=Unknown rows in IncidentsCategoryStats
    with rescued labels validated locally against AOAI.

.DESCRIPTION
    These rows were written by the 2026-06-03 12:13 UTC run, BEFORE the rescue
    classifier was deployed. Rather than re-run the whole runbook (data blob
    container is empty), this script merges the rescued PRC/DRC values
    directly into the existing rows so the dashboard reflects the fix.

    Each label below was produced by setup\Test-RescueStandalone.ps1 against
    live AOAI using the narrow per-category allowlists from the MD templates.
    INC15515840 is left as Unknown because the M365 Apps template has no
    label that fits a how-to / guidance request (template coverage gap).
#>

[CmdletBinding()]
param(
    [string]$ResourceGroup    = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccount   = 'opswprodtoolsblob',
    [string]$TableName        = 'IncidentsCategoryStats',
    [string]$PartitionKey     = '2026-W23'
)

$ErrorActionPreference = 'Stop'

# Ensure AzTable module is loaded
if (-not (Get-Module -ListAvailable -Name AzTable)) {
    Write-Host "Installing AzTable module..." -ForegroundColor Yellow
    Install-Module -Name AzTable -Scope CurrentUser -Force -AllowClobber
}
Import-Module AzTable -ErrorAction Stop

$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $key
$cloudTable = (Get-AzStorageTable -Name $TableName -Context $ctx).CloudTable

# Rescue results from local AOAI validation (Test-RescueStandalone.ps1)
$patches = @(
    @{ Id='INC15392222'; Prc='Excel Performance Degradation';        Drc='Excel desktop performance degradation' }
    @{ Id='INC15485074'; Prc='Corporate Add-in Not Available';       Drc='Word add-in not deployed by IT' }
    @{ Id='INC15507102'; Prc='Copilot SKU Not Provisioned';          Drc='Copilot SKU not provisioned for region / BU' }
    @{ Id='INC15511605'; Prc='License Propagation Delay';            Drc='Copilot licence assigned but not propagated' }
    @{ Id='INC15510251'; Prc='Google Drive Upload Blocked by Policy'; Drc='Google Drive upload blocked by IT policy' }
    @{ Id='INC15513267'; Prc='Subfolder Permission Missing';         Drc='Subfolder permission missing' }
    # INC15515840 intentionally skipped - M365 Apps template has no how-to/guidance label
    @{ Id='INC15515882'; Prc='OLAP / Power BI Performance Issue';    Drc='Underlying data permission missing (returns #N/A)' }
)

$updated = 0; $skipped = 0; $errors = 0
foreach ($p in $patches) {
    try {
        $row = Get-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -RowKey $p.Id -ErrorAction Stop
        if (-not $row) {
            Write-Host "  SKIP $($p.Id): row not found in table" -ForegroundColor Yellow
            $skipped++
            continue
        }
        $beforePrc = $row.PossibleRootCause
        $beforeDrc = $row.DetailedRootCause
        $row.PossibleRootCause = $p.Prc
        $row.DetailedRootCause = $p.Drc
        $null = $row | Update-AzTableRow -Table $cloudTable
        Write-Host "  $($p.Id) PRC '$beforePrc' -> '$($p.Prc)'" -ForegroundColor Green
        Write-Host "             DRC '$beforeDrc' -> '$($p.Drc)'" -ForegroundColor DarkGreen
        $updated++
    } catch {
        Write-Host "  ERROR $($p.Id): $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "Updated: $updated  Skipped: $skipped  Errors: $errors" -ForegroundColor Cyan
Write-Host "INC15515840 left as Unknown (template gap - M365 Apps has no how-to label)" -ForegroundColor Yellow
