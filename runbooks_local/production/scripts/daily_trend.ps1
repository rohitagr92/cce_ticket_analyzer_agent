<#
.SYNOPSIS
    Wrapper to run the daily trend analysis either locally or via Azure Automation.

.DESCRIPTION
    - Loads configuration from `config/production_config.psd1`.
    - In Azure mode it starts the configured Automation runbook. In local mode it
      invokes the local `runbooks/incident-trend-rb-prodtools.ps1` script.

.NOTES
    - Keep secrets in Automation variables or local secrets files; this wrapper is non-sensitive.
#>

[CmdletBinding()]
param(
    [switch]$Local,
    [switch]$WaitForCompletion
)

Set-StrictMode -Version Latest
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptRoot '..\config\production_config.psd1'
if (-not (Test-Path $ConfigPath)) { Write-Error "Config not found: $ConfigPath"; exit 1 }
$config = Import-PowerShellDataFile -Path $ConfigPath

if ($Local -or -not $config.RunInAzureAutomation) {
    Write-Output "[LOCAL] Running trend runbook script directly..."
    $localScript = Join-Path $ScriptRoot '..\..\..\runbooks\incident-trend-rb-prodtools.ps1'
    if (-not (Test-Path $localScript)) { Write-Error "Local runbook not found: $localScript"; exit 1 }
    & $localScript
    exit $LASTEXITCODE
}

Write-Output "[AZURE] Starting Automation runbook: $($config.TrendRunbookName)"
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Automation -ErrorAction Stop
try { Connect-AzAccount -Identity -ErrorAction Stop | Out-Null } catch { Write-Warning "Managed identity sign-in failed: $($_.Exception.Message)" }

$job = Start-AzAutomationRunbook -ResourceGroupName $config.ResourceGroupName -AutomationAccountName $config.AutomationAccountName -Name $config.TrendRunbookName
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
