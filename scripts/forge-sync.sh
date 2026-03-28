#!/usr/bin/env bash
# scripts/forge-sync.sh — Sync pipeline files from upstream forge template
#
# Fetches the diff between the forge commit your project was scaffolded from
# and the latest forge commit, then applies it to the paths listed in
# .forge/manifest.json.
#
# Usage:
#   ./scripts/forge-sync.sh                  # Apply updates from latest forge
#   ./scripts/forge-sync.sh --dry-run        # Preview changes without applying
#   ./scripts/forge-sync.sh --install-action # Install weekly auto-sync GitHub Action
#
# Requires: git, gh (GitHub CLI), jq

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
MANIFEST="$ROOT_DIR/.forge/manifest.json"
ACTION_TEMPLATE="$ROOT_DIR/setup/forge-sync-action.yml"
ACTION_DEST="$ROOT_DIR/.github/workflows/forge-sync.yml"

# ── Parse flags ──────────────────────────────────────────────────────────────
DRY_RUN=false
INSTALL_ACTION=false
for arg in "$@"; do
    case "$arg" in
        --dry-run)        DRY_RUN=true ;;
        --install-action) INSTALL_ACTION=true ;;
        -h|--help)
            echo "Usage: forge-sync.sh [--dry-run] [--install-action]"
            echo ""
            echo "  --dry-run         Preview changes without applying"
            echo "  --install-action  Install weekly auto-sync GitHub Action"
            exit 0
            ;;
    esac
done

# ── Install GitHub Action ────────────────────────────────────────────────────
if [ "$INSTALL_ACTION" = true ]; then
    if [ ! -f "$ACTION_TEMPLATE" ]; then
        echo "Error: $ACTION_TEMPLATE not found." >&2
        exit 1
    fi
    if [ -f "$ACTION_DEST" ]; then
        echo "forge-sync GitHub Action is already installed at $ACTION_DEST"
        exit 0
    fi
    cp "$ACTION_TEMPLATE" "$ACTION_DEST"
    echo "Installed: $ACTION_DEST"
    echo ""
    echo "Commit and push to activate the weekly sync:"
    echo "  git add .github/workflows/forge-sync.yml"
    echo "  git commit -m 'ci: add weekly forge template sync'"
    exit 0
fi

# ── Validate prerequisites ───────────────────────────────────────────────────
for cmd in git gh jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        case "$cmd" in
            gh)  echo "  Install: https://cli.github.com" >&2 ;;
            jq)  echo "  Install: https://jqlang.github.io/jq/download/" >&2 ;;
        esac
        exit 1
    fi
done

if [ ! -f "$MANIFEST" ]; then
    cat >&2 <<'EOF'
Error: .forge/manifest.json not found.

Run /onboard to initialize it, or create it manually:

  mkdir -p .forge && cat > .forge/manifest.json <<JSON
  {
    "template": "rnwolfe/forge",
    "commit": "<forge-commit-sha>",
    "synced_at": null,
    "synced_paths": [
      ".claude/skills/",
      ".claude/settings.json",
      "scripts/autodev/",
      ".github/workflows/autodev-dispatch.yml",
      ".github/workflows/autodev-implement.yml",
      ".github/workflows/autodev-review-fix.yml",
      ".github/workflows/claude-code-review.yml",
      ".github/workflows/autodev-audit.yml",
      "setup/"
    ]
  }
JSON

Replace <forge-commit-sha> with the forge commit your project was scaffolded from.
Hint: git log --oneline | grep "initialize project from forge"
EOF
    exit 1
fi

# ── Read manifest ────────────────────────────────────────────────────────────
TEMPLATE_REPO=$(jq -r '.template' "$MANIFEST")
PINNED_COMMIT=$(jq -r '.commit' "$MANIFEST")

if [ -z "$TEMPLATE_REPO" ] || [ "$TEMPLATE_REPO" = "null" ]; then
    echo "Error: .forge/manifest.json is missing the 'template' field." >&2
    exit 1
fi

if [ -z "$PINNED_COMMIT" ] || [ "$PINNED_COMMIT" = "null" ]; then
    cat >&2 <<EOF
Error: .forge/manifest.json has an empty 'commit' field.

The commit field records which forge version your project was scaffolded from.
Find it by looking at your initial commit:

  git log --oneline | grep -i "forge"

Then update .forge/manifest.json:
  "commit": "<that-sha>"
EOF
    exit 1
fi

# ── Check for updates ────────────────────────────────────────────────────────
echo "Checking $TEMPLATE_REPO for updates..."

LATEST_COMMIT=$(gh api "repos/$TEMPLATE_REPO/commits/main" --jq '.sha' 2>/dev/null) || {
    echo "Error: Could not reach $TEMPLATE_REPO via gh API." >&2
    echo "Make sure gh is authenticated (gh auth status) and the repo is accessible." >&2
    exit 1
}

LATEST_SHORT="${LATEST_COMMIT:0:7}"
PINNED_SHORT="${PINNED_COMMIT:0:7}"

if [ "$PINNED_COMMIT" = "$LATEST_COMMIT" ]; then
    echo "Already up to date (forge @ $PINNED_SHORT)."
    exit 0
fi

echo "Update available: $PINNED_SHORT → $LATEST_SHORT"
echo ""

# ── Clone template ───────────────────────────────────────────────────────────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Fetching forge template..."
git clone --quiet --filter=blob:none \
    "https://github.com/$TEMPLATE_REPO.git" "$TMP/forge" 2>/dev/null

# Verify the pinned commit exists in the cloned repo
if ! git -C "$TMP/forge" cat-file -e "${PINNED_COMMIT}^{commit}" 2>/dev/null; then
    echo "Error: Pinned commit $PINNED_SHORT not found in $TEMPLATE_REPO." >&2
    echo "The commit may have been force-pushed away. Update .forge/manifest.json" >&2
    echo "to a commit that exists in the repo's history." >&2
    exit 1
fi

# ── Generate diff ────────────────────────────────────────────────────────────
mapfile -t SYNCED_PATHS < <(jq -r '.synced_paths[]' "$MANIFEST")

echo "Diffing: ${SYNCED_PATHS[*]}"
echo ""

PATCH=$(git -C "$TMP/forge" diff "$PINNED_COMMIT" HEAD -- "${SYNCED_PATHS[@]}" 2>/dev/null || true)

if [ -z "$PATCH" ]; then
    echo "No changes in synced paths between $PINNED_SHORT and $LATEST_SHORT."
    if [ "$DRY_RUN" = false ]; then
        UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        TMP_MANIFEST=$(mktemp)
        jq --arg commit "$LATEST_COMMIT" --arg ts "$UPDATED_AT" \
            '.commit = $commit | .synced_at = $ts' \
            "$MANIFEST" > "$TMP_MANIFEST"
        mv "$TMP_MANIFEST" "$MANIFEST"
    fi
    exit 0
fi

# ── Dry run ──────────────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
    echo "--- Diff preview ($PINNED_SHORT → $LATEST_SHORT) ---"
    echo ""
    echo "$PATCH"
    exit 0
fi

# ── Apply patch ──────────────────────────────────────────────────────────────
echo "Applying changes..."
cd "$ROOT_DIR"

CONFLICTS=false
if echo "$PATCH" | git apply --3way - 2>/dev/null; then
    echo "Changes applied cleanly."
else
    echo ""
    echo "Warning: Some hunks had conflicts and were left with conflict markers."
    echo "Resolve them before committing."
    CONFLICTS=true
fi

# ── Update manifest ──────────────────────────────────────────────────────────
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TMP_MANIFEST=$(mktemp)
jq --arg commit "$LATEST_COMMIT" --arg ts "$UPDATED_AT" \
    '.commit = $commit | .synced_at = $ts' \
    "$MANIFEST" > "$TMP_MANIFEST"
mv "$TMP_MANIFEST" "$MANIFEST"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "forge-sync: $PINNED_SHORT → $LATEST_SHORT"
echo ""

if [ "$CONFLICTS" = true ]; then
    echo "Next steps:"
    echo "  1. Resolve merge conflicts (search for <<<<<<< in modified files)"
    echo "  2. git add -A"
    echo "  3. git commit -m 'chore: sync forge template updates'"
else
    echo "Next steps:"
    echo "  1. Review: git diff --cached"
    echo "  2. git add .forge/manifest.json"
    echo "  3. git commit -m 'chore: sync forge template updates'"
fi
