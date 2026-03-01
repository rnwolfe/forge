#!/usr/bin/env bash
set -euo pipefail

# scripts/autodev/check-gates.sh — Verify quality gates for an autodev PR
#
# Usage:
#   scripts/autodev/check-gates.sh PR_NUMBER
#
# Reports all gate results (doesn't short-circuit).
# Exits 0 if all gates pass, 1 if any gate fails.

source "$(dirname "$0")/config.sh"

PR_NUMBER="${1:?Usage: check-gates.sh PR_NUMBER}"

FAILURES=0

# ── Gate 1: CI test job ────────────────────────────────────────────

CI_STATUS=$(gh pr checks "$PR_NUMBER" \
    --repo "$AUTODEV_REPO" \
    --json name,state \
    --jq '.[] | select(.name == "test") | .state' 2>/dev/null || echo "UNKNOWN")

if [ "$CI_STATUS" = "SUCCESS" ]; then
    autodev_info "Gate CI: PASS (test=$CI_STATUS)"
else
    autodev_warn "Gate CI: FAIL (test=$CI_STATUS)"
    FAILURES=$((FAILURES + 1))
fi

# ── Gate 2: Iteration count ────────────────────────────────────────

PR_BODY=$(gh pr view "$PR_NUMBER" --repo "$AUTODEV_REPO" --json body --jq '.body')
ITERATION=$(echo "$PR_BODY" | grep -oP '(?<=<!-- autodev-state: \{"iteration": )\d+' || echo "0")

if [ "$ITERATION" -lt "$AUTODEV_MAX_ITERATIONS" ]; then
    autodev_info "Gate iterations: PASS ($ITERATION/$AUTODEV_MAX_ITERATIONS)"
else
    autodev_warn "Gate iterations: FAIL ($ITERATION/$AUTODEV_MAX_ITERATIONS)"
    FAILURES=$((FAILURES + 1))
fi

# ── Gate 3: Reviews resolved ──────────────────────────────────────

PENDING_REVIEWS=$(gh api \
    "repos/$AUTODEV_REPO/pulls/$PR_NUMBER/reviews" \
    --jq '[.[] | select(.state == "CHANGES_REQUESTED")] | length' 2>/dev/null || echo "0")

if [ "$PENDING_REVIEWS" -eq 0 ]; then
    autodev_info "Gate reviews: PASS (no changes requested)"
else
    autodev_warn "Gate reviews: FAIL ($PENDING_REVIEWS reviews requesting changes)"
    FAILURES=$((FAILURES + 1))
fi

# ── Gate 4: Mergeable ──────────────────────────────────────────────

MERGEABLE=$(gh pr view "$PR_NUMBER" --repo "$AUTODEV_REPO" --json mergeable --jq '.mergeable')

if [ "$MERGEABLE" = "MERGEABLE" ]; then
    autodev_info "Gate mergeable: PASS"
else
    autodev_warn "Gate mergeable: FAIL (state=$MERGEABLE)"
    FAILURES=$((FAILURES + 1))
fi

# ── Result ─────────────────────────────────────────────────────────

if [ "$FAILURES" -gt 0 ]; then
    autodev_error "$FAILURES gate(s) failed for PR #$PR_NUMBER"
    exit 1
fi

autodev_info "All gates passed for PR #$PR_NUMBER"
