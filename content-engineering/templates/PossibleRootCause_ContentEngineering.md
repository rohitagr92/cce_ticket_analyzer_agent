# Possible Root Cause Reference — Content Engineering

After selecting the product and symptom group, choose exactly one bold label from the matching table. Do not paraphrase or create a new label.

## Scope boundary

**In scope only**
- **SharePoint Online**
- **SharePoint Subscription Edition (SSE)**
- **Viva Engage (Yammer)**
- **Guest Onboarding Tool**
- **Collaboration Workspace Management Tool (WMT)**
- **Microsoft Teams**
- **Microsoft Planner**

**Out of scope**
- **Microsoft Power Apps**
- **Microsoft Power Automate**
- **Digital Content Management (AEM/CMS)**
- **SharePoint 2019 / SharePoint 2019 EOL**
- **Microsoft InfoPath 2013 / InfoPath EOL**

If a ticket belongs to an out-of-scope product, classify it as **Excluded**, set SubCategory to **Out of Scope**, and use **Out-of-scope Service Offering** as the Possible Root Cause. Do not map it to an in-scope product merely because SharePoint, Teams, or a portal is mentioned in the notes.
## Cross-file reference contract

Use the files in this order:
1. [TicketCategorisation_ContentEngineering.md](TicketCategorisation_ContentEngineering.md) selects the product category.
2. [TrendSubCategorisation_ContentEngineering.md](TrendSubCategorisation_ContentEngineering.md) selects the symptom group.
3. [PossibleRootCause_ContentEngineering.md](PossibleRootCause_ContentEngineering.md) selects one canonical root-cause label.
4. [DetailedRootCause_ContentEngineering.md](DetailedRootCause_ContentEngineering.md) selects the exact detailed cause heading.
5. [EnvironmentContext_ContentEngineering.md](EnvironmentContext_ContentEngineering.md) provides technical context only.
6. [WorkNotesCleanup_ContentEngineering.md](WorkNotesCleanup_ContentEngineering.md) prepares evidence without changing its meaning.
7. [WorkNotesSummary_ContentEngineering.md](WorkNotesSummary_ContentEngineering.md) creates the final concise summary.
8. [ReferenceMap_ContentEngineering.md](ReferenceMap_ContentEngineering.md) links products, incidents, KBs, categories, symptoms, and causes.

Every output must preserve this relationship: **Incident Number → Product → SubCategory → Possible Root Cause → Detailed Root Cause → KB / related incident evidence**.

## Canonical root-cause labels

### SharePoint Online

| # | Root Cause Label |
|---:|---|
| 1 | **Permission Entry Missing** |
| 2 | **Stale Identity / Rejoin Mapping** |
| 3 | **Broken Permission Inheritance** |
| 4 | **Deleted Content** |
| 5 | **Filtered Library View** |
| 6 | **Site Provisioning Delay** |
| 7 | **External Guest Not Provisioned** |
| 8 | **Site Ownership Missing** |
| 9 | **Page / Web Part Configuration** |
| 10 | **Storage / Quota Constraint** |
| 11 | **Transient SharePoint Service Issue** |
| 12 | **SharePoint Online Configuration Request** |
| 13 | **Incorrect SharePoint Link** |


### SharePoint Subscription Edition (SSE)

| # | Root Cause Label |
|---:|---|
| 1 | **SSE Permission Misconfiguration** |
| 2 | **SSE Ownership Missing** |
| 3 | **Low Disk Space** |
| 4 | **CPU Saturation** |
| 5 | **Host / Monitoring Unavailable** |
| 6 | **Network Connectivity Failure** |
| 7 | **Server Busy / Capacity Constraint** |
| 8 | **Workflow Compatibility Issue** |
| 9 | **File / List Configuration Issue** |
| 10 | **SSE Configuration Request** |


### Viva Engage (Yammer)

| # | Root Cause Label |
|---:|---|
| 1 | **Viva Engage License Missing** |
| 2 | **Community Admin Role Missing** |
| 3 | **Community Membership Missing** |
| 4 | **Tenant Synchronization Delay** |
| 5 | **SharePoint Conversation Web Part Configuration** |
| 6 | **Viva Engage Service Issue** |
| 7 | **Viva Engage Configuration Request** |


### Guest Onboarding Tool

| # | Root Cause Label |
|---:|---|
| 1 | **Guest Registration Incomplete** |
| 2 | **Guest Invitation Not Accepted** |
| 3 | **Duplicate Guest Identity** |
| 4 | **Guest Identity Synchronization Failure** |
| 5 | **Guest Removal Incomplete** |
| 6 | **Guest Provisioning Delay** |
| 7 | **Guest Onboarding Tool Failure** |
| 8 | **Guest Onboarding Configuration Request** |


### Collaboration Workspace Management Tool (WMT)

| # | Root Cause Label |
|---:|---|
| 1 | **Workspace Lease Expired** |
| 2 | **Renewal Validation Failure** |
| 3 | **Insufficient Workspace Owners** |
| 4 | **Workspace Ownership Mismatch** |
| 5 | **Workspace Not Visible** |
| 6 | **Archive / Banner State Mismatch** |
| 7 | **Workspace Provisioning Delay** |
| 8 | **WMT Tool Failure** |
| 9 | **WMT Configuration Request** |


### Microsoft Teams

| # | Root Cause Label |
|---:|---|
| 1 | **Teams Client Cache Corruption** |
| 2 | **Teams Sign-In / Org Permission Failure** |
| 3 | **Teams Client Installation Failure** |
| 4 | **Teams Client Service Issue** |
| 5 | **Channel Membership Missing** |
| 6 | **Private Channel Synchronization Delay** |
| 7 | **Team / Channel Provisioning Failure** |
| 8 | **Teams File Permission Issue** |
| 9 | **External Guest Not Provisioned** |
| 10 | **AGS-Managed Membership Override** |
| 11 | **Teams Meeting Add-in Disabled** |
| 12 | **Teams Meeting Add-in Corruption** |
| 13 | **Team / Channel Ownership Missing** |
| 14 | **Deleted Team / Channel** |
| 15 | **Teams Configuration Request** |
| 16 | **Teams Usage Knowledge Gap** |



### Microsoft Planner

| # | Root Cause Label |
|---:|---|
| 1 | **Plan Membership Missing** |
| 2 | **Planner Provisioning Failure** |
| 3 | **M365 Group Ownership Issue** |
| 4 | **Task Assignment Failure** |
| 5 | **Planner Synchronization Delay** |
| 6 | **Planner Service Issue** |
| 7 | **Planner Configuration Request** |
| 8 | **Unknown** |


### Excluded

| # | Root Cause Label |
|---:|---|
| 1 | **Out-of-scope Service Offering** |

## Strict output
`Possible Root Cause: <exact bold label>`

Use **Unknown** only when available ticket evidence cannot support a more specific label. For a guidance request, select the most relevant configuration label and set `HDI: Yes`; do not invent “Usage Guidance” as a cause.
Select **Site Ownership Missing** only when notes establish that a valid owner or administrator is absent; referring a requester to a known owner for access approval does not establish missing ownership or a permission defect.
