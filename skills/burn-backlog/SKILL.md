---
name: burn-backlog
description: Burn down the Linear backlog by orchestrating N parallel cloud sessions (default 6), one issue each, merging when green, archiving finished sessions and refilling the slot from a queue. Use when user types /burn-backlog or asks to work through the backlog with parallel sessions.
argument-hint: "[slots=6] [model=claude-sonnet-5-5] [extra filter, e.g. label or team]"
---

# Burn Backlog Workflow

You are the **orchestrator**. You do not write code. You pick issues, start one cloud session per issue (`create_session`), keep N of them running, verify each finish, archive it, and start the next. Each child session takes its issue all the way: branch → PR → green CI + review → squash-merge → Linear Done.

The user's standing instructions for a run are:
- **Merge when green.** No human review gate.
- **Follow-ups stay in the same PR/session.** Don't file new issues unless the work is large, in another repo, or needs a human decision. The goal is a smaller backlog.
- **Keep N slots busy.** Every time something closes, start the next issue.

Parse arguments: slot count (default 6), child model (default the latest Sonnet, e.g. `claude-sonnet-5-5`), and any extra filter.

---

## 1. Build the queue

1. `list_issues` with `state: backlog` (limit 100+, page through), fields `id,title,priority,estimate,labels,status,parentId`.
2. Keep issues labelled `agent-ready`. Drop anything labelled `blocked` or `needs-spec`, and drop `Epic`s.
3. Order: S before M before L, Bugs and small Improvements first, then by priority.
4. **Spread the first batch across areas** (codegen, runtime, class-system, repl, stdlib, lsp, cli…) so parallel PRs don't conflict.
5. **Defer conflict magnets to the end**: mechanical sweeps across hundreds of sites (clippy-wide fixes, mass renames, formatter changes). Run them alone, after the other sessions have merged.
6. Pair tightly related issues (one is cleanup of the other, same function) into **one session / one PR**.
7. Check `list_sessions` for sessions already working an issue; skip those.

Write the queue and the active table to a state file in the scratchpad (`state.md`): `issue → session_id`, a `Queue` line and a `Done` list (PR number + any leftover note). Re-read it at every check-in. It is what survives context compaction.

## 2. Start a session per slot

For each slot, `create_session` with:
- `model`: the child model.
- `source_url`: the repo the code lives in. **Check first** when the issue names a test or module from a satellite repo (e.g. `beamtalk-symphony`, `beamtalk-linear`); grep or ask, because children often **can't `add_repo`** themselves (the auto-mode classifier denies it).
- `title`: `"BT-XXXX: <short summary>"`.
- `tags`: `["backlog-burn"]`.
- `prompt`: the template below.

### Child prompt template

```
Work Linear issue {ID} ("{TITLE}") in {OWNER/REPO} end to end.
{Optional one-line context: related work merged today to build on, where the code lives, the planned fix from an earlier session.}

1. Read the issue (and its comments) in Linear, move it to In Progress, and investigate the code.
2. Implement it with tests. Run the repo's relevant fast checks locally (build, clippy/fmt, the affected test suites) before pushing.
3. Push to a branch and open a ready-for-review PR whose title starts with "{ID}:" and whose body says "Fixes {ID}". Subscribe to PR activity.
4. Drive the PR to green: fix CI failures and address review comments (including the Claude review bot) yourself. Do follow-up work in this same PR/session wherever it's reasonable instead of filing new issues — we are trying to shrink the backlog. Only file a new Linear issue if the follow-up is genuinely out of scope and large.
5. When CI is green and reviews are addressed, squash-merge the PR, then mark {ID} Done in Linear with a short comment linking the PR. If a check fails only at an infrastructure step before any test ran (e.g. apt mirror DNS failure), re-run it. If you can't merge for any reason, report that to the parent and stop.
6. Finish with a one-paragraph summary: PR number, merged or not, anything left over (and any issue you filed). Send that summary to your parent session with send_message (session_id "@parent").

If the issue turns out to be already fixed, invalid, or blocked, say so in a Linear comment, set the status accordingly, report to the parent, and stop.
```

Keep the child prompt plain: when a child can't proceed (merge refused, check stuck red), it reports and stops. Don't add instructions that route around permission checks. Blocked cases go to the user (§3).

## 3. Wait. Don't poll.

- Children report with `send_message` to `@parent`. That arrives as a notification and wakes you.
- Also schedule a fallback check-in with `send_later` every 25–30 minutes. Children that finish cleanly sometimes don't message.
- End your turn between events. Never `sleep`-poll.

### On a child's "done" message

1. **Verify.** `get_issue` shows `Done` (or `Canceled` with a reason), and the PR is merged (`list_pull_requests` / `pull_request_read`). Don't trust the message alone.
2. `archive_session` the child.
3. Start the next queued issue in the freed slot (§2) and update `state.md`.
4. Note any leftover the child reports. If it's in the issue's own scope, ask the child to finish it in a follow-up PR *before* archiving, or to document on the issue exactly what remains and why. Follow-ups that belong in another repo, or are blocked on a release/nightly, go in `state.md` and the user summary, not a new issue.
5. Give the user a short update: what closed (one line on what changed), what started, a running tally (merged / canceled), and what's running and queued.

### On a check-in

`list_sessions` (mine) plus open PRs. For each active child:
- **Idle, PR fully green, not merged**: message it to merge. If it reports its merge was refused by a permission check, tell the user which PR is green and waiting, and let them merge it or say how to proceed. Then have the child mark the issue Done.
- **Idle > 30 min, CI still running**: leave it. CI queues under 6+ parallel PRs.
- **Red check**: let the child handle it. Step in only if it's stuck.
- Reschedule the next `send_later`.

## 4. Known failure modes and fixes

| Symptom | What to do |
|---|---|
| Same infra failure across several PRs (e.g. `e2e` dies at apt/Playwright install, DNS "Temporary failure resolving …") | It's the runner, not the diff. Children **can't `send_later`** (classifier denies it), so **you** drive retries: at each check-in, message the stuck children to re-run the job. Once one PR's job passes, tell the rest to re-run now. If it persists, ask the user how to proceed. |
| Child left a stale `send_later` it couldn't delete | `delete_trigger` it yourself. |
| Child was started in the wrong repo | Archive it and start a fresh session with the right `source_url`, passing on what it learned (file path, planned fix). |
| Issue already fixed on main | Child sets it Canceled with a comment. Count it as closed and move on. |
| Child needs a product decision (an acceptance criterion says "confirm with user") | Child should implement the sensible default and flag it. Relay the question to the user and record their answer as a Linear comment. |
| Child's message crosses with yours | Re-send the instruction and ask for an explicit reply. |
| MCP servers (Linear, GitHub) disconnect and reconnect | Re-load the tool schemas with `ToolSearch` (`select:…`) and carry on. |

## 5. Finishing

When the queue is empty:
1. Run any deferred conflict-magnet sweep alone, now that the other sessions have merged.
2. Final summary: issues closed (merged vs canceled), PR numbers, leftovers noted but not filed, and what's left in the backlog (blocked / needs-spec / epics).
3. Ask the user whether to move on to `needs-spec` issues that look clear enough to work, or stop.
4. Cancel the remaining `send_later` check-in (`delete_trigger`).
