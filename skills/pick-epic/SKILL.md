---
name: pick-epic
description: Execute an epic by running children in dependency-ordered waves using parallel subagents, one isolated worktree and PR per issue, squash-merging as CI and the Claude review bot (plus CodeRabbit when available) pass. Use when user types /pick-epic or asks to execute an epic with parallel agents.
model: opus
argument-hint: "BT-XXX (epic ID)"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, mcp__linear-server__get_issue, mcp__linear-server__list_issues, mcp__linear-server__save_issue, mcp__linear-server__save_comment
---

# Pick Epic Workflow

Execute an epic by grouping its children into **dependency-ordered waves** and running each wave as **parallel subagents**, one per issue. Each issue gets its own isolated worktree, its own PR (squash-merged to main), and is merged as soon as CI passes and the **Claude review bot** (`claude[bot]`, the CI reviewer) is satisfied — plus CodeRabbit when it has reviewed. Waves are sequential — Wave N+1 starts only after all Wave N PRs are merged.

**Key difference from `/do-refactor`:** This skill uses isolated worktrees and parallel subagents for maximum throughput — one PR per issue, not one PR for the whole epic. Use this for any L/XL epic where issues touch non-overlapping files.

---

## Steps

### 1. Load the epic and children

Load the epic with `get_issue` (id: "BT-XXX") — it accepts the `BT-XXX` shorthand directly, no UUID needed.

Then fetch all child issues with their blocking relationships and sizes. This is a two-step fetch:

1. List the children with `list_issues` (parentId: "BT-XXX") to get each child's identifier, title, and state.
2. For each child, call `get_issue` (id: "BT-YYY") to read its labels and blocking relationships — `get_issue` returns the full labels and relationships; `list_issues` does not return full relations.

### 2. Validate and filter

- Skip children already `Done` or `In Progress`
- Skip children with `needs-spec` label — tell the user which ones need spec
- Stop if any blocking issue is not `Done` (the epic has unresolved external dependencies)
- Confirm `agent-ready` label is present on all workable children

### 3. Build dependency-ordered waves

Group children into waves using these rules:

**Wave assignment:**
- **Wave 1:** Issues with no unresolved blockers within this epic
- **Wave N+1:** Issues whose blockers are all in Wave N or earlier
- **Within a wave:** Sort by size (S → M → L → XL) then by priority

**Conflict check:** Within a wave, scan file overlap between issues. If two issues in the same wave touch the same files, push the lower-priority one to the next wave.

Present the wave plan and proceed immediately — no confirmation needed:
```
Wave 1 (parallel): BT-XXX (S), BT-YYY (M), BT-ZZZ (M)
Wave 2 (parallel): BT-AAA (L), BT-BBB (L)
Wave 3 (parallel): BT-CCC (XL)
```

Only pause if dependency ordering is ambiguous (e.g. two issues block each other, or a blocker is not in this epic).

### 4. Execute waves sequentially

For each wave:

**4a. Launch one subagent per issue in the wave (all in parallel):**

Before launching, write the **agent ledger** for this wave (a simple table, kept in your own report/scratch notes — not a file the subagents share): `issue | worktree path | branch | agent id/name | status`. Populate it as each agent starts. Verify before launch:
- No issue appears twice (no two agents assigned to the same issue).
- No two agents share a worktree path.
- Each planned worktree path is not already in use by a leftover worktree from a prior run (`git worktree list`) — remove stale ones first.

Use `Agent` tool with `isolation: "worktree"` and `run_in_background: true` for every issue in the wave simultaneously. Each agent receives a complete self-contained prompt (see **Agent Prompt Template** below).

**4b. Wait for all agents in the wave to complete.** Update the ledger's `status` column as each agent finishes (done / failed / needs-fix) — use the ledger, not memory, to track what's left in the wave. If an agent's returned worktree path or branch doesn't match its ledger entry, stop and reconcile before continuing (see **When to Stop and Ask**).

**4c. For each completed agent:**
- Check the PR URL returned
- Watch CI: `gh pr view <PR> --json statusCheckRollup`
- If CI fails: diagnose the failure, push a fix to the agent's branch
- **Wait for automated reviews** before merging:
  - **Claude review bot** (the anchor): it runs as the `Claude BeamTalk Review` CI check and posts inline findings when that check finishes. Wait on the check, not a timer:
    ```bash
    for _ in $(seq 1 30); do   # ~15 min safety cap at 30s/iteration
      BUCKET=$(gh pr checks <PR> --repo <owner>/<repo> --json name,bucket \
        --jq '.[] | select(.name == "Claude BeamTalk Review") | .bucket')
      [ -n "$BUCKET" ] && [ "$BUCKET" != "pending" ] && break
      sleep 30
    done
    ```
    If the check never appears within the cap, note it in the merge summary and proceed.
  - **CodeRabbit**: best-effort — give it time to reply, but skip it if rate-limited or absent:
    ```bash
    gh api repos/<owner>/<repo>/pulls/<PR>/reviews \
      --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | {state, body: .body[:120]}]'
    ```
    If its review body contains "usage limits", "rate limit", or "couldn't generate", or it hasn't posted by the time the Claude check completes, skip it and proceed.
- **Handle Claude review bot findings**: its reviews are always `COMMENTED` (non-blocking), but the findings are the primary signal — see **Handling Claude Review Bot Findings** below.
- **Handle CodeRabbit reviews**: If CodeRabbit requests changes:
  - Fix genuine issues introduced by the PR (scope creep, bugs)
  - Dismiss pre-existing issues with a comment: "Pre-existing code, not introduced by this PR"
  - Dismiss scope-creep feedback with a comment explaining the deliberate choice
  - Use `gh api -X PUT repos/<owner>/<repo>/pulls/<PR>/reviews/<review-id>/dismissals -f message="..."` to dismiss blocking reviews
- Once all checks pass and no blocking reviews remain, merge:
  ```bash
  gh pr merge <PR> --squash --admin
  ```
- After merge, clean up the agent's worktree to reclaim disk space:
  ```bash
  git worktree remove --force <worktree-path>
  git branch -D <branch-name>
  ```

**4d. Once all PRs in the wave are merged**, start Wave N+1.

### 5. Mark Linear issues Done

After each PR is merged, update the child with `save_issue` (id: "BT-YYY", state: "Done").

### 6. Mark the epic Done

After all waves complete:
- Mark the epic Done with `save_issue` (id: "BT-XXX", state: "Done").
- Post a completion comment with `save_comment` (issueId: "BT-XXX", body: "All child issues completed in <N> waves. PRs: #P1, #P2, ...").

### 7. Report to user

```
## Epic Complete: BT-XXX — <title>

Wave 1: BT-AAA (#PR1, merged), BT-BBB (#PR2, merged)
Wave 2: BT-CCC (#PR3, merged), BT-DDD (#PR4, merged)

Total: X issues, Y PRs, merged in Z waves.

Follow-up issues created: BT-NNN (<title>), BT-MMM (<title>)
```

---

## Agent Prompt Template

When spawning a subagent for an issue, use this template. Fill in all fields from the Linear issue:

```
Work on <BT-NNN> using the standard skill chain: /pick-issue → /review-code → /done.

1. `/pick-issue BT-NNN` — loads issue, creates branch, sets In Progress, implements
2. `/review-code` — multi-pass review, fix any 🔴/🟡 findings
3. `/done` — commit, push, create PR

**IMPORTANT: In /done, the bot-review gate (step 12) waits for the `Claude BeamTalk Review`
CI check (and counts CodeRabbit if it has posted) and may HALT** if unresolved findings remain,
prompting you to resolve (chain to /resolve-pr), dismiss with reason, or override
with the literal phrase `merge anyway`. The parent agent owns CI watching, review
handling, and merging — but expect /done to block at the gate when the review bot finds
something. Pick override only if you've audited the findings and accepted the
risk; the override is logged in the final report.

**Confinement and sync-only rules — this run is one of several parallel agents:**
- All work stays inside your assigned worktree. Never `cd` out of it, never edit files
  in the main checkout or another agent's worktree, and never touch the shared stash.
- Run `just test` / `just ci` / builds synchronously and wait for them to finish.
  Do not background a build or test command and then poll it in a loop — that just
  burns turns. If a command is genuinely long-running, use the harness's own
  background/notify support instead of a manual sleep-and-poll loop.
```

That's it — keep the prompt minimal. `/pick-issue` and `/done` already contain all the rules (license headers, CLAUDE.md guidelines, test commands, commit format). No need to repeat them.

---

## Handling CI Failures

When a subagent's PR has a CI failure:

1. Get the failing job: `gh pr view <PR> --json statusCheckRollup`
2. Get the log: `gh api repos/<owner>/<repo>/actions/jobs/<job-id>/logs`
3. Diagnose the root cause
4. Apply a targeted fix directly to the agent's worktree branch (or push a fix commit)
5. Re-push — CI re-triggers automatically

**Common cross-platform issues:**
- Windows: `String` vs `&str` when a `#[cfg(windows)]` rebind creates an owned value
- macOS: path separator assumptions

## Handling Claude Review Bot Findings

The Claude review bot (`claude[bot]`) is the CI reviewer. Its reviews are always `COMMENTED` (non-blocking), and it posts findings as **inline review threads** — judge by whether each thread is unresolved, never by review state. These are the primary review signal. **Do not skip them.**

1. **Confirm the review posted** — the `Claude BeamTalk Review` check has left `pending` (see step 4c).
2. **Get its inline threads** (unresolved, authored by `claude[bot]`):
   ```bash
   gh api graphql -f query='{ repository(owner:"<owner>", name:"<repo>") {
     pullRequest(number: <PR>) { reviewThreads(first:100) { nodes {
       id isResolved comments(first:1) { nodes { author { login } url body } } } } } } }' \
     --jq '.data.repository.pullRequest.reviewThreads.nodes[]
       | select(.isResolved | not)
       | select(.comments.nodes[0].author.login | test("claude"; "i"))
       | {url: .comments.nodes[0].url, body: (.comments.nodes[0].body[:200])}'
   ```
3. **Evaluate each finding**:

| Finding type | Action |
|---|---|
| Bug introduced by this PR | Fix it, push a commit, reply with fix hash |
| Valid improvement, small scope | Fix it inline if < 10 lines |
| Valid improvement, large scope | Create a follow-up Linear issue, reply with issue link |
| Pre-existing code | Reply: "Pre-existing, not introduced by this PR" |
| False positive / style nitpick | Reply briefly, then resolve the thread |

4. **Reply to and resolve each addressed thread**:
   ```bash
   gh api repos/<owner>/<repo>/pulls/<PR>/comments/<comment-id>/replies \
     -f body="Fixed in <commit-hash>"
   gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<thread-id>"}) { thread { isResolved } } }'
   ```

## Handling CodeRabbit Reviews

CodeRabbit may block merging with `CHANGES_REQUESTED`. Evaluate each finding:

| Finding type | Action |
|---|---|
| Bug introduced by this PR | Fix it, push a commit |
| Scope creep added by the agent | Remove the extra code, push a commit |
| Pre-existing code (exists on `main`) | Dismiss: "Pre-existing, not introduced by this PR" |
| Valid improvement, large scope | Create a Linear issue, add it as a child of the epic, then dismiss: "Tracked as <BT-NNN>" |

When creating a follow-up issue for a valid-but-out-of-scope finding, use `/create-issue` and set the epic as its parent. Collect all follow-up issues created during the epic and report them at the end — don't interrupt the wave flow to work on them.

Dismiss blocking reviews via the GitHub API:
```bash
gh api -X PUT repos/<owner>/<repo>/pulls/<PR>/reviews/<review-id>/dismissals \
  -f message="<reason>"
```

Then re-attempt merge.

## Wave Sizing Guidance

| Epic size | Expected waves | Typical parallelism |
|---|---|---|
| 3–5 issues | 1–2 waves | 3–5 parallel |
| 6–10 issues | 2–3 waves | 3–5 parallel per wave |
| 10+ issues | 3+ waves | Cap at 5 parallel (context overhead) |

Never run more than 5 subagents in a single wave — context overhead degrades quality beyond that.

## When to Stop and Ask

Stop and ask the user for guidance if:
- A subagent fails to compile after 2 fix attempts
- An issue has genuinely ambiguous acceptance criteria
- Two issues in the same wave have unexpected file overlap discovered mid-execution
- The Claude review bot or CodeRabbit raises a security finding that is not pre-existing
- A PR has merge conflicts with main (means another PR in this wave touched the same files)
- The agent ledger shows two agents mapped to the same issue, an agent's returned
  worktree/branch doesn't match its ledger entry, or evidence that an agent wrote
  outside its assigned worktree (e.g. unexpected diffs in the main checkout)
