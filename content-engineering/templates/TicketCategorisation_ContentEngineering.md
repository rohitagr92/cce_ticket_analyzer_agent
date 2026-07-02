# TicketCategorisation — Content Engineering

## PURPOSE
This template defines the allowed category and subcategory taxonomy for **Content Engineering** incidents.
The AI must only output values from the exact bold labels defined here.

## INSTRUCTIONS
- Assign exactly ONE Category and ONE Subcategory per incident.
- Use the exact **bold label** — do not paraphrase, abbreviate, or invent new labels.
- If no category clearly fits, assign **Unknown / Unclear**.

---

## CATEGORIES AND SUBCATEGORIES

### **Content Authoring & Publishing**
Tools and processes for creating, editing, and publishing content.

- **Authoring Tool Failure** — Tool crash, hang, or data loss during content creation.
- **Publishing Pipeline Error** — Failure during build, deploy, or publish to a content target.
- **Template / Style Issue** — Broken template, wrong formatting, or style guide violation.
- **Workflow Approval Blocked** — Content stuck in review/approval queue.

### **Content Management System (CMS)**
Issues with the CMS platform itself.

- **CMS Login / Access Issue** — Users cannot authenticate or lack permissions.
- **CMS Performance Degradation** — Slow load times, timeouts, or UI unresponsiveness.
- **CMS Data / Asset Corruption** — Incorrect, missing, or duplicate content/assets.
- **CMS Integration Failure** — Broken integrations with DAM, translation, or other systems.

### **Search & Discoverability**
Content cannot be found or indexed correctly.

- **Search Index Outdated** — Recently published content not appearing in search results.
- **Broken Links / 404s** — Content links returning not-found errors.
- **Metadata / Taxonomy Error** — Missing or incorrect tags preventing findability.

### **Localization & Translation**
Issues affecting multi-language content delivery.

- **Translation Job Failure** — Translation request failed or was not submitted.
- **Locale Configuration Error** — Wrong locale served to end users.
- **Translation Quality Issue** — Machine or human translation is incorrect.

### **Access & Permissions**
Users cannot access content or authoring systems.

- **Permission Denied** — User lacks required role to view or edit content.
- **Onboarding / Role Assignment** — New user not provisioned to the correct group.
- **Broken SSO** — Single sign-on failing for authoring or delivery platforms.

### **Unknown / Unclear**
Use only when no other category fits after careful review.

- **Insufficient Information** — Ticket lacks enough detail to categorize.
- **Out of Scope** — Incident does not belong to Content Engineering.
