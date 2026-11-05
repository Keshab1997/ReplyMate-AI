# Floating Assistant Overlay

## Status

Optional future feature. Not part of the initial MVP.

## Purpose

Provide a small floating assistant that users can open while using other applications.

## Android Technology

The feature may use an Android foreground service and overlay window APIs, subject to Android version and policy requirements.

The user must explicitly grant the required overlay permission.

## Possible Features

- Small floating ReplyMate icon
- Open and close assistant panel
- Manually paste or enter message text
- Generate AI reply suggestions
- Copy a selected suggestion

## Important Limitations

An overlay cannot automatically read arbitrary text from the underlying application.

Overlay permission does not grant notification access or accessibility access.

The assistant must not secretly capture screen content.

## Privacy Requirements

- Show a visible overlay.
- Provide an obvious close button.
- Never record the screen.
- Do not intercept passwords or sensitive input.
- Do not display over secure system screens.

## Development Decision

Build a separate prototype after the notification-based MVP is stable. Test Android restrictions and Google Play policy requirements before release.
