# Content Engineering Environment Context

> Use this context to interpret ticket evidence. Do not insert unsupported environmental assumptions into ticket summaries.

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

## Product boundaries and dependencies

### SharePoint Online
- Cloud SharePoint content, sites, permissions, pages, lists, libraries, files, ownership, external sharing, and provisioning.
- Guest access may depend on the Guest Onboarding Tool. Workspace lease and ownership may depend on WMT. Teams channel files may use SharePoint storage, but categorize by the component that actually failed.

### SharePoint Subscription Edition (SSE)
- Separate from SharePoint Online and SharePoint 2019.
- Covers SSE site administration, permissions, files/lists/workflows, server health, disk, CPU, connectivity, and availability.

### Viva Engage (Yammer)
- Covers Viva Engage access, licensing, community membership, community administration, and SharePoint Conversation web-part integration.

### Guest Onboarding Tool
- Covers external-user registration, identity creation, invitation, provisioning, synchronization, and removal.
- If onboarding succeeds but SharePoint or Teams permission still fails, categorize the downstream permission failure under the downstream product.

### Collaboration Workspace Management Tool (WMT)
- Covers workspace lease renewal, owner/admin compliance, visibility, archive state, warning banners, and workspace provisioning.
- If WMT is healthy but SharePoint/Teams access itself is broken, categorize under SharePoint Online or Microsoft Teams.

### Microsoft Teams
- Covers Teams client access and stability, channels, team/channel provisioning, Teams files, guest collaboration, team/channel ownership, deleted team/channel recovery, and Outlook Teams Meeting add-in issues.

### Microsoft Planner

Supports:
- Plans
- Buckets
- Tasks
- Assignments
- Group-backed Planner boards
- Task synchronization

Planner depends on:
- Microsoft 365 Groups
- Teams
- SharePoint Online

Planner board access may be affected by group membership and ownership.

## Evidence priority
1. Configuration item and Service offering.
2. Resolution notes and actions that restored service.
3. Work notes and user confirmation.
4. Error text, KB references, related incidents, problems, or changes.
5. Short description only when stronger evidence is absent.

## Cross-product disambiguation
- Guest cannot be created or invited: **Guest Onboarding Tool**.
- Guest exists but cannot access a SharePoint site/file: **SharePoint Online**.
- Guest exists but cannot access a Team/channel: **Microsoft Teams**.
- Workspace cannot renew or is archived due to lease/owner rules: **WMT**.
- Teams channel file permission fails in the connected library: use **Microsoft Teams** when the user-facing failure is the Teams channel/file experience; use **SharePoint Online** when the investigation confirms a SharePoint site/library permission failure independent of Teams.
- SharePoint server disk/CPU/host alerts: **SSE** only when Configuration item confirms SharePoint Subscription Edition; SharePoint 2019 remains out of scope.
