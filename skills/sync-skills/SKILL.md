---
name: sync-skills
description: Sync modified skills and agents back to the repo and create a PR. Use when user types /sync-skills or wants to save in-session skill improvements.
allowed-tools: Bash, Read, Glob, Grep
---

# Sync Skills Back to Repo

Sync any skills or agents that were modified during this session back to the source repository and create a PR with the changes.

## Steps

1. **Locate the skills repo**: Find the cloned skills repo at `.claude/skills-repo`:
   ```bash
   ls -la .claude/skills-repo/
   ```
   If it doesn't exist, inform the user and suggest running `scripts/init.sh` first.

2. **Detect changes**: Compare installed skills/agents against the repo source:
   ```bash
   diff -rq .claude/commands/ .claude/skills-repo/skills/ --exclude='.gitkeep' 2>/dev/null
   diff -rq .claude/agents/ .claude/skills-repo/agents/ --exclude='.gitkeep' 2>/dev/null
   ```
   If no differences found, inform the user that all installed skills/agents match the repo and stop.

3. **Run the sync script** (if available):
   ```bash
   bash "$CLAUDE_PROJECT_DIR/scripts/sync-skills.sh"
   ```
   If the script doesn't exist, perform manual sync:
   - Copy modified skill files back to the skills repo working tree
   - Create a branch, commit, push, and open a PR using `gh`

4. **Report results**:
   - If changes were synced and a PR was created, share the PR URL and summarize what changed
   - If the script fails (e.g., no git permissions, no `gh` CLI), suggest manual steps:
     ```bash
     cd .claude/skills-repo
     git checkout -b sync/skill-updates
     git add -A && git commit -m "chore: sync skill updates from project"
     git push -u origin HEAD
     gh pr create --title "chore: sync skill updates" --body "Synced from project session"
     ```

5. **Verify**: Confirm the PR was created and the changes look correct:
   ```bash
   gh pr view --json url,title,state
   ```
