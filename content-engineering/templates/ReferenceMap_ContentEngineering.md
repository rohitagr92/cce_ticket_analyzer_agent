# Content Engineering Reference Map

This file is the traceability index connecting the Content Engineering taxonomy to evidence in `ContentEngineering.xlsx`. It does not replace ticket-level validation.

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

## Product reference samples

| Product | Workbook records | Sample incident and KB references |
|---|---:|---|
| SharePoint Online | 451 | INC15811320 (KB10010412), INC15829778, INC15819894, INC15823849, INC15825714, INC15820523, INC15817694, INC15817146 |
| SharePoint Subscription Edition (SSE) | 80 | INC15827829 (KB10012119), INC15808388, INC15820442 (KB10012739), INC15618660 (KB000601769), INC15677298 (KB10065689), INC15674038 (KB000655628), INC15636613 (KB10065689), INC15606013 |
| Viva Engage (Yammer) | 17 | INC15823944, INC15603836 (KB10019598), INC15657364 (KB10019598), INC15678899, INC15784912 (KB10019598), INC15664834 (KB10019598), INC15761473, INC15687539 (KB10016860) |
| Guest Onboarding Tool | 36 | INC15813626 (KB000657957, KB10010434), INC15753689, INC15649030, INC15770100 (KB10013208), INC15649753, INC15709213 (KB10015939), INC15766999, INC15808958 |
| Collaboration Workspace Management Tool (WMT) | 61 | INC15826153 (KB10053018), INC15827861 (KB10012119), INC15816743 (KB10053018), INC15769520 (KB10053018), INC15678841, INC15665524 (KB10053018), INC15700410 (KB10012739), INC15792080 (KB10053018) |
| Microsoft Teams | 367 | INC15827563 (KB000660026), INC15818520, INC15818524, INC15816852 (KB000660026), INC15813489 (KB10012119), INC15818420, INC15827784, INC15812320 |
| Microsoft Planner | Planner plan, group, task, and synchronization incidents | Ticket-specific INC and KB references from ServiceNow |

## Mandatory relationship fields

| Field | Source / Rule |
|---|---|
| Incident Number | `Number` in ContentEngineering.xlsx |
| Product | `Configuration item`, validated against notes and resolution |
| SubCategory | Exact label from TrendSubCategorisation_ContentEngineering.md |
| Possible Root Cause | Exact label from PossibleRootCause_ContentEngineering.md |
| Detailed Root Cause | Exact heading from DetailedRootCause_ContentEngineering.md |
| KB / Related Records | Extract from resolution notes, work notes, comments, and related records |
| Evidence | Cleaned without changing technical meaning |

## Out-of-scope routing map

| Affected product | Category | SubCategory | Possible Root Cause |
|---|---|---|---|
| Microsoft Power Apps | Excluded | Out of Scope | Out-of-scope Service Offering |
| Microsoft Power Automate | Excluded | Out of Scope | Out-of-scope Service Offering |
| Digital Content Management (AEM/CMS) | Excluded | Out of Scope | Out-of-scope Service Offering |
| SharePoint 2019 / SharePoint 2019 EOL | Excluded | Out of Scope | Out-of-scope Service Offering |
| Microsoft InfoPath 2013 / InfoPath EOL | Excluded | Out of Scope | Out-of-scope Service Offering |
