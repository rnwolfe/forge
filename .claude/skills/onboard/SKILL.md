---
name: onboard
description: "Interactive project bootstrapping — generates CLAUDE.md, VISION.md, CI workflow, forge.toml, and configures GitHub"
disable-model-invocation: true
---

# Onboard — Interactive Project Bootstrapping

You are onboarding a new project onto the forge autonomous development pipeline. This is
an interactive, conversational process that generates high-quality, project-specific
configuration and documentation. The output is not fill-in-the-blank templates — it is
contextual, thoughtful content tailored to this specific project.

## Input

```
/onboard                  — Full interactive onboarding (all 6 phases)
/onboard --stack          — Reconfigure tech stack only (Phase 2)
/onboard --gating         — Reconfigure gating levels only (Phase 2, gating section)
/onboard --verify         — Verify existing setup: check forge.toml, CLAUDE.md, VISION.md, CI, labels
```

Arguments: `$ARGUMENTS`

---

## Overview

Six phases, each building on the previous:

| Phase | Name | Key Output |
|-------|------|------------|
| 1 | Identity | `docs/internal/VISION.md` |
| 2 | Tech Stack | `forge.toml` (populated), `.github/workflows/ci.yml` |
| 3 | Architecture | `CLAUDE.md` |
| 4 | Scaffolding | Surface area decisions, directory structure |
| 5 | MVP Features | Initial GitHub issues |
| 6 | GitHub Setup | Labels, branch protection, manual steps checklist |

The user can interrupt at any phase. Each phase produces a committed artifact that is
useful on its own even if later phases are skipped.

---

## Phase 0 — Prerequisites

**Run this before anything else (full onboarding only, skip for reconfiguration modes).**

### Check for `gh` CLI

The GitHub CLI (`gh`) is required for Phases 5 and 6 (creating issues, labels, branch
protection). Check if it's installed and authenticated:

```bash
gh --version 2>/dev/null
gh auth status 2>/dev/null
```

**If `gh` is not installed**, help the user set it up:

```
The GitHub CLI (gh) is required for the full onboarding experience.
It's used to create issues, configure labels, and set up branch protection.

Install it:
  macOS:   brew install gh
  Linux:   https://github.com/cli/cli/blob/trunk/docs/install_linux.md
  Windows: winget install --id GitHub.cli

After installing, authenticate:
  gh auth login

You can proceed with Phases 1-4 without gh, but Phases 5-6 (GitHub setup) will be
skipped. Run /onboard --verify later to finish setup.
```

If `gh` is installed but not authenticated (`gh auth status` fails), prompt:

```
gh is installed but not authenticated. Run:
  gh auth login

Then re-run /onboard to continue.
```

If the user wants to proceed without `gh`, note that Phases 5 and 6 will be skipped and
they can run `/onboard --verify` later to finish the GitHub-dependent steps.

### Fresh Git History

When a user creates a repo from the forge template, it inherits forge's commit history.
The project should start with a clean slate.

Check the current git state:

```bash
git log --oneline -5 2>/dev/null
git remote -v 2>/dev/null
```

If the repo has forge's template history (look for commits like "chore: initial forge
template repo" or a remote pointing to `rnwolfe/forge`), offer to reset:

```
This repo was created from the forge template and still has forge's git history.
Would you like to start with a clean git history? (Recommended)

This will:
  1. Remove the existing .git directory
  2. Initialize a fresh git repo
  3. Stage all template files as your first commit

Your files will not be modified — only the git history changes.
```

If the user agrees:

```bash
rm -rf .git
git init
git add -A
git commit -m "chore: initialize project from forge template

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### GitHub Repository

After resetting git history (or if the repo has no remote), offer to create a GitHub
repository:

```bash
git remote -v 2>/dev/null
```

If no remote is configured, ask:

```
No GitHub remote found. Would you like to create a GitHub repository now?

I'll need:
  1. Repository name (e.g., "myproject" or "org/myproject")
  2. Visibility: public or private?
```

If the user provides the info:

```bash
# For personal repos:
gh repo create $REPO_NAME --$VISIBILITY --source=. --push

# For org repos:
gh repo create $ORG/$REPO_NAME --$VISIBILITY --source=. --push
```

If the user wants to skip, note that they'll need a remote configured before Phases 5-6.
Phases 1-4 work fine without a remote.

If a remote already exists and points to the right repo, confirm and move on.

---

## Reconfiguration Modes

### `--stack`

Skip Phase 1 (Identity). Read the existing `docs/internal/VISION.md` for project context,
then jump directly to Phase 2 to reconfigure the tech stack. Update `forge.toml` and
regenerate `.github/workflows/ci.yml`.

### `--gating`

Read existing `forge.toml` and present the current gating configuration. Walk the user
through the four gating levels and update only the `[gating]` section. No other files
are modified.

### `--verify`

Read all generated files and verify:
- `forge.toml` has all required fields populated (non-empty)
- `CLAUDE.md` exists and contains project-specific content (not template placeholders)
- `docs/internal/VISION.md` exists
- `.github/workflows/ci.yml` exists and matches the stack in `forge.toml`
- `.github/CODEOWNERS` has a real username (not the placeholder)
- Labels exist on the GitHub repo (run `gh label list`)
- Branch protection is configured (run `gh api repos/$REPO/branches/$BASE/protection`)

Report what is configured, what is missing, and what needs manual action.

---

## Phase 1 — Identity

**Goal**: Understand what this project is, what it values, and where it is going. Generate
`docs/internal/VISION.md`.

### Conversation

Ask the user these questions. Do not dump all questions at once — ask 2-3 at a time and
respond to their answers before continuing. This is a conversation, not a form.

**Round 1 — What is it?**
1. What does this project do? (One sentence that a stranger would understand.)
2. Who is it for? (Specific audience, not "developers" — e.g., "backend engineers managing
   microservices" or "solo founders building MVPs".)
3. What problem does it solve that existing tools do not?

**Round 2 — What does it value?**
4. What are the 3-5 design principles that guide decisions? (Examples: "speed over features",
   "convention over configuration", "local-first", "zero dependencies".)
5. What is explicitly out of scope? What will this project never do?
6. Is there a personality or tone? (Formal/informal, playful/serious, opinionated/neutral.)

**Round 3 — Where is it going?**
7. What does "done" look like for a v1.0? What are the 3-5 features that constitute the
   minimum viable product?
8. What comes after v1.0? Are there phases or a roadmap?
9. Are there any existing decisions, constraints, or prior art that shape the architecture?

### Generate VISION.md

After gathering answers, generate `docs/internal/VISION.md`:

```markdown
# [Project Name] — Vision

> [One-sentence elevator pitch from question 1]

## Identity

**What it is**: [2-3 sentence expanded description]

**Who it's for**: [Target audience from question 2]

**Why it exists**: [Problem statement from question 3]

## Design Principles

[Numbered list of 3-5 principles from question 4, each with a one-sentence explanation
of what it means in practice for this project]

1. **[Principle name]**: [What this means for decisions]
2. ...

## Out of Scope

[Explicit boundaries from question 5 — what this project will never do]

## Personality

[Tone and voice from question 6 — how the project communicates with users]

## Roadmap

### Phase 1 — Foundation
[v1.0 features from question 7]

### Phase 2 — Growth
[Post-v1.0 features from question 8]

### Phase 3 — Maturity
[Long-term direction, if the user provided any]

## Prior Art & Constraints

[From question 9 — anything that shapes the architecture from the start]
```

**Commit**: `git add docs/internal/VISION.md && git commit -m "docs: add project vision"`

Present the generated VISION.md to the user for review before committing. Make adjustments
if they have feedback.

---

## Phase 2 — Tech Stack

**Goal**: Populate `forge.toml` with the project's actual tech stack and generate a CI
workflow.

### Conversation

Ask the user:

1. **Language and framework**: What language(s) and framework(s) does this project use?
   (Go, Node/TypeScript, Python, Rust, Java, etc.)

2. **Build and test commands**: What commands build and test the project?
   - Build: `make build`, `npm run build`, `cargo build`, `go build ./...`, etc.
   - Test: `make test`, `npm test`, `cargo test`, `go test ./...`, etc.
   - Lint (optional): `go vet ./...`, `npm run lint`, `cargo clippy`, etc.

3. **Release tooling**: How are releases published?
   - GoReleaser, npm publish, cargo publish, Docker, PyPI, GitHub Releases only, none yet

4. **Gating level**: How much human control do you want over the pipeline?

   Present the four levels clearly:

   ```
   Level 1 (recommended to start): Agent implements and reviews. Human merges every PR.
   Level 2: Same as Level 1, but auto-merge is enabled after human approves.
   Level 3: Human reviews only for sensitive file patterns (you define which patterns).
   Level 4: Fully autonomous — agent implements, reviews, and merges. Human oversight
            is passive (via audit reports and issue tracking).
   ```

   Recommend Level 1 for new projects. Level 4 is for mature projects with strong test
   coverage and well-established patterns.

5. **Trusted users**: Which GitHub usernames are authorized to trigger the pipeline by
   labeling issues `backlog/ready`?

6. **CODEOWNERS**: Who is the primary human reviewer? (GitHub username for CODEOWNERS file.)

7. **Protected files**: Besides the defaults (CLAUDE.md, workflows, autodev scripts,
   forge.toml), are there other files the agent should never modify?

### Update forge.toml

Read the existing `forge.toml` (it has all the keys with empty/default values). Update
each field based on the user's answers. Use the Edit tool to update fields in place — do
not rewrite the entire file (preserves comments and structure).

Key mappings:
- Question 1 -> `[stack]` section (`language`, `build_command`, `test_command`, `lint_command`)
- Question 3 -> `[stack]` section (`release_tool`)
- Question 4 -> `[gating]` section (all fields)
- Question 5 -> `[trust]` section (`trusted_users`)
- Question 6 -> `[trust]` section (`human_reviewer`)
- Question 7 -> `[protected_files]` section (`patterns`)

Also update `[project]` fields:
- `name`: from Phase 1 project name
- `repo`: ask the user for `org/repo` format
- `description`: from Phase 1 one-sentence pitch

### Update CODEOWNERS

Update `.github/CODEOWNERS` with the actual username:

```
* @username
```

### Generate CI Workflow

Generate `.github/workflows/ci.yml` based on the tech stack. The CI workflow should:
- Trigger on `push` to main and on `pull_request`
- Run the test command from `forge.toml`
- Run the build command from `forge.toml`
- Run the lint command (if provided)
- Name the test job `test` (branch protection references this name)

**Language-specific templates:**

For **Go**:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
      - name: Test
        run: [test_command]
      - name: Build
        run: [build_command]
```

For **Node/TypeScript**:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: .node-version
          cache: npm
      - run: npm ci
      - name: Lint
        run: [lint_command]
      - name: Test
        run: [test_command]
      - name: Build
        run: [build_command]
```

For **Python**:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version-file: .python-version
      - name: Install dependencies
        run: pip install -e ".[dev]"
      - name: Test
        run: [test_command]
```

For **Rust**:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      - name: Test
        run: [test_command]
      - name: Build
        run: [build_command]
```

For **other languages**: Generate a minimal workflow with checkout + the user's
build/test commands, and note that they may need to add a setup step for their runtime.

**Commit**: Stage `forge.toml`, `.github/CODEOWNERS`, and `.github/workflows/ci.yml`.
Commit with message `ci: configure tech stack and CI workflow`.

---

## Phase 3 — Architecture

**Goal**: Generate a comprehensive `CLAUDE.md` that serves as the operating manual for
both human and AI contributors.

### Conversation

Ask the user:

1. **File organization**: Describe the project's directory structure. What goes where?
   (If the project is new and has no structure yet, discuss what structure they want.)

2. **Architecture patterns**: What patterns does the codebase follow?
   - How is the code organized? (MVC, domain-driven, feature-based, flat?)
   - How is state managed? (Database, files, in-memory?)
   - How are external dependencies handled?
   - Are there any patterns that contributors must follow?

3. **Testing standards**: How should tests be written?
   - Unit vs. integration test strategy
   - Test file naming and location
   - Mocking/stubbing patterns
   - What constitutes sufficient test coverage?

4. **Error handling**: How should errors be handled and reported?
   - Error wrapping/chaining conventions
   - User-facing error message standards
   - Logging conventions

5. **Security rules**: Any project-specific security requirements?
   - Sensitive data handling
   - Input validation rules
   - Authentication/authorization patterns

6. **Development workflow**: Any project-specific workflow rules beyond what forge provides?
   - Code review expectations
   - Documentation requirements
   - Performance requirements

### Generate CLAUDE.md

Generate `CLAUDE.md` at the repository root. This file is the project's operating manual.
It should be comprehensive enough that a new contributor (human or AI) can understand the
project and contribute correctly after reading only this file.

Structure:

```markdown
# [Project Name] — Operating Manual

> This is the agentic knowledge base for [project]. It captures architecture decisions,
> patterns, and development practices. It is the source of truth for how to work on
> this project.

## Project Overview

**[Project name]** — [one-sentence description from Phase 1]

- **Language**: [from Phase 2]
- **Framework**: [from Phase 2]
- [Other key tech stack details]

## Build & Test

```bash
[build_command]     # Build
[test_command]      # Test
[lint_command]      # Lint (if applicable)
```

- ALWAYS run tests after code changes
- ALWAYS run build before committing
- NEVER commit if tests fail

## File Organization

```
[directory tree from question 1, annotated with what goes where]
```

Rules:
- [File organization rules from the conversation]
- Keep files under 500 lines
- Tests live next to the code they test

## Architecture Patterns

[From question 2 — numbered list of patterns with descriptions]

## Testing Standards

[From question 3 — conventions, naming, patterns]

## Error Handling

[From question 4 — wrapping, user-facing messages, logging]

## Security Rules

[From question 5 — security conventions]

- NEVER hardcode secrets or API keys
- NEVER commit .env files
- Validate all user input at system boundaries
- Sanitize file paths (prevent directory traversal)

## Development Workflow

- **main is sacred.** All changes go through PRs. No direct pushes.
- Branch naming: `feat/`, `fix/`, `chore/`, `docs/` prefixes
- Conventional commits: `type: description` format
- PRs require CI passing

[Additional project-specific workflow rules from question 6]

## Autonomous Development Workflow

An event-driven GitHub Actions pipeline that autonomously implements issues end-to-end.
For a comprehensive architecture deep-dive with diagrams, see
[docs/internal/autodev-pipeline.md](docs/internal/autodev-pipeline.md).

### How it works

Four workflows form the core loop, plus a weekly audit:

1. **`autodev-dispatch`** — Runs on a configurable cron. Picks the highest-priority
   `backlog/ready` issue, labels it `agent/implementing`, and triggers the implement workflow.
2. **`autodev-implement`** — Checks out the base branch, creates a feature branch, runs
   the agent to implement the issue, pushes, and opens a PR. After creating the PR, the
   workflow polls for Copilot review and dispatches `autodev-review-fix`.
3. **`autodev-review-fix`** — Phased review pipeline: Copilot phase (up to N iterations)
   -> Claude phase -> done.
4. **`claude-code-review`** — Triggered by `agent/review-claude` label or `@claude` mention.
5. **`autodev-audit`** — Weekly pipeline health report filed as a GitHub issue.

### Labels

| Label | Meaning |
|-------|---------|
| `backlog/ready` | Issue is ready for autonomous implementation |
| `agent/implementing` | Issue is currently being implemented by an agent |
| `agent/review-copilot` | Agent is addressing Copilot review feedback |
| `agent/review-claude` | Agent is addressing Claude review feedback |
| `human/blocked` | Agent hit a limit and needs human intervention |
| `via/actions` | PR created by GitHub Actions pipeline |
| `via/autodev` | PR created by /autodev CLI skill |

### Secrets required

| Secret | Purpose |
|--------|---------|
| `CLAUDE_CODE_OAUTH_TOKEN` | OAuth token for Claude Code agent execution |
| `APP_ID` + `APP_PRIVATE_KEY` | GitHub App credentials for push/PR operations |

## GitHub Issue Workflow

When creating a PR that implements a GitHub issue:

1. Read the original issue and extract acceptance criteria
2. Verify each criterion is satisfied by the implementation
3. Document verification in the PR body under "Acceptance Criteria"
4. Use closing keywords (`Closes #N`, `Fixes #N`) for auto-close on merge

## Key Files

[Start with known key files and add more as the project evolves]

| File | Purpose |
|------|---------|
| `CLAUDE.md` | This file — project operating manual |
| `forge.toml` | Pipeline configuration |
| `docs/internal/VISION.md` | Product vision and design principles |
| `docs/internal/DECISIONS.md` | Architectural decision records |
```

**Important**: The generated CLAUDE.md must be genuinely useful — not a template with
placeholders. Every section should contain real, specific content drawn from the
conversation. If the user didn't provide enough detail for a section, ask follow-up
questions before generating.

**Commit**: `git add CLAUDE.md && git commit -m "docs: add project operating manual"`

---

## Phase 4 — Scaffolding

**Goal**: Set up the project's directory structure and any boilerplate files.

### Conversation

Based on the architecture discussion in Phase 3, ask:

1. **Existing code**: Does the project already have code, or are we starting from scratch?
   - If existing: what's the current state? Anything that needs reorganization?
   - If new: should we create the initial directory structure now?

2. **Boilerplate files**: Does the project need any of these?
   - `.gitignore` (generate based on language from Phase 2)
   - `Makefile` or equivalent task runner
   - Dependency files (`go.mod`, `package.json`, `Cargo.toml`, `pyproject.toml`, etc.)
   - Docker files
   - Editor config (`.editorconfig`, `.vscode/settings.json`)

3. **Documentation structure**: The following are already created by forge:
   - `CLAUDE.md` (Phase 3)
   - `docs/internal/VISION.md` (Phase 1)
   - `docs/internal/DECISIONS.md` (pre-populated)
   - `docs/internal/LIFECYCLE.md` (pre-populated)
   - `docs/internal/autodev-pipeline.md` (pre-populated)
   - `CONTRIBUTING.md` (pre-populated)
   - `README.md` (needs project-specific content)

   Ask: Should we update the README.md with project-specific content now? (The template
   README describes forge itself — it should be replaced with the project's own README.)

### Actions

For each decision:
- Create requested directories
- Generate requested boilerplate files
- If updating README.md, generate a project-specific version

**Commit**: `git add -A && git commit -m "chore: scaffold project structure"`

Only create files the user explicitly requests. Do not add files "just in case."

---

## Phase 5 — MVP Features

**Goal**: Create the initial set of GitHub issues that define the project's first
implementation targets.

### Conversation

1. Review the Phase 1 roadmap (v1.0 features from VISION.md).

2. For each v1.0 feature, discuss:
   - Is this one issue or should it be broken into smaller issues?
   - What are the acceptance criteria?
   - Are there dependencies between features? (Which must be built first?)

3. Present a proposed issue list with titles, brief descriptions, and suggested labels.
   Ask the user to confirm, modify, or cut issues before creating them.

### Create Issues

For each confirmed issue, create it on GitHub:

```bash
gh issue create \
  --repo $REPO \
  --title "$TITLE" \
  --body "$(cat <<'EOF'
## Summary

[1-2 sentences: what this feature does and why it matters]

## Acceptance Criteria

- [ ] [Specific, testable criterion]
- [ ] [Another criterion]
- [ ] Tests pass
- [ ] Documentation updated (if applicable)

## Architecture Notes

[Brief notes on where this fits in the codebase — which packages/modules to create or modify]

## Dependencies

[List any issues that must be completed first, or "None"]
EOF
)" \
  --label "feature"
```

**Important**: Do NOT auto-label any issues as `backlog/ready`. The user should apply
that label manually after reviewing each issue. This is their first quality gate.

After creating issues, print a summary:

```
Created N issues for [project name]:

  #1: [Title]
  #2: [Title]
  ...

Next steps:
  1. Review each issue and add acceptance criteria details
  2. Label issues as `backlog/ready` when they are specific enough to implement
  3. The pipeline will pick them up on the next cron run (or run /autodev to start immediately)
```

---

## Phase 6 — GitHub Setup

**Goal**: Configure the GitHub repository for the autodev pipeline.

### Automated Steps

Run the setup script:

```bash
bash setup/setup.sh
```

This runs `create-labels.sh` and `configure-branch-protection.sh` idempotently.

Report the results of each step.

### Manual Steps Checklist

After the automated setup, present the manual steps the user needs to complete.
These cannot be automated because they require GitHub UI access or secret management.

```
GitHub Setup Checklist:

Automated (done):
  [x] Pipeline labels created
  [x] Branch protection configured

Manual (you need to do these):
  [ ] 1. Create a GitHub App for pipeline authentication
       - Go to: https://github.com/settings/apps/new
       - Permissions: Contents (read/write), Pull requests (read/write), Issues (read/write)
       - Install the app on your repository
       - Note the App ID and generate a private key

  [ ] 2. Add repository secrets (Settings > Secrets and variables > Actions)
       - CLAUDE_CODE_OAUTH_TOKEN: Your Claude Code OAuth token
       - APP_ID: GitHub App ID from step 1
       - APP_PRIVATE_KEY: GitHub App private key from step 1

  [ ] 3. Enable Copilot code review
       - Go to: Settings > Copilot > Code review
       - Enable "Copilot code review"

  [ ] 4. Enable auto-merge (if using gating level 2+)
       - Go to: Settings > General > Pull Requests
       - Check "Allow auto-merge"

  [ ] 5. Verify CI workflow
       - Push a branch and open a test PR
       - Confirm the CI workflow runs and passes

  [ ] 6. Test the pipeline
       - Create a test issue with a simple task
       - Label it `backlog/ready`
       - Watch the pipeline pick it up (or manually trigger autodev-dispatch)
       - Review and merge the resulting PR
       - Delete the test issue after verification
```

### Verification

After presenting the checklist, offer to run `/onboard --verify` to check what has been
configured so far.

---

## Guardrails

- **Always ask before committing.** Present the generated content and get confirmation
  before running `git commit`.
- **Always ask before creating issues.** Show the full issue body before running
  `gh issue create`.
- **Never auto-label issues as `backlog/ready`.** That is the user's quality gate.
- **Never modify existing code.** This skill generates configuration and documentation
  only. It does not refactor, restructure, or otherwise change the project's source code.
- **Never overwrite existing CLAUDE.md or VISION.md without confirmation.** If these files
  already exist, ask the user if they want to replace, merge, or skip.
- **Never store secrets.** Do not ask for or handle API keys, tokens, or passwords. Direct
  the user to GitHub's secret management UI.
- **Conversational, not robotic.** This is an interactive conversation. Respond to the
  user's answers with understanding before moving to the next question. Acknowledge
  constraints, suggest alternatives, share relevant experience from the forge patterns.
- **Quality over speed.** It is better to ask a clarifying question than to generate a
  vague CLAUDE.md. The output of this skill is the foundation that every future agent
  interaction builds on — it must be specific and accurate.

---

## Error Recovery

| Situation | Action |
|-----------|--------|
| `forge.toml` missing | It should exist in the repo root (shipped with forge). If somehow missing, create it from the template in the forge README. |
| User wants to skip a phase | Acknowledge and skip. Each phase is independently useful. Note what they skipped so they can return to it later. |
| `gh` CLI not installed | Walk the user through installation (brew, apt, winget). Phases 1-4 work without it. Phases 5-6 are skipped until `gh` is available. |
| `gh` CLI not authenticated | Tell the user to run `gh auth login`. Offer to wait while they do it, or skip Phases 5-6. |
| Repo not on GitHub yet | Offer to create it via `gh repo create`. If the user declines, Phases 1-4 work without a remote. Skip Phases 5-6 and tell the user to return after pushing to GitHub. |
| Forge template git history present | Offer to reset with `rm -rf .git && git init`. Explain this only removes commit history, not files. |
| Existing CLAUDE.md conflict | Ask: replace, merge (read existing and incorporate), or skip. |
| Labels already exist | `create-labels.sh` is idempotent — it updates existing labels. This is safe to re-run. |
| Branch protection fails | The script handles this gracefully — it prints manual instructions if the API call fails (usually a permissions issue). |
| `gh repo create` fails | Usually a permissions issue or name conflict. Show the error and suggest creating the repo manually via GitHub UI, then adding the remote: `git remote add origin https://github.com/ORG/REPO.git && git push -u origin main`. |
