#!/usr/bin/env bash
set -euo pipefail

# setup/configure-branch-protection.sh — Configure branch protection rules

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/autodev/config.sh"

if [ -z "$AUTODEV_REPO" ]; then
    echo "Error: project.repo not set in forge.toml"
    exit 1
fi

echo "Configuring branch protection for $AUTODEV_REPO ($AUTODEV_BASE_BRANCH)..."

# Note: This requires admin access to the repository.
# If it fails, the user needs to configure this manually via GitHub Settings.
if gh api -X PUT "repos/$AUTODEV_REPO/branches/$AUTODEV_BASE_BRANCH/protection" \
    --input - <<'EOF' 2>/dev/null; then
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["test"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0
  },
  "restrictions": null
}
EOF
    echo "  Branch protection configured for $AUTODEV_BASE_BRANCH"
else
    echo "  Warning: Could not configure branch protection."
    echo "  You may need admin access. Configure manually:"
    echo "    Settings > Branches > Branch protection rules"
    echo "    - Require status checks: 'test'"
    echo "    - Require branches to be up to date"
fi

echo "Done."
