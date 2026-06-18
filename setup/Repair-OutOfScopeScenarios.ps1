[CmdletBinding()]
param(
    [string]$ResourceGroup = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccount = 'opswprodtoolsblob',
    [string]$TableName = 'IncidentsCategoryStats',
    [string[]]$IncidentNumbers = @(),
    [string]$PartitionKey = '',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

function Get-SearchText {
    param([object]$Row)

    $parts = @(
        [string]$Row.AIAnalysis
        [string]$Row.Subcategory
        [string]$Row.PossibleRootCause
        [string]$Row.DetailedRootCause
        [string]$Row.ExclusionReason
    )

    return (($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()
}

function Get-OutOfScopeReason {
    param([string]$Text)

    if ($Text -match '(?i)github copilot|github enterprise|visual studio|vs code') {
        return 'Developer tooling request is owned by the GitHub / Visual Studio queue, not Productivity Tools.'
    }

    if ($Text -match '(?i)mailbox|exchange|calendar access|mail doesnt have the license|outlook mail|altera outlook|altera teams') {
        return 'Mail, mailbox, or account-lifecycle handling belongs to Messaging or identity support, not Productivity Tools.'
    }

    if ($Text -match '(?i)laptop|new os build|taskbar|pc refresh|hardware|badge transition|not supported from it') {
        return 'The failure is driven by the device or operating system state, which belongs to the PC / endpoint queue.'
    }

    if ($Text -match '(?i)shared drive|unc path|dfs|mapped drive|server out of our system') {
        return 'The issue is a shared-drive or network-share problem, which belongs to Shared File Service support.'
    }

    if ($Text -match '(?i)sharepoint online access request|sharepoint site|add item button|license request through a sharepoint list|data retrieval for business continuity') {
        return 'The request is a SharePoint Online access or workflow case, which is explicitly handled outside Productivity Tools.'
    }

    if ($Text -match '(?i)mobile|phone|from a phone|personal device|non-company-provided desktop') {
        return 'The request is tied to a mobile, personal-device, or unsupported-device access path rather than a supported Productivity Tools fault.'
    }

    if ($Text -match '(?i)transfer .* presentation and video|file transfer|usb drive|how to|retention|guidance') {
        return 'The ticket is a usage or guidance request rather than a product failure.'
    }

    return 'The ticket does not show a supported Productivity Tools product fault and remains outside the service scope.'
}

function Get-OutOfScopeAnalysis {
    param(
        [object]$Row,
        [string]$Reason
    )

    $category = ([string]$Row.Category).Trim()
    if ([string]::IsNullOrWhiteSpace($category)) { $category = 'Excluded' }

    $sub = ([string]$Row.Subcategory).Trim()
    if ([string]::IsNullOrWhiteSpace($sub) -or $sub -eq 'Out of scope') { $sub = 'Out of scope' }

    return "The ticket remains categorized as Excluded because $Reason The evidence in the work notes points to a different support queue, so Productivity Tools is not the owning service. The canonical out-of-scope labels are preserved to keep the dashboard aligned with the service boundary rules."
}

function Get-AllRowsFromTable {
    param(
        [string]$StorageAccountName,
        [string]$Table,
        $StorageContext,
        [string]$Pk
    )

    if (-not [string]::IsNullOrWhiteSpace($Pk)) {
        return @(Get-AzTableRow -Table $cloudTable -PartitionKey $Pk -ErrorAction Stop)
    }

    $sas = New-AzStorageTableSASToken -Name $Table -Permission 'r' -ExpiryTime (Get-Date).AddMinutes(20) -Protocol HttpsOnly -Context $StorageContext
    $base = "https://$StorageAccountName.table.core.windows.net/$Table()?$sas"

    $rows = @()
    $url = $base
    while ($url) {
        $resp = Invoke-WebRequest -Uri $url -Headers @{ Accept = 'application/json;odata=nometadata' } -UseBasicParsing
        $payload = $resp.Content | ConvertFrom-Json
        $rows += @($payload.value)

        $nextPk = $resp.Headers['x-ms-continuation-NextPartitionKey']
        $nextRk = $resp.Headers['x-ms-continuation-NextRowKey']
        if ($nextPk) {
            $url = $base + '&NextPartitionKey=' + [Uri]::EscapeDataString([string]$nextPk)
            if ($nextRk) { $url += '&NextRowKey=' + [Uri]::EscapeDataString([string]$nextRk) }
        } else {
            $url = $null
        }
    }

    return $rows
}

if (-not (Get-Module -ListAvailable -Name AzTable)) {
    Write-Host 'Installing AzTable module...' -ForegroundColor Yellow
    Install-Module -Name AzTable -Scope CurrentUser -Force -AllowClobber
}
Import-Module AzTable -ErrorAction Stop

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $storageKey
$cloudTable = (Get-AzStorageTable -Name $TableName -Context $ctx -ErrorAction Stop).CloudTable

$targets = @()
if ($IncidentNumbers.Count -gt 0) {
    foreach ($id in $IncidentNumbers) {
        $targets += @(Get-AzTableRow -Table $cloudTable -CustomFilter ("RowKey eq '{0}'" -f $id) -ErrorAction SilentlyContinue)
    }
} else {
    $targets = Get-AllRowsFromTable -StorageAccountName $StorageAccount -Table $TableName -StorageContext $ctx -Pk $PartitionKey
}

Write-Host "Rows loaded: $($targets.Count)" -ForegroundColor Cyan

$checked = 0
$candidates = 0
$updated = 0
$errors = 0

foreach ($row in $targets) {
    $checked++
    $text = Get-SearchText -Row $row
    $reason = Get-OutOfScopeReason -Text $text

    if ([string]::IsNullOrWhiteSpace($reason)) {
        continue
    }

    $candidates++

    $newCategory = 'Excluded'
    $newSubcategory = 'Out of scope'
    $newPrc = 'Out-of-scope Service Offering'
    $newDrc = 'Out-of-scope service offering'
    $newConfidence = if ($text -match '(?i)explicitly|confirmed|not supported|does not describe|not a Productivity Tools product fault') { 'High' } else { 'Medium' }
    $newAnalysis = Get-OutOfScopeAnalysis -Row $row -Reason $reason

    if (-not $Apply) {
        Write-Host ("[DRY-RUN] {0} -> Excluded | {1}" -f $row.RowKey, $reason) -ForegroundColor DarkGray
        continue
    }

    try {
        $tableRow = Get-AzTableRow -Table $cloudTable -PartitionKey $row.PartitionKey -RowKey $row.RowKey -ErrorAction Stop
        if ($null -eq ($tableRow.PSObject.Properties['Subcategory'])) {
            Add-Member -InputObject $tableRow -MemberType NoteProperty -Name 'Subcategory' -Value '' -Force
        }
        if ($null -eq ($tableRow.PSObject.Properties['PossibleRootCause'])) {
            Add-Member -InputObject $tableRow -MemberType NoteProperty -Name 'PossibleRootCause' -Value '' -Force
        }
        if ($null -eq ($tableRow.PSObject.Properties['DetailedRootCause'])) {
            Add-Member -InputObject $tableRow -MemberType NoteProperty -Name 'DetailedRootCause' -Value '' -Force
        }
        if ($null -eq ($tableRow.PSObject.Properties['ExclusionReason'])) {
            Add-Member -InputObject $tableRow -MemberType NoteProperty -Name 'ExclusionReason' -Value '' -Force
        }
        if ($null -eq ($tableRow.PSObject.Properties['AIAnalysis'])) {
            Add-Member -InputObject $tableRow -MemberType NoteProperty -Name 'AIAnalysis' -Value '' -Force
        }
        if ($null -eq ($tableRow.PSObject.Properties['Confidence'])) {
            Add-Member -InputObject $tableRow -MemberType NoteProperty -Name 'Confidence' -Value '' -Force
        }

        $tableRow.Category = $newCategory
        $tableRow.Subcategory = $newSubcategory
        $tableRow.PossibleRootCause = $newPrc
        $tableRow.DetailedRootCause = $newDrc
        $tableRow.ExclusionReason = $reason
        $tableRow.AIAnalysis = $newAnalysis
        $tableRow.Confidence = $newConfidence
        $null = $tableRow | Update-AzTableRow -Table $cloudTable

        $updated++
    } catch {
        $errors++
        Write-Host ("ERROR {0}: {1}" -f $row.RowKey, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '=== Repair Summary ===' -ForegroundColor Cyan
Write-Host "Checked rows   : $checked"
Write-Host "Candidate rows : $candidates"
if ($Apply) {
    Write-Host "Rows updated   : $updated" -ForegroundColor Green
    Write-Host "Errors         : $errors" -ForegroundColor Yellow
} else {
    Write-Host 'No updates applied (dry run). Re-run with -Apply to patch rows.' -ForegroundColor Yellow
}