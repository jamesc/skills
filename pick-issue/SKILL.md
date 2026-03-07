---
name: pick-issue
description: Start working on next Linear issue. Use when user types /pick-issue or asks to pick up the next task from the backlog.
---

# Next Issue Workflow

When activated, execute this workflow to start working on the next Linear issue:

## Steps

### 1. Determine Issue ID

The issue ID is determined in priority order:

1. **Explicit argument**: If user provides an issue ID, use that issue.
   - `/pick-issue BT-42` → issue BT-42
   - `/pick-issue 42` → issue BT-42 (BT- prefix added automatically)

2. **Worktree name**: If in a git worktree with a name matching `BT-{number}`, use that issue:
   ```bash
   # Check if this is a worktree
   git rev-parse --git-dir 2>/dev/null | grep -q "worktrees"

   # Extract issue ID from directory name
   basename "$(pwd)" | grep -oE '^BT-[0-9]+'
   ```
   Example: `/workspaces/BT-34` → issue `BT-34`

3. **Backlog query**: Query Linear for the highest priority `agent-ready` issue from the backlog that has no unresolved blockers (all blocking issues must be Done):
   ```bash
   streamlinear-cli search --state "Backlog" --team BT
   # Then filter results to those with the agent-ready label and no unresolved blockers
   ```

### 2. Fetch Issue Details

Get the full issue details from Linear:
```bash
streamlinear-cli get BT-{number}
```

### 3. Validate Issue State

Before proceeding, verify the issue is workable:
- **Must have `agent-ready` label** — if `needs-spec`, stop and tell the user the issue needs specification first.
- **Must not be `Done` or `In Progress`** — if already done, inform the user. If in progress by someone else, warn and ask for confirmation.
- **Must not be `blocked`** — check that all blocking issues are Done. If blockers remain, list them and stop.

If using backlog query (step 1.3), these checks are implicit. If using explicit ID or worktree, these checks are essential.

### 4. Check Working Tree

Before switching branches, verify no uncommitted changes would be lost:
```bash
git status --porcelain
```
If there are uncommitted changes, warn the user and suggest stashing or committing first. Do not proceed with `git checkout` until the working tree is clean.

### 5. Update Main Branch (if not already on issue branch)

Skip this step if:
- Already on a branch named `BT-{number}*`
- In a worktree for this issue

Otherwise:
```bash
git checkout main
git pull origin main
```

### 6. Create Feature Branch (if not already on issue branch)

Skip if already on a matching branch. Otherwise create:
- Format: `BT-{number}-{slug}`
- Example: `BT-7-implement-lexer`
- Slug: lowercase, hyphens, max 30 chars

```bash
git checkout -b BT-{number}-{slug}
```

### 7. Update Linear

Mark the issue as "In Progress":
```bash
streamlinear-cli update BT-{number} --state "In Progress"
```

### 8. Create Todo List

Break down the acceptance criteria into actionable tasks using the todo list tool.

### 9. Pattern Lookup (Required for .bt or Erlang FFI work)

Before writing any new Beamtalk or Erlang FFI code, search the codebase for
3+ existing examples of the pattern you're about to implement. This prevents
wrong syntax assumptions (e.g. `::` not `:` for type annotations, block `^`
semantics, DNU behavior).

```bash
# Find existing examples of the relevant pattern in Beamtalk source
grep -r "PATTERN" stdlib/test/ stdlib/src/ examples/ --include="*.bt" | head -10
# For Erlang FFI / runtime
grep -r "relevant_module" runtime/apps/ --include="*.erl" | head -10
```

Review the hits, note the exact syntax used, then implement consistently.
If no examples exist, read `docs/beamtalk-language-features.md` first.

Skip only for pure Rust changes with no Beamtalk syntax involved.

### 10. Start Implementation

Begin working on the issue, following AGENTS.md guidelines.

### 11. Test Frequently

After each significant change, run the fast test suite:
```bash
just test
```
This runs unit tests (~10s). Save full CI for the final check before code review.

### 12. Commit Often

Make small, focused commits as you complete each task. Use conventional commit format with the issue ID:
```
type: description BT-{number}
```

### 13. Push Regularly

Push after each commit to keep the remote updated.

### 14. Run Full CI

Before completing, run the full CI suite to catch any issues:
```bash
just ci
```
This runs all CI checks (build, clippy, fmt-check, test, test-e2e). Fix any failures before proceeding.

### 15. Auto-chain: resolve → review → done

After implementation, chain automatically through the remaining skills:

1. **Check for existing PR** (`gh pr list --head $(git branch --show-current)`).
   If one exists with unresolved review comments → chain to `/resolve-pr`.
2. Chain to `/review-code`. If review finds 🔴/🟡 issues, fix them and re-run `just ci`.
3. Chain to `/done`.

Only stop for user input if review identifies 🔵 issues requiring design decisions.
