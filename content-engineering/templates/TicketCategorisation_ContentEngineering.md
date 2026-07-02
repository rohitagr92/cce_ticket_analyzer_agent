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

---

### **Microsoft Teams**
Teams desktop/web client, Outlook add-in, and Outlook-Teams calendar integration.

- **Teams Add-in Missing in Outlook** — Teams COM add-in not loaded or visible in Outlook.
- **Teams Client Not Working** — Messages not sending, app crashing, UI frozen, or notifications broken.
- **Outlook-Teams Calendar Issue** — Teams meeting creation or scheduling broken in Outlook.
- **Teams Chat / Channel Issue** — Chat, channels, or reactions not working as expected.
- **Teams Audio / Video Issue** — Call quality, microphone, camera, or meeting join failure.

### **SharePoint On-Premises**
SharePoint 2019 and SharePoint Subscription Edition farm infrastructure alerts.

- **CPU / Resource Saturation** — Server CPU or memory threshold exceeded.
- **Low Disk Space** — Disk space below safe threshold on SharePoint farm server.
- **Host Shutdown / Restart** — SharePoint host or IIS worker process shut down (graceful or crash).
- **Network Connectivity Issue** — Network problem affecting SharePoint server reachability.
- **Service Performance Degradation** — General slowness, timeouts, or unresponsiveness on the farm.

### **SharePoint Online**
User-facing SharePoint Online (SPO) incidents and service requests.

- **Permission Denied** — User cannot access an SPO site, list, library, or document.
- **Site Administration Request** — Request to rename, change ownership, quota, or settings of an SPO site.
- **File / Item Recovery** — Request to restore deleted files or items from recycle bin.
- **SPO How-To / User Education** — Non-break/fix query about how to use SharePoint Online.

### **Microsoft 365 Apps**
Planner, OneDrive, OneNote, Forms, and other M365 productivity apps.

- **Planner / Project Not Working** — Planner tasks, plans, or assignments not accessible.
- **OneDrive / File Sync Issue** — Files not syncing or accessible via OneDrive.
- **M365 App Functional Issue** — Any other M365 app not working correctly.

### **Content Management System (CMS)**
Adobe Experience Manager, Sitecore, or equivalent CE-managed CMS platform.

- **CMS Login / Access Issue** — User cannot authenticate or lacks permissions to access CMS.
- **CMS Performance Degradation** — Slow load times, timeouts, or UI unresponsiveness in CMS.
- **CMS Data / Asset Corruption** — Incorrect, missing, or duplicate content or assets in CMS.
- **CMS Integration Failure** — Broken integration with DAM, translation system, or other platforms.

### **Content Authoring & Publishing**
Content authoring tools and publishing pipelines managed by Content Engineering.

- **Authoring Tool Failure** — Tool crash, hang, or data loss during content creation.
- **Publishing Pipeline Error** — Failure during build, deploy, or publish to a content target.
- **Template / Style Issue** — Broken template, wrong formatting, or style guide violation.
- **Workflow Approval Blocked** — Content stuck in review or approval queue.

### **Search & Discoverability**
Content search, indexing, and link health for CE-managed platforms.

- **Search Index Outdated** — Recently published content not appearing in search results.
- **Broken Links / 404s** — Content links returning not-found errors.
- **Metadata / Taxonomy Error** — Missing or incorrect tags preventing content findability.

### **Access & Permissions**
Cross-platform access issues for CE-managed tools (CMS, DAM, authoring tools).

- **Permission Denied** — User lacks required role to view or edit content in a CE tool.
- **Onboarding / Role Assignment** — New user not provisioned to the correct group or role.
- **Broken SSO** — Single sign-on failing for a CE-managed authoring or delivery platform.

### **How Do I / User Education**
Non-break/fix queries where the user needs guidance.

- **Teams Usage Query** — How-to question about Microsoft Teams features.
- **SharePoint Usage Query** — How-to question about SharePoint Online features.
- **General M365 Query** — How-to question about any other M365 app.

### **Unknown / Unclear**
Use ONLY when no other product clearly fits after careful review.

- **Insufficient Information** — Ticket lacks enough detail to assign a product and symptom.
- **Out of Scope** — Incident clearly does not belong to Content Engineering's supported products.

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
   
