# EnvironmentContext — Content Engineering

## PURPOSE
Provides the AI with context about the Content Engineering service scope, tools, and what is and is not in scope. This template is included in every categorization prompt.

---

## WHAT CONTENT ENGINEERING COVERS

Content Engineering is responsible for the platforms, pipelines, and tooling used to author, manage, localize, and publish content, as well as the Microsoft 365 collaboration infrastructure (SharePoint, Teams) that Intel employees use for content sharing and productivity.

**In-scope platforms and tools:**
- Authoring platforms: Adobe Experience Manager (AEM), Sitecore, or equivalent CMS
- Digital Asset Management (DAM) system
- Publishing pipelines and CI/CD for content delivery
- Localization / translation management system (TMS)
- Search and indexing services tied to content delivery
- Content API and headless delivery layer
- Internal wiki and documentation portals managed by the CE team
- **SharePoint 2019 / SharePoint Subscription Edition** on-premises farm (health monitoring, infra alerts)
- **SharePoint Online (SPO)** — user access, permissions, site administration, and file recovery
- **Microsoft Teams** — Teams client, add-ins, Outlook-Teams integration, meeting scheduling
- **M365 apps** — Planner, OneDrive, OneNote, and other integrated M365 productivity tools

**Typical users:**
- Content authors and editors
- Web content managers
- Localization coordinators
- Marketing and product teams publishing content via CE-managed platforms
- Intel employees raising Teams, SharePoint, or M365 support requests routed to CE

---

## WHAT IS OUT OF SCOPE

The following are **NOT** Content Engineering incidents even if they mention content:

- Network or corporate connectivity issues unrelated to SharePoint/Teams
- Device / endpoint issues on the author's laptop (hardware, VPN, OS)
- IT helpdesk requests for non-CE-managed business applications (SAP, Oracle, Workday)
- Issues with infrastructure services outside CE's ownership

If an incident clearly falls outside the above scope, use the category **Unknown / Unclear → Out of Scope**.

---

## KEY SIGNALS TO LOOK FOR

| Signal in work notes | Likely category |
|---|---|
| "SharePoint 2019 / CPU Saturation" | SharePoint Platform Health — CPU Saturation |
| "SharePoint / Host gracefully shutdown" | SharePoint Platform Health — Host Gracefully Shutdown |
| "SharePoint / Low disk space" | SharePoint Platform Health — Low Disk Space |
| "Teams add-in missing in Outlook" | Microsoft Teams & M365 Collaboration — Teams Add-in Missing in Outlook |
| "Teams messages not sending / app not working" | Microsoft Teams & M365 Collaboration — Teams Client Functional Issue |
| "Teams not integrated into Outlook meetings" | Microsoft Teams & M365 Collaboration — Outlook-Teams Integration Issue |
| "Can't access SharePoint site / permission denied" | SharePoint Online Administration — Permission Denied (SPO) |
| "Restore deleted files from SharePoint" | SharePoint Online Administration — Recycle Bin / File Recovery |
| "Change SharePoint site name / owner" | SharePoint Online Administration — Site Administration Request |
| "How to use Teams / SharePoint feature" | How Do I / User Education |
| "Can't log in to AEM / Sitecore" | Access & Permissions — Broken SSO |
| "Page not found after publish" | Content Authoring & Publishing — Publishing Pipeline Error |
| "Translation not showing up" | Localization & Translation — Translation Job Failure |
| "Search not returning new pages" | Search & Discoverability — Search Index Outdated |
| "Missing permissions on DAM" | Access & Permissions — Permission Denied |
| "CMS is slow / timing out" | Content Management System — CMS Performance Degradation |
