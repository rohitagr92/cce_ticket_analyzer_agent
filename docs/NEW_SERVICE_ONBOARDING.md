# New Service Offering — Onboarding Guide

Step-by-step guide for onboarding a new team that has **nothing set up** and wants the same AI Ticket Analyzer system. Covers what Azure infrastructure to create, what to reuse from the existing setup, and every code change needed.

> **Use the onboarding agent first:** `.github/agents/service-onboarding.agent.md` is the workspace agent for zero-knowledge service or service-offering onboarding. It keeps service-scoped and offering-scoped assets separate, protects production behavior, and requires live web app validation before the onboarding is considered complete.

> **Architecture note (updated 2026-07-09):** Each new offering now gets a **fully isolated stack** — its own **Automation Account**, **Key Vault** (for secrets), and **Storage Account** (blob + table). The only shared resources are the Resource Group, the Azure OpenAI deployment, and the Static Web App dashboard. Because the Automation Account is dedicated, runbooks keep the **same variable names** as Productivity Tools (no prefix rename needed) and secrets are read from Key Vault instead of encrypted Automation Variables. The running example below is **End User Conferencing → Meetings - Rooms and Hardware**.

---

## Table of Contents

1. [What to Reuse vs What to Create New](#1-what-to-reuse-vs-what-to-create-new)
2. [Phase 1 — Azure Infrastructure](#2-phase-1--azure-infrastructure-20-min)
3. [Phase 2 — Key Vault & Automation Variables](#3-phase-2--key-vault--automation-variables-15-min)
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
| Azure OpenAI `opsw-ticket-analyzer-foundary` | ✅ **Reuse** | Same deployment handles any number of offerings |
| Static Web App `opsw-prodtools-reports` | ✅ **Reuse** | Add new storage endpoints to `web/config.json` |
| Automation Account | 🆕 **Create new** | Dedicated account per offering — isolated runbooks, schedules, and managed identity |
| Key Vault | 🆕 **Create new** | Holds this offering's secrets (ServiceNow client secret, OpenAI key) |
| Storage Account | 🆕 **Create new** | One per offering — keeps incidents, reports, and logs fully isolated |
| Blob containers (`templates`, `data`, `logs`, `results`) | 🆕 **Create new** | Lives in the new storage account |
| Azure Table `IncidentsCategoryStats` | 🆕 **Create new** | Lives in the new storage account |
| Automation Variables | 🆕 **New set** | Same names as PT (no prefix) — the dedicated account keeps them isolated |
| ServiceNow OAuth credentials | ⚠️ **Check first** | Reuse if same API gateway app; create new if different tenant or app |
| Template `.md` files | 🆕 **Write new** | 7 files defining this team's category taxonomy and root causes |
| Runbooks | 🆕 **Copy + update** | Same logic; only template filenames, sys_ids, and Key Vault secret reads change |
| Schedules | 🆕 **Create new** | Separate sandbox — no need to stagger against PT schedules |

> **Why a dedicated Automation Account:**  
> With an isolated account, runbooks keep the **same variable names** as Productivity Tools (e.g., `Incidents_analyzer_StorageAccountName`) — no prefix rename is needed, because there is no collision. Secrets move to the new Key Vault, and the account's own system-assigned managed identity is granted access to the new Storage Account and Key Vault.

---

## 2. Phase 1 — Azure Infrastructure (~30 min)

Running example: **End User Conferencing** → offering **Meetings - Rooms and Hardware**.
Suggested names: Automation Account `OPSW-Conferencing-account`, Key Vault `opsw-conferencing-kv`, Storage Account `opswconferencingblob`.

### Step 1 — Create the new Automation Account

Azure Portal: **Automation Accounts → Create**

```
Resource Group:    OPSW-Ticket-Analyzer
Name:              OPSW-Conferencing-account
Region:            Same as existing (e.g., East US)
Identity:          System-assigned managed identity = ON
```

After creation, confirm **Identity → System assigned → Status = On** and note the **Object (principal) ID** — you grant it storage and Key Vault access in Step 4. Import the required modules (Runtime 7.2): `Az.Accounts`, `Az.Storage`, `Az.KeyVault`, `AzTable`.

Reference: [Create an Automation account](https://learn.microsoft.com/en-us/azure/automation/quickstarts/create-azure-automation-account-portal)

---

### Step 2 — Create the new Key Vault

Azure Portal: **Key vaults → Create**

```
Resource Group:    OPSW-Ticket-Analyzer
Name:              opsw-conferencing-kv     (globally unique)
Region:            Same as existing
Permission model:  Azure role-based access control (RBAC)
```

Reference: [Create a Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/quick-create-portal)

---

### Step 3 — Create the new Storage Account

Azure Portal: **Storage accounts → Create**

```
Resource Group:    OPSW-Ticket-Analyzer
Name:              opswconferencingblob      (must be globally unique, lowercase, no dashes)
Region:            Same as existing (e.g., East US)
Performance:       Standard
Redundancy:        LRS
```

Reference: [Create a storage account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create)

---

### Step 4 — Grant the new Automation Account's managed identity access

Assign roles to the **system-assigned managed identity** of `OPSW-Conferencing-account`:

**On the new storage account** — Access Control (IAM) → Add role assignment:

| Role | Why it is needed |
|---|---|
| `Storage Blob Data Contributor` | Read templates blob, write data / logs / results blobs |
| `Storage Account Contributor` | `Get-AzStorageAccountKey` called by runbooks to authenticate |

**On the new Key Vault** — Access control (IAM) → Add role assignment:

| Role | Why it is needed |
|---|---|
| `Key Vault Secrets User` | Runbooks call `Get-AzKeyVaultSecret` to read ServiceNow + OpenAI secrets |

Reference: [Assign Azure roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-portal)

---

### Step 5 — Create blob containers in the new storage account

```powershell
cd setup\bootstrap
.\Create-BlobContainers.ps1 `
  -StorageAccountName "opswconferencingblob" `
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

### Step 6 — Create the Azure Table

```powershell
.\Setup-StatisticsTable.ps1 `
  -StorageAccountName "opswconferencingblob" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -TableName "IncidentsCategoryStats"
```

Creates `IncidentsCategoryStats` with schema: `PartitionKey=YearWeek`, `RowKey=IncidentNumber`, plus `Category`, `Subcategory`, `RootCause`, `AIAnalysis`, `Confidence`, `Date`, `YearWeek`, `Year`, `WeekNumber`, `ReportBlobName`.

Reference: [Azure Table storage overview](https://learn.microsoft.com/en-us/azure/storage/tables/table-storage-overview)

---

## 3. Phase 2 — Key Vault & Automation Variables (~15 min)

Secrets live in the new **Key Vault**; non-secret config lives in **Automation Variables** on the new account. Because the account is dedicated, variables keep the **same names** as Productivity Tools — no prefix.

### Step 7 — Add secrets to the new Key Vault

Azure Portal: **Key vault `opsw-conferencing-kv` → Secrets → Generate/Import** (or via `Set-AzKeyVaultSecret`):

| Secret Name | Value |
|---|---|
| `ServiceNowClientSecret` | OAuth2 client secret for this team's API app |
| `AzureOpenAIApiKey` | Reuse existing OpenAI key (or a new key if dedicated quota is needed) |

Reference: [Set and retrieve a secret](https://learn.microsoft.com/en-us/azure/key-vault/secrets/quick-create-portal)

---

### Step 8 — Create automation variables for the new offering

Azure Portal: **Automation account `OPSW-Conferencing-account` → Variables → Add variable**

| Variable Name | Encrypted | Value |
|---|---|---|
| `Incidents_analyzer_StorageAccountName` | No | `opswconferencingblob` |
| `Incidents_analyzer_ResourceGroupName` | No | `OPSW-Ticket-Analyzer` |
| `Incidents_analyzer_PromptTemplateContainerName` | No | `templates` |
| `Incidents_analyzer_SubscriptionId` | No | `1c6d384e-bc83-4b02-859c-76eeb87f7676` |
| `Incidents_analyzer_DataContainerName` | No | `data` |
| `Incidents_analyzer_ResultsContainerName` | No | `results` |
| `KeyVaultName` | No | `opsw-conferencing-kv` |
| `ServiceNowIncidentsClientID` | No | OAuth2 client ID for this team's API app |
| `ServiceNowIncidentsScope` | No | `api://<app-id>/.default` |
| `TokenUrl` | No | `https://apis.intel.com/v1/auth/token` |
| `AzureOpenAIBaseUrl` | No | Reuse: `https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com` |
| `AzureOpenAIDeployment` | No | Reuse: `gpt-5.4-mini` |
| `AzureOpenAIApiVersion` | No | `2025-04-01-preview` |

> Secrets (`ServiceNowClientSecret`, `AzureOpenAIApiKey`) are **not** stored here — they come from Key Vault (Step 7) via `Get-AzKeyVaultSecret` using the `KeyVaultName` variable.

Reference: [Manage variables in Azure Automation](https://learn.microsoft.com/en-us/azure/automation/shared-resources/variables)

---

### Step 9 — Find your ServiceNow sys_ids

In ServiceNow:
- **Business Services** → open **End User Conferencing** → copy `sys_id` from the browser URL bar
- **Service Offerings** → open **Meetings - Rooms and Hardware** → copy `sys_id`

These are used in Step 13 to scope the ServiceNow query to this team's incidents only.

---

## 4. Phase 3 — Template Files (AI Prompts) (~30–60 min)

Templates are the AI's entire knowledge base for this offering. They define what categories, sub-symptoms, and root causes the AI is allowed to output — nothing outside these lists will appear in the results.

### Step 10 — Copy the ProductivityTools templates as a starting point

```powershell
Get-ChildItem templates\*_ProductivityTools.md | ForEach-Object {
    $newName = $_.Name -replace 'ProductivityTools', 'Conferencing'
    Copy-Item $_.FullName "templates\$newName"
}
```

### Step 11 — Edit each template for the new team

| File | What to change |
|---|---|
| `TicketCategorisation_Conferencing.md` | Replace entire category + subcategory taxonomy with conferencing incident types (Teams/Zoom meetings, room systems/MTRs, cameras/mics/displays, peripherals, booking/join failures) |
| `EnvironmentContext_Conferencing.md` | Replace app list, platform details, and out-of-scope section for this team |
| `TrendSubCategorisation_Conferencing.md` | Replace all sub-symptom sections and **bold header labels** per category |
| `PossibleRootCause_Conferencing.md` | Replace root cause tables with **bold header labels** per category |
| `DetailedRootCause_Conferencing.md` | Replace extended RCA descriptions |
| `WorkNotesCleanup_Conferencing.md` | Usually minimal — add team-specific noise patterns to strip if needed |
| `WorkNotesSummary_Conferencing.md` | Usually minimal — adjust team-specific terminology if needed |

**Critical label rules:**
- Every category, sub-symptom, and root cause label must be wrapped in `**double asterisks**`
- The AI output format instruction tells the model to copy these labels verbatim — any free-form text fails compliance validation
- Sub-symptom and root cause labels must be **bold headers** (not bullet text) — bullets are examples, headers are the actual labels the AI outputs

### Step 12 — Upload templates to the new storage account

```powershell
cd setup\publish
.\Upload-TemplateFiles.ps1 `
  -StorageAccountName "opswconferencingblob" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -LocalTemplatesFolder "..\..\templates" `
  -ContainerName "templates"
```

Only upload the 7 `*_Conferencing.md` files — the ProductivityTools templates stay in their own storage account.

> **Tip:** Templates are fetched fresh at every job start. If you update a template file and re-upload it, the next job run picks it up automatically — no runbook republishing needed.

---

## 5. Phase 4 — Runbooks (~20 min)

Because the offering has its **own Automation Account**, the runbooks keep the **same variable names** — you do **not** rename variables. You only change: template filenames, the ServiceNow sys_ids, and the secret reads (from encrypted variables to Key Vault).

### Step 13 — Copy all 4 runbooks and update template filenames, sys_ids, and secret reads

```powershell
Copy-Item runbooks\incident-analyzer-rb-prodtools.ps1        runbooks\incident-analyzer-rb-conferencing.ps1
Copy-Item runbooks\incident-trend-backfill-rb-prodtools.ps1  runbooks\incident-trend-backfill-rb-conferencing.ps1
Copy-Item runbooks\incident-trend-rb-prodtools.ps1           runbooks\incident-trend-rb-conferencing.ps1
Copy-Item runbooks\incident-reconcile-rb-prodtools.ps1       runbooks\incident-reconcile-rb-conferencing.ps1
```

**a) Read secrets from Key Vault.** Replace the encrypted-variable reads with Key Vault lookups (the managed identity was granted `Key Vault Secrets User` in Step 4):

```powershell
# Near secret loading — replaces Get-AutomationVariable for the two secrets
$kvName          = Get-AutomationVariable -Name 'KeyVaultName'
$snClientSecret  = (Get-AzKeyVaultSecret -VaultName $kvName -Name 'ServiceNowClientSecret' -AsPlainText)
$azureOpenAIKey  = (Get-AzKeyVaultSecret -VaultName $kvName -Name 'AzureOpenAIApiKey' -AsPlainText)
```

**b) Set the ServiceNow sys_ids** in the **backfill** copy (from Step 9):

```powershell
# In incident-trend-backfill-rb-conferencing.ps1
$BusinessServiceId = Get-OptVar 'BusinessServiceId' '<end_user_conferencing_sys_id>'
$ServiceOfferingId = Get-OptVar 'ServiceOfferingId' '<meetings_rooms_and_hardware_sys_id>'
```

**c) Update template filenames** in the **backfill** copy:

```powershell
# In incident-trend-backfill-rb-conferencing.ps1
$catTemplate    = Read-TemplateBlob -BlobName 'TicketCategorisation_Conferencing.md'
$envTemplate    = Read-TemplateBlob -BlobName 'EnvironmentContext_Conferencing.md'
$subCatTemplate = Read-TemplateBlob -BlobName 'TrendSubCategorisation_Conferencing.md'
$prcTemplate    = Read-TemplateBlob -BlobName 'PossibleRootCause_Conferencing.md'
```

**d) Update template filenames** in the **trend** copy:

```powershell
# In incident-trend-rb-conferencing.ps1 (inside the Main Execution try block)
$Script:TrendCatTemplate    = Get-PromptTemplate -TemplateName 'TicketCategorisation_Conferencing'
$Script:TrendEnvTemplate    = Get-PromptTemplate -TemplateName 'EnvironmentContext_Conferencing'
$Script:TrendSubCatTemplate = Get-PromptTemplate -TemplateName 'TrendSubCategorisation_Conferencing'
$Script:TrendPrcTemplate    = Get-PromptTemplate -TemplateName 'PossibleRootCause_Conferencing'
```

**e)** Point the analyzer copy's `ServiceNowIncidentsURL` at this team's ServiceNow query scoped to the two sys_ids. Keep `^ORDERBYDESCresolved_at` before `&sysparm_limit=` — omitting it silently drops the most recent week.

---

### Step 14 — Publish all 4 runbooks to the new Automation Account

```powershell
cd setup\publish

.\Publish-runbook.ps1 `
  -SourceFile "..\..\runbooks\incident-analyzer-rb-conferencing.ps1" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -AutomationAccountName "OPSW-Conferencing-account"

.\Publish-runbook.ps1 `
  -SourceFile "..\..\runbooks\incident-trend-backfill-rb-conferencing.ps1" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -AutomationAccountName "OPSW-Conferencing-account"

.\Publish-runbook.ps1 `
  -SourceFile "..\..\runbooks\incident-reconcile-rb-conferencing.ps1" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -AutomationAccountName "OPSW-Conferencing-account"

.\Publish-runbook.ps1 `
  -SourceFile "..\..\runbooks\incident-trend-rb-conferencing.ps1" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -AutomationAccountName "OPSW-Conferencing-account"
```

Verify: Azure Portal → Automation account `OPSW-Conferencing-account` → Runbooks — all 4 new runbooks show **Published** status.

---

## 6. Phase 5 — Schedules (~10 min)

Create 4 daily schedules on the new Automation Account. Because this is a **dedicated account with its own sandboxes**, there is no need to stagger against the PT schedules — but keep the natural order (backfill → analyzer → reconcile → trend).

Azure Portal: **Automation account `OPSW-Conferencing-account` → Schedules → Add a schedule**  
Reference: [Schedule a runbook](https://learn.microsoft.com/en-us/azure/automation/shared-resources/schedules)

| Schedule Name | Time (UTC) | Runbook to link |
|---|---|---|
| `IncidentTrendBackfill-Conferencing-Daily-0300UTC` | 03:00 | `incident-trend-backfill-rb-conferencing` |
| `IncidentAnalyzer-Conferencing-Daily-0600UTC` | 06:00 | `incident-analyzer-rb-conferencing` |
| `IncidentReconcile-Conferencing-Daily-0700UTC` | 07:00 | `incident-reconcile-rb-conferencing` |
| `IncidentTrend-Conferencing-Daily-0800UTC` | 08:00 | `incident-trend-rb-conferencing` |

**Link each schedule:** Open the runbook → **Schedules → Add a schedule → Link a schedule → select the new schedule → OK**

> **Gotcha:** `Publish-runbook.ps1` does a Remove + Import, which **drops the schedule link**. After re-publishing the analyzer runbook you must re-link its schedule.

---

## 7. Phase 6 — Dashboard (~10 min)

The existing Static Web App (`opsw-prodtools-reports`) can display data from both offerings side by side. You just add the new storage account endpoints to `web/config.json`.

### Step 16 — Generate a read-only SAS token for the new storage account

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

### Step 17 — Add the new offering to `web/config.json`

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
      "name": "End User Conferencing",
      "storageAccount": "opswconferencingblob",
      "tableEndpoint": "https://opswconferencingblob.table.core.windows.net",
      "blobEndpoint":  "https://opswconferencingblob.blob.core.windows.net",
      "sasToken": "?sv=...",
      "tableName": "IncidentsCategoryStats",
      "resultsContainer": "results"
    }
  ]
}
```

### Step 18 — Redeploy the dashboard

```powershell
cd setup\publish
.\Deploy-Web.ps1
```

---

## 8. Verify End-to-End

### Trigger a manual test run

```powershell
cd setup\publish
.\Run-And-Wait.ps1 -RunbookName "incident-trend-backfill-rb-conferencing"
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
| 1 | Create new Automation Account (system-assigned identity ON) | Azure Portal → Automation Accounts |
| 2 | Create new Key Vault (RBAC) | Azure Portal → Key vaults |
| 3 | Create new storage account | Azure Portal → Storage accounts |
| 4 | Grant managed identity: `Storage Blob Data Contributor` + `Storage Account Contributor` (storage) and `Key Vault Secrets User` (vault) | Azure Portal → IAM on storage + vault |
| 5 | Create 4 blob containers (`templates`, `data`, `logs`, `results`) | `setup\bootstrap\Create-BlobContainers.ps1` |
| 6 | Create `IncidentsCategoryStats` table | `setup\bootstrap\Setup-StatisticsTable.ps1` |
| 7 | Add secrets (`ServiceNowClientSecret`, `AzureOpenAIApiKey`) to Key Vault | Azure Portal → Key vault → Secrets |
| 8 | Create automation variables (same names as PT, no prefix) | Azure Portal → new Automation Account → Variables |
| 9 | Find ServiceNow `business_service` + `service_offering` sys_ids | ServiceNow |
| 10 | Copy 7 template files, rename to `_Conferencing`, edit taxonomy | `templates\*_Conferencing.md` |
| 11 | Upload templates to new storage account | `setup\publish\Upload-TemplateFiles.ps1` |
| 12 | Copy 4 runbooks, update template filenames + sys_ids + Key Vault secret reads | `runbooks\*-conferencing.ps1` |
| 13 | Publish all 4 runbooks to new Automation Account | `setup\publish\Publish-runbook.ps1` |
| 14 | Create + link 4 schedules | Azure Portal → new Automation Account → Schedules |
| 15 | Generate read-only SAS token for new storage | Azure Portal → new storage → Shared access signature |
| 16 | Add new offering to `web/config.json` + redeploy | `setup\publish\Deploy-Web.ps1` |
| 17 | Trigger manual test run + verify rows + check dashboard | `setup\publish\Run-And-Wait.ps1` |

---

*Document last updated: 2026-07-09*
