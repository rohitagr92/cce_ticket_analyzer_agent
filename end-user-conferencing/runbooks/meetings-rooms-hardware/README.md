# Meetings - Rooms and Hardware

Service-offering folder for meeting-room and device hardware incidents within End User Conferencing.

Scope:
- Rooms and hardware incidents
- Meeting room peripherals
- Cameras, microphones, displays, and room devices
- Room booking and room device workflow issues

Azure assets used by this service offering:
- Storage account: `opswconferblob`
- Key Vault: `opswconferkeyvault`
- Automation account: `opswconferautomation`

Runbooks planned for this folder:
- `incident-trend-backfill-rb-euc-rooms`
- `incident-analyzer-rb-euc-rooms`

This folder is intentionally isolated so future Rooms and Hardware changes do not affect the Messaging offering.
