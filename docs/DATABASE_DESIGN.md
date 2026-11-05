# Database Design

## MVP Principle

ReplyMate AI should avoid storing message content by default.

The MVP should work with minimal or no persistent personal data.

## Local Preferences

Possible local preferences:

- Selected language
- Preferred tone
- Reply length
- Selected messaging applications
- User interface settings

Store only what is necessary.

## Backend Storage

A backend database is not mandatory for the first prototype.

If accounts or synchronized preferences are introduced later, use a minimal schema.

Possible future tables:

### users

- id
- created_at
- account_status

### user_preferences

- user_id
- language
- default_tone
- reply_length

### usage_records

- id
- user_id or anonymous installation identifier
- request_timestamp
- usage_count
- status

Usage records should not contain raw messages or generated replies.

## Retention

Define a clear retention period before collecting any analytics or account data.

Provide a way to delete account-related data if accounts are introduced.

## Security

- Apply access controls.
- Protect stored credentials.
- Avoid storing message content.
- Do not expose private records to other users.
