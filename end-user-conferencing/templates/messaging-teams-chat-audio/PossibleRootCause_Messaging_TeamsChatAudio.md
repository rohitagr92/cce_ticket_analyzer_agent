## PossibleRootCause — Messaging - Teams Chat and Audio

### CRITICAL INSTRUCTIONS – READ FIRST
Select exactly one Root Cause Category and one matching Root Cause Subcategory. Use the final resolution notes and technical work notes before the short description. Do not treat reset, cache clearing, repair, reinstall, sign-out, restart, or driver update as proof of a cause unless the notes confirm the underlying condition.

### REQUIRED OUTPUT
Root Cause Category: <exact category>
Root Cause Subcategory: <exact matching subcategory>

## 1. Teams Client Local-State Failure
- Teams Cache Corruption
- Teams Local Database Corruption
- Teams Client Profile Corruption
- Teams Client State Synchronization Failure
- Teams Client Installation Corruption
- Teams Client Update / Version Issue
- Teams Client Process Failure
- Local-State Failure — Unspecified

Use when desktop behavior differs from Teams Web/mobile and local remediation restores the function. Cache clearing alone supports this category only when the affected feature returns and no service-side issue is documented.

## 2. Chat History / Message Synchronization Failure
- Chat History Not Synchronized
- Recent Messages Not Loaded
- Older Messages Not Loaded
- Group Chat History Not Loaded
- Meeting Chat History Not Loaded
- Channel Conversation Not Loaded
- Conversation Switching Failure
- Message State Not Refreshed
- Desktop / Web Data Mismatch
- Chat Synchronization Failure — Unspecified

## 3. Message Delivery Failure
- Unable to Send Message
- Unable to Receive Message
- Delayed Message Delivery
- Message Stuck Sending
- Message Loading Failure
- Chat Temporarily Unavailable
- Message Delivery Intermittent
- Message Delivery Failure — Unspecified

## 4. Retention / Deletion / Compliance Behavior
- Message Removed by Retention Policy
- Chat History Removed by Retention Policy
- Message Deleted by Sender / Owner
- Deleted Message Placeholder Displayed
- Conversation Retention Scope Issue
- External Organization Retention Policy
- Retention / Deletion Cause — Unspecified

Use only when the notes or visible message explicitly identify retention or deletion. Do not infer deletion because history is missing from desktop.

## 5. Teams Service / Backend Failure
- Microsoft Teams Service Incident
- Chat Backend Service Failure
- Message Synchronization Service Failure
- Teams Service Degradation
- Known Product Defect
- Backend Fix Required
- Service-Side Failure — Unspecified

Use when a known issue, service incident, product defect, backend remediation, problem record, or Microsoft tracking reference is documented.

## 6. Network / Connectivity Failure
- Network Connection Interruption
- Proxy / Firewall Restriction
- VPN Connectivity Impact
- DNS / Name Resolution Failure
- WebSocket / Real-Time Connection Failure
- High Network Latency
- Packet Loss / Unstable Connection
- Network Path Failure — Unspecified

## 7. Audio Device Hardware Failure
- Microphone Hardware Failure
- Speaker Hardware Failure
- Headset Hardware Failure
- Bluetooth Adapter Hardware Failure
- Audio Jack / Connector Failure
- USB Audio Device Hardware Failure
- Audio Hardware Failure — Unspecified

Use only with confirmed hardware failure, failed testing, or replacement evidence.

## 8. Audio Driver / Device Enumeration Failure
- Microphone Driver Failure
- Speaker Driver Failure
- Bluetooth Driver Failure
- USB Audio Driver Failure
- Audio Driver Compatibility Issue
- Audio Driver Update Regression
- Ghost / Duplicate Audio Driver
- Microphone Not Detected
- Speaker Not Detected
- Headset Not Detected
- Bluetooth Audio Device Not Detected
- Audio Device Enumeration Failure — Unspecified

## 9. Audio Configuration / Permission Failure
- Incorrect Teams Microphone Selected
- Incorrect Teams Speaker Selected
- Incorrect Headset Selected
- Microphone Permission Disabled
- Audio Device Disabled in Windows
- Teams Audio Permission Failure
- Automatic Mute Configuration Issue
- Microphone Level / Gain Misconfiguration
- Speaker Volume Misconfiguration
- Audio Configuration Failure — Unspecified

## 10. Audio Quality / Media Pipeline Failure
- Audio Distortion
- Audio Echo / Feedback
- Audio Latency
- Intermittent Audio
- Low Microphone Volume
- Low Speaker Volume
- One-Way Audio
- Teams Audio Processing Failure
- Teams Media Stack Failure
- Audio Quality Failure — Unspecified

## 11. Bluetooth / Headset Connectivity Failure
- Bluetooth Pairing Failure
- Bluetooth Connection Intermittent
- Bluetooth Profile Selection Issue
- Headset Connection Failure
- Headset Firmware Issue
- Headset Compatibility Issue
- Bluetooth / Headset Failure — Unspecified

## 12. Presence / Status Integration Failure
- Teams Status Not Updating
- Teams Presence Synchronization Failure
- Outlook OOO Event Driving Status
- OOO Status Stuck
- Calendar Presence Integration Failure
- Manual Status Configuration Issue
- Presence / Status Failure — Unspecified

## 13. Notification / Windows Integration Failure
- Teams Notifications Disabled
- Windows Do Not Disturb Enabled
- Windows Notification Permission Disabled
- Teams Notification Configuration Issue
- Notification Delivery Failure
- Notification Failure — Unspecified

## 14. External Access / Federation Failure
- External Federation Blocked
- External Tenant Policy Restriction
- Guest / External User Access Failure
- External Chat Delivery Failure
- External Contact Resolution Failure
- Cross-Tenant Messaging Failure
- External Access Failure — Unspecified

## 15. Identity / Authentication / Profile Failure
- Teams Sign-In Failure
- Authentication Token Failure
- Stale Credential / Session
- User Profile Corruption
- Account / License Configuration Issue
- Account Access Restriction
- Identity Failure — Unspecified

## 16. Feature / Content Failure
- GIF / GIPHY Content Failure
- File Sharing Failure
- Read Receipt Failure
- Recording Access Failure
- Voicemail Access / Playback Failure
- Contact / People Search Failure
- Call Log / History Failure
- Feature Failure — Unspecified

## 17. Policy / Expected Product Behavior
- Organization Policy Restriction
- Tenant Configuration Restriction
- Feature Not Supported
- Expected Product Behavior
- User Guidance Required
- Policy / Behavior — Unspecified

## 18. Operational / Ticket Disposition
- Duplicate Incident
- Related Known Incident
- Resolved by Known Problem
- Self-Resolved Before Investigation
- No Fault Found
- Unable to Reproduce
- Workaround Provided
- User Requested Closure
- No Action Required

## 19. Unknown / Unclear
- Insufficient Technical Evidence
- Conflicting Evidence
- Cause Not Documented
- Resolution Without Confirmed Cause

### EVIDENCE PRIORITY
1. Final resolution notes and final technical work note
2. Confirmed logs, error text, known-issue or problem reference
3. Reproduction comparison across desktop, web, and mobile
4. Verified configuration, driver, policy, calendar, or device finding
5. Successful validation after a targeted fix
6. Short description

### CRITICAL OUTPUT RULES
- Output one category and one valid matching subcategory.
- Copy labels exactly.
- Do not classify cache corruption solely because cache was cleared.
- Do not classify hardware failure solely because audio stopped working.
- If a generic reset/reinstall fixed the issue without confirming why, use Unknown / Unclear / Resolution Without Confirmed Cause.
