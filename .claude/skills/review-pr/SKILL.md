---
name: review-pr
description: "Process all open review comments on a PR: fix addressable issues, reply in-thread, create follow-up issues for deferred items"
disable-model-invocation: true
---

# Review PR — Process Review Feedback

Read all open review comments on a pull request, fix addressable issues, reply to each
comment thread with what was done, and create follow-up issues for items that need
deferral. Used by both the `/loop` pipeline and as a standalone skill for interactive
review processing.

## Input

`$ARGUMENTS` — optional PR number. Defaults to the PR for the current branch.

- `/review-pr` — process the current branch's PR
- `/review-pr 97` — process PR #97

---

## Step 0 — Read Configuration

Read `forge.toml`:

```toml
[project]
repo = "org/project"

[gating]
max_copilot_iterations = 3
```

Read `CLAUDE.md` for architecture conventions, testing requirements, and coding patterns.
All fixes must follow project conventions.

---

## Step 1 — Identify PR

If no PR number provided:

```bash
gh pr view --repo $REPO --json number,headRefName
```

If still ambiguous (multiple PRs for this branch), list them and ask the user to specify.

---

## Step 2 — Fetch All Open Review Feedback

Fetch formal reviews with `CHANGES_REQUESTED` or `COMMENTED` state:

```bash
gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" \
  --jq '[.[] | select(
    .state == "CHANGES_REQUESTED" or .state == "COMMENTED"
  ) | select(.user.login != "github-actions[bot]")
  | select(.body | length > 0)]
  | sort_by(.submitted_at) | .[-5:]'
```

Fetch inline comments not already replied to by this agent:

```bash
# Get all inline comments
ALL_COMMENTS=$(gh api "repos/$REPO/pulls/$PR_NUMBER/comments" \
  --jq '[.[] | select(.user.login != "github-actions[bot]")]')

# Get IDs of comments this agent has already replied to
REPLIED_TO=$(echo "$ALL_COMMENTS" \
  | jq '[.[] | select(.user.login == "claude[bot]" or .user.login == "github-actions[bot]")
         | .in_reply_to_id] | unique')

# Unresolved: top-level comments not already replied to
UNRESOLVED=$(echo "$ALL_COMMENTS" \
  | jq --argjson replied "$REPLIED_TO" \
    '[.[] | select(.in_reply_to_id == null)
           | select(.id as $id | $replied | index($id) | not)]
     | sort_by(.created_at) | .[-20:]')
```

---

## Step 3 — Triage Comments

For each comment, classify:

| Category | Criteria | Action |
|----------|----------|--------|
| **Fix now** | Bug, incorrect behavior, broken test, security issue, clear code error | Implement fix in Step 4 |
| **Discuss** | Design disagreement, ambiguous requirement, architectural tradeoff | Reply explaining the reasoning; create follow-up issue if significant |
| **Defer** | Scope creep, nice-to-have, out-of-scope for this PR | Reply noting it's deferred; create follow-up issue |
| **Already addressed** | The code has already been fixed by a prior commit | Reply with the commit SHA that addressed it |

Summarize the triage before fixing:

```
Found $TOTAL review comments on PR #$PR_NUMBER:
  Fix now:           $N (bugs, broken tests, clear errors)
  Discuss/explain:   $N (design choices to explain)
  Defer:             $N (out-of-scope, follow-up issues)
  Already addressed: $N
```

---

## Step 4 — Fix Addressable Comments

For each "fix now" comment:

1. Read the file at the referenced path and line
2. Understand the issue being raised
3. Implement the fix (edit the file)
4. Note the fix for the reply in Step 5

Follow all conventions from `CLAUDE.md`. If fixing a test, run the tests before proceeding
to the next comment to catch cascading failures early.

If a fix proves more complex than expected (requires architecture changes, affects multiple
files, or would expand the PR scope significantly), reclassify as "defer" and create a
follow-up issue instead.

---

## Step 5 — Run Verification

After all fixes are applied:

```bash
$TEST_COMMAND  # from forge.toml [stack]
$BUILD_COMMAND
```

If tests fail after fixes: investigate and fix. If still failing after 2 attempts,
revert the problematic fix and reclassify as "defer" with a note about why the fix
was reverted.

---

## Step 6 — Commit Fixes

```bash
git add -A
git commit -m "fix: address review feedback on PR #$PR_NUMBER

$(echo "$FIX_SUMMARY")"
git push
```

Use a concise commit message describing what was addressed in aggregate, not each
individual comment.

---

## Step 7 — Reply to Each Comment Thread

For every comment processed, post a reply in the comment thread. This is required —
it closes the loop for reviewers and makes it visible what was addressed vs. deferred.

```bash
# For inline comments
gh api -X POST \
  "repos/$REPO/pulls/comments/$COMMENT_ID/replies" \
  -f body="$REPLY_BODY"
```

Reply templates:

**Fixed:**
```
Fixed in $COMMIT_SHA — $ONE_LINE_DESCRIPTION_OF_WHAT_CHANGED.
```

**Deferred (follow-up filed):**
```
Good catch — deferred to #$FOLLOWUP_ISSUE_NUMBER to keep this PR focused.
```

**Discussed/explained:**
```
$EXPLANATION_OF_REASONING

Happy to revisit if this doesn't address the concern.
```

**Already addressed:**
```
This was addressed in $COMMIT_SHA (before this review was posted).
```

---

## Step 8 — Create Follow-up Issues

For each "defer" comment, create a GitHub issue:

```bash
gh issue create \
  --repo $REPO \
  --title "follow-up from PR #$PR_NUMBER: $SHORT_DESCRIPTION" \
  --label "backlog/needs-refinement" \
  --body "$(cat <<EOF
## Context

Raised as a review comment on PR #$PR_NUMBER by @$REVIEWER.

## Original comment

> $COMMENT_BODY

(File: $FILE_PATH, line $LINE_NUMBER)

## Why deferred

$DEFERRAL_REASON

## Acceptance criteria

$SUGGESTED_CRITERIA
EOF
)"
```

---

## Step 9 — Update PR Phase State

If the PR has an `autodev-state` tracker comment, increment `copilot_iterations`:

```bash
PR_BODY=$(gh pr view $PR_NUMBER --repo $REPO --json body --jq .body)
CURRENT_STATE=$(echo "$PR_BODY" | grep -oP '(?<=<!-- autodev-state: ).*?(?= -->)')
CURRENT_ITERS=$(echo "$CURRENT_STATE" | jq -r '.copilot_iterations // 0')
NEW_ITERS=$(( CURRENT_ITERS + 1 ))

NEW_STATE=$(echo "$CURRENT_STATE" | jq ". + {\"copilot_iterations\": $NEW_ITERS}")
UPDATED_BODY=$(echo "$PR_BODY" | sed "s|<!-- autodev-state: .*-->|<!-- autodev-state: $NEW_STATE -->|")
gh pr edit $PR_NUMBER --repo $REPO --body "$UPDATED_BODY"
```

---

## Step 10 — Summary Report

```
Review processing complete for PR #$PR_NUMBER.

  Fixed:    $FIX_COUNT comments addressed and committed ($COMMIT_SHA)
  Replied:  $REPLY_COUNT comment threads replied to
  Deferred: $DEFER_COUNT follow-up issues created (#$N1, #$N2, ...)
  Explained: $DISCUSS_COUNT design decisions explained inline

Iteration: $NEW_ITERS / $MAX_COPILOT_ITERATIONS
```

If `NEW_ITERS >= MAX_COPILOT_ITERATIONS`:
```
Max Copilot iterations reached. If there are still unresolved findings, they will be
handled in the Claude review phase. Run /loop or trigger claude-code-review.yml manually.
```

---

## Guardrails

- Never modify files listed in `forge.toml` `[protected_files]` patterns
- Never commit without running tests first
- Never reply "done" without a specific description of what changed
- Never create follow-up issues for already-addressed comments
- If the PR has no open comments at all, report that and exit cleanly
- Maximum fixes per run: determined by `max_copilot_iterations` — don't iterate
  indefinitely on a single PR
