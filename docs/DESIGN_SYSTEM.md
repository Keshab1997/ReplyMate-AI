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

Still to move: the composer, the permission screen, app selection and the admin
gate. They inherit the new tokens automatically because they read
`Theme.of(context)`, so the gap is layout polish, not colour.
