---
name: done
description: Complete work and push changes. Use when user types /done or says they are finished with the current task and ready to commit/push/create PR.
argument-hint: "[BT-number]"
allowed-tools: Bash, Read, Grep, Glob, mcp__linear-server__get_issue, mcp__linear-server__save_issue, mcp__linear-server__save_comment
---

# Done Workflow

When activated, execute this workflow to complete work and push:

## Steps

1. **Determine Issue ID**: resolve in priority order — (1) current branch name matching `BT-{number}-*`, (2) git worktree directory name matching `BT-{number}`, (3) ask the user. (This is its own resolution order, not `pick-issue`'s step 1 — that skill additionally falls back to a Linear backlog query, which doesn't apply here since `/done` always operates on work already in progress on a known branch.)
   If branch starts with `chore/`, `docs/`, or `refactor/` with no `BT-` prefix, treat as standalone — skip steps 10-11 (Linear updates) and omit issue ID from commit/PR.

2. **Check branch**: Verify we're NOT on `main` branch. If on main, stop and tell the user to create a feature branch first.

3. **Stage changes**:
   ```bash
   git add -A
   ```

4. **Check for changes**: Run `git status`. If there's nothing to commit, inform the user and stop.

5. **Run static checks and tests** (skip entirely for doc/config-only changes):
   If all changed files (staged + committed vs main) are docs/config (`.md`, `.json`, `.yaml`, `.toml`, etc.), skip this step.
   Otherwise run: `just build && just clippy && just fmt-check`. Stop on failure.

   **Tests:** run `just test` — unless `just test`/`just ci`/`just ci-changed` already ran
   clean earlier in this session against the exact same changes, with no files touched since
   (e.g. `/pick-issue` step 14 or `/review-code` Pass 3 already ran it right before chaining
   here). If anything changed since that run — including review-driven fixes — re-run `just
   test`. When unsure whether it's stale, run it; a redundant ~10s run is cheaper than a broken
   push.

   If any changed files are under `stdlib/`, `examples/`, or other corpus-source paths,
   also run `just build-corpus` and stage the regenerated `crates/beamtalk-examples/corpus.json`
   if it changed — this is exactly what `just ci`'s `check-corpus` step (and the pre-push hook)
   would otherwise catch, but catching it here avoids a fix-and-repush cycle after step 8.

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

   **If the pre-push hook fails** (it runs full CI), decide based on *where* the failure is:
   - **In code this change touches** → stop and fix it; the gate is doing its job. Do not bypass.
   - **Clearly unrelated / environmental** (e.g. a toolchain or OTP-version mismatch, or a failure in already-merged code this branch didn't touch — confirm the same code passes on `main`) → re-push with `git push --no-verify origin HEAD`, **state the exact reason in the final report**, and offer to file a follow-up issue for the broken hook/toolchain.

   When in doubt, treat it as related and fix it — only bypass when you can name why the failure is not yours.

   **Flaky post-push CI:** if a check goes red after pushing and the failure isn't explained by your change, reproduce locally; if local passes, re-run the failed job once (`gh run rerun <run-id> --failed`). Green on re-run = flaky, note it and continue; same failure again = treat as real. One re-run decides it — don't loop.

9. **Create or update Pull Request**: Check if a PR already exists for this branch:
   ```bash
   gh pr list --head $(git branch --show-current) --json number,url --jq '.[0]'
   ```
   
   **If PR exists:** Skip creation — the push in step 8 already updated it. Note the existing PR URL for reporting.
   
   **If no PR exists:** Use the issue ID from step 1 (if available). Fetch the Linear issue title with `get_issue` (id: "BT-{number}"). Create the PR:
   ```bash
   gh pr create --title "<Issue Title> (BT-{number})" --body "<Issue description with link to Linear issue>"
   ```
   The PR body should include:
   - Link to Linear issue: `https://linear.app/beamtalk/issue/BT-{number}` (if issue exists)
   - Brief summary of what was implemented
   - List of key changes
   
   For chore/docs/refactor branches without a Linear issue, use a descriptive title based on the commit message and omit the Linear link.

10. **Update Linear acceptance criteria**: Use `save_comment` (issueId: "BT-{number}", body: "✅ Implemented: ...") to add a comment on the issue summarising which acceptance criteria were completed with checkmarks (✅).

11. **Update Linear state**: Mark the Linear issue as "In Review" with `save_issue` (id: "BT-{number}", state: "In Review").

12. **Bot review gate** — never proceed past this step with unresolved review-bot findings.

    The CI reviewer is the **Claude review bot**, which runs as the **`Claude BeamTalk Review`**
    CI workflow (`.github/workflows/claude-review.yml`, `anthropics/claude-code-action`) and
    posts its findings as inline review threads, always `state: COMMENTED` (non-blocking) — so
    this gate keys off *unresolved threads*, never review state.

    **Bot identity — do not assume `claude[bot]`:** the workflow calls
    `anthropics/claude-code-action` without an explicit `github_token` input, so it authenticates
    with the default `GITHUB_TOKEN` and posts comments as **`github-actions[bot]`**
    (GraphQL `author.login` for this actor is the bare string `"github-actions"`, no `[bot]`
    suffix — GraphQL strips it for `Bot`-typed actors). Confirmed both via `gh api
    repos/{owner}/{repo}/pulls/comments/{id}` (`user.login: "github-actions[bot]"`,
    `user.type: "Bot"`) and the GraphQL query below. `claude-review.yml` is the only workflow in
    this repo with `pull-requests: write` that posts inline review comments, so `github-actions`
    is an unambiguous signal here — but the filter below still checks for a literal `claude`
    login too, in case the workflow is later switched to a dedicated GitHub App token. A filter
    that only matches `claude` will silently miss every finding — this happened once already
    (BT-3617's PR #4033: two real, correct findings went unenumerated by this gate until a human
    caught it) — so don't narrow this back down without re-verifying the actual `author.login`
    on a live PR first.

    Resolve `PR`, `OWNER`, `REPO` once up front so both subsections can use them:
    ```bash
    PR=$(gh pr view --json number --jq .number)
    OWNER=$(gh repo view --json owner --jq .owner.login)
    REPO=$(gh repo view --json name --jq .name)
    ```

    **a. Wait for reviews to arrive (new PRs only):**
    The Claude review is posted when its CI workflow finishes, so wait on the check rather than on a
    timer — poll the `Claude BeamTalk Review` check until it leaves the `pending` bucket:
    ```bash
    for _ in $(seq 1 30); do   # ~15 min safety cap at 30s/iteration
      BUCKET=$(gh pr checks "${PR}" --repo "${OWNER}/${REPO}" --json name,bucket \
        --jq '.[] | select(.name == "Claude BeamTalk Review") | .bucket')
      [ -n "$BUCKET" ] && [ "$BUCKET" != "pending" ] && break
      sleep 30
    done
    ```
    - When the check completes, the bot's inline threads (posted as `github-actions[bot]` — see the identity note above) are ready to enumerate in (b). If the check never appears within the cap, note it in the report and continue to (b).
    - Pre-existing PRs skip the wait.

    **b. Enumerate unresolved findings** — the Claude review bot posts findings as inline
    threads only (its review bodies are empty and always `COMMENTED`), so top-level review
    state is never the signal — judge by unresolved threads:
    ```bash
    gh api graphql -f query="
    {
      repository(owner: \"${OWNER}\", name: \"${REPO}\") {
        pullRequest(number: ${PR}) {
          reviewThreads(first: 100) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              isResolved
              comments(first: 100) {
                pageInfo { hasNextPage endCursor }
                nodes { author { login } url body }
              }
            }
          }
        }
      }
    }" --jq "
    {
      inline: [.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.comments.nodes | length > 0)
        | select(.comments.nodes[0].author.login | test(\"claude|github-actions\"; \"i\"))
        | select(.isResolved | not)
        | {url: .comments.nodes[0].url, body: (.comments.nodes[0].body[:200])}],
      pagination: {
        threads_has_next: .data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage,
        threads_end_cursor: .data.repository.pullRequest.reviewThreads.pageInfo.endCursor,
        thread_comments_has_next: [.data.repository.pullRequest.reviewThreads.nodes[]
          | .comments.pageInfo.hasNextPage] | any,
        thread_comment_cursors: [.data.repository.pullRequest.reviewThreads.nodes[]
          | select(.comments.pageInfo.hasNextPage)
          | select(.comments.nodes | length > 0)
          | {thread_id: .id, thread_url: .comments.nodes[0].url, end_cursor: .comments.pageInfo.endCursor}]
      }
    }"
    ```

    **Pagination:** If any `pagination.*_has_next` is `true`, re-issue the GraphQL query with `after: "<endCursor>"` on the relevant connection — use `threads_end_cursor` for `reviewThreads`, and the per-thread cursors in `thread_comment_cursors` for the inner `comments` connection — then merge the additional pages into the inline list before deciding the gate. Skipping pagination would silently ignore findings on large PRs.

    Concrete syntax — the cursor is an `after:` argument on the same connection field:
    ```graphql
    reviewThreads(first: 100, after: "<threads_end_cursor>") { ... }
    ```
    Per-thread `comments` pagination requires re-querying the specific thread by `thread_id` (now surfaced in `thread_comment_cursors`), then paging its `comments(first: 100, after: "<end_cursor>")` — for example via `node(id: "<thread_id>") { ... on PullRequestReviewThread { comments(first: 100, after: "<end_cursor>") { ... } } }`.

    **Resolution rule:** an inline thread only counts as resolved when `isResolved: true` — a
    reply alone does not close it. This matches `/resolve-pr` and `/pick-epic`, which both call
    the `resolveReviewThread` mutation after replying, and matches step (c).2 below, which
    requires resolving the thread even when dismissing with a reason.

    **c. If any unresolved findings remain, HALT** and prompt the user explicitly:
    - Print each finding: URL + first ~200 chars of body.
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
