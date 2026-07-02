# EnvironmentContext — Content Engineering

## PURPOSE
Provides the AI with context about the Content Engineering service scope, tools, and what is and is not in scope. This template is included in every categorization prompt.

---

## WHAT CONTENT ENGINEERING COVERS

Content Engineering is responsible for the platforms, pipelines, and tooling used to author, manage, localize, and publish content across Intel's web properties and internal portals.

**In-scope platforms and tools:**
- Authoring platforms: Adobe Experience Manager (AEM), Sitecore, or equivalent CMS
- Digital Asset Management (DAM) system
- Publishing pipelines and CI/CD for content delivery
- Localization / translation management system (TMS)
- Search and indexing services tied to content delivery
- Content API and headless delivery layer
- Internal wiki and documentation portals managed by the CE team

**Typical users:**
- Content authors and editors
- Web content managers
- Localization coordinators
- Marketing and product teams publishing content via CE-managed platforms

---

## WHAT IS OUT OF SCOPE

The following are **NOT** Content Engineering incidents even if they mention content:

- Network or corporate connectivity issues
- Device / endpoint issues on the author's laptop
- IT helpdesk requests unrelated to content platforms
- Issues with non-CE-managed SharePoint or OneDrive sites
- Business application issues (SAP, Oracle, Workday)

If an incident clearly falls outside the above scope, use the category **Unknown / Unclear → Out of Scope**.

---

## KEY SIGNALS TO LOOK FOR

| Signal in work notes | Likely category |
|---|---|
| "Can't log in to AEM / Sitecore" | Access & Permissions — Broken SSO |
| "Page not found after publish" | Content Authoring & Publishing — Publishing Pipeline Error |
| "Translation not showing up" | Localization & Translation — Translation Job Failure |
| "Search not returning new pages" | Search & Discoverability — Search Index Outdated |
| "Missing permissions on DAM" | Access & Permissions — Permission Denied |
| "CMS is slow / timing out" | Content Management System — CMS Performance Degradation |
