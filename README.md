# Skills & Agents Repository

A collection of Claude Code skills and agent definitions. The skills compose into a development lifecycle: architectural decisions are captured as ADRs, broken down into Linear issues, implemented on branches (solo or with parallel agents), and shipped through PRs.

## Workflows

### Planning via ADR

Significant changes start as an Architecture Decision Record and end as a planned epic in Linear:

1. `/draft-adr` — research a problem (codebase + web) and draft an ADR
2. `/review-adr` — review the ADR for completeness, correctness, and quality
3. `/plan-adr` — break the accepted ADR into a Linear epic with dependency-ordered implementation issues

### Building via pick-issue

The day-to-day loop for implementing issues:

1. `/whats-next` — recommend the next logical piece of work from the backlog
2. `/pick-issue` — pick up the next Linear issue and start a branch
3. `/review-code` — review the branch changes against main before pushing
4. `/done` — commit, push, and create the PR, linking the Linear issue
5. `/resolve-pr` — address review comments systematically
6. `/resolve-merge` — merge main into the branch and resolve conflicts

For a whole epic at once, `/pick-epic` runs the child issues in dependency-ordered waves using parallel subagents — one isolated worktree and PR per issue, squash-merging as CI and automated reviews pass.

### Refactoring

1. `/plan-refactor` — analyze the codebase and plan refactoring work as an epic
2. `/do-refactor` — execute the refactoring epic sequentially on a single branch, verifying CI after each issue

### Issue management

- `/linear` — general Linear issue management (tasks, tickets, bugs)
- `/create-issue` — create a well-structured issue with blocking relationships
- `/refresh-issue` — re-align an issue with the current docs and code state
- `/update-issues` — bulk-fix issues missing labels, sizes, or relationships

### Utilities

- `/explain` — produce a walkthrough document for code, a pattern, or a feature
- `/use-lsp` — navigate code via LSP (definitions, references, call hierarchies)
- `/sync-skills` — sync in-session skill improvements back to this repo as a PR

## Directory Structure

```
skills/           # Claude Code skills (SKILL.md per directory)
agents/           # Claude Code agents (.md files)
scripts/          # Tooling
  validate.sh     # Structural validation for skills & agents
  install.sh      # Local install (symlinks to ~/.claude/)
  sync-skills.sh  # Sync in-session changes back to repo
.claude/
  hooks/          # SessionStart/Stop hooks for web sessions
  settings.json   # Hook registration
```

## Setup

### Claude Code on the web

Skills and agents are automatically installed via the `SessionStart` hook when you open this repo in a Claude Code web session. Modified skills are synced back and a PR is created when the session ends.

### Local CLI

```bash
./scripts/install.sh
```

This symlinks all skills and agents to `~/.claude/skills/` and `~/.claude/agents/`, so edits in the repo are immediately available in Claude Code.

## Adding a Skill

1. Create a directory under `skills/` with a `SKILL.md` file:

```
skills/my-skill/
  SKILL.md
```

2. Include YAML frontmatter with at least `name` and `description`:

```yaml
---
name: my-skill
description: What this skill does and when to use it.
---
```

3. Optional fields: `model`, `argument-hint`, `allowed-tools`

## Adding an Agent

1. Create a `.md` file under `agents/`:

```
agents/my-agent.md
```

2. Include YAML frontmatter with at least `name` and `description`:

```yaml
---
name: my-agent
description: What this agent does.
---
```

3. Optional fields: `tools`, `model`, `maxTurns`, `permissionMode`, `isolation`, `background`, `skills`, `mcpServers`, `hooks`, `memory`, `disallowedTools`

## Validation

Run locally:

```bash
# Structural validation
./scripts/validate.sh

# Skill linting (frontmatter, description quality, body size, links)
npx skill-check check . --no-security-scan

# Markdown linting
npx markdownlint-cli2 "**/*.md"

# Shell script linting
shellcheck .claude/hooks/*.sh scripts/*.sh
```

CI runs all four checks on every push and PR to `main`. [skill-check](https://github.com/thedaviddias/skill-check) is configured via `skill-check.config.json`; the `frontmatter.unknown_fields` rule is disabled because Claude Code supports fields (`model`, `argument-hint`) beyond the agentskills.io spec. skill-check's security scan is disabled (`--no-security-scan`) because its backend (snyk-agent-scan) requires a Snyk account token — deliberate omission for a personal repo of hand-written skills.

## Syncing Improvements

If skills are improved during a Claude Code session:

- **Automatic**: The `SessionStop` hook syncs changes and opens a PR
- **Manual**: Run `/sync-skills` to sync on demand

## Expected Install Locations

| Tool | Global | Project |
|------|--------|---------|
| Claude Code | `~/.claude/skills/` / `~/.claude/agents/` | `.claude/skills/` / `.claude/agents/` |
| Copilot | `~/.copilot/skills/` | — |
| AMP | `~/.amp/skills/` | — |

Priority: Enterprise > User (Global) > Project
