# EnvironmentContext — End User Conferencing Rooms

## CRITICAL INSTRUCTIONS – READ FIRST

Use this file for AI analysis only. Do not repeat this context in ticket summaries. Use it to understand Rooms scope, common room hardware failure patterns, and what is outside the service offering.

## PURPOSE
Provide the AI with context about what the Meetings - Rooms and Hardware service covers and what is out of scope.

---

## WHAT ROOMS COVERS

Rooms is responsible for meeting room systems and conferencing hardware used for scheduled meetings.

**In-scope areas:**
- Room devices and conferencing appliances
- Displays, content sharing, and presentation output
- Cameras, microphones, speakers, and controllers
- Room booking and reservation workflows
- Room client or app issues tied to the room system
- Touch panels, consoles, and front-of-room units
- HDMI ingest and cable-related presentation paths
- Room online/offline state and basic device health

**Typical users:**
- Employees using meeting rooms
- Support staff troubleshooting room systems
- Users reporting camera, microphone, display, or controller issues
- Users asking about booking or joining a room meeting
- Users reporting console freezes, unresponsive touch panels, or camera/speaker module issues

---

## WHAT IS OUT OF SCOPE

The following are not Rooms incidents:
- Teams chat or calling issues on personal devices
- Laptop or endpoint issues unrelated to the room system
- Non-conferencing applications
- Generic infrastructure issues unless the room system is clearly impacted
- Pure software issues outside the room system unless the room app itself is the reported failure

If the issue is not clearly about room devices, displays, cameras, microphones, controllers, or reservations, use Unknown / Unclear.

## CSV-BASED SIGNALS TO LOOK FOR

| Signal in short description or work notes | Likely symptom |
|---|---|
| "offline" | Room Device Offline |
| "console", "touch panel", "unresponsive", "freezing" | Room Peripheral Failure or Room Client / App Failure |
| "camera", "microphone", "speaker", "audio" | Room Audio / Video Issue or Room Peripheral Failure |
| "display", "monitor", "front of room", "doesn't work" | Room Display / Sharing Issue |
| "HDMI ingest", "can't present", "share" | Room Display / Sharing Issue |
| "calendar sync" | Room Scheduling / Reservation Issue |
| "sign in (Teams)", "meeting app" | Room Client / App Failure |
| "unplug power" | Room Power / Connectivity Issue |
