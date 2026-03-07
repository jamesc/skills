---
name: do-refactor
description: Execute a refactoring epic on a single branch, implementing all issues sequentially with CI verification after each. Use when user types /do-refactor or asks to execute a refactoring plan.
model: claude-opus-4-6
---

# Do Refactor Workflow

Execute a **refactoring epic** on a single branch, implementing all child issues sequentially. Each issue is a commit (or small group of commits), CI is verified after each, and a PR is created early and updated incrementally.

**Key Philosophy:** Refactoring epics block other work, so execute them quickly on one branch with continuous CI validation. Ship the whole epic as a single PR to minimize disruption. If any issue breaks CI, fix it before moving to the next.

## Steps

1. **Identify the epic**: Ask the user for the Epic ID (e.g., `BT-XXX`) or accept it from the command.

2. **Load the epic and child issues**: Fetch the epic and all child issues from Linear:
   ```bash
   streamlinear-cli get BT-XXX
   # Then fetch child issues (use graphql for parent/child relationships)
   streamlinear-cli graphql "query { issue(id: \"<epic-uuid>\") { children { nodes { id identifier title description priority state { name } labels { nodes { name } } relations { nodes { type relatedIssue { identifier state { name } } } } } } } }"
   ```

   Build an ordered list respecting dependencies (blocked issues come after their blockers). If no explicit ordering, use: high priority first, smallest first (S before M before L).

3. **Validate prerequisites**:
   - All child issues must be `agent-ready` (have acceptance criteria, files to modify)
   - If any issue is `needs-spec`, STOP and tell the user which ones need specification
   - If any issue is `In Progress`, STOP — another agent is already working on it
   - Check that no child issue is already `Done` (skip those)
   - Ensure clean working tree: `git status --porcelain` must be empty

4. **Create the branch**: One branch for the entire epic:
   ```bash
   git fetch origin main
   git checkout -b refactor/BT-XXX origin/main
   ```
   Use `refactor/BT-XXX` naming convention (epic ID, not individual issue IDs).

5. **Verify baseline CI passes**:
   ```bash
   just ci
   ```
   If baseline CI fails, STOP — don't start refactoring on a broken main.

6. **Execute issues sequentially**: For each child issue (in dependency order):

   **a. Pick up the issue** (invoke the `pick-issue` skill with the issue ID):
   ```
   /pick-issue BT-YYY
   ```
   This loads the issue context, sets it to In Progress, reads acceptance criteria, and identifies files to modify. Review the safety principles:
     - Behavioral preservation (structure changes, not behavior)
     - Refactor under test (tests exist or add them first)
     - Incremental delivery (code works after this commit)

   **b. Implement the refactoring:**
   - Make the changes specified in the acceptance criteria
   - Follow all AGENTS.md guidelines (DDD, error handling, logging, license headers)
   - Keep changes minimal and focused on the issue scope
   - If the issue requires adding tests first, do that in a separate commit

   **c. Verify CI passes:**
   ```bash
   just ci
   ```

   **If CI fails:**
   - Fix the failure (it's caused by your refactoring)
   - Re-run `just ci` until it passes
   - If stuck after 3 attempts, STOP and ask the user for help
   - Do NOT move to the next issue with broken CI

   **d. Review the changes** (invoke the `review-code` skill):
   ```
   /review-code
   ```
   This runs a multi-pass code review against main. Fix any issues found before committing. Re-run `just ci` if changes were made.

   **e. Commit with issue ID:**
   ```bash
   git add -A
   git commit -m "refactor: <description> BT-YYY"
   ```
   One commit per issue (or a small group if the issue has distinct phases like "add tests" then "refactor").

   **f. Complete the issue:**
   ```bash
   streamlinear-cli update BT-YYY --state Done
   ```

   **g. Create or update the PR:**

   *After the FIRST issue:* Create the PR immediately (**no auto-merge** — human review required):
   ```bash
   git push -u origin HEAD
   gh pr create --title "Refactor: <epic title> BT-XXX" --body "<PR body>"
   ```
   Do NOT use `--auto-merge` or enable auto-merge. Refactoring PRs must be reviewed by a human.

   *After subsequent issues:* Push to update the existing PR:
   ```bash
   git push
   ```

   Add a PR comment summarising what was just completed:
   ```
   ✅ **BT-YYY: <issue title>** — Done
   - <brief summary of changes>
   - CI: passing
   - Progress: X/Y issues complete
   ```

7. **Handle failures gracefully**: If an issue cannot be completed:

   **Recoverable (fix and continue):**
   - CI failure caused by the refactoring → fix it
   - Minor acceptance criteria ambiguity → use best judgment, note in commit
   - Merge conflict with changes pushed to main → `git fetch origin main && git merge origin/main`, resolve, re-run CI

   **Blocking (stop and ask):**
   - Issue is `needs-spec` or acceptance criteria are unclear
   - CI failure that isn't caused by the refactoring (pre-existing)
   - Issue requires behavioral changes (not just structural refactoring)
   - Stuck after 3 fix attempts on the same CI failure
   - Issue depends on another issue that isn't in this epic

   When stopping:
   - Push current progress (all completed issues are already committed)
   - Update the PR with status
   - Tell the user which issue is blocking and why
   - Mark the blocking issue as blocked in Linear:
     ```bash
     streamlinear-cli update BT-YYY --state "Backlog"
     streamlinear-cli comment BT-YYY "Blocked: <explanation>"
     ```

8. **Final verification**: After all issues are complete:
   ```bash
   # Ensure we're up to date with main
   git fetch origin main
   git merge origin/main
   # If conflicts, resolve them

   # Final CI run on the complete refactoring
   just ci
   ```

9. **Update the PR**: Edit the PR body with the final summary:
   ```markdown
   ## Refactor: <Epic Title> (BT-XXX)

   ### Issues Completed
   - ✅ BT-YY1: <title> — <one-line summary>
   - ✅ BT-YY2: <title> — <one-line summary>
   - ...

   ### Changes Summary
   - **Files changed:** X
   - **Lines added/removed:** +N / -M
   - **CI status:** All passing

   ### Safety Verification
   - [ ] All existing tests pass without modification (behavioral preservation)
   - [ ] Each commit leaves CI green (incremental delivery)
   - [ ] No behavioral changes — structure only (or explicitly noted)

   ### Testing
   - `just ci` passes on final state
   - Each intermediate commit verified with `just ci`
   ```

10. **Update the epic**: Mark the epic as Done (or note remaining issues):
    ```bash
    # If all child issues complete:
    streamlinear-cli update BT-XXX --state Done

    # If some issues remain:
    streamlinear-cli update BT-XXX --state "In Progress"
    streamlinear-cli comment BT-XXX "Partial completion: X/Y issues done. Remaining: BT-YYY, ..."
    ```

11. **Notify the user**: Summary of what was accomplished:
    ```markdown
    ## Refactoring Complete

    **Epic:** BT-XXX — <title>
    **PR:** #NNN
    **Issues completed:** X/Y
    **Branch:** refactor/BT-XXX
    **Status:** Ready for review
    ```

---

## Guidelines

### Branch Strategy

**One branch, one PR, entire epic.** This minimises disruption:
- Other developers see one PR to review, not N small ones
- Merge conflicts are handled once, not per-issue
- Refactoring is atomic — either the whole thing merges or none of it does
- Bisecting is still possible since each issue is a separate commit

### Commit Discipline

- **One commit per issue** (sometimes two: "add tests" + "refactor")
- **Always include issue ID** in commit message: `refactor: description BT-YYY`
- **Never squash** — preserve the per-issue history for bisecting
- **CI must pass after every commit** — no "I'll fix it in the next one"

### When to Merge Main

Merge `origin/main` into the refactoring branch:
- Before starting (step 4 — branch from latest main)
- If the epic takes multiple days
- After all issues complete (step 8 — final merge before PR review)
- If a CI failure suggests main has diverged

Do NOT rebase — merge preserves commit history and is safer for large refactorings.

### PR Body Updates

Update the PR body (not just comments) as issues complete. The PR body should always reflect current state:
- Which issues are done ✅
- Which issue is in progress 🔄
- Which issues remain ⏳
- Any blockers 🚫

### Safety Checklist

Before marking the epic complete, verify:
- [ ] `just ci` passes on the final state
- [ ] No `unwrap()` added on user input
- [ ] No bare tuple errors in Erlang code
- [ ] License headers on all new files
- [ ] DDD naming conventions followed
- [ ] Module-level doc comments include bounded context
- [ ] No new clippy warnings
