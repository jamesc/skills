#!/bin/bash
set -euo pipefail

# Only run in remote (web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Sync any skill/agent improvements back to the repo and open a PR
"$CLAUDE_PROJECT_DIR/scripts/sync-skills.sh" --auto
