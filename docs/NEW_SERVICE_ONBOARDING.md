# New Service Offering — Onboarding Guide

Step-by-step guide for onboarding a new team that has **nothing set up** and wants the same AI Ticket Analyzer system. Covers what Azure infrastructure to create, what to reuse from the existing setup, and every code change needed.

---

## Table of Contents

1. [What to Reuse vs What to Create New](#1-what-to-reuse-vs-what-to-create-new)
2. [Phase 1 — Azure Infrastructure](#2-phase-1--azure-infrastructure-20-min)
3. [Phase 2 — Automation Variables](#3-phase-2--automation-variables-15-min)
4. [Phase 3 — Template Files (AI Prompts)](#4-phase-3--template-files-ai-prompts-3060-min)
5. [Phase 4 — Runbooks](#5-phase-4--runbooks-20-min)
6. [Phase 5 — Schedules](#6-phase-5--schedules-10-min)
7. [Phase 6 — Dashboard](#7-phase-6--dashboard-10-min)
8. [Verify End-to-End](#8-verify-end-to-end)
9. [Summary Checklist](#9-summary-checklist)

---

## 1. What to Reuse vs What to Create New

| Azure Resource | Action | Why |
|---|---|---|
| Resource Group `OPSW-Ticket-Analyzer` | ✅ **Reuse** | Keep all related resources in one place |
| Automation Account `OPSW-ProductivityTools-account` | ✅ **Reuse** | Can host multiple runbooks for multiple offerings |
| Azure OpenAI `opsw-ticket-analyzer-foundary` | ✅ **Reuse** | Same deployment handles any number of offerings |
| Static Web App `opsw-prodtools-reports` | ✅ **Reuse** | Add new storage endpoints to `web/config.json` |
| Storage Account | 🆕 **Create new** | One per offering — keeps incidents, reports, and logs fully isolated |
| Blob containers (`templates`, `data`, `logs`, `results`) | 🆕 **Create new** | Lives in the new storage account |
| Azure Table `IncidentsCategoryStats` | 🆕 **Create new** | Lives in the new storage account |
| Automation Variables | 🆕 **New set** | Use a new name prefix so each offering's runbooks point at the right storage |
| ServiceNow OAuth credentials | ⚠️ **Check first** | Reuse if same API gateway app; create new if different tenant or app |
| Template `.md` files | 🆕 **Write new** | 7 files defining this team's category taxonomy and root causes |
| Runbooks | 🆕 **Copy + update** | Same logic, different variable name prefix and template filenames |
| Schedules | 🆕 **Create new** | Stagger 30 min after existing PT schedules to avoid overlap |

> **Key constraint — why runbook copies are needed:**  
> Each runbook reads Azure Automation Variables by exact name (e.g., `Incidents_analyzer_StorageAccountName`).  
> If you share the Automation Account, you must **copy the runbooks and rename every variable reference** — otherwise both offerings would point at the same storage account and overwrite each other's data.

---

## 2. Phase 1 — Azure Infrastructure (~20 min)

### Step 1 — Create a new Storage Account

Azure Portal: **Storage accounts → Create**

```
Resource Group:    OPSW-Ticket-Analyzer
Name:              <yourteam>blob       (e.g., opswemailcalblob — must be globally unique, lowercase, no dashes)
Region:            Same as existing (e.g., East US)
Performance:       Standard
Redundancy:        LRS
```

Reference: [Create a storage account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create)

---

### Step 2 — Grant the existing Automation Account access to the new storage account

The Automation Account managed identity already exists — it just needs IAM permission on the new storage account.

Azure Portal: **New storage account → Access Control (IAM) → Add role assignment**

Assign both roles to the **Managed Identity** of `OPSW-ProductivityTools-account`:

| Role | Why it is needed |
|---|---|
| `Storage Blob Data Contributor` | Read templates blob, write data / logs / results blobs |
| `Storage Account Contributor` | `Get-AzStorageAccountKey` called by runbooks to authenticate |

Reference: [Assign Azure roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-portal)

---

### Step 3 — Create blob containers in the new storage account

```powershell
cd setup\bootstrap
.\Create-BlobContainers.ps1 `
  -StorageAccountName "<yourteam>blob" `
  -ResourceGroupName "OPSW-Ticket-Analyzer"
```

Creates 4 private containers:

| Container | Used for |
|---|---|
| `templates` | AI prompt `.md` files (uploaded once, read by runbooks at every job start) |
| `data` | Raw incident JSON + run artifacts per daily run |
| `logs` | Timestamped execution log files |
| `results` | Generated HTML reports served to the dashboard |

---

### Step 4 — Create the Azure Table

```powershell
.\Setup-StatisticsTable.ps1 `
  -StorageAccountName "<yourteam>blob" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -TableName "IncidentsCategoryStats"
```

Creates `IncidentsCategoryStats` with schema: `PartitionKey=YearWeek`, `RowKey=IncidentNumber`, plus `Category`, `Subcategory`, `RootCause`, `AIAnalysis`, `Confidence`, `Date`, `YearWeek`, `Year`, `WeekNumber`, `ReportBlobName`.

Reference: [Azure Table storage overview](https://learn.microsoft.com/en-us/azure/storage/tables/table-storage-overview)

---

## 3. Phase 2 — Automation Variables (~15 min)

The runbooks read all config from Azure Automation Variables. You need a **new set with a unique prefix** so they target the new storage account and the correct ServiceNow scope.

### Step 5 — Create automation variables for the new offering

Azure Portal: **Automation account `OPSW-ProductivityTools-account` → Variables → Add variable**

Choose a short prefix for your team — e.g., `EC_` for Email & Calendaring, `SP_` for SharePoint, `HW_` for Hardware.

| Variable Name | Encrypted | Value |
|---|---|---|
| `<PREFIX>_StorageAccountName` | No | New storage account name |
| `<PREFIX>_ResourceGroupName` | No | `OPSW-Ticket-Analyzer` |
| `<PREFIX>_PromptTemplateContainerName` | No | `templates` |
| `<PREFIX>_SubscriptionId` | No | `1c6d384e-bc83-4b02-859c-76eeb87f7676` |
| `<PREFIX>_DataContainerName` | No | `data` |
| `<PREFIX>_ResultsContainerName` | No | `results` |
| `<PREFIX>_ServiceNowClientID` | No | OAuth2 client ID for this team's API app |
| `<PREFIX>_ServiceNowClientSecret` | **Yes (encrypted)** | OAuth2 client secret |
| `<PREFIX>_ServiceNowScope` | No | `api://<app-id>/.default` |
| `<PREFIX>_TokenUrl` | No | `https://apis.intel.com/v1/auth/token` |
| `<PREFIX>_AzureOpenAIBaseUrl` | No | Reuse: `https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com` |
| `<PREFIX>_AzureOpenAIDeployment` | No | Reuse: `gpt-5.4-mini` |
| `<PREFIX>_AzureOpenAIApiKey` | **Yes (encrypted)** | Reuse existing key (or new if dedicated quota needed) |
| `<PREFIX>_AzureOpenAIApiVersion` | No | `2025-04-01-preview` |

Reference: [Manage variables in Azure Automation](https://learn.microsoft.com/en-us/azure/automation/shared-resources/variables)

---

### Step 6 — Find your ServiceNow sys_ids

In ServiceNow:
- Navigate to **Business Services** → open the service record → copy `sys_id` from the browser URL bar
- Navigate to **Service Offerings** → open the offering record → copy `sys_id`

These are used in Step 10 to scope the ServiceNow query to this team's incidents only.

---

## 4. Phase 3 — Template Files (AI Prompts) (~30–60 min)

Templates are the AI's entire knowledge base for this offering. They define what categories, sub-symptoms, and root causes the AI is allowed to output — nothing outside these lists will appear in the results.

### Step 7 — Copy the ProductivityTools templates as a starting point

```powershell
Get-ChildItem templates\*_ProductivityTools.md | ForEach-Object {
    $newName = $_.Name -replace 'ProductivityTools', 'YourTeam'
    Copy-Item $_.FullName "templates\$newName"
}
```

### Step 8 — Edit each template for the new team

| File | What to change |
|---|---|
| `TicketCategorisation_YourTeam.md` | Replace entire category + subcategory taxonomy with this team's incident types |
| `EnvironmentContext_YourTeam.md` | Replace app list, platform details, and out-of-scope section for this team |
| `TrendSubCategorisation_YourTeam.md` | Replace all sub-symptom sections and **bold header labels** per category |
| `PossibleRootCause_YourTeam.md` | Replace root cause tables with **bold header labels** per category |
| `DetailedRootCause_YourTeam.md` | Replace extended RCA descriptions |
| `WorkNotesCleanup_YourTeam.md` | Usually minimal — add team-specific noise patterns to strip if needed |
| `WorkNotesSummary_YourTeam.md` | Usually minimal — adjust team-specific terminology if needed |

**Critical label rules:**
- Every category, sub-symptom, and root cause label must be wrapped in `**double asterisks**`
- The AI output format instruction tells the model to copy these labels verbatim — any free-form text fails compliance validation
- Sub-symptom and root cause labels must be **bold headers** (not bullet text) — bullets are examples, headers are the actual labels the AI outputs

### Step 9 — Upload templates to the new storage account

```powershell
cd setup\publish
.\Upload-TemplateFiles.ps1 `
  -StorageAccountName "<yourteam>blob" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -LocalTemplatesFolder "..\..\templates" `
  -ContainerName "templates"
```

Only upload the 7 `*_YourTeam.md` files — the ProductivityTools templates stay in their own storage account.

> **Tip:** Templates are fetched fresh at every job start. If you update a template file and re-upload it, the next job run picks it up automatically — no runbook republishing needed.

---

## 5. Phase 4 — Runbooks (~20 min)

### Step 10 — Copy all 4 runbooks and update variable names + template filenames

```powershell
# Example: copying for Email & Calendaring (prefix EC_)
Copy-Item runbooks\incident-analyzer-rb-prodtools.ps1       runbooks\incident-analyzer-rb-emailcal.ps1
Copy-Item runbooks\incident-trend-backfill-rb-prodtools.ps1  runbooks\incident-trend-backfill-rb-emailcal.ps1
Copy-Item runbooks\incident-trend-rb-prodtools.ps1          runbooks\incident-trend-rb-emailcal.ps1
Copy-Item runbooks\incident-reconcile-rb-prodtools.ps1      runbooks\incident-reconcile-rb-emailcal.ps1
```

Open each copy and do a **find-and-replace** for every variable name:

| Find (PT name) | Replace with (your prefix) |
|---|---|
| `Incidents_analyzer_StorageAccountName` | `EC_StorageAccountName` |
| `Incidents_analyzer_ResourceGroupName` | `EC_ResourceGroupName` |
| `Incidents_analyzer_PromptTemplateContainerName` | `EC_PromptTemplateContainerName` |
| `Incidents_analyzer_SubscriptionId` | `EC_SubscriptionId` |
| `Incidents_analyzer_DataContainerName` | `EC_DataContainerName` |
| `Incidents_analyzer_ResultsContainerName` | `EC_ResultsContainerName` |
| `ServiceNowIncidentsClientID` | `EC_ServiceNowClientID` |
| `ServiceNowIncidentsClientSecret` | `EC_ServiceNowClientSecret` |
| `ServiceNowIncidentsScope` | `EC_ServiceNowScope` |
| `AzureOpenAIBaseUrl` | `EC_AzureOpenAIBaseUrl` |
| `AzureOpenAIDeployment` | `EC_AzureOpenAIDeployment` |
| `AzureOpenAIApiKey` | `EC_AzureOpenAIApiKey` |
| `AzureOpenAIApiVersion` | `EC_AzureOpenAIApiVersion` |

In the **backfill** copy, set the ServiceNow scope to your team's IDs. Find the `Get-OptVar` block and update the hardcoded defaults:

```powershell
# In incident-trend-backfill-rb-emailcal.ps1
$BusinessServiceId = Get-OptVar 'EC_BusinessServiceId' '<your_business_service_sys_id>'
$ServiceOfferingId = Get-OptVar 'EC_ServiceOfferingId' '<your_service_offering_sys_id>'
```

Update template filenames in the **backfill** copy:

```powershell
# In incident-trend-backfill-rb-emailcal.ps1
$catTemplate    = Read-TemplateBlob -BlobName 'TicketCategorisation_YourTeam.md'
$envTemplate    = Read-TemplateBlob -BlobName 'EnvironmentContext_YourTeam.md'
$subCatTemplate = Read-TemplateBlob -BlobName 'TrendSubCategorisation_YourTeam.md'
$prcTemplate    = Read-TemplateBlob -BlobName 'PossibleRootCause_YourTeam.md'
```

Update template filenames in the **trend** copy:

```powershell
# In incident-trend-rb-emailcal.ps1 (inside the Main Execution try block)
$Script:TrendCatTemplate    = Get-PromptTemplate -TemplateName 'TicketCategorisation_YourTeam'
$Script:TrendEnvTemplate    = Get-PromptTemplate -TemplateName 'EnvironmentContext_YourTeam'
$Script:TrendSubCatTemplate = Get-PromptTemplate -TemplateName 'TrendSubCategorisation_YourTeam'
$Script:TrendPrcTemplate    = Get-PromptTemplate -TemplateName 'PossibleRootCause_YourTeam'
```

Also update the `ServiceNowIncidentsURL` variable reference in the **analyzer** copy to use your team's ServiceNow query (or point it at a new variable named `EC_ServiceNowIncidentsURL` that you set in Step 5).

---

### Step 11 — Publish all 4 runbooks to Azure Automation

```powershell
cd setup\publish

.\Publish-runbook.ps1 `
  -SourceFile "..\..\runbooks\incident-analyzer-rb-emailcal.ps1" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -AutomationAccountName "OPSW-ProductivityTools-account"

.\Publish-runbook.ps1 `
  -SourceFile "..\..\runbooks\incident-trend-backfill-rb-emailcal.ps1" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -AutomationAccountName "OPSW-ProductivityTools-account"

.\Publish-runbook.ps1 `
  -SourceFile "..\..\runbooks\incident-reconcile-rb-emailcal.ps1" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -AutomationAccountName "OPSW-ProductivityTools-account"

.\Publish-runbook.ps1 `
  -SourceFile "..\..\runbooks\incident-trend-rb-emailcal.ps1" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -AutomationAccountName "OPSW-ProductivityTools-account"
```

Verify: Azure Portal → Automation account → Runbooks — all 4 new runbooks show **Published** status.

---

## 6. Phase 5 — Schedules (~10 min)

Create 4 daily schedules, **staggered 30 min after the existing PT schedules** to avoid resource contention on the Automation Account.

Azure Portal: **Automation account → Schedules → Add a schedule**  
Reference: [Schedule a runbook](https://learn.microsoft.com/en-us/azure/automation/shared-resources/schedules)

| Schedule Name | Time (UTC) | Runbook to link |
|---|---|---|
| `IncidentTrendBackfill-YourTeam-Daily-0330UTC` | 03:30 | `incident-trend-backfill-rb-emailcal` |
| `IncidentAnalyzer-YourTeam-Daily-0630UTC` | 06:30 | `incident-analyzer-rb-emailcal` |
| `IncidentReconcile-YourTeam-Daily-0730UTC` | 07:30 | `incident-reconcile-rb-emailcal` |
| `IncidentTrend-YourTeam-Daily-0830UTC` | 08:30 | `incident-trend-rb-emailcal` |

**Link each schedule:** Open the runbook → **Schedules → Add a schedule → Link a schedule → select the new schedule → OK**

> The existing PT schedules run at 03:00 / 06:00 / 07:00 / 08:00 UTC. The 30-min stagger ensures no two runbooks compete for the same Automation sandbox at the same time.

---

## 7. Phase 6 — Dashboard (~10 min)

The existing Static Web App (`opsw-prodtools-reports`) can display data from both offerings side by side. You just add the new storage account endpoints to `web/config.json`.

### Step 12 — Generate a read-only SAS token for the new storage account

Azure Portal: **New storage account → Shared access signature**

| Setting | Value |
|---|---|
| Allowed services | Blob + Table |
| Allowed resource types | Container + Object |
| Allowed permissions | Read + List |
| Expiry | Set 1–2 years ahead |
| HTTPS only | Yes |

Copy the generated SAS token string.

Reference: [Grant limited access with SAS](https://learn.microsoft.com/en-us/azure/storage/common/storage-sas-overview)

### Step 13 — Add the new offering to `web/config.json`

```json
{
  "offerings": [
    {
      "name": "Productivity Tools",
      "storageAccount": "opswprodtoolsblob",
      "tableEndpoint": "https://opswprodtoolsblob.table.core.windows.net",
      "blobEndpoint":  "https://opswprodtoolsblob.blob.core.windows.net",
      "sasToken": "?sv=...",
      "tableName": "IncidentsCategoryStats",
      "resultsContainer": "results"
    },
    {
      "name": "Email and Calendaring",
      "storageAccount": "<yourteam>blob",
      "tableEndpoint": "https://<yourteam>blob.table.core.windows.net",
      "blobEndpoint":  "https://<yourteam>blob.blob.core.windows.net",
      "sasToken": "?sv=...",
      "tableName": "IncidentsCategoryStats",
      "resultsContainer": "results"
    }
  ]
}
```

### Step 14 — Redeploy the dashboard

```powershell
cd setup\publish
.\Deploy-Web.ps1
```

---

## 8. Verify End-to-End

### Trigger a manual test run

```powershell
cd setup\publish
.\Run-And-Wait.ps1 -RunbookName "incident-trend-backfill-rb-emailcal"
```

### Expected successful output

```
[HH:MM:SS] Loading Automation variables...
[HH:MM:SS] Loading prompt templates from container 'templates'...
[HH:MM:SS] Day 1/2 - YYYY-MM-DD  Fetched N incidents.
[HH:MM:SS] Day 2/2 - YYYY-MM-DD  Fetched N incidents.
  YYYY-MM-DD  fetched=X  saved=Y  skipped=Z  errors=0
TOTAL  fetched=X  saved=Y  skipped=Z  errors=0
Final status: Completed
```

### Confirm rows in the table

```powershell
cd tools
.\list_table_partitions.ps1
# Should show a 2026-WXX partition for the new storage account
```

### Check the dashboard

Open the Static Web App URL — the new offering's tab should appear and show the current week's data.

---

## 9. Summary Checklist

| # | Task | Tool / Location |
|---|---|---|
| 1 | Create new storage account | Azure Portal → Storage accounts |
| 2 | Assign `Storage Blob Data Contributor` + `Storage Account Contributor` to Automation Account managed identity | Azure Portal → new storage → IAM |
| 3 | Create 4 blob containers (`templates`, `data`, `logs`, `results`) | `setup\bootstrap\Create-BlobContainers.ps1` |
| 4 | Create `IncidentsCategoryStats` table | `setup\bootstrap\Setup-StatisticsTable.ps1` |
| 5 | Create 14 automation variables with new prefix | Azure Portal → Automation Account → Variables |
| 6 | Find ServiceNow `business_service` + `service_offering` sys_ids | ServiceNow |
| 7 | Copy 7 template files, rename, edit for new team | `templates\*_YourTeam.md` |
| 8 | Upload templates to new storage account | `setup\publish\Upload-TemplateFiles.ps1` |
| 9 | Copy 4 runbooks, rename, replace variable prefix + template filenames | `runbooks\*-emailcal.ps1` |
| 10 | Publish all 4 runbooks | `setup\publish\Publish-runbook.ps1` |
| 11 | Create 4 schedules (staggered +30 min from PT) | Azure Portal → Automation Account → Schedules |
| 12 | Generate read-only SAS token for new storage | Azure Portal → new storage → Shared access signature |
| 13 | Add new offering to `web/config.json` + redeploy | `setup\publish\Deploy-Web.ps1` |
| 14 | Trigger manual test run + verify rows + check dashboard | `setup\publish\Run-And-Wait.ps1` |

---

*Document last updated: 2026-07-01*
