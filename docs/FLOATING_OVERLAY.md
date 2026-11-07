# Floating Reply Bubble — Implementation Spec

**Status: specified, not implemented.** This file is the source of truth for
the bubble. If code and this document disagree, the code is wrong until this
document is updated on purpose.

**Why it exists:** today a captured notification is only kept in memory while
the Flutter engine is alive, and nothing in the UI appears when a message
arrives. So a WhatsApp message produces no reply unless the user happened to
open ReplyMate seconds earlier. The bubble closes that gap.

---

## 1. What the user gets

1. A WhatsApp (or other allowlisted app) notification arrives while the user
   is inside that app.
2. A small circular ReplyMate bubble appears over the current screen.
3. The user taps it.
4. A panel opens over WhatsApp with: the message, language/tone/length chips,
   and a Generate button.
5. Suggestions appear. Each can be copied, edited, or sent with quick reply
   when — and only when — the original notification still has a valid
   `RemoteInput` action.
6. Closing the panel removes the bubble. No message text is kept anywhere.

The bubble never reads the screen. It only knows what the notification posted.

---

## 2. Scope

### In scope (v1)

- Overlay bubble over other apps (WhatsApp first).
- Panel with message context, generation, copy, edit, conditional quick reply.
- Fallback notification when the bubble cannot be shown.
- Overlay permission explained and requested from the existing permission
  screen.
- Settings toggle to disable the bubble and the fallback notification.
- Honest states: no Firebase, no key pool, no message text, dead action.

### Out of scope (do not build now)

- Reading text under the bubble (no AccessibilityService, no MediaProjection,
  no screen capture, ever).
- Reply to a conversation the notification does not identify.
- Automatic sending of anything.
- Persisting message content to disk.
- iOS. Android only.
- A second AI client, a backend, analytics, or crash reporting.

---

## 3. Hard rules (violating one of these fails review)

1. **No AccessibilityService, no screen scraping.** The bubble is drawn with
   `WindowManager`; it does not inspect the app underneath.
2. **No message content on disk.** The pending message lives in process memory
   (`OverlayBubbleController`) and, while the panel is open, in the intent that
   launched it. It is cleared when the panel closes.
3. **No message text in logs.** Not `Log.d`, not `debugPrint`, not analytics.
4. **No automatic send.** Quick reply runs only after the user taps a specific
   suggestion, and only against the notification that produced the context.
5. **No new AI path.** Generation goes through the existing
   `replyRepositoryProvider` (`KeyPoolReplyRepository`). Do not add an HTTP
   client to Kotlin.
6. **Guest mode still works.** Without `google-services.json` the panel opens,
   shows the message, and explains that AI is not configured. It never crashes.
7. **Honest fallbacks.** A missing overlay permission, a dead quick-reply
   action, or an empty key pool is explained, never hidden.

---

## 4. Architecture

### 4.1 Why native bubble + Flutter panel

The Flutter engine only exists while an activity is alive, which is exactly
the problem being solved. Two designs were considered:

| Option | Verdict |
|---|---|
| Native bubble + native panel, AI called over a second headless FlutterEngine | Works, but two engines, two Firebase/Hive bootstraps, and the panel would have to be rebuilt in Kotlin. |
| **Native bubble + translucent Flutter activity for the panel** | **Chosen.** The bubble is a tiny `WindowManager` view (always-on-top, no engine needed). The panel reuses every existing Dart screen, provider and test. One engine at a time. |

The bubble is the only truly native UI. It must stay small and dumb: draw,
drag, tap, disappear.

### 4.2 Components

```text
ReplyMateNotificationListener          (existing, extended)
  └─ onNotificationPosted → filter → OverlayBubbleController.hold(context)
                                   → OverlayBubbleService.show()

OverlayBubbleController                (new, in-memory singleton)
  └─ holds ONE pending context map, cleared on consume

OverlayBubbleService : Service         (new, foreground)
  ├─ NotificationChannel "replymate_bubble" (IMPORTANCE_MIN)
  ├─ WindowManager + TYPE_APPLICATION_OVERLAY view (56dp)
  └─ tap → startActivity(OverlayPanelActivity, extras)

OverlayPanelActivity : FlutterActivity (new, translucent, exported=false)
  └─ getInitialRoute() = "/overlay"
       → OverlayPanelScreen (new Dart screen)

OverlayPanelScreen                     (new Dart)
  └─ reads the context through the channel → renders message + chips +
     Generate + suggestion cards (reuses ReplyRequest / replyRepositoryProvider)

FallbackNotification                   (new, in the listener)
  └─ when the bubble cannot show: one notification per package,
     "New message from <app>" + "Draft reply" PendingIntent (no message text)
```

### 4.3 Data flow

```text
allowlisted notification with text
        │
        ├── overlay permission granted AND bubble enabled
        │       → OverlayBubbleController.hold(...)
        │       → OverlayBubbleService.start/show bubble
        │       → tap → OverlayPanelActivity("/overlay")
        │       → consumeOverlayContext → OverlayPanelScreen
        │
        └── otherwise
                → fallback notification (no text) → tap → MainActivity
                → consumeOverlayContext → ReplyComposerScreen (prefilled)
```

Both paths end in Dart with the same context map, so the message model is one
class.

---

## 5. Contracts

### 5.1 Channel (Dart ⇄ Kotlin)

Channel stays `com.keshabstudios.replymate/notifications`. New methods, all
documented in `docs/PLATFORM_CHANNELS.md` before they are written:

| Method | Direction | Arguments | Returns |
|---|---|---|---|
| `isOverlayEnabled` | Dart → Kotlin | – | `bool` (`Settings.canDrawOverlays`) |
| `openOverlaySettings` | Dart → Kotlin | – | `null` (opens `ACTION_MANAGE_OVERLAY_PERMISSION` with package uri) |
| `requestNotificationPermission` | Dart → Kotlin | – | `bool` (Android 13+ runtime POST_NOTIFICATIONS; `true` below 33) |
| `setBubbleEnabled` | Dart → Kotlin | `{enabled: bool}` | `null` (persists natively + starts/stops the service) |
| `consumeOverlayContext` | Dart → Kotlin | – | `Map?` `{source, packageName, key, title, text, isTruncated, isGrouped, mayBeRedacted, hasReplyAction}`; one-shot |

`source` is `"bubble"` or `"fallback"` so the Dart side can pick the screen
(panel vs composer). The notification fields use the same wire format as
`notification_captured` (docs/PLATFORM_CHANNELS.md), so
`CapturedNotification.fromMap` is reused unchanged.

### 5.2 Pending context lifetime

- `OverlayBubbleController.hold(map)` replaces any previous pending context.
  One message at a time; a newer notification wins.
- `consume()` returns the map and clears it — exactly once.
- `onDestroy` of the service and process death clear it implicitly.
- **Never** write it to SharedPreferences, a file, a database, or a log.

### 5.3 Filter for showing the bubble

Show only when **all** are true:

- package is on the user's allowlist (existing check);
- `text` is non-empty;
- not a group summary (`FLAG_GROUP_SUMMARY` unset);
- not ongoing (`FLAG_ONGOING_EVENT` unset);
- not a media/transport notification (no `MediaStyle`);
- screen is on and the device is unlocked;
- bubble is enabled by the user;
- the overlay permission is granted.

Anything else is dropped? No — it is still captured for the in-app list; it
just does not raise a bubble.

Hide the bubble immediately when: the source notification is removed, the
panel opens, 10 minutes pass, or the user taps the bubble's close affordance.

---

## 6. Permissions

| Permission | Why | Where requested |
|---|---|---|
| `BIND_NOTIFICATION_LISTENER_SERVICE` (user grant) | the only message source | existing permission screen → Android Settings |
| `SYSTEM_ALERT_WINDOW` | draw the bubble | new card on the permission screen → `ACTION_MANAGE_OVERLAY_PERMISSION` |
| `POST_NOTIFICATIONS` | foreground-service notification + fallback notification | runtime request on Android 13+ before the service starts |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE` | keep the bubble alive | manifest; declare in Play Console |

Rules:

- No permission implies another. Granting overlay access must not be treated
  as notification access.
- Every request is explained in plain language first, on the permission
  screen, before Android's dialog appears.
- Declining overlay keeps the rest of the app working; the fallback
  notification is the degraded path.

### Manifest additions

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>

<service
    android:name=".OverlayBubbleService"
    android:exported="false"
    android:foregroundServiceType="specialUse">
    <property
        android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
        android:value="floating reply bubble for messages the user allows" />
</service>

<activity
    android:name=".OverlayPanelActivity"
    android:exported="false"
    android:excludeFromRecents="true"
    android:theme="@style/OverlayPanelTheme" />
```

`OverlayPanelTheme` (values/styles.xml): `windowIsTranslucent=true`,
`windowBackground=@android:color/transparent`, `backgroundDimEnabled=false`,
`windowNoTitle=true`.

---

## 7. Android 12+ background-start reality

A foreground service may **not** be started from the background. Consequences:

- Start the bubble service from `MainActivity.onStart` (the user opened the
  app), and from `ReplyMateNotificationListener.onListenerConnected` **only**
  when the service is already running (bind, do not start).
- A cold-started process that receives a notification while the app is not
  running **cannot** raise a bubble by itself. It must post the fallback
  notification instead. This is the documented degraded path, not a bug.
- Never crash on `ForegroundServiceStartNotAllowedException`; catch it and fall
  back to the notification.

Document the behaviour honestly in the README and in `docs/NOTIFICATION_LISTENER.md`.
Do not promise a bubble on every OEM.

---

## 8. Failure modes and what the user sees

| Situation | Bubble | Panel / fallback |
|---|---|---|
| Overlay permission missing | none | fallback notification → composer prefilled |
| Bubble disabled in Settings | none | nothing (user's choice; do not nag) |
| POST_NOTIFICATIONS denied (13+) | service runs, notification hidden | bubble still works while the process lives; say so in Settings |
| App process killed, new message | none (cannot start FGS) | fallback notification |
| Message has no text (redacted) | none | nothing — there is nothing to reply to |
| Firebase / key pool missing | bubble shows | panel explains AI is not configured |
| No healthy key | bubble shows | panel shows the key-pool error |
| Notification dismissed after bubble | bubble hides | quick reply refuses honestly |
| Quick reply has no RemoteInput | bubble shows | button hidden; copy/open-app explained |
| A second chat's notification arrives while panel open | bubble updates | the old context becomes stale; quick reply refuses (existing key binding) |

---

## 9. Privacy and Play compliance

- The bubble shows an icon only — never message text.
- The fallback notification shows the app name only — never message text.
- The panel shows the text because the user asked for it, on their screen.
- No storage, no logs, no analytics.
- Prominent in-app disclosure before the first bubble: what notification
  access reads, what the bubble does, that message text is sent to an AI
  provider only when Generate is tapped.
- Play Console declarations: notification-listener access, foreground service
  (`specialUse`), overlay usage. The privacy policy must be published before
  release — this is a release gate in `docs/BUILD_AND_RELEASE.md`.
- Overlay + notification listener combined draws scrutiny. Ship behind a
  Settings toggle that defaults **off** until the user grants overlay access.

---

## 10. Device test additions

Rows 17–24 in `docs/PHASE1_DEVICE_TESTS.md` are the acceptance evidence. The
bubble is not "done" until those rows say what the device actually does.

---

## 11. Troubleshooting (support-facing)

- **No bubble at all** — check overlay permission, the Settings toggle, and
  whether POST_NOTIFICATIONS was granted on Android 13+. If the app process was
  dead, only the fallback notification is expected.
- **Bubble appears but panel is blank** — the pending context was consumed by
  another launch; dismiss and wait for the next message.
- **Bubble over the wrong app** — it follows the notification, not the
  foreground app. That is intended; it never reads the screen.
- **Bubble vanishes after a while** — 10-minute auto-hide; by design.
- **Quick reply button missing** — the notification has no `RemoteInput`
  action. Copy instead.
- **Battery saver kills it** — expected on some OEMs. The fallback
  notification is the reliable path.
