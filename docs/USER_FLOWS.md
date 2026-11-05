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
4. User selects language and tone.
5. User taps Generate.
6. AI suggestions appear.
7. User edits or selects a suggestion.
8. User copies or uses a supported quick-reply action.

## Flow 3: Quick Reply Unavailable

1. User selects a suggestion.
2. The app checks whether a valid notification reply action exists.
3. If unavailable, the app explains that quick reply is unsupported.
4. User can copy the reply or open the original application.

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
