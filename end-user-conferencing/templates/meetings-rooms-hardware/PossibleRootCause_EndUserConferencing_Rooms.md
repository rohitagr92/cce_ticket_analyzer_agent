## PossibleRootCause — End User Conferencing Rooms

### CRITICAL INSTRUCTIONS – READ FIRST
Select exactly one Root Cause Category and one matching Root Cause Subcategory for each Meetings - Rooms & Hardware incident. Do not use a broad category when the failed component or condition is documented. Narrative explanation belongs in Root Cause and AI Analysis.

### OUTPUT MODEL
Root Cause Category: <exact category>
Root Cause Subcategory: <exact matching subcategory>

### 1. HARDWARE COMPONENT FAILURE
Use only when physical hardware, a replaceable module, or a physical signal-path component failed.

Allowed subcategories:
- Camera Hardware Failure
- Microphone Hardware Failure
- Speaker Hardware Failure
- Display Hardware Failure
- Projector Hardware Failure
- Console Hardware Failure
- Touch Panel Hardware Failure
- MTR PC / UC Engine Hardware Failure
- Storage / SSD Failure
- Memory Failure
- Power Adapter / PSU Failure
- PoE Injector Failure
- HDMI Cable Failure
- DisplayPort Cable Failure
- USB Cable Failure
- Ethernet Cable Failure
- Adapter / Converter Failure
- Hub / Extender Failure
- DSP Hardware Failure
- Room Controller Hardware Failure
- Other Confirmed Hardware Failure

Selection rules:
- Use a component-specific label whenever the failed or replaced component is documented.
- Cable, adapter, hub, extender, power supply, and PoE failures belong here only when the component itself was confirmed faulty or replaced.
- Do not use this category merely because a reboot or power cycle restored service.
- Do not use this category for a loose, unplugged, or intentionally disconnected working component.

### 2. POWER / CONNECTIVITY FAILURE
Use when service failed because power, network, port, or physical connectivity was unavailable, but the connected component was not proven defective.

Allowed subcategories:
- Device Powered Off
- Power Supply Disconnected
- Power Strip / PDU Disconnected
- Building Power Outage
- PoE Connectivity Failure
- Ethernet Link Failure
- Network Port Failure
- Switch / VLAN Connectivity Failure
- IP Address / Network Configuration Failure
- Network Driver Failure
- Loose Cable Connection
- Disconnected Cable
- Peripheral Connectivity Failure
- Device Unreachable / Offline
- Intermittent Connectivity Failure

### 3. CAMERA & VIDEO PIPELINE FAILURE
Use when camera or video failed without confirmed physical camera replacement or damage.

Allowed subcategories:
- Camera Driver Failure
- Camera USB Enumeration Failure
- Camera Initialization Failure
- Camera Capture / Rendering Failure
- Camera Firmware Issue
- Camera Configuration Issue
- Camera Calibration / Framing Issue
- Content Camera Detection Failure
- Video Pipeline Failure

### 4. AUDIO SYSTEM FAILURE
Use for microphone, speaker, echo-cancellation, DSP, driver, or audio-processing failures without confirmed physical component failure.

Allowed subcategories:
- Audio Driver Failure
- Microphone Detection Failure
- Speaker Detection Failure
- USB Audio Enumeration Failure
- Echo-Cancelling Device Configuration Failure
- Audio Processing Pipeline Failure
- Audio Codec / Rendering Failure
- DSP Configuration Failure
- Audio Firmware Issue
- Audio Device Selection Issue
- Echo / Feedback Configuration Issue

### 5. DISPLAY & CONTENT-SHARING FAILURE
Use for display output, input, HDMI ingest, EDID, or sharing-path failures without confirmed defective hardware.

Allowed subcategories:
- HDMI Ingest Failure
- DisplayPort Signal Failure
- EDID Communication Failure
- Input Source Misconfiguration
- Resolution / Refresh Rate Misconfiguration
- Display Orientation Configuration Issue
- Display Power-Save / Standby Issue
- Front-of-Room Output Failure
- Content Sharing Path Failure
- Display Firmware Issue
- Projector Configuration Issue

### 6. ROOM CONTROLLER / INTEGRATION FAILURE
Use for synchronization or communication failures among integrated room components.

Allowed subcategories:
- Console Communication Failure
- Touch Panel Communication Failure
- Console Pairing Failure
- Room Controller Integration Failure
- UC Engine Integration Failure
- Peripheral Integration Failure
- Room Device Synchronization Failure
- Controller Firmware Issue

### 7. TEAMS ROOM APPLICATION FAILURE
Use for Teams Room software, meeting application, join flow, or media-service failures.

Allowed subcategories:
- MTR Application Failure
- Teams Media Stack Failure
- Meeting App Freeze / Crash
- Meeting Join Failure
- Application Service Failure
- Application Update Failure
- Windows Update Failure
- Operating System Corruption
- Application Configuration Failure

### 8. ACCOUNT / AUTHENTICATION FAILURE
Use when room access or client operation failed because of identity, credentials, or account state.

Allowed subcategories:
- Room Account Sign-In Failure
- Password / Credential Failure
- Forced Password Change Issue
- Account Disabled / Locked
- Authentication Token Failure
- Conditional Access / Policy Issue
- Account Configuration Failure

### 9. CALENDAR / RESOURCE INTEGRATION FAILURE
Use for scheduling, calendar, mailbox, and reservation workflow failures.

Allowed subcategories:
- Calendar Sync Failure
- Resource Mailbox Failure
- Room Booking Conflict
- Recurring Reservation Issue
- Room Approval / Permission Issue
- Scheduling Panel Sync Failure
- Calendar Configuration Failure
- Time Zone Configuration Issue

### 10. DEVICE FIRMWARE / DRIVER FAILURE
Use when firmware or a non-audio/non-camera device driver is the confirmed cause and a more specific branch does not apply.

Allowed subcategories:
- Device Firmware Incompatibility
- Device Firmware Corruption
- Unsupported Firmware Version
- Firmware Update Failure
- Firmware Rollback Required
- Generic Device Driver Failure
- Driver Compatibility Failure

### 11. COMPUTE / RESOURCE FAILURE
Use for constrained or failed computing resources without confirmed replaceable hardware failure.

Allowed subcategories:
- CPU Resource Exhaustion
- Memory Resource Exhaustion
- GPU Resource Exhaustion
- Disk Capacity / Resource Exhaustion
- Operating System Performance Failure
- BIOS Configuration Issue
- Compute Platform Instability

### 12. PHYSICAL DAMAGE / TAMPERING
Use only when notes explicitly document physical alteration, damage, removal, or intentional disconnection.

Allowed subcategories:
- Equipment Unplugged
- Equipment Intentionally Powered Off
- Equipment Damaged
- Equipment Dismantled
- Equipment Removed
- Equipment Stolen
- Cable Physically Damaged
- Construction / Furniture Activity Impact
- Room Maintenance Activity Impact
- Vandalism

### 13. OPERATIONAL / MONITORING EVENT
Use when the ticket disposition is operational rather than a confirmed technical failure.

Allowed subcategories:
- Auto-Recovered Monitoring Alert
- False Positive Monitoring Alert
- Duplicate Incident
- Related Existing Incident
- Covered by Problem Record
- Covered by Change / Request
- No Fault Found
- Unable to Reproduce
- Room Busy / In Use
- Room Under Maintenance
- Unsupported / Non-MTR Room
- No Action Required

### 14. UNKNOWN / UNCLEAR
Use when the evidence cannot support a more specific classification.

Allowed subcategories:
- Insufficient Technical Evidence
- Conflicting Evidence
- Cause Not Documented
- Resolution Without Confirmed Cause

### EVIDENCE PRIORITY
1. Final resolution notes and final technical work note
2. Confirmed onsite finding or failed/replaced component
3. Successful validation or test result
4. Resolution category and resolution code
5. Earlier diagnostics
6. Monitoring alert and short description

### DECISION RULES
- Replacement of a confirmed failed display → Hardware Component Failure / Display Hardware Failure.
- Reseated working display cable → Power / Connectivity Failure / Loose Cable Connection.
- Replaced faulty HDMI cable → Hardware Component Failure / HDMI Cable Failure.
- Incorrect display input → Display & Content-Sharing Failure / Input Source Misconfiguration.
- Camera absent from device list and restored after USB reseat → Camera & Video Pipeline Failure / Camera USB Enumeration Failure.
- Camera physically replaced → Hardware Component Failure / Camera Hardware Failure.
- MMR alert cleared with no repair → Operational / Monitoring Event / Auto-Recovered Monitoring Alert.
- Restart restored service but no cause was confirmed → Unknown / Unclear / Resolution Without Confirmed Cause.

### CRITICAL OUTPUT RULES
- Output one category and one valid matching subcategory.
- Copy labels exactly as written.
- Never pair a subcategory with the wrong category.
- Do not invent a component failure from a reboot, restart, or power cycle.
- If evidence is insufficient, use Unknown / Unclear and the closest matching unknown subcategory.
