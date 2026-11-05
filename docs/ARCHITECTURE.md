# System Architecture

## Overview

ReplyMate AI uses a Flutter application with native Android integrations and a secure backend for AI processing.

## Main Components

### 1. Flutter Application

Responsible for:
- User interface
- Onboarding
- Permission guidance
- App selection
- Language and tone preferences
- Reply editing and display
- Settings and privacy controls

### 2. Android Native Layer

Implemented in Kotlin.

Responsible for:
- NotificationListenerService
- Notification content extraction where permitted
- Notification action inspection
- RemoteInput quick-reply integration where supported
- Android lifecycle and permission handling

### 3. Backend

Responsible for:
- Authenticated AI requests
- AI provider integration
- Input validation
- Rate limiting
- Usage controls
- Safe error responses

### 4. AI Provider

Generates suggested replies from the context explicitly provided by the user and the application.

## Data Flow

1. A messaging notification arrives.
2. Android provides notification data to the native service.
3. The native layer checks whether the app is allowed and selected.
4. Available message context is passed to the Flutter interface.
5. The user requests suggestions.
6. Flutter sends the request to the secure backend.
7. The backend calls the configured AI provider.
8. Suggestions return to the application.
9. The user reviews and chooses an action.

## Important Boundaries

- Notification access does not mean access to an entire conversation.
- The app cannot read arbitrary underlying app screens.
- Quick reply is conditional on source-app support.
- The AI backend must not send messages.
- Sending remains a user-controlled action.

## Architectural Principle

Keep Android-specific code isolated from Flutter business logic. Use documented interfaces between layers.
