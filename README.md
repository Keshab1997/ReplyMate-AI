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
- Optional floating reply bubble: a bubble over the app
  you are in, a panel to draft the reply, and a fallback notification when the
  bubble cannot be drawn
- Copy, edit, and share generated suggestions
- Optional screen reading: draft a reply to the chat you already have open,
  where the app posts no notification
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

The core app prototype is implemented: Flutter onboarding, home, settings and reply flows; the Kotlin notification listener and platform bridge; and Firebase-backed admin/key-pool integration for AI reply generation. 76 Dart unit/widget tests cover the Dart side.

On 2026-11-06, Keshab reported a real-device smoke check confirming that the admin flow, API request and reply generation work. Device/build details and individual test steps were not recorded. This does **not** verify every notification, quick-reply, share/selection or OEM behavior; the Phase 1 device checklist has not been completed or recorded.

A floating reply bubble — the answer to "why does nothing appear when a WhatsApp message arrives?" — is implemented: tap the bubble, get a panel with the message and the same generation flow. It is **optional and off by default**, needs the "Display over other apps" permission, keeps the message in memory only, and shows an icon in the bubble — an opt-in *Show a preview* switch can add the sender and the first line beside it, off by default and never on the lock screen. When it cannot run (no permission, switched off, or the app process was dead in the background) the honest fallback is a "New message from \<app\>" notification that opens the composer prefilled. **The bubble may not survive aggressive OEM battery managers**; the fallback notification is the reliable path. Device evidence for rows 17–24 of the Phase 1 checklist is still pending, so treat the bubble as code-complete, not field-proven.

Reading the open chat uses an Android `AccessibilityService`, and it asks for
that access explicitly: the switch is off by default, shows a disclosure before
it moves, and stays inert until Android grants the access itself. It reads the
apps you selected and reports what it saw - it never types into another app,
never sends anything, and keeps nothing on disk. It also cannot run on a device
with Android's Advanced Protection Mode switched on, because the system will not
grant accessibility access to an app it does not classify as an accessibility
tool; ReplyMate is not one and does not claim to be. Rows 25-34 of the Phase 1
checklist are still pending, so this is code-complete, not field-proven.

The app is not release-ready. The current AI design lets signed-in clients read a Firestore key pool and call providers directly; the planned server-side proxy and rate limiting are not implemented. See API security and the [roadmap](ROADMAP.md) for remaining work.

## Development

The repository intentionally ships **without `google-services.json`**. Without it the app builds and runs as a full guest shell: every screen works, and AI generation plus the admin section explain that they are not configured instead of failing. Dropping the file from your Firebase project into `android/app/` enables Firebase Auth, the Firestore key pool and the admin gate; see for the exact console steps, collections and rules.

Real-device verification for the notification prototype is still outstanding (the Phase 1 device checklist has no record yet); the agent workflow and check policy live in [AGENTS.md](AGENTS.md).

## Privacy Principles

- No automatic sending
- No unnecessary message storage
- No message-content logging
- Explicit user permission for notification access
- Clear disclosure before sending message content to an AI service

## Repository Structure

See [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) and [PRODUCT_REQUIREMENTS.md](PRODUCT_REQUIREMENTS.md).

## License

License to be decided before public distribution.
