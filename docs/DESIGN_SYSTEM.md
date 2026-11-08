# Design system — mascot-first

The reference render for this pass is `design/app_redesign_preview.html` (open it
in a browser; it is self-contained). The bubble's own reference is
`design/bubble_preview.html`.

## 1. The character

One 3D face (`design/bubble_mascot_bubble.png`) is the app's whole personality.
It is not decoration bolted onto a UI; it is the thing the user recognises, so
it appears in exactly four places and nowhere else:

| Where | Size | Why |
| --- | --- | --- |
| Floating bubble (`OverlayBubbleService`) | 56 dp | the product's front door |
| Home hero (`MascotFace`) | 96 dp | "your helper" — the first thing on screen |
| Settings header | 34 dp | continuity, not a second hero |
| Thinking / result states | 40–56 dp | same face, different mood |

`MascotMood` (`lib/shared/widgets/mascot_face.dart`) is how the face reacts:
`idle`, `listening`, `thinking`, `happy`, `alert`. A mood changes the tilt and
the light behind it — never the artwork, so there is no frame budget and no
second asset to keep in sync.

`thinking` additionally shows three breathing dots under the face: the app's
only "the helper is working" cue, and deliberately wordless — it says
*something is happening* without guessing how long it will take. It is used in
two places: the composer header switches `listening` -> `thinking` while a
request is in flight, and the bubble panel's avatar does the same, then turns
`happy` when replies arrive.

The **bubble itself** has no thinking state on purpose: the bubble steps aside
while the panel is open, and the panel is the only place a request can be
started. A spinner on the bubble would be a spinner for something that cannot
be happening.

## 2. Motion rules

- **Finite in the app, continuous in the bubble.** The bubble is what the user
  watches over another app, so it bobs and blinks indefinitely there. Inside
  the app the bob runs 12 round trips and rests: an infinite ticker never lets
  `pumpAndSettle` settle in widget tests, and a face that is still after it has
  said hello is fine.
- No `Timer`-driven animation: blinks are driven by the bob controller, so a
  disposed screen leaves nothing pending.
- Every animation respects the platform's "remove animations" setting through
  Flutter's normal implicit-animation behaviour; nothing animates a value the
  user is trying to read.

## 3. Colour

| Token | Value | Use |
| --- | --- | --- |
| `AppTheme.brand` | `#1B6EF3` | primary, the blue the artwork is drawn on |
| `AppTheme.brandBright` | `#4A94FF` | links, icons on dark, gradient middle |
| `AppTheme.cyan` | `#38D9F8` | gradient end, accent glow |
| `AppTheme.mint` | `#43E0A0` | healthy state |
| `AppTheme.amber` | `#FFB545` | needs the user |
| `AppTheme.danger` | `#FF5D6C` | wrong / blocked |
| `AppTheme.ink` / `inkSurface` / `inkElevated` | `#070B14` / `#0C1220` / `#131B2C` | dark surfaces |

State is never colour alone: the dot always has a word next to it (`live` /
`off`), so the palette is not the only signal.

## 4. Shape and space

- Cards `18 dp`, tiles `16 dp`, buttons `16 dp`, pills `9 dp`. Pills are for
  values the app already decided (language, tone, length), never for questions.
- Spacing scale is the same one the code already had: 4 / 8 / 16 / 24 / 32.
- One gradient (`AppTheme.primaryGradient`) for the primary action and nothing
  else, so "the gradient" always means "press this".

## 5. Screen rules

1. **One big action per screen.** Home has Generate a reply; Suggestions has
   Send. Everything else is a tile or a text button.
2. **Blockers first, decoration never.** A missing permission is a full card at
   the top of Home, and it disappears the moment it is granted.
3. **The app states what it will not do.** The settings screen carries the two
   privacy promises (nothing stored, nothing auto-sent) as settings rows, so a
   user can find them without reading the docs.
4. **No re-asking.** The reply style is set once in Settings; Home and the
   bubble panel mirror it, they do not ask again.
5. **Dark first.** The night palette is the design; light mode is the same
   layout with the light tokens, not a second design.

## 6. What is still on the old system

The redesign landed in waves. Done: theme + tokens, the mascot, Home, the
bubble panel, onboarding, suggestions (cards, BEST FIT badge, quoted message)
and Settings (grouped sections, helper header, privacy promises as rows).

The composer moved too: message card first, one style card for the four axes,
a quiet error strip instead of an error card, and the honest "sent only when you
press Generate" line under the gradient button.

The remaining screens - permission setup, app selection and the admin gate -
moved in the fourth wave, and they introduced `ScreenHeader`
(`lib/shared/widgets/screen_header.dart`) so the app has exactly **one** back
affordance instead of four hand-copied chips.

Nothing is left on the old system. From here a new screen starts from
`ScreenHeader` + `AppTheme` tokens + `MascotFace` when the helper is relevant.

## 7. Accessibility rules

- **Reduce motion is honoured, not decorated.** `MascotFace` stops its
  controllers when `MediaQuery.disableAnimations` is true, so no frames are
  scheduled at all (`test/accessibility_test.dart` asserts exactly that).
- **The mascot is decoration by default.** It is wrapped in `ExcludeSemantics`;
  a caller passes `semanticLabel` only when the face carries meaning ("Thinking").
- **A tile reads as one sentence.** Tappable cards use
  `Semantics(button: true, label: '<title>. <subtitle>')` and hide their inner
  fragments, so TalkBack says "Paste a message. Reply to the chat you are in."
  instead of four disconnected labels.
- **Colour is never the only signal.** Every state dot has the word next to it
  (`live` / `off`) and a semantics label.
- **Text scale is a layout constraint.** No fixed-aspect-ratio grid, no
  `maxLines: 1` on a label the user needs: the quick-start grid became two
  `IntrinsicHeight` rows so a 2x font grows the card instead of clipping it.

## 8. Interface language

`lib/core/l10n/app_strings.dart` holds every string the redesigned screens show,
in two implementations (`EnglishStrings`, `BengaliStrings`) behind
`appStringsProvider`. The interface language is **independent of the reply
language**: a Bengali speaker writing to an English colleague wants a Bengali app
that drafts English replies, and the docs already treat those as separate
settings.

Scope today: Home and Settings are wired; their language switch lives in
Settings -> *App language*. The remaining screens keep English strings for now -
the migration is mechanical (add getters to the abstract class, replace the
literal) and the compiler lists what is missing.

Deliberately **not** generated ARB files yet: two languages, one translator, and
a compile error on a missing string is worth more here than a build step.
