## DetailedRootCause — Meetings - Rooms & Hardware

### CRITICAL INSTRUCTIONS – READ FIRST
Use this file to select one precise **Detailed Root Cause** after selecting the Root Cause Category and Root Cause Subcategory from `PossibleRootCause_EndUserConferencing_Rooms.md`.

This file provides the third and most detailed level of root-cause classification:

1. Root Cause Category — failure domain
2. Root Cause Subcategory — failed component or technical condition
3. Detailed Root Cause — precise failure mode supported by ticket evidence

Do not select a Detailed Root Cause only from the short description. Use final resolution notes, final technical work notes, confirmed onsite findings, component replacement details, and validation results.

### REQUIRED OUTPUT MODEL
Root Cause Category: <exact category>
Root Cause Subcategory: <exact matching subcategory>
Detailed Root Cause: <exact matching detailed root cause>

### GENERAL SELECTION RULES
- Select exactly one Detailed Root Cause.
- The Detailed Root Cause must belong to the selected Root Cause Subcategory.
- Prefer a confirmed cause over an observed symptom.
- Prefer the exact failed component or condition over a generic label.
- A reboot, restart, or power cycle is a remediation action and does not prove the root cause.
- A replaced component supports hardware failure only when the notes state that it was defective, failed testing, or replacement restored service.
- A reseated or reconnected component is not automatically defective.
- When multiple issues are documented, select the cause that drove the final repair or service restoration.
- When the cause is not documented, use the appropriate Unknown / Unclear value.

---

## 1. Hardware Component Failure

### Camera Hardware Failure
Allowed Detailed Root Causes:
- Camera Sensor Failure
- Camera Motor / PTZ Failure
- Camera Lens / Focus Mechanism Failure
- Camera Power Module Failure
- Camera Mainboard Failure
- Camera USB Interface Hardware Failure
- Camera Physical Damage
- Camera End-of-Life Failure
- Camera Hardware Failure — Unspecified

Use when the camera was confirmed defective or required physical replacement. Do not use for driver, firmware, USB enumeration, configuration, or framing issues.

### Microphone Hardware Failure
Allowed Detailed Root Causes:
- Microphone Capsule Failure
- Microphone Array Failure
- Microphone Control Module Failure
- Microphone Connector Failure
- Microphone Power Module Failure
- Microphone Physical Damage
- Microphone End-of-Life Failure
- Microphone Hardware Failure — Unspecified

### Speaker Hardware Failure
Allowed Detailed Root Causes:
- Speaker Driver Failure
- Speaker Amplifier Failure
- Speaker Control Module Failure
- Speaker Connector Failure
- Speaker Power Module Failure
- Speaker Physical Damage
- Speaker End-of-Life Failure
- Speaker Hardware Failure — Unspecified

### Display Hardware Failure
Allowed Detailed Root Causes:
- Display Panel Failure
- Display Backlight Failure
- Display Power Board Failure
- Display Mainboard Failure
- Display Input Port Hardware Failure
- Display Image Processing Failure
- Display Physical Damage
- Display End-of-Life Failure
- Display Hardware Failure — Unspecified

### Projector Hardware Failure
Allowed Detailed Root Causes:
- Projector Lamp Failure
- Projector Laser Source Failure
- Projector Power Supply Failure
- Projector Mainboard Failure
- Projector Input Port Hardware Failure
- Projector Optical Engine Failure
- Projector Cooling Fan Failure
- Projector Physical Damage
- Projector End-of-Life Failure
- Projector Hardware Failure — Unspecified

### Console Hardware Failure
Allowed Detailed Root Causes:
- Console Display Failure
- Console Touch Digitizer Failure
- Console Mainboard Failure
- Console USB Interface Hardware Failure
- Console Ethernet Interface Hardware Failure
- Console Power Module Failure
- Console Physical Damage
- Console End-of-Life Failure
- Console Hardware Failure — Unspecified

### Touch Panel Hardware Failure
Allowed Detailed Root Causes:
- Touch Panel Display Failure
- Touch Panel Digitizer Failure
- Touch Panel Mainboard Failure
- Touch Panel Network Interface Failure
- Touch Panel PoE Hardware Failure
- Touch Panel Physical Damage
- Touch Panel End-of-Life Failure
- Touch Panel Hardware Failure — Unspecified

### MTR PC / UC Engine Hardware Failure
Allowed Detailed Root Causes:
- MTR PC Mainboard Failure
- MTR PC Power Supply Failure
- MTR PC Processor Failure
- MTR PC Graphics Hardware Failure
- MTR PC Network Interface Hardware Failure
- MTR PC USB Port Hardware Failure
- UC Engine Hardware Failure
- MTR PC Physical Damage
- MTR PC End-of-Life Failure
- MTR PC / UC Engine Hardware Failure — Unspecified

### Storage / SSD Failure
Allowed Detailed Root Causes:
- SSD Read / Write Failure
- SSD Not Detected
- SSD Health Degradation
- SSD Controller Failure
- Storage Media Corruption
- Storage Hardware Failure — Unspecified

### Memory Failure
Allowed Detailed Root Causes:
- Memory Module Failure
- Memory Detection Failure
- Memory Hardware Instability
- Memory Hardware Failure — Unspecified

### Power Adapter / PSU Failure
Allowed Detailed Root Causes:
- External Power Adapter Failure
- Internal Power Supply Failure
- Power Brick Failure
- Power Cable Assembly Failure
- Unstable Power Output
- Power Adapter / PSU Failure — Unspecified

### PoE Injector Failure
Allowed Detailed Root Causes:
- PoE Injector Hardware Failure
- PoE Injector Port Failure
- PoE Injector Power Output Failure
- PoE Injector Failure — Unspecified

### HDMI Cable Failure
Allowed Detailed Root Causes:
- HDMI Cable Signal Failure
- HDMI Cable Connector Failure
- HDMI Cable Intermittent Failure
- HDMI Cable Physical Damage
- HDMI Cable Failure — Unspecified

### DisplayPort Cable Failure
Allowed Detailed Root Causes:
- DisplayPort Cable Signal Failure
- DisplayPort Connector Failure
- DisplayPort Cable Intermittent Failure
- DisplayPort Cable Physical Damage
- DisplayPort Cable Failure — Unspecified

### USB Cable Failure
Allowed Detailed Root Causes:
- USB Cable Data Failure
- USB Cable Power Failure
- USB Connector Failure
- USB Cable Intermittent Failure
- USB Cable Physical Damage
- USB Cable Failure — Unspecified

### Ethernet Cable Failure
Allowed Detailed Root Causes:
- Ethernet Cable Link Failure
- RJ45 Connector Failure
- Ethernet Cable Intermittent Failure
- Ethernet Cable Physical Damage
- Ethernet Cable Failure — Unspecified

### Adapter / Converter Failure
Allowed Detailed Root Causes:
- HDMI Adapter Failure
- DisplayPort Adapter Failure
- USB Adapter Failure
- USB-to-Ethernet Adapter Failure
- Video Converter Failure
- Signal Converter Failure
- Adapter / Converter Failure — Unspecified

### Hub / Extender Failure
Allowed Detailed Root Causes:
- USB Hub Failure
- HDMI Extender Failure
- USB Extender Failure
- Display Extender Failure
- Signal Distribution Hub Failure
- Hub / Extender Power Failure
- Hub / Extender Failure — Unspecified

### DSP Hardware Failure
Allowed Detailed Root Causes:
- DSP Processor Hardware Failure
- DSP Input Channel Failure
- DSP Output Channel Failure
- DSP Network Interface Failure
- DSP Power Supply Failure
- DSP Hardware Failure — Unspecified

### Room Controller Hardware Failure
Allowed Detailed Root Causes:
- Room Controller Mainboard Failure
- Room Controller Interface Failure
- Room Controller Network Hardware Failure
- Room Controller Power Failure
- Room Controller Hardware Failure — Unspecified

### Other Confirmed Hardware Failure
Allowed Detailed Root Causes:
- Confirmed Hardware Failure — Component Not Listed
- Multiple Confirmed Hardware Components Failed
- Hardware Failure — Exact Component Not Documented

---

## 2. Power / Connectivity Failure

### Device Powered Off
Allowed Detailed Root Causes:
- MTR PC Powered Off
- Display Powered Off
- Projector Powered Off
- Console Powered Off
- Touch Panel Powered Off
- Camera Powered Off
- Audio Device Powered Off
- Room System Powered Off — Device Unspecified

### Power Supply Disconnected
Allowed Detailed Root Causes:
- Device Power Cable Disconnected
- Power Adapter Disconnected
- Power Connector Loose
- Power Source Disconnected — Device Unspecified

### Power Strip / PDU Disconnected
Allowed Detailed Root Causes:
- Power Strip Switched Off
- Power Strip Unplugged
- PDU Connection Lost
- PDU Outlet Disabled

### Building Power Outage
Allowed Detailed Root Causes:
- Building Electrical Outage
- Room Electrical Circuit Outage
- Scheduled Electrical Maintenance
- Unstable Building Power

### PoE Connectivity Failure
Allowed Detailed Root Causes:
- PoE Cable Disconnected
- PoE Port Disabled
- PoE Power Not Delivered
- PoE Link Intermittent
- PoE Connectivity Failure — Unspecified

### Ethernet Link Failure
Allowed Detailed Root Causes:
- Ethernet Cable Disconnected
- Ethernet Link Down
- Ethernet Link Intermittent
- Network Adapter Link Not Established
- Ethernet Link Failure — Unspecified

### Network Port Failure
Allowed Detailed Root Causes:
- Wall Port Inactive
- Switch Port Disabled
- Switch Port Fault
- Incorrect Network Port Connection
- Network Port Failure — Unspecified

### Switch / VLAN Connectivity Failure
Allowed Detailed Root Causes:
- Network Switch Connectivity Failure
- VLAN Assignment Failure
- VLAN Configuration Mismatch
- Network Access Control Block
- Switch / VLAN Failure — Unspecified

### IP Address / Network Configuration Failure
Allowed Detailed Root Causes:
- Incorrect IP Address
- Duplicate IP Address
- DHCP Assignment Failure
- DNS Resolution Failure
- Gateway Configuration Failure
- Incorrect Device IP / MAC Record
- IP Configuration Failure — Unspecified

### Network Driver Failure
Allowed Detailed Root Causes:
- LAN Driver Initialization Failure
- LAN Driver Compatibility Failure
- LAN Driver Update Regression
- LAN Driver Rollback Required
- Network Driver Failure — Unspecified

### Loose Cable Connection
Allowed Detailed Root Causes:
- Loose HDMI Connection
- Loose DisplayPort Connection
- Loose USB Connection
- Loose Ethernet Connection
- Loose Power Connection
- Loose Peripheral Connection
- Loose Cable Connection — Unspecified

### Disconnected Cable
Allowed Detailed Root Causes:
- HDMI Cable Disconnected
- DisplayPort Cable Disconnected
- USB Cable Disconnected
- Ethernet Cable Disconnected
- Power Cable Disconnected
- Peripheral Cable Disconnected
- Disconnected Cable — Unspecified

### Peripheral Connectivity Failure
Allowed Detailed Root Causes:
- Camera Connectivity Lost
- Microphone Connectivity Lost
- Speaker Connectivity Lost
- Console Connectivity Lost
- Touch Panel Connectivity Lost
- Display Connectivity Lost
- Peripheral Connectivity Failure — Unspecified

### Device Unreachable / Offline
Allowed Detailed Root Causes:
- MTR PC Unreachable
- Console Unreachable
- Touch Panel Unreachable
- Display IP Unreachable
- Camera Unreachable
- Room System Offline — Cause Not Yet Isolated

### Intermittent Connectivity Failure
Allowed Detailed Root Causes:
- Intermittent Network Link
- Intermittent USB Connection
- Intermittent Video Connection
- Intermittent Peripheral Connection
- Intermittent Power Connection
- Intermittent Connectivity — Unspecified

---

## 3. Camera & Video Pipeline Failure

### Camera Driver Failure
Allowed Detailed Root Causes:
- Camera Driver Initialization Failure
- Camera Driver Corruption
- Camera Driver Compatibility Failure
- Camera Driver Update Regression
- Camera Driver Missing

### Camera USB Enumeration Failure
Allowed Detailed Root Causes:
- Camera Not Detected by USB
- Camera Intermittently Enumerated
- Camera Enumerated as Unknown Device
- Camera USB Device Lost After Restart
- Camera USB Enumeration Failure — Unspecified

### Camera Initialization Failure
Allowed Detailed Root Causes:
- Camera Failed to Initialize
- Camera Service Initialization Failure
- Camera Unavailable After Room Startup
- Camera Initialization Timeout

### Camera Capture / Rendering Failure
Allowed Detailed Root Causes:
- Camera Preview Blank
- Camera Video Frozen
- Camera Video Flickering
- Camera Capture Stream Failure
- Camera Video Rendering Failure
- Camera Image Corruption

### Camera Firmware Issue
Allowed Detailed Root Causes:
- Camera Firmware Outdated
- Camera Firmware Incompatible
- Camera Firmware Corrupted
- Camera Firmware Update Failed
- Camera Firmware Rollback Required

### Camera Configuration Issue
Allowed Detailed Root Causes:
- Camera Disabled in Settings
- Incorrect Default Camera Selected
- Camera Privacy Setting Blocked
- Camera Mode Misconfigured
- Camera Preset Misconfigured

### Camera Calibration / Framing Issue
Allowed Detailed Root Causes:
- Camera Framing Incorrect
- Camera Focus Incorrect
- Camera Position / Calibration Incorrect
- Camera Tracking Misconfigured
- Camera Preset Calibration Lost

### Content Camera Detection Failure
Allowed Detailed Root Causes:
- Content Camera Missing from Device List
- Content Camera Not Selected
- Content Camera Initialization Failure
- Content Camera USB Detection Failure

### Video Pipeline Failure
Allowed Detailed Root Causes:
- Video Capture Pipeline Failure
- Video Encoding Pipeline Failure
- Video Rendering Pipeline Failure
- Video Service Failure
- Video Pipeline Failure — Unspecified

---

## 4. Audio System Failure

### Audio Driver Failure
Allowed Detailed Root Causes:
- Audio Driver Initialization Failure
- Audio Driver Corruption
- Audio Driver Compatibility Failure
- Audio Driver Update Regression
- Audio Driver Missing

### Microphone Detection Failure
Allowed Detailed Root Causes:
- Microphone Not Detected
- Microphone Intermittently Detected
- Microphone Disabled in Settings
- Microphone Missing from Device List

### Speaker Detection Failure
Allowed Detailed Root Causes:
- Speaker Not Detected
- Speaker Intermittently Detected
- Speaker Disabled in Settings
- Speaker Missing from Device List

### USB Audio Enumeration Failure
Allowed Detailed Root Causes:
- USB Audio Device Not Enumerated
- USB Audio Device Lost
- USB Audio Device Detected as Unknown
- USB Audio Enumeration Intermittent

### Echo-Cancelling Device Configuration Failure
Allowed Detailed Root Causes:
- Echo-Cancelling Microphone Not Selected
- Echo-Cancelling Speaker Not Selected
- Echo-Cancelling Device Missing
- Incorrect Echo-Cancelling Peripheral Pairing

### Audio Processing Pipeline Failure
Allowed Detailed Root Causes:
- Audio Capture Pipeline Failure
- Audio Playback Pipeline Failure
- Audio Routing Failure
- Audio Service Failure
- Audio Processing Failure — Unspecified

### Audio Codec / Rendering Failure
Allowed Detailed Root Causes:
- Audio Codec Initialization Failure
- Audio Rendering Failure
- Audio Format Compatibility Failure
- Audio Stream Processing Failure

### DSP Configuration Failure
Allowed Detailed Root Causes:
- DSP Input Routing Misconfigured
- DSP Output Routing Misconfigured
- DSP Gain Misconfigured
- DSP Profile Misconfigured
- DSP Configuration Lost

### Audio Firmware Issue
Allowed Detailed Root Causes:
- Audio Device Firmware Outdated
- Audio Device Firmware Incompatible
- Audio Firmware Corrupted
- Audio Firmware Update Failed

### Audio Device Selection Issue
Allowed Detailed Root Causes:
- Incorrect Default Microphone Selected
- Incorrect Default Speaker Selected
- Incorrect Teams Audio Peripheral Selected
- Audio Device Selection Reset

### Echo / Feedback Configuration Issue
Allowed Detailed Root Causes:
- Acoustic Echo Configuration Issue
- Audio Feedback Loop
- Microphone Gain Too High
- Speaker Volume / Gain Misconfigured
- Recursive Dial Tone / Audio Loop

---

## 5. Display & Content-Sharing Failure

### HDMI Ingest Failure
Allowed Detailed Root Causes:
- HDMI Ingest Not Detected
- HDMI Ingest Signal Lost
- HDMI Ingest Intermittent
- HDMI Ingest Service Failure
- HDMI Ingest Failure — Unspecified

### DisplayPort Signal Failure
Allowed Detailed Root Causes:
- DisplayPort Signal Not Detected
- DisplayPort Link Intermittent
- DisplayPort Handshake Failure
- DisplayPort Signal Failure — Unspecified

### EDID Communication Failure
Allowed Detailed Root Causes:
- EDID Handshake Failure
- EDID Device Not Detected
- Incorrect EDID Profile
- EDID Adapter Communication Failure
- EDID Communication Failure — Unspecified

### Input Source Misconfiguration
Allowed Detailed Root Causes:
- Incorrect Display Input Selected
- Incorrect Projector Input Selected
- Display Input Auto-Detection Failure
- Input Source Changed Manually
- Dual-Display Input Assignment Incorrect

### Resolution / Refresh Rate Misconfiguration
Allowed Detailed Root Causes:
- Unsupported Display Resolution
- Incorrect Display Resolution
- Unsupported Refresh Rate
- Incorrect Refresh Rate
- Dual-Display Resolution Mismatch

### Display Orientation Configuration Issue
Allowed Detailed Root Causes:
- Display Rotation Incorrect
- Projector Image Orientation Incorrect
- Display Arrangement Incorrect
- Primary / Secondary Display Assignment Incorrect

### Display Power-Save / Standby Issue
Allowed Detailed Root Causes:
- Display Stuck in Standby
- Display Power-Save Configuration Issue
- Display Wake Failure
- Display Sleep State Not Cleared

### Front-of-Room Output Failure
Allowed Detailed Root Causes:
- Front-of-Room Display Blank
- Front-of-Room Video Output Lost
- Front-of-Room Output Intermittent
- Front-of-Room Output Frozen
- Front-of-Room Output Failure — Unspecified

### Content Sharing Path Failure
Allowed Detailed Root Causes:
- Laptop Content Not Presented
- Sharing Signal Not Routed
- Content Sharing Adapter Path Failure
- Content Sharing Service Failure
- Content Sharing Path Failure — Unspecified

### Display Firmware Issue
Allowed Detailed Root Causes:
- Display Firmware Outdated
- Display Firmware Incompatible
- Display Firmware Corrupted
- Display Firmware Update Failed

### Projector Configuration Issue
Allowed Detailed Root Causes:
- Projector Input Misconfigured
- Projector Resolution Misconfigured
- Projector Display Mode Misconfigured
- Projector Power-Save Misconfigured
- Projector Configuration Issue — Unspecified

---

## 6. Room Controller / Integration Failure

### Console Communication Failure
Allowed Detailed Root Causes:
- Console Lost Communication with MTR PC
- Console Communication Intermittent
- Console Control Service Failure
- Console Communication Failure — Unspecified

### Touch Panel Communication Failure
Allowed Detailed Root Causes:
- Touch Panel Lost Communication with Controller
- Touch Panel Network Communication Failure
- Touch Panel Communication Intermittent
- Touch Panel Communication Failure — Unspecified

### Console Pairing Failure
Allowed Detailed Root Causes:
- Console Not Paired
- Console Pairing Lost
- Console Pairing Configuration Invalid
- Console Re-Pairing Required

### Room Controller Integration Failure
Allowed Detailed Root Causes:
- Controller Integration Service Failure
- Controller Command Routing Failure
- Controller Device Mapping Failure
- Controller Integration Failure — Unspecified

### UC Engine Integration Failure
Allowed Detailed Root Causes:
- UC Engine Lost Peripheral Communication
- UC Engine Console Integration Failure
- UC Engine Display Integration Failure
- UC Engine Integration Failure — Unspecified

### Peripheral Integration Failure
Allowed Detailed Root Causes:
- Camera Integration Failure
- Audio Peripheral Integration Failure
- Display Integration Failure
- Multi-Peripheral Synchronization Failure
- Peripheral Integration Failure — Unspecified

### Room Device Synchronization Failure
Allowed Detailed Root Causes:
- Console and Display Synchronization Failure
- Controller and Peripheral Synchronization Failure
- Room Device State Synchronization Failure
- Room Device Synchronization Failure — Unspecified

### Controller Firmware Issue
Allowed Detailed Root Causes:
- Controller Firmware Outdated
- Controller Firmware Incompatible
- Controller Firmware Corrupted
- Controller Firmware Update Failed

---

## 7. Teams Room Application Failure

### MTR Application Failure
Allowed Detailed Root Causes:
- MTR Application Not Running
- MTR Application Unresponsive
- MTR Application Startup Failure
- MTR Application Service Failure
- MTR Application Failure — Unspecified

### Teams Media Stack Failure
Allowed Detailed Root Causes:
- Teams Media Service Failure
- Teams Audio Stack Failure
- Teams Video Stack Failure
- Teams Media Transport Failure
- Teams Media Stack Failure — Unspecified

### Meeting App Freeze / Crash
Allowed Detailed Root Causes:
- Meeting App Frozen
- Meeting App Crashed
- Meeting App Repeatedly Restarting
- Meeting App Not Responding

### Meeting Join Failure
Allowed Detailed Root Causes:
- Unable to Join Scheduled Meeting
- Join Button Unavailable
- Meeting Launch Failure
- Meeting Join Timeout
- Meeting Join Failure — Unspecified

### Application Service Failure
Allowed Detailed Root Causes:
- Required Service Stopped
- Required Service Failed to Start
- Application Backend Service Failure
- Application Service Intermittent

### Application Update Failure
Allowed Detailed Root Causes:
- MTR Application Update Failed
- Application Version Incompatible
- Application Update Incomplete
- Application Rollback Required

### Windows Update Failure
Allowed Detailed Root Causes:
- Windows Update Installation Failed
- Windows Update Pending Restart
- Windows Update Regression
- Windows Update Incomplete

### Operating System Corruption
Allowed Detailed Root Causes:
- Operating System File Corruption
- Operating System Boot Failure
- Operating System Service Corruption
- Operating System Reimage Required

### Application Configuration Failure
Allowed Detailed Root Causes:
- MTR Application Configuration Invalid
- Room Application Profile Incorrect
- Application Setting Reset
- Application Configuration Failure — Unspecified

---

## 8. Account / Authentication Failure

### Room Account Sign-In Failure
Allowed Detailed Root Causes:
- Room Account Unable to Sign In
- Room Account Sign-In Loop
- Room Account Session Expired
- Room Account Sign-In Failure — Unspecified

### Password / Credential Failure
Allowed Detailed Root Causes:
- Room Account Password Expired
- Incorrect Room Account Password
- Stored Credential Invalid
- Credential Synchronization Failure

### Forced Password Change Issue
Allowed Detailed Root Causes:
- Force Password Change Enabled
- Password Change Required at Next Sign-In
- Room Account Blocked by Password Change Requirement

### Account Disabled / Locked
Allowed Detailed Root Causes:
- Room Account Disabled
- Room Account Locked
- Room Account Access Revoked
- Room Account State Failure — Unspecified

### Authentication Token Failure
Allowed Detailed Root Causes:
- Authentication Token Expired
- Authentication Token Invalid
- Token Refresh Failure
- Cached Token Corruption

### Conditional Access / Policy Issue
Allowed Detailed Root Causes:
- Conditional Access Block
- Sign-In Policy Block
- Device Compliance Policy Block
- Authentication Policy Misconfiguration

### Account Configuration Failure
Allowed Detailed Root Causes:
- Incorrect Room Account Assigned
- Room Account Configuration Incomplete
- Room Account License / Service Configuration Issue
- Account Configuration Failure — Unspecified

---

## 9. Calendar / Resource Integration Failure

### Calendar Sync Failure
Allowed Detailed Root Causes:
- Calendar Not Synchronizing
- Calendar Updates Delayed
- Calendar Service Connection Failure
- Calendar Sync Intermittent
- Calendar Sync Failure — Unspecified

### Resource Mailbox Failure
Allowed Detailed Root Causes:
- Resource Mailbox Unavailable
- Resource Mailbox Misconfigured
- Resource Mailbox Permission Failure
- Resource Mailbox Processing Failure

### Room Booking Conflict
Allowed Detailed Root Causes:
- Conflicting Room Reservation
- Double Booking
- Booking Policy Conflict
- Existing Reservation Not Reflected

### Recurring Reservation Issue
Allowed Detailed Root Causes:
- Recurring Meeting Not Processed
- Recurring Reservation Conflict
- Recurring Series Update Failure
- Recurring Reservation Issue — Unspecified

### Room Approval / Permission Issue
Allowed Detailed Root Causes:
- Booking Approval Required
- Booking Permission Missing
- Delegate Approval Failure
- Restricted Room Booking Policy

### Scheduling Panel Sync Failure
Allowed Detailed Root Causes:
- Scheduling Panel Calendar Not Updated
- Scheduling Panel Shows Incorrect Availability
- Scheduling Panel Connection Failure
- Scheduling Panel Sync Failure — Unspecified

### Calendar Configuration Failure
Allowed Detailed Root Causes:
- Calendar Processing Configuration Incorrect
- Booking Window Configuration Incorrect
- Auto-Accept Configuration Incorrect
- Room Calendar Configuration Failure — Unspecified

### Time Zone Configuration Issue
Allowed Detailed Root Causes:
- Room Time Zone Incorrect
- Calendar Time Zone Mismatch
- System and Mailbox Time Zone Mismatch
- Time Zone Configuration Issue — Unspecified

---

## 10. Device Firmware / Driver Failure

### Device Firmware Incompatibility
Allowed Detailed Root Causes:
- Firmware Incompatible with Room Platform
- Peripheral Firmware Version Mismatch
- Firmware Compatibility Failure — Unspecified

### Device Firmware Corruption
Allowed Detailed Root Causes:
- Firmware Image Corrupted
- Firmware Boot Failure
- Firmware State Corrupted

### Unsupported Firmware Version
Allowed Detailed Root Causes:
- Firmware Below Supported Version
- Firmware Above Validated Version
- Unsupported Firmware Branch

### Firmware Update Failure
Allowed Detailed Root Causes:
- Firmware Installation Failed
- Firmware Update Interrupted
- Firmware Update Incomplete
- Firmware Update Repeatedly Failed

### Firmware Rollback Required
Allowed Detailed Root Causes:
- Firmware Regression
- Firmware Rollback Restored Service
- Previous Firmware Version Required

### Generic Device Driver Failure
Allowed Detailed Root Causes:
- Device Driver Missing
- Device Driver Corrupted
- Device Driver Failed to Initialize
- Generic Device Driver Failure — Unspecified

### Driver Compatibility Failure
Allowed Detailed Root Causes:
- Driver Incompatible with Operating System
- Driver Version Mismatch
- Driver Update Regression
- Driver Rollback Restored Service

---

## 11. Compute / Resource Failure

### CPU Resource Exhaustion
Allowed Detailed Root Causes:
- Sustained High CPU Utilization
- Application CPU Contention
- CPU Resource Exhaustion — Unspecified

### Memory Resource Exhaustion
Allowed Detailed Root Causes:
- Insufficient Available Memory
- Application Memory Leak
- Memory Pressure
- Memory Resource Exhaustion — Unspecified

### GPU Resource Exhaustion
Allowed Detailed Root Causes:
- GPU Utilization Saturation
- Video Processing Resource Exhaustion
- GPU Resource Exhaustion — Unspecified

### Disk Capacity / Resource Exhaustion
Allowed Detailed Root Causes:
- Disk Space Exhausted
- Temporary Storage Exhausted
- Log Growth Exhausted Storage
- Disk Resource Exhaustion — Unspecified

### Operating System Performance Failure
Allowed Detailed Root Causes:
- Operating System Unresponsive
- Operating System Service Contention
- System Performance Degradation
- Operating System Performance Failure — Unspecified

### BIOS Configuration Issue
Allowed Detailed Root Causes:
- BIOS Setting Misconfigured
- BIOS Version Incompatible
- BIOS Update Required
- BIOS Configuration Reset Required

### Compute Platform Instability
Allowed Detailed Root Causes:
- Repeated System Freeze
- Repeated Unexpected Restart
- Compute Platform Intermittent Failure
- Compute Platform Instability — Unspecified

---

## 12. Physical Damage / Tampering

### Equipment Unplugged
Allowed Detailed Root Causes:
- Camera Unplugged
- Microphone Unplugged
- Speaker Unplugged
- Display Unplugged
- Console Unplugged
- Touch Panel Unplugged
- MTR PC Unplugged
- Network Cable Unplugged
- Power Equipment Unplugged
- Equipment Unplugged — Component Unspecified

### Equipment Intentionally Powered Off
Allowed Detailed Root Causes:
- MTR PC Intentionally Powered Off
- Display Intentionally Powered Off
- Projector Intentionally Powered Off
- Console Intentionally Powered Off
- Room System Intentionally Powered Off — Unspecified

### Equipment Damaged
Allowed Detailed Root Causes:
- Camera Physically Damaged
- Microphone Physically Damaged
- Speaker Physically Damaged
- Display Physically Damaged
- Console Physically Damaged
- Touch Panel Physically Damaged
- Room Equipment Damaged — Unspecified

### Equipment Dismantled
Allowed Detailed Root Causes:
- Room System Dismantled
- Peripheral Removed from Installation
- Cabling Dismantled
- Equipment Dismantled — Unspecified

### Equipment Removed
Allowed Detailed Root Causes:
- Camera Removed
- Display Removed
- Console Removed
- Touch Panel Removed
- MTR PC Removed
- Room Equipment Removed — Unspecified

### Equipment Stolen
Allowed Detailed Root Causes:
- MTR PC Stolen
- Camera Stolen
- Display Stolen
- Peripheral Stolen
- Room Equipment Stolen — Unspecified

### Cable Physically Damaged
Allowed Detailed Root Causes:
- HDMI Cable Physically Damaged
- DisplayPort Cable Physically Damaged
- USB Cable Physically Damaged
- Ethernet Cable Physically Damaged
- Power Cable Physically Damaged
- Cable Physically Damaged — Type Unspecified

### Construction / Furniture Activity Impact
Allowed Detailed Root Causes:
- Room Construction Disconnected Equipment
- Furniture Work Disconnected Equipment
- Room Rebuild Changed Cabling
- Construction / Furniture Impact — Unspecified

### Room Maintenance Activity Impact
Allowed Detailed Root Causes:
- Planned Maintenance Powered Down Equipment
- Maintenance Work Disconnected Equipment
- Room Upgrade Temporarily Disabled System
- Maintenance Activity Impact — Unspecified

### Vandalism
Allowed Detailed Root Causes:
- Intentional Cable Disconnection
- Intentional Equipment Damage
- Intentional Equipment Removal
- Repeated Unauthorized Room-System Alteration
- Vandalism — Exact Action Not Documented

---

## 13. Operational / Monitoring Event

### Auto-Recovered Monitoring Alert
Allowed Detailed Root Causes:
- Monitoring Alert Cleared Automatically
- Device Health Restored Without Manual Action
- Transient Alert Auto-Recovered
- Auto-Recovered Alert — Exact Condition Not Documented

### False Positive Monitoring Alert
Allowed Detailed Root Causes:
- Room Healthy During Alert
- Monitoring State Incorrect
- Monitoring Data Stale
- False Positive Alert — Exact Trigger Not Documented

### Duplicate Incident
Allowed Detailed Root Causes:
- Duplicate of Existing Incident
- Repeated Alert for Same Active Incident
- Duplicate Ticket Created by Monitoring

### Related Existing Incident
Allowed Detailed Root Causes:
- Covered by Active Incident
- Associated with Parent Incident
- Related Site-Wide Incident
- Related Existing Incident — Reference Not Documented

### Covered by Problem Record
Allowed Detailed Root Causes:
- Known Problem Record
- Recurring Issue Tracked by Problem
- Resolution Deferred to Problem Record

### Covered by Change / Request
Allowed Detailed Root Causes:
- Fix Delivered by Change
- Room Upgrade Covered by Request
- Scheduled Work Covered by Change
- Covered by Change / Request — Unspecified

### No Fault Found
Allowed Detailed Root Causes:
- Room Tested Healthy
- Component Tested Healthy
- User-Reported Failure Not Reproduced
- Monitoring and Onsite Checks Healthy
- No Fault Found — Validation Not Detailed

### Unable to Reproduce
Allowed Detailed Root Causes:
- Intermittent Issue Not Reproduced
- Issue Cleared Before Investigation
- User Scenario Not Reproduced
- Unable to Reproduce — Unspecified

### Room Busy / In Use
Allowed Detailed Root Causes:
- Physical Validation Blocked by Active Meeting
- Repair Deferred Because Room Was Occupied
- Testing Limited Because Room Was in Use

### Room Under Maintenance
Allowed Detailed Root Causes:
- Room Closed for Maintenance
- Room System Under Upgrade
- Room Awaiting Repair Part
- Room Under Rebuild
- Room Under Maintenance — Unspecified

### Unsupported / Non-MTR Room
Allowed Detailed Root Causes:
- Non-MTR Room
- Unsupported Room Hardware
- Unsupported Site / Building
- Room Not Managed by Service

### No Action Required
Allowed Detailed Root Causes:
- Alert Cleared Before Action
- User Confirmed Service Working
- Existing Resolution Already Applied
- No Technical Action Required — Unspecified

---

## 14. Unknown / Unclear

### Insufficient Technical Evidence
Allowed Detailed Root Causes:
- Work Notes Missing
- Resolution Notes Missing
- Symptom Only — No Diagnostic Evidence
- Monitoring Alert Only — No Technical Evidence

### Conflicting Evidence
Allowed Detailed Root Causes:
- Work Notes and Resolution Conflict
- Multiple Possible Causes
- Conflicting Remote and Onsite Findings
- Conflicting Component Evidence

### Cause Not Documented
Allowed Detailed Root Causes:
- Resolution Documented but Cause Missing
- Replacement Documented but Failure Mode Missing
- Ticket Closed Without Cause
- Cause Not Documented — Unspecified

### Resolution Without Confirmed Cause
Allowed Detailed Root Causes:
- Reboot Restored Service — Cause Unconfirmed
- Restart Restored Service — Cause Unconfirmed
- Power Cycle Restored Service — Cause Unconfirmed
- Reconnection Restored Service — Failed Element Unconfirmed
- Configuration Refresh Restored Service — Cause Unconfirmed

## 15. Out of Scope / Misrouted

Use only when the primary category is Excluded / Out of Scope and the ticket is not a Rooms service failure.

Allowed Detailed Root Causes:
- Out of Scope - Not a Rooms Root Cause

---

## CONFIDENCE GUIDANCE

### High
Use when:
- A failed component was confirmed and replaced.
- Onsite findings explicitly identify the condition.
- A specific configuration, firmware, driver, account, or integration issue was verified.
- The documented corrective action directly addresses the confirmed cause and validation passed.

### Medium
Use when:
- The symptom and resolution are clear, but the exact failure mode is not fully confirmed.
- Evidence strongly supports one cause but does not include component testing or explicit confirmation.
- A device was reconnected or reconfigured and service was restored, but the underlying reason is partly inferred.

### Low
Use when:
- Only monitoring or short-description evidence exists.
- Notes are sparse, contradictory, or generic.
- The issue cleared before investigation.
- Reboot, restart, or power cycle restored service without confirming the condition.

## FINAL OUTPUT FORMAT
Root Cause Category: <exact category from PossibleRootCause_EndUserConferencing_Rooms.md>
Root Cause Subcategory: <exact matching subcategory>
Detailed Root Cause: <exact matching detailed root cause from this file>
Confidence Level: <High|Medium|Low>
Evidence: <short supporting phrases from work notes separated by " / ">

## CRITICAL OUTPUT RULES
- Use only labels defined in the approved root-cause files.
- Do not create new labels during ticket processing.
- Do not use a Detailed Root Cause from a different subcategory.
- Do not classify a component as failed solely because it was restarted, power-cycled, or reconnected.
- Do not classify an unplugged working component as Hardware Component Failure.
- When the exact hardware failure mode is not documented, use the relevant “Failure — Unspecified” value.
- When the cause itself is not supported, use Unknown / Unclear rather than forcing a component label.
