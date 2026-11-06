# Language Support

## Initial Languages

- Bengali (`bn`)
- Hindi (`hi`)
- English (`en`)

## Language Selection

Users can select:
- Application interface language
- AI reply output language

These settings should be independent.

## Bengali

Support Bengali script naturally. Avoid unnecessary transliteration unless the user requests it.

## Hindi

Support Devanagari script naturally.

## English

Use natural, grammatically correct English.

## Mixed-Language Messages

Users may receive messages containing multiple languages. The AI should understand mixed-language context when supported by the configured provider.

## Language Behaviour

- Respect the selected output language.
- Preserve names and important details.
- Do not translate unnecessarily.
- Do not change dates, numbers, or factual details.
- Avoid unnatural literal translations.

## Current implementation status (2026-11-06)

Reply output can be selected independently in Bengali, Hindi or English. The
application interface itself is currently English-only; independent UI
localization remains open work in `ROADMAP.md`.

## Testing

Test native script rendering, punctuation, line wrapping, and copy/paste behaviour for all three languages.
