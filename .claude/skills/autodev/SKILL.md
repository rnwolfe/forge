---
name: autodev
description: "Pick an issue from the backlog, implement it in a fresh worktree, and open a PR"
disable-model-invocation: true
---

# Autodev — Autonomous Implementation from the CLI

You are autonomously implementing a GitHub issue end-to-end: pick an issue, create a
fresh worktree, implement it, verify it, and open a PR.

## Input

The user may provide an issue number as an argument: `$ARGUMENTS`

- `/autodev` — auto-pick the highest-value `backlog/ready` issue
- `/autodev 42` — implement a specific issue number
- `/autodev 42 "custom branch suffix"` — optional branch name override

---

## Step 0 — Read Project Configuration

Before anything else, read `forge.toml` at the repo root. Extract these values and use
them throughout:

```toml
[project]
repo = "org/project"         # Used for all gh commands
base_branch = "main"         # Used for worktree base and PR target

[stack]
build_command = "..."        # Used in Step 6 verification
test_command = "..."         # Used in Step 6 verification

[protected_files]
patterns = [...]             # Files you must NOT modify
```

If `forge.toml` is missing or incomplete, stop and tell the user to run `/onboard` first.

---

## Step 1 — Read Project Context

Read `CLAUDE.md` for architecture patterns, design principles, key files, coding
conventions, and any project-specific workflows. This is your operating manual for this
project. Follow every convention it specifies.

---

## Step 2 — Select an Issue

### If an issue number was provided

```bash
gh issue view $ISSUE_NUMBER --repo $REPO --json number,title,body,labels,state
```

Validate:
- Issue is open
- Issue has the `backlog/ready` label (warn but proceed if missing — the user is overriding)
- Issue is not already `agent/implementing` (abort if it is and tell the user why)

**Then check if it's a parent issue** — proceed to Step 2.5.

### If no issue number was provided

**Check concurrency guard first:**

```bash
gh pr list --repo $REPO --label "via/autodev" --state open --json number,title
```

If there's already 1 or more open `via/autodev` PRs, **stop and report** what's in flight. Do
not start new work when there are open autodev PRs. Ask the user if they want to override.

**Fetch candidates:**

```bash
gh issue list --repo $REPO \
  --label "backlog/ready" \
  --state open \
  --json number,title,body,labels \
  --limit 30
```

Filter out any issues that already have the `agent/implementing` label.

If no `backlog/ready` issues exist, broaden the search:

```bash
gh issue list --repo $REPO \
  --state open \
  --label "feature" \
  --json number,title,body,labels \
  --limit 20
```

**Evaluate and pick** the highest-value issue. Consider:
- Concrete acceptance criteria (easier to verify = lower risk)
- Self-contained scope (touches one domain, not multiple systems)
- User-visible impact
- Dependencies: avoid issues blocked by other open issues
- Avoid issues with `human/blocked`, `blocked`, or `wip` labels

**Before committing to any candidate, check if it's a parent issue** — proceed to Step 2.5.

Present your selection with a brief rationale (1-2 sentences) before proceeding.
Give the user a moment to redirect if they disagree — but do not wait for approval
unless this is an interactive session. If non-interactive, proceed.

---

## Step 2.5 — Parent Issue Resolution

Parent issues (epics) should never be implemented directly — they are umbrellas that
decompose into implementable child issues. This step detects parent/child relationships
and navigates to the right child to execute.

### Detect child issues

Search for open issues that reference the selected issue as their parent:

```bash
gh issue list --repo $REPO --state open --limit 50 \
  --json number,title,body,labels,state \
  --jq '[.[] | select(.body | test("\\*\\*Parent issue\\*\\*.*#'"$ISSUE_NUMBER"'"))]'
```

Also check the GitHub sub-issues API (native sub-issues):

```bash
gh api graphql -f query='
{
  repository(owner: "'"$OWNER"'", name: "'"$REPO_NAME"'") {
    issue(number: '"$ISSUE_NUMBER"') {
      subIssues(first: 50) {
        nodes { number title state }
      }
    }
  }
}'
```

Merge results from both methods (deduplicate by issue number).

### If the issue has children → navigate, don't implement

**Do NOT implement the parent issue.** Instead:

1. **List all child issues** with their state (open/closed) and dependency info.

2. **Read each open child's Dependencies section** to build a dependency graph.
   Dependencies are expressed as:
   - `Depends on #N` or `- #N (description)` in a `## Dependencies` section
   - References to sibling sub-issues by title or number
   - `None` means no blockers

3. **Identify the next implementable child** — an open child whose dependencies are
   all satisfied (closed or merged). Apply the same selection criteria as Step 2:
   - Has `backlog/ready` label (preferred) or is well-specified
   - Not `agent/implementing`, `human/blocked`, `blocked`, or `wip`
   - Concrete acceptance criteria
   - Self-contained scope

4. **If multiple children are unblocked**, pick by:
   - Foundation layers first (issues with no dependencies, or those that unblock others)
   - Lowest issue number as tiebreaker (usually reflects intended ordering)

5. **If no children are unblocked** (all remaining open children have unsatisfied
   dependencies), report the blockage:
   ```
   Parent #$ISSUE_NUMBER has N open children, but all are blocked:
     #72 — blocked by #70 (open), #71 (open)
     #75 — blocked by #72 (open), #73 (open), #74 (open)
   ```
   Stop and let the user decide.

6. **Replace `$ISSUE_NUMBER`** with the selected child and continue to Step 3.
   Log the navigation:
   ```
   Parent #59: "Advanced visual editing with smart selection & inpainting"
     → Navigating to child #69: "SAM segmentation service in ai-service"
       (foundation layer, no dependencies, backlog/ready)
   ```

### If the issue has no children → proceed normally

Continue to Step 3 with the original issue.

### Recursive parents

If the selected child itself has children, apply this step recursively until you reach
a leaf issue (one with no children). Leaf issues are the ones you implement.

---

## Step 3 — Mark In-Progress and Prepare Branch

```bash
ISSUE_NUMBER=<picked number>
ISSUE_TITLE=$(gh issue view $ISSUE_NUMBER --repo $REPO --json title --jq .title)

# Slugify the title (lowercase, hyphens, max 50 chars)
SLUG=$(echo "$ISSUE_TITLE" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g' \
  | sed -E 's/^-+|-+$//g' \
  | cut -c1-50)

BRANCH="autodev/issue-${ISSUE_NUMBER}-${SLUG}"
```

Mark the issue in-progress:

```bash
gh issue edit $ISSUE_NUMBER --repo $REPO --add-label "agent/implementing"
```

---

## Step 4 — Create a Fresh Worktree

Ensure the base branch is up to date:

```bash
git fetch origin $BASE_BRANCH
```

Create a worktree branching from `origin/$BASE_BRANCH` (not local, which may be stale):

```bash
WORKTREE_PATH=".worktrees/${BRANCH##autodev/}"
git worktree add -b "$BRANCH" "$WORKTREE_PATH" origin/$BASE_BRANCH
```

All implementation work happens in `$WORKTREE_PATH`. Use absolute paths when reading
and writing files. Use `cd <worktree>` prefix for build/test commands.

---

## Step 5 — Implement the Issue

Read the full issue body:

```bash
gh issue view $ISSUE_NUMBER --repo $REPO --json body --jq .body
```

Then implement. Follow all conventions from CLAUDE.md:

- Match existing code patterns (look at similar code before writing new code)
- Write tests next to the code they test
- Follow the project's file organization and naming conventions
- Do NOT modify any files listed in `forge.toml` `[protected_files]` patterns

**Read before writing.** Before creating or editing any file, read the existing file
first to understand the current state. Explore related files to match patterns.

---

## Step 5.5 — Pre-Commit Quality Review

Before running tests, review your implementation against these checks:

**Reference implementation**: If the issue cites a reference file or pattern, verify
you read it and matched its style. Check: error handling, input validation, output
formatting, test patterns.

**Testing quality**:
- Tests exercise the actual behavior, not just internal helpers
- Error paths are tested end-to-end, not just at the helper level
- External tools are mocked appropriately for the project's testing patterns

**Error handling**:
- Invalid input errors include the expected format/pattern
- Errors are wrapped with operation context
- User-facing errors say what went wrong AND what to do about it

**Documentation completeness**:
- CLAUDE.md updated if new patterns or key files were added
- Any project-specific docs referenced in the issue are updated
- README or user-facing docs updated if the issue requires it

---

## Step 6 — Verify

From the worktree directory, run the project's test and build commands from `forge.toml`:

```bash
cd $WORKTREE_PATH && $TEST_COMMAND
cd $WORKTREE_PATH && $BUILD_COMMAND
```

If tests fail: fix them. Do not open a PR with failing tests.
If build fails: fix it. Do not open a PR that doesn't build.

If you cannot make tests pass after a reasonable attempt (2-3 iterations), add the
`human/blocked` label and stop:

```bash
gh issue edit $ISSUE_NUMBER --repo $REPO \
  --add-label "human/blocked" \
  --remove-label "agent/implementing"
```

---

## Step 7 — Commit

Stage and commit all changes. `git add -A` is safe here because the worktree
is an isolated copy containing only intentional changes — no risk of staging
sensitive files or unrelated work.

```bash
cd $WORKTREE_PATH
git add -A
git commit -m "$(cat <<EOF
feat: implement #${ISSUE_NUMBER} — ${ISSUE_TITLE}

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

Use conventional commit types: `feat`, `fix`, `refactor`, `test`, `docs`.
For bugs, use `fix:`. For new features, use `feat:`. Keep the first line under 72 chars.

---

## Step 8 — Write PR Description

Write a detailed PR description to `/tmp/pr-description-${ISSUE_NUMBER}.md`:

```markdown
## Summary

<2-4 sentences: what was implemented and why>

Closes #$ISSUE_NUMBER

## Changes

- **New files**: list each new file and its purpose
- **Modified files**: list each modified file and what changed
- **Architecture**: any design decisions or patterns used

## Test Coverage

- Unit tests for ...
- Edge cases covered: ...

## Acceptance Criteria

<Verify each criterion from the issue:>
- [x] Criterion — how it was met
- [ ] Criterion — why it was not met (note as follow-up issue if significant)
```

---

## Step 9 — Push and Open PR

Push the branch:

```bash
cd $WORKTREE_PATH
git push -u origin "$BRANCH"
```

Create the PR:

```bash
gh pr create \
  --repo $REPO \
  --head "$BRANCH" \
  --base $BASE_BRANCH \
  --title "$ISSUE_TITLE" \
  --body "$(cat /tmp/pr-description-${ISSUE_NUMBER}.md)

<!-- autodev-state: {\"phase\": \"copilot\", \"copilot_iterations\": 0} -->" \
  --label "via/autodev"
```

---

## Step 10 — Report

Print a clean summary:

```
Implemented #$ISSUE_NUMBER: $ISSUE_TITLE
  Branch:    $BRANCH
  Worktree:  $WORKTREE_PATH
  PR:        <PR URL>

The worktree is at .worktrees/<name>. Run `git worktree list` to see it.
To clean up after merge: git worktree remove .worktrees/<name>
```

---

## Guardrails

- **One PR at a time**: If a `via/autodev` PR is already open, report it and stop.
- **Never force-push the base branch**: Only push to the new feature branch.
- **Never modify protected files**: Check `forge.toml` `[protected_files]` patterns.
- **Tests must pass**: Never open a PR with failing tests or a broken build.
- **Verify acceptance criteria**: Read the issue's acceptance criteria and check each one
  in the PR description — don't just implement and hope.
- **Worktree hygiene**: Always create the worktree inside `.worktrees/`. Never create
  worktrees at the repo root or outside the project directory.
- **Stale branches**: Before creating the branch, check if it already exists remotely:
  ```bash
  git ls-remote --exit-code origin "refs/heads/$BRANCH" 2>/dev/null && \
    git push origin --delete "$BRANCH" || true
  ```

## Error Recovery

| Situation | Action |
|-----------|--------|
| Tests fail after 3 attempts | Add `human/blocked` label, clean up worktree, report to user |
| Issue has no acceptance criteria | Note it in PR, implement based on title/description |
| No `backlog/ready` issues exist | Broaden to open `feature`/`enhancement` issues, pick highest value |
| Worktree already exists | Remove it first: `git worktree remove --force <path>`, then recreate |
| Push fails (auth) | Report the error — never force-push or bypass auth |
| `forge.toml` missing or incomplete | Stop and tell the user to run `/onboard` or fill in the config |
