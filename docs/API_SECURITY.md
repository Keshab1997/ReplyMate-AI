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

## Key-pool decision (2026-11-05)

The Core Rule above says provider keys never live in the client. On
2026-11-05 Keshab chose the `admin_api_key_manager` key-pool design for the
MVP anyway, with full knowledge of the trade-off. Recorded here so the repo
never silently contradicts itself:

- **What ships now (architecture A):** the Flutter client reads the enabled
  key pool from Firestore (`admin_api_keys`) and calls the provider's
  `/chat/completions` endpoint directly. Failover, cooldowns, health checks
  and usage/error stats come from the package; the admin screen manages the
  pool behind a Firestore allowlist gate (`admin_config/access`).
- **Why:** zero backend cost and zero backend code at the planning stage, a
  ready-made admin UI, and a pool of disposable free-tier keys where a
  leaked key costs a cooldown, not a breach.
- **Mitigations while this stands:** keys in the pool are consumables, never
  production credentials; Firestore rules must deny writes to everyone except
  admins; usage and error logging give abuse visibility; the app never logs
  message content.
- **The hardening step (architecture C):** a backend proxy that reads the
  same Firestore pool server-side is the Phase 3 item already on ROADMAP.md
  ("Backend API", "AI provider adapter"). When it lands, the client stops
  seeing keys and this section becomes historical.

Until that proxy exists, treat every key in the pool as potentially public.
