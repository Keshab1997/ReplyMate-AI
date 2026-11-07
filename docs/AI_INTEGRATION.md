# AI Integration

## What actually ships (2026-11)

There is **no backend**. The client reads the admin-managed key pool from
Firestore (`admin_api_keys`) and calls an OpenAI-compatible
`/chat/completions` endpoint directly. This is architecture A, recorded with
its trade-off in `docs/API_SECURITY.md`.

```text
ReplyComposerScreen / OverlayPanelScreen (planned)
        │  ReplyRequest
        ▼
replyRepositoryProvider
        │  (KeyPoolReplyRepository in production,
        │   NotConfiguredReplyRepository when Firebase is absent)
        ▼
KeySource (admin_api_key_manager: health, cooldown, failover)
        ▼
OpenAiCompatibleClient → POST {baseUrl}/chat/completions
```

Code: `lib/features/reply/data/`.

- `reply_repository.dart` — the interface, the result types, the honest
  not-configured stub, the provider.
- `key_pool_reply_repository.dart` — validation, key selection, failover,
  response parsing.
- `openai_client.dart` — HTTP, typed failures, UTF-8 handling.
- `prompt_builder.dart` — the prompts.

The server-side proxy, request authentication and rate limiting described in
`docs/API_SECURITY.md` are **planned hardening, not implemented**.

## Supported output languages

Bengali, Hindi, English. The app's interface is English-only for now; only
generated replies are multilingual.

Rules the prompt carries: respect the requested language exactly, preserve
names and numbers, do not transliterate unless asked, keep mixed-language
input's meaning, never invent facts. Test script rendering, punctuation and
wrapping for all three.

## User controls

Output language, tone (friendly, casual, professional, polite, funny, short
and direct), length, and the number of suggestions (1–3, capped by
`AppConstants`).

## Request shape (to the provider)

The system prompt asks for exactly this JSON:

```json
{"replies": ["...", "..."]}
```

The parser accepts that shape first, then falls back to one reply per
non-empty line so a provider that ignores the format still yields something
usable. An empty list is a failure, never a silent success.

## Failure handling

Every failure is typed (`AiCallException`) and mapped to an honest,
retryable-or-not message:

| Case | Retryable | Notes |
|---|---|---|
| 401 / 403 | no | key rejected; reported to the pool |
| 429 | yes | rate limited by the provider |
| 5xx, timeout, DNS, TLS | yes | another key may work |
| Unreadable body | yes | never shown as a success |
| Empty `replies` | yes | explicit error |
| No healthy key | yes | pool empty / cooling down / unconfigured |

A key that misbehaved is reported back to the pool so cooldown and
deactivation logic can act. Nothing throws to the UI.

## Verification status

Keshab reports that API access and reply generation work on a real device
(2026-11-06). Device/build details were not recorded, and this says nothing
about the proxy, rate limiting or provider failover, none of which exist yet.

## Rules

- Never display a fabricated reply as a successful result.
- Never log message text or generated replies.
- Never send a message automatically; generation ends at a suggestion.
- Keep the provider behind `ReplyRepository` so a future proxy can replace the
  client without touching a screen.
- The overlay panel must call the same repository provider — no second AI path.
