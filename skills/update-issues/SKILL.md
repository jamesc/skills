---
name: update-issues
description: Find and update Linear issues that need labels, blocking relationships, or metadata. Use when user says '/update-issues' with criteria like 'no labels', 'missing agent-ready', 'needs size', etc.
model: claude-haiku-4-5-20251001
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

Use `streamlinear-cli` to find matching issues:

**All open issues (or issues in a specific state):**
```bash
streamlinear-cli search --state "Backlog" --team BT
streamlinear-cli search --team BT  # all open
```

**Get a specific issue:**
```bash
streamlinear-cli get BT-21
```

**Issues in a number range or with complex filters (use GraphQL):**
```bash
streamlinear-cli graphql "query { issues(filter: { number: { gte: 21, lte: 40 }, team: { key: { eq: \"BT\" } } }) { nodes { id identifier title description labels { nodes { name id } } state { name } assignee { email } } } }"
```

**Batch fetch by specific numbers:**
```bash
streamlinear-cli graphql "query { issues(filter: { number: { in: [308, 309, 310] }, team: { key: { eq: \"BT\" } } }) { nodes { id identifier labels { nodes { name id } } } } }"
```

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

**Note:** `Epic` label is for large initiatives grouping 5+ related issues. Most issues should use other types.

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

### Updating Priority, State, Assignee

Use the CLI for these fields:

```bash
streamlinear-cli update BT-123 --assignee me
streamlinear-cli update BT-123 --priority 3
streamlinear-cli update BT-123 --state "In Progress"
```

### Updating Labels (REQUIRES GraphQL)

**IMPORTANT:** The CLI `update` command does NOT support labels. You MUST use GraphQL.

#### Step 4a: Look Up Label UUIDs (once per session)

Query all available labels and store the ID mapping:

```bash
streamlinear-cli graphql "query { issueLabels(first: 50) { nodes { id name } } }"
```

Store the results in a SQL table for reuse:

```sql
CREATE TABLE label_map (name TEXT PRIMARY KEY, id TEXT);
INSERT INTO label_map VALUES ('agent-ready', '<uuid>'), ('Bug', '<uuid>'), ...;
```

#### Step 4b: Get Issue UUIDs in Bulk

Query multiple issues at once to get their UUIDs and existing labels:

```bash
streamlinear-cli graphql "query { issues(filter: { number: { in: [308, 309, 310] }, team: { key: { eq: \"BT\" } } }) { nodes { id identifier labels { nodes { name id } } } } }"
```

#### Step 4c: Apply Labels via GraphQL Mutation

**Preserve existing labels!** Merge inferred label IDs with existing ones.

Batch up to 6 updates per mutation using aliases:

```bash
streamlinear-cli graphql "mutation { bt308: issueUpdate(id: \"<issue-uuid>\", input: { labelIds: [\"<label-uuid-1>\", \"<label-uuid-2>\", \"<label-uuid-3>\", \"<label-uuid-4>\"] }) { success issue { identifier } } bt309: issueUpdate(id: \"<issue-uuid>\", input: { labelIds: [\"<label-uuid-1>\", \"<label-uuid-2>\"] }) { success issue { identifier } } }"
```

**Key rules:**
- `labelIds` REPLACES all labels (not additive) — always include existing label IDs
- Batch multiple issues in one mutation using GraphQL aliases (`bt308:`, `bt309:`, etc.)
- Maximum ~6 updates per mutation to avoid query size limits

### Available Update Fields

| Field | Via CLI `update` | Via GraphQL | Example |
|-------|-----------------|-------------|---------|
| `state` | ✅ | ✅ | `--state "Backlog"` |
| `priority` | ✅ | ✅ | `--priority 3` |
| `assignee` | ✅ | ✅ | `--assignee me` |
| `labels` | ❌ | ✅ `labelIds` | Array of label UUIDs |
| `title` | ❌ | ✅ | String |
| `body` | ❌ | ✅ `description` | Markdown |

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

1. **Look up label UUIDs** (once per session):

```bash
streamlinear-cli graphql "query { issueLabels(first: 50) { nodes { id name } } }"
```

Store in SQL: `CREATE TABLE label_map (name TEXT PRIMARY KEY, id TEXT);`

2. **Search for all open issues and get details** (batch by number range):

```bash
streamlinear-cli graphql "query { issues(filter: { number: { in: [308, 309, 310, 311, 312] }, team: { key: { eq: \"BT\" } } }) { nodes { id identifier title labels { nodes { name id } } state { name } } } }"
```

3. **Filter to issues with empty labels** — check `labels.nodes` is empty

4. **For each unlabeled issue:**
   - Read title and description to infer labels
   - Look up label UUIDs from your `label_map` table
   - Apply via batched GraphQL mutation

5. **Example: BT-21 "Implement String class core API"**
   - Has acceptance criteria → `agent-ready`
   - Mentions "String" → `stdlib`
   - Title starts with "Implement" → `Feature`
   - Multiple methods → `M`

```bash
streamlinear-cli graphql "mutation { bt21: issueUpdate(id: \"<bt21-uuid>\", input: { labelIds: [\"<agent-ready-uuid>\", \"<Feature-uuid>\", \"<stdlib-uuid>\", \"<M-uuid>\"] }) { success issue { identifier } } }"
```

### Scenario 2: `/update-issues for missing agent-ready`

1. **Get all open issues with their labels**:
```bash
streamlinear-cli graphql "query { issues(filter: { team: { key: { eq: \"BT\" } }, state: { name: { nin: [\"Done\", \"Canceled\"] } } }, first: 50) { nodes { id identifier title description labels { nodes { name id } } } } }"
```

2. **Filter to issues where `labels.nodes` has NO entry with name in** `[agent-ready, needs-spec, blocked, human-review, done]`

3. **For each, analyze and infer agent-state label**

4. **Apply via batched GraphQL mutation** — include ALL existing label IDs plus the new one

### Scenario 3: `/update-issues for BT-21 through BT-40`

1. **Get all issues in range with labels in one query:**

```bash
streamlinear-cli graphql "query { issues(filter: { number: { gte: 21, lte: 40 }, team: { key: { eq: \"BT\" } } }) { nodes { id identifier title description labels { nodes { name id } } state { name } } } }"
```

2. **Analyze and update each one**

3. **Skip issues in Done or Canceled states**

4. **Batch updates in groups of 6 per mutation**

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

1. **Get UUIDs for blocker and blocked issues:**
```bash
streamlinear-cli get BT-21   # note the `id` field (UUID)
streamlinear-cli get BT-32   # note the `id` field (UUID)
```

2. **Create relationship:**
```bash
streamlinear-cli graphql "mutation { issueRelationCreate(input: { issueId: \"<blocker-uuid>\", relatedIssueId: \"<blocked-uuid>\", type: blocks }) { success } }"
```

### Example: BT-21 blocks multiple issues

```
BT-21 (API definitions) blocks:
- BT-32 (block evaluation)
- BT-33 (collections)
- BT-34 (strings)
```

For each blocked issue, get both UUIDs then create the relation.

## Relationship Types

Linear supports these relationship types:

| Type | Description |
|------|-------------|
| `blocks` | This issue blocks another (dependency) |
| `blocked_by` | This issue is blocked by another (inverse) |
| `related` | Generic relationship |
| `duplicate` | Mark as duplicate |

**Note:** Use `blocks` type. Linear automatically creates the inverse `blocked_by` relationship.

## Tips

1. **Labels REQUIRE GraphQL** — the CLI `update` command does NOT support labels
2. **Look up label UUIDs once** per session, store in SQL `label_map` table
3. **Get issue UUIDs in bulk** — use `issues(filter: { number: { in: [...] } })` not individual gets
4. **`labelIds` REPLACES all labels** — always merge existing IDs with new ones
5. **Batch mutations with aliases** — `bt308: issueUpdate(...)  bt309: issueUpdate(...)` in one call
6. **Preserve existing labels** when updating — fetch current labels first, add to them
7. **Use GraphQL for relationships** — CLI update doesn't support relations
8. **Skip done issues** — Don't update issues in Done or Canceled states
9. **Report clearly** — Show what changed for each issue
10. **Max ~6 updates per mutation** — keep GraphQL query size manageable

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
