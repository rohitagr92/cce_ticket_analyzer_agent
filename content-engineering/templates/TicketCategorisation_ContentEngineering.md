# Ticket Categorisation — Content Engineering

Select the category from the product that **owns the failure**, not from a tool merely mentioned in the notes. Output exact labels only.

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

## Required output

```json
{
  "IncidentNumber": "INC########",
  "PrimaryCategory": "<exact product category>",
  "SubCategory": "<exact symptom label>",
  "PossibleRootCause": "<exact canonical root-cause label>",
  "DetailedRootCause": "<exact detailed heading>",
  "DetailedRootCauseExplanation": "<evidence-based description, at most 50 words>",
  "Issue": "<reported issue>",
  "RootCauseNarrative": "<verified cause or evidence gap>",
  "Resolution": "<documented outcome>",
  "Evidence": "<specific work/close-note findings>",
  "HDI": "Yes|No",
  "ExclusionReason": "<required only for Excluded>",
  "References": ["INC########", "KB########"],
  "AIAnalysis": "<2–3 evidence-based sentences>"
}
```

## Exact primary categories
- **SharePoint Online Issues**
- **SharePoint Subscription Edition (SSE) Issues**
- **Viva Engage (Yammer) Issues**
- **Guest Onboarding Tool Issues**
- **Collaboration Workspace Management Tool (WMT) Issues**
- **Microsoft Teams Issues**
- **Microsoft Planner Issues**
- **Excluded**

## Product decision rules
- Use **SharePoint Online Issues** for cloud SharePoint site, file, page, list, permission, provisioning, ownership, and external-collaboration failures.
- Use **SharePoint Subscription Edition (SSE) Issues** for on-premises SSE site, server health, disk, CPU, connectivity, workflow, and administration failures.
- Use **Viva Engage (Yammer) Issues** for community access, licensing, administration, and SharePoint Conversation web-part integration.
- Use **Guest Onboarding Tool Issues** when the failure is in guest registration, invitation, guest identity, provisioning, synchronization, or removal.
- Use **Collaboration Workspace Management Tool (WMT) Issues** for lease renewal, ownership compliance, workspace visibility, archive/banner, or WMT workflow failure.
- Use **Microsoft Teams Issues** for Teams client, sign-in, channels, files, external collaboration, provisioning, Outlook add-in, and ownership issues.
- Use **Microsoft Planner Issues** for plan access, missing boards, provisioning, task assignment, group-backed plans, and synchronization failures.
- When the evidence identifies an out-of-scope product, use **Excluded** even if the ticket was routed to Content Engineering.
- Do not treat “Created by AEM Portal” as the affected product. Determine the actual affected product from Configuration item, Short description, Resolution notes, and Work notes. If the affected product is AEM/CMS itself, exclude it.
