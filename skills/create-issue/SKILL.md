---
name: create-issue
description: Create a Linear issue with proper structure and blocking relationships. Use when creating new tasks, breaking down work, or setting up dependencies between issues.
argument-hint: "[issue title or description]"
allowed-tools: Read, Grep, Glob, mcp__linear-server__save_issue, mcp__linear-server__get_issue, mcp__linear-server__list_issues, mcp__linear-server__list_issue_labels, mcp__linear-server__save_comment
---

# Creating Linear Issues

Follow this workflow when creating issues in Linear:

## Required Fields

Every issue **must** have:

| Field | Value |
|-------|-------|
| **Team** | `BT` |
| **Assignee** | `--assignee me` (current user) |
| **Agent State Label** | `agent-ready` or `needs-spec` |
| **Item Area Label** | Component affected (see below) |
| **Estimate (Size)** | T-shirt size: S, M, L, XL |
| **Type** | See issue types below |

## Issue Types

| Type | Description |
|------|-------------|
| `Epic` | Groups a set of related issues that ship together — use for **any** multi-issue set so it's runnable via `/pick-epic` (use size XL) |
| `Feature` | A chunk of customer visible work |
| `Bug` | Bugs, broken tests, broken code |
| `Improvement` | Incremental work on top of a feature |
| `Documentation` | Words that explain things to humans and non-humans |
| `Infra` | Tools, CI, dev environment configuration |
| `Language Feature` | New Beamtalk language syntax/semantics |
| `Refactor` | Code cleanups, tech debt |
| `Research` | Research projects, code spikes |
| `Samples` | Code, examples, things to help devs get started |

**Note:** Create an `Epic` whenever work spans more than one issue (see "Breaking Work Into Multiple Issues" below) — a single self-contained issue needs none. Epic titles should use the `Epic:` prefix (e.g., "Epic: Feature Name"). See AGENTS.md "Epics" section for full guidelines.

## Item Area Labels

Every issue should have an area label to identify which component is affected:

| Area | Description | Key Directories |
|------|-------------|----------------|
| `class-system` | Class definition, parsing, codegen, and runtime | `crates/beamtalk-core/src/ast.rs`, `crates/beamtalk-core/src/source_analysis/` |
| `stdlib` | Standard library: collections, primitives, strings | `lib/` |
| `repl` | REPL backend and CLI interaction | `runtime/apps/beamtalk_runtime/src/beamtalk_repl*.erl`, `crates/beamtalk-cli/src/repl/` |
| `cli` | Command-line interface and build tooling | `crates/beamtalk-cli/` |
| `codegen` | Code generation to Core Erlang/BEAM | `crates/beamtalk-core/src/codegen/` |
| `runtime` | Erlang runtime: actors, futures, OTP integration | `runtime/apps/beamtalk_runtime/src/` |
| `parser` | Lexer, parser, AST | `crates/beamtalk-core/src/source_analysis/`, `crates/beamtalk-core/src/ast.rs` |

## Optional Fields

| Field | When to Use |
|-------|-------------|
| **Project** | If part of a larger initiative (e.g., "Stdlib Implementation") |
| **Priority** | 1 (Urgent), 2 (High), 3 (Medium), 4 (Low) - default is 3 |
| **Parent Issue** | If this is a sub-task of a larger issue |

## Issue Body Structure

Every issue description should include:

1. **Context** - Why this work matters, background info
2. **Acceptance Criteria** - Specific, testable requirements (checkboxes)
3. **Files to Modify** - Explicit paths to relevant files
4. **Dependencies** - Other issues that must complete first
5. **References** - Links to specs, examples, or related code

## Example Issue

```markdown
Title: Implement basic lexer token types

Context:
The lexer is the first phase of compilation. It needs to tokenize
Smalltalk-style message syntax including identifiers, numbers, and keywords.

Acceptance Criteria:
- [ ] Tokenize identifiers (letters, digits, underscores)
- [ ] Tokenize integers and floats
- [ ] Tokenize single and double quoted strings
- [ ] Tokenize message keywords ending in `:`
- [ ] Tokenize block delimiters `[` `]`
- [ ] All tokens include source span

Files to Modify:
- crates/beamtalk-core/src/source_analysis/token.rs
- crates/beamtalk-core/src/source_analysis/lexer.rs

Dependencies: None

References:
- See Gleam lexer: github.com/gleam-lang/gleam/blob/main/compiler-core/src/parse/lexer.rs
```

## Agent-State Labels

Always set one of these labels:
- `agent-ready` - Fully specified, all acceptance criteria clear, agent can start immediately
- `needs-spec` - Requires human clarification before work can start
- `blocked` - Waiting on external dependency or another issue

## Size Estimates (T-Shirt Sizing)

| Size | Description |
|------|-------------|
| **S** | Small change, few hours (add a test, simple refactor) |
| **M** | Medium change, ~1 day (new feature, moderate complexity) |
| **L** | Large change, 2-3 days (significant feature, multiple files) |
| **XL** | Extra large, consider breaking down (major feature, architectural change) |

## Breaking Work Into Multiple Issues

When a request spans more than one issue, **right-size first, then group under an Epic**:

- **Use the fewest issues that are each independently landable.** Don't split work that lands together; don't mint a separate "design spike" issue when the decisions can live in the description of the issue that implements them. If you're tempted by 4–5 issues, check whether 2–3 cover it.
- **Always wrap a multi-issue set under an `Epic`**, even for just two children. Create the Epic first (`Epic` type, size XL, `Epic:` title prefix), then create each child with `parentId` set to the Epic's `BT-XX`. This keeps the set runnable via `/pick-epic`, which executes an Epic's children in dependency-ordered waves.
- **Still wire blocking relationships** between the children (see below) — `/pick-epic` uses them to order the waves.
- A single, self-contained piece of work needs **no** Epic — just create the one issue.

## Creating the Issue

Use the Linear MCP tools (`mcp__linear-server__*`) — see `skills/linear/SKILL.md` for the canonical conventions. Create the issue with a single `save_issue` call (no `id` means create), passing labels, priority, parent, and any blocking relationships directly:

`save_issue` (NO `id`):
- `title`: `"Implement feature X"`
- `team`: `"BT"`
- `description`: the full body (Context, Acceptance Criteria, …)
- `assignee`: `"me"` (current user)
- `priority`: `3` (Medium; see priority table above)
- `labels`: label *names* directly — e.g. `["agent-ready", "Feature", "codegen", "M"]`. No UUIDs, no lookup step.
- `parentId`: a `BT-XX` identifier if this is a sub-task.
- `blockedBy` / `blocks`: `BT-XX` identifiers if dependencies are known (see below).

To discover or verify the available label *names*, use `list_issue_labels` (team: `"BT"`).

**Labels to include:**
- One **Agent State** label: `agent-ready`, `needs-spec`, or `blocked`
- One **Issue Type** label: `Feature`, `Bug`, `Improvement`, etc.
- One **Item Area** label: `parser`, `codegen`, `stdlib`, `repl`, `cli`, `runtime`, or `class-system`
- One **Item Size** label: `S`, `M`, `L`, or `XL`

## Creating Blocking Relationships

When issues have dependencies, **always** set up Linear's "blocks" relationships. `save_issue` accepts these directly by `BT-XX` identifier — no UUID lookup, no separate mutation:

- On the blocker: `save_issue` (id: `"BT-blocker"`, `blocks: ["BT-blocked"]`)
- Or on the blocked issue: `save_issue` (id: `"BT-blocked"`, `blockedBy: ["BT-blocker"]`)

When creating a new issue that is already blocked by an existing one, set `blockedBy` in the same `save_issue` create call — no follow-up step needed.

## Rules

- **Always assign to `me`** — pass `assignee: "me"` so issues go to the current user
- If issue A must be completed before issue B can start, then A "blocks" B
- Always create blocking relationships when dependencies are mentioned
- Set estimate based on complexity, not time
- Add to relevant project if one exists for the work area
