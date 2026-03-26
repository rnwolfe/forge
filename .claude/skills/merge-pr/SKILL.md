---
name: merge-pr
description: "Perform a final review check on a PR and merge it if clean, or report what's blocking"
disable-model-invocation: true
---

# Merge PR — Final Check and Merge

Perform a final pre-merge verification on a pull request and merge it if everything
is clean. Designed to be the last step in the `/forge-loop` pipeline, or run standalone
after human review.

## Input

`$ARGUMENTS` — PR number (required).

- `/merge-pr 97` — verify and merge PR #97

---

## Step 0 — Read Configuration

Read `forge.toml`:

```toml
[project]
repo = "org/project"

[gating]
human_merge_required = true      # If true: report ready-to-merge but do NOT merge
auto_merge_after_review = false  # If true: merge immediately when checks pass
require_human_review_for = ["*"] # Glob patterns requiring human sign-off
```

---

## Step 1 — PR Status Check

```bash
gh pr view $PR_NUMBER --repo $REPO \
  --json number,title,state,mergeable,mergeStateStatus,labels,reviewDecision,statusCheckRollup
```

Check each gate in order, stopping at the first failure:

| Gate | Check | Blocking? |
|------|-------|-----------|
| PR open | `state == "OPEN"` | Yes |
| Not already labeled blocked | No `human/blocked` label | Yes |
| CI green | `mergeStateStatus == "CLEAN"` or all checks passed | Yes |
| No outstanding reviews | `reviewDecision != "CHANGES_REQUESTED"` | Yes |
| Mergeable | `mergeable == "MERGEABLE"` | Yes |

---

## Step 2 — Review Pending Comments

Fetch open review comments to check for unresolved threads:

```bash
gh api "repos/$REPO/pulls/$PR_NUMBER/comments" \
  --jq '[.[] | select(.user.login != "github-actions[bot]")] | length'
```

If there are unresolved comments **and** `require_human_review_for` patterns match files
in this PR's diff, note them in the report but do NOT block the merge (they were
already processed by `/review-pr`).

---

## Step 3 — Decide: Merge or Report

### If `human_merge_required = true`

Do NOT merge. Label the PR and report:

```bash
gh pr edit $PR_NUMBER --repo $REPO --add-label "human/review-merge"
```

```
PR #$PR_NUMBER is ready to merge.

  Title:  $TITLE
  Branch: $BRANCH → $BASE
  CI:     All checks passed
  Labels: human/review-merge applied

Merge when ready:
  gh pr merge $PR_NUMBER --repo $REPO --squash --delete-branch
```

### If `human_merge_required = false` (auto-merge enabled)

Merge immediately:

```bash
gh pr merge $PR_NUMBER \
  --repo $REPO \
  --squash \
  --delete-branch \
  --subject "$PR_TITLE" \
  --body "Closes #$ISSUE_NUMBER"
```

Report:

```
Merged PR #$PR_NUMBER: $TITLE
  Merged as: squash commit
  Branch deleted: $BRANCH
  Issue closed: #$ISSUE_NUMBER (if referenced in PR body)
```

Clean up the local worktree if it still exists:

```bash
WORKTREE_PATH=".worktrees/issue-${ISSUE_NUMBER}-${SLUG}"
if git worktree list | grep -q "$WORKTREE_PATH"; then
  git worktree remove "$WORKTREE_PATH"
fi
```

---

## Step 4 — Blocking Report (if any gate failed)

If any gate fails, report clearly what's blocking and what action is needed:

```
PR #$PR_NUMBER cannot be merged yet.

  Blocking:
    - CI: 2 checks failing
        test (ubuntu-latest): FAILURE — https://...
    - Review: 1 CHANGES_REQUESTED review pending

  Next steps:
    1. Fix failing tests — run /review-pr $PR_NUMBER to process the feedback
    2. Address CHANGES_REQUESTED from @reviewer
    3. Re-run /merge-pr $PR_NUMBER when resolved
```

Label with `human/blocked` if the blockage requires human judgment:

```bash
gh pr edit $PR_NUMBER --repo $REPO --add-label "human/blocked"
```

---

## Guardrails

- Never merge a PR with failing CI
- Never merge if `human_merge_required = true` — only label
- Never force-merge or bypass required reviews
- Never delete the base branch
- If merge fails due to conflict: report the conflict, do not attempt to resolve it automatically
