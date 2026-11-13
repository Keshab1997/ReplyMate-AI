# ReplyMate AI Roadmap

_Last reconciled: 2026-11-07_

**Status legend:** `[x]` means implementation exists in the repository; it does
not mean every device test or release gate has passed. `[ ]` means not yet
implemented or not yet verified.

## Current snapshot

The core Flutter app, Android notification bridge, admin/key-pool flow and AI
reply-generation path are implemented. Keshab reports a real-device smoke check
confirmed admin, API access and reply generation. The device/build details and
exact test steps were not recorded; this is not a full Phase 1 sign-off.

The current AI path is the documented client-side Firestore key-pool design,
not a server-side proxy. The remaining device checks, architecture/security
hardening and release tasks are listed below.

The floating reply bubble — the answer to "nothing appears when a WhatsApp
message arrives" — is **implemented in code**.
It is not device-verified: rows 17–24 of the device checklist are still
pending.

## Phase 0 — Project Foundation

- [x] Create the repository and Flutter/Android project structure.
- [x] Document product requirements and the intended system architecture.
- [x] Configure the Flutter application and Android Kotlin integration.
- [x] Configure Firebase project wiring and Firestore rules.
- [ ] Reconcile the target backend architecture docs with the current key-pool implementation.

## Phase 1 — Android Feasibility

- [x] Implement the Kotlin `NotificationListenerService` and notification parser.
- [x] Implement notification-access setup and the selected-app allowlist.
- [x] Handle missing, grouped, redacted and truncated notification content in code.
- [x] Detect reply actions and bind quick reply to the notification it belongs to.
- [ ] Complete and record the real-device checklist, including quick-reply delivery, share/text-selection, permission revocation and OEM lifecycle behavior.

## Phase 2 — Flutter MVP

- [x] Implement onboarding, home, permission setup and supported-app selection.
- [x] Implement AI reply-language, tone, length and suggestion-count preferences.
- [x] Implement the reply composer, suggestions, edit/copy/share actions and conditional quick reply.
- [x] Add independent Bengali/Hindi/English app-interface localization.
      All three languages exist (`EnglishStrings`, `BengaliStrings`,
      `HindiStrings`) and the compiler refuses a language with a missing string.
      The setup path was the last English island and is now swept: onboarding,
      permission setup, app selection and the screen-reading status card read
      from `AppStrings`, and `test/setup_path_localization_test.dart` walks those
      screens in Bengali and Hindi and fails if an English original is still on
      screen. The admin gate stays English on purpose — see below.

      Translation quality is the open item, not coverage: the Bengali is the
      owner's own, the Hindi needs a speaker's review before release (`hi` here
      means the *interface* language, exactly like `bn`). The admin gate is
      deliberately not translated: it is an allowlisted operator screen, its
      audience is one person, and machine-translating "add its email or uid to
      `admin_config/access`" would make a precise instruction ambiguous.

## Phase 3 — AI Integration

- [x] Implement the Firestore key-pool/provider client path, request validation, reply parsing and user-visible failures.
- [x] Confirm by owner report that API access and reply generation work on a real device.
- [ ] Implement or explicitly defer the server-side proxy, authentication and
      rate limiting. The current client-readable key-pool trade-off is
      documented in the README ("Read this before shipping the rules") and in
      `admin_api_key_manager`.

## Phase 4 — Android Integration

- [x] Implement Flutter–Kotlin methods/events and notification, share-sheet and text-selection entry points.
- [x] Implement RemoteInput validation, stale-notification protection, copy fallback, Android share chooser and composer-close cleanup of transient context.
- [ ] Verify notification lifecycle and quick-reply behavior across supported apps/devices; see the Phase 1 checklist.

## Phase 5 — Testing and Release Readiness

- [x] Add core Dart unit and widget tests.
- [ ] Finish the manual real-device checklist; only the admin/API/reply-generation smoke test is currently reported here.
- [ ] Complete privacy/security and performance review.
- [ ] Publish the privacy policy, complete Play policy declarations and prepare closed testing.
- [ ] Complete release sign-off. No production release is claimed.

## Phase 6 — Floating reply bubble (implemented, device verification pending)

Implemented across five batches (empty state, native bubble + foreground
service, Flutter panel route and context model, listener wiring + fallback
notification + settings toggle, auto-hide/screen-off/badge/docs).

- [x] Batch 0 — honest empty state when nothing was captured.
- [x] Batch 1 — native overlay bubble + foreground service.
- [x] Batch 2 — Flutter panel route and context model.
- [x] Batch 3 — listener wiring, fallback notification, settings toggle.
- [x] Batch 4 — auto-hide, screen-off handling, badge, docs.
- [ ] Device rows 17–24 filled on a real phone. **The feature is not done until
      this is checked.**

Non-negotiable: no message text on disk, no automatic send, no claim that the
bubble survives every OEM's battery manager, and **no screen reading without
the user's explicit switch** -. Exactly one component
reads the screen (`ReplyMateScreenReaderService`), and it only ever reads: it
never types, never clicks and never sends.

## Phase 7 — Zero-bill smart features

Constraint: no Firebase billing, so no Cloud Functions and no server-side proxy.
Plan and ranking: [`docs/ZERO_BILL_FEATURES.md`](docs/ZERO_BILL_FEATURES.md).

- [x] Reply cache by message hash, labelled "from cache" with a bypass
- [x] Per-device daily AI budget, with an honest stopped state
- [x] Cheaper requests: one suggestion by default, capped `max_tokens`, trimmed prompt
- [x] On-device offline suggestions (works with no key, no Firebase, no network)
- [ ] Local language detection + intent-based tone chips
- [x] BYOK — the user's own key in Hive, never in Firestore (the real fix for
      the key-pool risk while there is no proxy)

## Phase 8 — Future Features

- [ ] Add more reply styles/languages and supported apps after validation.
- [ ] Optional server-side proxy (see Phase 3).
- [ ] iOS (different notification/overlay model; currently out of scope).
