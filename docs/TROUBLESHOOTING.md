# Troubleshooting

## Flutter Dependencies Fail

Try:

```bash
flutter clean
flutter pub get
```

Check the installed Flutter version and dependency compatibility.

## Android Build Fails

Check:
- JDK version
- Android SDK installation
- Android Gradle Plugin compatibility
- Gradle wrapper version
- Flutter Android configuration

Run:

```bash
flutter doctor -v
```

## Notifications Are Not Received

Check:
- Notification access is enabled.
- The source app is posting notifications.
- The notification is not hidden or suppressed.
- The Android service is correctly declared.
- Device battery restrictions are not interfering.

## Notification Text Is Missing

Possible causes:
- Source app hides notification content.
- User privacy settings redact content.
- Notification is grouped or summarized.
- The source app does not expose message text.

Do not assume this is always an application bug.

## Quick Reply Does Not Work

Check:
- Whether the notification has a reply action.
- Whether the action contains a valid RemoteInput.
- Whether the action is still valid.
- Whether the source app supports notification replies.

Provide copy/open-app fallback actions.

## AI Request Fails

Check:
- Internet connection
- Backend availability
- API authentication
- Provider quota
- Request validation
- Rate limits
- Timeout settings

Never expose provider credentials in error messages.

## Overlay Does Not Appear

Check:
- Whether overlay functionality has been implemented.
- Whether the user granted overlay permission.
- Android version restrictions.
- Foreground service requirements.
- Device manufacturer restrictions.

Overlay permission does not grant access to underlying screen content.

## Reporting a Bug

Include:
- Android version
- Device model
- App version
- Steps to reproduce
- Expected behaviour
- Actual behaviour

Never include private message content, passwords, or API keys in bug reports.
