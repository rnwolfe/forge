#!/usr/bin/env bash
set -euo pipefail

# setup/create-labels.sh — Create all pipeline labels (idempotent)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/autodev/config.sh"

if [ -z "$AUTODEV_REPO" ]; then
    echo "Error: project.repo not set in forge.toml"
    exit 1
fi

create_label() {
    local name="$1" color="$2" desc="$3"
    if gh label create "$name" --repo "$AUTODEV_REPO" --color "$color" --description "$desc" 2>/dev/null; then
        echo "  Created: $name"
    else
        gh label edit "$name" --repo "$AUTODEV_REPO" --color "$color" --description "$desc" 2>/dev/null || true
        echo "  Exists:  $name"
    fi
}

echo "Creating pipeline labels on $AUTODEV_REPO..."

# Pipeline stage labels
create_label "backlog/triage"          "c5def5" "New issue, needs evaluation"
create_label "backlog/needs-spec"      "c5def5" "Passed evaluation, needs specification"
create_label "backlog/needs-refinement" "c5def5" "Has spec, needs refinement before implementation"
create_label "backlog/ready"           "0e8a16" "Issue is ready for autonomous implementation"
create_label "agent/implementing"      "1d76db" "Issue is currently being implemented by an agent"
create_label "agent/review-copilot"    "1d76db" "Agent is addressing Copilot review feedback"
create_label "agent/review-claude"     "1d76db" "Agent is addressing Claude review feedback"
create_label "agent/auto-merge"        "0e8a16" "All reviews done, auto-merge enabled"
create_label "human/blocked"           "d93f0b" "Agent hit a limit and needs human intervention"
create_label "human/review-merge"      "d93f0b" "All reviews done, needs human merge"

# Origin labels
create_label "via/actions"             "5319e7" "PR created by GitHub Actions pipeline"
create_label "via/autodev"             "5319e7" "PR created by /autodev CLI skill"

# Priority labels
create_label "priority/critical"       "b60205" "Highest urgency — autodev picks first"
create_label "priority/high"           "ff9f1c" "Important — autodev prefers over normal"

# Report labels
create_label "report/pipeline-audit"   "ededed" "Weekly pipeline health report issue"

# Common issue labels
create_label "feature"                 "a2eeef" "New feature request"
create_label "enhancement"             "a2eeef" "Improvement to existing feature"
create_label "bug"                     "d73a4a" "Something isn't working"
create_label "infrastructure"          "ededed" "CI/CD, tooling, pipeline improvements"

echo "Done."
