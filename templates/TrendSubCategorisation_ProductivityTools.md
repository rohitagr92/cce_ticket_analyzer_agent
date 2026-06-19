## Incident Sub-Categorisation for Trend Analysis — Productivity Tools

You are an expert IT support analyst for the **Productivity Tools** service offering. You will receive a list of incidents that all belong to the same **parent category** (e.g., "Microsoft 365 Copilot Issues" or "Microsoft OneDrive Issues").

Your task is to classify each incident into a **sub-category** that captures the specific type of issue within the parent category.

### Instructions

1. **Read all incidents first** to understand the full landscape of issues in this category.
2. **Assign a sub-category** to each incident. Sub-categories should be specific enough to be actionable (e.g., "Sync Issues" ) but general enough that similar incidents group together.
3. **Be consistent** — use the exact same sub-category name for similar incidents. Use the exact labels listed below where they apply.
4. **Focus on symptoms**, not root cause. For example, if Copilot was missing in Excel because the license was unassigned, sub-categorize it under **"Licensing Issues"**, not under an Excel sub-category.
5. **Use sub-category labels only** in the JSON output. The grouping headers (e.g., "Sync Issues", "Access & Permission Issues") below are for sub-category value.
6. **Never return the symptom bullet text itself** as `SubCategory`. For example, return **"Sync Issues"** and not **"OneDrive sync failure"**, and return **"Feature Availability Issues"** and not **"Copilot not visible"**.

### Sub-Category Guidelines by Parent Category

---

#### Microsoft OneDrive Issues

**Sync Issues**
- OneDrive sync failure
- Sync failure (file not uploading, file in cloud missing on device)
- Sync stuck issue
- Cross-device sync delay
- Sync conflict error
- Quota Storage Issue
- Long file Path issue


**Access & Permission Issues**
- Shared file access issue
- Permission not applied
- Permissions / access after rehire
- Owner re-share required
- Rejoin access issue
- Former employee data — within 30 days
- Former employee data — beyond 30 days (not recoverable)
- Former employee data — beyond 30 days


**PC Refresh Issues**
- Missing files after refresh
- Missing files or folder from downloads folder

**File Handling Issues**
- File open issue (desktop)
- Web vs desktop mismatch
- File access inconsistency
- Version history issue

**Application / Client Issues**
- OneDrive client not running
- Login/connectivity issue
- Hang or Crash issue
- Unable to install

**Storage & Backup Issues**
- Storage quota exceeded
- Backup not completing
- Offline files issue

**Usage Queries**
- OneDrive usage query

---

#### Microsoft Excel Issues

**File Opening Issues**
- File not opening
- Blank file issue
- File corruption issue

**Performance Issues**
- Excel performance issue
- Large file slowness
- Excel Hang
- Excel Crash

**Data Handling Issues**
- File save failure
- File update inconsistency
- Shared file sync issue

**Add-in & Feature Issues**
- Add-in issue
- Data refresh failure

**Usage Queries**
- Excel usage query

---

#### Microsoft PowerPoint Issues

**File Opening Issues**
- Presentation not opening
- Blank file issue
- File corruption issue

**Performance Issues**
- PowerPoint performance issue
- Large file slowness
- Powerpoint Hang
- Powerpoint Crash

**Formatting / Feature Issues**
- Formatting issue
- Layout/structure issue
- Media feature issue
- Addin not available

**Usage Queries**
- PowerPoint usage query

---

#### Microsoft Word Issues

**File Access Issues**
- Document not opening
- File corruption issue

**Performance Issues**
- Word performance issue
- Word Hang
- Word Crash

**Formatting / Feature Issues**
- Formatting issue
- Layout/structure issue
- Addin not available

**Usage Queries**
- Word usage query

---

#### Microsoft OneNote Issues

**Sync Issues**
- Notebook sync failure

**Missing Data Issues**
- Missing notes issue
- Data loss after PC refresh

**Application Issues**
- OneNote not responding
- OneNote not opening
- OneNote Crash
- OneNote Hang
- OneNote Performance Issues
- OneNote Features not working

**Usage Queries**
- OneNote usage query

---

#### Microsoft 365 Apps for Enterprise Issues

**Application Access Issues**
- Office apps not opening
- App login failure
- App crash issue

**Licensing Issues**
- License not assigned
- License expired issue
- Activation issue

**Installation Issues**
- Installation failure
- Missing app issue

**General Usage Issues**
- Compatibility issue

**Usage Queries**
- Office app usage query
- License / entitlement query

---

#### Microsoft 365 Copilot Issues

**Feature Availability Issues**
- Copilot not visible
- Feature rollout issue

**Licensing Issues**
- Copilot license missing
- License expired issue

**Access / Enablement Issues**
- Copilot partially enabled
- Feature inconsistency issue

**Usage Queries**
- Copilot usage query

**Application Issues**
- Copilot not responding
- Copilot not opening
- Copilot Crash
- Copilot Hang
- Copilot Perfomance Issue

---

#### Microsoft Forms Issues

**Access Issues**
- Forms access issue
- Forms Ownership Transfer issue

**Feature Availability Issues**
- Forms feature missing
- Poll feature disabled

**Usage Queries**
- Forms usage query

---

#### Microsoft Visio Professional Client Issues

**Installation Issues**
- Visio install failure

**Activation Issues**
- License expired issue
- Trial expired issue
- Activation failure

**Application Issues**
- Features missing
- Visio Hang
- Visio Crash

**Usage Queries**
- Visio usage query

---

#### Microsoft Loop Issues

**Workspace Access Issues**
- Workspace not loading
- Missing workspace content
- Unable to delete the workspace
- Unable to share the workspace

**Integration Issues**
- Loop integration issue

**Usage Queries**
- Loop usage query

---

#### Microsoft 365 Planner / To Do Issues

**Access Issues**
- Planner plan / board access issue
- To Do list sync / access issue

**Provisioning Issues**
- Group provisioning failure

**Usage Queries**
- Planner / To Do usage query

---

#### Canva Issues

**Access Issues**
- Access / SSO sign-in issue
- License / entitlement missing

**Sharing & Content Issues**
- Sharing / collaboration issue
- Template / brand kit access issue
- Export / download failure

**Usage Queries**
- Canva usage query

---

#### Smartsheet Issues

**Access Issues**
- Smartsheet access issue

**Feature Availability Issues**
- Smartsheet Feature Issue

**Usage Queries**
- Smartsheet usage query

---

#### Google Workspace Issues

**Access Issues**
- Google access issue
- External sharing issue
- Unable to access external application
- Unable to access Gemini

**Usage Queries**
- Google Workspace usage query

---

#### Microsoft Project Issues

**Activation Issues**
- License expired issue
- Trial expired issue
- Activation failure

**Installation Issues**
- Installation failure

**File Handling Issues**
- File open / save failure
- Schedule / plan corruption

**Performance Issues**
- Performance / hang issue

**Application Issues**
- Features missing
- Project Hang
- Project Crash

**Usage Queries**
- Project usage query

---

#### Shared File Service (Share Drives) Issues

**Access Issues**
- Access permission issue
- Mapped drive not connecting
- Unable to map the drive

**File Handling Issues**
- Missing folder / file

**Storage Issues**
- Quota / storage issue

**Usage Queries**
- Shared drive usage query

---

#### Excluded

**Out of Scope**
- Visual Studio/Github - Misrouted
- Teams Facilitator - Misrouted
- SharePoint Online Access Request - Misrouted


---

#### Other / Miscellaneous

- Use a defined product-specific fallback label when none of the above sub-categories apply.

---

### Cross-Category Disambiguation Rules

- **Copilot wins over the host Office app.** If "Copilot not visible in Excel" is the symptom and the root cause is licensing/feature rollout, use a "Licensing Issues" as subcategory.
- **Rejoin scenarios.** If the user is a rejoined employee or accessing a former employee's data, use a rejoin subcategory inside **Microsoft OneDrive** (e.g., "Rejoin access issue", "Former employee data — within 30 days") — not a generic "Shared file access issue".
- **Single-app vs multi-app failure.**
    - Failure isolated to one Office app → use that app's sub-category e.g., "Performance Issues" under Microsoft Excel.
    - Failure across multiple Office apps, or driven by suite-wide install / update / license tier → use a "Installation Issues" or "Licensing Issues" as subcategory.
- **OneDrive client vs SharePoint permission.**
    - Sync / client / availability failure → "Application / Client Issues" as subcategory.
    - "Access denied" on a shared file resolved by owner re-share → "Access & Permission Issues" as a subcategory under Microsoft OneDrive (or the equivalent under Rejoin if the user rejoined).
- **OneNote on a new laptop.** Default to a "Missing Data Issues" or "Usage Queries" as a subcategory unless the work notes specifically attribute the failure to the OneDrive client.
- **Mapped network drive not connecting** is a "Access Issues" as a subCategory where server name contains "SFS"  — never OneDrive.

### Output Format

Return your response as a JSON array. Each element must have exactly these fields:

```json
[
  {
    "IncidentNumber": "INC15511605",
    "SubCategory": "Licensing Issues",
    "Justification": "Copilot not enabled in Excel and PowerPoint because the MSOL License – Copilot for M365 entitlement was hidden in AGS due to the blackout period."
  }
]
```

**Rules:**
- The `IncidentNumber` must exactly match the input.
- The `SubCategory` must be one of the exact labels as parent category above (use the bold grouping header as the value).
- If no listed sub-category fits, use the category-specific fallback label from this template.
- The `Justification` must be one sentence explaining why this sub-category was chosen.
- Return ONLY the JSON array, no additional text or markdown fencing.
