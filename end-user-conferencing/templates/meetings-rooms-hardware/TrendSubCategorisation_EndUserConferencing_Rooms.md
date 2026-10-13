## TrendSubCategorisation — End User Conferencing Rooms

### PURPOSE
Select exactly one user-observable trend label. This describes what appeared broken, not the technical root cause.

### ALLOWED TREND LABELS
- Room Offline
- Console / Touch Panel
- Display / Front of Room
- HDMI / Content Sharing
- Camera
- Microphone
- Speaker / Audio Output
- Call Quality / Echo
- Meeting App / Join
- Sign-in / Authentication
- Scheduling / Reservation
- Network Connectivity
- Power
- Performance / Freeze
- Physical Damage / Tampering
- Monitoring Alert / Auto-Recovered
- Duplicate / Related Ticket
- Unknown / Unclear

### GUIDANCE
- Room Offline: room or room system was unavailable, unreachable, unhealthy, or explicitly offline.
- Console / Touch Panel: console, controller, or touch panel was blank, frozen, disconnected, or unresponsive.
- Display / Front of Room: monitor, projector, front-of-room display, flicker, blank image, resolution, or orientation issue.
- HDMI / Content Sharing: HDMI ingest, laptop presentation, EDID, adapter, or sharing-path issue.
- Camera: camera unavailable, disabled, disconnected, unfocused, incorrectly framed, or failed.
- Microphone: microphone missing, muted, disconnected, not detected, or providing poor input.
- Speaker / Audio Output: speaker silent, unavailable, disconnected, distorted, or incorrectly selected.
- Call Quality / Echo: echo, feedback, latency, jitter, or degraded in-call media quality.
- Meeting App / Join: room client, Teams app, meeting launch, join, freeze, or crash.
- Sign-in / Authentication: room sign-in, password, credential, or access failure.
- Scheduling / Reservation: booking, calendar sync, room mailbox, approval, or reservation conflict.
- Network Connectivity: LAN, VLAN, switch, port, Ethernet, IP, or online-connectivity symptom.
- Power: room equipment visibly powered off or without power.
- Performance / Freeze: room system slow, hanging, or intermittently frozen.
- Physical Damage / Tampering: equipment damaged, stolen, unplugged, dismantled, moved, or intentionally altered.
- Monitoring Alert / Auto-Recovered: monitoring alert cleared and no user-visible failure was confirmed.
- Duplicate / Related Ticket: duplicate, repeat, or already-covered incident.
- Unknown / Unclear: reliable user-observable symptom is not documented.

### RULES
1. Use the reported user-visible symptom first.
2. If no user report exists, use the monitoring symptom.
3. For multiple symptoms, select the symptom driving the service impact or final fix.
4. Do not use root-cause language as the trend label.
5. Output exactly one label without explanation or punctuation.
