# Design system — mascot-first

The reference render for this pass is `design/app_redesign_preview.html` (open it
in a browser; it is self-contained). The bubble's own reference is
`design/bubble_preview.html`.

## 1. The character

One 3D face (`design/bubble_mascot_bubble.png`) is the app's whole personality.
It is not decoration bolted onto a UI; it is the thing the user recognises, so
it appears only in these familiar places:

| Where | Size | Why |
| --- | --- | --- |
| Floating bubble (`OverlayBubbleService`) | 56 dp | the product's front door |
| Home hero (`MascotFace`) | 72 dp | "your helper" — compact enough to keep actions in view |
| Onboarding hero (`MascotFace`) | 64 dp compact / 88 dp large | meet the character before any permission request |
| Settings header | 44 dp | continuity, not a second hero |
| Thinking / result states | 40–56 dp | same face, different mood |

`MascotMood` (`lib/shared/widgets/mascot_face.dart`) is how the face reacts:
`idle`, `listening`, `thinking`, `happy`, `alert`. Happy and alert have their
own carefully matched artwork; idle and listening occasionally crossfade to a
real closed-eye frame. The old whole-face squash is gone. Every variant keeps
the same circular crop and transparent outer pixels.

`thinking` additionally shows three breathing dots under the face: the app's
only "the helper is working" cue, and deliberately wordless — it says
*something is happening* without guessing how long it will take. The composer
header switches `listening` -> `thinking` while a request is in flight. The
floating panel keeps its sender/app header fixed and shows progress only on
its Generate button.

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
- Native bubble motion also checks Android's animator setting. Dragging stops
  the idle bob, gives a small scale/elevation response and settles with a
  damped spring; collapse and expansion animate the real window dimensions.
- The native blink swaps to matched closed-eye artwork. New messages briefly
  use happy artwork, while truncated/redacted/group-summary context uses the
  alert frame—never sender or message text.

## 3. Typography and icons

- **Inter** is the Latin face, with **Noto Sans Bengali** and **Noto Sans
  Devanagari** as bundled fallbacks. All three are variable fonts shipped in
  `assets/fonts/` with their OFL licences, so rendering never needs a network
  font download.
- `AppIcons` keeps the rounded Material icons consistent. Product concepts that
  need their own language use `BrandIcon`: reply, notification, language,
  privacy, screen reading and memory share the same rounded stroke.
- Choice chips can pair a value with its relevant icon. Their touch targets
  stay padded even when the visible chip is compact.
- Android uses the same identity at launch: a mascot splash in light and dark,
  the existing safe-zone adaptive icon, and an Android 13 monochrome reply
  bubble for themed launchers.

## 4. Colour

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

## 5. Shape and space

- Cards `20 dp`, tiles `16 dp`, buttons `16 dp`, pills `11 dp`. Pills are for
  values the app already decided (language, tone, length), never for questions.
- Spacing scale is the same one the code already had: 4 / 8 / 16 / 24 / 32.
- Content stays at most `680 dp` wide (`AppSurfaces.centered`), so tablets get
  a readable column rather than edge-to-edge cards.
- Body-small text starts at `12.5 dp`; important explanations do not use the
  old 10–11 dp microcopy treatment.
- One gradient (`AppTheme.primaryGradient`) for the primary action and nothing
  else, so "the gradient" always means "press this". Disabled actions lose the
  gradient and glow as well as their tap callback.

## 6. Screen rules

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

## 7. What is still on the old system

The redesign landed in waves. Done: theme + tokens, the mascot, Home, the
bubble panel, onboarding, suggestions (cards, BEST FIT badge, quoted message)
and Settings (grouped sections, helper header, privacy promises as rows).
The premium polish pass keeps that language while grouping onboarding's four
promises into one surface, making its bottom action permanently reachable,
and sharing the same gradient button, icon badge, responsive width and header
across the main and inner screens. Compact screens use a smaller mascot and
tighter vertical rhythm rather than shrinking explanatory text. Home switches
to a horizontal hero when space allows and stacks it for large text. Reply
generation previews the result layout with a finite skeleton, not an endless
shimmer.

The composer moved too: message card first, one style card for the four axes,
a quiet error strip instead of an error card, and the honest "sent only when you
press Generate" line under the gradient button.

The remaining screens - permission setup, app selection and the admin gate -
moved in the fourth wave, and they introduced `ScreenHeader`
(`lib/shared/widgets/screen_header.dart`) so the app has exactly **one** back
affordance instead of four hand-copied chips.

Nothing is left on the old system. From here a new screen starts from
`ScreenHeader` + `AppTheme` tokens + `MascotFace` when the helper is relevant.

## 8. Floating glass panel

The overlay is a **centered floating card**, not a bottom sheet. It is at most
`460 dp` wide and `760 dp` high, with `24 dp` corners, a subtle rim and a deep
soft shadow. A `20 dp` backdrop blur sits beneath a 90–95% surface tint: the
chat remains perceptible without competing with the message or controls. A
48–64% black scrim closes on an outside tap.

The sender/app header stays fixed while chat chips, message/style controls,
errors and suggestions scroll. The card shrinks for short empty/loading states
and moves above the keyboard rather than letting the text field disappear.
High contrast removes the blur and uses a solid, outlined surface; reduced
motion skips the entrance translation/scale. Native visuals still require
real-device confirmation because widget captures cannot render the Android
bubble over another application.

## 9. Accessibility rules

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

## 10. Interface language

`lib/core/l10n/app_strings.dart` holds the interface strings in
`EnglishStrings`, `BengaliStrings` and `HindiStrings` behind
`appStringsProvider`. The interface language is **independent of the reply
language**: a Bengali speaker writing to an English colleague wants a Bengali app
that drafts English replies, and the docs already treat those as separate
settings. Bundled font fallbacks make those three scripts share one screen
without falling back to a platform-dependent font.

Scope today: the heavily used Home, Reply, bubble and Settings surfaces are
wired; the remaining setup and admin strings are tracked in `ROADMAP.md`.
Deliberately **not** generated ARB files yet: one translator and a compile
error on a missing string are worth more here than a build step.
