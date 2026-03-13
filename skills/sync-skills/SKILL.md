---
name: sync-skills
description: Sync modified skills and agents back to the repo and create a PR. Use when user types /sync-skills or wants to save in-session skill improvements.
---

# Sync Skills Back to Repo

Sync any skills or agents that were modified during this session back to the source repository and create a PR with the changes.

## Workflow

1. Run the sync script:

```bash
"$CLAUDE_PROJECT_DIR/scripts/sync-skills.sh"
```

2. If the script reports no changes, inform the user that all installed skills/agents match the repo.

3. If changes were found and a PR was created, share the PR URL with the user and summarize what changed.

4. If the script fails (e.g., no git permissions, no gh CLI), help the user resolve the issue or suggest manual steps.
