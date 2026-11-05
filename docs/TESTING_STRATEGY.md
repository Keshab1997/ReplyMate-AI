# Testing Strategy

## 1. Unit Testing

Test:
- Reply request validation
- Language selection
- Tone selection
- Input length limits
- Notification parsing
- Error handling

## 2. Flutter Widget Testing

Test:
- Onboarding
- Home screen
- Permission screen
- Reply composer
- Suggestions
- Settings

## 3. Android Native Testing

Test:
- Notification listener connection
- Notification reception
- Missing notification text
- Grouped notifications
- Duplicate notifications
- RemoteInput action detection
- Permission revocation and regrant

## 4. Backend Testing

Test:
- Authentication
- Input validation
- Provider failures
- Rate limiting
- Invalid responses
- Timeouts
- Secret management

## 5. Language Testing

Test:
- Bengali output
- Hindi output
- English output
- Mixed-language input
- Names and numbers
- Copy/paste behaviour

## 6. Device Testing

Test on:
- Different Android versions
- Different screen sizes
- Different manufacturers
- Devices with battery optimization enabled
- Low-memory devices

## 7. Privacy Testing

Verify:
- No raw message content in logs
- No automatic sending
- No unnecessary storage
- Correct permission disclosures
- User-controlled access

## Release Gate

Do not release if critical privacy, security, notification-handling, or message-sending issues remain unresolved.
