#!/usr/bin/env bash
set -euo pipefail

# scripts/autodev/pick-issue.sh — Select the next issue for autodev
#
# Usage:
#   scripts/autodev/pick-issue.sh [ISSUE_NUMBER]
#
# If ISSUE_NUMBER is provided, uses that issue (manual override).
# Otherwise, picks the highest-priority backlog/ready issue not already being implemented.
# Exits 0 with empty output if nothing to do.

source "$(dirname "$0")/config.sh"

ISSUE_NUMBER="${1:-}"

# ── Verify agent-ready label was applied by a trusted user ────────

verify_trusted_labeler() {
    local issue="$1"

    LABELER=$(gh api "repos/$AUTODEV_REPO/issues/$issue/timeline" --paginate \
        --jq "[.[] | select(.event == \"labeled\" and .label.name == \"$AUTODEV_LABEL_READY\")] | last | .actor.login // empty")

    if [ -z "$LABELER" ]; then
        autodev_warn "Could not determine who applied '$AUTODEV_LABEL_READY' label to issue #$issue"
        return 1
    fi

    for trusted in "${AUTODEV_TRUSTED_USERS[@]}"; do
        if [ "$LABELER" = "$trusted" ]; then
            autodev_info "Label applied by trusted user: $LABELER"
            return 0
        fi
    done

    autodev_warn "Issue #$issue: '$AUTODEV_LABEL_READY' label applied by untrusted user '$LABELER'. Skipping."
    return 1
}

# ── Guard: block dispatch if too many active autodev PRs are open ──
OPEN_AUTODEV_COUNT=$(gh pr list \
    --repo "$AUTODEV_REPO" \
    --state open \
    --json number,labels \
    --jq '[.[] | select(
        (.labels | map(.name) | any(startswith("via/")))
        and (.labels | map(.name) | any(. == "human/blocked") | not)
    )] | length')

if [ "$OPEN_AUTODEV_COUNT" -ge "$FORGE_MAX_CONCURRENT_PRS" ]; then
    autodev_info "Skipping dispatch: $OPEN_AUTODEV_COUNT open autodev PR(s) (max $FORGE_MAX_CONCURRENT_PRS). Will retry next cycle."
    exit 0
fi

if [ -n "$ISSUE_NUMBER" ]; then
    # Manual override — validate the issue exists and has agent-ready label
    LABELS=$(gh issue view "$ISSUE_NUMBER" --repo "$AUTODEV_REPO" --json labels --jq '[.labels[].name]' 2>/dev/null) \
        || autodev_fatal "Issue #$ISSUE_NUMBER not found"

    if ! echo "$LABELS" | jq -e --arg label "$AUTODEV_LABEL_READY" 'index($label)' >/dev/null 2>&1; then
        autodev_fatal "Issue #$ISSUE_NUMBER does not have '$AUTODEV_LABEL_READY' label"
    fi

    verify_trusted_labeler "$ISSUE_NUMBER" \
        || autodev_fatal "Issue #$ISSUE_NUMBER: backlog/ready label not applied by a trusted user"

    gh issue edit "$ISSUE_NUMBER" --repo "$AUTODEV_REPO" --add-label "$AUTODEV_LABEL_IMPLEMENTING" >/dev/null

    echo "$ISSUE_NUMBER"
    exit 0
fi

# Auto-pick: highest-priority backlog/ready issue not already being implemented
CANDIDATES=$(gh issue list \
    --repo "$AUTODEV_REPO" \
    --label "$AUTODEV_LABEL_READY" \
    --state open \
    --json number,labels \
    --jq "[.[] | select(.labels | map(.name) | (index(\"$AUTODEV_LABEL_IMPLEMENTING\") | not) and (index(\"$AUTODEV_LABEL_BLOCKED\") | not))]
          | map(. + {pri: (if (.labels | map(.name) | index(\"$AUTODEV_LABEL_PRIORITY_CRITICAL\")) then 0
                         elif (.labels | map(.name) | index(\"$AUTODEV_LABEL_PRIORITY_HIGH\")) then 1
                         else 2 end)})
          | sort_by([.pri, .number])")

ISSUE_NUMBER=""
for row in $(echo "$CANDIDATES" | jq -r '.[].number'); do
    if verify_trusted_labeler "$row"; then
        ISSUE_NUMBER="$row"
        break
    fi
done

if [ -z "$ISSUE_NUMBER" ]; then
    autodev_info "No backlog/ready issues from trusted users found. Nothing to do."
    exit 0
fi

gh issue edit "$ISSUE_NUMBER" --repo "$AUTODEV_REPO" --add-label "$AUTODEV_LABEL_IMPLEMENTING" >/dev/null

echo "$ISSUE_NUMBER"
