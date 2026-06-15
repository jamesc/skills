---
name: update-issues
description: Find and update Linear issues that need labels, blocking relationships, or metadata. Use when user says '/update-issues' with criteria like 'no labels', 'missing agent-ready', 'needs size', etc.
model: haiku
---

# Update Issues Automatically

This skill searches for issues matching criteria and applies updates automatically.

## Overview

When the user says `/update-issues for ones with no labels` or similar:
1. Parse the criteria (what to look for)
2. Search Linear for matching issues
3. Analyze each issue to determine needed updates
4. Apply updates automatically
5. Report what was changed

## Supported Criteria

| User Says | What to Search For |
|-----------|-------------------|
| "no labels" | Issues with empty or missing labels |
| "missing agent-ready" | Issues without agent-state labels |
| "missing area" | Issues without item-area labels |
| "missing type" | Issues without issue-type labels |
| "missing size" | Issues without size estimate labels |
| "not assigned" | Issues without assignee |
| "in backlog" | Issues in Backlog state needing triage |
| "all open" | All open issues (for bulk updates) |
| "BT-X through BT-Y" | Specific range of issue numbers |

## Step 1: Parse User Criteria

Extract what the user wants to update:

**Examples:**
- `/update-issues for ones with no labels` → Find issues with no labels
- `/update-issues for missing agent-ready` → Find issues without agent-state labels
- `/update-issues for issues in backlog` → Find issues in Backlog state
- `/update-issues for BT-21 through BT-30` → Specific range

## Step 2: Search for Issues

Use the Linear MCP tools (`mcp__linear-server__*`) to find matching issues.

**All open issues (or issues in a specific state):** use `list_issues`:
- `list_issues` (team: "BT", state: "Backlog") — issues in a specific state
- `list_issues` (team: "BT") — all open issues

You can also narrow with `label` and `query` filters on `list_issues`.

**Get a specific issue:** use `get_issue` (id: "BT-21"). It accepts the `BT-XX` shorthand directly — no UUID needed.

**Issues in a number range or with complex filters:** call `list_issues` (team: "BT", state/label/query as needed) and filter the returned issues, or call `get_issue` per issue (e.g. `get_issue` (id: "BT-21"), `get_issue` (id: "BT-22"), …) for a specific set of numbers.

## Step 3: Analyze Each Issue

For each issue found, determine what's missing:

1. **Check labels** - Does it have agent-state, item-area, issue-type, and size?
2. **Check assignee** - Should be `jamesc.000@gmail.com`
3. **Check description** - Does it have acceptance criteria?
4. **Check priority** - Should default to 3 (Medium) if not set

### Determine Missing Labels

**Agent State:** Must have one of `agent-ready`, `needs-spec`, `blocked`, `human-review`, `done`

**Item Area:** Must have one of `class-system`, `stdlib`, `repl`, `cli`, `codegen`, `runtime`, `parser`

**Issue Type:** Must have one of `Epic`, `Feature`, `Bug`, `Improvement`, `Documentation`, `Infra`, `Language Feature`, `Refactor`, `Research`, `Samples`

**Note:** `Epic` is for an issue that groups a set of related children (any multi-issue set, so it's runnable via `/pick-epic`). Individual work items use the other types.

**Size:** Must have one of `S`, `M`, `L`, `XL`

### Smart Defaults

When labels are missing, infer from context:

**Agent State:**
- Has acceptance criteria + files to modify → `agent-ready`
- Vague or missing details → `needs-spec`
- Mentions "depends on", "waiting for" → `blocked`

**Item Area:**
- Mentions "parser", "lexer", "AST" → `parser`
- Mentions "codegen", "Core Erlang", "BEAM" → `codegen`
- Mentions "stdlib", "collections", "String" → `stdlib`
- Mentions "REPL", "interactive" → `repl`
- Mentions "CLI", "command" → `cli`
- Mentions "runtime", "actors", "OTP" → `runtime`
- Mentions "class", "methods" → `class-system`

**Issue Type:**
- Title starts with "Implement", "Add" → `Feature`
- Title starts with "Fix", "Bug" → `Bug`
- Title starts with "Refactor", "Clean up" → `Refactor`
- Title starts with "Document" → `Documentation`
- Title contains "Research", "Investigate" → `Research`
- Title contains "syntax", "keyword", "operator", "language feature" → `Language Feature`

**Size:**
- Simple, single file → `S`
- Multiple files, moderate scope → `M`
- Large feature, many files → `L`
- Major architectural change → `XL`

## Step 4: Apply Updates

All updates go through `save_issue`, keyed on the `BT-XX` identifier. No GraphQL, no UUID lookups.

### Updating Priority, State, Assignee

```
save_issue (id: "BT-123", assignee: "me")
save_issue (id: "BT-123", priority: 3)
save_issue (id: "BT-123", state: "In Progress")
```

`assignee` accepts `"me"`, a name, or an email; `state` names are fuzzy; `priority` is 0–4 (0=None, 1=Urgent, 2=High, 3=Medium, 4=Low). Fields can be combined in a single `save_issue` call.

### Updating Labels

`save_issue` applies labels directly by **name** — no UUIDs, no label-UUID lookup, no batched mutation.

#### Step 4a: Discover Valid Label Names (once per session)

If you need the list of valid label names to choose from, call `list_issue_labels` (team: "BT").

#### Step 4b: Apply Labels per Issue

Call `save_issue` once per issue with the inferred label names:

```
save_issue (id: "BT-21", labels: ["agent-ready", "Feature", "stdlib", "M"])
save_issue (id: "BT-32", labels: ["agent-ready", "Feature", "stdlib", "S"])
```

Pass the full set of label names you want the issue to carry. There are no UUIDs and no per-issue UUID lookups — just the `BT-XX` identifier and label names.

### Available Update Fields (via `save_issue`)

| Field | Argument | Example |
|-------|----------|---------|
| `state` | `state` | `state: "Backlog"` |
| `priority` | `priority` | `priority: 3` |
| `assignee` | `assignee` | `assignee: "me"` |
| `labels` | `labels` | `labels: ["agent-ready", "Feature"]` (names) |
| `title` | `title` | String |
| `body` | `description` | Markdown |
| blocking | `blocks` / `blockedBy` | `blocks: ["BT-32"]` (BT-XX identifiers) |

## Step 5: Report Changes

After updating, report what was changed:

```
Updated 5 issues:

✓ BT-21: Added labels [agent-ready, Feature, stdlib, M]
✓ BT-32: Added labels [agent-ready, Feature, stdlib, M], set assignee
✓ BT-33: Added labels [needs-spec, Feature, stdlib, M]
✓ BT-34: Added labels [agent-ready, Feature, stdlib, S]
✓ BT-35: Added labels [agent-ready, Feature, stdlib, M]
```

## Complete Example Workflows

### Scenario 1: `/update-issues for ones with no labels`

1. **Discover valid label names** (once per session, if needed):

   `list_issue_labels` (team: "BT")

2. **Search for open issues and read their details:**

   `list_issues` (team: "BT") — returns identifiers, titles, descriptions, and current labels.

3. **Filter to issues with empty labels** — keep those whose label set is empty

4. **For each unlabeled issue:**
   - Read title and description to infer labels
   - Apply with a single `save_issue` call using label names

5. **Example: BT-21 "Implement String class core API"**
   - Has acceptance criteria → `agent-ready`
   - Mentions "String" → `stdlib`
   - Title starts with "Implement" → `Feature`
   - Multiple methods → `M`

```
save_issue (id: "BT-21", labels: ["agent-ready", "Feature", "stdlib", "M"])
```

### Scenario 2: `/update-issues for missing agent-ready`

1. **Get open issues with their labels:** `list_issues` (team: "BT"). Exclude Done/Canceled issues from the result set.

2. **Filter to issues whose labels have NO entry in** `[agent-ready, needs-spec, blocked, human-review, done]`

3. **For each, analyze and infer the agent-state label**

4. **Apply with `save_issue`** (id: "BT-XX", labels: [...]) — pass the full set of label names the issue should carry, including the ones it already has plus the new agent-state label

### Scenario 3: `/update-issues for BT-21 through BT-40`

1. **Get the issues in range with their labels:** call `list_issues` (team: "BT") and filter to numbers 21–40, or call `get_issue` per number (`get_issue` (id: "BT-21"), …).

2. **Analyze and update each one** with `save_issue`

3. **Skip issues in Done or Canceled states**

## Label Inference Rules (Summary)

### Agent State

- ✅ Well-defined acceptance criteria + files → `agent-ready`
- ⚠️ Vague or incomplete → `needs-spec`
- 🚫 Mentions "depends on", "waiting for" → `blocked`

### Item Area (by keyword)

- "parser", "lexer", "token", "AST" → `parser`
- "codegen", "Core Erlang", "BEAM", "generate" → `codegen`
- "stdlib", "String", "Array", "collection" → `stdlib`
- "REPL", "interactive", "eval" → `repl`
- "CLI", "command", "flag" → `cli`
- "runtime", "actor", "OTP", "process" → `runtime`
- "class", "method", "object" → `class-system`

### Issue Type (by title)

- "Implement", "Add" → `Feature`
- "Fix", "Bug" → `Bug`
- "Refactor", "Clean up" → `Refactor`
- "Document", "Add docs" → `Documentation`
- "Research", "Investigate" → `Research`
- "syntax", "keyword", "operator", "language feature" → `Language Feature`

### Size (by scope)

- Single file, simple change → `S`
- Few files, moderate feature → `M`
- Many files, complex feature → `L`
- Architectural, breaking change → `XL`

## Setting Up Blocking Relationships

If the user also mentions dependencies (e.g., "and set up blocking relationships"):

`save_issue` creates relationships directly using `BT-XX` identifiers — no UUIDs, no GraphQL.

- On the blocker, pass `blocks`: `save_issue` (id: "BT-21", blocks: ["BT-32"])
- Or on the blocked issue, pass `blockedBy`: `save_issue` (id: "BT-32", blockedBy: ["BT-21"])

Relationships are append-only and Linear automatically maintains the inverse side, so you only need to set one direction.

### Example: BT-21 blocks multiple issues

```
BT-21 (API definitions) blocks:
- BT-32 (block evaluation)
- BT-33 (collections)
- BT-34 (strings)
```

Set them all in one call on the blocker:

```
save_issue (id: "BT-21", blocks: ["BT-32", "BT-33", "BT-34"])
```

## Relationship Types

`save_issue` supports these relationship arguments (all keyed on `BT-XX` identifiers):

| Argument | Description |
|------|-------------|
| `blocks` | This issue blocks another (dependency) |
| `blockedBy` | This issue is blocked by another (inverse) |
| `relatedTo` | Generic, non-blocking relationship |

**Note:** Use `blocks` (or `blockedBy`). Linear automatically creates the inverse relationship, so set only one side.

## Tips

1. **`save_issue` handles labels by name** — no GraphQL, no UUIDs; pass `labels: ["agent-ready", "Feature", …]`
2. **Discover label names with `list_issue_labels`** (team: "BT") when you need the valid set to choose from
3. **Fetch issues with `list_issues`** (team/state/label/query filters) or `get_issue` (id: "BT-XX") for specific numbers
4. **Pass the full label set** you want the issue to carry, including labels it already has plus any new ones
5. **One `save_issue` per issue** — keyed on the `BT-XX` identifier; no batching or aliasing needed
6. **Preserve existing labels** when updating — read the issue's current labels first and include them
7. **Relationships via `save_issue`** — `blocks` / `blockedBy` / `relatedTo` accept `BT-XX` identifiers
8. **Skip done issues** — Don't update issues in Done or Canceled states
9. **Report clearly** — Show what changed for each issue

## Workflow States

Team BT uses these workflow states:

| State | Description |
|-------|-------------|
| `Backlog` | Idea captured, not yet specified |
| `Todo` | Ready to start, fully specified |
| `In Progress` | Actively being worked on |
| `In Review` | Code complete, needs verification |
| `Done` | Merged and verified |
| `Canceled` | Won't do |
| `Duplicate` | Duplicate of another issue |
