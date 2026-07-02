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

### **SharePoint Platform Health**
Infrastructure and operational health events for SharePoint on-premises farms.

- **CPU Saturation** — SharePoint server CPU utilisation exceeded threshold.
- **Low Disk Space** — SharePoint server disk space below safe threshold.
- **Host Gracefully Shutdown** — SharePoint host or service process shut down cleanly (planned or auto-restart).
- **Network Problem** — Network connectivity issue affecting SharePoint farm.
- **SharePoint Service Degradation** — General performance degradation or service slowness on SharePoint farm.

### **Microsoft Teams & M365 Collaboration**
Issues with Microsoft Teams client, add-ins, and integrated M365 collaboration tools.

- **Teams Add-in Missing in Outlook** — Teams add-in not visible or loaded in Outlook client.
- **Teams Client Functional Issue** — Teams messaging, chat, calling, or UI not working correctly.
- **Outlook-Teams Integration Issue** — Teams meetings or scheduling broken within Outlook.
- **M365 Planner / Other App Issue** — Issues with Planner, OneDrive, OneNote, or other M365 apps.

### **SharePoint Online Administration**
User-facing requests and incidents on SharePoint Online sites and permissions.

- **Permission Denied (SPO)** — User cannot access a SharePoint Online site, list, or document.
- **Site Administration Request** — Request to change site name, ownership, settings, or quota.
- **Recycle Bin / File Recovery** — User requesting restore of deleted files or items.
- **User Education — SPO** — How-to query about SharePoint Online features (not a break/fix).

### **How Do I / User Education**
Non-break/fix queries where the user needs guidance on using a tool or feature.

- **Teams Usage Query** — How-to question about Microsoft Teams features.
- **SharePoint Usage Query** — How-to question about SharePoint or document management.
- **General M365 Query** — How-to question about any other M365 product.

### **Unknown / Unclear**
Use only when no other category fits after careful review.

- **Insufficient Information** — Ticket lacks enough detail to categorize.
- **Out of Scope** — Incident does not belong to Content Engineering's supported scope.
