---
name: whats-next
description: Find the next logical piece of work. Use when user types /whats-next or asks what they should work on next, or wants recommendations for the next task.
model: haiku
allowed-tools: Bash, Read, Grep, Glob, mcp__linear-server__list_cycles, mcp__linear-server__list_issues, mcp__linear-server__get_issue
---

# What's Next Workflow

When activated, execute this workflow to recommend the next issue to work on.

Use the Linear MCP tools (`mcp__linear-server__*`) for all Linear queries. `list_issues` filters by a **single** state at a time and supports `team`, `cycle`, `label`, `priority`, `parentId`, `query`, `orderBy` (`createdAt` | `updatedAt`), and `limit`. It does not return relations, children, or parent — call `get_issue` (id: `BT-XX`) on a candidate to inspect those.

## Steps

1. **Check current branch**: Determine if we're on a feature branch and extract the issue number if present.

2. **Check for active cycles**: Find the BT team's active cycle with `list_cycles` (team: "BT"), then list its issues with `list_issues` (team: "BT", cycle: "current"). If an active cycle exists, prioritize issues from that cycle.

3. **Get recent completed work**: List recently completed issues to understand work patterns. Call `list_issues` once per state (team: "BT", state: "Done", orderBy: "updatedAt", limit: 10) and again (team: "BT", state: "In Review", orderBy: "updatedAt", limit: 10). Note their labels and, where useful, `get_issue` on a few to see parent/area.

4. **Check git history**: Review recent commits to understand what areas were recently worked on:
   ```bash
   git log --oneline -20 --format="%s" | grep -oE "BT-[0-9]+" | sort -u | head -5
   ```

5. **Find candidate issues**: List backlog/todo issues that are ready to work on. Call `list_issues` once per state (team: "BT", state: "Backlog", limit: 20) and again (team: "BT", state: "Todo", limit: 20). **Skip "In Progress" issues** — those are already being worked on by another agent. Then, for the most promising candidates, call `get_issue` (id: "BT-XX") to read each one's relations (blockers/blocks), children, and parent — `list_issues` does not return these, and they drive the scoring below.

6. **Prioritize issues**: Score and rank issues based on:
   - **Active cycle membership** (highest priority if cycle is active)
   - **`agent-ready` label** (fully specified, can start immediately)
   - **Priority level** (1=Urgent, 2=High, 3=Medium, 4=Low)
   - **Blocking relationships** (issues that unblock others get priority)
   - **Relatedness to recent work** (same parent issue, similar area)
   - **Dependencies satisfied** (all blocking issues are Done)

7. **Present recommendations**: Display the top 3-5 recommended issues in this format:

   ```
   ## Recommended Next Issues

   | # | Issue | Title | Priority | Score | Why |
   |---|-------|-------|----------|-------|-----|
   | 1 | BT-XX | Title | High | 85 | In active cycle, unblocks BT-YY |
   | 2 | BT-ZZ | Title | Medium | 65 | agent-ready, related to recent BT-WW |
   | 3 | BT-AA | Title | Medium | 50 | agent-ready, no blockers |

   **Top pick: BT-XX** — [one sentence explaining why this is the best choice]
   ```

   For each issue include:
   - Issue identifier and title
   - Priority and score
   - Why it's recommended (cycle, related to recent work, unblocks others, etc.)
   - Any caveats (e.g., "large scope, consider breaking down")

8. **Optional: Start work**: Ask the user if they want to start on the top recommended issue (which would run the `/pick-issue` workflow for that specific issue).

## Scoring Logic

| Condition | Points |
|-----------|--------|
| In active cycle | +50 |
| Has `agent-ready` label | +30 |
| Blocker completed in last 7 days (newly unblocked) | +25 |
| Related to recently completed work (same parent or area) | +20 |
| Unblocks other issues | +15 |
| Priority 1 (Urgent) | +10 |
| Priority 2 (High) | +5 |
| Has unresolved blocking dependencies | -100 |
| Has `needs-spec` label (requires human input first) | -50 |
| Has `blocked` label | -20 |
| Is "In Progress" (another agent working on it) | -200 |
