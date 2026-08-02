# Messaging - Teams Chat and Audio

Service-offering folder for the Messaging portion of End User Conferencing.

Scope:
- Teams chat issues
- Teams audio / calling issues
- Teams meeting join and chat-related incidents

Azure assets used by this service offering:
- Storage account: `opswconferblob`
- Key Vault: `opswconferkeyvault`
- Automation account: `opswconferautomation`

Runbooks planned for this folder:
- `incident-trend-backfill-rb-euc-messaging`
- `incident-analyzer-rb-euc-messaging`

This folder is intentionally isolated so future Messaging changes do not affect the Rooms and Hardware offering.
