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
#   ./scripts/forge-sync.sh --init           # Enroll an existing project (no manifest yet)
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
FORCE=false
INIT=false
INSTALL_ACTION=false
for arg in "$@"; do
    case "$arg" in
        --dry-run)        DRY_RUN=true ;;
        --force)          FORCE=true ;;
        --init)           INIT=true ;;
        --install-action) INSTALL_ACTION=true ;;
        -h|--help)
            echo "Usage: forge-sync.sh [--dry-run] [--force] [--init] [--install-action]"
            echo ""
            echo "  --dry-run         Preview changes without applying"
            echo "  --force           Overwrite all synced files with forge versions (no merge)"
            echo "  --init            Enroll an existing project that has no manifest yet"
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
    mkdir -p "$(dirname "$ACTION_DEST")"
    cp "$ACTION_TEMPLATE" "$ACTION_DEST"
    echo "Installed: $ACTION_DEST"
    echo ""
    echo "Commit and push to activate the weekly sync:"
    echo "  git add .github/workflows/forge-sync.yml"
    echo "  git commit -m 'ci: add weekly forge template sync'"
    exit 0
fi

# ── Init: enroll an existing project ────────────────────────────────────────
if [ "$INIT" = true ]; then
    if [ -f "$MANIFEST" ]; then
        EXISTING_COMMIT=$(jq -r '.commit' "$MANIFEST" 2>/dev/null || true)
        if [ -n "$EXISTING_COMMIT" ] && [ "$EXISTING_COMMIT" != "null" ] && [ "$EXISTING_COMMIT" != "" ]; then
            echo "Already initialized (.forge/manifest.json exists with commit ${EXISTING_COMMIT:0:7})."
            echo "Run ./scripts/forge-sync.sh to check for updates."
            exit 0
        fi
    fi

    # Prereqs for init
    for cmd in gh jq; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: $cmd is required but not installed." >&2
            case "$cmd" in
                gh) echo "  Install: https://cli.github.com" >&2 ;;
                jq) echo "  Install: https://jqlang.github.io/jq/download/" >&2 ;;
            esac
            exit 1
        fi
    done

    TEMPLATE_REPO="rnwolfe/forge"

    # Clone forge so we can find its first commit and run the initial sync
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    echo "Fetching forge template..."
    CLONE_ERR=$(mktemp)
    if ! git clone --quiet --filter=blob:none \
            "https://github.com/$TEMPLATE_REPO.git" "$TMP/forge" 2>"$CLONE_ERR"; then
        echo "Error: failed to clone $TEMPLATE_REPO." >&2
        cat "$CLONE_ERR" >&2
        exit 1
    fi

    # Pin to the first-ever forge commit so the sync brings in everything
    GENESIS_COMMIT=$(git -C "$TMP/forge" rev-list --max-parents=0 HEAD)
    LATEST_COMMIT=$(git -C "$TMP/forge" rev-parse HEAD)
    GENESIS_SHORT="${GENESIS_COMMIT:0:7}"
    LATEST_SHORT="${LATEST_COMMIT:0:7}"

    SYNCED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    mkdir -p "$(dirname "$MANIFEST")"
    cat > "$MANIFEST" <<EOF
{
  "template": "$TEMPLATE_REPO",
  "commit": "$GENESIS_COMMIT",
  "synced_at": "$SYNCED_AT",
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
EOF

    echo "Initialized: .forge/manifest.json"
    echo "Syncing all forge changes from $GENESIS_SHORT → $LATEST_SHORT..."
    echo ""

    # Run the sync immediately so missing files are added now.
    # Re-exec without --init so it goes through the normal sync path.
    # Clean up TMP first — the trap won't fire after exec.
    rm -rf "$TMP"
    exec "$0"
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

If this project was scaffolded from forge before forge-sync existed, run:
  ./scripts/forge-sync.sh --init

For new projects, run /onboard (it writes the manifest automatically).
Or create it manually:

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
CLONE_ERR=$(mktemp)
if ! git clone --quiet --filter=blob:none \
        "https://github.com/$TEMPLATE_REPO.git" "$TMP/forge" 2>"$CLONE_ERR"; then
    echo "Error: failed to clone $TEMPLATE_REPO." >&2
    cat "$CLONE_ERR" >&2
    exit 1
fi

# Verify the pinned commit exists in the cloned repo
if ! git -C "$TMP/forge" cat-file -e "${PINNED_COMMIT}^{commit}" 2>/dev/null; then
    echo "Error: Pinned commit $PINNED_SHORT not found in $TEMPLATE_REPO." >&2
    echo "The commit may have been force-pushed away. Update .forge/manifest.json" >&2
    echo "to a commit that exists in the repo's history." >&2
    exit 1
fi

# ── Collect changed files ────────────────────────────────────────────────────
mapfile -t SYNCED_PATHS < <(jq -r '.synced_paths[]' "$MANIFEST")

echo "Diffing: ${SYNCED_PATHS[*]}"
echo ""

# --no-renames: treat renames as delete+add, keeps status parsing simple
mapfile -t CHANGED_FILES < <(
    git -C "$TMP/forge" diff --name-status --no-renames \
        "$PINNED_COMMIT" HEAD -- "${SYNCED_PATHS[@]}" 2>/dev/null || true
)

if [ ${#CHANGED_FILES[@]} -eq 0 ]; then
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
    echo "--- Changes ($PINNED_SHORT → $LATEST_SHORT) ---"
    echo ""
    for entry in "${CHANGED_FILES[@]}"; do
        status=$(printf '%s' "$entry" | cut -f1)
        filepath=$(printf '%s' "$entry" | cut -f2)
        case "${status:0:1}" in
            A) echo "  [add]    $filepath" ;;
            M) echo "  [update] $filepath" ;;
            D) echo "  [skip]   $filepath  (deleted upstream, kept locally)" ;;
            *) echo "  [?]      $filepath  ($status)" ;;
        esac
    done
    echo ""
    echo "Run without --dry-run to apply."
    exit 0
fi

# ── Apply changes file by file ───────────────────────────────────────────────
# Uses git merge-file for modified files — a true 3-way merge that works
# without the base blobs being present in the target repo's object store.
echo "Applying changes..."
cd "$ROOT_DIR"

CONFLICTS=false
N_ADDED=0
N_UPDATED=0
N_CONFLICTED=0

for entry in "${CHANGED_FILES[@]}"; do
    status=$(printf '%s' "$entry" | cut -f1)
    filepath=$(printf '%s' "$entry" | cut -f2)
    forge_new="$TMP/forge/$filepath"
    project_file="$ROOT_DIR/$filepath"

    case "${status:0:1}" in
        A)
            # New file in forge — copy directly
            mkdir -p "$(dirname "$project_file")"
            cp "$forge_new" "$project_file"
            git add "$filepath"
            N_ADDED=$((N_ADDED + 1))
            echo "  added:    $filepath"
            ;;
        M)
            if [ ! -f "$project_file" ]; then
                # File was deleted locally — restore from forge
                mkdir -p "$(dirname "$project_file")"
                cp "$forge_new" "$project_file"
                git add "$filepath"
                N_ADDED=$((N_ADDED + 1))
                echo "  restored: $filepath"
            else
                if [ "$FORCE" = true ]; then
                    cp "$forge_new" "$project_file"
                    git add "$filepath"
                    N_UPDATED=$((N_UPDATED + 1))
                    echo "  updated:  $filepath (overwritten)"
                else
                    # True 3-way merge: ours=project, base=old forge, theirs=new forge
                    forge_old=$(mktemp)
                    git -C "$TMP/forge" show "${PINNED_COMMIT}:${filepath}" \
                        > "$forge_old" 2>/dev/null || cp "$forge_new" "$forge_old"

                    if git merge-file -q "$project_file" "$forge_old" "$forge_new"; then
                        git add "$filepath"
                        N_UPDATED=$((N_UPDATED + 1))
                        echo "  updated:  $filepath"
                    else
                        # git merge-file leaves conflict markers in $project_file
                        N_CONFLICTED=$((N_CONFLICTED + 1))
                        CONFLICTS=true
                        echo "  conflict: $filepath"
                    fi
                    rm -f "$forge_old"
                fi
            fi
            ;;
        D)
            # Deleted upstream — leave the local file alone
            echo "  skipped:  $filepath  (removed from forge, kept locally)"
            ;;
    esac
done

# ── Update manifest ──────────────────────────────────────────────────────────
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TMP_MANIFEST=$(mktemp)
jq --arg commit "$LATEST_COMMIT" --arg ts "$UPDATED_AT" \
    '.commit = $commit | .synced_at = $ts' \
    "$MANIFEST" > "$TMP_MANIFEST"
mv "$TMP_MANIFEST" "$MANIFEST"
git add "$MANIFEST"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "forge-sync: $PINNED_SHORT → $LATEST_SHORT"
echo "  $N_ADDED added, $N_UPDATED updated, $N_CONFLICTED conflicted"
echo ""

if [ "$CONFLICTS" = true ]; then
    echo "Next steps:"
    echo "  1. Resolve conflicts (search for <<<<<<< in the files listed above)"
    echo "  2. git add -A"
    echo "  3. git commit -m 'chore: sync forge template updates'"
else
    echo "Next steps:"
    echo "  1. Review: git diff --cached"
    echo "  2. git commit -m 'chore: sync forge template updates'"
fi
