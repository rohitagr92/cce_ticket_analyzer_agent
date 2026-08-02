# PossibleRootCause — End User Conferencing Messaging

## CRITICAL INSTRUCTIONS – READ FIRST

Use this file to choose one technical/system-level root-cause label for Messaging incidents. Do not turn the label into a sentence. Narrative belongs in AI Analysis.

## PURPOSE
Provide short, bold root-cause labels that the AI can reuse consistently.

## RULES
- Use only the labels listed here.
- Keep the output short and specific.
- Prefer a concrete root cause over a vague label.

## ROOT CAUSE LABELS
- **Chat Service Synchronization Failure**
- **Teams Client Cache Corruption**
- **Messaging Service Backend Failure**
- **Identity & Authentication Failure**
- **Teams Client Application Defect**
- **Notification Service Failure**
- **Presence Synchronization Failure**
- **Policy & Configuration Failure**
- **Message Routing Failure**
- **Network Connectivity Degradation**
- **Audio / Media Failure**
- **Calendar / Meeting Integration Failure**
- **Permission / Access Failure**
- **Unknown / Unclear**

## ROOT CAUSE GUIDANCE
- Use **Chat Service Synchronization Failure** for missing, delayed, vanished, or not-reflecting chat history when the symptom is clearly tied to Teams messages.
- Use **Teams Client Cache Corruption** when restarting Teams, clearing state, or relaunching fixes the problem.
- Use **Messaging Service Backend Failure** when the evidence points to a service-side chat or message storage/retrieval problem.
- Use **Identity & Authentication Failure** when sign-in, token, or tenant auth is the blocker.
- Use **Teams Client Application Defect** when the app is crashing, hanging, or rendering incorrectly.
- Use **Notification Service Failure** for missing Teams notifications.
- Use **Presence Synchronization Failure** for out-of-office or presence state problems.
- Use **Policy & Configuration Failure** when chat or other Teams functionality was disabled by policy or admin.
- Use **Message Routing Failure** when messages are stuck, misrouted, or not delivered through the chat pipeline.
- Use **Network Connectivity Degradation** when the notes point to VPN, proxy, DNS, latency, or packet loss.
- Use **Audio / Media Failure** when the issue is hearing, microphone, or call audio related.
- Use **Calendar / Meeting Integration Failure** when the issue is meeting joins or calendar sync.
- Use **Permission / Access Failure** when the issue is entitlement or access related.

## CRITICAL OUTPUT RULES

- Output only one root cause label.
- Do not include explanations or extra punctuation.
- Keep the label exactly as shown in the list above.
