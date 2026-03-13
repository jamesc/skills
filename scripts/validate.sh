#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ERRORS=0
WARNINGS=0

# Colors (disabled in CI)
if [ -t 1 ]; then
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  GREEN='\033[0;32m'
  NC='\033[0m'
else
  RED='' YELLOW='' GREEN='' NC=''
fi

error() { ((ERRORS++)) || true; echo -e "${RED}ERROR${NC}: $1"; }
warn()  { ((WARNINGS++)) || true; echo -e "${YELLOW}WARN${NC}: $1"; }
ok()    { echo -e "${GREEN}OK${NC}: $1"; }

# Valid frontmatter fields
SKILL_FIELDS="name description model argument-hint allowed-tools"
AGENT_FIELDS="name description tools disallowedTools model maxTurns permissionMode isolation background skills mcpServers hooks memory"

# Extract YAML frontmatter lines (between first and second ---)
get_frontmatter() {
  local file="$1"
  awk 'BEGIN{c=0} /^---$/{c++;next} c==1{print} c>=2{exit}' "$file"
}

# Extract frontmatter value for a given key from a file
get_field() {
  local file="$1" key="$2"
  get_frontmatter "$file" | grep -E "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//" || true
}

# Get all frontmatter keys from a file
get_keys() {
  local file="$1"
  get_frontmatter "$file" | grep -E '^[a-zA-Z]' | sed 's/:.*//' || true
}

# Check if a string is valid kebab-case
is_kebab_case() {
  [[ "$1" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]]
}

echo "=== Validating skills ==="
echo ""

skill_count=0
for skill_dir in "$REPO_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  skill_file="$skill_dir/SKILL.md"

  if [ ! -f "$skill_file" ]; then
    error "$skill_name: missing SKILL.md"
    continue
  fi

  # Check required fields
  name=$(get_field "$skill_file" "name")
  description=$(get_field "$skill_file" "description")

  if [ -z "$name" ]; then
    error "$skill_name: missing required field 'name'"
  else
    # Name should match directory
    if [ "$name" != "$skill_name" ]; then
      error "$skill_name: name field '$name' does not match directory name '$skill_name'"
    fi
    # Name should be kebab-case
    if ! is_kebab_case "$name"; then
      error "$skill_name: name '$name' is not valid kebab-case"
    fi
  fi

  if [ -z "$description" ]; then
    error "$skill_name: missing required field 'description'"
  elif [ ${#description} -lt 10 ]; then
    warn "$skill_name: description is very short (${#description} chars)"
  fi

  # Validate model field if present
  model=$(get_field "$skill_file" "model")
  if [ -n "$model" ] && [[ ! "$model" =~ ^claude- ]]; then
    error "$skill_name: model '$model' does not match expected pattern (claude-*)"
  fi

  # Check for unknown fields
  get_keys "$skill_file" | while IFS= read -r key; do
    [ -z "$key" ] && continue
    if ! echo "$SKILL_FIELDS" | grep -qw "$key"; then
      echo "WARN_UNKNOWN: $skill_name: unknown frontmatter field '$key'"
    fi
  done

  ((skill_count++)) || true
done

echo ""
echo "=== Validating agents ==="
echo ""

agent_count=0
for agent_file in "$REPO_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  agent_name=$(basename "$agent_file" .md)

  # Skip .gitkeep or non-md files
  [[ "$agent_name" == ".gitkeep" ]] && continue

  name=$(get_field "$agent_file" "name")
  description=$(get_field "$agent_file" "description")

  if [ -z "$name" ]; then
    error "$agent_name: missing required field 'name'"
  else
    if [ "$name" != "$agent_name" ]; then
      error "$agent_name: name field '$name' does not match filename '$agent_name'"
    fi
    if ! is_kebab_case "$name"; then
      error "$agent_name: name '$name' is not valid kebab-case"
    fi
  fi

  if [ -z "$description" ]; then
    error "$agent_name: missing required field 'description'"
  elif [ ${#description} -lt 10 ]; then
    warn "$agent_name: description is very short (${#description} chars)"
  fi

  model=$(get_field "$agent_file" "model")
  if [ -n "$model" ] && [[ ! "$model" =~ ^claude- ]]; then
    error "$agent_name: model '$model' does not match expected pattern (claude-*)"
  fi

  get_keys "$agent_file" | while IFS= read -r key; do
    [ -z "$key" ] && continue
    if ! echo "$AGENT_FIELDS" | grep -qw "$key"; then
      echo "WARN_UNKNOWN: $agent_name: unknown frontmatter field '$key'"
    fi
  done

  ((agent_count++)) || true
done

if [ $agent_count -eq 0 ]; then
  echo "(no agents found)"
fi

echo ""
echo "=== Summary ==="
echo "Skills: $skill_count | Agents: $agent_count | Errors: $ERRORS | Warnings: $WARNINGS"

if [ $ERRORS -gt 0 ]; then
  exit 1
fi
echo "All checks passed."
