## EnvironmentContext — End User Conferencing Rooms

### CRITICAL INSTRUCTIONS
Use this file only to interpret and classify Meetings - Rooms & Hardware incidents. Do not copy this general context into individual ticket summaries.

### SERVICE SCOPE
In-scope areas:
- Microsoft Teams Rooms and supported room systems
- MTR PC and UC engine
- Console, controller, and touch panel
- Front-of-room display, monitor, and projector
- HDMI ingest, EDID, adapters, hubs, extenders, and presentation path
- Camera, microphone, speaker, DSP, and conferencing peripherals
- Room application, meeting join, and room sign-in
- Room mailbox, calendar sync, booking, and reservations
- Power, PoE, Ethernet, network port, cabling, and room health
- Hardware replacement, firmware, driver, BIOS, and configuration activity

Out-of-scope areas:
- Personal Teams chat or calling issues unrelated to a room
- General laptop, mobile, desktop, VPN, or endpoint incidents
- Non-conferencing applications
- Infrastructure incidents with no demonstrated room impact
- Work owned by another service offering

### ROOT-CAUSE INTERPRETATION MODEL
Classify causes at two levels:
1. Root Cause Category identifies the failure domain.
2. Root Cause Subcategory identifies the exact component or technical condition.

Avoid the blanket label Hardware Component Failure when the evidence identifies the individual component. Examples:
- Failed camera → Hardware Component Failure / Camera Hardware Failure
- Failed microphone → Hardware Component Failure / Microphone Hardware Failure
- Failed display → Hardware Component Failure / Display Hardware Failure
- Faulty HDMI cable → Hardware Component Failure / HDMI Cable Failure
- Loose HDMI cable → Power / Connectivity Failure / Loose Cable Connection
- Wrong display input → Display & Content-Sharing Failure / Input Source Misconfiguration

### COMMON INTERPRETATION RISKS
- A reboot is a remediation action, not proof of root cause.
- A powered-off or unplugged working device is not automatically defective.
- A missing USB device may be an enumeration or connection failure rather than a failed peripheral.
- A replaced component provides stronger failure evidence than an early monitoring alert.
- A room may appear healthy remotely while onsite evidence identifies a physical problem.
- An alert that cleared automatically may be an operational event rather than a confirmed failure.
- Recurring alerts should not automatically inherit the earlier cause without matching evidence.

### EVIDENCE HIERARCHY
1. Final resolution notes and final technical work note
2. Confirmed onsite finding or replaced component
3. Successful validation or test result
4. Resolution category and resolution code
5. Earlier diagnostics
6. Monitoring alert and short description

### CLASSIFICATION SAFEGUARDS
- Use component-specific hardware labels only with confirmed failure or replacement evidence.
- Use disconnection/connectivity labels for loose or disconnected working components.
- Use configuration labels for incorrect input, selection, resolution, refresh rate, time zone, or settings.
- Use firmware/driver labels only when notes document those conditions.
- Use Physical Damage / Tampering only when explicitly supported.
- Use Operational / Monitoring Event for auto-recovery, duplicates, no-fault-found, or unsupported-room outcomes.
- Use Unknown / Unclear when evidence is insufficient or conflicting.
