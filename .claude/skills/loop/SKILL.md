---
name: loop
description: "Run the full forge pipeline end-to-end within this Claude Code session, processing multiple issues autonomously until a stop condition is met"
disable-model-invocation: true
---

# Loop — Long-Horizon Autonomous Development

Run the complete forge pipeline entirely within this Claude Code session. Pick issues,
implement them, process review feedback, wait for CI, and merge — then repeat. Continue
until a stop condition is reached or you are interrupted.

This is the agent-native alternative to the GitHub Actions pipeline. Each major step
runs as a sub-agent with focused context. The loop itself is a thin orchestrator that
manages state and sequences the steps.

## Input

`$ARGUMENTS` — flags controlling the run.

```
/loop                               # Run until no more backlog/ready issues
/loop --max-issues 5                # Stop after 5 issues
/loop --max-hours 8                 # Stop after 8 hours
/loop --issues "#42,#43,#44"        # Process specific issues in this order
/loop --sweep                       # Run /sweep-issues before starting
/loop --no-merge                    # Stop before merge (human merges)
/loop --dry-run                     # Plan only: show what would run, no changes
```

Flags can be combined: `/loop --max-hours 4 --sweep --no-merge`

---

## Step 0 — Read Configuration

Read `forge.toml`:

```toml
[project]
repo = "org/project"
base_branch = "main"

[stack]
build_command = "..."
test_command = "..."

[gating]
human_merge_required = true
max_copilot_iterations = 3

[loop]
max_failures_before_stop = 3
ci_poll_interval_minutes = 5
ci_timeout_minutes = 60
```

Read `CLAUDE.md` for project conventions. This applies to all implementation work
across all issues in the run.

---

## Step 1 — Initialize Loop State

Create or resume `.forge/loop-state.json` at the repo root:

```json
{
  "session_start": "<ISO timestamp>",
  "flags": {
    "max_issues": null,
    "max_hours": null,
    "issue_list": [],
    "sweep": false,
    "no_merge": false,
    "dry_run": false
  },
  "issues_completed": 0,
  "consecutive_failures": 0,
  "current": null,
  "completed": [],
  "failed": []
}
```

If `.forge/loop-state.json` already exists with a non-null `current` entry, a previous
run was interrupted mid-issue. Ask the user:

```
Found in-progress issue from previous run:
  Issue #$N: $TITLE (phase: $PHASE, PR: #$PR)

Resume from where it left off? [Y/n]
```

If yes: skip to the appropriate step for that phase (Step 3, 4, 5, or 6).
If no: clean up the stale state (remove `agent/implementing` label, delete worktree)
and start fresh.

---

## Step 2 — Optional Backlog Sweep

If `--sweep` flag is set, run `/sweep-issues` before the main loop. This ensures the
backlog has quality-checked, ready issues before implementation begins.

In dry-run mode, report what `/sweep-issues` would do but don't execute it.

---

## Step 3 — Pick Next Issue

Determine the next issue to work on:

**If `--issues` list was provided:** take the next uncompleted issue from the list.

**Otherwise:** use `/dispatch` to pick the highest-priority `backlog/ready` issue.

If no issues are available (list exhausted or no `backlog/ready` issues), the loop
ends cleanly:

```
Loop complete — no more issues to process.
  Issues completed this session: $N
  Total time: $ELAPSED
```

Save final state and exit.

In dry-run mode, show which issue would be picked and stop.

---

## Step 4 — Implement

Update loop state:
```json
"current": { "issue": $N, "title": "...", "phase": "implement", "started_at": "..." }
```

Run `/autodev $ISSUE_NUMBER` as a sub-agent to implement the issue, create the worktree,
run tests, and open the PR. Pass the branch name from `/dispatch` if already created.

**On success:** update state with the PR number:
```json
"current": { "issue": $N, "pr": $PR_NUMBER, "phase": "review" }
```

**On failure (blocked, tests failing after retries):**
```json
"failed": [..., { "issue": $N, "phase": "implement", "reason": "...", "timestamp": "..." }]
"consecutive_failures": $N + 1
```

Check circuit breaker (Step 8). Then proceed to next issue.

---

## Step 5 — Review Loop

Run `/review-pr $PR_NUMBER` to process Copilot's review feedback.

Repeat up to `max_copilot_iterations` times:

```
Review iteration $I/$MAX on PR #$PR_NUMBER...
```

Each iteration:
1. Run `/review-pr $PR_NUMBER` — fixes comments, replies in-thread, commits
2. Wait briefly (30 seconds) for Copilot to re-review the updated code
3. Check if new comments have appeared

**Transitioning to Claude review:**

After `max_copilot_iterations` Copilot passes, or when Copilot has no remaining
actionable comments, trigger the Claude review phase:

```bash
gh issue edit $PR_NUMBER --repo $REPO \
  --add-label "agent/review-claude" \
  --remove-label "agent/review-copilot"
```

Wait for the `claude-code-review.yml` workflow to complete (poll `gh run list` for
the relevant workflow run). Then run one final `/review-pr $PR_NUMBER` pass to address
Claude's feedback.

**Update state:**
```json
"current": { ..., "phase": "await-ci" }
```

**On failure:** if `/review-pr` fails after 2 attempts, add `human/blocked`, log failure,
check circuit breaker, continue to next issue.

---

## Step 6 — Await CI

Run `/await-ci $PR_NUMBER` to wait for all CI checks to pass.

While waiting, report progress:
```
Waiting for CI on PR #$PR_NUMBER... ($ELAPSED_MINUTES min elapsed)
  passing: $N  pending: $N  failing: $N
```

**On CI pass:** proceed to Step 7.

**On CI failure:** inspect the failure output. If the failure is clearly fixable
(test assertion mismatch, lint error, type error): attempt a fix and push. Re-run
`/await-ci`. Maximum 2 CI fix attempts.

If fix attempts are exhausted or the failure requires deeper investigation:

```bash
gh pr edit $PR_NUMBER --repo $REPO --add-label "human/blocked"
```

Log the failure, check circuit breaker, continue to next issue.

**Update state:**
```json
"current": { ..., "phase": "merge" }
```

---

## Step 7 — Merge

Run `/merge-pr $PR_NUMBER`.

**If `human_merge_required = true` or `--no-merge` flag:**

```
PR #$PR_NUMBER is ready to merge.
  Labeled: human/review-merge
  URL: $PR_URL
```

Record as completed (merge is human's responsibility):
```json
"completed": [..., { "issue": $N, "pr": $PR_NUMBER, "merged": false, "ready_at": "..." }]
```

**If auto-merge is enabled:**

After successful merge, record:
```json
"completed": [..., { "issue": $N, "pr": $PR_NUMBER, "merged": true, "merged_at": "..." }]
```

Clean up the worktree:
```bash
git worktree remove ".worktrees/issue-$N-$SLUG" 2>/dev/null || true
```

Print a progress line:
```
✓ Issue #$N merged (PR #$PR_NUMBER) — $ELAPSED_MINUTES min total
  Session progress: $COMPLETED / $TOTAL issues
```

**Update state:**
```json
"current": null,
"issues_completed": $N + 1,
"consecutive_failures": 0
```

---

## Step 8 — Circuit Breaker

After every failure, check stop conditions:

```
consecutive_failures >= max_failures_before_stop
```

If triggered:

```
Circuit breaker: $N consecutive failures. Stopping the loop.

Failed issues:
  - #$N1: $REASON
  - #$N2: $REASON
  - #$N3: $REASON

These have been labeled human/blocked. The loop state is saved at .forge/loop-state.json.
Resume with /loop when the underlying issues are resolved.
```

Save state and exit.

---

## Step 9 — Check Global Stop Conditions

After each completed (or failed) issue, check:

| Condition | Check |
|-----------|-------|
| `--max-issues` reached | `issues_completed >= max_issues` |
| `--max-hours` reached | `now - session_start >= max_hours * 3600` |
| `--issues` list exhausted | All listed issues processed |
| No more ready issues | `/dispatch` returns nothing |

On any stop condition met:

```
Loop stopping: $REASON.

Session summary:
  Duration:   $ELAPSED
  Completed:  $COMPLETED issues
  Merged:     $MERGED PRs
  Blocked:    $BLOCKED issues (labeled human/blocked)
  Next ready: $NEXT_ISSUE (if any)
```

---

## Step 10 — Loop

If no stop condition is met, return to Step 3.

---

## Execution model — sub-agents

Each major step (implement, review, await-ci, merge) runs as a **sub-agent** to keep
the loop orchestrator's context small across long runs. The loop orchestrator:
- Reads state from `.forge/loop-state.json`
- Spawns the appropriate sub-agent
- Reads the result
- Updates state
- Decides what to do next

This means the loop can run many issues without the orchestrator's context window
growing unboundedly.

---

## State file location

`.forge/loop-state.json` at repo root. This file is gitignored (add `.forge/` to
`.gitignore` if not already present). It persists across interrupted runs and is
the checkpoint for resume.

---

## Dry-run mode

With `--dry-run`:
- Read all state (backlog, open PRs, CI status)
- Report what the loop *would* do: which issues, in which order, estimated duration
- Do not create branches, open PRs, push code, or modify any labels
- Output a plan table:

```
Dry-run plan — forge loop

  Would process:
    1. #42: $TITLE (backlog/ready, priority/high)
    2. #43: $TITLE (backlog/ready)
    3. #38: $TITLE (via/autodev PR #95 — in review-loop, 1/3 iterations)

  Stop condition: --max-issues 3
  Estimated time: 2–4 hours (at current pipeline velocity)

  Run /loop --max-issues 3 to execute.
```

---

## Guardrails

- **One loop at a time**: Check for a running loop (stale `.forge/loop-state.json`
  with a recent timestamp) before starting. If one appears active, warn and ask to confirm.
- **Never modify protected files**: Check `forge.toml` `[protected_files]` patterns
  before every commit.
- **Never push to base branch**: All work on `autodev/issue-*` branches only.
- **Always reply to review comments**: Every review pass must reply in-thread.
- **Respect CI**: Never merge with failing checks, even if `human_merge_required = false`.
- **Save state on interrupt**: If the user stops the loop (Ctrl+C), attempt to write
  the current state to `.forge/loop-state.json` before exiting.
