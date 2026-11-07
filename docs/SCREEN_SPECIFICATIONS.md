# Screen Specifications

## 1. Splash Screen

Purpose:
- Display ReplyMate AI branding.
- Initialize essential application state.

## 2. Onboarding Screen

Explain:
- What ReplyMate AI does.
- How notification-based suggestions work.
- What permissions are needed.
- Why message content may be unavailable.

## 3. Home Screen

Show:
- Permission status
- Selected messaging apps
- Language preference
- Default tone
- Main reply-assistant entry point

## 4. Permission Setup Screen

Show separate sections for:
- Notification access
- Optional overlay permission (floating reply bubble) - implemented as its own
  card: what it does, what it does not do, current status, and a button into
  Android's "Display over other apps" screen, plus the Android 13+ notification
  requirement

Explain each permission before opening Settings.

## 5. App Selection Screen

Allow users to select supported messaging applications.

Do not claim support for an application until it has been tested.

## 6. Reply Composer Screen

Show:
- Available message context
- Language selector
- Tone selector
- Reply length selector
- Number-of-suggestions selector
- Generate button
- Loading state
- Error state

## 7. Suggestions Screen

Display generated replies in separate cards.

Actions:
- Copy
- Edit
- Share through the system chooser
- Use quick reply if supported

## 8. Settings Screen

Include:
- Language
- Default tone
- Privacy information
- Permission status
- Clear local preferences

## 9. Privacy Screen

Explain:
- What notification access allows
- What information may be sent to the AI backend
- What is stored
- How to revoke permissions

## 10. Floating Reply Panel (`/overlay`, reached only from the bubble)

Reached only from the bubble, never from normal navigation. Must:
- show the source app and the message the notification exposed;
- reuse the language/tone/length chips and the same suggestion cards;
- make Copy the always-available action;
- offer quick reply only when the notification still has a valid action, and
  explain the fallback when it does not;
- close to nothing: no history, no stored message, no "recent replies" list.

The permission screen (4) gains one optional card for the overlay permission:
what it does, what it does not do, current status, and a Settings button.

All screens must handle small displays and different Android font scales.
