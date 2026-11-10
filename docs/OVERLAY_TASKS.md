# Overlay Work — Task Breakdown for the Implementing Agent

Read `docs/FLOATING_OVERLAY.md` first. This file turns that spec into ordered,
reviewable batches. Do not skip ahead: each batch must leave the app
buildable and every check green.

**Repo rules that still apply:** `AGENTS.md` (manual CI, preflight before every
push, commit straight to `main`, conventional messages), guest-mode invariant,
no automatic message sending, no message content on disk, no message text in
logs, and screen reading only through the consented path in
docs/SCREEN_READING.md.

---

## Definition of done (whole feature)

- [ ] Bubble appears over WhatsApp for an allowlisted notification with text,
      within ~2 s, while WhatsApp is foreground.
- [ ] Tapping it opens a panel with the message and three suggestions (Firebase
      configured) or an honest explanation (not configured / no key).
- [ ] Copy works; edit works; quick reply is offered only with a live
      `RemoteInput` action and is refused honestly when stale.
- [ ] Without overlay permission, a fallback notification appears; tapping it
      opens the composer prefilled with the message.
- [ ] No message text is written to disk or logs (`run-as` check below).
- [ ] Settings has a working bubble toggle, default off.
- [ ] `flutter analyze` clean, `flutter test` green, `python3 tool/preflight.py`
      clean.
- [ ] `docs/PHASE1_DEVICE_TESTS.md` rows 17–24 filled from a real device.
- [ ] `docs/PLATFORM_CHANNELS.md`, `docs/PRIVACY_AND_PERMISSIONS.md`,
      `docs/USER_FLOWS.md`, `docs/SCREEN_SPECIFICATIONS.md`, `README.md`
      updated in the same batch as the code.

---

## Batch 0 — Make the current silence honest (small, do it first)

**Problem:** when nothing was captured, the composer shows an empty box with
no explanation. This is the symptom the user reported.

- `lib/features/reply/presentation/reply_composer_screen.dart`
  - When `_context == null` and `launch == null` and the captured list is
    empty, show: *"No message was captured. ReplyMate only keeps a message
    while the app is running; open ReplyMate after a new message arrives, or
    paste the text."*
  - Do not add a "Generate" hint that implies a message exists.
- Test: `test/suggestions_screen_test.dart` is the wrong file — add
  `test/reply_composer_test.dart` with a widget test asserting the empty-state
  text and that Generate is still tappable (validation explains the problem).
- Docs: none beyond the composer comment.

**Acceptance:** opening the app with an empty capture list explains itself
instead of showing a blank composer.

---

## Batch 1 — Native bubble service (no panel yet)

Files:

- `android/app/src/main/kotlin/com/keshabstudios/replymate/OverlayBubbleController.kt`
  - `object OverlayBubbleController`
  - `@Volatile var pending: Map<String, Any?>? = null`
  - `@Synchronized fun hold(context: Map<String, Any?>)`
  - `@Synchronized fun consume(): Map<String, Any?>?`
  - Javadoc must state: memory only, never persisted, never logged.
- `android/app/src/main/kotlin/com/keshabstudios/replymate/OverlayBubbleService.kt`
  - `Service`, foreground, `START_NOT_STICKY`.
  - `onCreate`: notification channel `replymate_bubble` (IMPORTANCE_MIN,
    `setShowBadge(false)`), `startForeground(OVERLAY_NOTIF_ID, notification)`.
  - Build the view in code (no XML): `FrameLayout` 56dp, circular background,
    `ImageView` with `@mipmap/ic_launcher` as a placeholder glyph.
  - `WindowManager.LayoutParams`: `TYPE_APPLICATION_OVERLAY`,
    `FLAG_NOT_FOCUSABLE`, `PixelFormat.TRANSLUCENT`,
    `Gravity.TOP or Gravity.START`, default x/y from resources.
  - Drag with `OnTouchListener` (touch slop distinguishes drag from tap).
  - Tap → `startActivity(OverlayPanelActivity.createIntent(this))` (Batch 2);
    until Batch 2 exists, start `MainActivity` with
    `ACTION_OVERLAY_PANEL` and finish the batch with the intent constant in
    place.
  - `show()` becomes a no-op when `pending == null`.
  - `onDestroy`: remove the view, `stopForeground(STOP_FOREGROUND_REMOVE)`.
  - Catch `ForegroundServiceStartNotAllowedException` in `start()` and return
    `false` — the caller posts the fallback notification instead.
- `AndroidManifest.xml`: service + `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_SPECIAL_USE`, `SYSTEM_ALERT_WINDOW` permissions.
- `android/app/src/main/res/values/styles.xml`: `OverlayPanelTheme` (needed in
  Batch 2, harmless now).

Tests: none on the Kotlin side (there is no JVM test harness in this repo).
Cover it with device row 17 instead.

**Acceptance:** with the permission granted and the app opened once, a bubble
can be shown via a temporary debug call and disappears on stop.

---

## Batch 2 — Panel route in Flutter

- New `lib/features/overlay/models/overlay_context.dart`
  - `OverlayContext.fromMap(Map<String, Object?>)` with `source`
    (`bubble`/`fallback`) + a `CapturedNotification` built through the existing
    parser (`CapturedNotification.fromMap`). Unit-test it against every row of
    the wire table, including unknown `source` and missing fields.
- New `lib/features/overlay/presentation/overlay_panel_screen.dart`
  - Transparent `Scaffold`, bottom-anchored `Card`, drag-to-dismiss optional.
  - Header: app label + close button.
  - Message text (read-only, scrollable, max ~40% of height).
  - Reuses `ChoiceChips` for language/tone/length and `SuggestionCard` for
    results.
  - Generate → `replyRepositoryProvider.generate(ReplyRequest(...))`, same
    failure display as the composer.
  - Quick reply uses `NotificationsBridge.sendQuickReply(text, key)`.
  - No Firebase → honest guest-mode text, no crash.
- `lib/app/app.dart`
  - Replace `home:` with `initialRoute: '/'` + `onGenerateRoute`; add a
    `/overlay` route that builds `OverlayPanelScreen`.
  - Keep `StartupGate` for `/`.
- `lib/core/platform/notifications_bridge.dart`
  - `Future<Map<String, Object?>?> consumeOverlayContext()`.
  - Provider: `overlayContextProvider` (FutureProvider, one-shot).
- `android/.../OverlayPanelActivity.kt`
  - `FlutterActivity`, `getInitialRoute() = "/overlay"`,
    `getBackgroundMode()` handled through the intent extra
    `background_mode=transparent` (or
    `FlutterActivityLaunchConfigs.BackgroundMode.transparent` when using the
    builder in a static `createIntent`).
  - `exported=false`, `excludeFromRecents=true`, translucent theme.
  - `onNewIntent` must refresh the context (a second notification while the
    panel is open).

**Acceptance:** launching `/overlay` renders the panel with a stubbed context;
`flutter test` includes the new model test.

---

## Batch 3 — Wire the listener to the bubble

- `ReplyMateNotificationListener.kt`
  - After the existing parse, decide `shouldRaiseBubble(parsed)` using the
    filter in `docs/FLOATING_OVERLAY.md §5.3`.
  - If yes and the bubble is enabled: `OverlayBubbleController.hold(...)`,
    then bind/show the service; if starting it throws, post the fallback.
  - If no (or the bubble cannot show): post/update the fallback notification
    **only when the bubble is not available**, one per package, id
    `packageName.hashCode()`, `setOnlyAlertOnce(true)`.
  - Fallback content: *"New message from <label>"*, *"Draft a reply"*,
    `contentIntent` → `MainActivity` with the pending context consumed on
    start. Never include the message text.
  - `onNotificationRemoved`: hide the bubble if it belongs to that key.
- `MainActivity.kt`
  - `onStart`: if bubble enabled + overlay granted, start the service
    (foreground start is allowed from a foreground activity).
  - New methods: `isOverlayEnabled`, `openOverlaySettings`,
    `requestNotificationPermission`, `setBubbleEnabled`,
    `consumeOverlayContext`.
- `lib/features/permissions/providers/permission_provider.dart`
  - `overlayProvider` (bool) + `refreshOverlay()`.
- `lib/features/permissions/permission_setup_screen.dart`
  - Second card: *Floating reply bubble (optional)* — what it does, what it
    does **not** do, current status, button → overlay settings, and a note
    that Android 13+ also needs notifications allowed.
- `lib/features/settings/settings_screen.dart`
  - Switch *Reply bubble* (default off until permission granted), persisted via
    `setBubbleEnabled` + a SharedPreferences key
    `replymate.bubble_enabled` in `AppConstants`.
- `lib/main.dart` / `app.dart`
  - If the launch is from a fallback notification, route to the composer with
    the consumed context instead of Home.

**Acceptance:** a real WhatsApp message raises the bubble; without overlay
permission the fallback notification appears and opens a prefilled composer.

---

## Batch 4 — Safety net and polish

- Auto-hide after 10 minutes (Handler + `removeCallbacks` on destroy).
- Hide when screen off (`ACTION_SCREEN_OFF` receiver inside the service) and
  when locked (`KeyguardManager.isKeyguardLocked`).
- Bubble shows a small count badge when a second message arrives.
- Do not draw over ReplyMate's own activity (compare
  `ActivityManager.getRunningTasks`? **No** — that needs a permission. Skip;
  the bubble over our own app is harmless).
- Play declarations and privacy-policy checklist item in
  `docs/BUILD_AND_RELEASE.md`.
- README capability paragraph: bubble is optional, needs overlay permission,
  may not survive aggressive OEM battery managers.

---

## Verification (run in this order)

```bash
python3 tool/preflight.py                 # seconds
flutter analyze                           # must be clean
flutter test                              # all green
```

Device evidence (a real phone; CI cannot see any of this):

```bash
# no message content anywhere on disk
adb shell run-as com.keshabstudios.replymate ls -R files/ shared_prefs/

# no message content in logs
adb logcat -c && adb logcat | grep -i replymate
```

Then fill rows 17–24 of `docs/PHASE1_DEVICE_TESTS.md` and commit them with the
code that produced them.

---

## Do not

- Do not add `MediaProjection` or any screen-capture API. Screen reading
  exists in exactly one place - `ReplyMateScreenReaderService`, documented in
  docs/SCREEN_READING.md - and it only ever reads. Do not add a second one; if
  a task seems to need one, stop and report.
- Do not persist the pending message, its sender, or its text.
- Do not add a Kotlin HTTP client or a second AI integration.
- Do not send anything automatically, including "obvious" replies.
- Do not show message text in the bubble or the fallback notification.
- Do not claim universal bubble support in UI copy or docs. OEMs kill
  background services; the fallback notification is the honest promise.
- Do not bump the version or tag a release as part of this work.
- Do not edit `.github/workflows/` to make a check pass.

---

## Handy references

- `docs/FLOATING_OVERLAY.md` — the spec, including the filter and failure table.
- `docs/PLATFORM_CHANNELS.md` — the channel contract (add the new methods here
  **before** implementing them).
- `docs/NOTIFICATION_LISTENER.md` — listener rules the bubble must not break.
- `docs/PHASE1_DEVICE_TESTS.md` — evidence table (rows 17–24 are new).
- `lib/features/reply/presentation/suggestions_screen.dart` — the quick-reply
  behaviour to reuse, including the stale-key refusal.
- `android/.../ReplyMateNotificationListener.kt` — `sendQuickReply(text, key)`
  is already bound to one notification; keep that guarantee.
