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

Small problems found along the way (by `/review-code`, the review bot, or `/resolve-pr`) are fixed in the PR that found them. The backlog is being closed down, so these skills file a follow-up issue only for work in another repo, work of size M or larger, a decision that needs you, or a security finding that can't be fixed now. Everything else is fixed or dropped with a reason.

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
.claude-plugin/   # plugin.json + marketplace.json (installable as a plugin)
skills/           # Claude Code skills (SKILL.md per directory)
agents/           # Claude Code agents (.md files)
scripts/          # Tooling
  validate.sh     # Structural validation for skills & agents
  install.sh      # Local install (symlinks to ~/.claude/)
  sync-skills.sh  # Sync in-session changes back to repo
.claude/
  hooks/          # SessionStart hook for web sessions
  settings.json   # Hook registration
```

## Setup

### As a plugin (Claude Code marketplace)

This repo is a Claude Code plugin marketplace (`.claude-plugin/marketplace.json`) with one plugin, `dev-workflow`, that contains every skill and agent here:

```
/plugin install dev-workflow --marketplace jamesc/skills
```

Or in two steps: `/plugin marketplace add jamesc/skills`, then `/plugin install dev-workflow@jamesc-skills`.

Plugin skills are namespaced, so `/done` becomes `/dev-workflow:done`. Don't combine this with `./scripts/install.sh` below: each skill would be loaded twice, once from the symlinks and once from the plugin. Bump `version` in both `.claude-plugin/plugin.json` and the marketplace entry when you want installed copies to update.

### Claude Code on the web

Skills and agents are automatically installed via the `SessionStart` hook when you open this repo in a Claude Code web session. Run `/sync-skills` before ending the session to sync any improvements back and open a PR — see "Syncing Improvements" below.

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

3. Optional fields: `model`, `effort`, `context`, `agent`, `argument-hint`, `allowed-tools`, `disable-model-invocation`. Pick `model` by the policy in "Model Policy" below.

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

3. Optional fields: `tools`, `model`, `effort`, `maxTurns`, `permissionMode`, `isolation`, `background`, `skills`, `mcpServers`, `hooks`, `memory`, `disallowedTools`

## Model Policy

Each skill runs on the cheapest model that does its job reliably. A skill's `model` and `effort` apply for the rest of the turn that invokes it, then the session model resumes.

| Tier | Model | Work | Skills |
|---|---|---|---|
| Mechanical | `haiku` | Linear queries and bulk label edits, running a script | `whats-next`, `update-issues`, `sync-skills` |
| Routine | `sonnet` | Well-specified implementation, merges, commit/push/PR, comparing an issue against the code | `done`, `resolve-merge`, `refresh-issue`, `do-refactor` |
| Judgment | `opus` | Reviews, planning, orchestrating parallel agents | `review-code`, `review-adr`, `plan-adr`, `plan-refactor`, `pick-epic` |
| Open-ended | `fable` | Architecture decisions with no clear answer | `draft-adr` |
| Session model | (no pin) | Work whose difficulty varies, and reference skills | `pick-issue`, `resolve-pr`, `create-issue`, `explain`, `linear`, `use-lsp` |

Rules for choosing:

- **Pin a model only when the work is the same tier every time.** `pick-issue` implements anything from a typo to a codegen change, so it follows the session model. Choose that with `/model` before you start.
- **Never pin a reference skill.** `linear` and `use-lsp` load on their own in the middle of other work, and a pin would move that work to the pinned model for the rest of the turn.
- **In a chain, the last pinned skill wins.** `/pick-issue` → `/review-code` → `/done` runs on the session model, rises to Opus for the review, and drops to Sonnet for the push and CI wait. A skill at the end of a chain needs a pin for this reason, or it runs on whatever came before it.
- **Put the expensive model on the narrow step.** `do-refactor` runs on Sonnet and sends each review to an Opus subagent. `draft-adr` and `plan-refactor` send lookups and repo scans to Sonnet subagents and keep the main model for the analysis.
- **Fork read-heavy mechanical skills** (`context: fork`). `whats-next` and `update-issues` run in a fresh Haiku subagent: Haiku never re-reads the conversation so far, and dozens of issue listings stay out of the main context. A forked skill can't ask the user questions.
- **Set subagent models on the `Agent` call.** A subagent without `model` inherits the caller's, so an Opus orchestrator spawns Opus workers. `pick-epic` chooses by issue size: S/M on Sonnet, L/XL on Opus.
- **Raise `effort` before raising the model.** The review skills run at `effort: high`; everything else uses the session level.
- **An adversarial reviewer runs on a different model from the author.** `review-adr` uses Opus against Fable-drafted ADRs.

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

If skills are improved during a Claude Code session, run `/sync-skills` to sync the changes back to this repo and open a PR. `scripts/sync-skills.sh` also supports an `--auto` mode intended for a `SessionStop` hook, but no such hook is currently registered in `.claude/settings.json` — syncing today is manual only.

## Expected Install Locations

| Tool | Global | Project |
|------|--------|---------|
| Claude Code | `~/.claude/skills/` / `~/.claude/agents/` | `.claude/skills/` / `.claude/agents/` |
| Copilot | `~/.copilot/skills/` | — |
| AMP | `~/.amp/skills/` | — |

Priority: Enterprise > User (Global) > Project
