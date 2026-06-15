---
name: linear
description: Manage Linear issues. Use when asked about tasks, tickets, bugs, or Linear.
model: haiku
---

# Linear

Use the Linear MCP tools (`mcp__linear-server__*`) for all Linear interactions. The MCP tool descriptions document arguments — this skill only covers conventions that aren't obvious from those descriptions.

## Core tools

| Action | Tool |
|---|---|
| Find issues | `list_issues` (defaults to caller's active issues when `assignee: "me"`) |
| Issue details | `get_issue` (accepts `ABC-123`, URL, or UUID) |
| Create **or** update issue | `save_issue` — pass `id` to update, omit `id` to create |
| Comment | `save_comment` (pass `id` to edit) |
| List comments | `list_comments` |
| Teams / users / statuses | `list_teams`, `list_users`, `list_issue_statuses` |

Projects, milestones, and documents have the same `list_*` / `get_*` / `save_*` (or `create_*` / `update_*`) shape — check the tool list before hand-rolling anything. Attachments have `create_*` / `get_*` / `delete_*`. Labels can be listed (`list_issue_labels`, `list_project_labels`) and created (`create_issue_label`).

`save_issue` handles directly — no GraphQL, no UUID lookups:
- **Apply labels:** `labels: ["agent-ready", "Feature", …]` (label *names*, not UUIDs).
- **Blocking relationships:** `blocks: ["BT-2"]` or `blockedBy: ["BT-1"]` (`BT-XX` identifiers; append-only). `relatedTo` for non-blocking links.
- **State / priority / parent / assignee:** `state`, `priority` (0–4), `parentId`, `assignee` — all accept names/identifiers/`"me"`.

## Priority values

| Value | Label |
|-------|-------|
| 0 | No priority |
| 1 | Urgent |
| 2 | High |
| 3 | Medium |
| 4 | Low |

## Conventions

- **"me" / "my issues":** pass `assignee: "me"` to `list_issues`. The MCP resolves it to the authenticated user.
- **State names are fuzzy** in most tools — `"in progress"` matches `"In Progress"`. When in doubt, call `list_issue_statuses` for the exact names for a team.
- **Issue IDs:** `BT-123` style shorthand, Linear URLs, and UUIDs are all accepted by `get_issue` / `save_issue` / `save_comment`.
- **Unassign:** pass `assignee: null` to `save_issue`.
- **Create vs update:** both go through `save_issue`. Presence of `id` is the discriminator.

## Authentication

Handled by the MCP server config; no per-call token needed.
