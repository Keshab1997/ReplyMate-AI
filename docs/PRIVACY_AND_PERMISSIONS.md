# Privacy and Permissions

## Privacy Commitment

ReplyMate AI must give users control over their messages and data.

## Notification Access

Notification access may expose notifications from selected or other applications depending on Android behaviour and user configuration.

Explain this clearly before requesting access.

Process only notifications from applications selected by the user.

## AI Processing

When a user taps Generate, the message text on screen is sent to the
configured AI provider through the Firestore key pool
(`docs/AI_INTEGRATION.md`) — the current MVP calls the provider from the
client, and a server-side proxy is planned but not implemented. This happens
only on that explicit tap — never when a notification arrives.

Disclose this in onboarding and in Settings before the feature is used.

Do not claim that message content never leaves the device: with cloud AI
enabled, the text of the message being answered does leave it.

## The floating bubble, in privacy terms

- The bubble itself shows an icon only — no sender, no text.
- Tapping it opens a panel that shows the message because the user asked to
  see it, on their own screen.
- The pending message lives in process memory only. It is cleared when the
  panel closes or the process dies. It is never written to disk, a database,
  or a log.
- The overlay never reads the screen underneath, never captures the screen,
  and never inspects other apps' UI.
- The fallback notification says only "New message from \<app\>" and is
  suppressed entirely when the user turns the bubble off.

## Data Minimization

- Do not store full conversations.
- Do not log raw notification content.
- Do not collect unnecessary personal information.
- Keep only the information required to complete the requested action.
- Clear the in-memory notification buffer and native pending reply action when the composer session closes; never persist message content as conversation history.

## Permissions

### Notification Listener Access

Required for notification-based message assistance.

### SYSTEM_ALERT_WINDOW

Used by the floating reply bubble (`docs/FLOATING_OVERLAY.md`). Optional: the
app is fully usable without it. It is granted through Android Settings, and
declining it must never disable notification access or any other feature.

Overlay permission means "draw on top of other apps". It does **not** grant
access to what those apps display, and ReplyMate never reads the screen.

### FOREGROUND_SERVICE / FOREGROUND_SERVICE_SPECIAL_USE

Keeps the bubble alive while the user is in another app. The service is
declared with a `specialUse` subtype and must be declared in Play Console. If
the user disables the bubble, the service stops.

### POST_NOTIFICATIONS

Used for the bubble service's own notification and for the fallback
notification ("New message from \<app\> · Draft a reply"). The fallback never
contains message text.

## User Controls

Provide clear controls to:
- Disable notification access through Android Settings
- Change selected applications
- Turn the reply bubble (and its fallback notification) off, default off
- Clear local preferences
- Understand AI data processing

## Security

Provider credentials never enter the APK as literals: the pool is fetched from
Firestore at runtime and is admin-controlled (the trade-off of that design is
recorded in `docs/API_SECURITY.md`). All provider traffic is HTTPS.

## Policy Compliance

Before publishing, review current Google Play policies, including user-data, privacy, prominent disclosure, consent, and permissions requirements.

Do not introduce hidden monitoring or automatic message sending.
