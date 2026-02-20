# Skills Repository

This repository contains a collection of agent skills extracted from the current project. Each skill is designed to perform a specific task and is documented in its respective `SKILL.md` file.

## Directory Structure

- **create-issue/**: Skill for creating issues.
- **do-refactor/**: Skill for performing refactoring tasks.
- **done/**: Skill for marking tasks as done.
- **draft-adr/**: Skill for drafting architectural decision records (ADRs).
- **linear/**: Skill for linear workflows.
- **pick-issue/**: Skill for picking issues to work on.
- **plan-adr/**: Skill for planning ADRs.
- **plan-refactor/**: Skill for planning refactoring tasks.
- **refresh-issue/**: Skill for refreshing issue states.
- **resolve-merge/**: Skill for resolving merge conflicts.
- **resolve-pr/**: Skill for resolving pull requests.
- **review-adr/**: Skill for reviewing ADRs.
- **review-code/**: Skill for reviewing code.
- **update-issues/**: Skill for updating issues.
- **whats-next/**: Skill for determining the next steps.

## How to Use

Each skill is documented in its `SKILL.md` file. Refer to these files for detailed instructions on how to use each skill.

## Contributing

If you wish to contribute to this repository, please ensure that your skills are well-documented and follow the existing structure.

## Expected Locations for Skills

Different tools may expect the skills to be located in specific directories. Ensure that the skills are placed in the following locations:

- **Claude**: 
  - **Global Skills**: `~/.claude/skills/` (available in all projects).
  - **Project Skills**: `.claude/skills/` (project-specific).
  - **Behavior**: When skills share the same name, the priority is Enterprise > User (Global) > Project.
  - **Structure**: Each skill requires a `SKILL.md` file containing YAML metadata and markdown instructions.

- **Copilot**: Looks for skills in the `~/.copilot/skills/` directory, following the same structure as Claude.
- **AMP**: Requires skills to be organized under `~/.amp/skills/` with proper documentation in `SKILL.md` files.

Ensure that the directory structure and file naming conventions are consistent to avoid issues with these tools.