## TicketCategorisation — Messaging - Teams Chat and Audio

### CRITICAL INSTRUCTIONS – READ FIRST
Classify each ticket across service, user-observable symptom, root-cause category, root-cause subcategory, detailed root cause, trend, and confidence. Keep these dimensions separate.

### PRIMARY CATEGORY
For every in-scope ticket output exactly:
Messaging - Teams Chat and Audio

### ALLOWED SUB-SYMPTOMS
- Chat History Missing
- Chat / Messages Not Loading
- Unable to Send / Receive Messages
- Delayed / Intermittent Messaging
- Message Deleted / Retention Behavior
- Group / Meeting / Channel Chat Issue
- Teams Status / Presence Issue
- Teams Notification Issue
- Teams Microphone Issue
- Teams Speaker / Audio Output Issue
- Teams Headset / Bluetooth Issue
- Teams Audio Quality Issue
- External / Federated Messaging Issue
- Teams Sign-In / Profile Issue
- Teams Voicemail Issue
- Teams Recording / Call History Issue
- Teams Rich Content / GIF Issue
- Teams File Sharing Issue
- Teams Read Receipt Issue
- Teams Contact / Search Issue
- Insufficient Information
- Out of Scope
- Misrouted
- Insufficient Documentation
- Repeat / Related Incident

### ROOT-CAUSE MODEL
Select exact values from `PossibleRootCause_Messaging_TeamsChatAudio.md`:
- Root Cause Category
- Root Cause Subcategory

Then select one exact value from `DetailedRootCause_Messaging_TeamsChatAudio.md`:
- Detailed Root Cause

Select one exact visible-symptom label from `TrendSubCategorisation_Messaging_TeamsChatAudio.md`.

### CLASSIFICATION ORDER
1. Confirm offering scope.
2. Identify the affected Teams feature and user-observable symptom.
3. Identify whether desktop, web, mobile, or multiple clients were affected.
4. Review the final resolution note, final technical note, exact errors, logs, versions, and references.
5. Decide whether the cause is client local-state, synchronization, delivery, retention, service-side, network, audio hardware/driver/configuration, Bluetooth, status, notification, federation, identity, policy, operational, or unknown.
6. Select the exact root-cause category and matching subcategory.
7. Select the matching detailed root cause.
8. Select the trend label.
9. Assign confidence.
10. Write evidence-grounded narratives.

### SPECIAL HANDLING
- Desktop missing chats while web/mobile works, with local remediation and no known service issue: use the most specific client-state or synchronization label supported by notes.
- Cache cleared and issue fixed, but corruption not confirmed: do not automatically use Teams Cache Corruption; use Unknown / Unclear / Resolution Without Confirmed Cause when evidence is insufficient.
- Known Microsoft/service issue or backend fix: Teams Service / Backend Failure with the matching subcategory.
- Explicit retention-policy text: Retention / Deletion / Compliance Behavior.
- Message says deleted but no cause documented: use the closest deletion subcategory only if the deletion text is explicit; otherwise use Unknown / Unclear.
- OOO status caused by a calendar event: Presence / Status Integration Failure / Outlook OOO Event Driving Status.
- Microphone fixed by selecting the correct Teams device: Audio Configuration / Permission Failure / Incorrect Teams Microphone Selected.
- Bluetooth audio restored by driver rollback with documented regression: Audio Driver / Device Enumeration Failure / Audio Driver Update Regression or Bluetooth Driver Failure, based on the notes.
- Generic reset/reinstall/restart restored service without a confirmed cause: Unknown / Unclear / Resolution Without Confirmed Cause.

### CONFIDENCE
- High: exact error/finding plus targeted fix and validation, confirmed failed/replaced hardware, or documented service issue.
- Medium: clear symptom and outcome with strong but incomplete cause evidence.
- Low: sparse, conflicting, generic-remediation-only, self-resolved, or monitoring-only evidence.

### REQUIRED OUTPUT FORMAT
Primary Category: <exact category>
Sub-symptom: <exact allowed sub-symptom>
Root Cause Category: <exact category>
Root Cause Subcategory: <exact matching subcategory>
Detailed Root Cause: <exact matching detailed root cause>
Trend Subcategory: <exact trend label>
Confidence Level: <High|Medium|Low>
Issue: <1–2 sentences>
Root Cause: <2–4 evidence-grounded sentences>
Resolution: <1–3 sentences>
Evidence: <short source phrases separated by " / ">
AI Analysis: <2–4 sentences summarizing symptom, context, cause status, action, and outcome>

### CRITICAL OUTPUT RULES
- All fields are mandatory.
- Taxonomy labels must match the approved files exactly.
- Never pair a subcategory or detailed cause with the wrong parent.
- Do not invent technical causes from standard troubleshooting steps.
- If a narrative field is missing, write: Not documented in work notes.
