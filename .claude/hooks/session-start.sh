#!/bin/bash
set -euo pipefail

# Only run in remote (web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Copy skills from repo to global skills directory
SKILLS_DIR="${HOME}/.claude/skills"
mkdir -p "$SKILLS_DIR"

for skill_dir in "$CLAUDE_PROJECT_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  if [ -f "$skill_dir/SKILL.md" ]; then
    mkdir -p "$SKILLS_DIR/$skill_name"
    cp -r "$skill_dir"/* "$SKILLS_DIR/$skill_name/"
  fi
done

# Copy agents from repo to global agents directory
AGENTS_DIR="${HOME}/.claude/agents"
mkdir -p "$AGENTS_DIR"

for agent_file in "$CLAUDE_PROJECT_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  cp "$agent_file" "$AGENTS_DIR/"
done
