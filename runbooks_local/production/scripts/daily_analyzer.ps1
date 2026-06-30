<#
.SYNOPSIS
    Wrapper to run the daily analyzer either locally or by starting the Azure Automation runbook.

.DESCRIPTION
    - Loads top-level configuration from `config/production_config.psd1`.
    - By default (RunInAzureAutomation = $true) starts the Automation Account runbook
      named in the configuration. For development, pass -Local or set RunInAzureAutomation
      to $false in the config to execute the local `runbooks/incident-analyzer-rb-prodtools.ps1` script.

.NOTES
    Requirements when running in Azure Automation mode:
      - Az.Accounts and Az.Automation modules available
      - Script executed with a principal that has permission to start runbooks (managed identity)
    Local mode simply executes the repository script file; it does NOT modify Automation settings.
#>

[CmdletBinding()]
param(
    [switch]$Local,
    [switch]$WaitForCompletion
)

Set-StrictMode -Version Latest
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptRoot '..\config\production_config.psd1'
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config not found: $ConfigPath"
    exit 1
}
$config = Import-PowerShellDataFile -Path $ConfigPath

if ($Local -or -not $config.RunInAzureAutomation) {
    Write-Output "[LOCAL] Running analyzer runbook script directly..."
    $localScript = Join-Path $ScriptRoot '..\..\..\runbooks\incident-analyzer-rb-prodtools.ps1'
    if (-not (Test-Path $localScript)) { Write-Error "Local runbook not found: $localScript"; exit 1 }
    & $localScript -DailyLookbackHours $config.DailyLookbackHours
    exit $LASTEXITCODE
}

Write-Output "[AZURE] Starting Automation runbook: $($config.AnalyzerRunbookName)"
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Automation -ErrorAction Stop
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
} catch {
    Write-Warning "Managed identity sign-in failed; ensure the caller can authenticate: $($_.Exception.Message)"
}

$params = @{ DailyLookbackHours = $config.DailyLookbackHours }
$job = Start-AzAutomationRunbook -ResourceGroupName $config.ResourceGroupName `
    -AutomationAccountName $config.AutomationAccountName -Name $config.AnalyzerRunbookName -Parameters $params

Write-Output "Started runbook job: $($job.JobId)"
if ($WaitForCompletion) {
    Write-Output "Waiting for completion..."
    for ($i=0; $i -lt 240; $i++) {
        $j = Get-AzAutomationJob -ResourceGroupName $config.ResourceGroupName -AutomationAccountName $config.AutomationAccountName -Id $job.JobId
        if ($j.Status -in @('Completed','Failed','Stopped','Suspended')) { break }
        Start-Sleep -Seconds 10
    }
    $j = Get-AzAutomationJob -ResourceGroupName $config.ResourceGroupName -AutomationAccountName $config.AutomationAccountName -Id $job.JobId
    Write-Output "Final job status: $($j.Status)"
}
