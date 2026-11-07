# User Flows

## Flow 1: First-Time Setup

1. User installs ReplyMate AI.
2. User opens the application.
3. Onboarding explains the product.
4. User chooses preferred language.
5. User opens notification access settings.
6. User grants notification access.
7. User selects messaging applications.
8. User reaches the home screen.

## Flow 2: Generate a Reply

1. A message notification arrives.
2. ReplyMate AI receives available notification data.
3. User opens the assistant.
4. User selects output language, tone, length and the number of suggestions (one to three).
5. User taps Generate.
6. AI suggestions appear.
7. User edits or selects a suggestion.
8. User copies, shares, or uses a supported quick-reply action.

## Flow 3: Quick Reply Unavailable

1. User selects a suggestion.
2. The app checks whether a valid notification reply action exists.
3. If unavailable, the app explains that quick reply is unsupported.
4. User can copy or share the reply, or open the original application.

## Flow 4: Permission Revoked

1. User revokes notification access.
2. ReplyMate AI detects the unavailable permission when possible.
3. The application displays a permission warning.
4. User can reopen Android Settings.

## Flow 5: AI Request Failure

1. User requests suggestions.
2. Backend or network request fails.
3. The app displays a clear error.
4. User can retry or edit the message manually.

## Flow 6: Floating reply bubble (planned — `docs/FLOATING_OVERLAY.md`)

1. A message arrives from an allowlisted app while the user is in that app.
2. A small ReplyMate bubble appears over the screen.
3. The user taps it.
4. A panel opens with the message, language/tone/length chips and Generate.
5. Suggestions appear; the user copies, edits, or quick-replies.
6. Closing the panel removes the bubble and the message from memory.

If the bubble cannot run (no overlay permission, disabled, or the app process
was dead), a fallback notification says "New message from \<app\> · Draft a
reply" and opens the composer prefilled. No message text appears in either
the bubble or the notification.
