# Detailed Root Cause Catalog - Productivity Tools

> **How to use this file:** The "Detailed Root Cause" column in the report must contain the **exact heading** of one of the entries below (verbatim, including capitalisation). Do not paraphrase the heading itself. Use the description and "When to pick this" notes to decide which one matches the incident, then write the descriptive sentence in the AI Analysis field.
>
> Headings are grouped by **Product Category** (from `TicketCategorisation_ProductivityTools.md`). Each entry is also tagged with its **Top Root Cause** bucket (from `TopRootCause_ProductivityTools.md`).
>
> If no existing heading fits the incident, output exactly `Unknown` for the Detailed Root Cause (no `[NEW]` tag, no new heading).

---

## Microsoft OneDrive Issues

### OneDrive client stopped syncing
**Top Root Cause:** Sync / Path Conflict
The OneDrive desktop client has stopped pushing or pulling changes (the cloud icon may show paused, signed-out, or red-X). Local cache and online site are out of step in either direction.
**Pick when:** "files visible locally but missing online", "files visible online but not on PC", icon shows paused / error, restart or re-link fixes it.

### Long path or filename conflict
**Top Root Cause:** Sync / Path Conflict
The file or folder path exceeds OneDrive's 400-character limit, contains reserved characters (`< > : " / \ | ? *`), or is created by a SharePoint shortcut chain that nests deeper than supported.
**Pick when:** rename / sync errors specifically on long paths or shortcuts.

### Cloud file provider error (0x80070194)
**Top Root Cause:** Sync / Path Conflict
The OneDrive sync client lost session state and reports `0x80070194`; re-linking OneDrive and resyncing fixes it.
**Pick when:** explicit `0x80070194` in notes, files cannot be opened from File Explorer.

### Files-On-Demand / selective sync exclusion
**Top Root Cause:** Sync / Path Conflict
The file exists in OneDrive online but the local client is not downloading it because of a selective-sync setting or Files-On-Demand placeholder issue.
**Pick when:** file is online but the local copy is missing or zero-byte placeholder.

### OneDrive storage quota exceeded
**Top Root Cause:** Data Recovery / Retention Window
The user's OneDrive for Business storage quota is full; the sync client stops syncing new or changed files, or an orphaned folder appears inaccessible until quota is increased via the Intel Service Catalog.
**Pick when:** sync stopped or folder inaccessible due to quota full; quota increase request is the resolution path.

### OneDrive client failed to launch
**Top Root Cause:** Client-Side Corruption / Stale State
The OneDrive.exe client cannot start on the device (no tray icon, no sign-in window), independent of any specific file or path.
**Pick when:** client never starts; reset / reinstall is required.

### Shared file permission denied
**Top Root Cause:** Permission / Sharing Misconfiguration
The user lacks a valid sharing permission entry on a SharePoint/OneDrive file; the owner must remove and re-add access for the current identity.
**Pick when:** access used to work, no role change, owner re-share fixes it; or link is valid but recipient has no share entry.

### User removed during access review
**Top Root Cause:** Permission / Sharing Misconfiguration
The user was removed from the shared content during a periodic access review; the owner re-adds them after the request.
**Pick when:** notes mention an access review or recent re-attestation.

### Permission not inherited from parent
**Top Root Cause:** Permission / Sharing Misconfiguration
The user has permission on the parent site or library but not on the specific subfolder or file because inheritance was broken.
**Pick when:** parent path is accessible but a specific item is not.

### Office app cannot open file due to missing share
**Top Root Cause:** Permission / Sharing Misconfiguration
PowerPoint, Excel, or Word cannot open the file because the user has no share entry; symptom appears as an "Office cannot open" error.
**Pick when:** Office throws a generic open error and the fix is sharing, not repair.

### SharePoint site quota exceeded
**Top Root Cause:** Data Recovery / Retention Window
The SharePoint site collection reached its storage quota; no new files can be uploaded or synced until the site owner raises a quota increase request.
**Pick when:** upload or sync errors scoped to a SharePoint site/library, not a personal OneDrive.

### Rehired with new account identity (PUID changed)
**Top Root Cause:** Identity / Account Lifecycle
The user was rehired with a new account, so the new PUID does not match the previous OneDrive / SharePoint identity; prior content is bound to the old PUID.
**Pick when:** user explicitly rejoined; previous data exists but is unreachable from the new account.

### Previous OneDrive site not retained
**Top Root Cause:** Data Recovery / Retention Window
The previous OneDrive site was not retained within the 30-day post-separation recovery window and was permanently deleted before rejoin.
**Pick when:** rejoin happened after retention window expired; data is gone.

### PUID / URL mapping mismatch
**Top Root Cause:** Identity / Account Lifecycle
SharePoint or OneDrive permissions cannot resolve to the rejoined account because of a PUID-to-URL mapping mismatch in the backend.
**Pick when:** permission entries exist but do not bind to the new identity.

### Stale permission entry on old identity
**Top Root Cause:** Permission / Sharing Misconfiguration
SharePoint or OneDrive sharing entries still point at the user's old identity; the owner must remove and re-add the user under the new account.
**Pick when:** fix is owner-side re-share after rejoin, not backend re-provisioning.

### Former-employee OneDrive data request
**Top Root Cause:** Data Recovery / Retention Window
The requested file is in a separated employee's personal OneDrive; access requires a formal IT request within the 30-day retention window.
**Pick when:** user is asking for data of someone who has left Intel, within the retention window.

### Rejoin access not reapplied to OneDrive
**Top Root Cause:** Identity / Account Lifecycle
The rejoined user lost OneDrive access to prior content because permissions on the previous identity were not transferred to the new account.
**Pick when:** user rejoined and OneDrive content from before is inaccessible despite a valid new account.

### Missing files after PC refresh (OneDrive)
**Top Root Cause:** Client-Side Corruption / Stale State
After a PC refresh the OneDrive client was not signed in or Known Folder Move was not re-enabled, so files did not re-sync down to the new device.
**Pick when:** files missing on a refreshed PC; resolved by signing into OneDrive and re-enabling Known Folder Move.

### OneDrive sign-in / connectivity failure
**Top Root Cause:** Network / Infrastructure
The OneDrive desktop client cannot authenticate or reach service endpoints; sign-in fails or repeats and sync never starts.
**Pick when:** user cannot sign into OneDrive client; network, proxy, or auth handshake is the cause.

### Known Folder Backup failure
**Top Root Cause:** Sync / Path Conflict
OneDrive Known Folder Move (Desktop / Documents / Pictures backup) is paused, errored, or never completed; folder backup is not protecting user data.
**Pick when:** backup of Desktop/Documents/Pictures shows paused or errored in OneDrive settings.

### Offline files setting misconfigured
**Top Root Cause:** Sync / Path Conflict
"Always keep on this device" or offline availability setting is misconfigured, leaving files as cloud-only placeholders or causing local-not-found errors.
**Pick when:** file expected offline but is a placeholder, or vice versa; toggling availability fixes it.

---

## Microsoft 365 Apps for Enterprise Issues

### Corrupted Office installation
**Top Root Cause:** Client-Side Corruption / Stale State
The local Click-to-Run install is corrupt - one or more apps will not launch, UI renders incorrectly, or repair is required.
**Pick when:** Office Repair (Quick or Online) resolved the issue; multiple Office apps affected; UI rendering broken.

### Corrupted Office identity / cached credential
**Top Root Cause:** Client-Side Corruption / Stale State
Cached Office credentials on the device are corrupt; sign-in or activation fails despite a valid license. Clearing identity cache or running `dsregcmd` / re-signing fixes it.
**Pick when:** sign-in loop, activation prompt repeats, fix is identity reset rather than full reinstall.

### F3 license restriction
**Top Root Cause:** License / Entitlement Missing
The user holds an F3 SKU, which blocks desktop M365 app activation until an F3 License Exception or higher SKU is granted.
**Pick when:** activation explicitly denied due to F3; license exception is the resolution path.

### Activation endpoint unreachable
**Top Root Cause:** Network / Infrastructure
The device cannot reach M365 licensing endpoints (offline, proxy, VPN, firewall) so activation never completes.
**Pick when:** activation fails with network error; works on a different network.

### Click-to-Run installer hung in Company Portal
**Top Root Cause:** Installation / Update Failure
The M365 Apps install is stalled in Company Portal; the stuck OfficeClickToRun process must be cleared and the install retried.
**Pick when:** install never finishes, no error code, fix is killing the install task.

### Click-to-Run error 30015-xx
**Top Root Cause:** Installation / Update Failure
A `30015-xx` Click-to-Run error indicates a corrupted installer or update state requiring uninstall + clean reinstall.
**Pick when:** explicit `30015-` code in notes.

### Stale Office / Teams cached state
**Top Root Cause:** Client-Side Corruption / Stale State
Local Office or Teams cache is stale and causing intermittent launch or sign-in instability across multiple apps; clearing cache resolves it.
**Pick when:** fix was cache clear / sign-out-sign-in (not full repair).

### M365 Apps license not assigned after rejoin
**Top Root Cause:** License / Entitlement Missing
The Office suite license was not provisioned to the rejoined user's new identity; activation fails until the entitlement is re-granted in AGS.
**Pick when:** user rejoined and Office desktop apps show unlicensed / activation prompt.

### Office usage / how-to question
**Top Root Cause:** User Education / How-Do-I
No technical fault; user requested guidance, how-to instructions, or feature usage information for an M365 app (Word, Excel, Outlook, etc.).
**Pick when:** the ticket is a question about how to use a feature, not a fix request.

### Office app crash
**Top Root Cause:** App-Specific Performance / Crash
An Office desktop app crashes on launch or during use; commonly resolved by Quick/Online Repair, profile reset, or disabling a faulty add-in.
**Pick when:** app exits unexpectedly, event log shows app crash, fix is repair or profile reset.

### Office compatibility issue
**Top Root Cause:** Client-Side Corruption / Stale State
A document or feature fails due to a version, OS, or third-party software compatibility mismatch (older format, unsupported OS, add-in conflict).
**Pick when:** issue is tied to version / OS / third-party tool mismatch rather than corruption or license.

### Office sign-in / login failure
**Top Root Cause:** Client-Side Corruption / Stale State
User cannot sign in to an Office app despite a valid account; cached credentials, MFA, or tenant trust handshake fails.
**Pick when:** sign-in repeatedly fails or loops in an Office app and fix is credential / identity reset.

### Office activation failure
**Top Root Cause:** License / Entitlement Missing
Office app shows "unlicensed product" or activation error despite an assigned license; activation handshake to licensing endpoints fails.
**Pick when:** activation banner persists, license is confirmed in AGS, and resolution involves activation reset / endpoint reachability.

---

## Microsoft 365 Copilot Issues

### Copilot licence blackout (pool depleted)
**Top Root Cause:** License / Entitlement Missing
The Copilot license pool is depleted and the entitlement is hidden in AGS during a blackout window, so it cannot be assigned to new users.
**Pick when:** AGS shows no Copilot SKU available, support cites blackout, request is queued.

### Copilot SKU not provisioned for region / BU
**Top Root Cause:** License / Entitlement Missing
The Copilot SKU is not yet rolled out to the user's region or business unit, so the entitlement cannot be requested through normal channels.
**Pick when:** user is in a region or BU where Copilot is not yet generally available.

### Copilot licence assigned but not propagated
**Top Root Cause:** License / Entitlement Missing
The Copilot license was assigned in AGS / M365 admin but tenant propagation has not completed (typically 30-60 minutes), so the client still reports no entitlement.
**Pick when:** entitlement is visible in AGS but Copilot still not visible to the user.

### Copilot ChunkLoadError (stale browser / Teams cache)
**Top Root Cause:** Client-Side Corruption / Stale State
A stale or corrupted Teams desktop or web cache prevents the Copilot UI chunk from loading; clearing cache resolves it.
**Pick when:** explicit `ChunkLoadError` or Copilot UI failing to render.

### Copilot phased rollout ring
**Top Root Cause:** Tenant Policy / Phased Rollout
The Copilot feature is gated behind a tenant rollout ring the user's tenant has not yet reached.
**Pick when:** user has the licence but the feature is still not visible because rollout is incomplete.

### Copilot usage / how-to question
**Top Root Cause:** User Education / How-Do-I
The user needs guidance on Copilot capabilities (summarise meetings, draft email, prompt syntax), not a technical fix.
**Pick when:** "how do I use Copilot" type questions.

### Copilot license not assigned after rejoin
**Top Root Cause:** License / Entitlement Missing
The Copilot license was not provisioned to the rejoined user's new identity; must be re-requested via AGS.
**Pick when:** user rejoined and Copilot is missing specifically due to identity change, not a general blackout.

### Copilot feature inconsistency across apps
**Top Root Cause:** Tenant Policy / Phased Rollout
Copilot works in some host apps (e.g., Word) but not others (e.g., Excel) for the same user due to per-app entitlement or rollout state mismatch.
**Pick when:** Copilot appears in one M365 app but is missing or broken in another for the same user.

---

## Microsoft Excel Issues

### Excel stuck in hung process
**Top Root Cause:** Client-Side Corruption / Stale State
Excel is in a bad / hung process state; ending the Excel task allows the workbook to open.
**Pick when:** workbook opens after a task-kill / sign-out cycle.

### Stale Excel desktop cache
**Top Root Cause:** App-Specific Performance / Crash
The desktop client cache is stale - the web version shows newer content than the desktop. Indicates a desktop sync freshness problem, not a corrupt workbook.
**Pick when:** "desktop shows old content, web shows new" pattern.

### Excel desktop performance degradation
**Top Root Cause:** App-Specific Performance / Crash
Excel desktop is slow or unresponsive on the user's device with no specific workbook or add-in implicated; persists after basic troubleshooting.
**Pick when:** persistent slowness, escalated to Microsoft.

### Corrupted Excel add-in
**Top Root Cause:** Add-in / Extension Issue
A specific Excel add-in (Power BI publisher, IVO, third-party) is unstable; running Excel in Safe Mode bypasses the issue.
**Pick when:** Safe Mode resolves it, or a named add-in is the trigger.

### OLAP / Power BI data refresh slowness
**Top Root Cause:** App-Specific Performance / Crash
OLAP queries or Power BI data refresh are slow on Excel desktop while the web version works normally, indicating an Excel-specific data path issue.
**Pick when:** slowness only on desktop OLAP / Power BI flows.

### Underlying data permission missing (returns #N/A)
**Top Root Cause:** Permission / Sharing Misconfiguration
The user lacks read permission on the referenced sheet or workbook, so lookups return `#N/A` even though the host workbook opens.
**Pick when:** `#N/A` or empty cells with a clear permission cause.

### Excel data refresh failure
**Top Root Cause:** App-Specific Performance / Crash
An external data connection (Power Query, ODBC, web, OLAP) fails to refresh due to credentials, network, or source-side schema/permission change.
**Pick when:** refresh on a specific connection errors out; web/source works but Excel refresh fails.

---

## Microsoft OneNote Issues

### Notebook not added on new device
**Top Root Cause:** Client-Side Corruption / Stale State
After a PC refresh or new laptop the OneNote notebook has not been added or opened in the OneNote app, so cached pages are not present locally.
**Pick when:** "new laptop, OneNote content missing" - resolved by adding the notebook in the app.

### Notebook hosted on inaccessible OneDrive
**Top Root Cause:** Identity / Account Lifecycle
The notebook lives in a previous OneDrive site that is no longer accessible after rejoin or refresh; underlying issue is identity / OneDrive access, not OneNote.
**Pick when:** notebook is missing because the OneDrive site itself is unavailable.

### OneNote Windows 10 client compatibility
**Top Root Cause:** Sync / Path Conflict
The notebook was created in an older OneNote for Windows 10 client and is not syncing correctly with the modern OneNote app.
**Pick when:** notebook created in Win10 client; migration to current OneNote fixes sync.

### OneNote client launch failure
**Top Root Cause:** Client-Side Corruption / Stale State
A local Office / OneNote client fault prevents OneNote from launching; Office Repair resolves it.
**Pick when:** OneNote will not start - fix was Office Repair.

### OneNote stuck in hung process
**Top Root Cause:** App-Specific Performance / Crash
OneNote is stuck or unresponsive; ending the OneNote process and relaunching allows the notebook to open.
**Pick when:** OneNote becomes unresponsive and a task-kill restores it.

### OneNote performance degradation
**Top Root Cause:** App-Specific Performance / Crash
OneNote is slow or laggy when opening large notebooks, syncing pages, or rendering ink/media.
**Pick when:** persistent OneNote slowness, especially with large notebooks.

### OneNote feature not working
**Top Root Cause:** App-Specific Performance / Crash
A specific OneNote feature (search, audio, drawing, tags, etc.) is not functioning despite a working client.
**Pick when:** client launches fine but one feature is broken.

### Missing notes or pages in notebook
**Top Root Cause:** Sync / Path Conflict
Specific notes, pages, or sections are missing from a notebook due to sync failure, accidental deletion, or a hidden section group.
**Pick when:** notebook opens but expected content is missing; cause is sync gap or deletion, not whole-notebook loss.

### OneNote data loss after PC refresh
**Top Root Cause:** Data Recovery / Retention Window
OneNote local-only content or cached notebooks were lost after PC refresh because they were not synced to OneDrive / SharePoint before the refresh.
**Pick when:** user lost OneNote content after PC refresh and the notebook was not cloud-backed.

---

## Shared File Service (Share Drives) Issues

### Drive remap required after PC change
**Top Root Cause:** Network / Infrastructure
Mapped network drives did not reconnect after PC refresh or computer change; the share must be remapped using the correct UNC path.
**Pick when:** drive letter missing after PC change.

### Drive-letter / resource conflict
**Top Root Cause:** Network / Infrastructure
A drive-letter or resource conflict with another auto-mapped share is preventing the requested share from connecting.
**Pick when:** clash between scripts or GPO drive mappings.

### Missing AGS entitlement for share
**Top Root Cause:** License / Entitlement Missing
The user does not have the AGS entitlement for the specific server or share path; access request resolves it.
**Pick when:** entitlement add is the resolution path.

### Subfolder permission missing
**Top Root Cause:** Permission / Sharing Misconfiguration
The user has access to the parent path but inherits no permission on a requested subfolder or file.
**Pick when:** parent accessible, child denied.

### File or folder deleted on share
**Top Root Cause:** Data Recovery / Retention Window
The folder or file was deleted on a mapped or shared drive and must be restored by the Shared Drive Team from a NetApp snapshot or backup.
**Pick when:** file is missing because it was deleted, recovery from backup is required.

### Share access not reapplied after rejoin
**Top Root Cause:** Identity / Account Lifecycle
The rejoined user's mapped share drive access was not restored to the new identity; AGS entitlement must be re-requested and GPO re-applied.
**Pick when:** rejoin is confirmed and the specific symptom is missing share drive access.

### Shared drive quota / storage exhausted
**Top Root Cause:** Data Recovery / Retention Window
The shared drive volume has reached its storage quota; new writes fail until quota is increased or files are archived.
**Pick when:** writes to a share fail with quota / out-of-space error.

---

## Microsoft Forms Issues

### Forms Creation Access entitlement missing
**Top Root Cause:** License / Entitlement Missing
The user lacks the Microsoft Forms Creation Access entitlement on their account.
**Pick when:** Forms portal denies creation; fix is enabling the entitlement.

### Outlook / Teams poll not loading
**Top Root Cause:** Client-Side Corruption / Stale State
The poll feature in the host app was not enabled or did not load until the app was reopened or signed in fresh.
**Pick when:** poll button missing or grey until restart.

### Forms ownership transfer required
**Top Root Cause:** Identity / Account Lifecycle
The form is owned by a former employee or the wrong owner; ownership must be transferred via the Microsoft Forms admin process before changes can be made.
**Pick when:** form cannot be edited because its owner has left or is incorrect.

---

## Microsoft Word Issues

### Word add-in not deployed by IT
**Top Root Cause:** Add-in / Extension Issue
The Word add-in (e.g., IVO) is not available until IT-managed add-in configuration is updated and refreshed for the user.
**Pick when:** add-in missing; IT push or refresh fixes it.

### Office Store disabled by tenant policy
**Top Root Cause:** Tenant Policy / Phased Rollout
The Office Store is disabled by an organisation-wide policy, blocking standard add-in installation.
**Pick when:** user cannot install any Store add-in; tenant policy is the gate.

### Word document won't open
**Top Root Cause:** Client-Side Corruption / Stale State
A Word document fails to open due to a path, file lock, or Trust Center protected-view block (not file corruption).
**Pick when:** document refuses to open but the file itself is intact; fix is path, lock release, or trust setting.

### Word file corruption
**Top Root Cause:** App-Specific Performance / Crash
The Word file body is corrupted; document opens with errors or in recovery mode. Open and Repair or restoring the last good copy is required.
**Pick when:** file is corrupted; recovery / repair is the fix.

### Word stuck in hung process
**Top Root Cause:** Client-Side Corruption / Stale State
Word is stuck in a bad / hung process state; ending WINWORD.EXE in Task Manager allows the document to open.
**Pick when:** document opens after a Word task-kill / restart cycle.

### Word performance degradation
**Top Root Cause:** App-Specific Performance / Crash
Persistent Word slowness or hangs on the user's device, often with large documents, heavy formatting, or add-in interference.
**Pick when:** persistent Word slowness or hang, not a one-off freeze.

### Word formatting / layout issue
**Top Root Cause:** App-Specific Performance / Crash
Formatting, styles, layout, or page-structure misbehavior in a Word document due to template, style set, or rendering issue.
**Pick when:** document opens but layout/formatting renders incorrectly.

### Word usage / how-to question
**Top Root Cause:** User Education / How-Do-I
No technical fault; user requested guidance or how-to instructions for a Word feature.
**Pick when:** ticket is a Word feature question, not a fix.

---

## Microsoft PowerPoint Issues

### PowerPoint desktop-only crash
**Top Root Cause:** App-Specific Performance / Crash
PowerPoint desktop crashes on launch while other Microsoft 365 apps and PowerPoint web work normally - an app-specific desktop fault.
**Pick when:** only PowerPoint desktop is affected.

### Presentation path not reachable
**Top Root Cause:** Network / Infrastructure
The file path or location stored in the link is incorrect or no longer reachable from PowerPoint; support navigates to the correct path.
**Pick when:** file open fails because the path itself is wrong, not because of permissions.

### Presentation won't open
**Top Root Cause:** Client-Side Corruption / Stale State
A presentation fails to open due to file lock, Protected View, or Trust Center block (not file corruption).
**Pick when:** PPTX refuses to open but the file is intact; fix is unblock, unlock, or trust setting.

### PowerPoint file corruption
**Top Root Cause:** App-Specific Performance / Crash
The PPTX file body is corrupted; presentation opens with errors or in recovery mode. Open and Repair or restoring the last good copy is required.
**Pick when:** presentation is corrupted; recovery / repair is the fix.

### PowerPoint formatting / layout issue
**Top Root Cause:** App-Specific Performance / Crash
Slide formatting, master, theme, or layout rendering issue in the deck.
**Pick when:** presentation opens but slide layout or formatting renders incorrectly.

### PowerPoint media embed failure
**Top Root Cause:** App-Specific Performance / Crash
Embedded video, audio, or animation fails to play or render due to codec, broken link, or compatibility issue.
**Pick when:** embedded media is the symptom; non-media slides render normally.

### PowerPoint add-in not deployed by IT
**Top Root Cause:** Add-in / Extension Issue
An IT-managed PowerPoint add-in is unavailable until add-in configuration is refreshed for the user.
**Pick when:** PowerPoint add-in missing; IT push or refresh fixes it.

---

## Microsoft Project Issues

### Project install entitlement missing
**Top Root Cause:** License / Entitlement Missing
The user lacks the AGS entitlement required to install Microsoft Project from Company Portal.
**Pick when:** install denied for entitlement reasons.

### Project install failure
**Top Root Cause:** Installation / Update Failure
Microsoft Project install from Company Portal fails (Click-to-Run error, hung installer, or missing prerequisite).
**Pick when:** install errors out or hangs even though entitlement is in place.

### Project file open / save failure
**Top Root Cause:** Client-Side Corruption / Stale State
An .mpp file fails to open or save due to permission, lock, or path issue (not corruption).
**Pick when:** .mpp open/save fails for path/permission/lock reasons; file itself is intact.

### Project schedule / plan corruption
**Top Root Cause:** App-Specific Performance / Crash
The .mpp plan body is corrupted; opens with errors or recovery mode and restoring from last good copy is required.
**Pick when:** plan is corrupted; recovery / restore is the fix.

### Project stuck in hung process
**Top Root Cause:** Client-Side Corruption / Stale State
Microsoft Project is stuck or unresponsive; ending WINPROJ.EXE allows the plan to open.
**Pick when:** Project unresponsive and a task-kill restores it.

### Project performance degradation
**Top Root Cause:** App-Specific Performance / Crash
Microsoft Project is slow or laggy on large schedules or with many resources/links.
**Pick when:** persistent Project slowness, especially with large plans.

### Project feature not working
**Top Root Cause:** App-Specific Performance / Crash
A specific Project feature (Gantt rendering, baseline, resource pool, report) is not functioning despite a working client.
**Pick when:** client launches and plan opens but one feature is broken.

---

## Google Workspace Issues

### Google Drive upload blocked by IT policy
**Top Root Cause:** Tenant Policy / Phased Rollout
Google Drive upload is blocked by Intel IT policy; a formal access exception is required even though Documents Sharing access is enabled.
**Pick when:** upload denied by policy; exception request is the resolution.

### Google Drive storage quota exceeded
**Top Root Cause:** Data Recovery / Retention Window
The user's Google Drive storage quota is full, blocking new file uploads and creation of Docs, Sheets, or Slides.
**Pick when:** Google Drive uploads fail or new files cannot be created due to quota exhaustion.

### Google external sharing blocked by policy
**Top Root Cause:** Tenant Policy / Phased Rollout
Sharing Google Drive content with external (non-Intel) addresses is blocked by Intel IT policy; a formal exception request is required.
**Pick when:** external sharing invitation to a non-Intel address is blocked.

### Google external application access issue
**Top Root Cause:** Tenant Policy / Phased Rollout
User cannot access a third-party Google Workspace integration or connected app due to OAuth scope, policy, or licensing.
**Pick when:** a Google-connected third-party app fails to authorise or load.

### Gemini access issue
**Top Root Cause:** License / Entitlement Missing
User cannot access Gemini AI features due to licensing, regional rollout, or policy restriction.
**Pick when:** Gemini features missing or denied despite a working Google Workspace account.

---

## Microsoft Visio Issues

### Visio license missing or expired
**Top Root Cause:** License / Entitlement Missing
The Visio Professional AGS entitlement is not active; the license must be requested or renewed via AGS before Visio can be activated from Company Portal.
**Pick when:** Visio shows "unlicensed" or Company Portal install is denied due to missing entitlement.

### Visio license propagation delay
**Top Root Cause:** License / Entitlement Missing
The Visio license was assigned in AGS but has not yet propagated to the device; sign-out/in or a 30-60 minute wait resolves activation.
**Pick when:** entitlement approved in AGS but Visio still shows activation failure immediately after approval.

### Visio file permission denied
**Top Root Cause:** Permission / Sharing Misconfiguration
The Visio file is stored in a SharePoint or OneDrive location with incorrect permissions; opening fails until the owner re-shares with the correct account.
**Pick when:** Visio file cannot be opened and the fix is a permission re-share, not a license fix.

### Visio activation failure
**Top Root Cause:** License / Entitlement Missing
Visio activation fails after install due to sign-in, licensing endpoint, or cached identity issue, despite an assigned license.
**Pick when:** Visio shows activation error after a successful install and license is confirmed in AGS.

---

## Microsoft Loop Issues

### Loop membership not provisioned
**Top Root Cause:** License / Entitlement Missing
The user's M365 Group or Loop workspace membership has not been provisioned; the Loop workspace is invisible or inaccessible.
**Pick when:** Loop workspace does not appear and membership grant is the fix.

### Stale cache preventing Loop load
**Top Root Cause:** Client-Side Corruption / Stale State
A stale browser or Teams client cache prevents Loop from loading; clearing cache or opening in a private window resolves it.
**Pick when:** Loop page fails to render; private window or cache clear fixes it.

### Loop content access lost
**Top Root Cause:** Permission / Sharing Misconfiguration
Loop content was created in a Teams channel or M365 Group the user was subsequently removed from; the content is inaccessible until membership is restored.
**Pick when:** Loop content existed but is now inaccessible after a group membership change.

### Loop app not enabled for license tier
**Top Root Cause:** Tenant Policy / Phased Rollout
The Loop app is not enabled at the tenant level for the user's license tier; the workspace cannot be created or accessed.
**Pick when:** Loop is unavailable across the org or for a specific license group.

### Loop workspace load failure
**Top Root Cause:** Client-Side Corruption / Stale State
A Loop workspace fails to load (blank, error, or infinite spinner) despite valid membership; cache, network, or service-side rendering failure.
**Pick when:** workspace will not render despite confirmed access.

### Loop workspace action permission denied
**Top Root Cause:** Permission / Sharing Misconfiguration
User cannot delete or share a Loop workspace because they lack the owner / admin role required for the action.
**Pick when:** user can open the workspace but delete or share action is denied due to role.

---

## Microsoft 365 Groups / Planner / To Do Issues

### M365 Group membership removed
**Top Root Cause:** Identity / Account Lifecycle
The user was removed from the M365 Group manually or via an access review; re-adding requires the group owner or IT admin.
**Pick when:** user lost access to a Teams channel, Planner board, or SharePoint site backed by an M365 Group.

### No active group owner
**Top Root Cause:** Identity / Account Lifecycle
The M365 Group has no active owner following a departure; ownership must be reassigned before group settings can be changed or membership managed.
**Pick when:** group owner is a departed employee and no changes can be made.

### Planner plan deleted with group
**Top Root Cause:** Data Recovery / Retention Window
The Planner plan was deleted when the associated M365 Group was removed; recovery requires IT admin action within the soft-delete window.
**Pick when:** Planner board is missing after a group deletion event.

### To Do account provisioning delay
**Top Root Cause:** License / Entitlement Missing
To Do tasks are not appearing in the Teams Tasks app because the M365 account is not fully provisioned or the tenant sync has not completed.
**Pick when:** tasks missing immediately after account creation or rejoin.

---

## Smartsheet Issues

### Smartsheet entitlement missing
**Top Root Cause:** License / Entitlement Missing
The Smartsheet AGS entitlement is not granted; the user cannot log in to Smartsheet until the entitlement is requested and the group sync completes (up to 4 hours).
**Pick when:** Smartsheet login denied; AGS entitlement add is the fix.

### Removed from Smartsheet sheet or workspace
**Top Root Cause:** Permission / Sharing Misconfiguration
The user was removed from the Smartsheet sheet or workspace by the owner; re-invitation is required.
**Pick when:** user had access previously and was removed, not a license issue.

### Smartsheet external sharing blocked
**Top Root Cause:** Tenant Policy / Phased Rollout
Intel IT policy blocks Smartsheet sharing with external (non-Intel) email addresses; a formal exception request is required.
**Pick when:** sharing invitation to an external address is blocked.

### Smartsheet connector credential failure
**Top Root Cause:** Network / Infrastructure
A Smartsheet connector or integration (e.g., Salesforce, JIRA) stopped syncing due to a credential or permission change on the connected service.
**Pick when:** Smartsheet data sync stopped after a password change or permission update on the source system.

### Smartsheet import file format issue
**Top Root Cause:** User Education / How-Do-I
The import file (Excel, CSV) is malformed or exceeds Smartsheet row/column limits, causing the import to fail.
**Pick when:** import fails with a format or size error, not a permission or license issue.

---

## Canva Issues

### Canva entitlement missing
**Top Root Cause:** License / Entitlement Missing
The Canva for Enterprise AGS entitlement is not provisioned; the user cannot log in until the entitlement is requested via the standard AGS workflow.
**Pick when:** Canva login denied or user has no org account; entitlement request is the fix.

### Canva SSO account not linked
**Top Root Cause:** Identity / Account Lifecycle
The Canva license was assigned but the user's Intel SSO account has not been linked to the Canva org; IT admin provisioning is required.
**Pick when:** user has the entitlement but cannot log in via SSO; admin provisioning resolves it.

### Canva design shared with wrong account
**Top Root Cause:** Permission / Sharing Misconfiguration
A Canva design was shared with a personal email instead of the Intel SSO account; the owner must re-share using the corporate email.
**Pick when:** design is inaccessible because the share target is a personal email.

### Not added to Canva team
**Top Root Cause:** Permission / Sharing Misconfiguration
The user is not a member of the correct Canva team or brand folder; brand templates and shared assets are invisible until membership is granted by the team admin.
**Pick when:** user can log in but brand kits or team designs are missing.
