#!/bin/bash
set -euo pipefail

# Usage: curl -sL <raw-url>/scripts/init.sh | bash
#   or:  ./path/to/skills/scripts/init.sh
#
# Run this from the root of any project repo to set up Claude Code
# skills and agents from the shared skills repository.

SKILLS_REPO="${SKILLS_REPO_URL:-https://github.com/jamesc/skills.git}"
SKILLS_BRANCH="${SKILLS_BRANCH:-main}"
TARGET_DIR=".claude/skills-repo"

echo "==> Initializing Claude Code skills in $(pwd)"

# Clone or update the skills repo
if [ -d "$TARGET_DIR" ]; then
  echo "  Skills repo already cloned at $TARGET_DIR, pulling latest..."
  git -C "$TARGET_DIR" pull origin "$SKILLS_BRANCH" --ff-only
else
  echo "  Cloning skills repo..."
  mkdir -p .claude
  git clone --branch "$SKILLS_BRANCH" --single-branch "$SKILLS_REPO" "$TARGET_DIR"
fi

# Link skills into .claude/commands (project-level)
COMMANDS_DIR=".claude/commands"
mkdir -p "$COMMANDS_DIR"

echo "==> Linking skills..."
for skill_dir in "$TARGET_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  [ -f "$skill_dir/SKILL.md" ] || continue
  ln -sfn "../../$TARGET_DIR/skills/$skill_name" "$COMMANDS_DIR/$skill_name"
  echo "  Linked: $skill_name"
done

# Link agents
AGENTS_DIR=".claude/agents"
mkdir -p "$AGENTS_DIR"

echo "==> Linking agents..."
agent_count=0
for agent_file in "$TARGET_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  ln -sfn "../../$TARGET_DIR/agents/$(basename "$agent_file")" "$AGENTS_DIR/$(basename "$agent_file")"
  echo "  Linked: $(basename "$agent_file")"
  ((agent_count++)) || true
done
if [ $agent_count -eq 0 ]; then
  echo "  (no agents found)"
fi

# Copy hooks if not already present
HOOKS_DIR=".claude/hooks"
mkdir -p "$HOOKS_DIR"

echo "==> Copying hooks..."
for hook_file in "$TARGET_DIR"/.claude/hooks/*.sh; do
  [ -f "$hook_file" ] || continue
  hook_name=$(basename "$hook_file")
  if [ ! -f "$HOOKS_DIR/$hook_name" ]; then
    cp "$hook_file" "$HOOKS_DIR/$hook_name"
    chmod +x "$HOOKS_DIR/$hook_name"
    echo "  Copied hook: $hook_name"
  else
    echo "  Hook exists, skipping: $hook_name"
  fi
done

# Add skills-repo to .gitignore if not already there
if [ -f .gitignore ]; then
  if ! grep -qF '.claude/skills-repo' .gitignore; then
    # Ensure we append on a new line even if the file lacks a trailing newline
    [ -s .gitignore ] && [ "$(tail -c1 .gitignore)" != "" ] && echo "" >> .gitignore
    echo '.claude/skills-repo' >> .gitignore
    echo "==> Added .claude/skills-repo to .gitignore"
  fi
else
  echo '.claude/skills-repo' > .gitignore
  echo "==> Created .gitignore with .claude/skills-repo"
fi

echo ""
echo "Done! Skills and agents are linked into .claude/"
echo "  - Skills:  $COMMANDS_DIR/"
echo "  - Agents:  $AGENTS_DIR/"
echo "  - Source:   $TARGET_DIR/"
echo ""
echo "To update later, run: git -C $TARGET_DIR pull"
