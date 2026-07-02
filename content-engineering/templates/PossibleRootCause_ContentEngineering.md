# PossibleRootCause — Content Engineering

## PURPOSE
Defines the allowed root cause labels for AI analysis. The AI must output only the exact **bold labels** defined here when assigning a possible root cause.

---

## ROOT CAUSE LABELS BY CATEGORY

### Content Authoring & Publishing

| Bold Label | Description |
|---|---|
| **CMS Software Bug** | Defect in the CMS product (vendor or internal build) causing unexpected behavior. |
| **Publishing Config Error** | Misconfigured pipeline, target, or environment variable causing deployment failure. |
| **Template Defect** | Broken or invalid template file causing render failures. |
| **Approval Workflow Misconfigured** | Workflow rules or routing incorrectly defined, blocking content from progressing. |
| **Network / CDN Issue** | Connectivity or CDN propagation failure preventing content delivery. |

---

### Content Management System (CMS)

| Bold Label | Description |
|---|---|
| **Identity Provider (IdP) Failure** | SSO or SAML authentication service down or misconfigured. |
| **Database / Repository Corruption** | Underlying CMS data store returned unexpected or corrupted data. |
| **CMS Performance Bottleneck** | High load, memory leak, or unoptimized query causing slowness. |
| **Integration API Breaking Change** | Upstream API (DAM, translation, etc.) changed contract, breaking integration. |
| **Permissions Misconfiguration** | Role or group assignment incorrect in the CMS access model. |

---

### Search & Discoverability

| Bold Label | Description |
|---|---|
| **Search Index Rebuild Required** | Index is stale and requires manual or automated rebuild trigger. |
| **Crawler Configuration Error** | Crawler not pointed at correct sitemap or URL pattern. |
| **Broken Redirect Rule** | Redirect loop or missing rule causing 404s on valid URLs. |
| **Metadata Schema Mismatch** | Content metadata does not match search schema, preventing indexing. |

---

### Localization & Translation

| Bold Label | Description |
|---|---|
| **TMS Connector Misconfigured** | Translation management system connector not correctly set up for this locale or project. |
| **Locale Routing Rule Missing** | No routing rule exists for the requested locale, causing fallback or error. |
| **Translation File Format Error** | Exported file in wrong format or encoding, causing import failure. |
| **Third-Party Vendor Delay** | Human translation vendor did not deliver within SLA. |

---

### Access & Permissions

| Bold Label | Description |
|---|---|
| **AD Group Membership Missing** | User not in the required Active Directory group for CMS access. |
| **Provisioning Process Delay** | IT or onboarding process not completed in time. |
| **SSO Configuration Error** | Service provider or identity provider misconfigured for this application. |

---

### SharePoint Platform Health

| Bold Label | Description |
|---|---|
| **Server Resource Exhaustion** | CPU, memory, or disk threshold exceeded on SharePoint farm server. |
| **Planned Maintenance / Restart** | Host shutdown was scheduled or triggered by patching/maintenance process. |
| **Farm Configuration Issue** | SharePoint farm or IIS configuration caused service disruption. |
| **Network Infrastructure Issue** | Network problem between SharePoint servers or clients. |

---

### Microsoft Teams & M365 Collaboration

| Bold Label | Description |
|---|---|
| **Teams Add-in Not Deployed** | Teams COM add-in not installed or disabled by policy in Outlook. |
| **Teams Client Software Bug** | Defect or regression in Teams desktop/web client. |
| **M365 Service Outage** | Microsoft-side service disruption affecting Teams or M365 apps. |
| **Outlook-Teams Integration Misconfiguration** | Integration between Outlook and Teams incorrectly configured at device or tenant level. |

---

### SharePoint Online Administration

| Bold Label | Description |
|---|---|
| **Incorrect Permission Assignment** | User assigned wrong role or missing from required SPO group. |
| **Self-Service Request** | User requesting an admin action they cannot perform themselves. |
| **Deleted Content Not Recoverable** | Item past recycle bin retention period or permanently deleted. |
| **SPO Tenant Policy Restriction** | Action blocked by tenant-level governance or DLP policy. |

---

### How Do I / User Education

| Bold Label | Description |
|---|---|
| **Lack of User Training** | User unfamiliar with product feature — needs documentation or guidance. |
| **Documentation Gap** | Existing self-help docs missing or insufficient for the user's question. |

---

### Unknown / Unclear

| Bold Label | Description |
|---|---|
| **Root Cause Undetermined** | Not enough information in the ticket to identify a root cause. |
| **External Dependency** | Root cause is outside Content Engineering's direct control. |
