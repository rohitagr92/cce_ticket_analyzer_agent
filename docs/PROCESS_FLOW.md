# EUC Ticket Analyzer Agent — Process Flow

This document describes the end-to-end process flow for the two main runbooks:

1. **incident-analyzer-rb.ps1** — Daily incident categorization and weekly report generation
2. **incident-trend-rb.ps1** — Rolling 7-day trend analysis with AI sub-categorization

---

## 1. incident-analyzer-rb.ps1

### Purpose

Retrieves resolved incidents from ServiceNow, processes each ticket through a multi-step AI pipeline (work-note cleanup → summarization → strict categorization), merges daily results into a cumulative weekly report, and persists statistics to Azure Table Storage.

### High-Level Flow

```
┌─────────────────────────┐
│  Environment Detection  │
│  (Azure Automation vs   │
│   Local Development)    │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  Load Configuration     │
│  • Constants / secrets  │
│  • Prompt templates     │
│    from blob / local    │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  Initialize Logging     │
│  (Blob logging in Azure │
│   or console in local)  │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  Data Retrieval Phase   │
│  ┌─────────┐ ┌────────┐ │
│  │Live API │ │ Stored │ │
│  │(default)│ │  Data  │ │
│  └────┬────┘ └───┬────┘ │
│       └─────┬────┘      │
└─────────────┼───────────┘
              │
              ▼
┌─────────────────────────┐
│  Filter by Resolved     │
│  Window (lookback hrs)  │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  Save Raw Incidents     │
│  (blob or local JSON)   │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────────────────────┐
│  AI Processing Phase (per incident)     │
│                                         │
│  ┌────────────────────────────────┐     │
│  │ 1. Clean Work Notes            │     │
│  │    Prompt: WorkNotesCleanup    │     │
│  │    → strips noise from notes   │     │
│  └──────────────┬─────────────────┘     │
│                 ▼                        │
│  ┌────────────────────────────────┐     │
│  │ 2. Summarize Incident          │     │
│  │    Prompts: WorkNotesSummary   │     │
│  │           + EnvironmentContext  │     │
│  │    → concise problem/action    │     │
│  └──────────────┬─────────────────┘     │
│                 ▼                        │
│  ┌────────────────────────────────┐     │
│  │ 3. Strict Categorization       │     │
│  │    Prompts: TicketCategorisation│     │
│  │           + EnvironmentContext  │     │
│  │    → category, confidence,     │     │
│  │      reasoning, evidence       │     │
│  └──────────────┬─────────────────┘     │
│                 ▼                        │
│  ┌────────────────────────────────┐     │
│  │ 4. Store TicketAnalysis object │     │
│  │    in ProcessedTickets list    │     │
│  └────────────────────────────────┘     │
│                                         │
│  (retry up to 3× with exponential       │
│   backoff on rate-limit / 5xx errors;   │
│   3-second delay between tickets)       │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────┐
│  Save Run Artifact      │
│  run_artifact_<ts>.json │
│  (daily snapshot of     │
│   processed tickets +   │
│   summaries)            │
└───────────┬─────────────┘
            │
            ▼
┌──────────────────────────────┐
│  Merge Weekly Run Artifacts  │
│  • Scans all run_artifact_*  │
│    files for the current ISO │
│    week                      │
│  • Deduplicates by incident  │
│    number (keeps latest)     │
│  • Result replaces the       │
│    ProcessedTickets list     │
└───────────┬──────────────────┘
            │
            ▼
┌─────────────────────────┐
│  Category Statistics    │
│  Group tickets by       │
│  category, count, list  │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────────────┐
│  Report Generation              │
│  • HTML report with:            │
│    - Category summary table     │
│    - Incident detail table      │
│      (summaries + AI reasoning) │
│    - ServiceNow links           │
│  • Named by ISO week:           │
│    EUC_Weekly_Report_YYYY-Wnn   │
└───────────┬─────────────────────┘
            │
            ▼
┌──────────────────────────────────┐
│  Save Report                     │
│  • Azure: blob → results         │
│    container                     │
│  • Local: ./results/ directory   │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────┐
│  Save Statistics to Azure Table  │
│  (one row per incident:          │
│   PartitionKey = YearWeek,       │
│   RowKey = Incident Number)      │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────┐
│  Finalize Blob Logging           │
│  Flush remaining log buffer      │
└──────────────────────────────────┘
```

### Key Functions

| Function | Purpose |
|---|---|
| `Get-BlobMarkdownContent` | Load prompt template from blob storage or local `Templates/` |
| `Get-AccessToken` | OAuth client-credentials flow for ServiceNow API |
| `Invoke-AuthenticatedApiCall` | Unified HTTP client (Bearer token, API key, or Claude header) |
| `Get-CleanedWorkNotes` | AI call #1 — strips noise from work/close notes |
| `Get-IncidentSummary` | AI call #2 — generates concise problem/resolution summary |
| `Get-IncidentCategory` | AI call #3 — strict categorization with reasoning |
| `ConvertFrom-AiCategoryResponse` | Parses the AI's structured text response into fields |
| `Save-RunProcessingArtifact` | Persists daily snapshot (`run_artifact_*.json`) |
| `Get-MergedWeeklyRunData` | Merges all same-week artifacts, deduplicates by incident |
| `New-HtmlTicketReport` | Builds the full HTML weekly report |
| `Save-CategoryStatisticsToTable` | Writes per-incident rows to Azure Table Storage |

### AI Models Supported

The script supports two AI backends, selected via the `UseClaudeModel` configuration flag:

- **Azure OpenAI** — uses `api-key` header, standard chat completions endpoint
- **Claude (Anthropic)** — uses `x-api-key` + `anthropic-version` headers, model in request body

### Prompt Templates (loaded from `Templates/` or blob)

| Template | Used In |
|---|---|
| `WorkNotesCleanup.md` | Cleaning raw work notes |
| `WorkNotesSummary.md` | Summarizing cleaned notes |
| `TicketCategorisation.md` | Strict category assignment |
| `EnvironmentContext.md` | Appended to summary & categorization prompts as domain context |

### Data Artifacts

| File Pattern | Location | Contents |
|---|---|---|
| `incidents_<timestamp>.json` | `data/` container or local | Raw incidents from ServiceNow |
| `run_artifact_<timestamp>.json` | `data/` container or local | Processed tickets + summaries for one run |
| `EUC_Weekly_Report_YYYY-Wnn.html` | `results/` container or local | Cumulative weekly HTML report |

---

## 2. incident-trend-rb.ps1

### Purpose

Compares the most recent 7-day window of incidents against the previous 7-day window to detect categories with significant increases, then uses AI to sub-categorize the tickets driving each increase.

### High-Level Flow

```
┌─────────────────────────┐
│  Environment Detection  │
│  + Load Configuration   │
└───────────┬─────────────┘
            │
            ▼
┌──────────────────────────────────┐
│  Define Rolling 7-Day Windows    │
│                                  │
│  Current:  today-7  → yesterday  │
│  Previous: today-14 → today-8    │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────┐
│  Load Run Artifacts for Both     │
│  Windows                         │
│  • Scans run_artifact_*.json     │
│    from blob or local ./data/    │
│  • Filters by artifact date      │
│  • Deduplicates by incident      │
│    number (keeps latest)         │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────┐
│  Filter Excluded Categories      │
│  (removes "Excluded" and         │
│   "How Do I / User Education")   │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────┐
│  Compare Category Counts         │
│  (Compare-WeeklyCategories)      │
│  → per-category: currentCount,   │
│    previousCount, increase,      │
│    percentIncrease               │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────┐
│  Get Significant Increases       │
│  Filters where:                  │
│  • % increase ≥ threshold        │
│    (default 30%)                 │
│  • Current count ≥ minimum       │
│    (default 5)                   │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────────────────┐
│  AI Sub-Categorization                       │
│  (only for significant categories)           │
│                                              │
│  For each significant category:              │
│  ┌──────────────────────────────────────┐    │
│  │ 1. Gather current-period tickets     │    │
│  │ 2. Send to AI in batches of 30       │    │
│  │    Prompt: TrendSubCategorisation.md  │    │
│  │    → assigns a sub-category +        │    │
│  │      justification per ticket        │    │
│  │ 3. Repeat for previous-period        │    │
│  │    tickets (or reuse from cached     │    │
│  │    trend artifact)                   │    │
│  │ 4. Compare sub-category counts       │    │
│  │    → identify top drivers            │    │
│  └──────────────────────────────────────┘    │
└───────────────────┬──────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────┐
│  Generate HTML Trend Report      │
│  • Stats bar (totals + change)   │
│  • Category overview table       │
│    (all categories)              │
│  • Significant increase sections │
│    with sub-category breakdown   │
│    and key-driver callout        │
│  Named: EUC_Trend_Analysis_      │
│         YYYY-Wnn.html            │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────┐
│  Save Report                     │
│  • Azure: blob → results         │
│  • Local: ./results/             │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────┐
│  Save Trend Artifact             │
│  trend_artifact_<ts>.json        │
│  (caches sub-categorization      │
│   results to avoid re-running    │
│   AI for the previous period on  │
│   the next execution)            │
└──────────────────────────────────┘
```

### Key Functions

| Function | Purpose |
|---|---|
| `Get-MergedDateRangeData` | Loads and merges run artifacts whose date falls within a specified range; deduplicates by incident number |
| `Compare-WeeklyCategories` | Groups tickets by category, computes count/change/percent for each |
| `Get-SignificantIncreases` | Filters to categories meeting the threshold and minimum count |
| `Get-SubCategoryAnalysis` | Sends ticket batches to AI with `TrendSubCategorisation` prompt; returns sub-category + justification per ticket |
| `Compare-SubCategories` | Compares sub-category counts between current and previous periods |
| `New-TrendReportHtml` | Builds the full HTML trend report with tables, badges, and key-driver highlights |
| `Save-TrendArtifact` | Persists trend results as JSON for later reuse |
| `Get-PreviousTrendArtifact` | Loads a cached trend artifact to reuse previous-period sub-categorizations |

### Trend Configuration

| Setting | Default | Description |
|---|---|---|
| `SignificanceThresholdPercent` | 30 | Minimum % increase to flag a category |
| `MinIncidentCount` | 5 | Minimum current-period count to flag |
| `ExcludedCategories` | Excluded, How Do I / User Education | Categories skipped in trend analysis |
| `ArtifactLookbackDays` | 14 | How far back to scan for run artifacts |

### Data Dependencies

The trend script **does not call ServiceNow directly**. It relies entirely on `run_artifact_*.json` files produced by the daily runs of `incident-analyzer-rb.ps1`. Each artifact contains:

- `RunGeneratedAtUtc` — timestamp for date-range filtering
- `ProcessedTickets[]` — categorized ticket objects (Number, Category, Reasoning, etc.)
- `DetailedSummaries[]` — AI-generated summaries per incident

---

## How the Two Scripts Work Together

```
                    ┌──────────────────────────────┐
                    │   ServiceNow API             │
                    │   (resolved incidents)        │
                    └──────────────┬───────────────┘
                                   │
                                   ▼
  ┌─────────────────────────────────────────────────────┐
  │          incident-analyzer-rb.ps1  (daily)          │
  │                                                     │
  │  • Fetches & processes incidents                    │
  │  • AI categorization per ticket                     │
  │  • Saves run_artifact_*.json                        │
  │  • Merges week's artifacts → weekly HTML report     │
  │  • Saves statistics to Azure Table                  │
  └──────────────────────┬──────────────────────────────┘
                         │ produces
                         ▼
              run_artifact_*.json files
                         │
                         │ consumed by
                         ▼
  ┌─────────────────────────────────────────────────────┐
  │          incident-trend-rb.ps1  (daily/weekly)      │
  │                                                     │
  │  • Loads artifacts for two 7-day windows            │
  │  • Compares category counts                         │
  │  • AI sub-categorizes significant increases         │
  │  • Generates trend analysis HTML report             │
  │  • Saves trend_artifact_*.json for caching          │
  └─────────────────────────────────────────────────────┘
```

### Execution Order

1. **incident-analyzer-rb.ps1** runs first (typically daily via Azure Automation schedule).
2. **incident-trend-rb.ps1** runs after the analyzer completes, consuming the freshly produced `run_artifact_*.json`.

### Storage Layout

| Container / Folder | Contents |
|---|---|
| `data/` (blob or local) | `incidents_*.json`, `run_artifact_*.json`, `trend_artifact_*.json` |
| `results/` (blob or local) | `EUC_Weekly_Report_YYYY-Wnn.html`, `EUC_Trend_Analysis_YYYY-Wnn.html` |
| `prompt-templates/` (blob) or `Templates/` (local) | Markdown prompt files used by AI calls |
| `logs/` (blob, Azure only) | Timestamped execution logs |
| Azure Table `IncidentsCategoryStats` | Per-incident rows keyed by YearWeek + Incident Number |
