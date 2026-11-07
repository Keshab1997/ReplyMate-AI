# Documentation Index

The set is deliberately small: every file here describes the app as it is, or
a feature that is specified and about to be built. Redundant planning notes
were removed during the 2026-11-07 cleanup (`git log -- docs/` has them); the
three that carry distinct reference value are kept and labelled as history.

## Product

- `../PRODUCT_REQUIREMENTS.md` — functional and non-functional requirements
- `../PROJECT_OVERVIEW.md` — what the product is, for whom, non-goals
- `../ROADMAP.md` — what is done, what is next, and the release gates
- `USER_FLOWS.md` — end-to-end journeys, including the bubble flow
- `SCREEN_SPECIFICATIONS.md` — screen-by-screen requirements

## Android integration

- `PLATFORM_CHANNELS.md` — the exact Dart ⇄ Kotlin contract
- `NOTIFICATION_LISTENER.md` — listener rules, limits, quick reply
- `ANDROID_NATIVE_SERVICES.md` — native components and permission boundaries
- `FLOATING_OVERLAY.md` — floating reply bubble: full implementation spec
- `OVERLAY_TASKS.md` — the same, broken into batches for an implementing agent
- `PHASE1_DEVICE_TESTS.md` — the evidence table; nothing is "working" until
  these rows are filled from a real device

## AI and data

- `AI_INTEGRATION.md` — how generation actually works today (client-side key
  pool, direct provider call) and what the prompts must do
- `API_SECURITY.md` — the recorded key-pool decision and its trade-off
- `FIREBASE_SETUP.md` — console setup, collections, rules

## Historical reference (kept, annotated as history)

- `ARCHITECTURE.md` — system boundaries; its backend flow is the target, not
  the shipped path (see `AI_INTEGRATION.md`)
- `LANGUAGE_SUPPORT.md` — multilingual reply rules
- `IMPLEMENTATION_PLAN.md` — the original build order, not a progress tracker

## Privacy and delivery

- `PRIVACY_AND_PERMISSIONS.md` — permissions, disclosures, data rules
- `BUILD_AND_RELEASE.md` — signing, CI, Play declarations, release checklist

When documentation conflicts, the order is: privacy rules → product
requirements → this spec set → everything else. Fix the conflict rather than
ignoring it.
