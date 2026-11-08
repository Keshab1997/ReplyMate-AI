# Build and Release

## Development Requirements

- Flutter SDK
- Dart SDK
- Android SDK
- JDK version compatible with the selected Android Gradle Plugin
- Git
- Android physical device for testing

## Local Development

1. Clone the repository.
2. Install the required Flutter SDK.
3. Run `flutter doctor`.
4. Open the project in a compatible IDE.
5. Resolve missing Android toolchain requirements.
6. Run `flutter pub get`.
7. Connect an Android test device.
8. Run the application.

## Useful Commands

```bash
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter run
```

## Android Release Build

For an APK:

```bash
flutter build apk --release
```

For a Play Store App Bundle:

```bash
flutter build appbundle --release
```

## Signing

Configure release signing securely.

Never commit:
- Keystore files
- Keystore passwords
- Signing credentials
- Production API secrets

## Release Checklist

- [ ] Application tested on physical devices (all rows in
      `docs/PHASE1_DEVICE_TESTS.md`)
- [ ] Permissions reviewed — notification listener, POST_NOTIFICATIONS,
      overlay (if the bubble ships)
- [ ] Privacy policy published at a public URL
- [ ] Prominent in-app disclosure before AI processing and before the bubble
- [ ] Play Console: notification-listener access declaration
- [ ] Play Console: foreground service `specialUse` declaration (bubble)
- [ ] Play Console: overlay usage declared in the listing/description.
      Notification-listener access, overlay access and the `specialUse`
      foreground service are three separate declarations and are reviewed
      together; each must describe what the app actually does
- [ ] Device evidence attached for rows 17–24 of the Phase 1 checklist,
      including `adb shell run-as com.keshabstudios.replymate ls -R files/
      shared_prefs/` and `adb logcat | grep -i replymate` output showing no
      message text on disk or in the log
- [ ] Store listing prepared
- [ ] App icon and screenshots prepared (the launcher icon is still the
      Flutter default)
- [ ] Release signing configured (CI secrets, never in git)
- [ ] Provider keys treated as consumables; Firestore rules deployed
- [ ] Crash and error handling reviewed
- [ ] Play Store policy compliance reviewed

There is no backend to deploy (architecture A, `docs/API_SECURITY.md`), so
"backend over HTTPS" is not a checklist item until that hardening step lands.

## Low-Spec Development

Keep local builds simple. Cloud CI can be used for Android builds if the local Mac cannot comfortably run the full toolchain.

## CI on push

`.github/workflows/ci.yml` now runs on every push to `main` (and on demand).
Kotlin is only ever compiled in CI, so a manual-only pipeline meant a broken
service file could sit undetected until the next APK build. To go back to
manual-only, delete the `push:` block.

`android/app/src/test/kotlin/...` holds JVM unit tests for
`OverlayBubbleController` (pending-message order, no double-consume, the
five-chat cap). They are not wired into the reusable Flutter workflow yet - run
them with `./gradlew :app:testDebugUnitTest` on a machine with the Android SDK,
or add a gradle job to `ci.yml`.
