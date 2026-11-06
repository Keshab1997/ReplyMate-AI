# Privacy and Permissions

## Privacy Commitment

ReplyMate AI must give users control over their messages and data.

## Notification Access

Notification access may expose notifications from selected or other applications depending on Android behaviour and user configuration.

Explain this clearly before requesting access.

Process only notifications from applications selected by the user.

## AI Processing

When a user requests AI suggestions, relevant message context is sent to the configured AI provider. The current MVP calls the provider from the client using its Firestore key pool; a server-side proxy is planned but is not implemented yet (see `API_SECURITY.md`).

Disclose this before the user uses the feature.

Do not claim that message content never leaves the device when cloud AI processing is enabled.

## Data Minimization

- Do not store full conversations.
- Do not log raw notification content.
- Do not collect unnecessary personal information.
- Keep only the information required to complete the requested action.
- Clear the in-memory notification buffer and native pending reply action when the composer session closes; never persist message content as conversation history.

## Permissions

### Notification Listener Access

Required for notification-based message assistance.

### POST_NOTIFICATIONS

Used for ReplyMate AI's own notifications where Android requires it.

### SYSTEM_ALERT_WINDOW

Optional future overlay functionality. It is not required for the notification-based MVP.

### Internet

Required for cloud AI requests.

## User Controls

Provide clear controls to:
- Disable notification access through Android Settings
- Change selected applications
- Clear local preferences
- Understand AI data processing

## Security

Use HTTPS and secure backend credential management.

## Policy Compliance

Before publishing, review current Google Play policies, including user-data, privacy, prominent disclosure, consent, and permissions requirements.

Do not introduce hidden monitoring or automatic message sending.
