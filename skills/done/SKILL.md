---
name: done
description: Complete work and push changes. Use when user types /done or says they are finished with the current task and ready to commit/push/create PR.
argument-hint: "[BT-number]"
allowed-tools: Bash, Read, Grep, Glob
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

12. **Bot review gate** — never proceed past this step with unresolved Copilot / CodeRabbit findings.

    **a. Wait for reviews to arrive (new PRs only):**
    For PRs created in step 9, poll every 60s for up to 10 minutes for `copilot-pull-request-reviewer[bot]` and `coderabbitai[bot]` reviews:
    ```bash
    gh api repos/{owner}/{repo}/pulls/{pr}/reviews \
      --jq '[.[] | select(.user.login | test("copilot|coderabbit"; "i")) | {user: .user.login, state}]'
    ```
    If both still missing after 10 min, note it in the report and continue to (b). Pre-existing PRs skip the wait.

    **b. Enumerate unresolved findings** — both inline threads AND top-level review bodies. Derive `OWNER`/`REPO` at runtime so the gate works in any repo:
    ```bash
    PR=$(gh pr view --json number --jq .number)
    OWNER=$(gh repo view --json owner --jq .owner.login)
    REPO=$(gh repo view --json name --jq .name)
    AUTHOR=$(gh api "repos/${OWNER}/${REPO}/pulls/${PR}" --jq .user.login)
    gh api graphql -f query="
    {
      repository(owner: \"${OWNER}\", name: \"${REPO}\") {
        pullRequest(number: ${PR}) {
          reviewThreads(first: 100) {
            pageInfo { hasNextPage endCursor }
            nodes {
              isResolved
              comments(first: 100) {
                pageInfo { hasNextPage endCursor }
                nodes { author { login } url body }
              }
            }
          }
          reviews(first: 100) {
            pageInfo { hasNextPage endCursor }
            nodes { author { login } state body url submittedAt }
          }
        }
      }
    }" --jq "
    {
      inline: [.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.comments.nodes[0].author.login | test(\"copilot|coderabbit\"; \"i\"))
        | select(.isResolved | not)
        | select([.comments.nodes[].author.login] | index(\"${AUTHOR}\") | not)
        | {url: .comments.nodes[0].url, body: (.comments.nodes[0].body[:200])}],
      top_level: [.data.repository.pullRequest.reviews.nodes[]
        | select(.author.login | test(\"copilot|coderabbit\"; \"i\"))
        | select(.body != null and .body != \"\")
        | select(.state != \"DISMISSED\")
        | select((.state == \"CHANGES_REQUESTED\")
              or (.body | test(\"Actionable comments posted: [1-9]\")))
        | {url, state, body: (.body[:200])}],
      pagination: {
        threads_has_next: .data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage,
        threads_end_cursor: .data.repository.pullRequest.reviewThreads.pageInfo.endCursor,
        reviews_has_next: .data.repository.pullRequest.reviews.pageInfo.hasNextPage,
        reviews_end_cursor: .data.repository.pullRequest.reviews.pageInfo.endCursor,
        thread_comments_has_next: [.data.repository.pullRequest.reviewThreads.nodes[]
          | .comments.pageInfo.hasNextPage] | any,
        thread_comment_cursors: [.data.repository.pullRequest.reviewThreads.nodes[]
          | select(.comments.pageInfo.hasNextPage)
          | {thread_url: .comments.nodes[0].url, end_cursor: .comments.pageInfo.endCursor}]
      }
    }"
    ```

    **Pagination:** If any `pagination.*_has_next` is `true`, re-issue the GraphQL query with `after: \"<endCursor>\"` on the relevant connection — use `threads_end_cursor` for `reviewThreads`, `reviews_end_cursor` for `reviews`, and the per-thread cursors in `thread_comment_cursors` for the inner `comments` connection — then merge the additional pages into the inline/top-level lists before deciding the gate. Skipping pagination would silently ignore findings on large PRs.

    **Dismissal heuristic:**
    - Inline thread is **resolved** if `isResolved: true` (marked resolved in UI) OR the PR author (`${AUTHOR}`) has replied anywhere in the thread. Any reply counts — even "wontfix" or "out of scope".
    - Top-level review body counts as a **finding** only when `state == CHANGES_REQUESTED` OR the body matches `Actionable comments posted: [1-9]` (CodeRabbit's marker). Reviews with `state == DISMISSED` are always excluded — dismissing a CodeRabbit review keeps the "Actionable comments posted: N" text in its body, so without this filter dismissed reviews would re-trigger the gate forever. This also filters out Copilot's "Pull request overview" summaries and CodeRabbit's "Actionable comments posted: 0" runs.

    **c. If any unresolved findings remain, HALT** and prompt the user explicitly:
    - Print each finding: URL + first ~200 chars of body, grouped by `inline` vs `top_level`.
    - Ask: "Found N unresolved bot review findings — what do you want to do?"
      1. **Resolve** → chain to `/resolve-pr` (handles enumerate → fix → reply → resolve threads → push). This is the recommended path.
      2. **Dismiss with reason** → reply to each thread with a justification (e.g. "out of scope, tracked in BT-XXXX") and resolve the thread, then re-run the gate.
      3. **Override** → user types `merge anyway` (exact phrase) to proceed despite findings. Log the override in the final report.
    - Do not proceed to step 13 without one of {resolve done, dismiss done, explicit override}.

    **d. If zero unresolved findings**, report ✅ and continue.

13. **Report success**: Confirm the commit was pushed, PR was created/updated (include PR URL), Linear was updated, and the bot review gate result (passed clean / passed after resolve / overridden by user with phrase). If overridden, include the count of skipped findings so the risk is visible in the report.

## When PR is merged

> **Note:** These steps are manual — there is no automation to detect merge events yet.

- Update issue state to "Done"
- Add `done` agent-state label to indicate completion
