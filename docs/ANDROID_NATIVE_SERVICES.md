# Android Native Services

## Purpose

Android-native code provides functionality that Flutter cannot reliably implement by itself.

## Technology

- Kotlin
- Android SDK
- NotificationListenerService
- Notification and RemoteInput APIs
- MethodChannel or Pigeon for Flutter communication

## Main Components

### Notification Listener

Receives notifications that Android makes available after the user grants notification access.

### Notification Parser

Extracts only permitted and available fields. It must handle:
- Missing title
- Missing text
- Truncated text
- Grouped notifications
- Redacted notifications
- Duplicate updates

### Reply Action Handler

Inspects notification actions and determines whether a compatible RemoteInput action exists.

### Platform Bridge

Sends safe, structured events to Flutter and receives validated user actions.

### Floating Bubble (`docs/FLOATING_OVERLAY.md`)

A foreground service that draws one small overlay view with `WindowManager`.

- It is a *drawing* surface, not a reader: it never inspects the app beneath.
- It is started from the app (a foreground activity), never assumed to run.
- When it cannot run — no overlay permission, disabled by the user, or a
  cold-start background restriction — the listener posts a fallback
  notification instead. Silence is a bug, not a fallback.
- The pending message it carries lives in memory only.

## Permission Rules

Notification-listener access is granted through Android Settings.

POST_NOTIFICATIONS is a separate permission used for ReplyMate AI's own notifications on supported Android versions.

SYSTEM_ALERT_WINDOW is a separate permission for the optional floating bubble.
It grants drawing on top of other apps, not access to their content, and it is
never implied by, or a precondition for, notification access.

Never treat one permission as authorization for another feature.

## Reliability

Android may restrict background execution. Implement lifecycle-safe handling and avoid assuming that a service will remain active indefinitely.

A foreground service may not be started from the background on Android 12+.
Catch `ForegroundServiceStartNotAllowedException` and take the fallback path.

## Screen reading

An `AccessibilityService` **is** used, in exactly one place and for exactly one
job: `ReplyMateScreenReaderService` reads the newest visible message so the app
can draft a reply to the conversation the user is already looking at - the one
place a notification is never posted. The rules it lives by, and the reason each
one exists, are in docs/SCREEN_READING.md. The short version:

- off by default, and allowed only for packages on the user's allowlist;
- it reads and reports - it performs **no action** on the user's behalf, ever;
- nothing it reads is written to disk or to a log.

No other component reads the screen. That boundary has not moved: the bubble can
draw over other apps, and it still does not inspect them. If a requirement seems
to need screen reading anywhere else, the requirement is still wrong.
