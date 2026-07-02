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

### Unknown / Unclear

| Bold Label | Description |
|---|---|
| **Root Cause Undetermined** | Not enough information in the ticket to identify a root cause. |
| **External Dependency** | Root cause is outside Content Engineering's direct control. |
