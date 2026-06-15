# Productivity Tools Environment Context

## **IMPORTANT: This context is for AI analysis only. Do NOT reference this information in ticket summaries. Use only to understand technical terms, licensing flows, and typical issues for the Productivity Tools service.**

## SERVICE SCOPE & PLATFORMS

The **Productivity Tools** service offering covers cloud-first collaboration, content authoring, and file-storage applications used by all corporate users. All applications are delivered on **company-managed devices** (Windows, macOS, Linux where applicable) and authenticated through **Azure Active Directory (Azure AD / Entra ID)** with corporate SSO and MFA. Personal/BYOD access is restricted to web-only with conditional access.

### In-scope applications

- **Microsoft 365 Apps for Enterprise** — desktop suite: Word, Excel, PowerPoint, Outlook, OneNote, Access (limited), Publisher (deprecated). Delivered via Click-to-Run from the **Monthly Enterprise Channel** (some pilot groups on Current Channel).
- **Microsoft 365 Copilot** — generative-AI assistant integrated into Word, Excel, PowerPoint, Outlook, Teams, OneNote, Loop, Whiteboard, and the standalone Copilot Chat (M365.cloud.microsoft).
- **Microsoft OneDrive for Business** — per-user cloud storage with the OneDrive sync client (Windows/Mac), Known Folder Move (Desktop/Documents/Pictures redirected to OneDrive), Files On-Demand, and web access at intel-my.sharepoint.com.
- **Microsoft OneNote** — notebooks stored in OneDrive/SharePoint; two clients exist (OneNote for Windows 10/UWP — deprecated, and OneNote on Windows — the supported converged client).
- **Microsoft Loop** — workspaces, pages, and Loop components for cross-app real-time collaboration.
- **Microsoft Forms** — surveys, quizzes, and polls; ownership transfer is governed by tenant policy.
- **Microsoft Visio Professional Client** — diagramming desktop app with subscription-based activation.
- **Microsoft Project (Desktop / Project for the web)** — project scheduling.
- **Microsoft 365 Planner / To Do** — supporting collaboration apps tied to Groups.
- **Google Workspace** — Docs, Sheets, Slides, Drive, Gmail (federated where used), **Gemini** AI; tenant identity federated from Azure AD.
- **Smartsheet** — SaaS work management, SSO-integrated.
- **Shared File Service (Share Drives)** — legacy on-prem / hybrid SMB shares mapped via DFS namespaces, plus modern Azure Files where adopted.
- **Canva** 

### Out of scope (handled by other service offerings)

- Outlook **mail delivery / Exchange Online routing** issues (handled by Messaging service offering — Productivity Tools handles Outlook *client* install/profile issues only when they overlap with M365 Apps).
- Microsoft Teams calling/meeting/voice issues (handled by Collaboration / Teams service offering — Productivity Tools handles Teams files-and-Copilot integration only).
- Endpoint provisioning, Intune enrollment, BitLocker, hardware repairs (handled by PC service offering).
- Visual Studio Issue
- Outlook or Teams Feature related Issue
- Github Related issue

***

## IDENTITY, LICENSING & ENTITLEMENTS

### Identity & Authentication

- **Primary IdP**: Azure AD (Entra ID), synced from on-prem AD via Azure AD Connect. All M365, Copilot, OneDrive, SharePoint, Forms, Loop, Visio, Project, Stream, Smartsheet, Google Workspace, and GitHub Enterprise Cloud authenticate via Azure AD SSO with MFA enforced through Conditional Access.
- **Federation**: Google Workspace and Smartsheet are configured for SAML/OIDC federation to Azure AD. GitHub Enterprise Cloud uses **Enterprise Managed Users (EMU)** with SCIM provisioning from Azure AD — usernames are suffixed (e.g., `username_intel`).
- **Conditional Access**: Productivity Tools cloud apps require a **compliant** or **hybrid-joined** device for full access. Non-compliant or personal devices get **web-only / app-restricted** sessions (no download, no sync) enforced by Microsoft Defender for Cloud Apps / app-enforced restrictions.

### Licensing model (AGS — Access & Group Services)

All entitlements are requested and approved through Intel's **AGS** portal, which provisions licenses, group memberships, and feature flags into Azure AD. Key license SKUs and AGS entitlements that surface in tickets:

- **MSOL License – M365 E3 / E5** — base M365 Apps + OneDrive + SharePoint + Forms + Loop + OneNote.
- **MSOL License – F3 License** — frontline-worker SKU (web-only Office, 2 GB OneDrive, no desktop apps). Frontline users requesting desktop Office or full Copilot need an **F3 License Exception** entitlement approved.
- **MSOL License – F3 License Exception** — uplifts an F3 user to E3/E5-equivalent feature set; required before assigning Copilot.
- **MSOL License – Copilot for M365** — per-user Copilot for Microsoft 365 add-on. Hidden in AGS during scheduled rollout/blackout windows; surfaces again after the window. KB **KB10045042** documents the Copilot license request flow.
- **MSOL License – Visio Plan 2** — Visio Professional desktop activation.
- **MSOL License – Project Plan 3 / Plan 5** — Project Desktop / Project for the web.
- **MSOL License – Power BI Pro** — co-resident with Productivity Tools for some workflows; covered by Analytics SO but appears in tenant license stack.
- **Google Workspace Enterprise Plus** — base Google entitlement; **Gemini for Workspace** is a separate add-on entitlement.
- **Smartsheet Business / Enterprise** — per-user, managed via Smartsheet group sync.


> **Critical behavior**: License changes from AGS take **15 minutes to 4 hours** to propagate through Azure AD → tenant → client cache. Users often see "Copilot still not visible" immediately after approval and need to be told to wait, sign out/in, or restart the Office app to refresh the license token. KB **KB10057023** covers the Office license refresh / sign-out-sign-in procedure.

### Licensing rules and known precedence

1. **F3 baseline blocks Copilot** — a user on F3 alone cannot be assigned Copilot; AGS will hide the Copilot entitlement until F3 License Exception is approved.
2. **Copilot precedence over host app** — when a user reports "Copilot missing from Excel/Word/PowerPoint", root cause is almost always licensing or feature rollout, not the host app. Sub-categorize under Microsoft 365 Copilot, not under the host application.
3. **Blackout windows** — during scheduled Copilot rollout pauses, the Copilot entitlement is **hidden from AGS** but existing assignments are unaffected. Users requesting new Copilot during a blackout must wait for the window to close.
4. **Visio/Project per-user activation** — desktop activation requires the user to sign in to the app with the same UPN that holds the license. Shared/kiosk machines do not work.


***

## CONTENT STORAGE & SYNC ARCHITECTURE

### OneDrive for Business / SharePoint Online

- **Tenant URL pattern**: `https://intel-my.sharepoint.com/personal/<upn-with-dashes>/` (OneDrive); SharePoint team/communication sites live on the same `intel.sharepoint.com` domain.
- **Sync client**: OneDrive (modern, Next-Gen Sync Client). Deployed via M365 Apps; configured with **Silent Account Configuration**, **Known Folder Move (KFM)** for Desktop/Documents/Pictures, and **Files On-Demand** enabled by default.
- **Storage quota**: 1 TB per user (E3/E5). F3 users get 2 GB. SharePoint site collections have a separate quota managed by the site owner.
- **Retention**: Deleted files → first-stage Recycle Bin (93 days) → second-stage Recycle Bin (admin-restorable inside the 93-day window). After 93 days, content is unrecoverable.
- **Former-employee data**: When a user is terminated, their OneDrive is retained for **30 days** by default (configurable per tenant policy). After 30 days the site is permanently deleted and content is **not recoverable**. Manager-of-record can request a copy within the 30-day window via the offboarding workflow.
- **Rejoin scenarios**: A rehired employee receives a **new** OneDrive site keyed to their new UPN/object ID. Their old OneDrive content from the prior employment is **not** automatically restored and is usually unrecoverable past the 30-day window. SharePoint site permissions referencing the old object ID must be manually re-added by site owners.
- **SharePoint site types**: Team sites (M365 Group-backed), Communication sites, Hub sites. Permissions inherit from M365 Group membership unless broken inheritance is set on a library/folder.
- **SharePoint access patterns**: Owners/Members/Visitors at site level; granular library or item-level sharing via "Share" link (Anyone / People in Org / Specific people / Existing access).
- **Permission propagation delay**: Up to **15 minutes** for new group-membership-based access; up to **1 hour** for SCIM-driven group changes from AGS.
- **External sharing**: Disabled by default for most sites; "People in your organization" links and "Specific people" links to guest accounts are allowed only on sites explicitly enabled for external sharing.

### Known error codes & symptoms

- **0x80070032** — OneDrive sync "request not supported" — typically caused by a reserved filename, invalid path character, path-length > 400 chars, or a file locked by another process.
- **0x8004de40 / 0x8004de85 / 0x8004de8a** — sign-in / token errors; fix via sign-out, clear OneDrive credentials in Credential Manager, re-sign-in.
- **0x80004005** — generic sync failure; usually transient or permission-related.
- **"Files On-Demand error"** — local cache corruption; reset OneDrive (`%localappdata%\Microsoft\OneDrive\onedrive.exe /reset`).
- **"OneDrive isn't running" toast** after PC refresh — Silent Account Configuration GPO needs to apply; user must sign in to Office once to seed the token.
- **"Missing files after PC refresh"** — almost always KFM redirection that didn't complete on the old device before refresh, leaving local-only files on the wiped disk. Recovery is only possible if the user had previously confirmed sync completion.

### Shared File Service (Share Drives)

- **DFS namespaces** like `\\amr.corp.intel.com\<dept>\<share>` map to SMB shares on the file-server estate.
- **Mapped drives** delivered via GPO drive-map preferences keyed off AD group membership.
- **No OneDrive overlap** — never instruct a user to migrate a Share Drive to OneDrive without the data-owner's approval. Share Drive issues stay in Productivity Tools / Shared File Service sub-category, never OneDrive.

***

## MICROSOFT 365 COPILOT — DETAILED CONTEXT

### How Copilot surfaces in apps

- **In-app Copilot pane / ribbon**: Word, Excel, PowerPoint, Outlook (new Outlook), OneNote, Loop, Whiteboard.
- **Copilot Chat (work)**: Standalone at `m365.cloud.microsoft` and inside Teams; grounded in tenant data via Microsoft Graph (mail, files, chats, calendar).
- **Copilot in Teams**: Meeting recap, chat summaries, transcript Q&A — depends on meeting transcription being enabled.

### Activation prerequisites

1. User has **M365 E3 or E5** (or F3 + F3 Exception).
2. **Copilot for M365** license assigned in AGS and synced to Azure AD.
3. User signed in to Office with the correct UPN.
4. Office build is **Current Channel** or **Monthly Enterprise Channel** with a recent enough version (16.0.17xxx+).
5. The specific app surface has been **rolled out** to the tenant — Microsoft phases features per app and per channel.

### Common Copilot patterns

- **"Copilot missing in Excel but visible in Word"** — feature-rollout issue, not a license issue. Verify license is assigned, then point user to the Microsoft 365 admin center / Message Center for the per-app rollout date. No L1/L2 fix; tracked as Feature Availability.
- **"Copilot partially enabled"** — usually means the standalone Copilot Chat works but in-app Copilot doesn't (or vice versa). Almost always a token-cache issue: sign out of Office, clear the Office identity (File → Account → Sign out), sign back in.
- **"Copilot license missing after AGS approval"** — wait 4 hours, then sign out/in. If still missing after 24h, escalate to the Productivity Tools — Engineering assignment group with the AGS request number.
- **Copilot returning "I can't find information about that"** — usually a permission issue: Copilot only returns content the user can already access via Graph. Not a Copilot bug.

***

## CLIENT DEPLOYMENT & UPDATE CHANNELS

- **M365 Apps update channel**: Monthly Enterprise Channel (default) — security and feature updates on the 2nd Tuesday of each month. Pilot ring is Current Channel.
- **Deployment tooling**: Office Deployment Tool (ODT) configurations pushed via Intune Win32 apps. Repair via Control Panel → Programs → "Change" → Quick Repair / Online Repair.
- **OneDrive client update ring**: Enterprise ring (lags the consumer ring by several weeks).
- **Visio / Project**: Same Click-to-Run engine; activated per-user once license is assigned and the user signs in.
- **Mac M365 Apps**: Updated via **Microsoft AutoUpdate (MAU)**; channel matches Windows ring.

### Known client-side error codes

- **30015-26 / 30094-1011 / 30068-39** — Click-to-Run install/update failures. Usually fixed by Online Repair, clearing the C2R cache (`%programdata%\Microsoft\ClickToRun`), or full uninstall via Microsoft Support and Recovery Assistant (SaRA).
- **"Your account doesn't allow editing on a Mac"** — license assigned but Mac app needs sign-out/in.
- **"Something went wrong [1001]"** on activation — Azure AD token failure; sign out of Office and Windows, sign back in.
- **ChunkLoadError** in browser-based Office / SharePoint / Loop — stale service-worker cache; clear browser cache, hard refresh, or use private window.

***

## NETWORK & CONNECTIVITY DEPENDENCIES

- All M365 cloud apps require outbound HTTPS to **\*.office.com, \*.office365.com, \*.microsoft.com, \*.microsoftonline.com, \*.sharepoint.com, \*.onedrive.com, \*.live.com, \*.cloud.microsoft, \*.copilot.cloud.microsoft**.
- Proxy/firewall: Intel uses split-tunnel VPN; M365 endpoints follow the Microsoft "Optimize" category and are routed direct-to-internet from corporate networks per Microsoft's 365-network-connectivity guidance.
- **Common network failures**: proxy auth prompts in OneDrive client (fixed by ensuring WPAD or static proxy is set machine-wide), TLS inspection breaking Office activation, captive-portal Wi-Fi blocking token refresh.
- **Google Workspace** endpoints: `*.google.com, *.googleapis.com, accounts.google.com` — federation handshakes pass through Azure AD.


***

## SUPPORT STRUCTURE

### Assignment groups & escalation path

- **OSD L1** — First contact for all Productivity Tools tickets. Handles password issues, basic sign-in, OneDrive client restart, sync icon checks, KB-driven self-service guidance.
- **OSD L1.5** — Intermediate; handles repair/reinstall of M365 Apps, OneDrive reset, KFM verification, AGS entitlement-request guidance, basic SharePoint permission checks.
- **Collaboration Ops Spt** — Tenant-side investigations: SharePoint permission escalations, OneDrive site restore from second-stage recycle bin (within retention), Forms ownership transfer, Loop workspace recovery, Teams/SharePoint integration issues.
- **Productivity Tools — Engineering** — L3 engineering for licensing pipeline failures, AGS-to-Azure-AD sync defects, Copilot rollout issues, tenant policy changes, Visio/Project activation bugs, federation defects (Google Workspace, Smartsheet, GitHub EMU).
- **Service-specific L3s** — GitHub Admins (for SCIM/EMU), Google Workspace Admins (for Gemini and Drive), Smartsheet Admins (for group sync), Messaging team (for any Outlook/Exchange routing escalation that comes in mis-routed).

### Knowledge resources

- **ServiceNow KB**: Authoritative source for repeatable fixes. Frequently referenced articles:
    - **KB10045042** — Copilot for M365 license request flow via AGS.
    - **KB10057023** — Office sign-in / license refresh procedure after entitlement changes.
    - **KB10038xxx** series — OneDrive sync reset, KFM verification, error-code lookup.
    - **KB10042xxx** series — SharePoint sharing and permission how-tos.
    - **KB10049xxx** series — Visio / Project activation.
- **Microsoft 365 Message Center** — authoritative source for per-tenant feature rollout dates (used by Engineering when explaining "Copilot in app X not yet available").
- **AGS portal** — entitlement requests, group memberships, license visibility.
- **Self-service**: Intel IT Help portal hosts user-facing how-tos for common Productivity Tools tasks (sharing a file, requesting Copilot, recovering deleted files within 93 days).

***

## COMMON ISSUE PATTERNS

### Licensing & Entitlement

1. **"Copilot is not showing in my Office apps"** — verify Copilot for M365 license in AGS → check Azure AD assignment → instruct sign-out/in → wait 4h → if still missing, escalate to Productivity Tools — Engineering with the AGS request number. Reference KB10045042 and KB10057023.
2. **"F3 user asking for desktop Office or Copilot"** — request F3 License Exception through AGS first; only then can E3/E5-equivalent SKUs or Copilot be assigned.
3. **"Visio / Project desktop says unlicensed"** — confirm Visio Plan 2 / Project Plan 3 in AGS, sign-out/in of the app, repair Office if persistent.
4. **"License expired" / "Activation failure" on M365 Apps** — usually a stale token after a license SKU swap; sign out from File → Account, restart, sign back in. If repeated, run Office Online Repair.

### OneDrive / SharePoint

5. **Sync failure with red X or paused state** — restart OneDrive, check for reserved characters / long paths / locked files (error **0x80070032**), reset client if needed (`onedrive.exe /reset`).
6. **"Missing files after PC refresh"** — check whether KFM had completed on the old device; if not, files are unrecoverable. Set proper expectation with the user.
7. **"Shared file access denied"** — verify the file owner re-shared to the user; check for inherited SharePoint permissions; for rejoined employees, the new object ID differs from the old — site owners must re-add the user under the new account.
8. **"OneDrive storage quota exceeded"** — user's 1 TB is full; archive content to SharePoint or Share Drive; quota uplifts above 1 TB require Engineering approval.
9. **"Web vs desktop mismatch"** — usually sync hasn't completed; force a sync and wait, or open the file from the web copy.
10. **"Rejoined employee can't see previous OneDrive/SharePoint content"** — previous OneDrive was deleted after the 30-day retention; content is unrecoverable. New OneDrive is provisioned with the new identity. SharePoint site owners must re-add the user manually.
11. **"Manager wants former employee's data"** — within 30 days: request via offboarding workflow; beyond 30 days: not recoverable.

### Office Apps (Excel / Word / PowerPoint / OneNote)

10. **App crashes or won't open** — Online Repair → safe-mode (`excel /safe`) to isolate add-ins → disable COM add-ins → reinstall if persistent.
11. **Performance issues with large files** — usually file size > 50 MB with heavy formulas/macros (Excel) or embedded media (PowerPoint). Recommend splitting workbooks, removing unused formatting, compressing media.
12. **"File is locked for editing"** — co-author lock; check who has it open (file header in Excel/Word) or wait for the OneDrive lock to release (~30 min after the last editor closed).
13. **OneNote sync errors / "Notebook is not syncing"** — sign out and back in to the OneNote client; if notebook URL is broken, close it and reopen from OneDrive web. **Data loss after PC refresh** on OneNote almost always = local-only notebooks that were never uploaded to OneDrive.

### Microsoft 365 Copilot

14. **"Copilot not visible in Excel/Word/PowerPoint"** — license verification first; if licensed, check Microsoft 365 Message Center for per-app rollout status; if rolled out and still missing, sign-out/in and clear Office identity cache.
15. **"Copilot license missing in AGS"** — likely in a scheduled rollout/blackout window; explain and provide expected window-close date from Engineering.
16. **"Copilot returned wrong/empty results"** — explain Graph-grounding: Copilot only sees what the user can see. Not a defect unless grounding is broken (escalate with example prompt + expected source).

### Forms / Loop / Visio / Project

17. **"Forms Ownership Transfer"** — user requesting transfer of a form from a leaver. Requires Forms admin action via Collaboration Ops Spt.
18. **"Loop workspace not loading"** — usually a tenant policy rollout or a Loop URL stuck in a stale tab; clear browser cache or use a private window.
19. **"Visio Pro install failure"** — clear C2R cache, run Online Repair, ensure license assigned, retry. Persistent failure → Engineering.
20. **"Project file won't open"** — confirm Project license, check that the file isn't a newer Project for the web export (`.mpp` vs web export incompatibility).

### Google Workspace / Smartsheet 

21. **"Cannot access Gemini"** — Gemini add-on entitlement not assigned in AGS; request via AGS.
22. **"External sharing in Google Drive blocked"** — tenant external-sharing policy; exceptions require Information Security approval.
23. **"Smartsheet license missing"** — Smartsheet group sync from AGS lags up to 4 hours; if longer, escalate to Smartsheet Admin.

### Shared File Service (Share Drives)

24. **"Mapped drive missing"** — verify GPO drive-map applies (AD group membership), force `gpupdate /force`, sign-out/in.
25. **"Access denied on Share Drive folder"** — NTFS / share permission; data-owner must approve via AGS group request.

***

## TROUBLESHOOTING CONTEXT

### App identification clues

- **Microsoft 365 Apps** — file extensions (.docx/.xlsx/.pptx/.one), error codes starting with **0x8...** or **30xxx-xxxx**, mention of "Office", "Click-to-Run", "C2R", "MAU".
- **OneDrive** — cloud icon in system tray, "Files On-Demand", "sync", error codes **0x8007...** / **0x8004de...**, KFM, "Desktop redirected".
- **SharePoint** — `*.sharepoint.com` URLs, "site", "library", "permission level", "Owners/Members/Visitors".
- **Copilot** — "Copilot pane", "Copilot Chat", "license missing", "not visible", references to AGS Copilot entitlement.
- **OneNote** — "notebook", "section", "page", "sync conflict copies".
- **Visio / Project** — `.vsdx` / `.mpp` files, "activation", "unlicensed product".
- **Google Workspace** — `docs.google.com`, `drive.google.com`, "Gemini", "external sharing".
- **Smartsheet** — `app.smartsheet.com`, "sheet", "row", "group sync".
- **Shared File Service** — UNC paths (`\\amr.corp.intel.com\...`), "mapped drive", "DFS", "SMB".

### Resolution validation patterns

- **License-driven fix**: AGS entitlement approved → wait ≥15 min → user signs out/in to Office → license appears → close ticket.
- **Sync-driven fix**: OneDrive reset → sign back in → confirm sync icon turns green → confirm file appears on both web and desktop → close.
- **Permission-driven fix**: Owner re-shares → user opens link in private window → access granted → close.
- **Feature-rollout fix**: No tenant action possible; close with explanation referencing Microsoft 365 Message Center rollout date.
- **Last-resort fixes**: Office Online Repair, full Office reinstall, OneDrive reset, browser cache clear, sign-out-everywhere-and-back-in. Reimaging the PC is **out of scope** for Productivity Tools — refer to PC Service Offering.

### Cross-team handoffs

- **Outlook mail flow / Exchange routing** → Messaging service offering.
- **Teams calling / meeting failures** → Teams / Collaboration service offering.
- **Endpoint compliance / Intune / BitLocker** → PC service offering.
- **Identity / Conditional Access policy** → Identity & Access Management.
- **Google federation defects, Smartsheet provisioning defects** → respective L3 admin teams via Productivity Tools — Engineering.

**REMINDER:** This environment context is for the AI's internal comprehension only. When generating user-facing summaries, translate internal terms (AGS, SCIM, EMU, KFM, C2R, Conditional Access) into plain language ("we updated your license", "we refreshed your account", "we restored your file access"). Never reveal internal KB numbers, error-code mappings, license SKU names, or tenant policy details in summaries shared outside of IT support.
