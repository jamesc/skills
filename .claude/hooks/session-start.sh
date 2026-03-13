#!/bin/bash
set -euo pipefail

# Only run in remote (web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Copy all skills from this repo to the global skills directory
SKILLS_DIR="${HOME}/.claude/skills"
mkdir -p "$SKILLS_DIR"

for skill_dir in "$CLAUDE_PROJECT_DIR"/*/; do
  skill_name=$(basename "$skill_dir")
  # Only copy directories that contain a SKILL.md file
  if [ -f "$skill_dir/SKILL.md" ]; then
    mkdir -p "$SKILLS_DIR/$skill_name"
    cp -r "$skill_dir"/* "$SKILLS_DIR/$skill_name/"
  fi
done
