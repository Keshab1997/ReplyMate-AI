# Notification Listener

## Objective

Use Android notifications as an optional source of message context for reply suggestions.

## Android Component

Implement a Kotlin service based on `NotificationListenerService`.

Declare the service correctly in the Android manifest and provide the required notification-listener binding permission.

## User Setup

1. Open ReplyMate AI.
2. Explain why notification access is needed.
3. Open the relevant Android Settings page.
4. Let the user grant access.
5. Check the current access state when the app returns.
6. Allow the user to revoke access at any time through Settings.

## Notification Processing

For each notification:

1. Check the package name.
2. Check the user's app allowlist.
3. Inspect available notification extras.
4. Extract only necessary text fields.
5. Inspect available notification actions.
6. Ignore unsupported or irrelevant notifications.
7. Avoid retaining message content unnecessarily.

## Limitations

Notification content may be:
- Hidden by privacy settings
- Truncated
- Grouped
- Replaced by a summary
- Missing
- Restricted by the source app

Do not promise complete conversation history.

## Quick Reply

A notification may expose a RemoteInput action. This does not guarantee that every action is a text reply.

Before using it:
- Confirm the action is still valid.
- Confirm the expected RemoteInput is present.
- Validate the reply input.
- Handle failures safely.

If quick reply is unavailable, provide copy or open-app alternatives.

## Handoff and process death

The listener forwards each event once and keeps nothing on disk. That has a
consequence the UI must not hide:

- while the Flutter engine is alive, events reach the app and the newest one
  fills the composer;
- when the process is dead, events are dropped on purpose. The user opening
  the app later will find no captured message.

The planned fix is `docs/FLOATING_OVERLAY.md`: a bubble while the app is
running, and a fallback notification ("New message from \<app\>") when it is
not. Until that ships, the composer must say plainly that nothing was
captured — never show an empty box as if the message were there.

## Self notifications (planned)

ReplyMate may post its own notification for two reasons only: the bubble
service's foreground notification, and the fallback "Draft a reply" entry
point. Both are separate from notification-listener access and both must obey
the same rule: no message text, no sender name, no message preview.

## Testing

Test on multiple messaging apps and Android versions using real devices and test accounts.
