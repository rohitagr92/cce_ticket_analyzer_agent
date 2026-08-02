# EnvironmentContext — End User Conferencing Messaging

## CRITICAL INSTRUCTIONS – READ FIRST

Use this file for AI analysis only. Do not repeat this context in ticket summaries. Use it to understand Messaging scope, common Teams failure patterns, and what is outside the service offering.

## PURPOSE
Provide the AI with context about what the Messaging - Teams Chat and Audio service covers and what is out of scope.

---

## WHAT MESSAGING COVERS

Messaging is responsible for Microsoft Teams chat, calling, presence, notifications, call logs, and related Outlook integration issues.

**In-scope areas:**
- Teams desktop and web client issues
- Chat history missing, blank, not loading, disappearing, or not reflecting
- Message send and receive failures
- Audio and microphone issues during Teams calls
- Teams notifications not appearing
- Presence / status problems, including stuck Out of Office
- Outlook-Teams calendar integration and Teams add-in issues
- Call log visibility issues
- Admin-disabled chat or Teams functionality when the symptom is clearly on Teams
- Sign-in and client access issues tied to Teams

**Typical users:**
- Employees using Teams chat or calls
- Users reporting missing chat history or deleted messages
- Users having issues with Teams presence or notifications
- Users asking about meeting scheduling or the Outlook add-in
- Users reporting missing call logs or recent activity

---

## WHAT IS OUT OF SCOPE

The following are not Messaging incidents:
- Meeting room hardware failures
- General laptop or device issues not tied to Teams
- Non-conferencing business applications
- Generic network issues unless the evidence clearly points to Teams
- Generic account problems unless the issue is specifically Teams sign-in, Teams access, or Teams permissions

If the issue is not clearly about Teams chat, calls, status, notifications, login, or Outlook integration, use Unknown / Unclear.

## CSV-BASED SIGNALS TO LOOK FOR

| Signal in short description or work notes | Likely symptom |
|---|---|
| "missing chat", "missing chats", "chat history missing", "old chats not reflecting" | Chat History Missing / Not Visible |
| "unable to send", "messages will not send", "cannot chat" | Message Send Failure |
| "messages are not getting delivered", "not updating", "not reflecting" | Message Receive / Delivery Failure |
| "audio issue", "cannot hear", "mic issue", "microphone" | Audio / Microphone Issue |
| "notifications are not appearing" | Notifications Missing |
| "out of office", "status is not turning off", "status stuck" | Presence / Status Issue |
| "unable to login", "cannot sign in" | Teams Login / Access Issue |
| "call log" | Call Log / Activity Issue |
| "administrator has disabled chat" | Administrator Disabled Feature |
