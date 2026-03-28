#!/usr/bin/env bash
# setup/bootstrap.sh — Enroll an existing project in forge-sync
#
# Designed to be run via curl from any project scaffolded from forge:
#
#   curl -fsSL https://raw.githubusercontent.com/rnwolfe/forge/main/setup/bootstrap.sh | bash
#
# What it does:
#   1. Downloads scripts/forge-sync.sh from the forge template
#   2. Makes it executable
#   3. Runs --init to write .forge/manifest.json pinned to current forge HEAD
#
# Requires: curl or gh, git

set -euo pipefail

FORGE_REPO="rnwolfe/forge"
FORGE_RAW="https://raw.githubusercontent.com/$FORGE_REPO/main"
SCRIPT_DEST="scripts/forge-sync.sh"

# ── Must run from a git repo root ────────────────────────────────────────────
if ! git rev-parse --show-toplevel &>/dev/null; then
    echo "Error: must be run from inside a git repository." >&2
    exit 1
fi

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

# ── Download forge-sync.sh ───────────────────────────────────────────────────
mkdir -p scripts

# Prefer gh API over curl — gh hits the GitHub API directly and is never
# served from CDN cache, so it always returns the latest committed content.
if command -v gh &>/dev/null; then
    gh api "repos/$FORGE_REPO/contents/$SCRIPT_DEST" --jq '.content' \
        | base64 -d > "$SCRIPT_DEST"
elif command -v curl &>/dev/null; then
    curl -fsSL "$FORGE_RAW/$SCRIPT_DEST" -o "$SCRIPT_DEST"
else
    echo "Error: gh or curl is required to download forge-sync.sh." >&2
    exit 1
fi

chmod +x "$SCRIPT_DEST"
echo "Downloaded: $SCRIPT_DEST"
echo ""

# ── Run init ─────────────────────────────────────────────────────────────────
bash "$SCRIPT_DEST" --init
