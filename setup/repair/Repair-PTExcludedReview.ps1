[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$ResourceGroup = 'OPSW-Ticket-Analyzer',
    [string]$StorageAccount = 'opswprodtoolsblob',
    [string]$TableName = 'IncidentsCategoryStats',
    [string]$AutomationAccount = 'OPSW-ProductivityTools-account'
)

$ErrorActionPreference = 'Stop'

$reclassifications = @(
    [pscustomobject]@{
        PartitionKey = '2026-W16'; RowKey = 'INC15409300'
        Category = 'Microsoft OneDrive Issues'; Subcategory = 'Access & Permission Issues'
        PossibleRootCause = 'Shared File Permission Denied'; DetailedRootCause = 'Content owner had not granted access to meeting files'
        Confidence = 'High'
        Issue = 'The user could not access meeting recordings and slides because permission to the underlying files had not been granted.'
        RootCauseNarrative = 'The user had not been invited to the meeting and lacked access to its SharePoint files. The content owner granted access after support provided the correct process.'
        Resolution = 'The content owner granted access to the meeting files, and support provided access-request guidance.'
        Evidence = 'The notes state the customer was not invited, the owner did not know how to grant file access, and access was later granted.'
        Reasoning = 'This was a file-level permission failure for meeting content, not a Teams meeting-service fault. The owner granting access restored the files, matching Microsoft OneDrive Issues and Access & Permission Issues. The work notes support Shared File Permission Denied.'
    }
    [pscustomobject]@{
        PartitionKey = '2026-W23'; RowKey = 'INC15555395'
        Category = 'Microsoft OneDrive Issues'; Subcategory = 'Access & Permission Issues'
        PossibleRootCause = 'Shared File Permission Denied'; DetailedRootCause = 'Original file permissions could not be reverted'
        Confidence = 'Medium'
        Issue = 'The user could not revert permissions on a specific SharePoint-hosted Word file, preventing normal access to the revised copy.'
        RootCauseNarrative = 'The notes identify a permission problem on one SharePoint file, not a Word client fault. The exact underlying permission state was not established; a duplicate file restored the user ability to work.'
        Resolution = 'The user created a duplicate file, uploaded it to the Teams-connected SharePoint location, and continued working in the new copy.'
        Evidence = 'Work notes say permissions could not be reverted on the specific SharePoint file; the duplicate was uploaded to the same path and the issue was resolved.'
        Reasoning = 'The affected item was one shared SharePoint file, and the documented workaround replaced that file after its permissions could not be reverted. This is a file-level access/permission issue rather than a Word application failure, so Microsoft OneDrive Issues is the closest PT category. Confidence is Medium because the notes do not establish the exact permission defect.'
    }
    [pscustomobject]@{
        PartitionKey = '2026-W14'; RowKey = 'INC15419108'
        Category = 'Microsoft OneDrive Issues'; Subcategory = 'Access & Permission Issues'
        PossibleRootCause = 'Former Employee Data Request'; DetailedRootCause = 'MDR process required for departed employee OneDrive data'
        Confidence = 'High'
        Issue = 'The requester needed access to a departed employee OneDrive content to retrieve recorded training material.'
        RootCauseNarrative = 'The content was stored in a departed employee OneDrive and required the Manager Data Retrieval process. This was a data-access workflow, not a OneDrive client or sync failure.'
        Resolution = 'Support provided the Manager Data Retrieval link and instructions; the user submitted the separate request.'
        Evidence = 'The user requested access to departed employee OneDrive content, and the notes say the MDR link was provided and submitted.'
        Reasoning = 'The ticket explicitly concerns access to a departed employee OneDrive data. The PT taxonomy includes Former Employee Data Request under Microsoft OneDrive, so this should not be Excluded merely because MDR is the required fulfillment process.'
    }
    [pscustomobject]@{
        PartitionKey = '2026-W32'; RowKey = 'INC15687763'
        Category = 'Microsoft OneDrive Issues'; Subcategory = 'Usage Queries'
        PossibleRootCause = 'OneDrive Configuration Request'; DetailedRootCause = 'External sharing required an approved SharePoint site'
        Confidence = 'High'
        Issue = 'The user asked how to share an internal OneDrive or SharePoint folder with an onboarded external guest.'
        RootCauseNarrative = 'The notes show the current internal site did not allow the requested external sharing. Support advised using an internal-external SharePoint site; no OneDrive sync or client fault was reported.'
        Resolution = 'Support recommended an internal-external SharePoint site and shared the related guidance.'
        Evidence = 'The user asked how to share a folder with an onboarded external guest; support advised using an internal-external SharePoint site.'
        Reasoning = 'This was a sharing-configuration question involving OneDrive/SharePoint, not a product malfunction. The PT root-cause catalog includes OneDrive Configuration Request for sharing guidance, so classify it as Microsoft OneDrive Issues / Usage Queries.'
    }
)

$analysisRepairs = @(
    [pscustomobject]@{ PartitionKey='2026-W22'; RowKey='INC15547462'; Narrative='The reported copy/paste problem occurred on claude.ai, which the notes identify as an unsupported third-party site. Support confirmed the approved access was for GitHub Copilot and directed the user to Intel-supported alternatives; no Productivity Tools product failure was documented.'; ExclusionReason='Out of scope - unsupported third-party claude.ai usage, not a Productivity Tools product issue.' }
    [pscustomobject]@{ PartitionKey='2026-W24'; RowKey='INC15539428'; Narrative='This was access to a SharePoint list used for an administrative Teams-license request workflow, not a shared end-user file or Productivity Tools application failure. Support submitted the request on the user behalf, and the user later regained access to the list; retain Excluded as a workflow/site-list access case.'; ExclusionReason='Out of scope - administrative SharePoint request-list access for a Teams licensing workflow.' }
    [pscustomobject]@{ PartitionKey='2026-W24'; RowKey='INC15566961'; Narrative='The user could not see folders in a Teams-connected SharePoint site, and access was restored when the site owner removed and re-added the user in site permissions. This is site/library membership administration, not a OneDrive client or shared-file permission fault; retain Excluded under the current SharePoint site-scope rule.'; ExclusionReason='Out of scope - SharePoint site/library membership administration.' }
    [pscustomobject]@{ PartitionKey='2026-W24'; RowKey='INC15567325'; Narrative='Teams and Outlook failed on the laptop but worked on the user mobile device. The user could connect through a mobile hotspot and access returned after restarting the home modem, supporting a home-network connectivity cause rather than a Productivity Tools product fault.'; ExclusionReason='Out of scope - home network connectivity issue affecting laptop access.' }
    [pscustomobject]@{ PartitionKey='2026-W24'; RowKey='INC15568548'; Narrative='The work notes describe an announced policy change blocking Altera accounts in desktop applications on Intel-managed devices while browser access remained available. Support explained the policy and directed the user to the web experience; this is cross-tenant access policy, not a PT product defect.'; ExclusionReason='Out of scope - Altera cross-tenant desktop-access policy.' }
    [pscustomobject]@{ PartitionKey='2026-W24'; RowKey='INC15575501'; Narrative='The notes say the user needed an M365 E3 license for Outlook and was referred to the sponsor for licensing. They do not document an Outlook desktop activation or client failure; this is treated as mailbox/licensing provisioning owned by Messaging, not a PT application incident.'; ExclusionReason='Out of scope - Outlook mailbox/licensing provisioning request.' }
    [pscustomobject]@{ PartitionKey='2026-W28'; RowKey='INC15628726'; Narrative='The work notes attribute the Outlook desktop restriction to the Altera account policy effective June 1, 2026, and state that web access remained supported. The user accepted the web alternative, so the cause is cross-tenant access policy rather than an Outlook client defect.'; ExclusionReason='Out of scope - Altera cross-tenant Outlook access policy.' }
    [pscustomobject]@{ PartitionKey='2026-W29'; RowKey='INC15640222'; Narrative='The user wanted to change desk-location information displayed in Microsoft 365 profile surfaces. Support supplied self-service profile-update instructions and the user confirmed success; this is identity/profile maintenance, not a Productivity Tools product fault.'; ExclusionReason='Out of scope - identity profile information update.' }
    [pscustomobject]@{ PartitionKey='2026-W30'; RowKey='INC15646193'; Narrative='The permission error was on Google Cloud billing-account creation, not Google Workspace apps such as Drive or Docs. The notes state the user Workspace license did not provide Google Cloud billing access and routed the request to the external hosting/Cloud CoE process.'; ExclusionReason='Out of scope - Google Cloud billing administration, not Google Workspace support.' }
)

$protected = @(
    [pscustomobject]@{ PartitionKey='2026-W16'; RowKey='INC15453874' }
    [pscustomobject]@{ PartitionKey='2026-W02'; RowKey='INC15221757' }
    [pscustomobject]@{ PartitionKey='2026-W03'; RowKey='INC15230366' }
    [pscustomobject]@{ PartitionKey='2026-W25'; RowKey='INC15583422' }
)

Import-Module AzTable -ErrorAction Stop
$activeJobs = @(Get-AzAutomationJob -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -ErrorAction Stop | Where-Object {
    $_.RunbookName -in @('incident-analyzer-rb-prodtools','incident-trend-backfill-rb-prodtools','incident-quality-guard-rb-prodtools') -and
    $_.Status -in @('New','Activating','Running','Queued')
})
if ($activeJobs.Count -gt 0) { throw 'A PT analyzer/backfill/quality job is active; refusing targeted write.' }

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount -ErrorAction Stop)[0].Value
$storageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $storageKey
$cloudTable = (Get-AzStorageTable -Name $TableName -Context $storageContext -ErrorAction Stop).CloudTable
$targets = @()

foreach ($plan in @($reclassifications) + @($analysisRepairs)) {
    $row = Get-AzTableRow -Table $cloudTable -PartitionKey $plan.PartitionKey -RowKey $plan.RowKey -ErrorAction Stop
    $isReclassified = $plan.PSObject.Properties['Category'] -and
        [string]$row.Category -eq [string]$plan.Category -and
        [string]$row.PossibleRootCause -eq [string]$plan.PossibleRootCause
    $alreadyApplied = $isReclassified -and [string]$row.Misrouted -ieq 'False' -and [string]::IsNullOrWhiteSpace([string]$row.ExclusionReason)
    if ([string]$row.Category -ne 'Excluded' -and -not $isReclassified) { throw "Refusing update: $($plan.RowKey) in $($plan.PartitionKey) is no longer Excluded." }
    if ([string]$row.AIAnalysis -match '(?i)Visual Studio Code|VS Code|GitHub Copilot' -and $plan.PSObject.Properties['Category']) {
        throw "Refusing reclassification of developer-tooling case $($plan.RowKey)."
    }
    $kind = if ($alreadyApplied) { 'Already applied' } elseif ($isReclassified) { 'Complete fields' } elseif ($plan.PSObject.Properties['Category']) { 'Reclassify' } else { 'Analysis refresh' }
    $targets += [pscustomobject]@{ PartitionKey=$plan.PartitionKey; RowKey=$plan.RowKey; CurrentCategory=[string]$row.Category; NewCategory=if ($plan.PSObject.Properties['Category']) {[string]$plan.Category} else {[string]$row.Category}; Kind=$kind }
}

foreach ($item in $protected) {
    $row = Get-AzTableRow -Table $cloudTable -PartitionKey $item.PartitionKey -RowKey $item.RowKey -ErrorAction Stop
    if ([string]$row.Category -ne 'Excluded') { throw "Protected exception $($item.RowKey) is unexpectedly not Excluded." }
    if ($targets.RowKey -contains $item.RowKey) { throw "Protected exception $($item.RowKey) is in the update plan." }
}

Write-Host "Rows planned: $($targets.Count) (4 reclassifications; $($analysisRepairs.Count) Excluded analysis refreshes)."
$targets | Format-Table PartitionKey,RowKey,Kind,CurrentCategory,NewCategory -AutoSize
if (-not $Apply) {
    Write-Host 'Dry run only. No Azure Table rows were changed. Re-run with -Apply to write the targeted updates.' -ForegroundColor Yellow
    return
}

$backupPath = Join-Path $PSScriptRoot ("..\archive\backups\pt-excluded-review-backup-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$originalRows = @()
foreach ($target in $targets) {
    $originalRows += Get-AzTableRow -Table $cloudTable -PartitionKey $target.PartitionKey -RowKey $target.RowKey -ErrorAction Stop
}
$originalRows | ConvertTo-Json -Depth 20 | Set-Content -Path $backupPath -Encoding UTF8

$updated = 0
foreach ($plan in $reclassifications) {
    $row = Get-AzTableRow -Table $cloudTable -PartitionKey $plan.PartitionKey -RowKey $plan.RowKey -ErrorAction Stop
    if ([string]$row.Category -eq $plan.Category -and [string]$row.PossibleRootCause -eq $plan.PossibleRootCause -and [string]$row.Misrouted -ieq 'False' -and [string]::IsNullOrWhiteSpace([string]$row.ExclusionReason)) { continue }
    $analysis = "Problem: $($plan.Issue)`nRoot Cause: $($plan.RootCauseNarrative)`nResolution: $($plan.Resolution)`nEvidence: $($plan.Evidence)`nAI Analysis ($($plan.Confidence) Confidence): $($plan.Reasoning)"
    $properties = @{
        Category = $plan.Category
        Subcategory = $plan.Subcategory
        PossibleRootCause = $plan.PossibleRootCause
        RootCause = $plan.PossibleRootCause
        DetailedRootCause = $plan.DetailedRootCause
        Confidence = $plan.Confidence
        Misrouted = $false
        Issue = $plan.Issue
        RootCauseNarrative = $plan.RootCauseNarrative
        Resolution = $plan.Resolution
        Evidence = $plan.Evidence
        Reasoning = $plan.Reasoning
        ExclusionReason = ''
        AIAnalysis = $analysis
        Service = 'Productivity Tools'
    }
    foreach ($name in $properties.Keys) {
        if ($null -eq $row.PSObject.Properties[$name]) { Add-Member -InputObject $row -MemberType NoteProperty -Name $name -Value '' -Force }
        $row.$name = $properties[$name]
    }
    $null = $row | Update-AzTableRow -Table $cloudTable
    $updated++
}

foreach ($plan in $analysisRepairs) {
    $row = Get-AzTableRow -Table $cloudTable -PartitionKey $plan.PartitionKey -RowKey $plan.RowKey -ErrorAction Stop
    $oldAnalysis = [string]$row.AIAnalysis
    $prefix = [regex]::Replace($oldAnalysis, '(?is)\r?\nAI Analysis\s*(?:\([^)]*\))?\s*:.*$', '').TrimEnd()
    if ($prefix -eq $oldAnalysis -or $prefix -notmatch '(?im)^\s*Problem\s*:') { throw "Could not safely isolate AI Analysis for $($plan.RowKey)." }
    $confidence = if ([string]::IsNullOrWhiteSpace([string]$row.Confidence)) { 'Medium' } else { [string]$row.Confidence }
    $newAnalysis = "$prefix`nAI Analysis ($confidence Confidence): $($plan.Narrative)"
    $row.AIAnalysis = $newAnalysis
    foreach ($name in @('Reasoning','ExclusionReason')) {
        if ($null -eq $row.PSObject.Properties[$name]) { Add-Member -InputObject $row -MemberType NoteProperty -Name $name -Value '' -Force }
    }
    $row.Reasoning = $plan.Narrative
    $row.ExclusionReason = $plan.ExclusionReason
    $null = $row | Update-AzTableRow -Table $cloudTable
    $updated++
}

Write-Host "Updated rows: $updated" -ForegroundColor Green
Write-Host "Backup: $backupPath" -ForegroundColor DarkGray