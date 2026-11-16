# Changelog

All notable project changes are recorded here.

## [Unreleased]

### Write another, without retyping the brief

- One draft per prompt made "none of these" the common case, and the only way
  out was to write the brief again. Every draft now has **Write another**, which
  re-runs the same request with `bypassCache: true` - the cached answer *is* the
  draft already on screen, so serving it again would look like the button did
  nothing.
- It replaces the draft in place rather than adding a turn, so asking three
  times does not turn the conversation into a pile.
- The request is the one that produced the visible draft, not the current chips:
  re-styling the toolbar afterwards must not change what "another" means.

### A failed draft can be retried

- A generation failure used to be a dead end: the brief was still on screen,
  the style was still chosen, and there was nothing to press. Each failed turn
  now offers **Try again**, which re-runs the *same* request - no retyping, and
  no quietly dropping the style or format the user picked.
- Send, retry and (soon) regenerate share one code path, so the retry cannot
  drift away from what a first send does.
- A turn that recovers stops showing the error it recovered from.

### A quieter chat screen: one reply per prompt, one toolbar

- **One reply per prompt.** Two drafts for the same brief made the screen look
  undecided and doubled the reading before a choice. The writer is a
  conversation, so it writes one message; the reply panel still offers several,
  because there choosing *is* the feature.
- **The chips are gone from the screen.** Four format chips, nine tone chips and
  a style row took ~180 logical pixels above the text box. They are now two
  compact pills on one toolbar line — `Chat message` and
  `English · Friendly · Short` — each opening a sheet with the choices. Nothing
  was removed, only moved.
- **The style is stated once.** `Bengali · Premika · Medium` used to repeat under
  every draft; it now appears only when the draft came back in a different style
  than asked (`Written in English, not what the style asks for`), which is
  exactly when the difference would otherwise look like a bug.
- **Format menu is new**, and its title is `Write as` rather than the first
  format's name. Three new strings in English, Bengali and Hindi.
- The style list in the welcome panel is gone — it is on the toolbar pill now.

### The chat answers in the style you choose — fixed

- The writer chat used to ignore the style it was showing. Language, tone and
  length were read from Settings on **every send**, so whatever the user picked
  was overwritten one line later: choosing "Premika" still produced a Friendly
  English line, because that was the stored default.
- The style now belongs to the **chat**, the way it does in a chat app: it is
  seeded from Settings when the chat opens, then follows the user's choice for
  the rest of the conversation.
- A style pill above the input states the current style in full (for example
  `বাংলা · Premika · Medium`) and opens a sheet with the three groups —
  Language, Tone, Length — instead of nine chips inline, which ran to 1600
  logical pixels and pushed the chips off a phone screen.
- Each draft is labelled with the style it was **actually** written in. The pill
  says what will be asked for; the label says what came back, and they can
  differ because an explicit request inside the brief wins.
- The style is saved with the chat, so a reopened Bengali/polite chat continues
  Bengali/polite instead of quietly reverting to the app default.
- Drafts are drawn as message bubbles (mirrored tail), not bordered cards, so
  the screen reads as a chat rather than a form.

### Create a message writes letters, emails and applications too

- The chat screen has four formats, one tap apart: **Chat message**, **Email**,
  **Letter**, **Application**. The format is part of the request
  (`WritingFormat`), not a phrase in the brief, so it changes the prompt
  contract, the token budget and the cache key:
  - *Email* → `Subject:` line, greeting, short body, sign-off.
  - *Letter* → date line, salutation, body, closing.
  - *Application* → recipient block, `Subject:`, salutation, purpose/facts/
    request/closing, and **bracketed placeholders** where the user gave no
    fact (dates, roll number, address) instead of invented ones.
- Quick ideas follow the format: choosing Email offers "Email to a teacher" and
  "Email to a landlord", Application offers "Leave application" and "Job
  application", instead of romantic lines.
- Token budget grows for documents (500 + 450 per draft, capped, count clamped
  to 3). A truncated letter is worse than no letter: the parser salvages
  nothing from cut-off JSON, so the user would have seen "empty suggestion
  list" instead of most of a letter.
- The format is also part of the reply-cache key and of saved writer history, so
  a reopened letter regenerates as a letter and a letter is never served as a
  chat reply.

## [1.5.6] - 2026-11-16

### "Not quite right" has a free answer

- The suggestions screen offers **Free variation** when the offer is honest:
  the rules layer re-phrases the same intent on the device, with lines already
  on screen excluded, for no tokens, no key and no network. It is labelled as
  a free on-device rewrite and raises a banner whose **Ask AI** button is the
  paid escalation, so nobody is trapped in the free path.
- Deliberately *not* the first step of the cache banner's **Regenerate**: that
  button means "ask the model", and answering it with local text would be the
  small lie this screen exists to avoid.
- Intent chips and standalone writing briefs never get the offer — a generic
  table line cannot answer "write a romantic quote".
- Fixed a crash found while testing this: regenerate disposed the screen's
  `TextEditingController`s and then wrote to them, so a successful regeneration
  threw "A TextEditingController was used after being disposed".

## [1.5.5] - 2026-11-16

### Pooled AI works for a device that has never signed in

- The bootstrap signs the device in **anonymously** at launch. `firestore.rules` allows
  the key pool to be read by any *signed-in* user, and the only sign-in in the app was the
  admin gate's Google flow — so on a fresh install with Firebase configured, the pool read
  came back `permission-denied`, `getNextKey()` was null, and every AI request failed with
  "no healthy API key". It worked on the owner's phone because that device had signed in
  as admin and cached the pool.
- Bounded (8 s) and best-effort: a disabled Anonymous provider or an offline launch logs
  and continues, and the pool reports its own honest failure.
- Admin gate: a Google sign-in over the anonymous session is **linked**, keeping the uid
  the pool keyed its cooldowns on, and falls back to a plain sign-in when the Google
  account is already in use.

### One bad key is no longer the user's whole answer

- `KeyPoolReplyRepository` now tries up to three keys per request. A provider that answers
  200 with an unusable body is reported to the pool (previously not reported at all, so the
  key was handed out again on the next tap, forever) and the next key is tried.
- Bounded twice: three attempts, and no key twice in one call — which is also what keeps a
  one-key pool from looping on itself. An auth failure (401/403) still stops immediately
  instead of burning the rest of the pool.

### The reply cache can no longer say what the message was

- Cache keys were `base64Url(message + options)` — an encoding of the text, not
  a hash, sitting in a Hive file on disk. The doc comment claimed a hash and
  `AGENTS.md` says conversation memory is the only feature allowed to write
  message text to disk, so this was both a leak and a lie: anyone with the file
  could read every message the cache had seen.
- Keys are now SHA-256 hex (`package:crypto`). The box moved to
  `reply_cache_v2` and the v1 box is deleted on first open rather than
  migrated, because a hash cannot be computed from the old key without reading
  the text we are trying to stop storing. Losing a cache costs one provider
  call.
- `isTimeSensitive` matched `am `/`pm ` as substrings, so "I am fine", "team
  lunch?" and "grammar check" bypassed the cache entirely. Clock times are now
  matched as clock times (`at 5 pm`, `9am`).

### A healthy key in the admin panel is a working key in the app

- `OpenAiCompatibleClient` now speaks each provider's dialect, matching the
  admin panel's own health check: a `google` key is called at
  `models/<model>:generateContent` with the key in the query string and
  constrained JSON output, and an OpenRouter key gets its bare model name
  prefixed (`gpt-4o-mini` -> `openai/gpt-4o-mini` via the package's
  `resolveOpenRouterModel`).
- Before this, both cases passed the health check and failed every real call:
  a 404 at `/v1beta/chat/completions`, or a 400 for a bare OpenRouter model.
  That is the shape of "the admin screen says the key is fine but the app says
  the provider is unavailable".
- Status classification is one helper (`_throwForStatus`), so 401/403, 429 and
  5xx mean the same thing on both paths.

### The bubble tucks itself away

- A full-size bubble nobody has touched for five seconds now slides to the
  nearest edge on its own, as the slim tab the drag gesture used to be the only
  way to reach. Tapping the tab brings it back as before.
- The countdown restarts on every sign of interest (a new message, a tap, a
  drag, the long-press menu, closing the reply panel) and is suspended on
  `ACTION_DOWN`, so the bubble never changes shape under a finger. Nothing is
  scheduled while the menu or the panel is open.
- Auto-hide (5/10/30 min or never) is unchanged and still removes the bubble
  entirely; the tuck is the earlier, gentler step before it.

### The admin key pool is the only AI path

- Removed Settings → **Your own AI key** (BYOK). The card, its Hive box, the
  own-key repository and its tests are gone; `main.dart` always builds
  `KeyPoolReplyRepository` when Firebase is ready, so every AI call is served
  by an admin key and rotates through the pool's failover and cooldowns.
- Settings → **AI replies** now holds only usage and per-chat styles. The
  `ownKeySection` string became `aiSection` in all three languages.
- Consequence, stated plainly: a build with no reachable key pool has no AI.
  Offline suggestions still work, and the failure copy already says why.
- Nothing secret was ever on the device through this path, so there is no
  cleanup step for existing installs beyond the removed Hive box.

### AI generation has no app-enforced daily cap

- Removed the per-device 50-request hard stop. An informational local count
  remains in AI settings, but only the configured provider's own billing and
  rate limits can restrict usage.

### The admin screen stops blaming the network

- Bumped `admin_api_key_manager` to `594dc3c`, which classifies a failed
  key-pool read instead of printing raw Firestore text. `permission-denied`
  (this account is not on the allowlist) is now a different screen from
  `unavailable` (no connection), because they have different fixes and the old
  copy sent both to "check your connection".
- A build with no Firebase says so and points at the setting that works
  without it: your own AI key. `test/admin_key_pool_errors_test.dart` asserts
  the pin brings the behaviour, so a rollback that loses it fails a test rather
  than a device.

## [1.5.0] - 2026-11-14

### Your own AI key (BYOK)

- Settings → **Your own AI key**: paste a key from OpenRouter, Google AI Studio
  or any OpenAI-compatible endpoint. It is stored in its own Hive box on this
  phone — never in Firestore, never in a backup (`android:allowBackup` is
  false), never logged. The card says so where the user is typing, not in a
  README.
- This is the security answer that fits an app with no billing: a key in the
  user's own storage cannot leak out of a shared pool, has no Firestore rules to
  get wrong, and burns nobody else's quota. It also removes the last Firebase
  dependency from the reply path — with a key set, a build with no
  `google-services.json` generates replies.
- The saved key is never rendered back ("set" is the whole state shown), the
  field is obscured, and "Saved" appears only after the write succeeded.
- `OwnKeyReplyRepository` talks to both wire formats (OpenAI-compatible and
  Gemini `generateContent`), sharing the prompt builder and reply parser with
  the key-pool path rather than duplicating them.

### Costs less to run, and says so

- **Reply cache.** An identical request (same message, language, tone, length,
  count and prior context) is served from an on-device Hive box instead of a
  paid call. A hit is labelled **"From cache · N ago · no AI call was made"**
  with a real *Regenerate* that bypasses it — a cache without an exit is a trap,
  not a saving. Messages carrying a time reference (today/kal/আজ/12:30 …) are
  never cached, because a stale answer there is wrong rather than merely old.
- **Daily AI allowance.** 50 paid generations per device per day, shown in
  Settings as "N of 50 used today". This is the guard `ApiKeyManager` never
  had: it protects against dead keys, not against spending. It counts requests,
  not tokens, is per device, and fails open — a broken counter must never be
  the reason the app stops working.
- **Cheaper requests.** `max_tokens` capped at 300 (providers otherwise bill
  the model default), and the style-examples block is dropped from the prompt
  when the request carries none — it was the largest input block in the prompt.
- `ReplyRepository.generate` grew `bypassCache`; `ReplySuccess` carries
  `fromCache`/`cachedAt` so no screen can present a cached reply as fresh.
- **Offline suggestions.** When a paid call fails — no key, no network, no
  Firebase, allowance spent — the app now offers rule-based candidates written
  on the device (question, thanks, apology, greeting, farewell, acknowledgement,
  plan, plus a tone line), in all three reply languages. They are labelled
  "Offline suggestions … no AI call was made", never dressed as model output,
  and an unrecognised message returns *nothing* rather than a confident wrong
  reply.

### Setup path speaks Bengali and Hindi

- Onboarding, the permission screen, app selection and the screen-reading
  status card now read every string from `AppStrings`; 55 new strings were
  added in all three languages. This was the last place a Bengali session still
  showed English.
- `setup_path_localization_test.dart` renders those screens in Bengali and
  Hindi and asserts the English originals are gone, plus that no new string is
  left equal to its English text (the failure mode when a getter is added to
  the interface and the translation is forgotten).
- The admin gate stays English on purpose: an allowlisted operator screen whose
  copy is an exact Firestore instruction, not prose for end users.

### Floating bubble and glass panel polish

- Replaced the bottom-aligned overlay sheet with a centered, keyboard-safe
  glass card: controlled blur, high-opacity tint, subtle border, soft shadow,
  fixed sender/app header and scrolling controls/suggestions.
- Added native bubble rim/highlight, matched blink/happy/alert artwork,
  animated count badge, tactile drag feedback, spring-like edge settling and
  reduced-motion fallbacks. The bubble still exposes no sender/message text or
  generation state.
- Refined the long-press menu with rounded line icons, 48 dp rows, dividers,
  entrance motion and selection haptics; updated the self-contained design
  reference to match the shipped interaction model.

### Visual identity, motion and accessibility refinement

- Bundled Inter, Noto Sans Bengali and Noto Sans Devanagari with their OFL
  licences, so English, Bengali and Hindi render consistently offline.
- Added a shared rounded `AppIcons` vocabulary and custom `BrandIcon` line art
  for reply, notification, language, privacy, screen reading and memory.
- Added matched blink, happy and alert mascot artwork. Blinking now crossfades
  to closed eyes instead of squashing the whole robot.
- Compacted onboarding and Home without shrinking copy; added icon-aware reply
  controls, a finite generation skeleton and wrap-safe 48 dp suggestion
  actions.
- Added light/dark mascot launch screens and an Android 13 monochrome themed
  launcher icon; padded chip and header touch targets and strengthened dark
  card separation.

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
- Not done: rows 17–24 of the Phase 1 device checklist are still `_pending_` —
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
- The screen-reading spec, including the honest limitation that Android
  16+ Advanced Protection refuses accessibility access to an app it does not
  classify as an accessibility tool, which ReplyMate is not and does not claim
  to be.

Not done: rows 25-34 of the Phase 1 device checklist are still `_pending_` -
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
or a second AI client in Kotlin, which the overlay batch plan forbids.
The privacy and permissions notes now state the rule the way the code
actually behaves.

### Implemented in the repository
- Flutter onboarding, home, permissions, app selection, settings and reply-suggestion flows, including a selectable 1–3 suggestion count, copy/edit/share actions and composer-session cleanup of transient message context.
- Kotlin notification listener, parser and Flutter platform-channel integration, including conditional RemoteInput quick reply and user-initiated share/text-selection entry points.
- Firebase admin gate and Firestore-backed API-key pool with direct provider API integration for reply generation.
- Bengali, Hindi and English output-language choices, tone/length controls, request validation and user-visible failure handling.

### Owner-reported verification — 2026-11-06
- Keshab reports that admin, API access and reply generation work on a real device. Device model, OS/app build and detailed test steps were not recorded; this is a smoke-test report, not full Phase 1 sign-off.

### Added
- The floating-overlay spec — full implementation spec for the floating reply
  bubble (bubble, panel, fallback notification, permissions, failure table,
  privacy and Play rules)
- The overlay batch plan — the same work broken into five batches for an
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
- Complete and record the Phase 1 real-device checklist.
- Decide/implement server-side provider-key handling and rate limiting; the current client-readable key-pool trade-off is documented in the README and in the `admin_api_key_manager` package README.
- Complete privacy/security, performance and Play policy review, then closed testing.

## [0.1.0] - Not released

### Added
- Initial project documentation
- Product requirements
- Architecture and implementation plan

### Notes
This project is in its planning and early development stage. No production-ready features are claimed yet.
