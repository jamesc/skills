#!/bin/bash
set -euo pipefail

# Shared sync logic: diffs ~/.claude/skills and ~/.claude/agents against repo,
# copies changes back, creates a branch, commits, pushes, and opens a PR.
#
# Usage: scripts/sync-skills.sh [--auto]
#   --auto: used by SessionStop hook, skips if no changes

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AUTO_MODE="${1:-}"
SKILLS_SRC="${HOME}/.claude/skills"
AGENTS_SRC="${HOME}/.claude/agents"
SKILLS_DST="$REPO_DIR/skills"
AGENTS_DST="$REPO_DIR/agents"
CHANGES=""

cd "$REPO_DIR"

# Sync skills back
for skill_dir in "$SKILLS_SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  [ -f "$skill_dir/SKILL.md" ] || continue

  # Skip if this skill doesn't exist in the repo (externally installed)
  [ -d "$SKILLS_DST/$skill_name" ] || continue

  if ! diff -rq "$skill_dir" "$SKILLS_DST/$skill_name/" >/dev/null 2>&1; then
    cp -r "$skill_dir"/* "$SKILLS_DST/$skill_name/"
    CHANGES="${CHANGES}\n- **$skill_name** (skill): updated"
  fi
done

# Sync agents back
for agent_file in "$AGENTS_SRC"/*.md; do
  [ -f "$agent_file" ] || continue
  agent_name=$(basename "$agent_file")

  # Skip if this agent doesn't exist in the repo
  [ -f "$AGENTS_DST/$agent_name" ] || continue

  if ! diff -q "$agent_file" "$AGENTS_DST/$agent_name" >/dev/null 2>&1; then
    cp "$agent_file" "$AGENTS_DST/$agent_name"
    CHANGES="${CHANGES}\n- **$agent_name** (agent): updated"
  fi
done

# Exit early if no changes
if [ -z "$CHANGES" ]; then
  if [ "$AUTO_MODE" = "--auto" ]; then
    exit 0
  fi
  echo "No changes detected between installed and repo skills/agents."
  exit 0
fi

# Create branch, commit, push, and open PR
BRANCH="sync/skills-$(date +%Y%m%d-%H%M%S)"
git checkout -b "$BRANCH"
git add skills/ agents/
git commit -m "$(cat <<EOF
sync: skill improvements from session

Changes detected:
$(echo -e "$CHANGES")
EOF
)"

git push -u origin "$BRANCH"

# Create PR if gh is available
if command -v gh >/dev/null 2>&1; then
  gh pr create \
    --title "sync: skill improvements from session" \
    --body "$(cat <<EOF
## Summary

Skills/agents were modified during a Claude Code session and synced back to the repo.

## Changes
$(echo -e "$CHANGES")

## Details

$(git diff HEAD~1 --stat)
EOF
)"
  echo "PR created successfully."
else
  echo "Changes pushed to $BRANCH. Create a PR manually (gh CLI not available)."
fi
