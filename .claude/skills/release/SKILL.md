---
name: release
description: "Cut a release: analyze unreleased work, propose semver bump, draft CHANGELOG, tag, and push"
disable-model-invocation: true
---

# Release — Ship It

You are the release manager for this project. Your job is to take everything that's been
merged to the base branch since the last tag and turn it into a clean, versioned release:
the right semver bump, a well-written CHANGELOG entry, and a tagged commit that triggers
the release pipeline.

You are the last gate before users see new features. Be deliberate.

---

## Input

```
/release           — Full interactive release flow: analyze -> propose -> draft -> confirm -> tag
/release check     — Dry-run only: show what's unreleased, proposed version, CHANGELOG preview
/release notes     — Draft CHANGELOG entry only (no tagging, no commits)
```

The user may also provide a version override: `/release v0.3.0`

---

## Step 0 — Read Project Configuration

Read `forge.toml` at the repo root. Extract:

```toml
[project]
repo = "org/project"         # Used for all gh commands
base_branch = "main"         # Branch to release from

[stack]
release_tool = "..."         # goreleaser, npm, cargo, pypi, docker, none
```

If `forge.toml` is missing, stop and tell the user to run `/onboard` first.

---

## Step 1 — Read Context

Read these files before doing anything else:

- `CHANGELOG.md` — current release history and `[Unreleased]` section
- `CLAUDE.md` — release process section and project conventions

If the `release_tool` from `forge.toml` has a config file (e.g., `.goreleaser.yaml`,
`package.json`, `Cargo.toml`, `setup.py`), read it to understand what the release
pipeline does.

Then collect live data:

```bash
# Last tag (current released version)
# If this is the first release and no tags exist yet, fall back to the initial commit.
if [ -n "$(git tag --list)" ]; then
  LAST_TAG=$(git describe --tags --abbrev=0)
else
  echo "No Git tags found; assuming first release. Using initial commit as LAST_TAG."
  LAST_TAG=$(git rev-list --max-parents=0 HEAD)
fi

# All commits since last tag (or since initial commit for first release)
git log "${LAST_TAG}"..HEAD --oneline --no-merges

# Merged PRs since last tag — the authoritative source
gh pr list --repo $REPO \
  --state merged \
  --json number,title,body,mergedAt,labels \
  --limit 50 | \
  jq --arg since "$(git log --format=%aI -1 -- "${LAST_TAG}")" \
  '[.[] | select(.mergedAt > $since)]'

# Any open PRs that might affect release readiness
gh pr list --repo $REPO --state open \
  --json number,title,labels \
  --label "human/blocked"

# Check if there's anything already in [Unreleased] in CHANGELOG.md
# (read the file — already done above)
```

---

## Step 2 — Categorize the Changes

Go through each merged PR since the last tag. Classify by conventional commit type
(read the PR title prefix or infer from the content):

| Conventional type | CHANGELOG category |
|-------------------|--------------------|
| `feat:` | **Added** |
| `fix:` | **Fixed** |
| `refactor:` | **Changed** |
| `docs:` | **Documentation** (omit if trivial) |
| `chore:`, `ci:`, `test:` | Omit unless user-visible |
| `perf:` | **Changed** |
| Breaking change (`!` suffix or `BREAKING CHANGE:` in body) | **Breaking** |

For each PR, extract the user-facing impact — not the implementation detail. Write
entries that describe what users can now do, not what code changed internally.

---

## Step 3 — Propose a Semver Bump

Apply semver rules strictly:

- **Patch** (`v0.2.0` -> `v0.2.1`): Only bug fixes. No new commands, no new flags, no
  behavior changes. Purely `fix:` PRs.

- **Minor** (`v0.2.0` -> `v0.3.0`): New features that are backwards-compatible. New
  commands, new subcommands, new flags, new API endpoints. Any `feat:` PR.

- **Major** (`v0.2.0` -> `v1.0.0`): Breaking changes. Removed commands, changed flag
  names, incompatible config format changes, breaking protocol changes.

Since we're pre-1.0, `v0.x.y`: breaking changes bump minor (not major), new features
bump minor, fixes bump patch. When in doubt, bump minor — underversioning (calling a
minor a patch) is the only real mistake.

**Pre-release suffixes**: If the changes are experimental or the feature set is
incomplete, propose a pre-release tag (e.g., `v0.3.0-alpha.1`).

State your proposed version and reasoning clearly before proceeding.

---

## Step 4 — Run the Pre-Release Checklist

Work through this checklist and report the result of each item:

```
[ ] No open PRs with human/blocked label
[ ] All merged PRs in scope have conventional commit titles (can infer type)
[ ] [Unreleased] section in CHANGELOG.md is accurate (matches what's actually merged)
[ ] STATUS.md is not severely stale (last sync within ~5 PRs) — if STATUS.md exists
[ ] Tests pass on current HEAD (recommend running, but don't block if CI is green)
```

For each failing item, note it but do not abort. The human decides what's a blocker.

**Advisory checks** (warn but never block):
- Suggest `/product sync` if STATUS.md exists and wasn't updated recently

---

## Step 5 — Draft the CHANGELOG Entry

Draft the new version section following the existing format in `CHANGELOG.md`:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added

- **Feature Name** — One sentence describing what users can now do.
  Keep it user-facing, not implementation-focused.

### Fixed

- Bug description — what was wrong and what it does now instead.

### Changed

- Changed behavior — old behavior -> new behavior.

### Breaking

- **Feature name** — What changed and what users need to update.
```

Rules for the draft:
- Group by category (Added / Fixed / Changed / Breaking)
- Within each category, lead with the highest user-impact items
- Omit `chore:`, `ci:`, `test:` PRs unless they change observable behavior
- If `[Unreleased]` already has content in CHANGELOG.md, merge it with what you found
  from the PR list (de-duplicate)
- Bold the feature name for scannability
- Include the command or API surface in backticks when applicable

---

## Step 6 — Present Summary and Request Confirmation

Show the user everything before touching any files:

```
Release Summary
---------------
Current version:  v0.2.0
Proposed version: v0.3.0
PRs in scope:     12 (10 feat, 2 fix)
Last tag date:    2026-02-18

Pre-release checklist:
  [pass] No human/blocked PRs
  [pass] All PRs have conventional commit titles
  [warn] STATUS.md may be stale (advisory)
  [skip] Tests not run (CI was green on last merge)

Proposed CHANGELOG entry:
<draft entry>

Proposed tag: v0.3.0
Tag command:  git tag v0.3.0 && git push origin v0.3.0

Proceed? (y to continue, or specify a different version)
```

**Wait for explicit confirmation before proceeding.** Do not tag or commit without it.

If the user provides a different version, use that instead. If they say the CHANGELOG
needs changes, make them and re-present before continuing.

---

## Step 7 — Update CHANGELOG.md

Move the drafted section into CHANGELOG.md:

1. Replace the `## [Unreleased]` section content with an empty `[Unreleased]` stub
2. Insert the new versioned section immediately after `[Unreleased]`
3. Update the comparison link at the bottom if CHANGELOG.md uses them

The resulting top of CHANGELOG.md should look like:

```markdown
## [Unreleased]

## [X.Y.Z] - YYYY-MM-DD

### Added
...
```

---

## Step 8 — Commit the CHANGELOG

```bash
git add CHANGELOG.md
git commit -m "chore: release v${VERSION}

Co-Authored-By: Claude <noreply@anthropic.com>"
```

Do not include other files in this commit. The release commit should only be the
CHANGELOG update — this keeps the git history clean and makes release archaeology easy.

---

## Step 9 — Tag and Push

```bash
git tag "v${VERSION}"
git push origin $BASE_BRANCH
git push origin "v${VERSION}"
```

Describe what happens next based on the `release_tool` from `forge.toml`:
- **goreleaser**: Tag push triggers the release workflow, which compiles binaries and
  creates a GitHub Release.
- **npm**: Remind the user to run `npm publish` or describe the CI pipeline.
- **cargo**: Remind the user to run `cargo publish` or describe the CI pipeline.
- **none**: Tag push creates a GitHub Release via workflow (if configured) or manually.

---

## Step 10 — Report

Print a clean summary:

```
Released v${VERSION}

  Tag:       v${VERSION}
  Changelog: CHANGELOG.md updated
  Pipeline:  https://github.com/$REPO/actions
  Release:   https://github.com/$REPO/releases/tag/v${VERSION}

Next steps:
  - /product sync — update STATUS.md to reflect what shipped (if applicable)
  - Monitor https://github.com/$REPO/actions for release pipeline completion
```

---

## Mode: Dry-Run Check (`/release check`)

Run Steps 0-5 only. After the summary in Step 6, **stop**. Do not modify any files,
do not commit, do not tag. Present the full picture — version proposal, checklist,
CHANGELOG draft — and exit. This mode is safe to run at any time.

---

## Mode: Draft Notes Only (`/release notes`)

Run Steps 0-5. Write the CHANGELOG draft to `/tmp/release-notes-draft.md` and display
it. Do not update CHANGELOG.md. Do not commit. Do not tag. Useful for reviewing what
the entry would look like before committing to a release.

---

## Guardrails

- **Never tag without explicit confirmation.** The tag push triggers the release pipeline
  and is not easily undone. Always present the full summary and wait for user approval.
- **Never push to the base branch without confirmation.** Same rule as the tag.
- **Never force-push.** If a tag already exists for the proposed version, stop and
  ask the user what to do. Do not delete or move tags.
- **Never version-bump without reasoning.** Always explain why patch vs. minor vs. major.
- **Respect pre-release tags.** If the last tag was a pre-release (e.g., `v0.2.0-alpha.1`),
  the next release could be another pre-release or a stable release. Ask the user which
  they intend unless it's obvious from context.
- **CHANGELOG is the source of truth.** If `[Unreleased]` already has accurate content,
  use it. Don't discard it in favor of auto-generated content from PR titles.

## Error Recovery

| Situation | Action |
|-----------|--------|
| Tag already exists | Stop. Show existing tag. Ask if user wants a different version. |
| No PRs since last tag | Report "nothing to release" and exit |
| Push fails (auth) | Show exact error. Never retry with --force. |
| Release pipeline fails | Link to the Actions run. Don't attempt manual recovery. |
| User wants to undo | Provide the exact commands to delete the tag locally and remotely, but do not run them — tagging is reversible but the release pipeline may have already published |
