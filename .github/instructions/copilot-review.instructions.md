# Copilot Review Instructions

## Project Context

Read CLAUDE.md for project-specific conventions, patterns, and standards.

## General Review Criteria

### Error Handling (Priority: High)

Flag these patterns:
- **Silent error ignoring**: Any error from I/O, database, or network operations that is discarded or unchecked
- **Catch-all error masking**: Generic error handling that obscures the actual failure
- **Missing error wrapping**: Bare error returns without operation context

### Code Organization

- Keep files under 500 lines
- Domain logic should be separated from CLI/API layer
- Tests should live next to the code they test

### Testing Standards

- Tests should use temporary directories and environment isolation
- Integration tests should exercise the actual handler, not just helpers
- External tool interactions should be mocked

### Security

- No hardcoded secrets or API keys
- Validate user input at system boundaries
- Sanitize file paths (prevent directory traversal)
