# ServiceNow Ticket Summary Prompt — Content Engineering

Create an ultra-concise, evidence-based summary for the Content Engineering service offering.

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

## Exact output format

**Problem:** [One sentence describing the core issue.] [Optional second sentence for impact/scope.]  
**Product:** [Readable product name without the " Issues" suffix; keep the exact category in classification data]  
**SubCategory:** [Exact symptom label]  
**Possible Root Cause:** [Exact PRC label]  
**Detailed Root Cause:** [Exact DRC heading]  
**Key Actions:**
- [Most significant action]
- [Critical corrective or administrative step]
- [Final outcome/status]
**Critical Details:**
- [Exact error, permission, identity, lease, provisioning, server-health, client, or add-in finding]
- [Current status or limitation]
**References:**
- Incident: INC########
- KB / Related Records: KB######## / INC######## / PRB######## / CHG######## / None documented
**Work Notes Evidence:**
- "[Exact meaningful quote with personal identifiers removed]"
- "[Exact meaningful quote with personal identifiers removed]"
- "[Exact meaningful quote with personal identifiers removed]"

## Rules
- Maximum two sentences in Problem.
- Maximum three bullets in each section.
- Never assert a cause that is not supported by the cleaned notes or resolution evidence.
- Name only the affected product category, not every platform mentioned.
- For out-of-scope products, set Product to **Excluded**, SubCategory to **Out of Scope**, Possible Root Cause to **Out-of-scope Service Offering**, and state the affected product in the Problem or Critical Details.
- Preserve exact Incident and KB references so the summary can be traced across every Content Engineering Markdown file.

## Planner example
**Product:** Microsoft Planner  
**SubCategory:** Task Management Issues  
**Possible Root Cause:** Task Assignment Failure  
**Detailed Root Cause:** Planner task assignment did not complete
**Detailed Root Cause Explanation:** Work notes confirm that the assignment failed; the agent corrected the task assignment and the user verified it appeared in their plan.
