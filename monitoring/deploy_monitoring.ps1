<#
Deploy monitoring infrastructure for Automation runbooks: Log Analytics workspace,
Action Group (email -> Teams), Diagnostic Setting for Automation Account,
and a Scheduled Query Rule (alert) for failed runbook jobs.

Usage (run interactively or CI):
.
.
Install-Module -Name Az -Scope CurrentUser -Force

Set parameters and run:
.
$subscriptionId = '<SUBSCRIPTION_ID>'
$resourceGroup = '<RESOURCE_GROUP>'
$location = 'eastus'
$automationAccount = '<AUTOMATION_ACCOUNT_NAME>'
$workspaceName = 'rg-monitoring-workspace'
$actionGroupName = 'ag-automation-alerts'
$teamsEmail = '7d20a744.intel.onmicrosoft.com@amer.teams.ms'
.
.
Execute:
.
.
#> 
param(
    [Parameter(Mandatory=$true)] [string]$SubscriptionId,
    [Parameter(Mandatory=$true)] [string]$ResourceGroupName,
    [Parameter(Mandatory=$true)] [string]$Location,
    [Parameter(Mandatory=$true)] [string]$AutomationAccountName,
    [string]$WorkspaceName = 'la-opsw-prodtools',
    [string]$ActionGroupName = 'ag-opsw-automation-alerts',
    [string]$TeamsEmail = '7d20a744.intel.onmicrosoft.com@amer.teams.ms',
    [int]$AlertWindowMinutes = 15,
    [int]$AlertThresholdFailedJobs = 1
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.OperationalInsights -ErrorAction Stop
Import-Module Az.Monitor -ErrorAction Stop
Import-Module Az.Automation -ErrorAction Stop

Select-AzSubscription -SubscriptionId $SubscriptionId

# Create resource group if missing
if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating resource group $ResourceGroupName in $Location"
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
}

# Create Log Analytics workspace
$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction SilentlyContinue
if (-not $workspace) {
    Write-Host "Creating Log Analytics workspace $WorkspaceName"
    $workspace = New-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -Location $Location -Sku "PerGB2018" -RetentionInDays 30
}

# Create Action Group with Email Receiver (Teams channel email)
$existingAG = Get-AzActionGroup -ResourceGroupName $ResourceGroupName -Name $ActionGroupName -ErrorAction SilentlyContinue
if (-not $existingAG) {
    Write-Host "Creating Action Group $ActionGroupName with email receiver $TeamsEmail"
    $emailReceiver = New-AzActionGroupReceiver -Name 'teamsEmail' -EmailReceiverAddress $TeamsEmail
    New-AzActionGroup -ResourceGroupName $ResourceGroupName -Name $ActionGroupName -ShortName 'opswAG' -Receiver $emailReceiver | Out-Null
} else {
    Write-Host "Action Group $ActionGroupName already exists"
}

# Configure Diagnostic Settings on Automation Account to send JobStream / Job logs to LA workspace
$automationResourceId = (Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName -ErrorAction Stop).Id
$diagName = 'Diag-Automation-To-LA'
$existingDiag = Get-AzDiagnosticSetting -ResourceId $automationResourceId -Name $diagName -ErrorAction SilentlyContinue
if (-not $existingDiag) {
    Write-Host "Adding Diagnostic Setting to Automation Account -> Log Analytics"
    Set-AzDiagnosticSetting -ResourceId $automationResourceId -Name $diagName -WorkspaceId $workspace.ResourceId -Category "JobStreams","Job" -Enabled $true | Out-Null
} else {
    Write-Host "Diagnostic setting $diagName already present"
}

# Create Scheduled Query Rule: alert when failed jobs > threshold in the last window
$ruleName = 'Alert-Automation-FailedJobs'
$existingRule = Get-AzScheduledQueryRule -ResourceGroupName $ResourceGroupName -Name $ruleName -ErrorAction SilentlyContinue
$query = @"
AzureDiagnostics
| where Category == 'JobStreams' or Category == 'Job'
| where Level == 'Error' or Status_s == 'Failed'
| where TimeGenerated > ago({0}m)
| summarize FailedJobs = count()
| where FailedJobs >= {1}
"@ -f $AlertWindowMinutes, $AlertThresholdFailedJobs

if (-not $existingRule) {
    Write-Host "Creating scheduled query alert rule: $ruleName"
    $actionGroup = Get-AzActionGroup -ResourceGroupName $ResourceGroupName -Name $ActionGroupName

    $scope = @($workspace.ResourceId)

    $trigger = New-AzScheduledQueryRuleTrigger -Threshold $AlertThresholdFailedJobs -Operator GreaterThanOrEqual -MetricName 'FailedJobs' -MetricTriggerColumn 'FailedJobs' -MetricTriggerAggregation 'Total' -TimeWindow (New-TimeSpan -Minutes $AlertWindowMinutes) -Frequency (New-TimeSpan -Minutes 5)

    New-AzScheduledQueryRule -ResourceGroupName $ResourceGroupName -Name $ruleName -Location $Location -Description 'Alert when Automation runbook jobs fail' -Source (New-AzScheduledQueryRuleSource -Query $query -DataSourceId $workspace.ResourceId) -Action (New-AzScheduledQueryRuleAction -ActionGroupId $actionGroup.Id -Severity 2) -Enabled $true -FrequencyInMinutes 5 -WindowSizeInMinutes $AlertWindowMinutes | Out-Null
    Write-Host "Scheduled query alert created"
} else {
    Write-Host "Scheduled query rule $ruleName already exists"
}

Write-Host "Done. Review the workspace and alert in the portal before enabling broad alerts."
