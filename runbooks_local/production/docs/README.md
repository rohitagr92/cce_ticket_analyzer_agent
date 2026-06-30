This folder holds simple, documented wrappers and a non-sensitive configuration file to
run the two daily runbooks locally or via Azure Automation.

Files:
- `config/production_config.psd1` : non-sensitive top-level settings (resource names, runbook names, schedule hours)
- `scripts/daily_analyzer.ps1`     : wrapper to run `incident-analyzer-rb-prodtools` (local or Azure)
- `scripts/daily_trend.ps1`        : wrapper to run `incident-trend-rb-prodtools` (local or Azure)

Usage examples:

Run analyzer locally (calls repository runbook script directly):

```powershell
.\runbooks_local\production\scripts\daily_analyzer.ps1 -Local
```

Start Azure Automation analyzer runbook (requires managed identity / Az modules):

```powershell
.\runbooks_local\production\scripts\daily_analyzer.ps1
```

To wait for the cloud job to finish (blocks):

```powershell
.\runbooks_local\production\scripts\daily_analyzer.ps1 -WaitForCompletion
```

Notes:
- Keep secrets out of `production_config.psd1`. Put secrets into Azure Automation variables
  for production, or into a local private secrets file for development.
- The wrappers are intentionally small: they avoid changing production runbooks and provide
  a single place for top-level configuration and safe invocation.
