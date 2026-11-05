# API Security

## Core Rule

Never store an AI provider's secret API key inside the Flutter application, Android APK, or public GitHub repository.

## Architecture

Flutter client → Secure backend → AI provider

## Backend Responsibilities

- Authenticate requests where appropriate.
- Validate all input.
- Apply request-size limits.
- Apply rate limits.
- Protect provider credentials.
- Set request timeouts.
- Return safe error messages.
- Monitor abuse without logging raw message content.

## API Design

Suggested endpoint:

`POST /v1/replies/generate`

The exact authentication method and API contract must be finalized before implementation.

## Input Validation

Validate:
- Message length
- Language
- Tone
- Reply count
- Request format

Reject unexpected fields and oversized requests.

## Secrets

Use environment variables or a managed secret store on the backend.

Never commit `.env` files containing real credentials.

Provide `.env.example` with placeholder values only.

## Abuse Prevention

- Rate-limit requests.
- Add usage limits.
- Monitor unusual traffic.
- Protect endpoints from automated abuse.
- Avoid exposing internal provider errors.

## Logging

Do not log raw message text, generated replies, or unnecessary personal information.

## Deployment

Use HTTPS for production communication. Rotate compromised credentials immediately.
