<#
.SYNOPSIS
    Removes incident data older than a per-Service-Offering retention cutoff (WW) from
    Azure Table Storage and Blob Storage (weekly/trend report artifacts), so the Static
    Web App output for that Service Offering never shows data before the cutoff.

.DESCRIPTION
    Implements the data-retention rule requested for the AI Incident Analyzer:
      - Prod Tools            : remove data before WW19
      - Email and Calendaring : remove data before WW27
      - Content Engineering   ("Content Sharing"): remove data before WW26

    This script only touches ONE Service Offering's storage account/table/container per
    invocation (matching the existing single-account pattern used by
    setup/inspect/Flush-NonW23-TableRows.ps1), so cleanup for one offering can never
    accidentally affect another offering's data.

    Defaults for -StorageAccountName / -TableName / -CutoffYearWeek are looked up from
    -ServiceOffering below; pass explicit values to override for a non-default environment.

    SAFE BY DEFAULT: runs as a dry run (reports what WOULD be deleted) unless -Execute is
    passed. Also supports -WhatIf/-Confirm via SupportsShouldProcess.

.PARAMETER ServiceOffering
    One of: 'Productivity Tools', 'Email and Calendaring', 'Content Engineering'.
    Used to look up the default cutoff WW and, where possible, default storage account.

.PARAMETER CutoffYearWeek
    ISO YearWeek (e.g. '2026-W19'). Rows/blobs strictly before this week are removed.
    Overrides the built-in default for -ServiceOffering.

.PARAMETER Execute
    Actually perform deletions. Without this switch the script only reports counts.

.EXAMPLE
    # Dry run - shows what would be deleted for Prod Tools before WW19
    ./Cleanup-OldWeeksByServiceOffering.ps1 -ServiceOffering 'Productivity Tools'

.EXAMPLE
    # Actually delete Email and Calendaring rows/blobs before WW27
    ./Cleanup-OldWeeksByServiceOffering.ps1 -ServiceOffering 'Email and Calendaring' -Execute
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Productivity Tools', 'Email and Calendaring', 'Content Engineering')]
    [string]$ServiceOffering,

    [string]$CutoffYearWeek,

    [string]$ResourceGroupName,
    [string]$StorageAccountName,
    [string]$TableName = 'IncidentsCategoryStats',
    [string]$ReportsContainerName = 'results',

    # Perform the deletions. Omit for a dry run.
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# Defaults per Service Offering. Keep this map in sync with the client-side
# SERVICE_WW_CUTOFF map in web/index.html (ensureTableLoaded / isWeekAllowedForService).
# TODO: update StorageAccountName defaults if a Service Offering is migrated to a new
# storage account; ResourceGroupName defaults to the shared 'OPSW-Ticket-Analyzer' RG.
# ------------------------------------------------------------------
$defaults = @{
    'Productivity Tools'    = @{ CutoffYearWeek = '2026-W19'; StorageAccountName = 'opswprodtoolsblob' }
    'Email and Calendaring' = @{ CutoffYearWeek = '2026-W27'; StorageAccountName = 'opswticketanal0571255553' }
    'Content Engineering'   = @{ CutoffYearWeek = '2026-W26'; StorageAccountName = 'opswcontentenggblob' }
}

if (-not $CutoffYearWeek)       { $CutoffYearWeek = $defaults[$ServiceOffering].CutoffYearWeek }
if (-not $StorageAccountName)   { $StorageAccountName = $defaults[$ServiceOffering].StorageAccountName }
if (-not $ResourceGroupName)    { $ResourceGroupName = 'OPSW-Ticket-Analyzer' }

Write-Host "Service Offering : $ServiceOffering" -ForegroundColor Cyan
Write-Host "Cutoff YearWeek  : $CutoffYearWeek (rows/blobs strictly before this are removed)" -ForegroundColor Cyan
Write-Host "Storage Account  : $StorageAccountName" -ForegroundColor Cyan
Write-Host "Table            : $TableName" -ForegroundColor Cyan
Write-Host "Reports Container: $ReportsContainerName" -ForegroundColor Cyan
Write-Host "Mode             : $(if ($Execute) { 'EXECUTE (will delete)' } else { 'DRY RUN (no changes)' })" -ForegroundColor $(if ($Execute) { 'Red' } else { 'Yellow' })

$key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $key

# ------------------------------------------------------------------
# 1) Table Storage - delete rows with PartitionKey (YearWeek) older than CutoffYearWeek
# ------------------------------------------------------------------
Add-Type -AssemblyName 'Microsoft.Azure.Cosmos.Table' -ErrorAction SilentlyContinue
$table = (Get-AzStorageTable -Name $TableName -Context $ctx).CloudTable

$filter = "PartitionKey lt '$CutoffYearWeek'"
$query = New-Object Microsoft.Azure.Cosmos.Table.TableQuery
$query = $query.Where($filter)

Write-Host "`nScanning table '$TableName' for rows older than $CutoffYearWeek..." -ForegroundColor Cyan
$token = $null
$batches = @{}
$totalFound = 0
do {
    $segment = $table.ExecuteQuerySegmentedAsync($query, $token).GetAwaiter().GetResult()
    foreach ($e in $segment.Results) {
        if (-not $batches.ContainsKey($e.PartitionKey)) {
            $batches[$e.PartitionKey] = New-Object System.Collections.Generic.List[object]
        }
        $batches[$e.PartitionKey].Add($e)
        $totalFound++
    }
    $token = $segment.ContinuationToken
} while ($null -ne $token)

Write-Host "Found $totalFound table row(s) to remove across $($batches.Keys.Count) partition(s):" -ForegroundColor Yellow
$batches.Keys | Sort-Object | ForEach-Object { Write-Host "  $_  ($($batches[$_].Count) rows)" }

if ($Execute -and $totalFound -gt 0) {
    foreach ($pk in $batches.Keys) {
        if (-not $PSCmdlet.ShouldProcess("Table partition '$pk' in '$TableName'", "Delete $($batches[$pk].Count) row(s)")) { continue }
        $entities = $batches[$pk]
        for ($i = 0; $i -lt $entities.Count; $i += 100) {
            $chunk = $entities | Select-Object -Skip $i -First 100
            $batch = New-Object Microsoft.Azure.Cosmos.Table.TableBatchOperation
            foreach ($e in $chunk) { $e.ETag = '*'; $batch.Delete($e) }
            $table.ExecuteBatchAsync($batch).GetAwaiter().GetResult() | Out-Null
        }
        Write-Host "  Deleted $($entities.Count) row(s) for partition $pk" -ForegroundColor Green
    }
} elseif (-not $Execute -and $totalFound -gt 0) {
    Write-Host "(Dry run - re-run with -Execute to actually delete these rows.)" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 2) Blob Storage - remove weekly/trend report artifacts whose filename WW is older than cutoff.
#    Also covers the Static Web App output because web/index.html and
#    setup/reporting/Build-ReportsIndex.ps1 read report listings directly from this
#    container (see docs/AI-Incident-Analyzer-WebApp-Change-Log.md).
# ------------------------------------------------------------------
Write-Host "`nScanning container '$ReportsContainerName' for report blobs older than $CutoffYearWeek..." -ForegroundColor Cyan
$oldBlobs = Get-AzStorageBlob -Container $ReportsContainerName -Context $ctx | Where-Object {
    $_.Name -match '(\d{4})-W(\d{2})' -and ("$($matches[1])-W$($matches[2])") -lt $CutoffYearWeek
}
Write-Host "Found $($oldBlobs.Count) blob(s) to remove:" -ForegroundColor Yellow
$oldBlobs | ForEach-Object { Write-Host "  $($_.Name)" }

if ($Execute -and $oldBlobs.Count -gt 0) {
    foreach ($b in $oldBlobs) {
        if (-not $PSCmdlet.ShouldProcess("Blob '$($b.Name)'", 'Delete')) { continue }
        Remove-AzStorageBlob -Container $ReportsContainerName -Blob $b.Name -Context $ctx -Force
        Write-Host "  Deleted $($b.Name)" -ForegroundColor Green
    }
} elseif (-not $Execute -and $oldBlobs.Count -gt 0) {
    Write-Host "(Dry run - re-run with -Execute to actually delete these blobs.)" -ForegroundColor Yellow
}

Write-Host "`nDone. After an -Execute run, re-run setup/reporting/Build-ReportsIndex.ps1 for this container so index.json reflects the removed reports." -ForegroundColor Cyan
