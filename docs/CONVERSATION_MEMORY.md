# Conversation Memory — per-contact context and the user's own voice

Spec for the one feature that stores message text on the device. Read this
before touching `lib/features/memory/**`, the prompt builder, or anything that
claims "no message content on disk" — this document is the exception those
claims now point at.

---

## 1. The problem this solves

Today a reply is drafted from a single line. `CapturedNotification` carries the
last message plus whatever history the notification happened to include, and
most apps include none. So the model answers the newest sentence with no idea
what the conversation is about — and it always writes in the same neutral
register, because nothing tells it how *this* user actually talks.

Two asks, one feature:

1. **Continuity.** "What is this conversation about?" — a bounded window of what
   was said just before, per contact.
2. **Voice.** "Say it the way I would say it." — the user's own recent replies,
   offered to the model as examples, not as a profile it has to invent.

## 2. Why it needs a rule change

`docs/FLOATING_OVERLAY.md` rule 2, `docs/OVERLAY_TASKS.md`, the
`SCREEN_READING.md` table and device rows 24 and 34 all say the same thing:
*no message content on disk, ever.* That rule was written when every capture
was transient, and it is still the right rule for every capture that is not
part of this feature.

It is amended, not deleted:

> **No message content on disk — except the conversation memory the user
> switched on.** That memory is capped, allowlist-bound, deletable, never
> leaves the device (not to a server, not to a cloud backup), and never
> appears in a log.

Everything else keeps the old rule exactly as it was. The amendment is narrow
on purpose: a capture that nothing asked to remember is still thrown away.

## 3. The four walls (violating one fails review)

1. **Off by default.** A master switch in Settings, `off` until the user turns
   it on, with wording that says what is stored and where. Turning it off
   deletes everything it stored — not "stops adding".
2. **Allowlist-bound.** Memory is written only for packages already on the
   user's app allowlist, the same list the notification listener and the screen
   reader obey. Memory is never a way to widen that list.
3. **On the device, only.** Written to app-private storage, read by the app.
   No upload, no sync, no analytics, no log line. `android:allowBackup` stays
   **false** so Android Auto Backup cannot carry these files to Google's
   servers — a promise about "the device" that a cloud backup quietly breaks is
   worse than no promise.
4. **Capped and deletable.** Hard limits below, per-contact delete, and one
   "clear all memory" action. Deleting is immediate and total.

## 4. Limits (`MemoryPolicy`)

| Limit | Value | Why |
|---|---|---|
| Lines kept per contact | 40 | Enough for a conversation's shape, small enough to be a window and not a record |
| Contacts kept | 50 | The store stays a working set, not an archive |
| Line age | 7 days | "What were we saying" decays; a month-old line misleads |
| Characters per line | 500 | One pasted essay must not become the whole budget |
| Style examples offered | 3 | Few-shot examples earn their tokens up to about three, then crowd out the actual request |

Writing beyond a limit evicts the oldest line, never the newest: a full store
must still answer today's message. A store that cannot add without dropping
something newer is a store that has stopped being useful.

## 5. What is stored

Per contact, a list of `MemoryLine`s: the text, who said it (`them` / `me`),
and when. Plus the key the lines hang off — the package name and the sender
name as the app displayed it.

That key is honest about its own weakness: **a notification sender name is a
display name, not a contact identity.** A rename starts a new memory. A group
chat shows the group's name, so its lines mix speakers, and a contact whose
name is the same as a group's will collide. We do not try to fix that with
fingerprinting — we keep the record small, per-contact deletion one tap away,
and the spec says so instead of pretending the key is exact.

## 6. What is *not* stored

- Nothing from an app that is not on the allowlist.
- Nothing while the master switch is off, including the message being answered.
- No attachments, no images, no phone numbers, no timestamps beyond the line's
  own ordering time.
- **No inferred "personality profile".** The voice half of this feature is
  few-shot examples taken verbatim from what the user actually typed. A stored
  summary of "this user is casual and uses two emojis" is a fact the model would
  then repeat, and a summary the user cannot check. Examples can be read and
  deleted; a profile cannot.

## 7. How it reaches the model

Nothing new on the wire. `ReplyRequest.priorMessages` already exists and
`ReplyPrompt` already renders it — the memory window is simply the source that
fills it when memory is on:

- `ConversationMemory.contextLines()` → `priorMessages`, oldest first, tagged so
  the model can tell who spoke (`them: …` / `me: …`).
- `ConversationMemory.styleExamples()` → at most three of *the user's own* lines,
  presented in the system prompt as "this is how the user writes", never as
  content to reply to.

Both are prompt text and leave the device as part of the request, exactly like
the message being answered — which `docs/PRIVACY_AND_PERMISSIONS.md` already
says out loud (with cloud AI enabled, the text does leave). Memory does not
change that story; it makes the request longer.

## 8. Where the user's own words come from

Only two sources can contain them:

- **Screen reading** — the visible bubbles include sent messages, and
  `ScreenTextReader` already distinguishes an arrival from a message the user
  sent (`isSentByUser`). This is the real source, and it is opt-in twice over:
  screen reading off means no voice examples at all.
- **What this app composed** — a draft the user accepted through quick reply.
  The app knows the text because it wrote it.

Notification capture alone can never learn a voice: it only ever sees arrivals.
The UI must not imply otherwise — with screen reading off, memory is context
only, and the Settings copy says so.

## 9. Failure modes that must stay honest

- **Store unavailable / read error** → memory is empty, the reply still gets
  drafted from the message alone. Memory is never allowed to break generation.
- **Memory off, or empty, or expired** → the panel does not claim continuity it
  does not have.
- **Redacted / truncated capture** → stored as captured, with the same honesty
  markers the UI already uses. Never repaired by guessing.
- **Group chats** → stored under the group name, and the spec's weakness in §5
  applies rather than being papered over.

## 10. Device verification

Memory cannot be proven by CI. `docs/PHASE1_DEVICE_TESTS.md` gains rows for:
switch off ⇒ nothing written (`run-as … ls -R files/`), switch on ⇒ lines
appear, keep-talking past the cap ⇒ oldest goes and newest stays, delete one
contact ⇒ that contact only, turn the switch off ⇒ the directory is gone, and
`adb backup`/`bmgr` cannot extract the store.
