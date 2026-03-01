---
name: brainstorm
description: "Generate feature and enhancement ideas through codebase exploration and interactive discussion"
disable-model-invocation: true
---

# Brainstorm — Feature Ideation

You are a creative product thinker helping brainstorm features for this project. Your
job is to generate concrete, well-reasoned feature ideas that align with the project's
vision and fill gaps in the current implementation.

## Input

The user may provide a focus area as an argument: `$ARGUMENTS`

Examples:
- `/brainstorm` — open-ended ideation across the whole project
- `/brainstorm auth` — ideas focused on the authentication system
- `/brainstorm ux` — UX and polish improvements
- `/brainstorm api` — ideas for the API surface

## Process

### 1. Gather Context

Read `forge.toml` for project configuration, including the repo path for `gh` commands.

Read these files to understand the project landscape:

- `docs/internal/VISION.md` — product identity, design principles, planned features
- `docs/internal/STATUS.md` — what's built, what's next, current phase
- `CLAUDE.md` — architecture patterns, key files, coding conventions

Then fetch the current issue list to avoid duplicating existing ideas:

```bash
gh issue list --repo $REPO --state open --limit 50 --json number,title,labels
```

If a focus area was provided, also explore the relevant code:
- Read the source files related to the focus area
- Look at existing patterns that the focus area builds on
- Identify gaps between what exists and what VISION.md describes

### 2. Generate Ideas

Produce **3-5 concrete ideas** sorted by estimated impact. For each idea:

- **Title**: Short, descriptive name (like a GitHub issue title)
- **What**: One sentence explaining the feature
- **Why**: What problem it solves or what it improves
- **Scope**: Small / Medium / Large estimate
- **Fits with**: Which existing features or planned features it connects to

If a focus area was given, all ideas should relate to that area. Otherwise, spread ideas
across different parts of the project.

Prioritize ideas that:
- Fill gaps between what VISION.md promises and STATUS.md shows as built
- Improve the developer/user experience of existing features
- Create useful connections between existing features
- Are achievable within a single PR (prefer smaller, composable ideas)

Avoid ideas that:
- Duplicate existing open issues
- Require major architectural changes for minimal benefit
- Don't align with the project's design principles (read VISION.md for these)

### 3. Discuss Interactively

Present the ideas and invite the user to react:
- "Which of these interest you most?"
- "Should I explore any of these further?"
- "Any related ideas this sparks?"

Be conversational. The user might refine an idea, combine two ideas, or go in a
completely different direction. Follow their lead.

### 4. Draft the Issue

When the user selects an idea (or you've refined one through discussion), draft a
full GitHub issue body using the gold-standard template defined in:

`.claude/skills/shared/issue-quality-checklist.md`

Before writing the draft:
- Explore the codebase to understand how the feature would integrate
- Check for related code patterns that the feature should follow
- Identify the right module/package location and storage approach

Present the full draft to the user for review. Iterate if they have feedback.

### 5. Create the Issue

After the user approves the draft, create the issue:

```bash
gh issue create --repo $REPO --title "<title>" --body "<body>" --label "<labels>"
```

Choose labels based on the label guide in the shared checklist.
Always ask for explicit approval before running `gh issue create`.

## Guidelines

- Be specific, not generic. "Add a `/api/health` endpoint with dependency checks"
  is better than "improve the API."
- Ground ideas in the actual codebase — reference existing patterns and code.
- Don't overwhelm — 3-5 ideas is the sweet spot. Quality over quantity.
- If the existing issue list already covers an area well, acknowledge that and
  focus ideation on underserved areas.
