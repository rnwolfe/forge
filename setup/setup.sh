#!/usr/bin/env bash
set -euo pipefail

# setup/setup.sh — One-time GitHub setup for the forge autodev pipeline
#
# Usage:
#   bash setup/setup.sh
#
# Runs idempotent setup steps: creates labels, configures branch protection.
# Safe to re-run.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/scripts/autodev/config.sh"

if [ -z "$AUTODEV_REPO" ]; then
    echo "Error: project.repo not set in forge.toml"
    exit 1
fi

echo "Setting up forge autodev pipeline for $AUTODEV_REPO..."
echo ""

# Step 1: Create labels
echo "Step 1: Creating labels..."
bash "$SCRIPT_DIR/create-labels.sh"
echo ""

# Step 2: Configure branch protection
echo "Step 2: Configuring branch protection..."
bash "$SCRIPT_DIR/configure-branch-protection.sh"
echo ""

echo "Setup complete!"
echo ""
echo "Manual steps remaining:"
echo "  1. Create a GitHub App or use a fine-grained PAT for AUTODEV_TOKEN"
echo "     - Permissions: Contents (read/write), Pull requests (read/write), Issues (read/write)"
echo "  2. Add repository secrets:"
echo "     - CLAUDE_CODE_OAUTH_TOKEN: OAuth token for Claude Code"
echo "     - APP_ID + APP_PRIVATE_KEY: GitHub App credentials (or AUTODEV_TOKEN PAT)"
echo "  3. Enable Copilot code review on the repository (Settings > Copilot > Code review)"
echo "  4. Enable auto-merge on the repository (Settings > General > Allow auto-merge)"
