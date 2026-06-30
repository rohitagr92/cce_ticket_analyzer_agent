# Blob & Table Storage â€” Current State

This document describes the storage layout, container purposes, and table schema for the AI Ticket Analyzer system.

---

## Storage Account

| Property | Value |
|---|---|
| Account name | `opswprodtoolsblob` |
| Resource Group | `OPSW-Ticket-Analyzer` |
| Subscription | OPSW Resources (`1c6d384e-bc83-4b02-859c-76eeb87f7676`) |
| Access | Managed identity (Automation Account) + read-only SAS (Static Web App) |

---

## Blob Containers

| Container | Access | Written by | Read by | Contents |
|---|---|---|---|---|
| `templates` | Private | Manual upload (`Upload-TemplateFiles.ps1`) | All runbooks at startup | AI prompt template `.md` files |
| `data` | Private | `incident-analyzer-rb-prodtools` | `incident-trend-rb-prodtools` | `incidents_*.json`, `run_artifact_*.json`, `trend_artifact_*.json` |
| `logs` | Private | All runbooks | Ops team | Timestamped execution log files per job run |
| `results` | Private | `incident-analyzer-rb-prodtools`, `incident-trend-rb-prodtools` | Static Web App (SAS read) | HTML report files served to the dashboard |

### Container: `templates`

Holds the 7 Markdown prompt templates used by the AI pipeline. All runbooks download the latest version at job start â€” no runbook republishing needed when templates change.

```
templates/
â”œâ”€â”€ WorkNotesCleanup_ProductivityTools.md       # Strips noise from ServiceNow work notes
â”œâ”€â”€ WorkNotesSummary_ProductivityTools.md       # Summarizes cleaned notes into problem/resolution
â”œâ”€â”€ EnvironmentContext_ProductivityTools.md     # Domain knowledge about supported apps and services
â”œâ”€â”€ TicketCategorisation_ProductivityTools.md   # Category + subcategory label taxonomy
â”œâ”€â”€ TrendSubCategorisation_ProductivityTools.md # Sub-symptom labels (bold header format)
â”œâ”€â”€ PossibleRootCause_ProductivityTools.md      # Root cause labels (bold header format)
â””â”€â”€ DetailedRootCause_ProductivityTools.md      # Extended RCA descriptions (reference, not in AI prompt)
```

> **Label format rule:** `TrendSubCategorisation` and `PossibleRootCause` files use `**bold headers**` as the canonical label text. The AI output format instruction requires the model to copy these exact bold labels verbatim. Any free-form text fails compliance validation.

### Container: `data`

Raw and processed data files produced by each daily analyzer run.

```
data/
â”œâ”€â”€ incidents_2026-06-29_06-12-34.json      # Raw ServiceNow incidents (one file per run)
â”œâ”€â”€ run_artifact_2026-06-29_06-18-00.json   # Processed tickets + AI summaries for one run
â””â”€â”€ trend_artifact_2026-06-29_07-05-00.json # Cached trend sub-category results
```

File naming:
- `incidents_<YYYY-MM-DD_HH-mm-ss>.json` â€” raw incidents from ServiceNow API
- `run_artifact_<YYYY-MM-DD_HH-mm-ss>.json` â€” processed tickets for one run (merged weekly by the analyzer)
- `trend_artifact_<YYYY-MM-DD_HH-mm-ss>.json` â€” trend sub-category results (cached to avoid repeat AI calls)

### Container: `results`

HTML report files served directly to the dashboard via SAS read token.

```
results/
â”œâ”€â”€ EUC_Weekly_Report_2026-W26.html     # Cumulative weekly incident categorization report
â”œâ”€â”€ EUC_Weekly_Report_2026-W27.html
â”œâ”€â”€ EUC_Trend_Analysis_2026-W26.html    # Rolling 7-day trend analysis report
â””â”€â”€ EUC_Trend_Analysis_2026-W27.html
```

All blobs in `results/` must be uploaded with `Content-Type: text/html` so browsers render them inline instead of downloading them.

---

## Azure Table Storage

### Table: `IncidentsCategoryStats`

One row per resolved/closed incident. Written by both `incident-analyzer-rb-prodtools` (full weekly pass) and `incident-trend-backfill-rb-prodtools` (incremental daily fill). Both use InsertOrReplace â€” safe to run multiple times.

**Schema:**

| Column | Type | Example | Notes |
|---|---|---|---|
| `PartitionKey` | String | `2026-W26` | ISO year-week of `resolved_at` |
| `RowKey` | String | `INC1234567` | Incident number |
| `Category` | String | `Application Issue` | Exact bold category label |
| `Subcategory` | String | `OneDrive Sync Issue` | Exact bold sub-symptom label |
| `RootCause` | String | `Corrupted Cache` | Exact bold PRC label |
| `AIAnalysis` | String | *(plain text)* | 2-3 sentence AI explanation |
| `Confidence` | String | `High` | `High` / `Medium` / `Low` |
| `Date` | String | `2026-06-28` | `resolved_at` date (YYYY-MM-DD) |
| `YearWeek` | String | `2026-W26` | Duplicate of PartitionKey (for query convenience) |
| `Year` | Int32 | `2026` | Calendar year |
| `WeekNumber` | Int32 | `26` | ISO week number |
| `ReportBlobName` | String | `run_artifact_2026-...json` | Source artifact filename |

**Partitioning strategy:**
- PartitionKey = YearWeek allows efficient range queries (e.g., all of WW26 in a single partition scan)
- RowKey = IncidentNumber ensures one row per incident, and InsertOrReplace keeps the latest AI result

**Access pattern from the dashboard:**
```
GET https://opswprodtoolsblob.table.core.windows.net/IncidentsCategoryStats
    ?$filter=PartitionKey eq '2026-W26'
    &<SAS token>
```

---

## SAS Token Usage

The Static Web App uses a **read-only SAS token** scoped to Blob + Table, stored in `web/config.json`. This token must be rotated before its expiry.

| Token scope | Permissions | Expiry to watch |
|---|---|---|
| Table `IncidentsCategoryStats` | Read, List | See `web/.sas-token.txt` |
| Blob `results/` container | Read, List | Same SAS token |

To regenerate: Azure Portal â†’ Storage account `opswprodtoolsblob` â†’ **Shared access signature** â†’ select Blob + Table, Read + List, set new expiry â†’ update `web/config.json` â†’ redeploy.

---

## Automation Account Access

The Automation Account managed identity has these roles on the storage account:

| Role | Why |
|---|---|
| `Storage Blob Data Contributor` | Read templates, write data/logs/results blobs |
| `Storage Account Contributor` | `Get-AzStorageAccountKey` for SDK-based table writes |

Table writes use `Microsoft.WindowsAzure.Storage` SDK (`InsertOrMerge` / `InsertOrReplace`) loaded via `Add-Type -AssemblyName` in PS 5.1 runbook runtime. Table reads use `Get-AzTableRow` from the `AzTable` module (PS 5.1 runtime).

