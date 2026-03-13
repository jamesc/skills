# Skills & Agents Repository

A collection of Claude Code skills and agent definitions.

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

# Markdown linting
npx markdownlint-cli2 "**/*.md"

# Shell script linting
shellcheck .claude/hooks/*.sh scripts/*.sh
```

CI runs all three checks on every push and PR to `main`.

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
