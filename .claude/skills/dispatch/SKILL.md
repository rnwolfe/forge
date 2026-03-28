---
name: dispatch
description: "Pick the next backlog/ready issue, claim it, and prepare a branch — without implementing it"
disable-model-invocation: true
---

# Dispatch — Claim the Next Issue

Pick the highest-priority `backlog/ready` issue, label it `agent/implementing`, create the
feature branch, and report back the issue number and branch name. Does NOT implement.

Used by `/forge-loop` to separate "what to work on next" from "do the work". Can also be run
standalone to claim an issue and hand off to a human or a different agent.

## Input

`$ARGUMENTS` — optional issue number.

- `/dispatch` — auto-pick highest-priority `backlog/ready` issue
- `/dispatch 42` — claim a specific issue

---

## Step 0 — Read Configuration

Read `forge.toml`:

```toml
[project]
repo = "org/project"
base_branch = "main"

[dispatch]
max_concurrent_prs = 1

[trust]
trusted_users = [...]
```

If `forge.toml` is missing, stop and tell the user to run `/onboard` first.

---

## Step 1 — Concurrency Guard

```bash
OPEN_COUNT=$(gh pr list --repo $REPO \
  --state open --json number,labels \
  --jq '[.[] | select(
    (.labels | map(.name) | any(startswith("via/")))
    and (.labels | map(.name) | any(. == "human/blocked") | not)
  )] | length')
```

If `$OPEN_COUNT >= max_concurrent_prs`, stop:

```
Dispatch skipped: $OPEN_COUNT open autodev PR(s) already in flight (max $MAX).
Open PRs: <list titles and numbers>
```

Ask the user if they want to override the concurrency limit.

---

## Step 2 — Select Issue

### If an issue number was provided

```bash
gh issue view $ISSUE_NUMBER --repo $REPO --json number,title,body,labels,state
```

Validate:
- Issue is open
- Not already labeled `agent/implementing` or `human/blocked`
- Has `backlog/ready` label (warn if missing — user is overriding)

### If no issue number was provided

```bash
gh issue list --repo $REPO \
  --label "backlog/ready" \
  --state open \
  --json number,title,labels \
  --limit 30
```

Filter out issues with `agent/implementing` or `human/blocked` labels. Sort by:
1. `priority/critical` first
2. `priority/high` second
3. Lowest issue number as tiebreaker

Present the top choice with a 1-sentence rationale. If running non-interactively (e.g.,
called by `/forge-loop`), skip the confirmation and proceed.

---

## Step 2.5 — Parent Issue Resolution

If the selected issue has child issues, navigate to the next unblocked leaf child.
See `/autodev` Step 2.5 for the full parent resolution algorithm. Apply it here identically.

---

## Step 3 — Claim and Prepare Branch

Label the issue:

```bash
gh issue edit $ISSUE_NUMBER --repo $REPO --add-label "agent/implementing"
```

Compute the branch name:

```bash
ISSUE_TITLE=$(gh issue view $ISSUE_NUMBER --repo $REPO --json title --jq .title)
SLUG=$(echo "$ISSUE_TITLE" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g' \
  | sed -E 's/^-+|-+$//g' \
  | cut -c1-50)
BRANCH="autodev/issue-${ISSUE_NUMBER}-${SLUG}"
```

Check for stale remote branch and clean up:

```bash
git ls-remote --exit-code origin "refs/heads/$BRANCH" 2>/dev/null && \
  git push origin --delete "$BRANCH" || true
```

Fetch and create the worktree:

```bash
git fetch origin $BASE_BRANCH
WORKTREE_PATH=".worktrees/${BRANCH##autodev/}"
git worktree add -b "$BRANCH" "$WORKTREE_PATH" origin/$BASE_BRANCH
```

---

## Step 4 — Report

Print a machine-readable summary (parseable by `/forge-loop`):

```
DISPATCH_ISSUE=$ISSUE_NUMBER
DISPATCH_TITLE=$ISSUE_TITLE
DISPATCH_BRANCH=$BRANCH
DISPATCH_WORKTREE=$WORKTREE_PATH
```

Then a human-readable summary:

```
Claimed #$ISSUE_NUMBER: $ISSUE_TITLE
  Branch:   $BRANCH
  Worktree: $WORKTREE_PATH

Next step: run /autodev $ISSUE_NUMBER to implement, or /forge-loop to run the full pipeline.
```

---

## Guardrails

- Never claim an issue already labeled `agent/implementing` or `human/blocked`
- Never create the worktree outside `.worktrees/`
- Never push to the base branch
- If the worktree already exists, remove and recreate: `git worktree remove --force $WORKTREE_PATH`
