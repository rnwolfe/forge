# forge

> Bootstrap any project with a full autonomous development lifecycle.

**forge** is a GitHub template repository that gives your project a battle-tested autonomous
development pipeline from day one. AI agents pick up issues, implement features, iterate on
review feedback, and prepare PRs for human merge — all without manual intervention.

## What You Get

- **5 GitHub Actions workflows** — dispatch, implement, review-fix, code review, audit
- **Automated review pipeline** — Copilot reviews (up to 3 iterations) → Claude review → human merge
- **13 Claude Code skills** — `/loop`, `/autodev`, `/review-pr`, `/product`, `/release`, and more
- **Living documentation system** — VISION.md, STATUS.md, CLAUDE.md maintained by skills
- **Configurable gating** — from full human control to fully autonomous, adjustable per-project

## Two Ways to Run

forge supports two execution modes that share the same config and produce identical results:

### GitHub Actions pipeline (always-on, server-side)

Issues labeled `backlog/ready` are picked up by a cron-triggered workflow, implemented
by the agent, reviewed, and queued for merge — all without your laptop open. Runs
entirely in your repo's GitHub Actions environment.

```
label backlog/ready → autodev-dispatch → autodev-implement → autodev-review-fix → human merge
```

### Agent-native loop (interactive, long-horizon)

Run the full pipeline as a single Claude Code session. Useful for watching the agent work,
intervening on complex issues, or running sustained autonomous sprints directly from your
machine.

```
/loop --max-hours 8 --sweep
```

This orchestrates: sweep → dispatch → implement → review → await CI → merge → repeat.
Each step runs as a focused sub-agent. The loop can process many issues over hours or
days, checkpointing state between issues so it can resume if interrupted.

## Quick Start

1. **Use this template** — Click "Use this template" on GitHub to create your repo

2. **Run the onboarding skill**:
   ```
   /onboard
   ```
   This interactive conversation generates your project's CLAUDE.md, VISION.md, CI workflow,
   and configures GitHub labels and branch protection.

3. **Create your first issue** with clear acceptance criteria

4. **Label it `backlog/ready`** — the pipeline picks it up within an hour, or run it
   immediately with `/autodev` or `/loop`

## Keeping Up to Date

As forge improves, you can pull the latest skills, autodev scripts, and workflow fixes into
any project that was scaffolded from it.

### New projects

`/onboard` writes `.forge/manifest.json` automatically, recording the forge commit your
project was scaffolded from. To sync:

```bash
./scripts/forge-sync.sh              # apply latest forge updates
./scripts/forge-sync.sh --dry-run    # preview the diff first
```

### Existing projects (scaffolded before forge-sync)

Bootstrap with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/rnwolfe/forge/main/setup/bootstrap.sh | bash
```

This downloads `forge-sync.sh` and runs `--init`, which diffs forge's entire history
against your project and applies everything missing — new skills, updated scripts, new
workflows. Existing files you've modified are 3-way merged, so local changes are
preserved where possible.

### Automatic weekly sync (optional)

To have a PR opened automatically whenever forge has upstream changes:

```bash
./scripts/forge-sync.sh --install-action
git add .github/workflows/forge-sync.yml
git commit -m "ci: add weekly forge template sync"
```

**What gets synced**: `.claude/skills/`, `scripts/autodev/`, and the five forge-owned
workflows. **Never touched**: `forge.toml`, `CLAUDE.md`, `VISION.md`, `ci.yml`, or
anything else project-specific.

## Configuration

All pipeline settings live in `forge.toml`:

```toml
[project]
name = "myproject"
repo = "org/myproject"

[stack]
language = "go"
build_command = "make build"
test_command = "make test"

[gating]
human_merge_required = true  # Start with full human control

[loop]
ci_poll_interval_minutes = 5   # How often to check CI while waiting
ci_timeout_minutes = 60        # Give up waiting for CI after this long
max_failures_before_stop = 3   # Circuit breaker: stop loop after N consecutive failures

[steps]
# Per-step provider/model overrides (optional)
# implement_model = "claude-opus-4-6"   # Best quality for implementation
# review_model = "claude-sonnet-4-6"    # Faster for review iteration
```

See `forge.toml` for all available options with documentation.

## Gating Levels

| Level | Description | Config |
|-------|-------------|--------|
| 1 (default) | Agent implements → reviews → human merges | `human_merge_required = true` |
| 2 | Same + auto-merge after human approves | `auto_merge_after_review = true` |
| 3 | Human reviews only sensitive files | `require_human_review_for = ["*.yml"]` |
| 4 | Fully autonomous | `require_human_review_for = []` |

## Skills Reference

### Pipeline skills

| Skill | Purpose |
|-------|---------|
| `/loop` | End-to-end autonomous loop — dispatch → implement → review → CI → merge, repeating across multiple issues |
| `/autodev` | Pick a single issue and implement it end-to-end |
| `/dispatch` | Claim the next backlog issue and prepare its branch, without implementing |
| `/review-pr` | Process open review comments: fix code, reply in-thread, create follow-up issues |
| `/await-ci` | Wait for a PR's CI checks to pass or fail, with configurable timeout |
| `/merge-pr` | Final pre-merge check and squash-merge (or label for human merge) |

### Product skills

| Skill | Purpose |
|-------|---------|
| `/onboard` | Interactive project bootstrapping |
| `/product` | Roadmap health check and strategic planning |
| `/brainstorm` | Generate feature ideas |
| `/draft-issue` | Turn an idea into a structured issue |
| `/sweep-issues` | Audit backlog quality |
| `/refine-issue` | Improve an issue iteratively |
| `/release` | Cut a release with CHANGELOG and tagging |

## Required Secrets

| Secret | Purpose |
|--------|---------|
| `CLAUDE_CODE_OAUTH_TOKEN` | OAuth token for Claude Code agent execution |
| `APP_ID` + `APP_PRIVATE_KEY` | GitHub App for push/PR operations (GH Actions pipeline only) |

## Documentation

- `CLAUDE.md` — Project knowledge base (generated by `/onboard`)
- `docs/internal/VISION.md` — Product vision and design principles
- `docs/internal/LIFECYCLE.md` — Full development lifecycle
- `docs/internal/autodev-pipeline.md` — Pipeline architecture deep dive
- `forge.toml` — Pipeline configuration

## License

MIT
