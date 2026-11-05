# Contributing to ReplyMate AI

Thank you for your interest in contributing.

## Before You Start

Read:
- README.md
- AGENTS.md
- PROJECT_OVERVIEW.md
- PRODUCT_REQUIREMENTS.md
- Relevant documentation in `docs/`

## Contribution Guidelines

1. Keep changes focused and easy to review.
2. Follow the existing architecture.
3. Do not introduce unnecessary dependencies.
4. Never commit API keys, passwords, or private credentials.
5. Never log real message contents.
6. Add tests for new business logic.
7. Document Android-specific limitations.
8. Test permission-related changes on a physical device.

## Suggested Workflow

1. Create a feature branch.
2. Implement the change.
3. Run tests and static analysis.
4. Test on Android.
5. Update relevant documentation.
6. Submit a pull request with a clear description.

## Commit Message Examples

- `feat: add notification permission screen`
- `feat: implement reply generation`
- `fix: handle missing notification text`
- `test: add RemoteInput validation tests`
- `docs: update Android integration guide`

## Privacy

Do not submit real private conversations, phone numbers, or personal information in issues, screenshots, test fixtures, or logs.
