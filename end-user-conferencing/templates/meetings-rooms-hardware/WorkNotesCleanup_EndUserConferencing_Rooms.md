## WorkNotesCleanup — End User Conferencing Rooms

### PURPOSE
Clean noisy work notes while preserving evidence required to identify the symptom, failed component, technical condition, action, validation, and final disposition.

### KEEP
- Room name, configuration item, asset identifier, and incident number.
- Reported or monitored symptom.
- Exact affected component: camera, microphone, speaker, display, projector, console, touch panel, MTR PC, UC engine, adapter, hub, extender, cable, power supply, PoE, controller, or room account.
- Exact hardware make/model when documented.
- Remote diagnostic findings from room-management or monitoring tools.
- Confirmed onsite findings.
- Evidence distinguishing defective, loose, disconnected, misconfigured, disabled, outdated, unreachable, or intentionally unplugged equipment.
- Reboot, restart, power-cycle, reseat, reconnect, reconfigure, update, rollback, repair, rebuild, and replacement actions.
- Component replacement and part details.
- Final validation such as test-call success, restored display, device online, user confirmation, auto-recovery, no fault found, duplicate, or unresolved state.
- KB, problem, change, request, RMA, warranty, and related-incident identifiers.

### REMOVE
- Repeated assignment, acknowledgement, transfer, and status-only updates.
- Repeated monitoring checks with no new evidence.
- Attachment notifications without described technical content.
- Greetings, signatures, personal names, user IDs, and email addresses.
- Repeated requests for the same physical check.
- Generic statements without a technical result.
- Unrelated troubleshooting from another service offering.

### NORMALIZATION RULES
- Preserve chronological order from earliest meaningful evidence to final outcome.
- Preserve negation and uncertainty.
- Do not change “suspected,” “possible,” or “not reproduced” into a confirmed cause.
- Do not treat a reboot as proof of component failure.
- Keep the difference between a failed cable and a disconnected working cable.
- Keep the difference between a failed component and a configuration/selection issue.
- Do not merge separate rooms, devices, or incidents.
- Remove personal information while keeping technical identifiers.

### REQUIRED OUTPUT
- Reported Symptom:
- Environment / Component:
- Diagnostic Findings:
- Actions Taken:
- Validation / Final State:
- Related References:

### OUTPUT RULES
- Include only source-supported facts.
- If no meaningful troubleshooting exists, output: Insufficient technical work-note evidence.
- Do not add root-cause labels in this cleanup output.
