#!/usr/bin/env bash
set -euo pipefail

# scripts/autodev/open-pr.sh — Create a PR for an autodev implementation
#
# Usage:
#   scripts/autodev/open-pr.sh ISSUE_NUMBER BRANCH_NAME [ORIGIN_LABEL]

source "$(dirname "$0")/config.sh"

ISSUE_NUMBER="${1:?Usage: open-pr.sh ISSUE_NUMBER BRANCH_NAME}"
BRANCH_NAME="${2:?Usage: open-pr.sh ISSUE_NUMBER BRANCH_NAME}"
ORIGIN_LABEL="${3:-$AUTODEV_LABEL_VIA_ACTIONS}"

ISSUE_JSON=$(gh issue view "$ISSUE_NUMBER" --repo "$AUTODEV_REPO" --json title,body)
ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')

PR_TITLE_FILE="/tmp/pr-title.txt"
if [ -f "$PR_TITLE_FILE" ] && [ -s "$PR_TITLE_FILE" ]; then
    autodev_info "Using agent-generated PR title"
    PR_TITLE=$(head -1 "$PR_TITLE_FILE")
else
    autodev_warn "No agent-generated PR title found, falling back to issue title"
    PR_TITLE="$ISSUE_TITLE"
fi

PR_DESC_FILE="/tmp/pr-description.md"

if [ -f "$PR_DESC_FILE" ] && [ -s "$PR_DESC_FILE" ]; then
    autodev_info "Using agent-generated PR description"
    PR_BODY=$(cat "$PR_DESC_FILE")
else
    autodev_warn "No agent-generated PR description found, using fallback template"
    PR_BODY=$(cat <<EOF
## Summary

Autonomous implementation of #$ISSUE_NUMBER.

Closes #$ISSUE_NUMBER

## Changes

See commits on this branch for implementation details.

## Test Plan

- [ ] CI passes
- [ ] Code review feedback addressed
EOF
)
fi

# Append autodev state tracker
PR_BODY+=$'\n\n<!-- autodev-state: {"phase": "copilot", "copilot_iterations": 0} -->'

PR_URL=$(gh pr create \
    --repo "$AUTODEV_REPO" \
    --head "$BRANCH_NAME" \
    --base "$AUTODEV_BASE_BRANCH" \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    --label "$ORIGIN_LABEL" --label "$AUTODEV_LABEL_REVIEW_COPILOT")

autodev_info "Created PR: $PR_URL"

PR_NUMBER=$(echo "$PR_URL" | grep -oP '/pull/\K\d+')

# Remove human reviewer auto-added by CODEOWNERS
if [ -n "$AUTODEV_HUMAN_REVIEWER" ]; then
    if gh api -X DELETE \
        "repos/$AUTODEV_REPO/pulls/$PR_NUMBER/requested_reviewers" \
        -f "reviewers[]=$AUTODEV_HUMAN_REVIEWER" 2>/tmp/remove-reviewer-err.txt; then
        autodev_info "Removed human reviewer ($AUTODEV_HUMAN_REVIEWER) from PR #$PR_NUMBER"
    else
        autodev_warn "Could not remove human reviewer from PR #$PR_NUMBER: $(cat /tmp/remove-reviewer-err.txt)"
    fi
fi

# Request Copilot review explicitly
if gh api -X POST \
    "repos/$AUTODEV_REPO/pulls/$PR_NUMBER/requested_reviewers" \
    -f 'reviewers[]=copilot-pull-request-reviewer' 2>/tmp/copilot-review-err.txt; then
    autodev_info "Requested Copilot review on PR #$PR_NUMBER"
else
    autodev_warn "Could not request Copilot review on PR #$PR_NUMBER: $(cat /tmp/copilot-review-err.txt)"
    autodev_warn "Pipeline will fall back to Claude phase via scheduled poll"
fi

echo "$PR_URL"
