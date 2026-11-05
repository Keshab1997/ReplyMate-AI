# ReplyMate AI Roadmap

## Phase 0 — Project Foundation

- [ ] Create repository structure
- [ ] Finalize product requirements
- [ ] Finalize architecture
- [ ] Configure Flutter project
- [ ] Configure Android Kotlin integration

## Phase 1 — Android Feasibility

- [ ] Implement a minimal NotificationListenerService
- [ ] Request notification access
- [ ] Capture test notifications
- [ ] Handle missing and redacted content
- [ ] Detect notification actions
- [ ] Test RemoteInput on physical Android devices

**Release gate:** Do not proceed with claims of universal quick reply until real-device tests establish what works.

## Phase 2 — Flutter MVP

- [ ] Onboarding
- [ ] Home screen
- [ ] Permission setup screen
- [ ] Supported-app selection
- [ ] Language selection
- [ ] Tone selection
- [ ] Reply suggestion interface

## Phase 3 — AI Integration

- [ ] Backend API
- [ ] AI provider adapter
- [ ] Reply-generation endpoint
- [ ] Error handling
- [ ] Rate limiting
- [ ] Privacy controls

## Phase 4 — Android Integration

- [ ] Flutter-to-Kotlin communication
- [ ] Notification event handling
- [ ] Reply action validation
- [ ] Copy and fallback actions
- [ ] Lifecycle and permission testing

## Phase 5 — Testing

- [ ] Functional tests
- [ ] Physical-device tests
- [ ] Privacy review
- [ ] Performance review
- [ ] Closed testing

## Phase 6 — Future Features

- [ ] Floating overlay prototype
- [ ] More reply styles
- [ ] More languages
- [ ] Additional supported apps

Each phase must be tested before moving to the next one.
