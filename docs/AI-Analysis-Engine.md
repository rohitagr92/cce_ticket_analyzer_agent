# AI Analysis Engine

This repository now has a reusable PowerShell module for executive incident analysis:

- `setup/tools/AIAnalysisEngine.psm1`

The engine is designed to:

- produce one professional paragraph per incident
- prefer evidence from the ticket over generic fallback text
- detect label-style or weak analysis and mark it for reanalysis
- infer a root-cause status such as `Identified`, `Not Identified`, `Customer Non-Responsive`, or `No Issue Found`
- stay configurable so other service offerings can plug in their own field map later

## Typical usage

```powershell
Import-Module .\setup\tools\AIAnalysisEngine.psm1 -Force

$config = New-AiAnalysisEngineConfig -ServiceOfferingName 'Productivity Tools'
$analysis = Get-AiAnalysisExecutiveAnalysis -Ticket $ticket -Config $config -ModelAnalysisText $ticket.AIAnalysis

$analysis.ExecutiveAnalysis
$analysis.RootCauseStatus
```

## How to extend

For another service offering, pass a custom `FieldMap` to `New-AiAnalysisEngineConfig` so the engine can read that offering's issue, investigation, communication, and resolution fields without changing the core logic.