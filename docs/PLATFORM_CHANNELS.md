# Platform Channel Contract

Single MethodChannel, both directions:

```text
com.keshabstudios.replymate/notifications
```

Dart side: `lib/core/platform/notifications_bridge.dart`.
Kotlin side: `android/app/src/main/kotlin/com/keshabstudios/replymate/MainActivity.kt`.

Every Dart method degrades to a safe empty answer when the native layer is
absent (widget tests, web preview), so the UI explains instead of crashing.

## Dart -> Kotlin methods

| Method | Arguments | Returns | Notes |
|---|---|---|---|
| `isListenerEnabled` | – | `bool` | Reads `Settings.Secure.enabled_notification_listeners` for our component. |
| `openListenerSettings` | – | `null` | Starts `ACTION_NOTIFICATION_LISTENER_SETTINGS`. The grant decision stays in Android Settings. |
| `candidateApps` | – | `List<Map>` of `{packageName, label}` | Only packages that are installed **and** visible under the manifest `<queries>` list. Never claims an app it cannot see. |
| `setAllowedPackages` | `{packages: List<String>}` | `null` | Mirrors the user's allowlist into native prefs; the listener processes only these packages. |
| `sendQuickReply` | `{text: String, key: String}` | `bool` | Attempts a RemoteInput reply on the notification identified by `key`, and only when that is still the notification the listener holds. `false` = no service / no stored notification / a different notification was captured in the meantime / dead action / throw; the UI then offers copy or open-app. |
| `shareText` | `{text: String}` | `bool` | Opens Android's system share chooser with the edited reply. `true` means only that the chooser opened; the user chooses a destination and confirms any send. Missing plugin, empty text or launch failure returns `false`. |
| `clearRetainedContext` | – | `null` | Clears the native reply action held for the current composer session. Called when the composer closes; Dart also clears its in-memory notification buffer. |
| `consumeLaunchContext` | – | `Map?` `{source, text}` or `null` | Text from `ACTION_PROCESS_TEXT` (`source: process_text`) or `ACTION_SEND` (`source: share`). Consumed once, then cleared. |

`sendQuickReply` is bound to one notification. The listener keeps a single
notification - the last one that exposed a reply action - and the call carries
that notification's `key`, so a reply is only ever delivered to the
conversation it was written for. A newer notification from another chat makes
the stored action stale, the call returns `false`, and the UI falls back to
copy / open-app instead of delivering the reply somewhere the user never saw
it.

## Kotlin -> Dart events (`onEvent`)

| `type` | Payload | Meaning |
|---|---|---|
| `listener_connected` | – | The notification listener service is live. |
| `listener_disconnected` | – | The service died or access was revoked. |
| `notification_captured` | `{notification: <map below>}` | A notification from an allowed package arrived. |
| `screen_captured` | `{notification: <map below>}` | A message was read off the screen of an allowed package (docs/SCREEN_READING.md). Same payload, plus `fromScreen: true`. |

Events posted before the engine exists, or after it is torn down, are
**dropped on purpose**: queueing them would retain message content
(docs/PRIVACY_AND_PERMISSIONS.md, data minimization).

## `notification_captured` wire format

| Key | Type | Notes |
|---|---|---|
| `packageName` | `String` | Required; a missing one makes the event untrusted (`FormatException`). |
| `key` | `String` | Required; `StatusBarNotification.key`. |
| `title` | `String?` | `EXTRA_TITLE`, null when absent. |
| `text` | `String?` | `EXTRA_TEXT`, falling back to `EXTRA_BIG_TEXT` when the app puts the body only there. Null when the notification exposes no text at all - a normal state (FR-04). |
| `isTruncated` | `bool` | `EXTRA_BIG_TEXT` at the platform cap (5120) or a trailing ellipsis. |
| `isGrouped` | `bool` | `notification.group != null`. |
| `isGroupSummary` | `bool` | `FLAG_GROUP_SUMMARY`. |
| `mayBeRedacted` | `bool` | `visibility != VISIBILITY_PUBLIC`: lock-screen content may arrive redacted. |
| `hasReplyAction` | `bool` | True only when some action carries a non-empty `remoteInputs`. |
| `replyActionLabel` | `String?` | That action's title. |
| `postedAtMillis` | `int` | `StatusBarNotification.postTime`. |
| `fromScreen` | `bool` | `true` when the text was read off the screen rather than delivered by a notification; absent means false. Surfaced on the model as `isScreenRead` so the UI can say where a message came from. |

Dart mirror: `CapturedNotification.fromMap` - strict about structure, lenient
about content, and unit-tested against every row of this table.

## Entry points into the composer

1. **Notification capture** - the listener service, filtered by the allowlist.
2. **Text selection** - `ACTION_PROCESS_TEXT` intent filter on `MainActivity`;
   selected text arrives as `EXTRA_PROCESS_TEXT`.
3. **Share sheet** - `ACTION_SEND` with `text/plain`; text arrives as
   `EXTRA_TEXT`.
4. **Manual** - the composer's text field; paste or type, no integration
   needed.

Routes 2 and 3 are user-initiated by construction: Android only delivers them
after an explicit user action in another app. Route 5 (screen reading) is
user-initiated by consent instead: it needs accessibility access granted in
Android Settings **and** the in-app switch, and it is documented in
docs/SCREEN_READING.md.

---

# Floating reply bubble

Specified in `docs/FLOATING_OVERLAY.md`; batches in `docs/OVERLAY_TASKS.md`.
Implement a method — and this table — in the same batch, or the channel and its
documentation drift apart. All five methods below are implemented; the bubble
service, the panel route (`/overlay`) and the listener wiring shipped with them.

## Dart -> Kotlin methods

| Method | Arguments | Returns | Status | Notes |
|---|---|---|---|---|
| `consumeOverlayContext` | – | `Map?` | **implemented** | One-shot pending context, read by `overlayContextProvider` and parsed by `OverlayContext.fromMap`. Same field names as the `notification_captured` table above, plus `source` (`bubble` / `fallback`). Cleared on read, so a second call returns `null`. |
| `isOverlayEnabled` | – | `bool` | **implemented** | `Settings.canDrawOverlays(this)`. |
| `openOverlaySettings` | – | `null` | **implemented** | `ACTION_MANAGE_OVERLAY_PERMISSION` with our package uri. Grants nothing by itself. |
| `requestNotificationPermission` | – | `bool` | **implemented** | Runtime `POST_NOTIFICATIONS` on Android 13+; `true` on older versions. Needed before the bubble service can show its own notification. |
| `setBubbleEnabled` | `{enabled: bool}` | `null` | **implemented** | Persists in native prefs and starts/stops `OverlayBubbleService`. Starting from the background may throw `ForegroundServiceStartNotAllowedException`; that is caught and reported as `false`, never a crash. |
| `isScreenReadingAvailable` | – | `bool` | **implemented** | Whether Android has granted accessibility access to `ReplyMateScreenReaderService`, read from `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES`. `false` on a device that refuses the grant (Android 16+ Advanced Protection Mode does exactly this for an app it does not classify as an accessibility tool). |
| `openAccessibilitySettings` | – | `null` | **implemented** | Starts `ACTION_ACCESSIBILITY_SETTINGS`. Grants nothing by itself. |
| `setScreenReadingEnabled` | `{enabled: bool}` | `null` | **implemented** | Persists the user's screen-reading switch in native prefs, because the accessibility service runs with no Flutter engine alive. |

`source` is `bubble` (the panel activity launched at route `/overlay`) or
`fallback` (ReplyMate's own notification, which opens the composer). An unknown
`source` is read as `fallback`: the conservative path can never promise more
than Android gave us.

## Fallback notification

When the bubble cannot be shown (no overlay permission, bubble disabled,
process cold-started in the background), the listener posts one notification
per package:

- title: *New message from \<app label\>* — **never** the message text
- action: *Draft a reply* → `MainActivity`, which consumes the pending context
  and opens the composer prefilled
- one notification id per package, `setOnlyAlertOnce(true)`, replaced rather
  than stacked

`consumeOverlayContext` returns the same map in both paths, so the Dart side
has exactly one model (`OverlayContext`).
