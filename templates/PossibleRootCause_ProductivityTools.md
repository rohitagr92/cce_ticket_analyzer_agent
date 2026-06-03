# Possible Root Cause Reference - Productivity Tools

> **Purpose:** Canonical, fixed catalog of root cause labels for all Productivity Tools incidents. After selecting the Category and Sub-symptom from `TicketCategorisation_ProductivityTools.md`, you MUST pick exactly one **bold label** from the matching product's table below — copy it verbatim, do not paraphrase, do not invent a new label.
>
> **Output rule:** Always end your response with one root cause label in the strict output block:
> ```
> Possible Root Cause: <exact bold label from the chosen product's table>
> ```
> If no label in the chosen product's table fits, output exactly `Unknown` (no extra text, no `[NEW]` tag, no sentence).

---



## 1. Microsoft OneDrive Issues

| # | Root Cause Label | Description |
|---|---|---|
| 1.1 | **Sync Stall** | OneDrive client stuck/stopped on device; restart or sign-out/sign-in re-establishes sync. |
| 1.2 | **Long File Path Issue** | File/folder path exceeds OneDrive's 400-character limit or contains reserved characters, blocking sync. |
| 1.3 | **File Availability Setting** | "Always keep on this device" toggle or Error 0x80070032 prevents file copy/move to Samba or external location. |
| 1.4 | **Quota Storage Issue** | OneDrive for Business storage quota full; sync stops or orphaned folder inaccessible until quota is increased via Intel Service Catalog. |
| 1.5 | **OneDrive Client Failure** | OneDrive desktop client failed to launch or threw error 0x80070194; resolved by re-linking or fresh sign-in. |
| 1.6 | **Shared File Permission Denied** | User lacks a valid sharing permission entry on a SharePoint/OneDrive file; owner must remove and re-add. |
| 1.7 | **Stale or Revoked Share Link** | Share link expired, revoked, or points to content the user no longer has access to after a role change. |
| 1.8 | **PUID Mismatch** | Rejoined user's new account identity (PUID) does not match old SharePoint/OneDrive permission entries; owner must re-share under the new account. |
| 1.9 | **Prior OneDrive Site Expired** | Previous OneDrive site was not retained within the 30-day post-separation window and is permanently deleted. |
| 1.10 | **Former Employee Data Request** | File is in a separated employee's OneDrive; access requires a formal IT request within the 30-day retention window. |
| 1.11 | **SharePoint Site Quota Exceeded** | SharePoint site collection reached its storage quota; no uploads until the site owner raises a quota increase request. |
| 1.12 | **Rejoin Access Issue** | Rejoined user lost OneDrive access to prior content because old permissions did not transfer to the new identity. |
| 1.13 | **Missing Files After PC Refresh** | Files not re-synced to the new device after PC refresh because OneDrive client was not signed in or Known Folder Move was not re-enabled. |
| 1.14 | **OneDrive Sign-In / Connectivity Failure** | OneDrive client cannot authenticate or reach service endpoints; blocks login on user device. |
| 1.15 | **Known Folder Backup Failure** | OneDrive Known Folder Move (Desktop / Documents / Pictures backup) is paused, errored, or never completed. |
| 1.16 | **Offline Files Setting Issue** | "Always keep on this device" or offline availability setting misconfigured, causing local file not found / not synced. |

---

## 2. Microsoft 365 Apps for Enterprise Issues

| # | Root Cause Label | Description |
|---|---|---|
| 2.1 | **Corrupted Office Identity** | Cached credential or Office identity token corrupt; repeated sign-in prompts despite a valid license. |
| 2.2 | **F3 License Restriction** | F3 license blocks desktop M365 app activation; resolved by submitting "MSOL License - F3 License Exception" via AGS. |
| 2.3 | **Licensing Endpoint Unreachable** | Device offline or unable to reach licensing endpoints, blocking activation. |
| 2.4 | **Click-to-Run Installer Corruption** | Error 30015-xx indicates corrupted installer state; requires Quick/Online Repair or full reinstall. |
| 2.5 | **Company Portal Install Stuck** | M365 Apps installer hung in Company Portal; stalled process must be cleared before retry. |
| 2.6 | **AGS Entitlement Missing** | AGS entitlement for Microsoft 365 Apps install not granted on the user's account. |
| 2.7 | **License Not Assigned After Rejoin** | Office suite license not provisioned to the rejoined user's new identity. |
| 2.8 | **Usage Guidance (How Do I)** | No technical fault; user requested guidance, how-to instructions, or feature usage information for an M365 app. |
| 2.9 | **Office App Crash** | Office desktop app crashes on launch or during use; commonly resolved by Quick/Online Repair or profile reset. |
| 2.10 | **Office Compatibility Issue** | Document or feature fails due to version, OS, or third-party software compatibility mismatch. |
| 2.11 | **Sign-in / Login Failure** | User cannot sign in to the Office app despite a valid account; cached credential, MFA, or tenant trust failure. |
| 2.12 | **Office Activation Failure** | Office app shows "unlicensed product" or activation error despite an assigned license; activation handshake fails. |

---

## 3. Microsoft 365 Copilot Issues

| # | Root Cause Label | Description |
|---|---|---|
| 3.1 | **Copilot License Blackout** | Copilot entitlement hidden in AGS due to depleted license pool during a blackout/contract period. |
| 3.2 | **Copilot SKU Not Provisioned** | User not assigned the Copilot SKU for their region or business unit. |
| 3.3 | **License Propagation Delay** | Copilot license assigned but not yet propagated to M365 tenant (resolves in 30–60 minutes). |
| 3.4 | **ChunkLoadError / Stale Cache** | Stale or corrupted Teams client/web cache caused the Copilot component to fail loading. |
| 3.5 | **Phased Rollout Gate** | Copilot feature gated behind a rollout ring the tenant has not yet reached. |
| 3.6 | **Usage Guidance (How Do I)** | No technical fault; user needs documentation or training on Copilot capabilities. |
| 3.7 | **License Not Assigned After Rejoin** | Copilot license not provisioned to the rejoined user's new identity. |
| 3.8 | **Feature Inconsistency Across Apps** | Copilot works in some host apps (e.g., Word) but not others (e.g., Excel) for the same user due to per-app entitlement or rollout state mismatch. |


---

## 4. Microsoft Excel Issues

| # | Root Cause Label | Description |
|---|---|---|
| 4.1 | **Hung Excel Process** | Excel in a bad process state; ending EXCEL.EXE in Task Manager allows the workbook to open. |
| 4.2 | **Stale Desktop Cache** | Local Office file cache stale; web version shows newer content indicating a sync freshness issue. |
| 4.3 | **File Locked by Another User** | File locked by another user or by a stale lock from a prior crash. |
| 4.4 | **Corrupted Add-in** | Corrupted or incompatible Excel add-in causing data refresh failure or session instability. |
| 4.5 | **OLAP / Power BI Performance Issue** | OLAP query or Power BI data source performance degradation on desktop client only. |
| 4.6 | **Excel Performance Degradation** | Persistent Excel slowness/hang on user device; escalated to Microsoft after basic troubleshooting. |
| 4.7 | **Data Refresh Failure** | External data connection (Power Query, ODBC, web, OLAP) fails to refresh due to credentials, network, or source-side change. |
| 4.8 | **Underlying Data Permission Missing** | Formula returns #N/A or empty because the user lacks permission on the source dataset the workbook queries. |

---

## 5. Microsoft OneNote Issues

| # | Root Cause Label | Description |
|---|---|---|
| 5.1 | **Notebook Not Added on New Device** | Notebook not opened via File → Open → OneDrive on the new device after PC refresh or rejoin. |
| 5.2 | **Prior OneDrive Site Inaccessible** | Notebook hosted in a previous OneDrive site no longer accessible after rejoin or separation. |
| 5.3 | **Legacy Client Compatibility Issue** | Notebook created in older OneNote for Windows 10 client; sync incompatibility with modern OneNote app. |
| 5.4 | **OneNote Client Fault** | Local OneNote client fault; resolved by Office Quick/Online Repair. |
| 5.5 | **Hung OneNote Process** | OneNote stuck or unresponsive; ending the process and relaunching resolves it. |
| 5.6 | **OneNote Performance Degradation** | OneNote slow or laggy when opening large notebooks or syncing pages. |
| 5.7 | **OneNote Feature Not Working** | Specific OneNote feature (search, audio, drawing, tags, etc.) not functioning despite a working client. |
| 5.8 | **Missing Notes / Pages** | Specific notes, pages, or sections are missing from a notebook (sync failure, accidental deletion, or section group hidden). |
| 5.9 | **Data Loss After PC Refresh** | OneNote local-only content or cached notebooks lost after PC refresh because they were not synced to OneDrive/SharePoint. |

---

## 6. Shared File Service (Share Drives) Issues

| # | Root Cause Label | Description |
|---|---|---|
| 6.1 | **Mapped Drive Not Reconnected** | Mapped network drive lost after PC refresh; share must be remapped using the correct UNC path. |
| 6.2 | **Drive-Letter Conflict** | Drive-letter or resource conflict with another auto-mapped share prevents reconnect. |
| 6.3 | **Subfolder Permission Missing** | User has parent path access but not the requested subfolder; effective permissions inherit incorrectly. |
| 6.4 | **AGS Share Entitlement Missing** | AGS entitlement for the specific server/share not granted; access request required. |
| 6.5 | **File Deleted from Shared Drive** | File/folder deleted from the mapped drive; recovery requires NetApp snapshot/backup restore. |
| 6.6 | **Share Access Not Reapplied After Rejoin** | Rejoined user's mapped share drive access not restored to the new identity. |
| 6.7 | **Share Quota / Storage Exhausted** | Shared drive volume reached its storage quota; new writes fail until quota is increased or files are archived. |

---

## 7. Microsoft Forms Issues

| # | Root Cause Label | Description |
|---|---|---|
| 7.1 | **Forms Entitlement Missing** | "Microsoft Forms Creation Access" entitlement not enabled on the user's account. |
| 7.2 | **Poll Feature Not Loaded** | Poll feature not enabled or did not load correctly in Teams/Outlook until app was reopened. |
| 7.3 | **Forms Ownership Transfer Required** | Form is owned by a former employee or wrong owner; ownership must be transferred via Microsoft Forms admin process. |

---

## 8. Microsoft Word Issues

| # | Root Cause Label | Description |
|---|---|---|
| 8.1 | **Corporate Add-in Not Available** | IVO or other IT-managed Word add-in unavailable; requires add-in configuration refresh. |
| 8.2 | **Office Store Blocked by Policy** | Tenant policy disables the Office Store, preventing add-in installation through standard flow. |
| 8.3 | **Word Document Won't Open** | Document fails to open due to a path, lock, or trust-center protected-view issue (not corruption). |
| 8.4 | **Word File Corruption** | Word file body is corrupted; opens with errors or in recovery mode; Open and Repair or last good copy required. |
| 8.5 | **Hung Word Process** | Word stuck in a bad process state; ending WINWORD.EXE in Task Manager allows the document to open. |
| 8.6 | **Word Performance Degradation** | Persistent Word slowness/hang on user device; large documents, heavy formatting, or add-in interference. |
| 8.7 | **Word Formatting / Layout Issue** | Formatting, styles, layout, or page-structure misbehavior in the document (template, style set, or rendering issue). |
| 8.8 | **Usage Guidance (How Do I)** | No technical fault; user requested guidance or how-to instructions for a Word feature. |

---

## 9. Microsoft PowerPoint Issues

| # | Root Cause Label | Description |
|---|---|---|
| 9.1 | **PowerPoint Client Fault** | App-specific desktop client fault in PowerPoint; web version works normally. |
| 9.2 | **Incorrect File Path** | File path or location wrong or inaccessible; must navigate to correct path to open. |
| 9.3 | **Presentation Won't Open** | Presentation fails to open due to file lock, protected-view, or trust-center block (not corruption). |
| 9.4 | **PowerPoint File Corruption** | PPTX file body corrupted; opens with errors or recovery mode; Open and Repair or last good copy required. |
| 9.5 | **PowerPoint Formatting / Layout Issue** | Slide formatting, master, theme, or layout rendering issue in the deck. |
| 9.6 | **Media Embed Failure** | Embedded video, audio, or animation fails to play or render due to codec, link, or compatibility issue. |
| 9.7 | **Corporate Add-in Not Available** | IT-managed PowerPoint add-in unavailable; requires add-in configuration refresh. |

---

## 10. Microsoft Project Issues

| # | Root Cause Label | Description |
|---|---|---|
| 10.1 | **Project License / Entitlement Missing** | AGS entitlement for Microsoft Project not granted; user cannot install from Company Portal. |
| 10.2 | **Project Install Failure** | Microsoft Project install from Company Portal fails (Click-to-Run error, hung installer, or missing prerequisite). |
| 10.3 | **Project File Open / Save Failure** | .mpp file fails to open or save due to permission, lock, or path issue (not corruption). |
| 10.4 | **Project Schedule / Plan Corruption** | .mpp plan body corrupted; opens with errors or recovery mode; restore from last good copy required. |
| 10.5 | **Hung Project Process** | Microsoft Project stuck or unresponsive; ending WINPROJ.EXE resolves it. |
| 10.6 | **Project Performance Degradation** | Microsoft Project slow or laggy on large schedules or with many resources/links. |
| 10.7 | **Project Feature Not Working** | Specific Project feature (Gantt rendering, baseline, resource pool, report) not functioning. |

---

## 11. Google Workspace Issues

| # | Root Cause Label | Description |
|---|---|---|
| 11.1 | **Google Drive Upload Blocked by Policy** | User has "Google Documents Sharing" access but upload blocked by Intel IT policy; exception request required. |
| 11.2 | **Google Drive Quota Storage Issue** | Google Drive storage quota full; file uploads and new Doc/Sheet/Slide creation blocked. |
| 11.3 | **External Sharing Blocked by Policy** | Sharing Google Drive content with external (non-Intel) addresses blocked by Intel IT policy; exception request required. |
| 11.4 | **External Application Access Issue** | User cannot access a third-party Google Workspace integration or connected app due to OAuth, policy, or licensing. |
| 11.5 | **Gemini Access Issue** | User cannot access Gemini AI features due to licensing, regional rollout, or policy restriction. |

---

## 12. Microsoft Visio Issues

| # | Root Cause Label | Description |
|---|---|---|
| 12.1 | **Visio License Missing / Expired** | Visio Professional AGS entitlement not active; must be requested or renewed via AGS. |
| 12.2 | **Visio License Propagation Delay** | License assigned but not yet propagated to device; sign-out/in or 30–60 minute wait resolves. |
| 12.3 | **Visio AGS Entitlement Not Granted** | AGS entitlement not confirmed before Company Portal install attempt; entitlement must be granted first. |
| 12.4 | **Visio File Permission Denied** | Visio file in a SharePoint/OneDrive location with incorrect permissions; owner must re-share. |
| 12.5 | **Visio Activation Failure** | Visio activation fails after install (sign-in, licensing endpoint, or cached identity issue). |

---

## 13. Microsoft Loop Issues

| # | Root Cause Label | Description |
|---|---|---|
| 13.1 | **Loop Membership Not Provisioned** | M365 Group or Loop workspace membership not provisioned for the user's account. |
| 13.2 | **Stale Cache (Loop)** | Stale browser or Teams cache prevents Loop from loading. |
| 13.3 | **Loop Content Access Lost** | Loop content created in a context (Teams channel, M365 Group) the user was removed from. |
| 13.4 | **Loop App Not Enabled** | Loop app not enabled at tenant level for the user's license tier. |
| 13.5 | **Workspace Load Failure** | Loop workspace fails to load (blank, error, or infinite spinner) despite valid membership. |
| 13.6 | **Workspace Action Permission Denied** | User cannot delete or share a Loop workspace because they lack the owner/admin role required for the action. |

---

## 14. Microsoft 365 Groups / Planner / To Do Issues

| # | Root Cause Label | Description |
|---|---|---|
| 14.1 | **M365 Group Membership Removed** | User removed from M365 Group manually or via access review; re-add requires group owner or IT admin. |
| 14.2 | **No Active Group Owner** | Group has no active owner after a departure; ownership must be reassigned. |
| 14.3 | **Planner Plan Deleted** | Plan deleted when associated M365 Group was removed; recovery requires IT admin within soft-delete window. |
| 14.4 | **To Do Account Provisioning Delay** | To Do tasks not appearing due to incomplete M365 account provisioning or pending tenant sync. |

---

## 15. Smartsheet Issues

| # | Root Cause Label | Description |
|---|---|---|
| 15.1 | **Smartsheet Entitlement Missing** | Smartsheet AGS entitlement not granted; access must be requested via AGS. |
| 15.2 | **Removed from Sheet / Workspace** | User removed from Smartsheet sheet or workspace; re-invitation required from owner. |
| 15.3 | **External Sharing Blocked by Policy** | Intel IT policy blocks Smartsheet sharing with external (non-Intel) addresses by default. |
| 15.4 | **Connector / Integration Credential Failure** | Smartsheet connector (e.g., Salesforce, JIRA) stopped syncing due to a credential or permission change. |
| 15.5 | **Import File Format Issue** | Import file (Excel, CSV) is malformed or exceeds Smartsheet row/column limits. |

---

## 16. Canva Issues

| # | Root Cause Label | Description |
|---|---|---|
| 16.1 | **Canva Entitlement Missing** | Canva for Enterprise AGS entitlement not provisioned; access must be requested via catalog. |
| 16.2 | **SSO Account Not Linked** | Canva license assigned but Intel SSO account not linked to Canva org; IT admin provisioning required. |
| 16.3 | **Design Shared with Wrong Account** | Canva design shared with personal email instead of Intel SSO; owner must re-share with corporate email. |
| 16.4 | **Not Added to Canva Team** | User not a member of the correct Canva team or brand folder; brand templates invisible until membership is granted. |

---

## Cross-Cutting Patterns

| Root Cause Label | When to Apply |
|---|---|
| **Tenant License / SKU Blackout** | Feature hidden in AGS, no entitlement assignable (common with Copilot) |
| **Corrupted Local Office Client** | Multi-symptom Office issues; resolved by Quick/Online Repair or sign-out/in |
| **Long File Path Issue** | OneDrive/SharePoint 400-char path cap, reserved characters, long shortcut chains |
| **PUID Mismatch** | Rejoin/rehire PUID change breaks inherited permissions |
| **Mapped Drive vs OneDrive Confusion** | User reports OneDrive issue but root cause is SMB/shared drive |
| **Phased Rollout Gate** | Feature works for some users due to tenant ring assignment |
| **Stale Browser / Teams Cache** | ChunkLoadError and Copilot UI load failures |
| **Network Proxy / VPN Interference** | Intermittent licensing or sync endpoint failures |
| **Quota Storage Issue** | OneDrive, SharePoint, or Google Drive quota exhaustion stops sync/upload |
| **AGS Entitlement Missing** | Feature or app unavailable because the AGS entitlement was never requested or has expired |

---

## How to Use This Catalog

1. Pick the **Category** and **Sub-symptom** from `TicketCategorisation_ProductivityTools.md`.
2. Find the closest **Root Cause Label** from the matching product section above based on the actual evidence in the incident's work/close notes.
3. Output:

```
Possible Root Cause: **Root Cause Label**
```

If no entry fits, write a fresh sentence prefixed with `[NEW]`.


