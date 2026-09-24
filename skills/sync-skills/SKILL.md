---
name: sync-skills
description: Sync modified skills and agents back to the repo and create a PR. Use when user types /sync-skills or wants to save in-session skill improvements.
allowed-tools: Bash, Read, Glob, Grep
---

# Sync Skills Back to Repo

Sync any skills or agents that were modified during this session back to the source repository and create a PR with the changes.

There are two install modes this needs to handle, since either can be active on a given machine:

- **Global symlink install** (`scripts/install.sh`): `~/.claude/skills/<name>` and `~/.claude/agents/<name>.md` are symlinks straight into the repo's own `skills/<name>/` and `agents/<name>.md`. Editing the installed skill *is* editing the repo — there is nothing to copy, only to commit.
- **Per-project clone install** (`scripts/init.sh`): a project checked out `.claude/skills-repo` as a real clone and symlinked `.claude/commands/<name>` / `.claude/agents/<name>.md` into it. Same "editing is editing the repo" property, but the repo lives inside the current project instead of at a fixed user-level path.

Neither mode requires copying files by hand — `scripts/sync-skills.sh`'s copy step exists only for a stale/non-symlinked install (e.g. someone `cp`'d a skill instead of symlinking); on both modes above it will find no diffs, which is expected, not a bug.

## Steps

1. **Locate the skills repo** — try each of these in order, stop at the first that resolves:
   - **Global install:** resolve `$REPO_DIR` from a known symlink rather than guessing a path:
     ```bash
     REPO_DIR="$(dirname "$(dirname "$(readlink -f ~/.claude/skills/sync-skills)")")"
     ```
     `readlink -f ~/.claude/skills/sync-skills` resolves to `<repo>/skills/sync-skills`; stripping two path components gives `<repo>`. If `~/.claude/skills/sync-skills` isn't a symlink (`readlink` prints nothing), this mode isn't active — move on.
   - **Per-project clone:** check `.claude/skills-repo` in the current project:
     ```bash
     [ -d .claude/skills-repo ] && REPO_DIR="$(cd .claude/skills-repo && pwd)"
     ```
   - **Neither found:** tell the user no skills-repo install was detected on this machine, and point them at the repo's `scripts/init.sh` (per-project) or `scripts/install.sh` (global) to set one up. Stop.

2. **Detect changes**: with `$REPO_DIR` resolved, changes are already live in the repo's working tree under either mode (nothing to diff against an external "installed" copy) — just check its git status:
   ```bash
   git -C "$REPO_DIR" status --short -- skills/ agents/
   ```
   If empty, inform the user that all skills/agents match the repo's last commit and stop.

3. **Run the sync script**:
   ```bash
   bash "$REPO_DIR/scripts/sync-skills.sh"
   ```
   This diffs `~/.claude/skills`/`~/.claude/agents` against `$REPO_DIR/skills`/`$REPO_DIR/agents` (a no-op under the symlink-install modes above — same inode either way), then falls back to `git status` on `$REPO_DIR` itself so a direct edit to a symlinked skill/agent is still caught, before creating a branch, committing, pushing, and opening a PR via `gh` if there's anything to commit. Run it with `$REPO_DIR` as resolved in step 1 — do not assume it lives under `$CLAUDE_PROJECT_DIR` (the *current project*, e.g. `beamtalk`), since the skills repo is a separate, unrelated repo.

   If the script isn't present (older repo checkout) or fails for a reason other than "nothing to sync", fall back to manual steps from `$REPO_DIR`:
   ```bash
   cd "$REPO_DIR"
   git checkout -b sync/skill-updates
   git add skills/ agents/
   git commit -m "sync: skill improvements from session"
   git push -u origin HEAD
   gh pr create --title "sync: skill improvements from session" --body "Synced from project session"
   ```

4. **Report results**:
   - If changes were synced and a PR was created, share the PR URL and summarize what changed.
   - If the script/manual push fails (e.g., no git permissions, no `gh` CLI), report the exact failure and suggest the manual steps above.

5. **Verify**: Confirm the PR was created and the changes look correct:
   ```bash
   gh pr view --repo "$(git -C "$REPO_DIR" remote get-url origin | sed -E 's#.*/([^/]+/[^/]+)(\.git)?$#\1#')" --json url,title,state
   ```
