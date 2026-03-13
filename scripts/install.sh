#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

SKILLS_DIR="${HOME}/.claude/skills"
AGENTS_DIR="${HOME}/.claude/agents"
mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"

echo "Installing skills..."
for skill_dir in "$REPO_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  [ -f "$skill_dir/SKILL.md" ] || continue
  ln -sfn "$skill_dir" "$SKILLS_DIR/$skill_name"
  echo "  Linked: $skill_name"
done

echo "Installing agents..."
agent_count=0
for agent_file in "$REPO_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  ln -sfn "$agent_file" "$AGENTS_DIR/$(basename "$agent_file")"
  echo "  Linked: $(basename "$agent_file")"
  ((agent_count++)) || true
done
if [ $agent_count -eq 0 ]; then
  echo "  (no agents found)"
fi

echo "Done. Skills and agents are symlinked — edits in the repo are live immediately."
