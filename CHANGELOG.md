# Changelog

All notable project changes are recorded here.

## [Unreleased]

### Premium visual polish

- Refined the shared light/dark theme: clearer typography, quieter card
  borders, larger chips, consistent list/input/dialog styling and a themed
  navigation bar.
- Rebuilt onboarding around the mascot, one grouped promise surface and a
  bottom action that remains reachable on short screens.
- Added shared responsive width, icon-badge and primary-action treatments;
  Home, Reply, Suggestions, Apps, Settings, permissions and Admin now use the
  same visual hierarchy without changing their behaviour.

### Floating reply bubble — implemented (device verification pending)
- Batch 0: the composer explains an empty capture session ("No message was
  captured…") instead of showing a blank box, and Generate still runs so
  validation explains what is missing.
- Batch 1: `OverlayBubbleService` (foreground, `specialUse`) draws a 56dp
  `WindowManager` bubble from code, with drag-vs-tap touch slop, a silent
  `IMPORTANCE_MIN` channel, and `OverlayBubbleController` holding exactly one
  pending context **in memory only**.
- Batch 2: `OverlayPanelScreen` at route `/overlay` behind a translucent,
  non-exported `OverlayPanelActivity`; `OverlayContext` model reads the
  `consumeOverlayContext` wire format and reuses `CapturedNotification`; panel
  reuses the language/tone/length chips and `SuggestionCard`.
- Batch 3: the listener decides bubble vs fallback per notification (§5.3
  filter), posts a text-free "New message from \<app\>" fallback that opens the
  composer prefilled, and hides the bubble when its notification is removed.
  New channel methods `isOverlayEnabled`, `openOverlaySettings`,
  `requestNotificationPermission`, `setBubbleEnabled`,
  `consumeOverlayContext`; overlay permission card on the permission screen; a
  "Reply bubble" switch in Settings (default off, unusable without overlay
  access).
- Batch 4: 10-minute auto-hide, hide while the screen is off or locked (and
  re-show on unlock while a message is pending), a count badge when more
  messages arrive, and the Play/privacy checklist lines.
- Not done: rows 17–24 of `docs/PHASE1_DEVICE_TESTS.md` are still `_pending_` —
  no Android device was available. The bubble is code-complete, not
  device-proven.

### Screen reading — implemented (device verification pending)

The gap the notification listener can never close: a messaging app posts no
notification for the chat you are already looking at, so there was nothing to
read exactly when a reply was most wanted.

- `ReplyMateScreenReaderService` (an `AccessibilityService`) reads the visible
  conversation of the apps on the user's allowlist and hands the newest
  incoming message to the same pipeline a notification uses - the bubble or the
  fallback notification (`OverlayRouter`), and the in-app capture list.
- `ScreenTextReader` holds the heuristics and is a pure function of a node tree,
  so it is proven on a plain JVM: 8 tests, including one that asserts what the
  user is typing is never captured.
- Off by default, behind a switch that shows a disclosure before it moves, and
  inert until Android grants accessibility access. Nothing is written to disk
  or to a log, and `hasReplyAction` is always false for a screen reading - the
  service reads and reports, it never types and never sends.
- Docs: `docs/SCREEN_READING.md`, including the honest limitation that Android
  16+ Advanced Protection refuses accessibility access to an app it does not
  classify as an accessibility tool, which ReplyMate is not and does not claim
  to be.

Not done: rows 25-34 of `docs/PHASE1_DEVICE_TESTS.md` are still `_pending_` -
no Android device was available. The reader is code-complete, not field-proven.

### The panel drafts on open

Tapping the bubble now produces a draft: the panel generates as soon as it
opens, so the reply is on screen without a second tap. The "Generate" button
becomes "Generate again" and stays there for edits and second thoughts.

What deliberately did **not** change: nothing is sent before the user acts.
A message arriving, or being read off the screen, still sends nothing - the
panel only drafts because the user opened it. Auto-drafting at capture time
was considered and rejected: it would send every message to the AI before the
user had looked at anything, and it would need a background Flutter engine
or a second AI client in Kotlin, which `docs/OVERLAY_TASKS.md` forbids.
`docs/PRIVACY_AND_PERMISSIONS.md` now states the rule the way the code
actually behaves.

### Implemented in the repository
- Flutter onboarding, home, permissions, app selection, settings and reply-suggestion flows, including a selectable 1–3 suggestion count, copy/edit/share actions and composer-session cleanup of transient message context.
- Kotlin notification listener, parser and Flutter platform-channel integration, including conditional RemoteInput quick reply and user-initiated share/text-selection entry points.
- Firebase admin gate and Firestore-backed API-key pool with direct provider API integration for reply generation.
- Bengali, Hindi and English output-language choices, tone/length controls, request validation and user-visible failure handling.

### Owner-reported verification — 2026-11-06
- Keshab reports that admin, API access and reply generation work on a real device. Device model, OS/app build and detailed test steps were not recorded; this is a smoke-test report, not full Phase 1 sign-off.

### Added
- `docs/FLOATING_OVERLAY.md` — full implementation spec for the floating reply
  bubble (bubble, panel, fallback notification, permissions, failure table,
  privacy and Play rules)
- `docs/OVERLAY_TASKS.md` — the same work broken into five batches for an
  implementing agent, with acceptance criteria and the device evidence rows
- Device test rows 17–24 for the bubble

### Changed
- `ROADMAP.md` gained the bubble phase and the explicit "specified, not built"
  state, on top of the 2026-11-06 implementation reconciliation
- `AI_INTEGRATION.md` now describes the shipped architecture A end to end
  (client-side key pool, direct provider call, typed failures); the old
  request-flow sections described a backend that was never built
- `PRIVACY_AND_PERMISSIONS.md`, `ANDROID_NATIVE_SERVICES.md`,
  `PLATFORM_CHANNELS.md`, `NOTIFICATION_LISTENER.md`, `USER_FLOWS.md`,
  `SCREEN_SPECIFICATIONS.md`, `BUILD_AND_RELEASE.md` updated for the bubble plan
- `README.md` links the bubble spec instead of calling it "planned"

### Removed
- Redundant planning notes, their surviving content folded into the docs above
  and the code: `FLUTTER_ARCHITECTURE.md`, `DATABASE_DESIGN.md`,
  `DESIGN_SYSTEM.md`, `UI_UX_GUIDELINES.md`, `TESTING_STRATEGY.md`,
  `TROUBLESHOOTING.md`

### Remaining before release
- Complete and record the real-device checklist in `docs/PHASE1_DEVICE_TESTS.md`.
- Decide/implement server-side provider-key handling and rate limiting; the current client-readable key-pool trade-off is documented in `docs/API_SECURITY.md`.
- Complete privacy/security, performance and Play policy review, then closed testing.

## [0.1.0] - Not released

### Added
- Initial project documentation
- Product requirements
- Architecture and implementation plan

### Notes
This project is in its planning and early development stage. No production-ready features are claimed yet.
