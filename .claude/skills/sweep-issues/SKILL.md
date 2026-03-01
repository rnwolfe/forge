---
name: sweep-issues
description: "Sweep open issues against the quality checklist and label those needing refinement"
disable-model-invocation: true
---

# Sweep Issues — Backlog Quality Audit

You are a disciplined issue triager. Your job is to evaluate open issues against the
gold-standard quality checklist and surface those that need work, so the team can
prioritize refinement.

## Input

The user may provide a label filter as an argument: `$ARGUMENTS`

Examples:
- `/sweep-issues` — sweep all open issues
- `/sweep-issues feature` — only sweep issues labeled `feature`
- `/sweep-issues phase:2` — only sweep issues in phase 2

## Process

### 1. Read Project Configuration

Read `forge.toml` for the repo path used in `gh` commands.

### 2. Read the Quality Bar

Read the gold-standard template and checklist:

`.claude/skills/shared/issue-quality-checklist.md`

The 10-item checklist is your scoring rubric:
1. Summary
2. Scope (features/commands)
3. Architecture
4. Integration
5. Acceptance criteria
6. Edge cases
7. Tests
8. Documentation
9. CLAUDE.md update
10. Labels

### 3. Fetch Open Issues

Fetch the issue list:

```bash
gh issue list --repo $REPO --state open --limit 100 --json number,title,labels,body
```

If the user provided a label filter, add `--label "<filter>"` to narrow the set.

After fetching, manually filter out issues that already have `backlog/needs-refinement` or
`backlog/ready` labels — these are already in the pipeline.

### 4. Assess Each Issue

For each remaining issue, score it against the 10-item checklist. Rate each item as:

- **Present**: The section exists and meets the bar
- **Weak**: The section exists but needs improvement
- **Missing**: The section is absent entirely

**Adapt the checklist to the issue type:**
- Bug reports: skip Features table, Architecture can be lighter
- Small enhancements: skip Architecture if the scope is a single function change
- Feature requests: all 10 items apply

Count a score as: Present = 1, Weak = 0.5, Missing = 0. Total out of 10 (or the
applicable subset for the issue type).

Assign a verdict:
- **Ready** (8+/10): Already meets the bar — suggest `backlog/ready` label
- **Needs refinement** (4-7.5/10): Has gaps worth filling
- **Stub** (<4/10): Needs significant work

### 5. Present Summary Table

Show the user a table like:

```
Backlog sweep — 12 issues evaluated

  #   Title                              Score  Verdict
  35  Feature X                          9/10   Ready
  42  Enhancement Y                      5/10   Needs refinement
  48  Better error messages              3/10   Stub
  51  New API endpoint                   6/10   Needs refinement
  ...

Summary: 2 ready, 6 need refinement, 4 stubs
```

For issues verdicted as "Needs refinement" or "Stub", list the top 2-3 missing/weak
items so the user knows what gaps to fill.

### 6. Apply Labels (With Approval)

Ask the user which actions to take:
- Apply `backlog/needs-refinement` label to issues verdicted as "Needs refinement" or "Stub"
- Optionally post a comment on each labeled issue listing the specific gaps found
- Suggest `backlog/ready` for issues that already meet the bar

**Always ask for explicit approval before modifying any issues.**

After approval, apply labels:

```bash
gh issue edit $ISSUE_NUMBER --repo $REPO --add-label "backlog/needs-refinement"
```

If the user opted for gap comments:

```bash
gh issue comment $ISSUE_NUMBER --repo $REPO --body "<gap listing>"
```

### 7. Report Results

Print a results summary:

```
Sweep complete:
  - 2 issues already meet the bar (suggested backlog/ready)
  - 6 issues labeled backlog/needs-refinement
  - 4 stubs labeled backlog/needs-refinement

Next step: run /refine-issue to start improving the highest-priority issues.
```

## Guidelines

- **Non-destructive.** Only add labels and comments. Never remove labels, edit issue
  bodies, or close issues. The sweep is read-heavy, write-light.
- **Adapt the checklist.** A bug report with clear repro steps and expected behavior
  might score 8/10 even without a Features table. Don't penalize issues for skipping
  sections that don't apply to their type.
- **Be efficient.** For large backlogs, summarize rather than showing per-item breakdowns
  for every issue. Only show detailed gaps for issues the user is likely to act on.
- **Suggest `backlog/ready` generously.** If an issue is close to the bar and the gaps are
  minor (e.g., missing CLAUDE.md update note), say so — the user may want to quickly
  patch it rather than going through full refinement.
- **Batch sensibly.** If there are 50+ issues, process them in batches and let the user
  decide whether to continue.
