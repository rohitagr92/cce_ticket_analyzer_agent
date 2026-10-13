[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$ResourceGroup = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccount = 'opswprodtoolsblob',
    [string]$TableName = 'IncidentsCategoryStats',
    [string]$AutomationAccount = 'OPSW-ProductivityTools-account'
)

$ErrorActionPreference = 'Stop'
$skuLabel = 'Copilot SKU Not Provisioned'
$missingLabel = 'Copilot License Missing'
$blackoutLabel = 'Copilot License Blackout'
$regionRolloutIds = @('INC15356793','INC15425292','INC15436930','INC15573795')
$blackoutIds = @('INC15527762','INC15597556')
$manualMissingIds = @(
    'INC15471465','INC15517606','INC15543940','INC15551795','INC15607085',
    'INC15614075','INC15616161','INC15627576','INC15629553','INC15629843',
    'INC15632110','INC15492763','INC15383382','INC15441838','INC15640735',
    'INC15649201','INC15649000','INC15662440','INC15748483','INC15402729'
)
$manualReviewIds = @('INC15595973')
$manualRootCausePlans = @(
    [pscustomobject]@{ PartitionKey='2026-W10'; RowKey='INC15355293'; Action='Copilot guidance / no fault'; NewRootCause='Unknown'; NewDetailedRootCause='Copilot entitlement was active; user asked about using it on a new PC'; NewSubcategory='Usage Queries'; Confidence='Medium'; RootNarrative='AGS showed the Copilot entitlement was active and tied to the user account, not the old PC. No missing-license or rollout fault was documented.'; NewAiNarrative='This was a Copilot usage question about moving from an old PC to a new one. The entitlement was active in AGS and followed the user account, so Copilot License Missing and Copilot SKU Not Provisioned do not fit.' }
    [pscustomobject]@{ PartitionKey='2026-W14'; RowKey='INC15410279'; Action='Copilot usage / policy guidance'; NewRootCause='Unknown'; NewDetailedRootCause='User asked for standard Copilot file-safety guidance'; NewSubcategory='Usage Queries'; Confidence='Medium'; RootNarrative='The notes document a security and data-classification question about standard Microsoft Copilot file uploads, not a missing Microsoft 365 Copilot entitlement or product failure.'; NewAiNarrative='The user requested guidance about safe file uploads in standard Microsoft Copilot. No Microsoft 365 Copilot license issue or regional SKU restriction was reported, so Copilot License Missing and Copilot SKU Not Provisioned do not fit.' }
    [pscustomobject]@{ PartitionKey='2026-W25'; RowKey='INC15591530'; Action='Facilitator meeting-option configuration'; NewRootCause='Copilot Access / Environment Configuration Issue'; NewDetailedRootCause='Facilitator setting needed enabling in meeting options'; NewSubcategory='Copilot Enablement Issues'; Confidence='High'; RootNarrative='Support guided the user to enable Facilitator in the Teams meeting options. The recorded resolution is a meeting-level setting change; the notes do not document a missing Copilot entitlement or regional rollout restriction.'; NewAiNarrative='The issue was resolved by enabling the Facilitator setting in meeting options. The recorded evidence supports a Copilot feature-configuration issue, not a missing license or an unprovisioned regional SKU.' }
    [pscustomobject]@{ PartitionKey='2026-W33'; RowKey='INC15708817'; Action='Copilot Read Aloud usage guidance'; NewRootCause='Unknown'; NewDetailedRootCause='User requested Read Aloud usage instructions'; NewSubcategory='Usage Queries'; Confidence='Medium'; RootNarrative='The user asked how to use Copilot Read Aloud, and support provided the built-in steps. No entitlement problem, regional restriction, or product failure was documented.'; NewAiNarrative='This was a how-to request for Copilot Read Aloud. The notes show the feature steps were provided and no license or regional availability problem was reported, so Copilot License Missing and Copilot SKU Not Provisioned do not fit.' }
)

function Get-AnalysisSection {
    param([string]$Text, [string]$Label, [string[]]$StopLabels)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $labelPattern = [regex]::Escape($Label)
    $stopPattern = ($StopLabels | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $match = [regex]::Match($Text, "(?ims)^\s*$labelPattern\s*:\s*(.*?)(?=\r?\n\s*(?:$stopPattern)\s*:|\z)")
    if (-not $match.Success) { return '' }
    return ($match.Groups[1].Value -replace '\s+', ' ').Trim()
}

function Set-AnalysisSection {
    param([string]$Text, [string]$Label, [string[]]$StopLabels, [string]$Value)

    $labelPattern = [regex]::Escape($Label)
    $stopPattern = ($StopLabels | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $pattern = "(?ims)(^\s*$labelPattern\s*:\s*).*?(?=\r?\n\s*(?:$stopPattern)\s*:|\z)"
    if ($Text -notmatch $pattern) { return $Text }
    return [regex]::Replace($Text, $pattern, ('$1' + $Value), 1)
}

function Test-MissingCopilotEntitlement {
    param([string]$Text)

    $msolRequest = '(?i)MSOL License\s*[–-]\s*Copilot for M365'
    $missingState = '(?i)(?:does not|doesn''t|did not|didn''t|do not|not having|no)\s+(?:currently\s+)?(?:have|has|assigned|possess)?.{0,80}(?:Copilot|MSOL|license|entitlement|access)|(?:Copilot|MSOL).{0,80}(?:license|entitlement|access).{0,80}(?:missing|not assigned|not available|not present|absent)|AGS.{0,100}(?:no Copilot|does not have access|not assigned|not available)'
    $requestAction = '(?i)(?:request|apply|submit|raise).{0,100}(?:Copilot license|Copilot access|Copilot entitlement|MSOL License)|(?:Copilot license|Copilot entitlement|MSOL License).{0,100}(?:request|apply|submit|raise)'

    return [bool]($Text -match $missingState -or ($Text -match $msolRequest -and $Text -match $requestAction))
}

function Ensure-Property {
    param([object]$Row, [string]$Name)
    if ($null -eq $Row.PSObject.Properties[$Name]) {
        Add-Member -InputObject $Row -MemberType NoteProperty -Name $Name -Value '' -Force
    }
}

function Get-AiAnalysisParagraph {
    param([string]$Text)
    $match = [regex]::Match($Text, '(?ims)^\s*AI\s*Analysis(?:\s*\([^)]*\))?\s*:\s*(.*)\z')
    if (-not $match.Success) { return '' }
    return $match.Groups[1].Value.Trim()
}

function Set-AiAnalysisParagraph {
    param([string]$Text, [string]$Narrative)
    $match = [regex]::Match($Text, '(?ims)^\s*AI\s*Analysis(?:\s*\([^)]*\))?\s*:\s*')
    if (-not $match.Success) { return $Text }
    return $Text.Substring(0, $match.Index) + $match.Value + $Narrative
}

Import-Module AzTable -ErrorAction Stop

$activeJobs = @(Get-AzAutomationJob -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -ErrorAction Stop | Where-Object {
    $_.RunbookName -in @('incident-analyzer-rb-prodtools','incident-trend-backfill-rb-prodtools','incident-quality-guard-rb-prodtools') -and
    $_.Status -in @('New','Activating','Running','Queued')
})
if ($activeJobs.Count -gt 0) { throw 'A PT analyzer/backfill/quality job is active; refusing Copilot root-cause update.' }

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount -ErrorAction Stop)[0].Value
$storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $storageKey
$cloudTable = (Get-AzStorageTable -Name $TableName -Context $storageContext -ErrorAction Stop).CloudTable
$rows = @(Get-AzTableRow -Table $cloudTable -CustomFilter "PossibleRootCause eq '$skuLabel' or RootCause eq '$skuLabel'" -ErrorAction Stop)

$plans = @()
$manualReview = @()
foreach ($row in $rows) {
    $incident = [string]$row.RowKey
    $ai = [string]$row.AIAnalysis
    $rootNarrative = Get-AnalysisSection -Text $ai -Label 'Root Cause' -StopLabels @('Resolution','Evidence','AI Analysis')
    $evidence = Get-AnalysisSection -Text $ai -Label 'Evidence' -StopLabels @('AI Analysis')
    $signal = @([string]$row.DetailedRootCause, $rootNarrative, $evidence) -join ' '

    if ($incident -in $regionRolloutIds) {
        $newSubcategory = if ([string]$row.Subcategory -eq 'Feature Availability Issues') { '' } else { 'Feature Availability Issues' }
        $plans += [pscustomobject]@{ PartitionKey=$row.PartitionKey; RowKey=$incident; Action='Retain rollout SKU'; NewRootCause=$skuLabel; NewDetailedRootCause='Copilot is not available in the user region'; NewSubcategory=$newSubcategory; Confidence=[string]$row.Confidence }
        continue
    }

    if ($incident -in $blackoutIds) {
        $plans += [pscustomobject]@{ PartitionKey=$row.PartitionKey; RowKey=$incident; Action='Copilot License Blackout'; NewRootCause=$blackoutLabel; NewDetailedRootCause='Additional M365 Copilot licenses unavailable during contract blackout'; NewSubcategory=''; Confidence='High' }
        continue
    }

    $manualRootPlan = $manualRootCausePlans | Where-Object { $_.RowKey -eq $incident } | Select-Object -First 1
    if ($manualRootPlan) {
        $plans += $manualRootPlan
        continue
    }

    if ($incident -in $manualReviewIds) {
        $manualReview += [pscustomobject]@{ PartitionKey=$row.PartitionKey; RowKey=$incident; Reason='Active entitlement, non-licensed usage guidance, ambiguous product, or no documented missing-entitlement evidence.' }
        continue
    }

    $missing = ($incident -in $manualMissingIds) -or (Test-MissingCopilotEntitlement -Text $signal)
    if (-not $missing) {
        $manualReview += [pscustomobject]@{ PartitionKey=$row.PartitionKey; RowKey=$incident; Reason='No sufficiently specific missing-entitlement evidence in the stored source analysis.' }
        continue
    }

    $newRootNarrative = $rootNarrative
    if ($rootNarrative -match '(?i)evidence supports Copilot SKU Not Provisioned|Ticket notes and close notes reference the relevant Copilot symptom|Copilot SKU not provisioned for region / BU') {
        $newRootNarrative = 'The source notes indicate the required Microsoft 365 Copilot entitlement was not assigned or the user was directed to request it through AGS. No region or business-unit rollout cause is established for this incident.'
    }
    $plans += [pscustomobject]@{
        PartitionKey = $row.PartitionKey
        RowKey = $incident
        Action = $missingLabel
        NewRootCause = $missingLabel
        NewDetailedRootCause = 'Copilot for M365 entitlement not assigned or request pending'
        NewSubcategory = ''
        Confidence = [string]$row.Confidence
        RootNarrative = $newRootNarrative
    }
}

$analysisPlans = @()
$missingRows = @(Get-AzTableRow -Table $cloudTable -CustomFilter "PossibleRootCause eq '$missingLabel'" -ErrorAction Stop)
$plannedKeys = @{}
foreach ($plan in $plans) { $plannedKeys[([string]$plan.PartitionKey + '|' + [string]$plan.RowKey)] = $true }
$staleAiPattern = '(?i)Copilot SKU Not Provisioned|Copilot SKU not provisioned for region|Copilot License Blackout|Copilot licence blackout|Ticket notes and close notes reference the relevant Copilot symptom|evidence supports Copilot SKU'
foreach ($row in $missingRows) {
    $key = [string]$row.PartitionKey + '|' + [string]$row.RowKey
    $aiParagraph = Get-AiAnalysisParagraph -Text ([string]$row.AIAnalysis)
    $refreshAnalysis = $aiParagraph -match $staleAiPattern
    $syncRoot = -not [string]::IsNullOrWhiteSpace([string]$row.RootCause) -and [string]$row.RootCause -cne [string]$row.PossibleRootCause
    if (($refreshAnalysis -or $syncRoot) -and -not $plannedKeys.ContainsKey($key)) {
        $analysisPlans += [pscustomobject]@{
            PartitionKey = [string]$row.PartitionKey
            RowKey = [string]$row.RowKey
            Action = if ($refreshAnalysis) { 'Refresh stale AIAnalysis' } else { 'Sync canonical RootCause' }
            Confidence = [string]$row.Confidence
            DetailedRootCause = [string]$row.DetailedRootCause
        }
        $plannedKeys[$key] = $true
    }
}

$copilotRows = @(Get-AzTableRow -Table $cloudTable -CustomFilter "Category eq 'Microsoft 365 Copilot Issues'" -ErrorAction Stop)
foreach ($row in $copilotRows) {
    $key = [string]$row.PartitionKey + '|' + [string]$row.RowKey
    if (-not [string]::IsNullOrWhiteSpace([string]$row.PossibleRootCause) -and
        -not [string]::IsNullOrWhiteSpace([string]$row.RootCause) -and
        [string]$row.RootCause -cne [string]$row.PossibleRootCause -and
        -not $plannedKeys.ContainsKey($key)) {
        $analysisPlans += [pscustomobject]@{
            PartitionKey = [string]$row.PartitionKey
            RowKey = [string]$row.RowKey
            Action = 'Sync canonical RootCause'
            Confidence = [string]$row.Confidence
            DetailedRootCause = [string]$row.DetailedRootCause
        }
        $plannedKeys[$key] = $true
    }
}

Write-Host "Rows scanned with Copilot SKU label: $($rows.Count)"
Write-Host "Rows planned for correction: $($plans.Count + $analysisPlans.Count)"
Write-Host "Rows left for manual review: $($manualReview.Count)"
$plans | Format-Table PartitionKey,RowKey,Action,NewRootCause,NewSubcategory -AutoSize
$analysisPlans | Format-Table PartitionKey,RowKey,Action,DetailedRootCause -AutoSize
if ($manualReview.Count -gt 0) {
    Write-Host 'Manual-review exceptions:' -ForegroundColor Yellow
    $manualReview | Format-Table PartitionKey,RowKey,Reason -AutoSize
}

if (-not $Apply) {
    Write-Host 'Dry run only. No Azure Table rows were changed. Re-run with -Apply to update the listed rows.' -ForegroundColor Yellow
    return
}

$backupPath = Join-Path $PSScriptRoot ("..\archive\backups\copilot-sku-rootcause-backup-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$backupRows = @()
foreach ($plan in @($plans) + @($analysisPlans)) {
    $backupRows += Get-AzTableRow -Table $cloudTable -PartitionKey $plan.PartitionKey -RowKey $plan.RowKey -ErrorAction Stop
}
$backupRows | ConvertTo-Json -Depth 20 | Set-Content -Path $backupPath -Encoding UTF8

$updated = 0
foreach ($plan in $plans) {
    $row = Get-AzTableRow -Table $cloudTable -PartitionKey $plan.PartitionKey -RowKey $plan.RowKey -ErrorAction Stop
    if ([string]$row.PossibleRootCause -ne $skuLabel -and [string]$row.RootCause -ne $skuLabel) {
        if ([string]$row.PossibleRootCause -eq $plan.NewRootCause -and [string]$row.RootCause -eq $plan.NewRootCause) { continue }
        throw "Row $($plan.RowKey) changed after the dry run; refusing update."
    }

    foreach ($name in @('PossibleRootCause','RootCause','DetailedRootCause','Subcategory','AIAnalysis','Confidence','Reasoning')) {
        Ensure-Property -Row $row -Name $name
    }
    $row.PossibleRootCause = $plan.NewRootCause
    $row.RootCause = $plan.NewRootCause
    $row.DetailedRootCause = $plan.NewDetailedRootCause
    if (-not [string]::IsNullOrWhiteSpace([string]$plan.NewSubcategory)) { $row.Subcategory = $plan.NewSubcategory }
    if (-not [string]::IsNullOrWhiteSpace([string]$plan.Confidence)) { $row.Confidence = $plan.Confidence }

    if ($plan.Action -eq $blackoutLabel) {
        $blackoutText = if ($row.RowKey -eq 'INC15527762') {
            'The source notes state additional Microsoft 365 Copilot licenses were unavailable during contract negotiations, with limited inventory and no new AGS assignments until the blackout is lifted.'
        } else {
            'The source notes explicitly state an active contract blackout during which additional Microsoft 365 Copilot licenses could not be purchased and the AGS entitlement would be hidden when inventory was depleted.'
        }
        $row.AIAnalysis = Set-AnalysisSection -Text ([string]$row.AIAnalysis) -Label 'Root Cause' -StopLabels @('Resolution','Evidence','AI Analysis') -Value $blackoutText
        $row.Reasoning = 'The work notes document an active Copilot contract blackout and unavailable additional license inventory. This meets the catalog evidence gate for Copilot License Blackout; it is not a regional SKU rollout issue.'
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$plan.RootNarrative)) {
        $row.AIAnalysis = Set-AnalysisSection -Text ([string]$row.AIAnalysis) -Label 'Root Cause' -StopLabels @('Resolution','Evidence','AI Analysis') -Value $plan.RootNarrative
        $row.Reasoning = $plan.RootNarrative
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$plan.NewAiNarrative)) {
        $row.AIAnalysis = Set-AiAnalysisParagraph -Text ([string]$row.AIAnalysis) -Narrative ([string]$plan.NewAiNarrative)
        $row.Reasoning = [string]$plan.NewAiNarrative
    }

    $aiParagraph = Get-AiAnalysisParagraph -Text ([string]$row.AIAnalysis)
    if ($aiParagraph -match $staleAiPattern) {
        $newAiNarrative = switch ($plan.Action) {
            $missingLabel { 'The ticket notes indicate that the required Microsoft 365 Copilot entitlement was not assigned or was pending an AGS request. This supports Copilot License Missing; no region or business-unit rollout cause is established.'; break }
            $blackoutLabel { 'The ticket notes document an active contract blackout and restricted M365 Copilot license inventory. This meets the Copilot License Blackout evidence gate.'; break }
            default { 'The ticket notes identify regional Copilot availability as the limiting factor. This supports Copilot SKU Not Provisioned rather than a missing account entitlement.'; break }
        }
        $row.AIAnalysis = Set-AiAnalysisParagraph -Text ([string]$row.AIAnalysis) -Narrative $newAiNarrative
        $row.Reasoning = $newAiNarrative
    }

    $null = $row | Update-AzTableRow -Table $cloudTable
    $updated++
}

foreach ($plan in $analysisPlans) {
    $row = Get-AzTableRow -Table $cloudTable -PartitionKey $plan.PartitionKey -RowKey $plan.RowKey -ErrorAction Stop
    Ensure-Property -Row $row -Name 'RootCause'
    Ensure-Property -Row $row -Name 'Reasoning'
    if ($plan.Action -eq 'Sync canonical RootCause') {
        if ([string]$row.Category -ne 'Microsoft 365 Copilot Issues' -or [string]::IsNullOrWhiteSpace([string]$row.PossibleRootCause)) {
            throw "Row $($plan.RowKey) changed category/root cause after dry run; refusing field sync."
        }
        $row.RootCause = [string]$row.PossibleRootCause
        $null = $row | Update-AzTableRow -Table $cloudTable
        $updated++
        continue
    }
    if ([string]$row.PossibleRootCause -ne $missingLabel) { throw "Row $($plan.RowKey) changed category/root cause after dry run; refusing analysis refresh." }
    $row.RootCause = $missingLabel
    $rootNarrative = Get-AnalysisSection -Text ([string]$row.AIAnalysis) -Label 'Root Cause' -StopLabels @('Resolution','Evidence','AI Analysis')
    if ($rootNarrative -match $staleAiPattern) {
        $detail = ([string]$row.DetailedRootCause).Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'Copilot for M365 entitlement was not assigned or was pending request' }
        $rootNarrative = "The ticket root-cause detail is: $detail. The user lacked the Copilot entitlement or needed to request it through AGS; no regional or business-unit rollout cause is established."
        $row.AIAnalysis = Set-AnalysisSection -Text ([string]$row.AIAnalysis) -Label 'Root Cause' -StopLabels @('Resolution','Evidence','AI Analysis') -Value $rootNarrative
    }
    $aiParagraph = Get-AiAnalysisParagraph -Text ([string]$row.AIAnalysis)
    if ($aiParagraph -match $staleAiPattern) {
        $narrative = 'The ticket notes indicate that the required Microsoft 365 Copilot entitlement was not assigned or was pending an AGS request. This supports Copilot License Missing; no region or business-unit rollout cause is established.'
        $row.AIAnalysis = Set-AiAnalysisParagraph -Text ([string]$row.AIAnalysis) -Narrative $narrative
        $row.Reasoning = $narrative
    }
    $null = $row | Update-AzTableRow -Table $cloudTable
    $updated++
}

Write-Host "Rows updated: $updated" -ForegroundColor Green
Write-Host "Backup: $backupPath" -ForegroundColor DarkGray