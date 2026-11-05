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

## Permission Rules

Notification-listener access is granted through Android Settings.

POST_NOTIFICATIONS is a separate permission used for ReplyMate AI's own notifications on supported Android versions.

SYSTEM_ALERT_WINDOW is a separate permission for an optional overlay.

Never treat one permission as authorization for another feature.

## Reliability

Android may restrict background execution. Implement lifecycle-safe handling and avoid assuming that a service will remain active indefinitely.

## MVP Restriction

Do not use AccessibilityService or screen scraping in the MVP.
