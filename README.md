# ReplyMate AI

**Your AI-powered reply assistant for everyday conversations.**

ReplyMate AI helps users generate smart, contextual replies to messages from supported messaging apps. It is designed for multilingual communication, with support for Bengali, Hindi, and English.

## Vision

Make replying to messages faster, easier, and more natural without taking control away from the user.

## Core Features

- AI-generated contextual reply suggestions (choose one to three)
- Bengali, Hindi, and English reply output
- Multiple reply tones: Friendly, Professional, Casual, Polite, Funny, and Short and direct
- Android notification-based message assistance
- Optional floating reply assistant (planned)
- Copy, edit, and share generated suggestions
- User reviews and sends every reply
- Privacy-first design
- No automatic message sending

## Supported Workflow

1. A supported messaging app displays a notification.
2. ReplyMate AI receives the notification after the user grants notification access.
3. The user requests AI reply suggestions.
4. ReplyMate AI generates suitable replies.
5. The user reviews, edits, copies, or uses a supported quick-reply action.

**Important:** ReplyMate AI cannot guarantee access to every message or the ability to reply directly in every app. These capabilities depend on the source app and Android notification actions.

## Technology

- Flutter for the application UI
- Kotlin for Android-native integrations
- Firestore-backed API-key pool and OpenAI-compatible provider client in the current MVP
- Server-side provider proxy and rate limiting remain planned hardening

## Development Status

The core app prototype is implemented: Flutter onboarding, home, settings and reply flows; the Kotlin notification listener and platform bridge; and Firebase-backed admin/key-pool integration for AI reply generation.

On 2026-11-06, Keshab reported a real-device smoke check confirming that the admin flow, API request and reply generation work. Device/build details and individual test steps were not recorded. This does **not** verify every notification, quick-reply, share/selection or OEM behavior; see [the Phase 1 device checklist](docs/PHASE1_DEVICE_TESTS.md).

The app is not release-ready. The current AI design lets signed-in clients read a Firestore key pool and call providers directly; the planned server-side proxy and rate limiting are not implemented. See [API security](docs/API_SECURITY.md) and the [roadmap](ROADMAP.md) for remaining work.

## Development

The repository intentionally ships **without `google-services.json`**. Without it the app builds and runs as a full guest shell: every screen works, and AI generation plus the admin section explain that they are not configured instead of failing. Dropping the file from your Firebase project into `android/app/` enables Firebase Auth, the Firestore key pool and the admin gate; see [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md) for the exact console steps, collections and rules.

Real-device verification for the notification prototype lives in [docs/PHASE1_DEVICE_TESTS.md](docs/PHASE1_DEVICE_TESTS.md); the agent workflow and check policy live in [AGENTS.md](AGENTS.md).

## Privacy Principles

- No automatic sending
- No unnecessary message storage
- No message-content logging
- Explicit user permission for notification access
- Clear disclosure before sending message content to an AI service

## Repository Structure

See [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md), [PRODUCT_REQUIREMENTS.md](PRODUCT_REQUIREMENTS.md), and the `docs/` directory.

## License

License to be decided before public distribution.
