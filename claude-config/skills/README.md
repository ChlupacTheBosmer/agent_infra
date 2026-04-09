# Skills – Usage and Management

## What are skills?

Skills are reusable slash-command prompts for Claude Code. Each skill lives in its own
subdirectory containing a `SKILL.md` file. Claude Code automatically discovers any
`SKILL.md` file inside a subdirectory of `~/.claude/skills/` and makes it available
as a `/skill-name` slash-command (where `skill-name` matches the directory name).

When you type `/parallel-implement` in a Claude Code session, Claude Code loads the
`SKILL.md` from `parallel-implement/SKILL.md` and executes it as a structured prompt.

## Currently installed skills

| Skill directory | Trigger | Purpose |
|----------------|---------|---------|
| parallel-implement/ | /parallel-implement | Best-of-3 parallel coding with judge |
| implement-and-refine/ | /implement-and-refine | Generator-evaluator refinement loop |
| (add rows as you install community skills) | | |

## How to add a new skill

1. Download or create a skill directory (e.g. `git-workflow/SKILL.md`)
2. Drop it into `agent-infra/claude-config/skills/`
3. `git add` the directory and commit — the skill is immediately available via symlink in all sessions, and versioned in the infra repo

## Where to find community skills

Community skills are available at: https://github.com/hesreallyhim/awesome-claude-code

Browse the repository for skill collections, download the ones you want, and drop them
into this directory following the steps above.

## Scope: global vs project-local

Skills in `~/.claude/skills/` (symlinked from this directory) are **global** — available
in all Claude Code sessions across all projects.

Project-local skills go in `.claude/skills/` inside the project repo itself. These
override global skills with the same name within that project.

## Skill file format

Each `SKILL.md` must have YAML frontmatter with at minimum:
```yaml
---
name: skill-name
description: >
  One paragraph describing when to use this skill.
---
```

The body of the file is the prompt that will be executed when the skill is invoked.
