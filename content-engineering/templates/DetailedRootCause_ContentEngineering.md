# Detailed Root Cause Catalog — Content Engineering

The Detailed Root Cause field must contain one exact heading below. The associated Possible Root Cause must come from [PossibleRootCause_ContentEngineering.md](PossibleRootCause_ContentEngineering.md).
Store any longer ticket-specific detail separately as DetailedRootCauseExplanation (1 to 50 words). Derive it from incident evidence; never replace the exact catalog heading or invent a cause.

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

## SharePoint Online Issues

### Permission entry missing or stale

**Possible Root Cause:** Permission Entry Missing  
**When to pick:** Use when access is restored by removing and re-adding the user or a permission entry.

### Rejoined identity is mapped to the previous account

**Possible Root Cause:** Stale Identity / Rejoin Mapping  
**When to pick:** Use when a rehire or new identity cannot use permissions tied to the previous object.

### Permission inheritance is broken

**Possible Root Cause:** Broken Permission Inheritance  
**When to pick:** Use when site access exists but a library, folder, list, or item remains inaccessible.

### File or folder was deleted and restored

**Possible Root Cause:** Deleted Content  
**When to pick:** Use when recovery from a recycle bin or version history resolves the issue.

### Library view filter hid valid content

**Possible Root Cause:** Filtered Library View  
**When to pick:** Use when files exist but the active view or filter prevents visibility.

### SharePoint site provisioning is delayed or stuck

**Possible Root Cause:** Site Provisioning Delay  
**When to pick:** Use when a requested site or collaboration space stays pending or in progress.

### External user is not fully onboarded

**Possible Root Cause:** External Guest Not Provisioned  
**When to pick:** Use when guest onboarding or invitation completion is required before access.

### Site has no valid owner or administrator

**Possible Root Cause:** Site Ownership Missing  
**When to pick:** Use only when notes verify that a valid owner or administrator is missing and ownership transfer, recovery, or assignment is required.

### Page, list, metadata, or web part is misconfigured

**Possible Root Cause:** Page / Web Part Configuration  
**When to pick:** Use for content-page, list, column, metadata, or web-part configuration issues.

### SharePoint Online issue is not evidenced

**Possible Root Cause:** Unknown  
**When to pick:** Use only when notes do not establish a defensible cause.

### External SharePoint site group connection is unavailable

**Possible Root Cause:** SharePoint Online Configuration Request  
**When to pick:** Use when support confirms that connecting the existing external SharePoint site to a new Microsoft 365 Group is unavailable for that site.

### Expired SharePoint site requires a restoration request

**Possible Root Cause:** SharePoint Online Configuration Request  
**When to pick:** Use when an expired site is unavailable and support directs the user to the documented SharePoint site-restoration request process; do not claim restoration was completed.

### Incorrect SharePoint list link used

**Possible Root Cause:** Incorrect SharePoint Link  
**When to pick:** Use when permissions are valid but access succeeds only with the correct site or list URL.

## SharePoint Subscription Edition (SSE) Issues

### SSE access permission is missing or incorrect

**Possible Root Cause:** SSE Permission Misconfiguration  
**When to pick:** Use for site, list, library, or item access corrected by permission repair.

### SSE site ownership is missing or outdated

**Possible Root Cause:** SSE Ownership Missing  
**When to pick:** Use when owner or site administrator changes resolve the issue.

### SSE server disk space is below threshold

**Possible Root Cause:** Low Disk Space  
**When to pick:** Use when monitoring or remediation identifies low disk capacity.

### SSE server CPU is saturated

**Possible Root Cause:** CPU Saturation  
**When to pick:** Use when high CPU or a saturation alert is the confirmed condition.

### SSE host or monitoring endpoint is unavailable

**Possible Root Cause:** Host / Monitoring Unavailable  
**When to pick:** Use for host-down or monitoring-unavailable evidence.

### SSE network connectivity is interrupted

**Possible Root Cause:** Network Connectivity Failure  
**When to pick:** Use when access or health failure is traced to network connectivity.

### SSE server capacity returns a busy response

**Possible Root Cause:** Server Busy / Capacity Constraint  
**When to pick:** Use for server-busy or capacity-related access failures.

### Legacy workflow is incompatible with SSE

**Possible Root Cause:** Workflow Compatibility Issue  
**When to pick:** Use when a workflow regression or version mismatch is confirmed.

### SSE issue is not evidenced

**Possible Root Cause:** Unknown  
**When to pick:** Use only when notes do not establish a defensible cause.

## Viva Engage (Yammer) Issues

### Viva Engage entitlement is missing

**Possible Root Cause:** Viva Engage License Missing  
**When to pick:** Use when the required license or exception is absent.

### Community administrator role is missing

**Possible Root Cause:** Community Admin Role Missing  
**When to pick:** Use when admin rights are requested or granted.

### Community membership is missing

**Possible Root Cause:** Community Membership Missing  
**When to pick:** Use when access depends on community membership.

### Viva Engage access is waiting for synchronization

**Possible Root Cause:** Tenant Synchronization Delay  
**When to pick:** Use when entitlement exists but access has not propagated.

### SharePoint embedding is misconfigured

**Possible Root Cause:** SharePoint Conversation Web Part Configuration  
**When to pick:** Use when the Conversation web part or integration setup is the issue.

### Viva Engage issue is not evidenced

**Possible Root Cause:** Unknown  
**When to pick:** Use only when notes do not establish a defensible cause.

## Guest Onboarding Tool Issues

### Guest registration is incomplete

**Possible Root Cause:** Guest Registration Incomplete  
**When to pick:** Use when required registration data or workflow completion is missing.

### Guest has not accepted the invitation

**Possible Root Cause:** Guest Invitation Not Accepted  
**When to pick:** Use when the invitation must be accepted before collaboration access.

### Duplicate guest objects exist

**Possible Root Cause:** Duplicate Guest Identity  
**When to pick:** Use when multiple guest identities cause access or selection problems.

### Guest identity failed to synchronize

**Possible Root Cause:** Guest Identity Synchronization Failure  
**When to pick:** Use when Entra/Azure AD or downstream synchronization fails.

### Guest removal did not complete

**Possible Root Cause:** Guest Removal Incomplete  
**When to pick:** Use when deprovisioning or removal is incomplete.

### Guest provisioning is delayed

**Possible Root Cause:** Guest Provisioning Delay  
**When to pick:** Use when the workflow succeeded but downstream availability is pending.

### Guest Onboarding Tool is unavailable or errors

**Possible Root Cause:** Guest Onboarding Tool Failure  
**When to pick:** Use for tool submission, design, or availability failures.

### Guest onboarding requires approval and invitation

**Possible Root Cause:** Guest Onboarding Configuration Request  
**When to pick:** Use when support explains the required approval, guest invitation, or expected access-propagation steps; do not imply provisioning completed.

### Guest onboarding cause is not evidenced

**Possible Root Cause:** Unknown  
**When to pick:** Use only when notes do not establish a defensible cause.

## Collaboration Workspace Management Tool (WMT) Issues

### Workspace lease has expired

**Possible Root Cause:** Workspace Lease Expired  
**When to pick:** Use when access, banner, or archive state follows lease expiry.

### Workspace renewal validation failed

**Possible Root Cause:** Renewal Validation Failure  
**When to pick:** Use when a renewal cannot complete despite a valid request.

### Workspace has fewer than the required owners

**Possible Root Cause:** Insufficient Workspace Owners  
**When to pick:** Use when renewal or compliance is blocked by owner count.

### Workspace owner record is incorrect

**Possible Root Cause:** Workspace Ownership Mismatch  
**When to pick:** Use when WMT and SharePoint/Teams owner information is inconsistent.

### Workspace is not visible in WMT

**Possible Root Cause:** Workspace Not Visible  
**When to pick:** Use when the user cannot find an existing workspace in the tool.

### Archive or warning banner state is stale

**Possible Root Cause:** Archive / Banner State Mismatch  
**When to pick:** Use when the lease is renewed but banner/archive status is incorrect.

### Workspace provisioning is delayed

**Possible Root Cause:** Workspace Provisioning Delay  
**When to pick:** Use when the workspace remains pending or unavailable after request.

### WMT is unavailable or errors

**Possible Root Cause:** WMT Tool Failure  
**When to pick:** Use for tool functionality, design, or availability failures.

### WMT cause is not evidenced

**Possible Root Cause:** Unknown  
**When to pick:** Use only when notes do not establish a defensible cause.
## Microsoft Planner Issues

### User is not a member of the Planner plan

Possible Root Cause:
Plan Membership Missing

### Planner plan provisioning failed

Possible Root Cause:
Planner Provisioning Failure

### Microsoft 365 group ownership is missing

Possible Root Cause:
M365 Group Ownership Issue

### Planner task assignment did not complete

Possible Root Cause:
Task Assignment Failure

### Planner synchronization is delayed

Possible Root Cause:
Planner Synchronization Delay

### Planner service is unavailable

**Possible Root Cause:** Planner Service Issue  
**When to pick:** Use only when service-side failure is confirmed in the notes.

### Planner configuration needs to be changed

**Possible Root Cause:** Planner Configuration Request  
**When to pick:** Use when a supported Planner setting or configuration is requested.

### Planner cause is not evidenced

**Possible Root Cause:** Unknown  
**When to pick:** Use only when the notes do not establish a defensible cause.

## Microsoft Teams Issues

### Teams local cache is stale or corrupted

**Possible Root Cause:** Teams Client Cache Corruption  
**When to pick:** Use when reset, cache cleanup, or reinstall resolves launch, status, or messaging instability.

### Teams cannot access the organization

**Possible Root Cause:** Teams Sign-In / Org Permission Failure  
**When to pick:** Use for sign-in failures or required-permission-to-access-org errors.

### Teams client installation is incomplete or corrupt

**Possible Root Cause:** Teams Client Installation Failure  
**When to pick:** Use when reinstall or deployment repair is required.

### Channel membership is missing

**Possible Root Cause:** Channel Membership Missing  
**When to pick:** Use when adding or restoring membership resolves channel access.

### Private channel membership has not synchronized

**Possible Root Cause:** Private Channel Synchronization Delay  
**When to pick:** Use when membership is valid but private-channel access is delayed.

### Team or channel provisioning failed

**Possible Root Cause:** Team / Channel Provisioning Failure  
**When to pick:** Use when creation stays pending, fails, or produces an incomplete workspace.

### Teams file permission is missing

**Possible Root Cause:** Teams File Permission Issue  
**When to pick:** Use when the Teams surface works but the connected file content is inaccessible.

### External guest is not fully provisioned

**Possible Root Cause:** External Guest Not Provisioned  
**When to pick:** Use when onboarding or invitation acceptance is required.

### Approved entitlement overrides manual membership

**Possible Root Cause:** AGS-Managed Membership Override  
**When to pick:** Use when manually added users are removed because membership is managed by an approved entitlement process.

### Teams Meeting add-in is disabled

**Possible Root Cause:** Teams Meeting Add-in Disabled  
**When to pick:** Use when enabling the Outlook add-in restores meeting creation.

### Teams Meeting add-in installation is corrupt

**Possible Root Cause:** Teams Meeting Add-in Corruption  
**When to pick:** Use when Office repair or Teams reinstall restores the add-in.

### Team or channel ownership is missing

**Possible Root Cause:** Team / Channel Ownership Missing  
**When to pick:** Use when owner assignment or orphan recovery is required.

### Team or channel was deleted

**Possible Root Cause:** Deleted Team / Channel  
**When to pick:** Use when restoration of a deleted team, channel, or meeting workspace is requested.

### Teams cause is not evidenced

**Possible Root Cause:** Unknown  
**When to pick:** Use only when notes do not establish a defensible cause.

### Teams notification settings require user configuration

**Possible Root Cause:** Teams Configuration Request  
**When to pick:** Use when the user's notification preferences are changed in Teams settings and no Teams service or client failure is documented.

### Teams channel hierarchy was misunderstood

**Possible Root Cause:** Teams Usage Knowledge Gap  
**When to pick:** Use when work notes confirm a channel was intentionally created under an existing Team and its shared SharePoint site was expected, not an accidental merge.

### AGS-managed membership requires a new Team

**Possible Root Cause:** Teams Configuration Request  
**When to pick:** Use when notes confirm AGS/Azure group integration cannot be retrofitted to an existing Team and support advises creating a new Team with it configured at creation.

## Excluded

### Affected product belongs to another service offering

**Possible Root Cause:** Out-of-scope Service Offering  
**When to pick:** The affected product is Microsoft Power Apps, Microsoft Power Automate, Digital Content Management (AEM/CMS), SharePoint 2019/EOL, InfoPath/EOL, or another product outside the seven-item in-scope list.
