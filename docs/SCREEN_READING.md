# Screen reading — the chat you are already looking at

**Status:** implemented in code, **not** verified on a device. Rows 25–31 of
`docs/PHASE1_DEVICE_TESTS.md` are `_pending_`. Treat this feature as
code-complete and unproven until those rows are filled in on a real phone.

---

## 1. The problem it solves

A messaging app posts no notification for the conversation the user is currently
looking at. That is Android behaving correctly, and it leaves the notification
listener with nothing to read at exactly the moment a reply is most likely to be
wanted: someone asks something, the user is staring at it, and ReplyMate says
nothing because no notification arrived.

The workarounds that already exist all need a deliberate action from the user —
long-press the message and use the *ReplyMate AI* item in the selection menu,
share the message to ReplyMate, or paste it into the composer. They work, and
they are still the right answer for anyone who does not want to grant
accessibility access. They are also three taps when zero would do.

Screen reading closes that gap: while a chat from an allowed app is on screen,
ReplyMate can draft a reply to it.

---

## 2. What it is, precisely

`android/app/src/main/kotlin/.../ReplyMateScreenReaderService.kt` is an
`AccessibilityService` that receives window-content events, reads the visible
conversation, and — when it finds a message the user has not answered — hands it
to the **same pipeline a notification would have used**: the bubble or the
fallback notification (`OverlayRouter`), and the in-app capture list.

It is a *reader*. That single word is the whole design.

| It does | It never does |
|---|---|
| Read text that is already on the user's screen | Type into another app |
| Report the newest incoming message | Click, tap or perform a gesture |
| Raise the same bubble a notification would raise | Send a message — not even a "helpful" one |
| Hold one line of text per app, in memory, to avoid re-reading an unchanged screen | Write that text to disk, prefs, a database or a log |

---

## 3. The rules, and why each one is there

1. **Off by default.** This is the only feature here that can see text the
   platform never hands us. It is not on until the user turns it on.

2. **Allowlist-bound.** Only packages the user selected on the app-selection
   screen are read (`AppAllowlist`) — the same list the notification listener
   obeys. Screen reading is not a way to widen that list by accident.

3. **Consent, stated in words, before the switch moves.** Turning the switch on
   shows a disclosure explaining what is read, what is sent, and that nothing is
   kept, and waits for a real confirmation. Turning it off asks nothing;
   stopping is never something the app argues with.

4. **Two independent grants.** Android grants accessibility access in its own
   Settings screen, and the in-app switch decides whether ReplyMate uses it.
   Either one off means nothing is read. The switch is inert — visibly, not
   silently — until Android has granted access.

5. **Nothing is stored.** The last message text per package sits in a `HashMap`
   in the service's process heap, purely to stop an unchanged screen being
   re-read on every repaint. It dies with the process
   (`docs/PRIVACY_AND_PERMISSIONS.md`).

6. **No message text in logs.** Not `Log.d`, not `debugPrint`, not analytics.
   The same rule that already applies everywhere else.

7. **What the user is typing is excluded.** The input box is filtered out by
   resource id *before* any text is collected, and a test proves it
   (`neverCapturesWhatTheUserIsTyping` in `ScreenTextReaderTest.kt`). Sending
   someone's half-written draft to an AI is the one mistake this feature must
   never make.

8. **`hasReplyAction` is always `false` for a screen reading.** A screen gives
   us no `RemoteInput` to reply through. Inventing one would mean typing into
   someone else's app, so the UI offers copy and share instead — which is the
   honest answer, not a missing feature.

---

## 4. How the reading works

`ScreenTextReader` is a pure function of a node tree — no Android imports — so
its heuristics are proven on a plain JVM (`ScreenTextReaderTest.kt`, 8 tests).
`AndroidScreenNode` is the only file that touches `AccessibilityNodeInfo`.

1. Events arrive for `TYPE_WINDOW_CONTENT_CHANGED` and
   `TYPE_WINDOW_STATE_CHANGED`, throttled to one scan per 1.2 s (a chat repaints
   for the clock, for a typing dot, for a one-pixel scroll).
2. The active window must belong to the package the event came from — a toast, a
   keyboard or a system dialog is not "the app the user allowed".
3. The message list is the scrolling container with the most children.
4. Rows are read newest-first, up to six, skipping the app's own chrome: date
   headers, timestamps, `typing…` and "last seen".
5. The first row that holds a message decides: incoming if it sits on the left
   half of the screen, outgoing if the right. **A newest message that is
   outgoing means the user already answered**, so nothing is drafted.

   **Both of those are measured on the node that holds the text, never on the
   row that contains it.** A message row is as wide as the list in every app
   this reader targets - the bubble inside it is not - so a width test on the
   row rejects the whole conversation and a centre test on the row calls every
   message outgoing. A bubble wider than 92 % of the screen is still rejected
   as chrome (a menu, an input bar, an encryption notice). Getting this wrong
   is not a small error: it reads, from the outside, exactly like a feature
   that was never switched on.
6. The longest readable string in that row is taken as the message — a bubble
   also holds its timestamp, and a group bubble holds the sender's name.
7. Text longer than 2000 characters is cut and flagged `isTruncated`.
8. `ScreenReadingGate` then decides whether that text is **new**: anything seen
   before, for that package, is dropped - and everything seen while the user is
   scrolling is remembered but never emitted.

**These are heuristics, and the code says so.** Messaging apps give message
bubbles no stable resource id, so this reads shape. When the shape cannot be
trusted — no rectangle, no text, no list — the reader returns `null` rather than
guessing. A message we cannot attribute is a message we do not invent.

### Known limitations, stated rather than hidden

- **A message you scrolled back to will not raise a bubble.** The gate
  remembers the texts a scroll passed, which is what stops an old message
  looking like an arrival; the price is that scrolling back down to one does
  not re-offer it either. Calm was chosen over completeness on purpose - a
  bubble that fires every time you scroll is a bubble you switch off.
- **A messaging app update can break it.** There is no contract for bubble
  layout. When the shape changes, the reader stops finding messages; it fails
  by saying nothing, never by inventing text.
- **Right-to-left layouts** are not distinguished from left-to-right ones yet;
  incoming/outgoing is decided by which half of the screen a bubble sits on.
- **Group chats**: the message body is the longest string in the bubble, which
  is usually right and occasionally the sender's name.
- **Very old Android versions** and OEM skins that trim accessibility events may
  simply deliver nothing.
- **Advanced Protection Mode (Android 16+)**: the system refuses to grant
  accessibility access to an app it does not classify as an accessibility tool,
  and revokes it from one already granted. ReplyMate is not assistive technology
  in the usual sense, but `isAccessibilityTool="true"` **is** declared in
  `screen_reader_service_config.xml`, at the owner's instruction: this is a
  personal, sideloaded build with one user, and the alternative is a feature
  that is dead on such a device for no benefit to anybody. The flag changes
  nothing about what the service does — it still reads only allowlisted apps,
  only while the in-app switch is on, and never types, clicks or sends.
## 3b. Finding out why it read nothing

"Screen reading does not work" is five different failures, and from outside the
phone they look identical. Every scan now records which one it was, and
**Settings → Screen reading → "What the reader is doing"** shows it:

| Report | What it means |
|---|---|
| `no_window` | Nothing was in front to read — no active window at all. |
| `other_app` | The window in front belonged to a different package (a keyboard, a toast, a system dialog). |
| `no_list` | No scrolling container on that screen — not a conversation, or the tree was empty. |
| `no_rows` | The list was found but none of its rows looked readable. |
| `no_message` | Rows were readable, but none held a message (timestamps, typing dots, date headers). |
| `outgoing` | The newest message is one the user sent, so there is nothing to answer. |
| `not_new` | Already seen, or the user scrolled past it — the gate is doing its job. |
| `read` | A message was read and handed to the pipeline. |

The card also shows whether the service is running, whether the switch is on,
which packages are being watched, and how many scans have happened since
install. `screenReadingStatus` on the channel is the same report.

**The way to the fix is one tap.** The card's "Open Android settings" button
opens ReplyMate's *own* accessibility page directly
(`ACTION_ACCESSIBILITY_DETAILS_SETTINGS`, Android 12+) instead of the generic
list, which on several OEM skins sits two levels down behind "downloaded
services". It falls back to the list where the deep link is missing, and says
when the device has no such screen at all.

The button is offered whenever the reader is not working - not only when the
grant is absent. The grant and the running service are different things, and
the toggle has to be cycled off and on again after a config change, which is
something you do while the grant is still in place.

The report is kept in preferences rather than in memory because the process that
reads the screen is not the one showing Settings: Android kills and restarts it
freely, and a report that dies with it is a report nobody reads.

**`typeViewScrolled` is requested on purpose.** Scrolling is the event that
teaches the gate what the user has already seen; without it, stopping on an old
message while scrolling back through a chat looks exactly like a new arrival.

- **Distribution.** This build is sideloaded. If that ever changes, Google Play's
  accessibility policy has to be settled *first* — non-accessibility use of the
  API needs a declaration and an approval, and an undeclared one is a removal.
  Nothing about the code changes; the gate is the store's.

---

## 5. What it shares with notifications

| | Notification | Screen reading |
|---|---|---|
| Event | `notification_captured` | `screen_captured` |
| Payload | the `notification_captured` wire format | the same, plus `fromScreen: true` |
| Allowed packages | the user's allowlist | the same allowlist |
| Bubble / fallback decision | `OverlayRouter` | the same `OverlayRouter` |
| Quick reply | only with a live `RemoteInput` | never — `hasReplyAction: false` |
| Stored on disk | never\* | never\* |

\* Unless the user switched on conversation memory (docs/CONVERSATION_MEMORY.md),
which is off by default, capped, on this device only, and deleted when turned
off. Without it, both sources are thrown away when the panel closes.

`CapturedNotification.isScreenRead` carries the difference to the UI, so a
screen-read message can say where it came from. That is not a warning — it is a
fact the app owes the user, because "where did this come from" is exactly the
question a privacy-first assistant has to answer before it is asked.

---

## 6. Files

| File | Job |
|---|---|
| `ScreenTextReader.kt` | The heuristics. Pure, no Android, JVM-tested. |
| `AndroidScreenNode.kt` | The only adapter to `AccessibilityNodeInfo`. |
| `ReplyMateScreenReaderService.kt` | The service: throttle, allowlist, dedupe, hand-off. |
| `ScreenReadingGate.kt` | "Is this text new?" - keeps a scroll from looking like an arrival. Pure, JVM-tested. |
| `AppAllowlist.kt` | The user's app selection, read the same way by both sources. |
| `OverlayRouter.kt` | Bubble-or-fallback, one decision for both sources. |
| `screen_reading_provider.dart` | The switch and the availability read. |
| `res/xml/screen_reader_service_config.xml` | The service declaration Android shows. |
