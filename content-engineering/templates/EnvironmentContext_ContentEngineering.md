# EnvironmentContext — Content Engineering

## PURPOSE
Provides the AI with context about the Content Engineering service scope, tools, and what is and is not in scope. This template is included in every categorization prompt.

---

## WHAT CONTENT ENGINEERING COVERS

Content Engineering is responsible for the platforms, pipelines, and tooling used to author, manage, localize, and publish content, as well as the Microsoft 365 collaboration infrastructure (SharePoint, Teams) that Intel employees use for content sharing and productivity.

**In-scope platforms and tools:**
- **SharePoint Online (SPO) — Enterprise collaboration platform used for document management, content sharing, site administration, permissions management, file storage, and team collaboration
- **SharePoint Subscription Edition (SSE) — On-premises SharePoint platform used for business applications, workflow automation, document management, manufacturing solutions, and custom integrated solutions 
- **SharePoint 2019 — Legacy on-premises SharePoint platform supporting internal business applications, collaboration sites, workflows, content management, and enterprise integrations. 
- **Microsoft Teams — Collaboration platform used for team communication, channel collaboration, Teams administration, Teams add-ins, and integration with Microsoft 365 services. 
- **Viva Engage (Yammer) — Enterprise social networking and community platform used for employee engagement, communities, discussions, announcements, and knowledge sharing. 
- **Guest Onboarding Tool — Service used to onboard, manage, and govern external guest user access to Microsoft 365 collaboration platforms. 
- **Collaboration Workspace Management Tool (WMT) — Service used to provision, manage, renew, and govern collaboration workspaces and associated resources.


**Typical users:**
- Intel employees using SharePoint Online, SharePoint 2019, SharePoint Subscription Edition, Teams, Viva Engage (Yammer), Planner, Power Apps, and Power Automate for collaboration and productivity. 
- Site owners, workspace owners, community owners, and administrators responsible for managing collaboration environments. 
- Content authors, editors, and publishers managing content through CE-supported platforms. 
- Business users requesting access, permissions, licensing, provisioning, workspace administration, guest collaboration, and community management services. 
- Application owners and technical contacts managing integrations, workflows, automation, and business solutions built on CE-supported platforms.

---

## WHAT IS OUT OF SCOPE

The following are **NOT** Content Engineering incidents even if they reference collaboration or content platform

- Corporate network, DNS, VPN, proxy, or general connectivity issues that are not specific to a CE-managed platform. 
- Device, operating system, browser, hardware, or endpoint configuration issues. 
- Email, Exchange, Outlook mailbox, or messaging issues that are unrelated to Teams, SharePoint, or Viva Engage functionality. 
- IT support requests for non-CE business applications (SAP, Oracle, Workday, Ariba, ServiceNow, GitHub, etc.). 
- Identity, HR, payroll, finance, procurement, or enterprise business process issues. 
- Infrastructure services, cloud platforms, databases, servers, or applications owned by teams outside Content Engineering. 
- Requests involving software installation, device provisioning, or endpoint administration. 
- General Microsoft 365 issues that are not directly related to SharePoint, Teams, Viva Engage, Planner, Power Apps, Power Automate, Guest Onboarding Tool, or Workspace Management Tool.

If an incident clearly falls outside the above scope, use the category **Unknown / Unclear → Out of Scope**.

---

## KEY SIGNALS TO LOOK FOR

| Signal in work notes | Likely category |
|---|---|
| "SharePoint 2019 / CPU Saturation" | SharePoint Platform Health — CPU Saturation | 
| "SharePoint / Host gracefully shutdown" | SharePoint Platform Health — Host Gracefully Shutdown | 
| "SharePoint / Low disk space" | SharePoint Platform Health — Low Disk Space | 
| "Teams add-in missing in Outlook" | Microsoft Teams & M365 Collaboration — Teams Add-in Issue | 
| "Unable to access Team or Channel" | Microsoft Teams & M365 Collaboration — Teams Access Issue | 
| "Unable to open Teams" | Microsoft Teams & M365 Collaboration — Teams Client Issue | 
| "Can't access SharePoint site / permission denied" | SharePoint Online Administration | 
| "Restore deleted files from SharePoint" | SharePoint Online Administration | 
| "Change SharePoint site name / owner" | SharePoint Online Administration | 
| "Unable to access Viva Engage" | Viva Engage (Yammer) | 
| "M365 - Yammer License Exception for Contingent Workers" | Viva Engage (Yammer) | 
| "Create Viva Engage Community" | Viva Engage (Yammer) | 
| "Guest onboarding" | Guest Onboarding Tool | 
| "Workspace Management Tool" or "WMT" | Collaboration Workspace Management Tool | 
| "Server busy" / "Data not loading" on SSE | SharePoint Subscription Edition | 
| "Resolved by BigPanda" | Content Engineering Alert Service Offering | 
| "How to use Teams / SharePoint / Viva Engage feature" | How Do I / User Education |
| "Guest onboarding" | Guest Onboarding Tool | 
| "Guest user" + "external user" + onboarding | Guest Onboarding Tool | 
| "Workspace Management Tool" or "WMT" | Collaboration Workspace Management Tool | 
| "Workspace renewal" | Collaboration Workspace Management Tool | 
| "Workspace lease" | Collaboration Workspace Management Tool | 
| "Owner changes not reflecting" | Collaboration Workspace Management Tool |
