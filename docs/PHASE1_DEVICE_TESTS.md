# Phase 1 Device Test Checklist

The ROADMAP release gate forbids claiming quick-reply support until real
devices establish what works. This checklist is how that evidence gets
collected. The agent sandbox cannot run it because no Android device or
emulator is attached. The agent must not run a full local build merely as a
check (AGENTS.md); a developer can use the local `flutter run` path below on a
machine with the Android toolchain.

## Owner-reported smoke test (2026-11-06)

Keshab reports that admin, API access and reply generation work on a real
device. Device model, Android/app version and exact test steps were not
recorded. This report does not establish notification capture, RemoteInput
quick-reply delivery, share/text-selection behavior or the rest of this
checklist; keep those cases pending until their results are recorded.

## Getting a build

- **Preferred:** Actions → *Build Android APK or AAB (Manual)* → Run workflow → download the APK
  artifact (signed with the upload keystore from repository secrets).
- **Local:** `flutter run` on a machine with the Android toolchain, with the
  device in developer mode.

Record results by editing the Result column and committing, or by telling the
agent and letting it record them.

## Setup (once per device)

1. Install the APK.
2. Open the app, finish onboarding.
3. Home → Manage → *Open Android Settings* → grant **notification access**
   to ReplyMate AI. Return to the app: the status card must flip to
   *Notification access enabled* without a restart.
4. Home → *Manage supported apps* → select one test app (WhatsApp or the
   system Messages app). Use a test account, not real conversations.

## Tests

| # | Step | Expected | Result |
|---|---|---|---|
| 1 | Send a test message from the selected app while ReplyMate is in background | Composer shows the message text as context, with the sender as title | _pending_ |
| 2 | Send a message from a **non-selected** app | Nothing is captured; composer unchanged | _pending_ |
| 3 | Lock-screen / redacted notification (privacy setting hides content) | Context card warns *may be redacted* or *no message text available*; no crash | _pending_ |
| 4 | Grouped notification (3+ messages stacked) | Warning chip says *grouped notification*; summary text shown as-is | _pending_ |
| 5 | Very long message (6000+ characters) | Warning chip says *text may be truncated* | _pending_ |
| 6 | Generate a reply (Firebase configured) | Suggestions in the chosen language and tone; count matches | _pending_ |
| 7 | Quick reply on a notification that shows a reply action | Reply lands in the source app; snackbar confirms | _pending_ |
| 8 | Quick reply where the notification has **no** reply action | Button absent; copy/open-app fallback explained | _pending_ |
| 9 | Swipe away the notification, then try quick reply from a stale session | Honest *no longer valid* message, no crash | _pending_ |
| 10 | Select text in the system Messages app → selection menu | *ReplyMate AI* entry appears; tapping opens the composer with that text | _pending_ |
| 11 | Same selection-menu test inside WhatsApp | Record whether the entry appears (WhatsApp uses custom views; absence is a known limitation, not a bug) | _pending_ |
| 12 | Share a text message from any app to ReplyMate | Composer opens with the shared text | _pending_ |
| 13 | Revoke notification access in Settings, return to the app | Status card flips to *not granted*; manual paste still works | _pending_ |
| 14 | Force-stop ReplyMate, send a message, reopen the app | Record whether the notification was missed (Android may not reconnect the listener until reboot on some OEMs) | _pending_ |
| 15 | Battery-optimization / OEM background restriction enabled | Record listener behaviour per manufacturer | _pending_ |
| 16 | With the composer open for message A, let a **second** notification from another chat (with a reply action) arrive, then use quick reply | Quick reply is refused; the reply is never delivered to the second chat; copy/open-app fallback is offered instead | _pending_ |

## Reading the results

- Any _pending_ left when someone claims Phase 1 done = the gate is not met.
- Rows 10, 11, 14 and 15 are **evidence rows**: whatever the device says is
  the truth, and the docs (NOTIFICATION_LISTENER.md, README capability
  claims, app copy) get updated to match it - never the other way round.
- Privacy rows to re-check while here: no message content in `logcat`
  (`adb logcat | grep -i replymate`), nothing retained after the composer
  closes, no network call before the user taps Generate.
