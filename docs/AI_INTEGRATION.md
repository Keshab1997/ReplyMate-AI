# AI Integration

## Objective

Generate relevant, natural, context-aware message replies.

## Supported Languages

- Bengali
- Hindi
- English

## User Controls

The user should be able to choose:
- Output language
- Reply tone
- Reply length
- Number of suggestions

## Suggested Tones

- Friendly
- Casual
- Professional
- Polite
- Funny
- Short and direct

## Request Flow

1. User selects a notification or enters text manually.
2. User selects language and tone.
3. Flutter sends the request to the backend.
4. Backend validates the input.
5. Backend calls the selected AI provider.
6. Backend validates and returns the suggestions.
7. Flutter displays editable suggestions.

## Example Request

```json
{
  "message": "Can we meet tomorrow?",
  "language": "English",
  "tone": "Friendly",
  "length": "Short",
  "count": 3
}
```

## Example Response

```json
{
  "replies": [
    "Sure! What time works best for you?",
    "Yes, tomorrow sounds good.",
    "Absolutely. Let me know the time."
  ]
}
```

## Prompt Rules

- Preserve the intended meaning.
- Do not invent facts about the user.
- Do not assume a relationship between participants.
- Keep replies natural and concise.
- Respect the selected language and tone.
- Do not generate harmful or deceptive content.
- Return structured output that the app can validate.

## Current implementation status (2026-11-06)

The request-flow sections above describe the intended backend architecture.
The current MVP instead reads an enabled key from the Firestore key pool and
calls an OpenAI-compatible provider from the client; see
[`API_SECURITY.md`](API_SECURITY.md) for the accepted trade-off and planned
server-side proxy. Keshab reports API access and reply generation working on a
real device, but this does not mean the backend proxy or rate limiting exists.

## Provider Independence

Use a backend adapter so the application is not tightly coupled to one AI provider.

## Failure Handling

Handle:
- Network errors
- Provider downtime
- Rate limits
- Invalid responses
- Empty suggestions
- Timeouts

Never display a fabricated reply as a successful AI result.
