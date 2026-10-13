## TicketCategorisation — End User Conferencing Rooms

### CRITICAL INSTRUCTIONS – READ FIRST
Classify each ticket across four independent dimensions: owning service, user-observable symptom, root-cause category, and root-cause subcategory. Do not use a broad hardware label when the failed component is documented.

### REQUIRED CLASSIFICATION MODEL
1. Primary Category
2. Sub-symptom
3. Root Cause Category
4. Root Cause Subcategory
5. Trend Subcategory
6. Confidence Level

### PRIMARY CATEGORY
For every in-scope ticket, output exactly:
Meetings - Rooms & Hardware

### ALLOWED SUB-SYMPTOMS
- Room Device Offline
- Room Audio / Video Issue
- Room Display / Sharing Issue
- Room Scheduling / Reservation Issue
- Room Peripheral Failure
- Room Client / App Failure
- Room Power / Connectivity Issue
- Insufficient Information
- Out of Scope
- Misrouted
- Insufficient Documentation
- Repeat Tags

### SUB-SYMPTOM SELECTION
- Room Device Offline: room system unavailable, unreachable, unhealthy, or explicitly offline.
- Room Audio / Video Issue: camera, microphone, speaker, echo, or in-meeting media symptom.
- Room Display / Sharing Issue: display, projector, front-of-room, HDMI ingest, or presentation symptom.
- Room Scheduling / Reservation Issue: booking, calendar, mailbox, approval, or reservation symptom.
- Room Peripheral Failure: console, touch panel, controller, or another peripheral was the primary user-visible failure.
- Room Client / App Failure: room application, meeting join, freeze, crash, or sign-in symptom.
- Room Power / Connectivity Issue: power, PoE, LAN, port, cabling, or connectivity was the primary visible issue.
- Insufficient Information: source fields do not identify the symptom.
- Out of Scope: issue does not concern room conferencing services.
- Misrouted: another service or team owns the issue.
- Insufficient Documentation: likely room issue but notes do not support reliable classification.
- Repeat Tags: duplicate, repeat, reopened, or related incident.

### ROOT-CAUSE SELECTION
Select one exact Root Cause Category and one valid matching Root Cause Subcategory from PossibleRootCause_EndUserConferencing_Rooms_Final.md.

Root Cause Categories:
- Hardware Component Failure
- Power / Connectivity Failure
- Camera & Video Pipeline Failure
- Audio System Failure
- Display & Content-Sharing Failure
- Room Controller / Integration Failure
- Teams Room Application Failure
- Account / Authentication Failure
- Calendar / Resource Integration Failure
- Device Firmware / Driver Failure
- Compute / Resource Failure
- Physical Damage / Tampering
- Operational / Monitoring Event
- Unknown / Unclear

### TREND SUBCATEGORY
Select one exact label from TrendSubCategorisation_EndUserConferencing_Rooms_Final.md. Trend is based on the visible symptom, not the root cause.

### CLASSIFICATION ORDER
1. Confirm service scope.
2. Identify the reported or monitored symptom.
3. Identify the exact affected component.
4. Review the final resolution note and final technical work note.
5. Determine whether the evidence shows failure, disconnection, misconfiguration, firmware/driver issue, integration issue, account issue, or operational disposition.
6. Select the exact Root Cause Category.
7. Select the matching Root Cause Subcategory.
8. Select the Trend Subcategory.
9. Assign confidence.
10. Write evidence-grounded narrative fields.

### COMPONENT-SPECIFIC HARDWARE RULES
Use Hardware Component Failure only with confirmed physical failure or replacement evidence. Select the exact component subcategory:
- Camera → Camera Hardware Failure
- Microphone → Microphone Hardware Failure
- Speaker → Speaker Hardware Failure
- Display → Display Hardware Failure
- Projector → Projector Hardware Failure
- Console → Console Hardware Failure
- Touch panel → Touch Panel Hardware Failure
- MTR PC or UC engine → MTR PC / UC Engine Hardware Failure
- SSD → Storage / SSD Failure
- Power adapter or PSU → Power Adapter / PSU Failure
- PoE injector → PoE Injector Failure
- HDMI cable → HDMI Cable Failure
- DisplayPort cable → DisplayPort Cable Failure
- USB cable → USB Cable Failure
- Ethernet cable → Ethernet Cable Failure
- Adapter or converter → Adapter / Converter Failure
- Hub or extender → Hub / Extender Failure
- DSP → DSP Hardware Failure
- Room controller → Room Controller Hardware Failure

Do not use Hardware Component Failure when:
- the component was only unplugged, loose, disabled, or powered off;
- the issue was corrected through input, peripheral, resolution, or device selection;
- firmware, driver, enumeration, authentication, or integration is the documented cause;
- a reboot restored service without confirming cause.

### SPECIAL HANDLING
- Monitoring alert auto-closed without confirmed fault → Operational / Monitoring Event / Auto-Recovered Monitoring Alert.
- Reboot restored service without confirmed cause → Unknown / Unclear / Resolution Without Confirmed Cause.
- Faulty component replaced → Hardware Component Failure / exact component subcategory.
- Working cable reseated → Power / Connectivity Failure / Loose Cable Connection.
- Cable confirmed faulty and replaced → Hardware Component Failure / exact cable subcategory.
- Incorrect display input → Display & Content-Sharing Failure / Input Source Misconfiguration.
- Missing camera after USB detection failure → Camera & Video Pipeline Failure / Camera USB Enumeration Failure.
- Explicit vandalism or theft → Physical Damage / Tampering / matching subcategory.
- Duplicate ticket → Operational / Monitoring Event / Duplicate Incident.
- Room confirmed healthy with no action → Operational / Monitoring Event / No Fault Found.

### CONFIDENCE LEVEL
- High: clear symptom plus confirmed cause, failed component, or final repair evidence.
- Medium: clear symptom and resolution but cause is partly inferred or not fully confirmed.
- Low: sparse, conflicting, duplicate, monitoring-only, or undocumented evidence.

### REQUIRED OUTPUT FORMAT
Primary Category: <exact category>
Sub-symptom: <exact allowed sub-symptom>
Root Cause Category: <exact category from root-cause file>
Root Cause Subcategory: <exact matching subcategory from root-cause file>
Detailed Root Cause: <exact matching label from DetailedRootCause_ProductivityTools.md; use Out of Scope - Not a Rooms Root Cause only when Primary Category is Excluded>
Trend Subcategory: <exact trend label>
Confidence Level: <High|Medium|Low>
Issue: <1–2 plain-language sentences describing the observable problem>
Root Cause: <2–4 sentences describing confirmed or most likely cause, with evidence status>
Resolution: <1–3 sentences describing final action and outcome>
Evidence: <short source phrases separated by " / ">
AI Analysis: <2–4 sentences summarizing symptom, exact component/condition, action, and operational significance>

### CRITICAL OUTPUT RULES
- All fields are mandatory.
- Taxonomy labels must exactly match the allowed values.
- Root Cause Subcategory must belong to the selected Root Cause Category.
- Do not use bold formatting in final ticket output.
- Do not invent a component, cause, action, result, user impact, owner, or date.
- If a narrative field is unavailable, write: Not documented in work notes.
- Evidence must be short source-supported phrases.
