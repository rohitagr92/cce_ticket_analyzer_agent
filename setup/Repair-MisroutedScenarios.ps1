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

function Get-MisrouteRule {
    param([string]$Text, [string]$IncidentNumber)

    if ($IncidentNumber -in @('INC15494549','INC15555395') -or $Text -match '(?i)you need permission to access this item|sharepoint file shared by teammates|could not revert permissions on a specific sharepoint file|owner re-share|required') {
        return [pscustomobject]@{
            Category = 'Microsoft OneDrive Issues'
            Subcategory = 'Access & Permission Issues'
            PossibleRootCause = 'Shared File Permission Denied'
            DetailedRootCause = 'Owner re-share required'
            Confidence = 'High'
            Analysis = 'The ticket is a file-level access and permission problem on a shared SharePoint or OneDrive item, so it belongs in Microsoft OneDrive Issues rather than Excluded. The notes describe permission denied behavior or a failed permission change on a specific file, which matches the OneDrive access and permission pattern. The fix is to have the owner re-share the file or reset the target permissions for the current user.'
        }
    }

    if ($Text -match '(?i)copilot|facilitator|msol license - copilot for m365|blackout period|copilot license') {
        return [pscustomobject]@{
            Category = 'Microsoft 365 Copilot Issues'
            Subcategory = 'Licensing Issues'
            PossibleRootCause = 'Copilot SKU Not Provisioned'
            DetailedRootCause = 'License propagation delay'
            Confidence = 'High'
            Analysis = 'The ticket is a Copilot entitlement or feature availability case, so it should be classified under Microsoft 365 Copilot Issues instead of Excluded. The evidence points to license or rollout state rather than an Office app fault, which is why Copilot owns the failure. The correct resolution path is to validate the Copilot entitlement and wait for propagation or rollout completion.'
        }
    }

    if ($Text -match '(?i)office apps|m365 apps|activation|license expired|unlicensed product|quick repair|online repair|install failure|company portal') {
        return [pscustomobject]@{
            Category = 'Microsoft 365 Apps for Enterprise Issues'
            Subcategory = 'License activation issue'
            PossibleRootCause = 'Office Activation Failure'
            DetailedRootCause = 'Corrupted Office Identity'
            Confidence = 'Medium'
            Analysis = 'The ticket points to a Microsoft 365 Apps install, activation, or sign-in problem, so it belongs under Microsoft 365 Apps for Enterprise Issues. The failure is suite-wide rather than a single app or out-of-scope request, and the work notes indicate an app repair or activation step rather than an external queue. The fix path is to repair Office, clear identity state, or reapply the correct license.'
        }
    }

    if ($Text -match '(?i)onedrive.*permission|shared file|access denied|permission denied|need permission to access this item') {
        return [pscustomobject]@{
            Category = 'Microsoft OneDrive Issues'
            Subcategory = 'Access & Permission Issues'
            PossibleRootCause = 'Shared File Permission Denied'
            DetailedRootCause = 'Permission issue on the synced file or shortcut'
            Confidence = 'Medium'
            Analysis = 'The ticket is a OneDrive or shared-file access problem because the user was blocked from a specific file or shortcut rather than from the entire service. That is an in-scope Productivity Tools file-permission issue, which should be routed to Microsoft OneDrive Issues. The correct fix is owner re-share or permission reset on the target item.'
        }
    }

    return $null
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
$skipped = 0
$errors = 0

foreach ($row in $targets) {
    $checked++
    $text = Get-SearchText -Row $row
    $rule = Get-MisrouteRule -Text $text -IncidentNumber ([string]$row.RowKey)

    if ($null -eq $rule) {
        $skipped++
        continue
    }

    $candidates++

    if (-not $Apply) {
        Write-Host ("[DRY-RUN] {0} -> {1} / {2} / {3}" -f $row.RowKey, $rule.Category, $rule.Subcategory, $rule.PossibleRootCause) -ForegroundColor DarkGray
        continue
    }

    try {
        $tableRow = Get-AzTableRow -Table $cloudTable -PartitionKey $row.PartitionKey -RowKey $row.RowKey -ErrorAction Stop
        foreach ($name in @('Category','Subcategory','PossibleRootCause','DetailedRootCause','ExclusionReason','AIAnalysis','Confidence')) {
            if ($null -eq ($tableRow.PSObject.Properties[$name])) {
                Add-Member -InputObject $tableRow -MemberType NoteProperty -Name $name -Value '' -Force
            }
        }

        $tableRow.Category = $rule.Category
        $tableRow.Subcategory = $rule.Subcategory
        $tableRow.PossibleRootCause = $rule.PossibleRootCause
        $tableRow.DetailedRootCause = $rule.DetailedRootCause
        $tableRow.ExclusionReason = ''
        $tableRow.AIAnalysis = $rule.Analysis
        $tableRow.Confidence = $rule.Confidence
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
Write-Host "Skipped rows   : $skipped"
if ($Apply) {
    Write-Host "Rows updated   : $updated" -ForegroundColor Green
    Write-Host "Errors         : $errors" -ForegroundColor Yellow
} else {
    Write-Host 'No updates applied (dry run). Re-run with -Apply to patch rows.' -ForegroundColor Yellow
}