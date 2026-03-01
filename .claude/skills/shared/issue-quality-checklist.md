# Gold-Standard Issue Template

This defines the quality bar for GitHub issues in this project. All backlog curation
skills target this template as the output format.

## Template

```markdown
## Summary

One paragraph explaining what this feature/enhancement does and why it matters.
Should answer: What problem does this solve? Who benefits? How does it fit into the
project's vision?

## Features / Scope

| Feature / Command | Description |
|-------------------|-------------|
| Feature A | What it does |
| Feature B --flag | What the flag changes |

> Omit this section if the issue is a bug fix, refactor, or single-behavior enhancement.

## Architecture / Design Notes

- **Module/package location**: Where the core logic lives
- **Storage**: Database tables, file storage, config keys, or "no storage needed"
- **Key technical decisions**: Libraries, algorithms, protocols
- **Security considerations**: Input validation, encryption, access control
- **Performance**: Any performance considerations

## Integration Points

How this connects to existing features:
- Which existing modules or commands are affected?
- Does it interact with config, storage, or plugins?
- Are there dependencies on other planned features?

## Acceptance Criteria

- [ ] Specific, testable criterion that maps to one verifiable behavior
- [ ] Another criterion — include happy path AND edge cases
- [ ] Error handling: what happens when X fails?
- [ ] Unit tests for core logic
- [ ] Integration tests that exercise the feature end-to-end (if applicable)

> Each checkbox should be independently verifiable. Avoid vague criteria like
> "works correctly" — instead say "returns exit code 0 and prints confirmation message".

## Documentation

- [ ] User-facing docs (if applicable)
- [ ] Internal specs (if complex): `docs/internal/specs/<feature>.md`
- [ ] CLAUDE.md updates: new key files, architecture patterns, or lessons learned
```

## Quality Checklist

When evaluating an issue, check each item:

- [ ] **Summary**: Clear one-paragraph explanation of what and why
- [ ] **Scope**: Features/commands/endpoints enumerated (if applicable)
- [ ] **Architecture**: Module location, storage approach, key decisions documented
- [ ] **Integration**: Connections to existing features identified
- [ ] **Acceptance criteria**: Specific, testable checkboxes (not vague)
- [ ] **Edge cases**: Error handling and failure modes covered in criteria
- [ ] **Tests**: Test requirements included in acceptance criteria
- [ ] **Documentation**: Doc requirements listed with specific file paths
- [ ] **CLAUDE.md**: Update requirement noted for new patterns/key files
- [ ] **Labels**: Appropriate labels applied

## Label Guide

| Label | When to use |
|-------|-------------|
| `feature` | Brand new capability (new command, new module, new endpoint) |
| `enhancement` | Improvement to existing feature |
| `bug` | Something is broken |
| `phase:1` | Foundation features |
| `phase:2` | Growth features |
| `phase:3` | Advanced features |
| `good-first-issue` | Clear scope, isolated domain, good for new contributors |
| `spec` | Has a spec document in `docs/internal/specs/` |
| `backlog/ready` | Issue is well-defined enough for autonomous implementation |
| `backlog/needs-refinement` | Issue needs more detail before implementation |
| `backlog/triage` | New issue, needs evaluation |
| `human/blocked` | Agent hit a limit and needs human intervention |
