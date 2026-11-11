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

### 3. Backend (target — see status below)

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

What actually runs, today:

1. A message arrives — as a notification, as shared text, as a `PROCESS_TEXT`
   selection, or as a bubble on a chat the user opened.
2. Android hands it to the native layer: the notification listener, the share
   intent, or the screen reader (`ReplyMateScreenReaderService`, off by default,
   docs/SCREEN_READING.md).
3. The native layer checks the user's app allowlist and drops anything else.
4. Available context — the message, the history the source could give, and (for
   a screen read) which line came from which side — reaches Flutter as
   `CapturedNotification`, or opens the reply bubble.
5. If the user switched on conversation memory, the message is filed against its
   contact and the window is pulled back for the prompt
   (docs/CONVERSATION_MEMORY.md). Off means nothing is written and the prompt
   is exactly what it would have been.
6. The user asks for suggestions. Flutter takes a key from the Firestore pool and
   calls the provider **directly** — architecture A in `API_SECURITY.md`.
7. Suggestions return; the app parses them and refuses to present an empty or
   unparseable answer as a success.
8. The user reviews, edits, copies, shares or quick-replies. **Nothing is ever
   sent on its own.**

The target flow — Flutter to an authenticated backend, which owns the provider
key, validation and rate limiting — is §3 above and stays unimplemented.

## Important Boundaries

- Notification access does not mean access to an entire conversation. A
  notification carries the line that triggered it and, when the sender's app
  includes it, a few lines before that — nothing more.
- **Screen reading is a separate, opt-in feature** and not a general screen
  scraper: it is off until the user grants accessibility *and* turns the switch
  on, it obeys the same app allowlist, it reads only the visible message list of
  an allowed chat, and it never types, clicks or sends
  (docs/SCREEN_READING.md).
- Conversation memory is bound by narrower rules than either source: off by
  default, capped, on the device only, deletable, and it never infers a profile
  of the user (docs/CONVERSATION_MEMORY.md).
- Quick reply is conditional on source-app support: it needs a live
  `RemoteInput` action on the notification being answered. The native channel
  (`sendQuickReply`) is implemented and its guard is tested; no Flutter surface
  currently offers it — the bubble and composer offer copy and share instead,
  and saying "quick reply works end to end" would overstate what ships today.
- The AI backend must not send messages.
- Sending remains a user-controlled action.

## Current implementation status (2026-11-11)

The backend flow above is the target/hardening architecture, not the current
runtime path. The MVP currently uses architecture A from
[`API_SECURITY.md`](API_SECURITY.md): Flutter reads the Firestore key pool and
calls the configured provider directly. A server-side proxy, authentication
and rate limiting remain open work (ROADMAP Phase 3). Do not treat the target
flow above as an implemented backend.

Since this note was first written, the runtime path gained the floating bubble,
screen reading and conversation memory — all reflected in "Data Flow" above and
in their own specs. The one thing that has *not* changed is the AI transport:
still the client-side key pool, still the trade-off recorded in
`API_SECURITY.md`.

## Architectural Principle

Keep Android-specific code isolated from Flutter business logic. Use documented interfaces between layers.
