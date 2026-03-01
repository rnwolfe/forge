#!/usr/bin/env bash
set -euo pipefail

# scripts/autodev/parse-reviews.sh — Extract actionable review feedback from a PR
#
# Usage:
#   scripts/autodev/parse-reviews.sh PR_NUMBER
#
# Outputs structured review feedback for agent consumption.
# Exits 0 with empty stdout if no actionable comments found.
# Exits 1 on error (gh API failure, jq error, etc.).

source "$(dirname "$0")/config.sh"

PR_NUMBER="${1:?Usage: parse-reviews.sh PR_NUMBER [EXCLUDE_LOGIN]}"
# EXCLUDE_LOGIN: reviews/comments from this user are ignored.
# copilot-fix path uses the default (exclude Claude's bot reviews).
# claude-fix path passes "copilot-pull-request-reviewer[bot]" so Claude's
# github-actions[bot] reviews are included and Copilot's are excluded.
EXCLUDE_LOGIN="${2:-github-actions[bot]}"

FEEDBACK=""

# ── Top-level reviews ──────────────────────────────────────────────

REVIEWS=$(gh api --paginate \
    "repos/$AUTODEV_REPO/pulls/$PR_NUMBER/reviews" \
    | jq --arg exclude "$EXCLUDE_LOGIN" '[.[] | select(
        (.state == "CHANGES_REQUESTED" or .state == "COMMENTED") and
        (.body != null and .body != "") and
        (.user.login != $exclude)
    )] | sort_by(.submitted_at) | reverse | .[0:5]')

REVIEW_COUNT=$(echo "$REVIEWS" | jq 'length')

if [ "$REVIEW_COUNT" -gt 0 ]; then
    FEEDBACK+="## Review Comments"$'\n\n'
    while IFS= read -r review; do
        AUTHOR=$(echo "$review" | jq -r '.user.login')
        STATE=$(echo "$review" | jq -r '.state')
        BODY=$(echo "$review" | jq -r '.body')
        REVIEW_ID=$(echo "$review" | jq -r '.id')
        FEEDBACK+="### $AUTHOR ($STATE) [review_id: $REVIEW_ID]"$'\n'
        FEEDBACK+="$BODY"$'\n\n'
    done < <(echo "$REVIEWS" | jq -c '.[]')
fi

# ── Line-level review comments ─────────────────────────────────────

# Fetch all inline comments in one pass. We use this both to identify which
# comments the claude fix agent has already replied to (so we don't hand them
# to the agent again) and to build the actionable feedback list.
ALL_INLINE_RAW=$(gh api --paginate "repos/$AUTODEV_REPO/pulls/$PR_NUMBER/comments")

# Collect IDs of comments that claude has already replied to. Any comment whose
# ID appears as an `in_reply_to_id` on a claude reply is considered handled and
# is excluded from the feedback so the agent doesn't address it a second time.
# Matches "claude", "claude[bot]", "claude-code-review[bot]", etc.
CLAUDE_REPLIED_IDS=$(echo "$ALL_INLINE_RAW" \
    | jq '[.[] | select((.user.login | ascii_downcase | startswith("claude")) and (.in_reply_to_id != null)) | .in_reply_to_id]')

COMMENTS=$(echo "$ALL_INLINE_RAW" \
    | jq --arg exclude "$EXCLUDE_LOGIN" --argjson replied "$CLAUDE_REPLIED_IDS" '[.[] | select(
        .user.login != $exclude and
        ((.id) as $id | ($replied | index($id)) == null)
    )] | sort_by(.created_at) | reverse | .[0:20]')

COMMENT_COUNT=$(echo "$COMMENTS" | jq 'length')

if [ "$COMMENT_COUNT" -gt 0 ]; then
    FEEDBACK+="## Inline Comments"$'\n\n'
    while IFS= read -r comment; do
        AUTHOR=$(echo "$comment" | jq -r '.user.login')
        FILEPATH=$(echo "$comment" | jq -r '.path')
        LINE=$(echo "$comment" | jq -r '.line // .original_line // "N/A"')
        BODY=$(echo "$comment" | jq -r '.body')
        COMMENT_ID=$(echo "$comment" | jq -r '.id')
        FEEDBACK+="### $FILEPATH:$LINE ($AUTHOR) [comment_id: $COMMENT_ID]"$'\n'
        FEEDBACK+="$BODY"$'\n\n'
    done < <(echo "$COMMENTS" | jq -c '.[]')
fi

# ── Output ──────────────────────────────────────────────────────────

if [ -z "$FEEDBACK" ]; then
    autodev_info "No actionable review comments found on PR #$PR_NUMBER"
    exit 0
fi

echo "$FEEDBACK"
