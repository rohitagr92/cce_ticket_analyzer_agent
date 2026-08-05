# PossibleRootCause — Content Engineering

## PURPOSE
Defines the allowed root cause labels for AI analysis. The AI must output only the exact **bold labels** defined here when assigning a possible root cause.

---

## ROOT CAUSE LABELS BY PRODUCT

### Microsoft Teams

| Bold Label | Description |
|---|---|
| **Teams Add-in Disabled or Missing** | Enable, reinstall, or restore the Teams Outlook add-in. | 
| **User Permission Misconfiguration** | Correct Team, Channel, Chat, or resource permissions. | 
| **Provisioning Failure** | Re-provision the Team, Channel, membership, or affected user. | 
| **Guest Access Configuration Issue** | Correct guest access, external collaboration settings. | 
| **Teams Client Configuration Issue** | Clear cache, reset Teams client state, or recreate the local profile. | 
| **Teams Client Software Defect** | Product defect or regression within the Teams client. | 
| **Outlook-Teams Integration Misconfiguration** | Correct Outlook and Teams integration settings and meeting configuration. | 
| **Network or Connectivity Issue** | Resolve VPN, proxy, firewall, DNS, or connectivity-related problems. | 
| **Microsoft Service Outage** | Microsoft-side service degradation or outage affecting Teams functionality. | 
| **Product Usage Knowledge Gap** | Provide documentation, training, or supported usage guidance. | 


---

### SharePoint On-Premises (SSE)

| Bold Label | Description |
|---|---|
| **BigPanda Alert Routing Issue** | Monitoring alert should be routed through the Content Engineering Alert service offering. | 
| **Infrastructure Health Issue** | Node, host, server, or platform health issue impacting SSE availability. | 
| **Microsoft Software Defect** | Product defect or regression introduced through Microsoft updates or cumulative updates. | 
| **Integration Failure** | External application, connector, script, or configuration failure. | 
| **File Operation Limitation** | Product limits or file operation constraints prevented successful completion. | 
| **Permission Misconfiguration** | Incorrect permissions, labels, or access configuration. | 
| **Product Usage Knowledge Gap** | User requires documentation, training, or supported usage guidance. | 
| **Insufficient Diagnostic Information** | Additional information required to determine root cause. |

---

### SharePoint Online

| Bold Label | Description |
|---|---|
| **Permission Misconfiguration** | Correct site, library, file, group, or role permissions. | 
| **Identity Mismatch** | Resolve rehire, legacy identity, or PUID/SID issues. | 
| **Site Ownership / Admin Gap** | Assign valid owner or site administrator. | 
| **Provisioning Failure** | Re-provision site, workspace, or membership. | 
| **File Storage / Backend Issue** | Recover content, resolve locks, sync, or restore files. | 
| **External Collaboration Configuration** | Correct guest access, onboarding, MFA, or external sharing settings. | 
| **Automation / Integration Issue** | Correct workflow, API, Power Apps, or automation configuration. | 
| **Tenant Policy Restriction** | Action blocked by SharePoint or compliance policy. | 
| **Storage / Quota Capacity Issue** | Increase storage or remove content. | 
| **Product Usage Knowledge Gap** | User requires documentation or training. | 
| **Insufficient Diagnostic Information** | Additional information required to determine cause. |

---

### Yammer

| Bold Label | Description |
|---|---|
| **License Entitlement Missing** | Required Yammer entitlement has not been granted. | 
| **Permission Misconfiguration** | Incorrect permissions, role assignments, or community administration settings. | 
| **Community Configuration Issue** | Community creation, naming, ownership, or management configuration issue. | 
| **Membership Synchronization Failure** | Azure AD, M365 Group, or Yammer membership synchronization issue. | 
| **Application Defect** | Yammer/Viva Engage application behavior or unsupported feature issue. | 
| **Feature Limitation** | Product limitation or expected behavior. | 
| **Product Usage Knowledge Gap** | User requires guidance on supported functionality or process. | 
| **Account State Issue** | User account suspended, inactive, or not fully provisioned. | 
| **Insufficient Diagnostic Information** | Additional information required to determine cause. |

---

### Guest Onboarding Tool | 
Bold Label | Description | 
|---|---| 
| **Guest User Already Exists** | Guest account already exists in the environment. | 
| **Guest Identity Validation Failure** | Guest email, domain, or identity validation failed. | 
| **Guest Provisioning Failure** | Guest onboarding or synchronization process failed. | 
| **Guest Management Request** | User requested add, modify, or delete actions for guest accounts. | 
| **Tool Configuration Issue** | Guest Onboarding Tool configuration issue prevented successful operation. | 
| **Browser or Client Issue** | Browser cache, cookies, or client-side issue impacted functionality. | 
| **Product Usage Knowledge Gap** | User requires guidance on Guest Onboarding Tool functionality or process. | 
| **Insufficient Diagnostic Information** | Additional information is required to determine root cause. |


---

### Collaboration Workspace Management Tool (WMT)
| Bold Label | Description | 
|---|---| 
| **Workspace Ownership Misconfiguration** | Workspace ownership information is incorrect or not synchronized. | 
| **Workspace Permission Misconfiguration** | Workspace permissions or administrative access are incorrectly configured. | 
| **Workspace Lease or Compliance Restriction** | Workspace renewal or lifecycle action is restricted by compliance or lease requirements. | 
| **Workspace Data Synchronization Delay** | Workspace updates have not yet propagated across systems. | 
| **Tool Configuration Issue** | Workspace Management Tool configuration issue prevented successful operation. | 
| **Product Usage Knowledge Gap** | User requires guidance on Workspace Management Tool functionality or process. | 
| **Insufficient Diagnostic Information** | Additional information is required to determine root cause. |















