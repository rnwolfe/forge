---
name: await-ci
description: "Poll a PR's CI checks until all pass, any fail, or timeout — then report the result"
disable-model-invocation: true
---

# Await CI — Wait for PR Checks to Settle

Poll a pull request's CI status until all required checks pass, any required check
fails, or the timeout is reached. Reports the result clearly so the caller (human or
`/forge-loop`) can decide what to do next.

## Input

`$ARGUMENTS` — PR number (required).

- `/await-ci 97` — wait for PR #97's checks

---

## Step 0 — Read Configuration

Read `forge.toml`:

```toml
[project]
repo = "org/project"

[loop]
ci_poll_interval_minutes = 5     # How long to wait between checks
ci_timeout_minutes = 60          # Max total wait time
```

Defaults if not set: `ci_poll_interval_minutes = 5`, `ci_timeout_minutes = 60`.

---

## Step 1 — Validate PR

```bash
gh pr view $PR_NUMBER --repo $REPO --json number,title,state,headRefName
```

Verify the PR is open. If closed or merged, report immediately:

```
PR #$PR_NUMBER is already $STATE — no checks to wait for.
```

---

## Step 2 — Poll CI Status

Poll on the configured interval until checks settle or timeout:

```bash
gh pr checks $PR_NUMBER --repo $REPO --json name,state,conclusion
```

**Check states:**
- `PENDING` / `IN_PROGRESS` / `QUEUED` → still running, keep polling
- `SUCCESS` / `NEUTRAL` / `SKIPPED` → passed
- `FAILURE` / `ERROR` / `CANCELLED` / `TIMED_OUT` / `ACTION_REQUIRED` → failed

**Settled when:** no checks are in a pending/running state.

Print a progress line on each poll:

```
[12:03] PR #97 — 3/5 checks passing, 2 pending (elapsed: 8m)
[12:08] PR #97 — 5/5 checks passing (elapsed: 13m)
```

**Timeout:** If elapsed time exceeds `ci_timeout_minutes`, stop polling and report:

```
CI timeout after $TIMEOUT_MINUTES minutes. PR #$PR_NUMBER checks did not settle.
Still running: <list check names>
```

---

## Step 3 — Report Result

### All checks passed

```
CI PASSED — PR #$PR_NUMBER is green.
  Checks: $PASS_COUNT passed, $SKIP_COUNT skipped
  Elapsed: $ELAPSED_MINUTES minutes

Ready for review and merge.
```

Exit with success.

### Any required check failed

```
CI FAILED — PR #$PR_NUMBER has failing checks.
  Failed: $FAIL_COUNT check(s)
    - $CHECK_NAME: $CONCLUSION ($DETAILS_URL)
  Passed: $PASS_COUNT
  Elapsed: $ELAPSED_MINUTES minutes

Recommended action: read the failure logs and either fix the code or mark the PR
human/blocked if the failure requires investigation.
```

Exit with failure.

### Timeout

```
CI TIMEOUT — PR #$PR_NUMBER did not finish within $TIMEOUT_MINUTES minutes.
  Still running: $PENDING_COUNT check(s)
    - $CHECK_NAME (running for $ELAPSED_MINUTES minutes)

Recommended action: check if CI is stuck (flaky test, hung job). Consider re-running
failed checks or marking human/blocked.
```

Exit with failure.

---

## Guardrails

- Never merge or modify the PR — this skill only observes
- Never exit before checks are settled (unless timeout)
- If `gh pr checks` returns no checks at all, wait one full interval and retry (checks
  may not have started yet)
- If polling fails due to API rate limit, wait 60 seconds and retry up to 3 times
