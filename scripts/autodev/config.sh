#!/usr/bin/env bash
# scripts/autodev/config.sh — Shared constants for autodev workflows
#
# Reads forge.toml and exports shell variables used by all autodev scripts.
# Source this file from other autodev scripts:
#   source "$(dirname "$0")/config.sh"

# ── TOML parser ──────────────────────────────────────────────────────
# Lightweight awk-based parser. Handles simple TOML key-value pairs,
# strings (quoted and unquoted), booleans, integers, and arrays of strings.
# Does NOT handle nested tables, inline tables, or multiline strings.

_forge_toml() {
    local file="${FORGE_CONFIG:-$(git rev-parse --show-toplevel 2>/dev/null)/forge.toml}"
    if [ ! -f "$file" ]; then
        echo ""
        return
    fi
    local section="$1"
    local key="$2"
    awk -v section="$section" -v key="$key" '
    BEGIN { in_section = 0 }
    /^\[/ {
        gsub(/[\[\] \t]/, "")
        in_section = ($0 == section)
        next
    }
    in_section && /^[[:space:]]*#/ { next }
    in_section && /^[[:space:]]*$/ { next }
    in_section {
        split($0, parts, "=")
        k = parts[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
        if (k == key) {
            # Rejoin everything after first = (value may contain =)
            val = ""
            for (i = 2; i <= length(parts); i++) {
                if (i > 2) val = val "="
                val = val parts[i]
            }
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            # Strip inline comments (not inside quotes)
            if (val !~ /^\[/ && val !~ /^"/) {
                sub(/[[:space:]]+#.*$/, "", val)
            }
            # Strip surrounding quotes
            gsub(/^"|"$/, "", val)
            print val
            exit
        }
    }
    ' "$file"
}

# Parse a TOML array of strings into a bash array.
# Usage: _forge_toml_array "section" "key" → prints one value per line
_forge_toml_array() {
    local file="${FORGE_CONFIG:-$(git rev-parse --show-toplevel 2>/dev/null)/forge.toml}"
    if [ ! -f "$file" ]; then
        return
    fi
    local section="$1"
    local key="$2"
    awk -v section="$section" -v key="$key" '
    BEGIN { in_section = 0; capturing = 0 }
    /^\[/ {
        gsub(/[\[\] \t]/, "")
        in_section = ($0 == section)
        if (!in_section && capturing) exit
        next
    }
    in_section && capturing {
        if (/\]/) { capturing = 0; next }
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        gsub(/,/, "")
        gsub(/^"|"$/, "")
        if ($0 != "") print
        next
    }
    in_section {
        split($0, parts, "=")
        k = parts[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
        if (k == key) {
            val = ""
            for (i = 2; i <= length(parts); i++) {
                if (i > 2) val = val "="
                val = val parts[i]
            }
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            # Single-line array
            if (val ~ /^\[.*\]$/) {
                gsub(/[\[\]]/, "", val)
                n = split(val, items, ",")
                for (i = 1; i <= n; i++) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", items[i])
                    gsub(/^"|"$/, "", items[i])
                    if (items[i] != "") print items[i]
                }
                exit
            }
            # Multi-line array starts with [
            if (val ~ /^\[/) {
                capturing = 1
                next
            }
        }
    }
    ' "$file"
}

# ── Read forge.toml ──────────────────────────────────────────────────

# Repository
AUTODEV_REPO="$(_forge_toml "project" "repo")"
AUTODEV_BASE_BRANCH="$(_forge_toml "project" "base_branch")"
AUTODEV_BASE_BRANCH="${AUTODEV_BASE_BRANCH:-main}"

# Stack
FORGE_BUILD_COMMAND="$(_forge_toml "stack" "build_command")"
FORGE_TEST_COMMAND="$(_forge_toml "stack" "test_command")"
FORGE_LINT_COMMAND="$(_forge_toml "stack" "lint_command")"

# Gating
FORGE_HUMAN_MERGE_REQUIRED="$(_forge_toml "gating" "human_merge_required")"
FORGE_AUTO_MERGE="$(_forge_toml "gating" "auto_merge_after_review")"
FORGE_COPILOT_REVIEW="$(_forge_toml "gating" "copilot_review")"
FORGE_CLAUDE_REVIEW="$(_forge_toml "gating" "claude_review")"

# Dispatch
FORGE_MAX_CONCURRENT_PRS="$(_forge_toml "dispatch" "max_concurrent_prs")"
FORGE_MAX_CONCURRENT_PRS="${FORGE_MAX_CONCURRENT_PRS:-1}"

# Agent
FORGE_MODEL="$(_forge_toml "agent" "model")"
FORGE_MODEL="${FORGE_MODEL:-claude-sonnet-4-6}"
FORGE_MAX_IMPLEMENT_TURNS="$(_forge_toml "agent" "max_implement_turns")"
FORGE_MAX_IMPLEMENT_TURNS="${FORGE_MAX_IMPLEMENT_TURNS:-150}"
FORGE_MAX_REVIEW_TURNS="$(_forge_toml "agent" "max_review_turns")"
FORGE_MAX_REVIEW_TURNS="${FORGE_MAX_REVIEW_TURNS:-50}"

# Pipeline stage labels (mutually exclusive per issue/PR)
AUTODEV_LABEL_READY="backlog/ready"
AUTODEV_LABEL_IMPLEMENTING="agent/implementing"
AUTODEV_LABEL_REVIEW_COPILOT="agent/review-copilot"
AUTODEV_LABEL_REVIEW_CLAUDE="agent/review-claude"
AUTODEV_LABEL_REVIEW_MERGE="human/review-merge"
AUTODEV_LABEL_BLOCKED="human/blocked"

# Origin labels (persistent, one per PR)
AUTODEV_LABEL_VIA_ACTIONS="via/actions"
AUTODEV_LABEL_VIA_AUTODEV="via/autodev"

# Priority labels (dispatch ordering)
AUTODEV_LABEL_PRIORITY_CRITICAL="priority/critical"
AUTODEV_LABEL_PRIORITY_HIGH="priority/high"

# Report labels
AUTODEV_LABEL_PIPELINE_AUDIT="report/pipeline-audit"

# Limits
AUTODEV_MAX_ITERATIONS="$(_forge_toml "gating" "max_copilot_iterations")"
AUTODEV_MAX_ITERATIONS="${AUTODEV_MAX_ITERATIONS:-3}"

# Trusted users who can trigger autodev via backlog/ready label.
# Read from forge.toml; always include bot actors.
mapfile -t _trusted_from_toml < <(_forge_toml_array "trust" "trusted_users")
AUTODEV_TRUSTED_USERS=("${_trusted_from_toml[@]}" "github-actions[bot]" "claude[bot]")

# Human reviewer to remove from autodev PRs (auto-added by CODEOWNERS).
AUTODEV_HUMAN_REVIEWER="$(_forge_toml "trust" "human_reviewer")"

# Protected file patterns (read from forge.toml)
mapfile -t AUTODEV_PROTECTED_PATTERNS < <(_forge_toml_array "protected_files" "patterns")

# Provider (model-agnostic switch)
AUTODEV_PROVIDER="${AUTODEV_PROVIDER:-$(_forge_toml "agent" "provider")}"
AUTODEV_PROVIDER="${AUTODEV_PROVIDER:-claude}"

# ── Logging helpers ─────────────────────────────────────────────────

autodev_info()  { echo "::notice::autodev: $*" >&2; }
autodev_warn()  { echo "::warning::autodev: $*" >&2; }
autodev_error() { echo "::error::autodev: $*" >&2; }

autodev_fatal() {
    autodev_error "$@"
    exit 1
}

# ── Utilities ───────────────────────────────────────────────────────

# Convert a string to a branch-safe slug
# Usage: autodev_slugify "Add user authentication"  →  add-user-authentication
autodev_slugify() {
    echo "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g' \
        | sed -E 's/^-+|-+$//g' \
        | cut -c1-50
}

# Build a grep regex from protected file patterns
# Usage: autodev_protected_regex → outputs regex for grep -E
autodev_protected_regex() {
    local regex=""
    for pattern in "${AUTODEV_PROTECTED_PATTERNS[@]}"; do
        # Escape dots, convert glob * to regex .*
        local escaped
        escaped=$(echo "$pattern" | sed 's/\./\\./g; s/\*/.*/g')
        if [ -n "$regex" ]; then
            regex="$regex|$escaped"
        else
            regex="$escaped"
        fi
    done
    echo "($regex)"
}
