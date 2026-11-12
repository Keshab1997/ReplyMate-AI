# Floating Reply Bubble — Implementation Spec

**Status: implemented (batches 0–4 of `docs/OVERLAY_TASKS.md`); device
verification pending.** This file is the source of truth for the bubble. If code
and this document disagree, the code is wrong until this document is updated on
purpose.

Rows 17–24 of `docs/PHASE1_DEVICE_TESTS.md` are still `_pending_`. The agent
sandbox has no Android device or emulator, so nothing in this document has been
confirmed on hardware yet - the bubble is code-complete, not device-proven.

**Why it exists:** today a captured notification is only kept in memory while
the Flutter engine is alive, and nothing in the UI appears when a message
arrives. So a WhatsApp message produces no reply unless the user happened to
open ReplyMate seconds earlier. The bubble closes that gap.

---

## 1. What the user gets

1. A WhatsApp (or other allowlisted app) notification arrives while the user
   is inside that app.
2. A small circular ReplyMate bubble appears over the current screen. Drag it
   anywhere; drop it within a thumb of a screen edge and it tucks itself away
   as a slim tab (the user's own choice to get it out of the way). Tap the tab
   and the full bubble comes back - a tucked bubble never fires an action by
   accident, and a new message expands it on its own.
3. The user taps it.
4. A panel opens over WhatsApp with: the message, the **reply style the user
   already chose in Settings**, and a Generate button. The message can be
   copied, edited by hand, or replaced with one pasted from the clipboard -
   which is the supported way to reply to something the notification never
   carried. The panel deliberately
   does not re-ask language/tone/length - a bubble is a shortcut, not a second
   app - and a tune icon in its header opens Settings when the style does need
   changing.
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

- Reading text *under the bubble* (no MediaProjection, no screen capture,
  ever). The bubble draws; it does not inspect the app underneath. Reading the
  visible conversation is a separate, consented feature with its own switch and
  disclosure (docs/SCREEN_READING.md) that feeds this same bubble.
- Reply to a conversation the notification does not identify.
- Automatic sending of anything.
- Persisting message content to disk.
- iOS. Android only.
- A second AI client, a backend, analytics, or crash reporting.

---

## 3. Hard rules (violating one of these fails review)

1. **The bubble does not read the screen.** It is drawn with `WindowManager`
   and inspects nothing underneath. Screen reading is a separate service with
   its own switch, its own disclosure and its own rules
   (docs/SCREEN_READING.md); it shares this bubble's pipeline, never its
   permission to act.
2. **No message content on disk** — with one named exception. The pending
   message lives in process memory (`OverlayBubbleController`) and, while the
   panel is open, in the intent that launched it; it is cleared when the panel
   closes. The exception is the opt-in conversation memory in
   docs/CONVERSATION_MEMORY.md: off by default, capped, on this device only,
   never in a log, deleted when the user says so. A capture nothing asked to
   remember still follows this rule unchanged.
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
  └─ reads the context through the channel → renders message + the saved style +
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

- `OverlayBubbleController.hold(map)` keeps up to **five** conversations,
  keyed by notification key and ordered by arrival. A chat that posts twice
  updates its entry instead of stacking a duplicate; the oldest is dropped when
  the cap is reached. Collapsing them into one meant the badge said "3" while
  the panel could only answer the last message.
- `consume()` returns the newest map and removes it — exactly once.
- `peekAll()` is read-only and feeds the panel's chat switcher, so naming the
  other waiting chats never eats the one the bubble already shows.
- `size()` is what the bubble's badge displays.
- `onDestroy` of the service and process death clear everything implicitly.
- **Never** write any of it to SharedPreferences, a file, a database, or a log.

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

Hide the bubble when: the panel opens (it steps aside and **comes back** when
the panel closes - see below), 10 minutes pass, or the user picks *Dismiss*.

Tapping the bubble opens **only** the panel, never the main app, and neither
does tapping the empty space around it. The panel activity now builds **one**
route (`onGenerateInitialRoutes`), because Flutter's default behaviour stacked
`/` underneath `/overlay`: the transparent panel had the main app behind it, so
a tap on the empty space popped the panel and revealed ReplyMate over the chat.
Closing goes through the platform (`closeOverlayPanel` -> `finish()`), which
returns to the conversation the bubble was floating over. The only in-panel
navigation that leaves the bubble flow is the tune icon, which opens Settings
inside the panel on purpose. That is a
manifest guarantee, not a habit: `OverlayPanelActivity` carries its own
`taskAffinity`, so it never joins the app's task and dismissing it returns to
whatever was underneath. Without that, closing the panel dropped the user into
ReplyMate - which is exactly what "the bubble takes me into the app" felt like.

The bubble survives a panel session. `onPanelClosed()` restores the view and
re-holds the pending context (memory only) that the panel consumed, so the user
can reply, paste, generate again, or open the same message a second time
without waiting for the next notification. The 10-minute timer keeps running
while the panel is open: if the panel never reports back (process death), the
bubble still cleans itself up instead of lingering invisibly.

The panel is a centered floating glass card rather than a bottom sheet. Its
460 dp maximum width, 760 dp maximum height and safe-area margins keep it on
screen; content scrolls and keyboard insets move the whole card into the
remaining space. Backdrop blur is paired with a 90–95% opaque surface tint and
a subtle border so a busy chat cannot make the reply text unreadable. High
contrast uses a solid surface and reduced motion removes the entrance motion.
Outside taps still close the panel, and the sender/app header, Settings and
Close controls remain visible while the content scrolls.

### 5.4 Resting state, motion and the edge tab

The bubble is a 3D helper face (`design/bubble_mascot_bubble.png`, preview in
`design/bubble_preview.html`) on a glass-blue disc with a separate crisp rim,
soft highlight and elevation shadow. Motion uses ordinary view/window
animations plus matched artwork frames—no Lottie or animated-drawable pipeline:

- **idle**: an 1800 ms vertical bob and an irregular 150 ms closed-eye artwork
  swap every 3.5–6.5 s; the whole face is never squashed;
- **arrival**: one soft pop plus `VIRTUAL_KEY` haptic feedback, an animated
  count badge and a short happy face. Incomplete/redacted/group-summary context
  uses the alert frame instead. Neither mood exposes text;
- **drag**: idle motion stops, the bubble lifts/scales slightly and gives a
  clock-tick haptic; release settles with a damped spring;
- **tuck**: the actual window width and edge position animate between the 56 dp
  bubble and 22 dp tab. Android's animator setting disables bob, blink, spring,
  badge and entrance motion.

**Drawing order matters for the tab.** The mascot artwork is drawn before the
rim and the highlight, and the highlight is a separate clipped oval rather than
part of the bitmap: a centre-cropped face under a painted ring is what made the
edges look soft on low-density screens. Nothing here is content - no sender, no
text, no unread badge beyond a count.

A **long press** (450 ms, cancelled the moment the finger moves) opens a small
three-row icon menu beside the bubble: *Draft a reply*, *Hide at the edge*,
*Dismiss until the next message*. Rows are 48 dp high with quiet dividers,
18 dp card corners, entrance motion and selection haptics. Dragging and waiting for a notification both
hide the bubble, but neither is discoverable - the long press is the gesture
people try on anything round. The menu closes on a second tap, on any drag, on
a tap on one of its rows, or by itself after 6 seconds; a refused menu window is
swallowed so it can never take the bubble down with it.

Dragging the bubble within ~28 dp of a screen edge tucks it there as a 22 dp
tab with three dots instead of the face. A tap on the tab restores the bubble
and does **not** open the panel, so hiding it can never fire an action by
accident; a second tap opens the panel. A new message expands a tucked bubble
on its own, and a tab released away from both edges becomes a full bubble again
rather than a stray sliver in the middle of the screen.

When the source notification is removed the bubble **tucks itself against the
nearest screen edge** instead of disappearing - reasoned through in a 6-second
grace window first, so a post-then-withdraw notification cannot make it flicker
out from under a finger. Messaging apps retract the notification the moment the
user opens the conversation, which is exactly when a reply helper is wanted:
the bubble steps aside as a slim tab, keeps the message in memory, and comes
back on a tap. The auto-hide timer - ten minutes by default, the user's choice
per §5.5 - not the notification, is what eventually removes it. Some messaging apps post a notification
and retract it a moment later (WhatsApp does this for the chat you already have
open), and clearing on the first removal made the bubble flicker out of
existence before a finger could reach it. A tap inside the window is still
honest: the panel opens with the message and quick reply refuses, because the
action it would have used is gone.

### 5.5 The auto-hide timer is the user's, not ours

The bubble hides itself when nobody has used it for a while. That timeout used
to be a fixed ten minutes, which was wrong in both directions: too long for
someone who has already replied, too short for a long conversation. It is now a
setting - **5, 10, 30 minutes or never** - shown in Settings directly under the
bubble switch and only while that switch is on (a hide-timer for a bubble that
does not exist is a setting that cannot do anything).

- **Default: ten minutes**, the previous hard-coded value, so an existing user's
  bubble does not change behaviour on update.
- **"Never" is a real answer.** The service simply does not schedule the timer;
  the bubble still leaves on a withdrawal, a dismiss, or the switch going off.
- **The value is mirrored natively** (`bubble_auto_hide_minutes`, minutes, `0` =
  never) for the same reason as the switch itself: the service has to answer
  this with no Flutter engine alive.
- **An unrecognised value falls back to ten minutes, never to "never"** - the
  quieter of the two honest readings. A hand-edited preference cannot park a
  bubble on the screen forever.
- A live bubble picks the new value up on its next schedule, so changing the
  setting does not need a restart.

The timer is a tidy-up, not a data decision: the pending context is already
gone from memory when it fires, exactly as before.

### What notifications cannot do: the chat you are already looking at

The bubble was originally driven by **notifications** only. When the user is
inside a chat, the messaging app normally posts no notification for that
conversation at all, so there is nothing for any notification listener to read -
the bubble stayed away at exactly the moment it would have been most useful.

That gap is now closed by the screen reader, a separate service with its own
switch and disclosure (docs/SCREEN_READING.md). This section still applies to
notifications themselves, and one thing has not changed: **the bubble never
reads anything**. It is drawn, it is tapped, and the text it shows was given to
it by one of the two message sources, both of which the user switched on.

The in-app alternatives that do work in that situation: select the message text
and use the *ReplyMate AI* entry in the selection menu (route 2 in
`docs/PLATFORM_CHANNELS.md`), share the message to ReplyMate, or paste it into
the composer.

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
- **Bubble vanishes after a while** — the auto-hide timer, 10 minutes unless
  the user changed it (Settings → *Hide the bubble after* → 5 / 10 / 30 min or
  *Never*); by design.
- **Quick reply button missing** — the notification has no `RemoteInput`
  action. Copy instead.
- **Battery saver kills it** — expected on some OEMs. The fallback
  notification is the reliable path.
