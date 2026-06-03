## CRITICAL INSTRUCTIONS – READ FIRST

You are analyzing IT service desk tickets for the **Productivity Tools** service offering. Your goal is to determine the correct category **based on the root cause of the issue**, *not* merely the initial symptoms or resolution steps. All classification decisions should be driven by what ultimately **caused** the incident.

Productivity Tools tickets are about the following in-scope products only: **Microsoft 365 Apps for Enterprise** (Word, Excel, PowerPoint, Outlook client install/profile, OneNote, Access, Publisher), **Microsoft 365 Copilot**, **Microsoft OneDrive for Business**, **Microsoft SharePoint Online**, **Microsoft OneNote**, **Microsoft Loop**, **Microsoft Forms**, **Microsoft Visio Professional Client**, **Microsoft Project (Desktop / Project for the web)**, **Microsoft 365 Groups / Planner / To Do**, **Google Workspace** (Docs, Sheets, Slides, Drive, Gemini), **Smartsheet**, **Shared File Service (Share Drives)**, and **Canva**. They are **not** about device hardware, OS rebuilds, network/VPN, PC deployment, Outlook/Exchange mail-flow, Teams calling/meetings, or GitHub/developer-tool licensing - those belong to other service offerings.

***

### **Application & Scope Context**

- **Always identify the affected application/area first** - the category name is anchored on the in-scope product.
    - *Microsoft Excel / Word / PowerPoint / OneNote* - app-specific category.
    - *Microsoft 365 Apps for Enterprise* - generic Office suite issues (install, update, activation, license) where the failure is not isolated to a single Office app.
    - *Microsoft OneDrive* - OneDrive client, sync, file availability.
    - *Microsoft 365 Copilot* - Copilot in any Office app, Copilot licensing.
    - *Microsoft Forms* - Forms creation/access, Teams polls.
    - *Microsoft Visio / Project / Loop* - app-specific.
    - *Microsoft 365 Planner / To Do* - Group membership, Planner plan/board, To Do list issues.
    - *Smartsheet* - access issue, Features related.
    - *Shared File Service (Share Drives)* - mapped network drives, SMB, DFS shared drive paths.
    - *Google Workspace* - Google Drive / Docs / Gemini.
    - *Canva* - Canva access, license, sharing, template issues.
    - **Never assign a category that doesn't fit one of the in-scope products.**
    - *Example*: "Notebook missing after new PC" -> Microsoft OneNote Issues, not Microsoft OneDrive Issues, unless the root cause is the OneDrive client.
- **Check Service Offering field:** Should be "Productivity Tools". If clearly outside that scope (cellular, printer supplies, PC hardware, OS rebuild, mailbox, Teams calling, GitHub/developer tools, Visual Studio, Outlook Feature issue), use **Excluded**.

***

### **How to Categorize**

- **Classify by Product, not symptoms.**
- **Prioritize evidence in this order:**
1. *Based on the Products* — Which Product was determined to be the underlying issue (TOP PRIORITY).


***

### **Special Rules**

**Single Office App vs Microsoft 365 Apps for Enterprise**
- If the failure is isolated to **one** app (Excel only / Word only / PowerPoint only / OneNote only) → use that **app-specific category** (e.g., Microsoft Excel Issues).
- If the failure affects **multiple Office apps** at once (install, update, activation, license tier) → use **Microsoft 365 Apps for Enterprise**.
- License-tier restrictions (e.g., F3 blocking Excel/Word/PowerPoint/OneNote/Outlook desktop) → **Microsoft 365 Apps for Enterprise** even if the user mentions only one app, because the cause is suite-wide.
- App-specific license/activation issue (e.g., Visio license expired) → that app's category.

**Microsoft 365 Copilot — Always Use the Copilot Category**
- All Copilot scenarios (license missing, blackout / entitlement hidden in AGS, Copilot not visible in Excel/Word/PowerPoint, Copilot partially enabled, ChunkLoadError) → **Microsoft 365 Copilot**.
- Do NOT split into "Excel Issues" or "Teams Issues" if the root cause is Copilot — Copilot wins.

**Microsoft 365 F3 vs E3 License Restrictions**
- F3 license blocking desktop Office apps or Teams Facilitator → **Microsoft 365 Apps for Enterprise** (sub-symptom: license activation issue).
- Resolution is typically guidance to request **"MSOL License - F3 License Exception"** via AGS with manager approval.

**Office Activation / Sign-in Loop**
- License is present, but user gets repeated sign-in prompts, identity/profile corruption, "Work or school account" issues → **Microsoft 365 Apps for Enterprise** (sub-symptom: license activation issue).

**Device Change / New Laptop**
- **OneNote notebooks missing after new laptop** because notebook was not added/opened in app → **Microsoft OneNote** (sub-symptom: data not available after device change).
- **OneDrive files not syncing on new laptop** → **Microsoft OneDrive**.
- **Mapped network drives not reconnecting after PC refresh** → **Shared File Service (Share Drives)**.

**Shared File / SharePoint Permissions**
- "Access denied", "You need permission to access this item" on a shared SharePoint/OneDrive file → **Micrsoft OneDrive**.
- Resolution typically involves the **owner** removing and re-adding the user.
- If the user is rejoined and issue with OneDrive → prefer **Micrsoft OneDrive**.

**OneDrive File Availability Setting**
- "Error 0x80070032: The request is not supported" while copying OneDrive file to Samba / external location, "Always keep on this device" toggle involved → **Microsoft OneDrive** (sub-symptom: drive sync failure / file availability).

***

### **When to Use "Excluded" Category**

The **Excluded** category is for tickets that fall outside the scope of Productivity Tools support. **ONLY** the following qualify:

**1. Out of Scope Service Offerings:**
- **Cellular / Mobile device service** — SIM, PUK, cellular plan issues.
- **Imaging Vendor Managed HW** — printer paper, toner, cartridges.
- **PC Hardware / OS rebuild / Network-VPN** — desktop/laptop support, not Productivity Tools.
- **Outlook / Exchange mailbox issues** — Messaging service offering (unless the issue is specifically a Productivity Tools add-in inside Outlook).
- **Github** 
- **Microsoft Visual Studio issue**
- **Teams Facilitator issue**  
- **Sharepoint Online issue** 

**CRITICAL — DO NOT use Excluded for these scenarios:**
- ❌ Copilot licensing/access requests → **Microsoft 365 Copilot**
- ❌ F3 license blocking Office desktop → **Microsoft 365 Apps for Enterprise**
- ❌ Tickets escalated to L1.5 / engineering / Microsoft → If a resolution or root cause is documented, categorize accordingly.

***

### **Categories & When to Use Them**

Each category lists the **sub-symptoms** (the recurring failure modes seen in tickets) that map into it. The Primary Category output must be only the bold category name — the sub-symptom list is for matching evidence and for the separate Sub-symptom output field.

***

**Microsoft Excel Issues**

- *Sub-symptoms:*
    - File not opening (blank/grey screen, embedded file fails to open)
    - Excel freezing / hanging (slowness, unresponsive UI)
    - File save failure
    - Large file performance issue
    - Add-in failure (Excel-specific add-in not loading)
    - Data refresh issue (Power Query / Power BI data source, Edit Permissions dialog blank)
    - Excel license issue (Excel-only license/activation problem; if suite-wide → M365 Apps)
- *Common resolutions:* End EXCEL.EXE in Task Manager, clear `%localappdata%\Microsoft\Office\16.0\OfficeFileCache`, open Excel in safe mode (`excel /safe`), quick / online repair, re-enable / update add-in.
- *Exclude:* Permission error on the workbook (use Microsoft OneDrive Issues). Copilot in Excel (use Microsoft 365 Copilot). Multi-app failure (use M365 Apps).

***

**Microsoft Word Issues**

- *Sub-symptoms:*
    - Document not opening
    - Word crashing / freezing
    - Formatting issue
    - File corruption issue
    - Add-in failure (e.g., IVO / CLM add-in missing in Word, add-in launch failure)
- *Common resolutions:* Sign out and back in to Word, update / re-entitle the add-in via AGS, repair Office, open document from correct location, recover from auto-save.
- *Exclude:* Permission error on the document (Microsoft OneDrive Issues). Copilot in Word (Microsoft 365 Copilot). Multi-app failure (M365 Apps).

***

**Microsoft PowerPoint Issues**

- *Sub-symptoms:*
    - Presentation not opening (path/location issue)
    - PowerPoint crashing / freezing
    - Formatting issue
    - File corruption issue
    - License activation issue (PowerPoint-only; if suite-wide → M365 Apps)
- *Common resolutions:* Validate file path, open from correct location, quick repair, end POWERPNT.EXE in Task Manager.
- *Exclude:* "You are not signed in to Office with an account that has permission to open this presentation" → Microsoft OneDrive Issues. Copilot in PowerPoint → Microsoft 365 Copilot.

***

**Microsoft OneNote Issues**

- *Sub-symptoms:*
    - Notebook sync failure (between web and app, between devices)
    - Missing notes issue (pages / subpages not present after sync)
    - OneNote not responding
    - Data not available after device change (notebook not added on new laptop, content lost after rejoin/separation)
    - Data not available after rejoin (notebook from prior employment missing on new identity)
- *Common resolutions:* Open notebook via File → Open → OneDrive on new device, run sync on both devices, close and reopen OneNote, validate notebook storage location.
- *Indicators for rejoin:* "Rejoined Intel", "previous notebook", "old identity", "account terminated".
- *Exclude:* Data permanently unrecoverable because retention window expired → Microsoft OneDrive Issues (sub-symptom: Former-employee OneDrive data request).

***

**Microsoft 365 Apps for Enterprise Issues**

- *Sub-symptoms:*
    - Office apps not opening (multi-app blank / launch failure)
    - License activation issue (sign-in / activation loop with valid license, identity/profile corruption, F3 license blocking desktop apps)
    - App crash / instability (across multiple Office apps)
    - Installation failure (Company Portal install fails, error code 30015-26, install stuck)
    - Update-related issue (M365 in-app update fails)
    - License not assigned to rejoined identity (Office suite license missing after rehire / new UPN)
- *Common resolutions:* Online / quick repair, end M365 app processes in Task Manager, delete Office identity folder, clear credentials, reinstall via Company Portal, submit "MSOL License - F3 License Exception" AGS request.
- *Indicators:* "F3 License", "F3 License Exception", "restricted from accessing M365 Client Applications", "Error Code 30015-26", "Work or school account" sign-in prompts repeated across apps.
- *Exclude:* Failure isolated to one Office app → that app-specific category.

***

**Microsoft 365 Copilot Issues**

- *Sub-symptoms:*
    - Copilot not visible (icon missing in Excel / Word / PowerPoint / Teams)
    - Copilot license missing (entitlement not assigned, AGS hidden, blackout / depleted inventory)
    - Copilot partially enabled (works in Outlook but not Excel / PowerPoint, etc.)
    - Teams facilitator not available
    - Feature rollout issue (ChunkLoadError, Copilot fails to load despite license)
    - Usage guidance query
    - License not assigned to rejoined identity (Copilot license missing after rehire / new UPN)
- *Common resolutions:* Direct user to KB10045042 / M365 Copilot License Request Form, add to waitlist, clear Teams cache / reinstall Teams (technical failure with license).
- *Indicators:* "MSOL License – Copilot for M365", "entitlement has been hidden in AGS", "blackout period", "additional Copilot licenses cannot be purchased", "ChunkLoadError", KB10045042.
- *Critical rule:* Any time Copilot is the root cause, use this category — do NOT split by Office app.

***

**Microsoft Forms Issues**

- *Sub-symptoms:*
    - Forms not accessible ("Your organization has not enabled Microsoft Forms for your current account")
    - Forms feature disabled
    - Polls not working (Teams)
    - Form creation failure
- *Common resolutions:* Submit AGS request for "Microsoft Forms Creation access" with manager approval; validate Forms entitlement.

***

**Microsoft Visio Issues**

- *Sub-symptoms:*
    - License expired issue
    - Activation failure
    - Installation issue
    - File open / save failure
- *Common resolutions:* Validate Visio license entitlement in AGS, request / renew license, repair / reinstall Visio.

***

**Microsoft Project Issues**

- *Sub-symptoms:*
    - License activation issue
    - Installation failure
    - File open / save failure
    - Schedule / plan corruption
    - Performance / hang issue
- *Common resolutions:* Validate Project license entitlement, repair / reinstall Project, recover plan from backup.

***

**Microsoft Loop Issues**

- *Sub-symptoms:*
    - Workspace not loading
    - Loop content missing
    - Integration issue (M365 group, Teams, Outlook)
- *Common resolutions:* Sign out / in, validate Loop / M365 group membership, escalate to engineering for tenant-level integration issues.

***

**Microsoft OneDrive Issues**

- *Sub-symptoms:*
    - Sync failure (file not uploading, file in cloud missing on device)
    - Sync stuck / delayed
    - File rename / path conflict (long path, SharePoint shortcut character limit)
    - File availability setting ("Always keep on this device", Error 0x80070032 on copy)
    - OneDrive client not working / stopped
    - Storage quota exceeded
    - "Access denied" / "You need permission to access this item" on a shared SharePoint or OneDrive file
    - Owner re-share required
    - PowerPoint / Excel / Word file permission error inside the Office app
    - Rejoined user — previous OneDrive content unavailable
    - Former-employee OneDrive data request
- *Common resolutions:* Sign out / in OneDrive, reset OneDrive (`wsreset.exe`), remove SharePoint shortcuts (KB10057023), untick "Always keep on this device", reinstall OneDrive client; owner removes user from sharing list and re-adds for permission errors.
- *Exclude:* Mapped network drive / SMB / DFS path issue → Shared File Service (Share Drives) Issues.

***

**Shared File Service (Share Drives) Issues**

- *Sub-symptoms:*
    - Access permission issue on a shared / mapped drive path
    - Mapped drive not connecting ("local device name is already in use", reconnect failure after PC refresh)
    - Missing folder / file on a shared drive
    - Quota / storage issue
    - Drive sync failure (SMB / Samba copy errors not caused by the OneDrive client)
    - Access not reapplied to new identity (rejoin — mapped share drive access not restored after rehire)
- *Common resolutions:* Remap drive via File Explorer, validate share path owner via AGS, restart workstation, request access to share path.

***

**Smartsheet Issues**

- *Sub-symptoms:*
    - Access permission issue
    - External sharing issue
    - Data sync issue
    - Import / export failure
- *Common resolutions:* Validate Smartsheet entitlement, request access, escalate to Smartsheet admin / SME for sharing or sync issues.

***

**Google Workspace Issues**

- *Sub-symptoms:*
    - Access issue (cannot open Drive / Docs)
    - Permission issue (blocked uploads, sharing controls)
    - Account provisioning issue ("Google Documents Sharing" entitlement)
- *Common resolutions:* Provide ServiceNow catalog request link, validate "Google Documents Sharing" access, SME confirmation.

***



**Other / Miscellaneous**

- *Definition:* Genuine Productivity Tools incident that does not fit any category above.
- Only use when no other category fits AND the ticket is in scope.

***

**Excluded**

- *Definition:* Service offering / request type clearly outside Productivity Tools (cellular, printer supplies, PC hardware/OS rebuild, network/VPN, Outlook mailbox/Exchange mail-flow, Teams calling/meetings, GitHub Enterprise, Microsoft Visual Studio, GitHub Copilot, any developer-tooling licensing).
- *Critical rule:* If the ticket has a documented Productivity Tools resolution, it must be categorized - do not exclude.

***

**Microsoft 365 Groups / Planner / To Do Issues**

- *Sub-symptoms:*
    - M365 Group membership / ownership issue (cannot add owner, group missing from Outlook/Teams)
    - Planner plan / board access issue (cannot open plan, missing tasks, plan not loading)
    - To Do list sync / access issue
    - Group provisioning failure (group not created from Teams / SharePoint site)
- *Common resolutions:* Validate M365 Group membership in Azure AD, re-add owner via group settings, recreate plan from Planner web, sign out / in to To Do client.
- *Exclude:* Pure Outlook/Exchange mailbox issue on the group mailbox -> Messaging service offering (Excluded).

***

**Canva Issues**

- *Sub-symptoms:*
    - Access / SSO sign-in issue
    - License / entitlement missing (Canva for Teams/Enterprise)
    - Sharing / collaboration issue (cannot share design with org user)
    - Template / brand kit access issue
    - Export / download failure
- *Common resolutions:* Validate Canva entitlement in AGS, request access via catalog, re-authenticate SSO, escalate to Canva admin for tenant-level sharing.
***

### **Quick Decision Tree**

**FIRST: Service Offering check**
- Service Offering is not "Productivity Tools" and the issue is clearly cellular / printer supplies / PC hardware / OS rebuild / mailbox? → **Excluded**.
- Otherwise continue.

**THEN: Categorize**

2. **Copilot involved as root cause (license, blackout, icon missing, ChunkLoadError, Facilitator)?** -> Microsoft 365 Copilot Issues.
3. **Rejoined user or former employee's OneDrive/SharePoint data?** -> Microsoft OneDrive Issues.
4. **Shared SharePoint/OneDrive file permission error (owner re-share fixes it)?** -> Microsoft OneDrive Issues.
5. **Mapped network drive / SMB / shared drive path issue?** -> Shared File Service (Share Drives) Issues.
6. **OneDrive client sync / upload / file availability issue?** -> Microsoft OneDrive Issues.
7. **OneNote-specific (notebook sync, missing notes, device change)?** -> Microsoft OneNote Issues.
8. **Excel-only behavior (blank screen, cache, freeze, add-in, data refresh)?** -> Microsoft Excel Issues.
9. **Word-only behavior (document, formatting, add-in like IVO)?** -> Microsoft Word Issues.
10. **PowerPoint-only behavior (presentation, formatting, app crash)?** -> Microsoft PowerPoint Issues.
11. **Visio-specific issue?** -> Microsoft Visio Issues.
12. **Project-specific issue?** -> Microsoft Project Issues.
13. **Loop-specific issue?** -> Microsoft Loop Issues.
14. **Forms-specific issue?** -> Microsoft Forms Issues.
15. **M365 Group / Planner / To Do issue?** -> Microsoft 365 Groups / Planner / To Do Issues.
16. **Smartsheet issue?** -> Smartsheet Issues.
17. **Google Workspace / Gemini issue?** -> Google Workspace Issues.
18. **Canva issue?** -> Canva Issues.
19. **Multi-Office-app install, update, activation, or F3 license tier issue?** -> Microsoft 365 Apps for Enterprise Issues.
20. **None fit but in scope?** -> Other / Miscellaneous.
21. **Clearly out of scope service offering (cellular, printer, PC hardware, network/VPN, Outlook mailbox, Teams calling, GitHub, Visual Studio)?** -> Excluded.

***

## REQUIRED OUTPUT FORMAT

**FOR ALL TICKETS (including Excluded):**

Primary Category: [Choose only from the 19 product categories above - OUTPUT ONLY THE CATEGORY NAME. "How Do I / User Education" is NOT a valid category - route guidance questions to the relevant product category instead (e.g., Copilot usage guidance → Microsoft 365 Copilot Issues, OneDrive usage guidance → Microsoft OneDrive Issues).]

**If using "Excluded" category, also include:**
Exclusion Reason: [Brief description of why the ticket is out of scope, e.g. "Out of scope — cellular service" or "Out of scope — PC hardware replacement"]

**INVALID reasons for using Excluded category (use the appropriate category instead):**
- ❌ "Copilot license not available" → Microsoft 365 Copilot Issues
- ❌ "F3 license blocking Office desktop" → Microsoft 365 Apps for Enterprise Issues
- ❌ "Rejoined user can't access old OneDrive" → Microsoft OneDrive Issues
- ❌ "Escalated to L1.5 / engineering / Microsoft" → If resolution is documented, categorize based on what fixed it
- ❌ "Limited work notes" → Use close_notes / resolution_category for evidence

**FOR ALL TICKETS:**

Sub-symptom: [Pick the closest matching sub-symptom from the chosen category's list, e.g. "License activation issue", "Notebook sync failure", "Mapped drive not connecting". This adds traceability between root cause and category.]

Confidence Level: [High/Medium/Low]
- High (90%+): Clear root cause with documented resolution and user confirmation
- Medium (70–89%): Clear resolution path but some ambiguity in root cause or evidence
- Low (Under 70%): Multiple possible categories or unclear / undocumented resolution

**CONFIDENCE CALCULATION FRAMEWORK:**

**CONFIDENCE BOOSTERS (+):**
- Application clearly identified and matches category (+20%)
- Specific error message, error code, KB number, or entitlement name present (+15%)
- Agent used Productivity-Tools-specific terminology (MSOL License, AGS entitlement, OfficeFileCache, KB10045042, KB10057023, F3 License Exception) (+10%)
- Resolution matches category examples exactly (+15%)
- Clear root cause identification with supporting evidence (+10%)

**CONFIDENCE REDUCERS (-):**
- Application/area unclear, ambiguous, or contradictory (-20%)
- Only user symptom language, no agent technical detail or resolution (-15%)
- Multiple possible categories apply with equal evidence (e.g., could be Copilot Issues or Excel Issues) (-10%)
- Contradictory information between description, work notes, and close notes (-25%)
- Vague or generic language; "issue resolved" with no documented steps (-10%)

**CONFIDENCE CALCULATION:**
Base Confidence (50%) + Total Boosters − Total Reducers = Final Confidence Level
- 90%+ = High Confidence
- 70–89% = Medium Confidence
- Under 70% = Low Confidence

Reasoning: [Detailed explanation of why this category and sub-symptom were selected. Reference the application/area identified (Excel, OneDrive, Copilot, etc.), specific resolution indicators from the category definition that matched the ticket, key phrases or entitlement names from the work/close notes, and why other categories were excluded. Note any licensing constraints (Copilot blackout, F3 restriction) that drove the categorization.

APPLICATION VALIDATION: Confirm the application/feature matches the selected category. If the ticket mentions multiple applications (e.g., "Copilot in Excel"), use the **root cause** application — Copilot if license/feature-driven, Excel if app-driven. If the application is unclear or only generic "Office" / "M365" language is used, reduce confidence accordingly.]

Key Evidence: [Multiple relevant quotes from work notes, close notes, or short description that support the classification. Include error messages, entitlement names (e.g., "MSOL License – Copilot for M365"), KB numbers, error codes (e.g., "Error 0x80070032", "Error Code 30015-26"), and resolution steps.]

Resolution Summary: [One sentence describing what actually fixed the issue (or, if unresolved, the disposition such as "User submitted Copilot license request form and was added to the waitlist").]

How Do I or Error: [Was the incident a "How Do I" question (user education with no technical failure) or an Error (technical failure, error message, or feature unavailable)?]

KB Provided: [Was a KB attached or provided in work notes/comments? If yes, provide the KB number (e.g., KB10045042, KB10057023). Otherwise "No".]

**CRITICAL OUTPUT RULES:**
- For Primary Category, output ONLY the exact category name without any formatting.
- Do NOT include asterisks, bold formatting, or headers.
- Example of CORRECT output:
    Primary Category: Microsoft 365 Copilot Issues  
    Sub-symptom: Copilot license missing  
    Confidence Level: High  
    Reasoning: The user reported Copilot was not visible in Excel and PowerPoint while it still worked in Outlook. The agent confirmed in AGS that the "MSOL License – Copilot for M365" entitlement was hidden because existing license inventory was depleted during a contract blackout period. The resolution path was to submit the M365 Copilot License Request Form and join the waitlist. This is a licensing/entitlement constraint, which routes to Microsoft 365 Copilot Issues regardless of which Office app the user mentioned. Microsoft Excel Issues and Microsoft PowerPoint Issues are ruled out because the root cause is Copilot licensing, not the Office app itself.  
    Key Evidence: "Co-pilot not enabled in excel and power point but it works in outlook." / "the \"MSOL License – Copilot for M365\" entitlement has been hidden in AGS" / "Existing license inventory is limited and currently depleted." / KB10045042 referenced.  
    Resolution Summary: User was directed to the M365 Copilot License Request Form and added to the waitlist for the blackout period.  
    How Do I or Error: Error  
    KB Provided: KB10045042

***

### **Final Reminders**

- **"Excluded" is a category** only for tickets clearly outside Productivity Tools scope. Do not use Excluded for Copilot/Office licensing, rejoin scenarios, shared file permissions, or any documented Productivity Tools resolution.
- **Single-app vs multi-app:** Failure isolated to one Office app → that app's category. Multi-app or suite-wide (install / update / F3 license / activation loop) → Microsoft 365 Apps for Enterprise Issues.
- **Copilot always wins** when it is the root cause — never split into Excel / Word / PowerPoint / Teams.
- **Rejoin scenarios** always route to Microsoft OneDrive Issues (for OneDrive/SharePoint content and permission issues).
- **OneNote on a new laptop:** Default to Microsoft OneNote Issues unless the work notes specifically attribute the failure to the OneDrive client.
- **"Always keep on this device" / Error 0x80070032** is Microsoft OneDrive Issues.
- **"MSOL License – Copilot for M365" hidden in AGS / blackout period** is Microsoft 365 Copilot Issues.
- **"MSOL License - F3 License Exception"** is Microsoft 365 Apps for Enterprise Issues.
- **Mapped network drive / Samba** is Shared File Service (Share Drives) Issues, not OneDrive.
- Output only the required fields, in the exact format above, for each incident.
- Do not add extra explanation, commentary, or formatting.
- Always use the most specific, root-cause-based category and sub-symptom.

***
