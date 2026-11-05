# Flutter Architecture

## Goal

Keep the Flutter codebase modular, testable, and maintainable.

## Recommended Stack

- Flutter
- Dart
- Riverpod for state management
- GoRouter for navigation, if routing complexity requires it
- Dio or the standard HTTP client for API communication
- Flutter Secure Storage only for appropriate local secrets or tokens

Do not add packages without a clear requirement.

## Suggested Folder Structure

```text
lib/
├── main.dart
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme/
├── core/
│   ├── constants/
│   ├── errors/
│   ├── network/
│   ├── platform/
│   └── utils/
├── features/
│   ├── onboarding/
│   ├── permissions/
│   ├── notifications/
│   ├── app_selection/
│   ├── reply/
│   ├── settings/
│   └── privacy/
└── shared/
    ├── widgets/
    └── models/
```

## Feature Layer Pattern

Each feature should use the simplest structure that fits its complexity:

- `data/` — API clients, data sources, and repository implementations
- `domain/` — Business rules and entities
- `presentation/` — Screens, widgets, and state management

Avoid creating empty abstractions just to follow a pattern.

## State Management

Use Riverpod for:
- Permission state
- User preferences
- Selected applications
- Reply-generation state
- API loading and error state

## Platform Communication

Use a clearly defined platform channel or Pigeon interface for Flutter-Kotlin communication.

Validate all incoming native data before using it.

## Testing

- Unit tests for business logic
- Widget tests for screens
- Integration tests for major user flows
- Physical-device tests for Android native features
