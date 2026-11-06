# Changelog

All notable project changes will be recorded here.

## [Unreleased]

### Implemented in the repository
- Flutter onboarding, home, permissions, app selection, settings and reply-suggestion flows.
- Kotlin notification listener, parser and Flutter platform-channel integration, including conditional RemoteInput quick reply and user-initiated share/text-selection entry points.
- Firebase admin gate and Firestore-backed API-key pool with direct provider API integration for reply generation.
- Bengali, Hindi and English output-language choices, tone/length controls, request validation and user-visible failure handling.

### Owner-reported verification — 2026-11-06
- Keshab reports that admin, API access and reply generation work on a real device. Device model, OS/app build and detailed test steps were not recorded; this is a smoke-test report, not full Phase 1 sign-off.

### Remaining before release
- Complete and record the real-device checklist in `docs/PHASE1_DEVICE_TESTS.md`.
- Decide/implement server-side provider-key handling and rate limiting; the current client-readable key-pool trade-off is documented in `docs/API_SECURITY.md`.
- Complete privacy/security, performance and Play policy review, then closed testing.

## [0.1.0] - Not released

### Added
- Initial project documentation
- Product requirements
- Architecture and implementation plan

### Notes
This project is in its planning and early development stage. No production-ready features are claimed yet.
