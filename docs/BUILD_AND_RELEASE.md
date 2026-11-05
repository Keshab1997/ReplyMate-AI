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

- [ ] Application tested on physical devices
- [ ] Permissions reviewed
- [ ] Privacy policy published
- [ ] Store listing prepared
- [ ] App icon and screenshots prepared
- [ ] Release signing configured
- [ ] Backend deployed over HTTPS
- [ ] API rate limits enabled
- [ ] Crash and error handling reviewed
- [ ] Play Store policy compliance reviewed

## Low-Spec Development

Keep local builds simple. Cloud CI can be used for Android builds if the local Mac cannot comfortably run the full toolchain.
