# PossibleRootCause — Content Engineering

## PURPOSE
Defines the allowed root cause labels for AI analysis. The AI must output only the exact **bold labels** defined here when assigning a possible root cause.

---

## ROOT CAUSE LABELS BY PRODUCT

### Microsoft Teams

| Bold Label | Description |
|---|---|
| **Teams Add-in Not Deployed** | Teams COM add-in not installed or disabled by Outlook/Group Policy. |
| **Teams Client Software Bug** | Defect or regression in Teams desktop or web client. |
| **Microsoft Service Outage** | Microsoft-side Teams or M365 service disruption. |
| **Outlook-Teams Integration Misconfiguration** | Outlook and Teams integration incorrectly configured at device or tenant level. |

---

### SharePoint On-Premises

| Bold Label | Description |
|---|---|
| **Server Resource Exhaustion** | CPU, memory, or disk threshold exceeded on SharePoint farm server. |
| **Planned Maintenance / Restart** | Host shutdown triggered by scheduled patching or maintenance. |
| **Farm Configuration Issue** | SharePoint farm or IIS configuration caused service disruption. |
| **Network Infrastructure Issue** | Network connectivity problem between SharePoint servers or clients. |

---

### SharePoint Online

| Bold Label | Description |
|---|---|
| **Incorrect Permission Assignment** | User assigned wrong role or missing from required SPO group. |
| **Self-Service Admin Request** | User requesting an admin action they cannot perform themselves. |
| **Deleted Content Not Recoverable** | Item past recycle bin retention or permanently deleted. |
| **SPO Tenant Policy Restriction** | Action blocked by tenant-level governance or DLP policy. |

---

### Microsoft 365 Apps

| Bold Label | Description |
|---|---|
| **Microsoft Service Outage** | Microsoft-side service disruption affecting M365 apps. |
| **App Configuration Issue** | App incorrectly configured at tenant or user level. |
| **License / Entitlement Missing** | User lacks required M365 license or app entitlement. |

---

### Content Management System (CMS)

| Bold Label | Description |
|---|---|
| **Identity Provider (IdP) Failure** | SSO or SAML authentication service down or misconfigured. |
| **Database / Repository Corruption** | Underlying CMS data store returned corrupted or unexpected data. |
| **CMS Performance Bottleneck** | High load, memory leak, or unoptimized query causing slowness. |
| **Integration API Breaking Change** | Upstream API changed contract, breaking CMS integration. |
| **Permissions Misconfiguration** | Role or group assignment incorrect in the CMS access model. |

---

### Content Authoring & Publishing

| Bold Label | Description |
|---|---|
| **CMS Software Bug** | Defect in the CMS product causing unexpected authoring behavior. |
| **Publishing Config Error** | Misconfigured pipeline, target, or environment variable. |
| **Template Defect** | Broken or invalid template file causing render failures. |
| **Approval Workflow Misconfigured** | Workflow rules incorrectly defined, blocking content from progressing. |

---

### Search & Discoverability

| Bold Label | Description |
|---|---|
| **Search Index Rebuild Required** | Index is stale and requires manual or automated rebuild. |
| **Broken Redirect Rule** | Redirect loop or missing rule causing 404s on valid URLs. |
| **Metadata Schema Mismatch** | Content metadata does not match search schema, preventing indexing. |

---

### Access & Permissions

| Bold Label | Description |
|---|---|
| **AD Group Membership Missing** | User not in the required Active Directory group for CE tool access. |
| **Provisioning Process Delay** | IT or onboarding process not completed in time. |
| **SSO Configuration Error** | Service provider or identity provider misconfigured for the application. |

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
