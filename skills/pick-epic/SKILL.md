---
name: pick-epic
description: Execute an epic by running children in dependency-ordered waves using parallel subagents, one isolated worktree and PR per issue, squash-merging as CI and automated reviews (CodeRabbit + Copilot) pass. Use when user types /pick-epic or asks to execute an epic with parallel agents.
model: opus
argument-hint: "BT-XXX (epic ID)"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# Pick Epic Workflow

Execute an epic by grouping its children into **dependency-ordered waves** and running each wave as **parallel subagents**, one per issue. Each issue gets its own isolated worktree, its own PR (squash-merged to main), and is merged as soon as CI passes and automated reviews (CodeRabbit + Copilot) are satisfied. Waves are sequential — Wave N+1 starts only after all Wave N PRs are merged.

**Key difference from `/do-refactor`:** This skill uses isolated worktrees and parallel subagents for maximum throughput — one PR per issue, not one PR for the whole epic. Use this for any L/XL epic where issues touch non-overlapping files.

---

## Steps

### 1. Load the epic and children

```bash
streamlinear-cli get BT-XXX
```

Then fetch all child issues with their blocking relationships and sizes:

```bash
streamlinear-cli graphql "query {
  issue(id: \"<epic-node-id>\") {
    children {
      nodes {
        id identifier title state { name }
        labels { nodes { name } }
        relations { nodes { type relatedIssue { identifier state { name } } } }
      }
    }
  }
}"
```

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

Use `Agent` tool with `isolation: "worktree"` and `run_in_background: true` for every issue in the wave simultaneously. Each agent receives a complete self-contained prompt (see **Agent Prompt Template** below).

**4b. Wait for all agents in the wave to complete.**

**4c. For each completed agent:**
- Check the PR URL returned
- Watch CI: `gh pr view <PR> --json statusCheckRollup`
- If CI fails: diagnose the failure, push a fix to the agent's branch
- **Wait for automated reviews** before merging. Poll every 60s for up to 5 minutes:
  ```bash
  gh api repos/<owner>/<repo>/pulls/<PR>/reviews \
    --jq '[.[] | select(.user.login | test("copilot|coderabbit"; "i")) | {user: .user.login, state}]'
  ```
  - **Copilot**: Wait for its review to appear. If Copilot's review body contains "usage limits" or "rate limit", skip — Copilot is unavailable this run.
  - **CodeRabbit**: Wait for its review to appear (APPROVED or CHANGES_REQUESTED).
  - **Timeout (5 min)**: Proceed if at least one bot reviewed. If neither appeared, note it in the merge summary but proceed.
- **Handle Copilot comments**: Copilot reviews are always `COMMENTED` (never blocking), but their findings are valuable:
  - Spawn a subagent (or fix directly) to address genuine bugs Copilot identified
  - Reply to each addressed comment with the fix commit hash
  - Skip style/nitpick suggestions — note them in the merge summary
  - If Copilot found nothing actionable, proceed
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

After each PR is merged:
```bash
streamlinear-cli update BT-YYY --state Done
```

### 6. Mark the epic Done

After all waves complete:
```bash
streamlinear-cli update BT-XXX --state Done
streamlinear-cli comment BT-XXX "All child issues completed in <N> waves. PRs: #P1, #P2, ..."
```

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

**IMPORTANT: In /done, the bot-review gate (step 12) will wait up to 10 minutes
for Copilot / CodeRabbit reviews and may HALT** if unresolved findings remain,
prompting you to resolve (chain to /resolve-pr), dismiss with reason, or override
with the literal phrase `merge anyway`. The parent agent owns CI watching, review
handling, and merging — but expect /done to block at the gate when bots find
something. Pick override only if you've audited the findings and accepted the
risk; the override is logged in the final report.
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

## Handling Copilot Reviews

Copilot reviews are `COMMENTED` (non-blocking) but contain valuable findings. **Do not skip them.**

1. **Wait for Copilot's review** to appear (poll alongside CodeRabbit)
2. **Check for rate limiting**: If the review body contains "usage limits", "rate limit", or "couldn't generate", Copilot is unavailable — skip and note in merge summary
3. **Get inline comments**:
   ```bash
   gh api repos/<owner>/<repo>/pulls/<PR>/reviews/<review-id>/comments \
     --jq '[.[] | {id, path, body: .body[:200]}]'
   ```
4. **Evaluate each comment**:

| Finding type | Action |
|---|---|
| Bug introduced by this PR | Fix it, push a commit, reply with fix hash |
| Valid improvement, small scope | Fix it inline if < 10 lines |
| Valid improvement, large scope | Create a follow-up Linear issue, reply with issue link |
| Pre-existing code | Reply: "Pre-existing, not introduced by this PR" |
| False positive / style nitpick | Skip — no reply needed |

5. **Reply to addressed comments**: For each comment you fixed:
   ```bash
   gh api repos/<owner>/<repo>/pulls/<PR>/comments/<comment-id>/replies \
     -f body="Fixed in <commit-hash>"
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
- CodeRabbit or Copilot raises a security finding that is not pre-existing
- A PR has merge conflicts with main (means another PR in this wave touched the same files)
