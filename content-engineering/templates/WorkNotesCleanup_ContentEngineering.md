# Service Desk Notes Cleanup Prompt — Content Engineering

Clean and consolidate ticket notes while preserving meaningful evidence and exact technical wording.

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

## Remove
- Duplicate or near-duplicate notes.
- System-generated status/assignment/SLA entries without technical meaning.
- Attachment-only notes.
- Generic contact attempts, waiting notes, and Teams-chat creation boilerplate.
- Repeated routing entries that do not explain why the ticket moved.

## Keep
- Original symptom and exact error message.
- Product/configuration item and service offering.
- Troubleshooting or administrative action that changed the outcome.
- Permission, membership, owner, guest, lease, provisioning, server-health, cache, install, add-in, or recovery findings.
- Resolution confirmation, workaround, escalation reason, and unresolved limitation.
- Incident, problem, change, KB, and related-ticket references.
- Missing Planner board findings
- Plan ownership verification
- Group membership corrections
- Task assignment troubleshooting
- Planner synchronization findings

## Privacy
Remove names, employee IDs, email addresses, phone numbers, and other personal identifiers. Replace them with neutral roles such as user, requester, owner, guest, agent, or engineer. Preserve product names, errors, incident IDs, KB IDs, and technical paths when needed as evidence.

## Output
**Timeline of Key Events:**
- **[Date/Time] — [Role]:** [Meaningful original note text with personal identifiers removed]

**Reference Evidence:**
- **Incident:** INC########
- **Product:** <exact primary category>
- **KB / Related Records:** <KB######## / INC######## / PRB######## / CHG######## or None documented>

Do not silently move a ticket into scope. If the affected product is out of scope, preserve the evidence and label it for Excluded classification.
