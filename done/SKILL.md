---
name: done
description: Complete work and push changes. Use when user types /done or says they are finished with the current task and ready to commit/push/create PR.
---

# Done Workflow

When activated, execute this workflow to complete work and push:

## Steps

1. **Determine Issue ID** per pick-issue step 1 (branch name → worktree name → ask user).
   If branch starts with `chore/`, `docs/`, or `refactor/` with no `BT-` prefix, treat as standalone — skip steps 10-11 (Linear updates) and omit issue ID from commit/PR.

2. **Check branch**: Verify we're NOT on `main` branch. If on main, stop and tell the user to create a feature branch first.

3. **Stage changes**:
   ```bash
   git add -A
   ```

4. **Check for changes**: Run `git status`. If there's nothing to commit, inform the user and stop.

5. **Run static checks** (skip for doc/config-only changes):
   If all changed files (staged + committed vs main) are docs/config (`.md`, `.json`, `.yaml`, `.toml`, etc.), skip CI.
   Otherwise run: `just build && just clippy && just fmt-check`. Stop on failure.

6. **Generate commit message**: Based on the staged diff (`git diff --cached`), create a conventional commit message:
   - Use format: `type: short description BT-{number}` (include issue ID when available)
   - Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
   - Keep first line under 72 characters
   - For chore/docs/refactor branches without an issue, omit `BT-{number}` (e.g., `chore: clean up dead code`)
   - Add bullet points for details if multiple changes

7. **Commit**:
   ```bash
   git commit -m "<generated message>"
   ```

8. **Push**:
   ```bash
   git push -u origin HEAD
   ```

9. **Create or update Pull Request**: Check if a PR already exists for this branch:
   ```bash
   gh pr list --head $(git branch --show-current) --json number,url --jq '.[0]'
   ```
   
   **If PR exists:** Skip creation — the push in step 8 already updated it. Note the existing PR URL for reporting.
   
   **If no PR exists:** Use the issue ID from step 1 (if available). Fetch the Linear issue title using the CLI:
   ```bash
   streamlinear-cli get BT-{number}
   ```
   Create the PR:
   ```bash
   gh pr create --title "<Issue Title> (BT-{number})" --body "<Issue description with link to Linear issue>"
   ```
   The PR body should include:
   - Link to Linear issue: `https://linear.app/beamtalk/issue/BT-{number}` (if issue exists)
   - Brief summary of what was implemented
   - List of key changes
   
   For chore/docs/refactor branches without a Linear issue, use a descriptive title based on the commit message and omit the Linear link.

10. **Update Linear acceptance criteria**: Use the CLI to add a comment on the issue summarising which acceptance criteria were completed with checkmarks (✅):
    ```bash
    streamlinear-cli comment BT-{number} "✅ Implemented: ..."
    ```

11. **Update Linear state**: Mark the Linear issue as "In Review":
    ```bash
    streamlinear-cli update BT-{number} --state "In Review"
    ```

12. **Wait for automated code reviews** (new PRs only — skip if PR already existed):
    Poll every 60s for up to 10 minutes for Copilot (`copilot-pull-request-reviewer[bot]`) and CodeRabbit (`coderabbitai[bot]`) reviews:
    ```bash
    gh api repos/{owner}/{repo}/pulls/{pr}/reviews --jq '.[] | select(.user.login | test("copilot|coderabbit"; "i")) | {user: .user.login, state}'
    ```
    - **Reviews with comments** → chain to `/resolve-pr` (it handles enumerate → fix → verify → push)
    - **Reviews with no comments** → report passed ✅
    - **Timeout** → report which reviews arrived, continue to step 13
    - **Pre-existing PR with unresolved threads** → chain to `/resolve-pr` directly, don't poll

13. **Report success**: Confirm the commit was pushed, PR was created/updated (include PR URL), Linear was updated, and review status for both Copilot and CodeRabbit.

## When PR is merged

> **Note:** These steps are manual — there is no automation to detect merge events yet.

- Update issue state to "Done"
- Add `done` agent-state label to indicate completion
