Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Shared AI analysis engine for ServiceNow incident summaries.

.DESCRIPTION
    This module normalizes ticket fields, rejects weak fallback-style analysis,
    and builds a one-paragraph executive review from structured incident facts.

    The engine is service-offering aware through a config object. Productivity
    Tools can use it first, and future offerings can supply their own field map
    without changing the analysis contract.
#>

function New-AiAnalysisEngineConfig {
    [CmdletBinding()]
    param(
        [string]$ServiceOfferingName = 'Productivity Tools',
        [hashtable]$FieldMap = $null,
        [string]$DefaultRootCauseStatus = 'Not Identified'
    )

    $defaultFieldMap = @{
        ReportedIssue         = @('Issue', 'OriginalDescription', 'Description', 'ShortDescription')
        SupportActions        = @('SupportActions', 'ActionsTaken', 'WorkNotesSummary', 'NotesSummary')
        Investigation         = @('Investigation', 'InvestigationSummary', 'Troubleshooting', 'Evidence')
        Communications        = @('Communications', 'CustomerCommunicationSummary', 'FollowUpSummary', 'EmailsSent')
        ClassificationChanges = @('ClassificationChanges', 'ServiceClassificationSummary', 'RoutingChanges')
        FinalResolution       = @('Resolution', 'ClosureReason', 'Outcome')
        RootCauseStatus       = @('RootCauseStatus', 'RootCauseDisposition')
        Confidence            = @('Confidence')
    }

    if (-not $FieldMap) {
        $FieldMap = $defaultFieldMap
    }

    [pscustomobject]@{
        ServiceOfferingName    = $ServiceOfferingName
        FieldMap               = $FieldMap
        DefaultRootCauseStatus = $DefaultRootCauseStatus
    }
}

function Resolve-AiAnalysisFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string[]]$FieldNames
    )

    foreach ($fieldName in $FieldNames) {
        if ($null -eq $InputObject.PSObject.Properties[$fieldName]) { continue }
        $value = [string]$InputObject.$fieldName
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    }

    return $null
}

function Normalize-AiAnalysisText {
    [CmdletBinding()]
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    return ($Text -replace '\s+', ' ').Trim()
}

function Test-AiAnalysisNeedsReanalysis {
    [CmdletBinding()]
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $true }

    $clean = $Text.Trim()
    if ($clean.Length -lt 120) { return $true }

    $labelPattern = '(?im)(^|\n)\s*(category|symptom|possible root cause|detailed root cause|ai analysis|problem|root cause|resolution|evidence)\s*:'
    $fallbackPattern = '(?im)(generic fallback|fallback classification|not documented in the available work notes|not documented beyond the catalog classification|the notes do not clearly state)'
    $bulletPattern = '(?im)^[\s>*-]+'

    return [bool]($clean -match $labelPattern -or $clean -match $fallbackPattern -or $clean -match $bulletPattern)
}

function Resolve-AiAnalysisRootCauseStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Ticket,
        [Parameter(Mandatory)][object]$Config,
        [string]$TextHint = ''
    )

    $configuredStatus = Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames @('RootCauseStatus', 'RootCauseDisposition')
    if (-not [string]::IsNullOrWhiteSpace($configuredStatus)) {
        return $configuredStatus
    }

    $statusSource = @(
        (Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames $Config.FieldMap.RootCauseStatus),
        (Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames $Config.FieldMap.FinalResolution),
        (Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames $Config.FieldMap.Investigation),
        (Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames $Config.FieldMap.Communications),
        $TextHint
    ) -join ' '

    $statusSource = Normalize-AiAnalysisText -Text $statusSource
    if ([string]::IsNullOrWhiteSpace($statusSource)) {
        return $Config.DefaultRootCauseStatus
    }

    if ($statusSource -match '(?im)customer\s+non[- ]responsive|customer nonresponsive|no response from customer') {
        return 'Customer Non-Responsive'
    }

    if ($statusSource -match '(?im)no issue found|unable to reproduce|not reproducible|no defect found|working as expected') {
        return 'No Issue Found'
    }

    if ($statusSource -match '(?im)identified|confirmed|root cause identified|cause confirmed|resolved by') {
        return 'Identified'
    }

    if ($statusSource -match '(?im)not identified|unknown|undetermined|not confirmed|pending investigation') {
        return 'Not Identified'
    }

    return $Config.DefaultRootCauseStatus
}

function Get-AiAnalysisExecutiveAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Ticket,
        [object]$Config = (New-AiAnalysisEngineConfig),
        [string]$ModelAnalysisText = '',
        [string]$ReanalysisText = ''
    )

    $reportedIssue = Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames $Config.FieldMap.ReportedIssue
    $supportActions = Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames $Config.FieldMap.SupportActions
    $investigation = Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames $Config.FieldMap.Investigation
    $communications = Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames $Config.FieldMap.Communications
    $classificationChanges = Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames $Config.FieldMap.ClassificationChanges
    $finalResolution = Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames $Config.FieldMap.FinalResolution
    $confidence = Resolve-AiAnalysisFieldValue -InputObject $Ticket -FieldNames $Config.FieldMap.Confidence

    $candidateAnalysis = $null
    $analysisSource = 'Structured facts'

    if (-not [string]::IsNullOrWhiteSpace($ReanalysisText)) {
        $candidateAnalysis = Normalize-AiAnalysisText -Text $ReanalysisText
        $analysisSource = 'Reanalysis'
    } elseif (-not [string]::IsNullOrWhiteSpace($ModelAnalysisText)) {
        $candidateAnalysis = Normalize-AiAnalysisText -Text $ModelAnalysisText
        $analysisSource = 'Model analysis'
    }

    $needsReanalysis = $false
    if (-not [string]::IsNullOrWhiteSpace($candidateAnalysis)) {
        $needsReanalysis = Test-AiAnalysisNeedsReanalysis -Text $candidateAnalysis
    }

    if ($candidateAnalysis -and -not $needsReanalysis) {
        $rootCauseStatus = Resolve-AiAnalysisRootCauseStatus -Ticket $Ticket -Config $Config -TextHint $candidateAnalysis
        return [pscustomobject]@{
            ExecutiveAnalysis = $candidateAnalysis
            RootCauseStatus    = $rootCauseStatus
            Confidence         = if ([string]::IsNullOrWhiteSpace($confidence)) { 'Unknown' } else { $confidence }
            Source             = $analysisSource
            NeedsReanalysis    = $false
        }
    }

    $summarySegments = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($reportedIssue)) {
        $summarySegments.Add("The user reported $reportedIssue.")
    }

    $supportSentence = $null
    if (-not [string]::IsNullOrWhiteSpace($supportActions) -and -not [string]::IsNullOrWhiteSpace($communications)) {
        $followUpSummary = if ($communications -match '(?im)email') {
            'follow-up emails'
        } elseif ($communications -match '(?im)call|phone') {
            'phone follow-up'
        } else {
            'customer follow-up'
        }

        $supportSentence = "Support acknowledged the issue, took the following actions: $supportActions, and attempted $followUpSummary, but the customer did not provide additional information."
    } elseif (-not [string]::IsNullOrWhiteSpace($supportActions)) {
        $supportSentence = "Support acknowledged the issue and took the following actions: $supportActions."
    } elseif (-not [string]::IsNullOrWhiteSpace($communications)) {
        $supportSentence = "Support attempted customer follow-up via $communications."
    }

    if (-not [string]::IsNullOrWhiteSpace($supportSentence)) {
        $summarySegments.Add($supportSentence)
    }

    if (-not [string]::IsNullOrWhiteSpace($investigation)) {
        $summarySegments.Add("Investigation and troubleshooting showed $investigation.")
    }

    if (-not [string]::IsNullOrWhiteSpace($classificationChanges)) {
        $summarySegments.Add("During triage, the service classification was updated to $classificationChanges.")
    }

    if (-not [string]::IsNullOrWhiteSpace($finalResolution)) {
        $summarySegments.Add("The incident was ultimately closed as $finalResolution.")
    }

    $rootCauseStatus = Resolve-AiAnalysisRootCauseStatus -Ticket $Ticket -Config $Config -TextHint ($summarySegments -join ' ')
    $summarySegments.Add("Root cause status: $rootCauseStatus.")

    if ([string]::IsNullOrWhiteSpace($confidence)) {
        $confidence = 'Unknown'
    }

    $analysis = ($summarySegments -join ' ')
    $analysis = Normalize-AiAnalysisText -Text $analysis

    return [pscustomobject]@{
        ExecutiveAnalysis = $analysis
        RootCauseStatus    = $rootCauseStatus
        Confidence         = $confidence
        Source             = 'Structured facts'
        NeedsReanalysis    = $true
    }
}

Export-ModuleMember -Function `
    New-AiAnalysisEngineConfig, `
    Test-AiAnalysisNeedsReanalysis, `
    Get-AiAnalysisExecutiveAnalysis