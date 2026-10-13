## WorkNotesCleanup — Messaging - Teams Chat and Audio

### PURPOSE
Remove ticket noise while preserving evidence necessary to identify the Teams chat/audio symptom, environment, cause, action, and outcome.

### KEEP
- Incident number and exact error message.
- Affected Teams surface: desktop, web, mobile, group chat, meeting chat, channel, external chat, audio, status, notification, voicemail, or call history.
- Comparison across desktop, web, and mobile.
- Whether chats/messages were missing, deleted, delayed, unsent, unavailable, or not loading.
- Whether microphone, speaker, headset, Bluetooth, status, notification, or external access was affected.
- Teams version, Windows version, audio/Bluetooth driver version, device model, and relevant BIOS/firmware version when documented.
- Verified policy, retention, OOO calendar, Windows notification, permission, device-selection, proxy, network, or account findings.
- Cache clear, Repair, Reset, sign-out/sign-in, quit/relaunch, update, reinstall, driver rollback/update, BIOS update, device selection, permission change, and calendar correction.
- Whether remediation was temporary or permanent and whether the issue recurred.
- Logs collected and escalation references when they affected disposition.
- Known-issue, Microsoft tracking, problem, major incident, change, request, or KB identifiers.
- Final user validation, workaround, escalation, on-hold state, or closure basis.

### REMOVE
- Repeated assignment, acknowledgement, transfer, callback, and status-only notes.
- Template fields with no value or marked NA.
- Remote-access disclaimers, greetings, signatures, personal names, phone numbers, email addresses, and user IDs.
- Attachment notifications without described evidence.
- Repeated troubleshooting steps that add no new outcome.
- Generic statements such as “checked the issue” without findings.

### NORMALIZATION RULES
- Preserve chronological order.
- Preserve exact errors, versions, incident/problem/KB references, and client comparisons.
- Preserve uncertainty and recurrence.
- Do not convert a successful generic reset into a confirmed cache or profile root cause.
- Distinguish missing history from retention-based deletion.
- Distinguish hardware failure from driver, enumeration, selection, permission, or Bluetooth connectivity issues.
- Remove personal information while retaining technical identifiers.

### REQUIRED OUTPUT
- Reported Symptom:
- Environment / Scope:
- Diagnostic Findings:
- Actions Taken:
- Validation / Final State:
- Related References:

### OUTPUT RULES
- Include only source-supported facts.
- If there is no meaningful technical evidence, output: Insufficient technical work-note evidence.
