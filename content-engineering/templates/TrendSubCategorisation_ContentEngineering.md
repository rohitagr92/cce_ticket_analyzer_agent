# Incident Sub-Categorisation for Trend Analysis — Content Engineering

Choose one exact symptom-group label from the selected product. Focus on what the user observed, not the cause.

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

## Canonical subcategories

Select the observed problem, not the suspected root cause. Use **Access & Permission Issues** when a user cannot open, edit, or share a resource; do not infer a missing owner from an access request. Use **Ownership & Administration Issues** only when assigning/recovering an owner or performing an owner/admin workflow is itself the problem. Use **Usage Queries** for feature availability or configuration guidance when no owner/admin workflow failed. For SharePoint, use **File Recovery & Content Issues** when the site or its content expired, was deleted, or needs restoration; prior ownership alone is not an ownership issue.

### SharePoint Online Issues
- **Access & Permission Issues**
- **File Recovery & Content Issues**
- **Provisioning Issues**
- **External Collaboration Issues**
- **Page, List & Web Part Issues**
- **Ownership & Administration Issues**
- **Performance & Availability Issues**
- **Usage Queries**

### SharePoint Subscription Edition (SSE) Issues
- **Access & Permission Issues**
- **Server Health & Capacity Issues**
- **Connectivity & Availability Issues**
- **Files, Lists & Workflow Issues**
- **Ownership & Administration Issues**
- **Performance Issues**
- **Usage Queries**

### Viva Engage (Yammer) Issues
- **Access & Licensing Issues**
- **Community Administration Issues**
- **SharePoint Integration Issues**
- **Feature & Content Issues**
- **Usage Queries**

### Guest Onboarding Tool Issues
- **Guest Registration Issues**
- **Invitation & Acceptance Issues**
- **Guest Identity Issues**
- **Provisioning Issues**
- **Synchronization Issues**
- **Guest Removal Issues**
- **Tool Availability Issues**
- **Usage Queries**

### Collaboration Workspace Management Tool (WMT) Issues
- **Lease Renewal Issues**
- **Ownership & Administration Issues**
- **Workspace Visibility Issues**
- **Banner & Archive Issues**
- **Provisioning Issues**
- **Tool Availability Issues**
- **Usage Queries**

### Microsoft Teams Issues
- **App Sign-In & Launch Issues**
- **Performance & Stability Issues**
- **Channel Access & Membership Issues**
- **Provisioning Issues**
- **Files & Content Issues**
- **External Collaboration Issues**
- **Meeting & Outlook Add-in Issues**
- **Ownership & Administration Issues**
- **Usage Queries**


### Microsoft Planner Issues

- **Access & Permission Issues**
- Unable to access plan
- Missing planner board
- Missing assigned tasks

- **Provisioning Issues**
- Planner not created
- Plan creation failure
- Group provisioning issue

- **Task Management Issues**
- Task assignment failure
- Task update failure
- Bucket issues

- **Synchronization Issues**
- Planner sync delay
- Planner-Web mismatch

- **Usage Queries**
- Planner how-to request

### Excluded
- **Out of Scope**

## Output format
```json
[{"IncidentNumber":"INC########","PrimaryCategory":"<exact product>","SubCategory":"<exact label>","Justification":"<one evidence-based sentence>","References":["INC########","KB########"]}]
```
