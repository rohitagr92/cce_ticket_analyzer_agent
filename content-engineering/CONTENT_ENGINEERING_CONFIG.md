# Content Engineering — Configuration Reference

Quick reference for all Azure resources, variables, runbooks, and schedules for the Content Engineering service offering.

---

## Azure Resources

| Resource | Type | Name / Value |
|---|---|---|
| Subscription | Azure Subscription | OPSW Resources (`1c6d384e-bc83-4b02-859c-76eeb87f7676`) |
| Resource Group | Resource Group | `OPSW-Ticket-Analyzer` |
| Storage Account | Azure Storage | `opswcontentenggblob` (East US, LRS) |
| Automation Account | Azure Automation | `OPSW-contentengg-account` (shared) |
| Azure OpenAI | Cognitive Services | `opsw-ticket-analyzer-foundary` (shared) |
| Static Web App | Web App | `opsw-prodtools-reports` (shared) |

---

## Storage Account — `opswcontentenggblob`

### Blob Containers

| Container | Purpose |
|---|---|
| `templates` | AI prompt `.md` template files (uploaded once, read at every job start) |
| `data` | Raw incident JSON + run artifacts per daily job |
| `logs` | Timestamped execution log files |
| `results` | Generated HTML reports served to the dashboard |

### Azure Table

| Name | Schema |
|---|---|
| `IncidentsCategoryStats` | PK=`YearWeek` (e.g. `2026-W27`), RK=`IncidentNumber` (e.g. `INC12345678`) |

---

## ServiceNow Scope

| Field | Value |
|---|---|
| Business Service sys_id | `a1de2ff2db8f50108062531dd3961911` (End-User Collaboration — shared with PT) |
| Service Offering sys_id | `ce614555dbeb5c105447610ed39619f8` (Content Engineering) |
| State filter | `stateIN6,7` (resolved + closed) |
| Sort order | `ORDERBYDESCresolved_at` (required) |
| Token URL | `https://apis.intel.com/v1/auth/token` |
| Incidents API URL | `https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=business_service=a1de2ff2db8f50108062531dd3961911^service_offering=ce614555dbeb5c105447610ed39619f8^stateIN6,7^ORDERBYDESCresolved_at&sysparm_display_value=true&sysparm_limit=1000` |

---

## Azure OpenAI (shared with Productivity Tools)

| Setting | Value |
|---|---|
| Endpoint | `https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com` |
| Deployment | `gpt-5.4-mini` |
| API Version | `2025-04-01-preview` |

---

## Automation Variables (`ContentEng_` prefix)

### Non-secret variables

| Variable Name | Value |
|---|---|
| `ContentEng_StorageAccountName` | `opswcontentenggblob` |
| `ContentEng_ResourceGroupName` | `OPSW-Ticket-Analyzer` |
| `ContentEng_PromptTemplateContainerName` | `templates` |
| `ContentEng_SubscriptionId` | `1c6d384e-bc83-4b02-859c-76eeb87f7676` |
| `ContentEng_DataContainerName` | `data` |
| `ContentEng_ResultsContainerName` | `results` |
| `ContentEng_TokenUrl` | `https://apis.intel.com/v1/auth/token` |
| `ContentEng_AzureOpenAIBaseUrl` | `https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com` |
| `ContentEng_AzureOpenAIDeployment` | `gpt-5.4-mini` |
| `ContentEng_AzureOpenAIApiVersion` | `2025-04-01-preview` |
| `ContentEng_ServiceNowIncidentsURL` | *(see ServiceNow Scope section above)* |
| `ContentEng_ServiceNowRequestsURL` | *(sc_task variant of the incidents URL)* |
| `ContentEng_BusinessServiceId` | `a1de2ff2db8f50108062531dd3961911` |
| `ContentEng_ServiceOfferingId` | `ce614555dbeb5c105447610ed39619f8` |
| `ContentEng_TrendTableName` | `IncidentsCategoryStats` |
| `ContentEng_TrendLookbackDays` | `2` |
| `ContentEng_ReconcileWeeksToCheck` | `2` |
| `ContentEng_ReconcileDeltaThreshold` | `0` |
| `ContentEng_ReconcileEnableAutoHeal` | `true` |
| `ContentEng_ReconcileMaxHealPerWeekPerDay` | `1` |
| `ContentEng_ReconcileDelayHours` | `30` |

### Encrypted variables (set during setup, not shown in Portal)

| Variable Name | What it holds |
|---|---|
| `ContentEng_ServiceNowClientID` | ServiceNow OAuth client ID |
| `ContentEng_ServiceNowClientSecret` | ServiceNow OAuth client secret |
| `ContentEng_ServiceNowScope` | OAuth scope (e.g. `api://.../.default`) |
| `ContentEng_AzureOpenAIApiKey` | Azure OpenAI API key |

---

## Runbooks

All 3 runbooks are in `content-engineering/runbooks/` and published to the `OPSW-contentengg-account` automation account.

| Runbook File | Published Name | Purpose |
|---|---|---|
| `incident-trend-backfill-rb-contenteng.ps1` | `incident-trend-backfill-rb-contenteng` | Daily incremental AI categorization — reads new incidents, calls OpenAI, writes to table |
| `incident-analyzer-rb-contenteng.ps1` | `incident-analyzer-rb-contenteng` | Main weekly analyzer — full analysis + HTML report generation |
| `incident-trend-rb-contenteng.ps1` | `incident-trend-rb-contenteng` | Rolling 7-day trend analysis — sub-categorizes spikes, generates trend report |

---

## Schedules

Staggered 30 min after the Productivity Tools schedules to avoid Automation Account contention.

Operational note: during CE historical-week rebuilds, the backfill schedules may be temporarily disabled to avoid stale backfill jobs overwriting structured analyzer output. Re-enable only after week data validation is complete.

| Schedule Name | Time (UTC) | Runbook |
|---|---|---|
| `IncidentTrendBackfill-ContentEng-Daily-0330UTC` | 03:30 | `incident-trend-backfill-rb-contenteng` |
| `IncidentAnalyzer-ContentEng-Daily-0630UTC` | 06:30 | `incident-analyzer-rb-contenteng` |
| `IncidentTrend-ContentEng-Daily-0830UTC` | 08:30 | `incident-trend-rb-contenteng` |

### Historical Week Recovery

Preferred order for CE historical week recovery:

1. Retrieve the target week directly from ServiceNow using the Content Engineering service offering scope.
2. Regenerate the week only from validated incident records, work notes, investigation notes, close notes, and engineer updates.
3. Normalize AIAnalysis into the structured incident detail format used by the web app:
   - `Problem:`
   - `Issue:`
   - `Root Cause:`
   - `Resolution:`
   - `Evidence:`
   - `AI Analysis (...)`
4. Validate table rows before considering the week complete:
   - `Category`, `Subcategory`, `Date`, and `YearWeek` must all be populated.
   - `AIAnalysis` must use the structured Problem format.

Restrictions:

- Do not use cached reports, historical artifacts, placeholder content, or prior generated summaries as the report data source for WW30 or future work weeks.
- Existing week output may be retained only when it is validated against current ServiceNow incident records and fully conforms to the approved Problem Analysis template.

---

## Template Files

All 6 templates are in `content-engineering/templates/` and must be uploaded to the `templates` container of `opswcontentenggblob`.

| File | Used by | Purpose |
|---|---|---|
| `TicketCategorisation_ContentEngineering.md` | backfill, analyzer, trend | Category + subcategory taxonomy |
| `EnvironmentContext_ContentEngineering.md` | backfill, analyzer, trend | In-scope/out-of-scope context for AI |
| `TrendSubCategorisation_ContentEngineering.md` | backfill, trend | Sub-symptom bold labels for trend analysis |
| `PossibleRootCause_ContentEngineering.md` | backfill, trend | Root cause bold labels |
| `WorkNotesCleanup_ContentEngineering.md` | analyzer | Work notes noise-removal rules |
| `WorkNotesSummary_ContentEngineering.md` | analyzer | Summary output format guidance |

---

## Quick Commands

### First-time setup (run once)
```powershell
cd content-engineering\setup
.\Setup-ContentEngineering.ps1
```

### Upload templates
```powershell
cd content-engineering\setup
.\Upload-ContentEngineeringTemplates.ps1
```

### Publish runbooks
```powershell
cd setup\publish
.\Publish-runbook.ps1 -SourceFile "..\..\content-engineering\runbooks\incident-trend-backfill-rb-contenteng.ps1"
.\Publish-runbook.ps1 -SourceFile "..\..\content-engineering\runbooks\incident-analyzer-rb-contenteng.ps1"
.\Publish-runbook.ps1 -SourceFile "..\..\content-engineering\runbooks\incident-trend-rb-contenteng.ps1"
```

Preferred CE flow:
```powershell
cd content-engineering\setup
.\Publish-ContentEngineeringRunbooks.ps1
```

That wrapper publishes the CE runbooks, relinks the two scheduled jobs, and leaves the trend runbook manual/on-demand.

### Trigger manual backfill (test run)
```powershell
cd setup\publish
.\Run-And-Wait.ps1 -RunbookName "incident-trend-backfill-rb-contenteng"
```

### Check latest job log
```powershell
cd setup
.\Get-Latest-Log.ps1 -RunbookName "incident-trend-backfill-rb-contenteng"
```

---

*Last updated: 2026-07-01*
