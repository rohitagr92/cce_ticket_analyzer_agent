# AI Ticket Analyzer â€” Project Overview

AI-powered incident categorization and trend analysis for ServiceNow service offerings, built on Azure Automation and Azure OpenAI.

---

## What It Does

- **Pulls** resolved/closed incidents from ServiceNow daily via OAuth2
- **Processes** each ticket through a 3-step AI pipeline: clean work notes â†’ summarize â†’ strict categorize
- **Stores** one row per incident in Azure Table Storage (`IncidentsCategoryStats`)
- **Generates** weekly HTML reports and rolling 7-day trend analysis reports
- **Serves** all reports and data to a team dashboard via Azure Static Web App

---

## Key Documents

| Document | Purpose |
|---|---|
| [SETUP_GUIDE.md](SETUP_GUIDE.md) | Step-by-step guide to set up from scratch for any service offering |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Azure component map, resource inventory, security notes |
| [PROCESS_FLOW.md](PROCESS_FLOW.md) | Detailed flow for each of the 4 production runbooks |
| [BLOB_STORAGE_SUMMARY.md](BLOB_STORAGE_SUMMARY.md) | Storage account layout, container purposes, table schema |

---

## Production Runbooks

| Runbook | Schedule (UTC) | Purpose |
|---|---|---|
| `incident-trend-backfill-rb-prodtools` | Daily ~03:00 | Incremental fill â€” cheap, idempotent |
| `incident-analyzer-rb-prodtools` | Daily ~06:00 | Full daily ingest + weekly report |
| `incident-reconcile-rb-prodtools` | Daily ~07:00 | Count check; auto-heal if gap |
| `incident-trend-rb-prodtools` | After analyzer | Trend analysis HTML report |

All runbooks live in `runbooks/` and run in the Azure Automation Account `OPSW-ProductivityTools-account`.

---

## AI Prompt Templates

Seven Markdown files in `templates/` define the AI's vocabulary. Uploaded to blob container `templates/` via `setup/publish/Upload-TemplateFiles.ps1`. No runbook republishing needed after a template update â€” runbooks always fetch the latest version at job start.

| Template | Role |
|---|---|
| `WorkNotesCleanup_ProductivityTools.md` | Strip noise from ServiceNow work notes |
| `WorkNotesSummary_ProductivityTools.md` | Summarize into concise problem/resolution |
| `TicketCategorisation_ProductivityTools.md` | Strict category + subcategory labels |
| `EnvironmentContext_ProductivityTools.md` | Domain knowledge about supported apps |
| `TrendSubCategorisation_ProductivityTools.md` | Sub-symptom labels (bold header format) |
| `PossibleRootCause_ProductivityTools.md` | Root cause labels (bold header format) |
| `DetailedRootCause_ProductivityTools.md` | Extended RCA descriptions (reference only) |

---

## Azure Resources

| Resource | Name |
|---|---|
| Resource Group | `OPSW-Ticket-Analyzer` |
| Automation Account | `OPSW-ProductivityTools-account` |
| Storage Account | `opswprodtoolsblob` |
| Azure OpenAI | `opsw-ticket-analyzer-foundary` (model `gpt-5.4-mini`) |
| Static Web App | `opsw-prodtools-reports` |
| Subscription | OPSW Resources (`1c6d384e-bc83-4b02-859c-76eeb87f7676`) |

---

## Local Development

1. Copy `config/LocalConfig-ProductivityTools.psd1` and `config/LocalSecrets-ProductivityTools.psd1`
2. Fill in your storage account name, Azure OpenAI endpoint/key, and ServiceNow credentials
3. Run any script in `local-dev/` or `tools/` directly from PowerShell

Secrets are **never committed** â€” `LocalSecrets-*.psd1` is git-ignored.

---

## Quick Reference â€” Utility Scripts

| Task | Script |
|---|---|
| Verify week compliance | `tools\verify_ww26_compliance.ps1 -YearWeek '2026-W27'` |
| Count rows in a week | `tools\count_table_week.ps1 -YearWeek '2026-W27'` |
| List all week partitions | `tools\list_table_partitions.ps1` |
| Look up an incident | `tools\find_incidents_in_table.ps1 -IncidentNumber 'INC1234567'` |
| Re-run AI for a week | `tools\fix_ai_analysis_by_week.ps1 -YearWeek '2026-W27'` |
| Publish backfill runbook | `setup\publish\Publish-TrendBackfillRunbook.ps1` |
| Upload templates to blob | `setup\publish\Upload-TemplateFiles.ps1` |


