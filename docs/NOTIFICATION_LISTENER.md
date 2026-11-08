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

The fix is the bubble (`docs/FLOATING_OVERLAY.md`): a bubble while the app is
running, and a fallback notification ("New message from \<app\>") when it is
not. When neither ran — and whenever the capture buffer is empty — the composer
says plainly that nothing was captured, never showing an empty box as if the
message were there (Batch 0 in `docs/OVERLAY_TASKS.md`).

## Bubble routing (implemented)

`onNotificationPosted` first emits the `notification_captured` event exactly as
before, so the in-app list keeps working. It then decides, in this order:

1. Is the user's bubble switch on? If not, nothing else happens — no bubble and
   no fallback notification. Off is off; the app does not nag.
2. Does the notification pass the `docs/FLOATING_OVERLAY.md` §5.3 filter (has
   text, no `FLAG_GROUP_SUMMARY`, no `FLAG_ONGOING_EVENT`, not a `MediaStyle`
   transport, screen on and unlocked)? If not, it is captured in the app only.
3. Is overlay access granted? If not → fallback notification.
4. Hold the context with `source=bubble` and start/refresh the bubble service.
   If Android refuses the start (background FGS restriction, Android 12+), hold
   the context with `source=fallback` and post the fallback notification.

The bubble can also be tucked against a screen edge by dragging it there; it
then waits as a slim tab until tapped (or until the next message expands it).

The bubble also disappears when its notification is removed
(`onNotificationRemoved` matches the pending key) - after a 6-second grace
window, because some apps post and immediately retract a notification - after
ten minutes, and while the screen is off or locked.

### Why nothing appears while you are in the chat

While the user is looking at a conversation, the messaging app usually posts no
notification for it. No notification means no event, no context and no bubble;
the alternative (reading the screen) needs an `AccessibilityService`, which this
project forbids. Text selection (PROCESS_TEXT), the share sheet and pasting into
the composer are the supported routes in that situation.

### Known limitation: the fallback tap while the app is already open

The fallback notification opens the composer **when it starts the app** (cold
start, or a warm start where `MainActivity` had no pending reply session). If
ReplyMate is already on screen, tapping it brings the app forward and leaves the
user on Home; the message is still in the capture buffer, so
*Generate a reply* opens the composer with it. Closing that gap needs a new
native → Dart event, which this channel does not have yet - recorded here rather
than hidden.

## Self notifications (implemented)

ReplyMate may post its own notification for two reasons only: the bubble
service's foreground notification, and the fallback "Draft a reply" entry
point. Both are separate from notification-listener access and both must obey
the same rule: no message text, no sender name, no message preview.

## Testing

Test on multiple messaging apps and Android versions using real devices and test accounts.
