---
name: resolve-pr
description: Address PR review comments systematically. Use when user types /resolve-pr or asks to fix/address PR feedback, review comments, or requested changes.
argument-hint: "[PR number or BT-number]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# PR Resolve Workflow

When activated, execute this workflow to systematically address all PR review comments:

## Steps

1. **Determine Issue ID** per pick-issue step 1 (branch name → worktree name → ask user).

2. **Enumerate ALL unresolved threads — never declare "no comments" without evidence**:

   Fetch from all three sources and print a numbered list of everything found:

   **Review threads** (code-level, includes CodeRabbit and Copilot): Use the GitHub MCP `pull_request_read` tool with method `get_review_comments`. Capture `threadId` (node ID, e.g. `PRRT_kwDO…`) and `isResolved`/`isOutdated` for each.

   **General PR comments** (conversation-level): Use method `get_comments`. Includes bot summary comments from CodeRabbit and Copilot.

   **Bot reviews explicitly**: Also fetch reviews from named bots:
   ```bash
   gh api repos/{owner}/{repo}/pulls/{pr}/reviews --jq '.[] | select(.user.login | test("copilot|coderabbit|github-copilot"; "i")) | {id, state, user: .user.login}'
   ```

   **RULE:** You MUST show the raw count from each source before saying there is nothing to do. "0 threads, 0 general comments, 0 bot reviews" is the only acceptable "nothing to do" output.

3. **Analyze and plan**: For each review comment:
   - Understand what the reviewer is asking for
   - Determine if it needs a code fix, documentation, Linear issue, or just clarification
   - Create a todo list with all items to address

4. **Run tests first**: Verify current state passes all checks:
   ```bash
   just ci
   ```
   This runs all CI checks (build, clippy, fmt-check, test, test-e2e).

5. **Write tests for behavioral changes**: For code fixes that change logic or behavior:
   - Write a failing test that demonstrates the bug or missing behavior
   - Run the test to confirm it fails as expected
   - This ensures the fix is verifiable and prevents regressions
   
   **Skip tests for:** Naming changes, documentation updates, style/formatting fixes, comment improvements — these don't need TDD.

6. **Address each comment**: For each item in the plan:
   - Make the necessary code changes to make the test pass
   - Run tests after each significant change to catch regressions early
   - If a comment requires a follow-up Linear issue (e.g., "TODO for later"):
     - Create the Linear issue with full context
     - Add a TODO comment in the code referencing the issue number
   - Mark the todo item complete

7. **Run full test suite**: After all changes:
   ```bash
   just ci
   ```

8. **Commit changes**: Stage and commit with a descriptive message (using issue ID from step 1):
   ```bash
   git add -A
   git commit -m "fix: address PR review comments BT-{number}

   - Summary of each fix
   - Reference any Linear issues created"
   ```

9. **Push changes**:
   ```bash
   git push
   ```

10. **Reply to each comment**: For every review comment that was addressed, add a reply explaining what was done:
   ```bash
   gh api repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies -f body="<explanation of fix, commit hash, any Linear issues created>"
   ```
   Include:
    - Commit hash where the fix was made
    - Brief description of the change
    - Links to any Linear issues created for follow-up work

11. **Resolve review threads**: After replying, resolve each addressed review thread using the GraphQL API:
    ```bash
    gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<thread_node_id>"}) { thread { isResolved } } }'
    ```
    The thread node ID (e.g., `PRRT_kwDO...`) is available from the `get_review_comments` response in step 2. Only resolve threads where the fix has been committed and pushed.

12. **Final verification pass** — re-fetch all threads after pushing and confirm completeness:
    ```bash
    # Re-fetch review threads and check none are still unresolved
    gh api repos/{owner}/{repo}/pulls/{pr}/comments --jq '[.[] | {id, path, resolved: false}] | length'
    # Re-fetch bot reviews
    gh api repos/{owner}/{repo}/pulls/{pr}/reviews --jq '[.[] | select(.state == "CHANGES_REQUESTED")] | length'
    ```
    Also re-run the GitHub MCP `get_review_comments` to confirm `isResolved: true` on every thread addressed.

    **Do not proceed to step 13 until every thread is verified resolved or explicitly acknowledged as a known skip (e.g. outdated).**

13. **Report summary**: Provide a summary table of all comments and how they were resolved, with thread IDs and commit hashes.

14. **Auto-chain to done**: If all review comments have been successfully resolved (no failures, no pending issues), automatically activate the `done` skill:
    - Inform the user that all PR comments have been addressed
    - Activate the `done` skill without waiting for user confirmation
    
    If there are any issues or manual steps needed, report them and wait for user input instead.
