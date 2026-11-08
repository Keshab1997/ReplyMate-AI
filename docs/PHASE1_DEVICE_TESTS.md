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
quick-reply delivery, inbound or outbound sharing, text-selection behavior,
composer-close cleanup or the rest of this checklist; keep those cases pending
until their results are recorded.

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
| 17 | From a generated suggestion, tap **Share** and choose a destination app | The system chooser shows the edited reply; nothing is sent until the user confirms in the destination app | _pending_ |
| 18 | Open the composer from a notification, close it, then open it again without a new notification | The previous message is not shown and quick reply is unavailable until a fresh notification arrives | _pending_ |

### Floating bubble (`docs/FLOATING_OVERLAY.md`)

Grant the optional overlay permission on the permission screen before starting
this block. Rows 17–24 are the acceptance evidence for the bubble; none of
them can be checked from CI.

| # | Step | Expected | Result |
|---|---|---|---|
| 17 | Open WhatsApp, keep it foreground, ask someone to send a message | A small ReplyMate bubble appears within ~2 s; it shows no sender and no message text | _pending_ |
| 18 | Tap the bubble | Panel opens showing that message; Generate returns suggestions in the chosen language and tone (with Firebase) or an honest "not configured / no key" message (without) | _pending_ |
| 19 | Edit a suggestion, then Copy | Clipboard holds the edited text; snackbar confirms | _pending_ |
| 20 | Use quick reply from the panel, then trigger another chat's notification and try again | First reply lands in the correct chat; the second is refused with the copy/open-app explanation, never delivered to the wrong chat | _pending_ |
| 21 | Revoke overlay permission (Settings → Apps → Special access → Display over other apps), send a message, then tap the fallback notification | No bubble; a notification says "New message from WhatsApp" with **no text**; tapping opens the composer prefilled | _pending_ |
| 22 | Force-stop ReplyMate, send a message, wait, then open the app | Record what happens: bubble, fallback notification, or nothing. No crash either way | _pending_ |
| 23 | Drag the bubble to another corner; turn the screen off and on; lock and unlock; wait 10 minutes | Bubble follows the drag, hides while the screen is off/locked, auto-hides after the timeout, leaves no ghost view | _pending_ |
| 25 | Tap the bubble on a chat you have not opened | Only the panel appears; Close puts you back in WhatsApp, never in ReplyMate | _pending_ |
| 26 | Drag the bubble to the left or right screen edge and let go | It tucks itself into a slim tab on that edge; the messaging app underneath stays usable |
| 27 | Tap the tucked tab, then drag the tab back into the middle of the screen | First tap restores the full bubble without opening the panel; releasing it mid-screen leaves a full bubble, not a stray tab |
| 28 | Tuck the bubble away, then send yourself a message | The bubble expands again on its own and shows the count, so a hidden bubble never misses a message |
| 33 | Long-press the bubble for half a second, then tap *Hide at the edge* | A three-row menu appears beside the bubble; the bubble tucks to the nearest edge and the menu closes |
| 34 | Long-press, then tap *Dismiss until the next message* | Bubble and menu both disappear; the next message brings the bubble back |
| 35 | Long-press the bubble, then tap the bubble again (or ignore the menu for 6 seconds) | The menu closes and the panel does not open by accident |
| 30 | Send a message and watch the bubble for ten seconds | The 3D face bobs gently and blinks now and then; scrolling the chat behind it stays smooth; no battery or jank complaint |
| 31 | Tap the bubble, close the panel, then tap the bubble again | The bubble is back in the same spot after the panel closes and the second tap shows the same message, not an empty panel |
| 32 | Keep the panel closed and send yourself a second message | One soft pop, a haptic tick and the count goes to 2 - never a second bubble |
| 29 | Copy a message from the chat, tap the bubble / Paste, then Generate | The pasted text is what gets replies; Copy puts the captured message on the clipboard; Edit lets you change it first |
| 24 | Close the panel, then inspect storage and logs: `adb shell run-as com.keshabstudios.replymate ls -R files/ shared_prefs/` and `adb logcat -c && adb logcat \| grep -i replymate` | No message text anywhere on disk; no message text in logcat | _pending_ |

## Reading the results

- Any _pending_ left when someone claims Phase 1 done = the gate is not met.
- Rows 10, 11, 14, 15 and 22 are **evidence rows**: whatever the device says
  is the truth, and the docs (NOTIFICATION_LISTENER.md, README capability
  claims, app copy) get updated to match it - never the other way round.
- Privacy rows to re-check while here: no message content in `logcat`
  (`adb logcat | grep -i replymate`), nothing retained after the composer
  closes or the bubble panel closes, no network call before the user taps
  Generate.
