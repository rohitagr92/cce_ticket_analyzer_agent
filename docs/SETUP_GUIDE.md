# AI Ticket Analyzer â€” Complete Setup Guide

This guide walks through setting up the entire AI Ticket Analyzer system from scratch for any ServiceNow service offering.  
Whether you are onboarding a new team or replicating this for a different business service, follow the steps in order.

---

## Table of Contents

1. [How the System Works](#1-how-the-system-works)
2. [Prerequisites](#2-prerequisites)
3. [Azure Infrastructure Setup](#3-azure-infrastructure-setup)
4. [Azure OpenAI Setup](#4-azure-openai-setup)
5. [ServiceNow API Access](#5-servicenow-api-access)
6. [Code Repository Configuration](#6-code-repository-configuration)
7. [Template Files (AI Prompts)](#7-template-files-ai-prompts)
8. [Bootstrap: Automation Variables](#8-bootstrap-automation-variables)
9. [Bootstrap: Storage Containers & Table](#9-bootstrap-storage-containers--table)
10. [Upload Templates to Blob](#10-upload-templates-to-blob)
11. [Publish Runbooks to Azure Automation](#11-publish-runbooks-to-azure-automation)
12. [Create Daily Schedules](#12-create-daily-schedules)
13. [Deploy the Dashboard (Static Web App)](#13-deploy-the-dashboard-static-web-app)
14. [Verify End-to-End](#14-verify-end-to-end)
15. [Adapting for a Different Service Offering](#15-adapting-for-a-different-service-offering)
16. [Monitoring & Alerting](#16-monitoring--alerting)
17. [Troubleshooting Reference](#17-troubleshooting-reference)

---

## 1. How the System Works

```
ServiceNow  â”€â”€â–º  Azure Automation Runbooks  â”€â”€â–º  Azure OpenAI (GPT)
                         â”‚                              â”‚
                         â–¼                              â”‚
                  Blob Storage                          â”‚
                 (templates, logs, reports)  â—„â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                         â”‚
                         â–¼
                  Table Storage
              (IncidentsCategoryStats)
                         â”‚
                         â–¼
              Azure Static Web App
                 (User Dashboard)
```

**Four runbooks run on schedule every day:**

| Runbook | Schedule (UTC) | What it does |
|---|---|---|
| `incident-trend-backfill-rb-prodtools.ps1` | Daily ~03:00 | Incremental fill â€” processes any incident not yet in the stats table for the past 2 days. Cheap, idempotent |
| `incident-analyzer-rb-prodtools.ps1` | Daily ~06:00 | Pulls resolved incidents from ServiceNow, runs 3-step AI pipeline per ticket (clean â†’ summarize â†’ categorize), merges into weekly HTML report, upserts stats table |
| `incident-reconcile-rb-prodtools.ps1` | Daily ~07:00 | Cross-checks ServiceNow count vs table count per week; triggers backfill if gap exceeds threshold |
| `incident-trend-rb-prodtools.ps1` | Daily ~08:00 (after analyzer) | Loads run artifacts for two rolling 7-day windows, compares category counts, AI sub-categorizes significant increases, generates trend HTML report |

**AI pipeline per ticket (3 LLM calls):**
1. **Clean work notes** â€” strips noise (auto-updates, SCCM logs, redundant lines)
2. **Summarize** â€” produces concise problem + resolution statement
3. **Categorize strictly** â€” outputs `Category / Subcategory / RootCause / Confidence` using only labels defined in the template files

**Storage layout:**

| Container / Table | Purpose |
|---|---|
| `templates/` (blob) | AI prompt template `.md` files â€” the "knowledge base" |
| `data/` (blob) | Raw incident JSON saved by each run |
| `logs/` (blob) | Execution logs per run |
| `results/` (blob) | Generated HTML reports served by the dashboard |
| `IncidentsCategoryStats` (table) | One row per incident: Category, Subcategory, RootCause, AIAnalysis, Date, YearWeek |

---

## 2. Prerequisites

### Local machine
- **PowerShell 7.x** â€” [Install PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell)
- **Azure PowerShell (Az module)** â€” run once:
  ```powershell
  Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
  ```
  Reference: [Install Azure PowerShell](https://learn.microsoft.com/en-us/powershell/azure/install-az-ps)
- **Git** for cloning / version control
- **Az CLI** (optional, useful for Static Web App deployment) â€” [Install Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)

### Azure access
- Azure subscription with **Contributor** role (or Owner)
- Ability to create: Resource Groups, Storage Accounts, Automation Accounts, Static Web Apps
- Access to an **Azure OpenAI** resource (or permission to create one)

### ServiceNow access
- A registered **OAuth2 client application** in the ServiceNow/API gateway with `client_credentials` grant
- The **sys_id** values for:
  - `business_service` (the team's service record)
  - `service_offering` (the specific offering, e.g., "Productivity Tools")
- These are GUIDs found in ServiceNow by navigating to the record and copying the sys_id from the URL

---

## 3. Azure Infrastructure Setup

All resources should live in **one resource group** for easy management.

### 3.1 Create a Resource Group

Azure Portal: **Resource groups â†’ Create**  
Reference: [Manage resource groups](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-portal)

```
Name:     OPSW-Ticket-Analyzer          (or: <Team>-Ticket-Analyzer)
Region:   East US  (or your preferred region)
```

### 3.2 Create a Storage Account

Azure Portal: **Storage accounts â†’ Create**  
Reference: [Create a storage account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create)

```
Resource Group:    <your resource group>
Name:              opswprodtoolsblob      (globally unique, lowercase, no dashes)
Region:            Same as resource group
Performance:       Standard
Redundancy:        LRS  (locally redundant â€” sufficient for reports/logs)
```

> Keep the storage account name â€” it is used throughout all scripts.

### 3.3 Create an Automation Account

Azure Portal: **Automation accounts â†’ Create**  
Reference: [Create an Automation account](https://learn.microsoft.com/en-us/azure/automation/automation-create-standalone-account)

```
Resource Group:    <your resource group>
Name:              OPSW-ProductivityTools-account
Region:            Same as resource group
System-assigned managed identity: ENABLED  â† critical
```

After creation, go to **Identity â†’ System assigned** and confirm **Status = On**.  
Copy the **Object (principal) ID** â€” you need it in step 3.4.

### 3.4 Grant the Automation Account Access to Storage

The automation account's managed identity must be able to read/write the storage account.

Azure Portal: **Storage account â†’ Access Control (IAM) â†’ Add role assignment**  
Reference: [Assign Azure roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-portal)

Add these two roles, assigning them to the **Managed Identity** of the Automation Account:
- `Storage Blob Data Contributor`
- `Storage Account Contributor` (needed for `Get-AzStorageAccountKey`)

Repeat for the Resource Group level if you prefer broader access:
```
Role: Contributor
Assign access to: Managed identity
Select: OPSW-ProductivityTools-account
```

### 3.5 Import Required PowerShell Modules into Automation Account

Azure Portal: **Automation account â†’ Modules â†’ Browse Gallery**  
Reference: [Manage modules in Azure Automation](https://learn.microsoft.com/en-us/azure/automation/shared-resources/modules)

Import these modules for **PowerShell 5.1 runtime**:

| Module | Minimum Version | Why |
|---|---|---|
| `Az.Accounts` | 2.x | Azure authentication |
| `Az.Storage` | 6.x | Blob and Table storage |
| `Az.Automation` | 1.x | Job management |
| `AzTable` | 2.x | `Get-AzTableRow` for reading table partitions |

> **Important:** Import `Az.Accounts` first. Each subsequent module depends on it.  
> Wait for each import to show **Succeeded** before importing the next.

---

## 4. Azure OpenAI Setup

Reference: [Create and deploy Azure OpenAI resources](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/create-resource)

### 4.1 Create Azure OpenAI Resource

Azure Portal: **Azure OpenAI â†’ Create**

```
Resource Group:    <your resource group>
Name:              opsw-ticket-analyzer-foundary   (or any name)
Region:            East US or Sweden Central (model availability varies)
Pricing tier:      Standard S0
```

### 4.2 Deploy a Model

Inside your OpenAI resource: **Model deployments â†’ Deploy model**

```
Model:             gpt-4o-mini  (recommended: low cost, sufficient reasoning)
Deployment name:   gpt-5.4-mini  (this is what goes in AzureOpenAIDeployment variable)
Version:           Latest available
```

Reference: [Azure OpenAI model availability](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/models)

### 4.3 Collect Endpoint & Key

Go to **Keys and Endpoint**:
- **Endpoint** (e.g., `https://opsw-ticket-analyzer-foundary.cognitiveservices.azure.com`)
- **Key 1** â€” copy for the `AzureOpenAIApiKey` automation variable

---

## 5. ServiceNow API Access

This system uses the Intel **apis.intel.com** gateway with OAuth2 client credentials.  
For a different environment, adapt the token URL and base URL accordingly.

### What you need

| Value | Where to find it |
|---|---|
| `client_id` | Registered app in the API portal |
| `client_secret` | Same â€” treat as a secret |
| `scope` | Format: `api://<app-id>/.default` |
| `token_url` | E.g., `https://apis.intel.com/v1/auth/token` |
| `business_service sys_id` | ServiceNow â†’ Business Services â†’ open record â†’ URL bar shows the sys_id |
| `service_offering sys_id` | ServiceNow â†’ Service Offerings â†’ open record â†’ URL bar sys_id |

### Verify the ServiceNow query

The runbook queries with this filter (adjust field names for your environment):

```
sysparm_query=
  business_service=<business_service_sys_id>
  ^service_offering=<service_offering_sys_id>
  ^stateIN6,7               â† 6=Resolved, 7=Closed
  ^ORDERBYDESCresolved_at   â† REQUIRED â€” without this, sysparm_limit returns random old tickets
```

Test the query in Postman or your browser before wiring it into the runbook.  
Reference: [ServiceNow Table API](https://developer.servicenow.com/dev.do#!/reference/api/sandiego/rest/c_TableAPI)

---

## 6. Code Repository Configuration

### 6.1 Clone the repository

```powershell
git clone <repo-url>
cd CCE_ticket_analyzer_agent
```

### 6.2 Create your local config files

Copy the sample and fill in your values:

```powershell
Copy-Item config\LocalConfig-ProductivityTools.psd1 config\LocalConfig-<YourTeam>.psd1
Copy-Item config\LocalSecrets-ProductivityTools.psd1 config\LocalSecrets-<YourTeam>.psd1
```

Edit `LocalConfig-<YourTeam>.psd1`:

```powershell
@{
    # Azure Storage
    PSD_AI_Automations_StorageAccountName          = "<your-storage-account>"
    PSD_AI_Automations_PromptTemplateContainerName = "templates"
    PSD_AI_Automations_ResourceGroupName           = "<your-resource-group>"
    Incidents_analyzer_SubscriptionId              = "<your-subscription-id>"

    # ServiceNow
    ServiceNowIncidentsClientID     = "<client-id>"
    ServiceNowIncidentsClientSecret = $null     # put in LocalSecrets file
    ServiceNowIncidentsScope        = "api://<app-id>/.default"
    TokenUrl                        = "https://apis.intel.com/v1/auth/token"
    ServiceNowIncidentsURL          = "https://apis.intel.com/itsm/api/now/table/incident?sysparm_query=business_service=<bs_sys_id>^service_offering=<so_sys_id>^stateIN6,7^ORDERBYDESCresolved_at&sysparm_display_value=true&sysparm_limit=1000"

    # Azure OpenAI
    AzureOpenAIBaseUrl    = "https://<your-resource>.cognitiveservices.azure.com"
    AzureOpenAIModel      = "gpt-4o-mini"
    AzureOpenAIDeployment = "<your-deployment-name>"
    AzureOpenAIApiVersion = "2025-04-01-preview"
    AzureOpenAIApiKey     = $null     # put in LocalSecrets file

    # Processing
    DailyLookbackHours = 26
}
```

Edit `LocalSecrets-<YourTeam>.psd1` (this file is git-ignored):
```powershell
@{
    ServiceNowIncidentsClientSecret = "<your-secret>"
    AzureOpenAIApiKey               = "<your-api-key>"
}
```

---

## 7. Template Files (AI Prompts)

Templates are the "brain" of the system â€” they define what categories, subcategories, and root causes the AI can output. They live in `templates/` locally and are uploaded to the `templates/` blob container.

| File | Purpose |
|---|---|
| `TicketCategorisation_<Team>.md` | Master list of categories and subcategory labels. AI must pick only from these labels. |
| `EnvironmentContext_<Team>.md` | Background on the team, technologies, and environment for the AI to understand context. |
| `TrendSubCategorisation_<Team>.md` | Detailed sub-symptom labels used in trend analysis. Must use **bold** label format. |
| `PossibleRootCause_<Team>.md` | Possible root cause catalog. Must use **bold** label format. |
| `DetailedRootCause_<Team>.md` | Extended root cause descriptions for the detailed root cause report. |
| `WorkNotesCleanup_<Team>.md` | Instructions for stripping noise from ServiceNow work notes before summarization. |
| `WorkNotesSummary_<Team>.md` | Instructions for summarizing cleaned work notes into a concise problem/resolution. |

### Rules for writing template files

1. **Category and subcategory labels must be bold** â€” the AI is instructed to output the exact label. E.g., `**OneDrive Sync Issue**`
2. **No free-form descriptions in the label list** â€” labels are single-line, bolded, specific
3. Keep the `TicketCategorisation` file as the single source of truth for what categories exist
4. The `TrendSubCategorisation` and `PossibleRootCause` files should have headings per main category, with bold labels beneath each

For new teams: copy the existing `ProductivityTools` templates as a starting point, then replace the category taxonomy with your team's incident types.

---

## 8. Bootstrap: Automation Variables

The runbooks read all secrets and config from **Azure Automation Variables** (not hardcoded). Set these up once.

### Run the setup script

```powershell
cd setup\bootstrap
.\Setup-AzureAutomationVariables.ps1
```

The script is interactive â€” it will prompt for each value and create variables in your Automation Account.

### Variables created (13 required)

| Variable Name | Encrypted | Value |
|---|---|---|
| `Incidents_analyzer_StorageAccountName` | No | Storage account name |
| `Incidents_analyzer_ResourceGroupName` | No | Resource group name |
| `Incidents_analyzer_PromptTemplateContainerName` | No | `templates` |
| `Incidents_analyzer_SubscriptionId` | No | Azure subscription GUID |
| `Incidents_analyzer_DataContainerName` | No | `data` |
| `Incidents_analyzer_ResultsContainerName` | No | `results` |
| `ServiceNowIncidentsClientID` | No | OAuth2 client ID |
| `ServiceNowIncidentsClientSecret` | **Yes** | OAuth2 client secret |
| `ServiceNowIncidentsScope` | No | OAuth2 scope |
| `TokenUrl` | No | Token endpoint URL |
| `AzureOpenAIBaseUrl` | No | OpenAI resource endpoint |
| `AzureOpenAIDeployment` | No | Deployment name |
| `AzureOpenAIApiKey` | **Yes** | OpenAI API key |
| `AzureOpenAIApiVersion` | No | API version string |

### Optional variables (backfill runbook â€” have defaults)

| Variable Name | Default | Override to |
|---|---|---|
| `PT_BusinessServiceId` | *(hardcoded PT value)* | Your business_service sys_id |
| `PT_ServiceOfferingId` | *(hardcoded PT value)* | Your service_offering sys_id |
| `PT_TrendTableName` | `IncidentsCategoryStats` | Different table name if needed |
| `PT_TrendLookbackDays` | `2` | How many days back to check |

To set an optional variable manually:  
Azure Portal â†’ **Automation account â†’ Variables â†’ Add variable**  
Reference: [Manage variables in Azure Automation](https://learn.microsoft.com/en-us/azure/automation/shared-resources/variables)

---

## 9. Bootstrap: Storage Containers & Table

### 9.1 Create blob containers

```powershell
cd setup\bootstrap
.\Create-BlobContainers.ps1
```

This creates 4 containers in your storage account:

| Container | Access | Contents |
|---|---|---|
| `templates` | Private | AI prompt template `.md` files |
| `data` | Private | Raw incident JSON per run |
| `logs` | Private | Execution log files |
| `results` | Private | HTML report files served to dashboard |

Reference: [Create a container in Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-container-create)

### 9.2 Create the Azure Table

```powershell
.\Setup-StatisticsTable.ps1 `
  -StorageAccountName "opswprodtoolsblob" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -TableName "IncidentsCategoryStats"
```

This creates the `IncidentsCategoryStats` table with the schema:

| Column | Type | Example |
|---|---|---|
| `PartitionKey` | String | `2026-W26` (ISO year-week) |
| `RowKey` | String | `INC1234567` |
| `Category` | String | `Application Issue` |
| `Subcategory` | String | `**OneDrive Sync Issue**` |
| `RootCause` | String | `**Corrupted Cache**` |
| `AIAnalysis` | String | Plain text AI explanation |
| `Confidence` | String | `High` / `Medium` / `Low` |
| `Date` | String | `2026-06-28` |
| `YearWeek` | String | `2026-W26` |
| `Year` | Int | `2026` |
| `WeekNumber` | Int | `26` |
| `ReportBlobName` | String | Run artifact filename |

Reference: [Azure Table storage overview](https://learn.microsoft.com/en-us/azure/storage/tables/table-storage-overview)

---

## 10. Upload Templates to Blob

After writing your template files locally in `templates/`, upload them:

```powershell
cd setup\publish
.\Upload-TemplateFiles.ps1 `
  -StorageAccountName "opswprodtoolsblob" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -LocalTemplatesFolder "..\..\templates" `
  -ContainerName "templates"
```

Verify in Azure Portal: **Storage account â†’ Containers â†’ templates** â€” all 7 `.md` files should appear.

> **Tip:** Every time you update a template, re-run this script. The runbooks always fetch the latest version from blob at job start, so no republishing of runbooks is needed.

---

## 11. Publish Runbooks to Azure Automation

### 11.1 Publish the main analyzer runbook

```powershell
cd setup\publish
.\Publish-runbook.ps1 `
  -SourceFile "..\..\runbooks\incident-analyzer-rb-prodtools.ps1" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -AutomationAccountName "OPSW-ProductivityTools-account"
```

### 11.2 Publish the backfill runbook

```powershell
.\Publish-TrendBackfillRunbook.ps1
```

This also creates and links the `IncidentTrendBackfill-Daily-0300UTC` schedule automatically.

### 11.3 Publish the reconcile runbook

```powershell
.\Publish-runbook.ps1 `
  -SourceFile "..\..\runbooks\incident-reconcile-rb-prodtools.ps1" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -AutomationAccountName "OPSW-ProductivityTools-account"
```

### 11.4 Publish the trend runbook

```powershell
.\Publish-runbook.ps1 `
  -SourceFile "..\..\runbooks\incident-trend-rb-prodtools.ps1" `
  -ResourceGroupName "OPSW-Ticket-Analyzer" `
  -AutomationAccountName "OPSW-ProductivityTools-account"
```

After publishing, verify in Azure Portal:  
**Automation account â†’ Runbooks** â€” each runbook should show **Published** status.  
Reference: [Manage runbooks in Azure Automation](https://learn.microsoft.com/en-us/azure/automation/manage-runbooks)

---

## 12. Create Daily Schedules

Each runbook needs a schedule. The backfill runbook's schedule is created by `Publish-TrendBackfillRunbook.ps1`. For the others:

Azure Portal: **Automation account â†’ Schedules â†’ Add a schedule**  
Reference: [Schedule a runbook in Azure Automation](https://learn.microsoft.com/en-us/azure/automation/shared-resources/schedules)

| Schedule Name | Frequency | Time (UTC) | Runbook |
|---|---|---|---|
| `IncidentTrendBackfill-Daily-0300UTC` | Daily | 03:00 | `incident-trend-backfill-rb-prodtools` |
| `IncidentAnalyzer-Daily-0600UTC` | Daily | 06:00 | `incident-analyzer-rb-prodtools` |
| `IncidentReconcile-Daily-0700UTC` | Daily | 07:00 | `incident-reconcile-rb-prodtools` |
| `IncidentTrend-Daily-0800UTC` | Daily | 08:00 | `incident-trend-rb-prodtools` |

**Link a schedule to a runbook:**  
Runbook â†’ **Schedules â†’ Add a schedule â†’ Link a schedule â†’ select existing**

---

## 13. Deploy the Dashboard (Static Web App)

The dashboard is a single-page HTML app that reads directly from Table Storage and Blob Storage using a SAS token.

### 13.1 Create the Static Web App

Azure Portal: **Static Web Apps â†’ Create**  
Reference: [Azure Static Web Apps quickstart](https://learn.microsoft.com/en-us/azure/static-web-apps/getting-started)

```
Resource Group:   <your resource group>
Name:             opsw-prodtools-reports
Plan:             Free
Source:           Other (manual deploy â€” no GitHub Actions needed)
```

### 13.2 Configure the dashboard

Edit `web/config.json` with your storage details and SAS token:

```json
{
  "storageAccount": "opswprodtoolsblob",
  "tableEndpoint": "https://opswprodtoolsblob.table.core.windows.net",
  "blobEndpoint":  "https://opswprodtoolsblob.blob.core.windows.net",
  "sasToken": "?sv=2024-...&sig=...",
  "tableName": "IncidentsCategoryStats",
  "resultsContainer": "results"
}
```

Generate a SAS token in Azure Portal:  
**Storage account â†’ Shared access signature**  
- Allowed services: Blob + Table  
- Allowed resource types: Container + Object  
- Permissions: Read + List  
- Expiry: Set 1â€“2 years ahead  
Reference: [Create a service SAS](https://learn.microsoft.com/en-us/azure/storage/common/storage-sas-overview)

### 13.3 Deploy the web files

```powershell
cd setup\publish
.\Deploy-Web.ps1
```

Or use Az CLI:
```bash
az staticwebapp deploy --app-name opsw-prodtools-reports --source web/
```

### 13.4 Configure authentication

Azure Portal: **Static Web App â†’ Authentication â†’ Add provider â†’ Azure Active Directory**  
Reference: [Authentication in Static Web Apps](https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-authorization)

The `web/staticwebapp.config.json` already sets routes requiring `authenticated` role â€” no additional code needed.

---

## 14. Verify End-to-End

### 14.1 Trigger a manual test run

```powershell
cd setup\publish
.\Run-And-Wait.ps1 -RunbookName "incident-trend-backfill-rb-prodtools"
```

Or in Azure Portal: **Runbook â†’ Start â†’ OK**

### 14.2 Check job output

Azure Portal: **Automation account â†’ Jobs â†’ select latest job â†’ Output**

Expected successful output:
```
[HH:MM:SS] Loading Automation variables...
[HH:MM:SS] Loading prompt templates from container 'templates'...
[HH:MM:SS] Day 1/2 - 2026-06-29  Fetched N incidents.
...
TOTAL  fetched=X  saved=Y  skipped=Z  errors=0
Final status: Completed
```

### 14.3 Verify table rows

```powershell
cd tools
.\verify_ww26_compliance.ps1 -YearWeek '2026-W27'
```

### 14.4 Check the dashboard

Open your Static Web App URL in a browser â€” the current week's categorized tickets should appear in the **Trends** and **Ops Report** tabs.

---

## 15. Onboarding a New Service Offering

For a complete step-by-step guide to onboarding a new team from scratch â€” including what Azure infrastructure to create, what to reuse, automation variable setup, template authoring, runbook copying, schedules, and dashboard wiring â€” see the dedicated guide:

**[docs/NEW_SERVICE_ONBOARDING.md](NEW_SERVICE_ONBOARDING.md)**

---

## 16. Monitoring & Alerting

### Azure Monitor Alerts

Reference: [Create metric alerts in Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-metric-alert-rule)

Create these alerts on the Automation Account:

| Alert | Metric | Condition | Severity |
|---|---|---|---|
| Runbook job failed | `TotalJob` (status=Failed) | > 0 | Sev 2 |
| Runbook not running | `TotalJob` (24h count) | < 1 | Sev 3 |

### Log Analytics (optional)

Send Automation job logs to a Log Analytics workspace for KQL queries:  
**Automation account â†’ Diagnostic settings â†’ Add diagnostic setting â†’ send to Log Analytics**

Sample KQL â€” jobs failed in last 24h:
```kql
AzureDiagnostics
| where ResourceType == "AUTOMATIONACCOUNTS"
| where ResultType == "Failed"
| where TimeGenerated > ago(24h)
| project TimeGenerated, RunbookName_s, ResultDescription
```

See [monitoring/alert_kql_and_instructions.txt](../monitoring/alert_kql_and_instructions.txt) for pre-written KQL queries.

### Health check

Run this anytime to see how many rows are in each week's partition:
```powershell
.\tools\list_table_partitions.ps1
```

---

## 17. Troubleshooting Reference

| Symptom | Likely cause | Fix |
|---|---|---|
| Job fails: `Get-AutomationVariable not found` | Module missing from Automation Account | Import `Az.Automation` for PS 5.1 runtime (step 3.5) |
| Job fails: `401 Unauthorized` on ServiceNow | Client secret expired or wrong | Rotate secret, update `ServiceNowIncidentsClientSecret` variable |
| Job fails: `Could not find blob 'TicketCategorisation_...'` | Template not uploaded | Run `Upload-TemplateFiles.ps1` |
| Job completes but `saved=0` always | Incidents already in table (OK) | Normal if backfill ran previously for that date range |
| Dashboard shows no data | Wrong SAS token or expired | Regenerate SAS, update `web/config.json`, redeploy |
| Table rows have `Unknown` category | AI returned free-form instead of label | Check template files â€” ensure labels are **bold** format |
| `AzTable module 401` in PS 7.2 | Module not in PS 7.2 gallery | Use PS 5.1 runtime for runbooks, or install AzTable via Portal â†’ Modules |
| Weekly report not generated | Main analyzer runbook not scheduled | Verify `incident-analyzer-rb-prodtools` has an active schedule linked |

### Key script reference

| Task | Script |
|---|---|
| Check how many rows in a week | `tools\count_table_week.ps1 -YearWeek '2026-W27'` |
| Check all partitions in table | `tools\list_table_partitions.ps1` |
| Check compliance of a week's rows | `tools\verify_ww26_compliance.ps1 -YearWeek '2026-W27'` |
| Look up a specific incident | `tools\find_incidents_in_table.ps1 -IncidentNumber 'INC1234567'` |
| Print all fields for one row | `tools\inspect_one_entity.ps1` |
| List report blobs for a week | `tools\list_week_blobs.ps1 -YearWeek '2026-W27'` |
| Re-run AI analysis for a week | `tools\fix_ai_analysis_by_week.ps1 -YearWeek '2026-W27'` |

---

*Document last updated: 2026-07-01*
