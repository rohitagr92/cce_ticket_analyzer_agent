# TicketCategorisation — Content Engineering

## PURPOSE

This template defines the allowed category and subcategory taxonomy for **Content Engineering** incidents.
The AI must only output values from the exact bold labels defined here.

## INSTRUCTIONS

- Assign exactly ONE Category and ONE Subcategory per incident.
- Use the exact **bold label** — do not paraphrase, abbreviate, or invent new labels.
- If no category clearly fits, assign **Unknown / Unclear**.

---

## PRODUCTS (CATEGORY) AND SYMPTOMS (SUBCATEGORY)

Each incident must be assigned:

- **Category** = the exact **product name** that has the issue
- **Subcategory** = the exact **symptom label** for what the user experienced

Allowed product categories:

- **Microsoft Teams**
- **SharePoint Online**
- **SharePoint Subscription Edition (SSE)**
- **Viva Engage (Yammer)**
- **Guest Onboarding Tool**
- **Collaboration Workspace Management Tool (WMT)**

---

### **Microsoft Teams**

Microsoft Teams collaboration platform used for team communication, channels, chat, file collaboration, Outlook integration, and related productivity services.

- **Teams Add-in Missing or Not Working** — User cannot see, access, or use the Microsoft Teams add-in from Outlook.
- **Unable to Access Team, Channel** — User cannot access a Team, Channel, Chat, or related collaboration workspace.
- **Unable to Open or Use Teams** — Teams application fails to launch, crashes, hangs, becomes unresponsive, or does not function as expected.
- **File Access or Sharing Issue** — User cannot access, upload, download, synchronize, or share files through Teams.
- **External Collaboration Issue** — User experiences issues collaborating with guest users, external users, or federated organizations.
- **Teams How-To / User Education** — User requires guidance, information, or assistance understanding Teams functionality.
- **Unable to Classify** — Insufficient information exists to confidently determine the symptom category.

### **SharePoint Subscription Edition (SSE)**

On-premises SharePoint platform supporting business applications, document management, workflows, integrations, manufacturing solutions, and platform health monitoring.

- **BigPanda Monitoring Alert** — Monitoring or infrastructure alert generated through BigPanda for SharePoint Subscription Edition.
- **SSE Site Accessibility Issue** — User cannot access SharePoint content, sites, pages, or data due to availability or accessibility issues.
- **SSE Workflow / Automation Issue** — SharePoint workflows, notifications, or automation processes are not functioning as expected.
- **SSE Integration / Application Issue** — Integrated applications, services, connectors, or external systems interacting with SSE are failing.
- **SSE File Access / Sharing Issue** — User cannot access, share, upload, download, or manage SharePoint files and documents.
- **SSE Permission Issue** — User access or permissions prevent successful use of SharePoint resources.
- **SSE How-To / User Education** — User requires guidance or assistance using SharePoint Subscription Edition functionality.
- **Unable to Classify** — Insufficient information exists to confidently determine the symptom category.

### **SharePoint Online**

Enterprise collaboration platform used for document management, content sharing, permissions management, site administration, file storage, external collaboration, and business process automation.

- **Access / Permission Issue** — User cannot access SharePoint sites, libraries, files, folders, lists, or other SharePoint resources.
- **File Access / Sharing Issue** — User cannot access, upload, download, synchronize, recover, or share SharePoint content.
- **External Collaboration Issue** — User experiences issues collaborating with guest users, external users, or external organizations.
- **Site / Content Functionality Issue** — SharePoint pages, web parts, links, content, or site functionality are not working as expected.
- **Site / Workspace Administration Issue** — User requires assistance with site administration, ownership, workspace management, or site lifecycle activities.
- **Customization / Automation / Integration Issue** — SharePoint workflows, integrations, applications, automation, APIs, or custom solutions are not functioning as expected.
- **Policy / Tenant Restriction Issue** — User action is restricted by SharePoint Online, compliance, security, or tenant policy settings.
- **Storage / Quota Issue** — SharePoint storage limits, capacity restrictions, or quota-related conditions prevent normal operation.
- **User Guidance / How-To Issue** — User requires guidance, documentation, or assistance using SharePoint functionality.
- **Unable to Classify** — Insufficient information exists to confidently determine the symptom category.

### **Viva Engage (Yammer)**

Enterprise social networking and community platform used for employee engagement, communities, discussions, announcements, and knowledge sharing.

- **Yammer Access Issue** — User cannot access, sign in to, or use Viva Engage (Yammer).
- **Yammer Community Management Issue** — User experiences issues creating, managing, administering, or maintaining Viva Engage communities.
- **Yammer Membership / Synchronization Issue** — User experiences membership, synchronization, entitlement, or directory-related issues.
- **Yammer Content Interaction Issue** — User cannot post, upload, share, subscribe, receive notifications, or otherwise interact with content.
- **Yammer How-To / User Education** — User requires guidance or assistance using Viva Engage functionality.
- **Unable to Classify** — Insufficient information exists to confidently determine the symptom category.

### **Guest Onboarding Tool**

Tool used to onboard, manage, modify, and remove external guest users for collaboration across Microsoft 365 and Content Engineering platforms.

- **Unable to Onboard Guest User** — User is unable to onboard a new guest user due to validation, provisioning, or onboarding failures.
- **Guest User Management Issue** — User is unable to add, modify, delete, or manage existing guest users.
- **Guest Onboarding Tool Error** — Tool displays errors, unexpected behavior, or fails during guest onboarding activities.
- **Guest Onboarding How-To / User Education** — User requires guidance on onboarding, managing, or removing guest users.
- **Unable to Classify** — Insufficient information exists to confidently determine the symptom category.

### **Collaboration Workspace Management Tool (WMT)**

Tool used by workspace owners and administrators to manage collaboration workspaces, ownership, permissions, lease information, lifecycle actions, and workspace governance.

- **Workspace Ownership or Permission Issue** — Workspace owner, administrator, or permission information is incorrect, missing, or not updating as expected.
- **Workspace Renewal or Lease Issue** — User is unable to renew, extend, review, or manage workspace lease and lifecycle information.
- **Workspace Information or Visibility Issue** — Workspace details, ownership information, permissions, or workspace metadata are missing or not visible.
- **Workspace Management Tool Error** — Tool displays errors, fails to load correctly, or behaves unexpectedly during workspace management activities.
- **Workspace Management How-To / User Education** — User requires guidance on workspace management, ownership, permissions, lease management, or governance functionality.
- **Unable to Classify** — Insufficient information exists to confidently determine the symptom category.

---

## FOR ALL TICKETS — Additional Fields

Confidence Level: [High/Medium/Low]

- High (90%+): Clear root cause with documented resolution and user confirmation
- Medium (70–89%): Clear resolution path but some ambiguity in root cause or evidence
- Low (Under 70%): Multiple possible categories or unclear / undocumented resolution

**CONFIDENCE CALCULATION FRAMEWORK:**

**CONFIDENCE BOOSTERS (+):**

- Application/platform clearly identified and matches category (+25%)
- Specific error message, error code, or permission/role name present (+15%)
- KB number or KB link present (+5% max contribution)
- Agent used Content-Engineering-specific terminology (AEM, Sitecore, DAM, SSO, SPO permissions, publishing pipeline, workflow approval) (+10%)
- Resolution matches category examples exactly (+15%)

**CONFIDENCE REDUCERS (-):**

- Application/platform unclear, ambiguous, or contradictory (-20%)
- Only user symptom language, no agent technical detail or resolution (-10%)
- Multiple possible categories apply with equal evidence (e.g., could be CMS Login Issue or Broken SSO) (-10%)
- Contradictory information between description, work notes, and close notes (-25%)
- Vague or generic language; "issue resolved" with no documented steps (-10%)

**CONFIDENCE CALCULATION:**

Base Confidence (50%) + Total Boosters − Total Reducers = Final Confidence Level

- 90%+ = High Confidence
- 70–89% = Medium Confidence
- Under 70% = Low Confidence
- Guardrail: KB/KA evidence must be treated as supporting context only and can contribute at most +5%. KB/KA presence alone must never determine category confidence.

Reasoning: [Detailed explanation of why this category and subcategory were selected. Reference the platform/tool identified (Teams, SharePoint, AEM, CMS, etc.), specific resolution indicators from the category definition that matched the ticket, key phrases or role/permission names from the work/close notes, and why other categories were excluded.]

Key Evidence: [Multiple relevant quotes from work notes, close notes, or short description that support the classification. Include error messages, role or group names, KB numbers, and resolution steps.]

Resolution Summary: [One sentence describing what actually fixed the issue (or, if unresolved, the disposition such as "User was assigned the required CMS author role in the provisioning system").]

How Do I or Error: [Was the incident a "How Do I" question (user education with no technical failure) or an Error (technical failure, error message, or feature unavailable)?]

KB Provided: [Was a KB attached or provided a link or KB number in work notes/comments? If yes, provide the KB number. Otherwise "No".]

**CRITICAL OUTPUT RULES:**

- For Category, output ONLY the exact category name without any formatting.
- Do NOT include asterisks, bold formatting, or headers.
- Example of CORRECT output:

    Category: SharePoint Online
    Subcategory: Permission Denied
    Confidence Level: High
    Reasoning: The user reported they could not access an SPO site after a site ownership change. The agent confirmed the user's group membership had been removed from the site's Members group during a restructure. The resolution was to re-add the user to the correct SharePoint group. This is a clear permission/access failure matching the Permission Denied subcategory under SharePoint Online. CMS Login / Access Issue is ruled out because the platform is SPO, not a CE-managed CMS.
    Key Evidence: "Getting Access Denied when trying to open the project site." / "User was removed from the Members group during team restructure." / "Re-added user to SharePoint Members group — access restored."
    Resolution Summary: User was re-added to the correct SharePoint Members group and access was restored.
    How Do I or Error: Error
