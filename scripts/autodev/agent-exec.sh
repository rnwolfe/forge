#!/usr/bin/env bash
set -euo pipefail

# scripts/autodev/agent-exec.sh — Model-agnostic agent execution abstraction
#
# Usage:
#   scripts/autodev/agent-exec.sh TASK_FILE
#
# Routes to the configured provider. In CI, workflows use claude-code-action@v1
# directly — this script exists for local testing and documenting the abstraction.
#
# Providers:
#   claude  — Claude CLI (requires `claude` in PATH)
#   codex   — OpenAI Codex (placeholder)
#   gemini  — Google Gemini (placeholder)

source "$(dirname "$0")/config.sh"

TASK_FILE="${1:?Usage: agent-exec.sh TASK_FILE}"

if [ ! -f "$TASK_FILE" ]; then
    autodev_fatal "Task file not found: $TASK_FILE"
fi

PROMPT=$(cat "$TASK_FILE")

case "$AUTODEV_PROVIDER" in
    claude)
        autodev_info "Running agent via Claude CLI"
        if ! command -v claude >/dev/null 2>&1; then
            autodev_fatal "Claude CLI not found. Install from https://claude.ai/code"
        fi
        claude --print --dangerously-skip-permissions "$PROMPT"
        ;;
    codex)
        autodev_fatal "Codex provider not yet implemented. Swap the provider or implement the stub."
        ;;
    gemini)
        autodev_fatal "Gemini provider not yet implemented. Swap the provider or implement the stub."
        ;;
    *)
        autodev_fatal "Unknown provider: $AUTODEV_PROVIDER"
        ;;
esac
