# Agent Infrastructure

A reusable multi-agent development infrastructure for Claude Code. Combines an Anthropic-powered
orchestrator with free CERIT-powered worker agents, an Obsidian-compatible second brain vault,
automatic archiving hooks, and quality enforcement gates.

## What this is

- **Orchestrator** (Anthropic Claude): reasoning, decisions, PR review, user communication
- **Workers** (CERIT – free OpenAI-compatible endpoint): all heavy work – coding, research, testing
- **Second brain vault**: Obsidian-compatible markdown vault that accumulates knowledge automatically
- **Librarian**: CERIT-powered agent that reads and writes the vault; called by hooks automatically
- **Parallel implementation**: best-of-3 pattern with a judge for high-quality output
- **Quality enforcement**: linting on every write, test gate before session close

## Prerequisites

- [`claude`](https://claude.ai/download) CLI installed and authenticated
- `git` (any recent version)
- `python3` (3.10+)
- `curl` and `jq`
- [`gh`](https://cli.github.com/) (GitHub CLI) – optional, enables PR creation in workers

## Quick start

```bash
git clone https://github.com/ChlupacTheBosmer/agent_infra.git
cd agent_infra
./install.sh
source ~/.bashrc
```

The installer will:
1. Check prerequisites
2. Prompt for your Anthropic API key and vault path
3. Query CERIT for available models and ask you to select one per role
4. Write environment variables to `~/.bashrc`
5. Create symlinks in `~/.claude/`
6. Write `~/.claude/settings.json` with all hooks configured
7. Copy the vault template to your vault path
8. Initialise the vault as a git repo

## Using with a new project

```bash
# In your project repo:
cp -r /path/to/agent-infra/project-template/.claude .claude
cp /path/to/agent-infra/project-template/CLAUDE.md CLAUDE.md
cp -r /path/to/agent-infra/project-template/docs docs
cp -r /path/to/agent-infra/project-template/tasks tasks
```

Then fill in Zone B of `CLAUDE.md` with project-specific context.

## Provider switching

After `source ~/.bashrc`:

```bash
ca   # Anthropic Claude (orchestrator – costs money, use for decisions)
cc   # CERIT Claude (free – use for all heavy work)
```

## Spawning CERIT workers

```bash
# Inline task string (quick ad-hoc tasks)
bash cerit-worker.sh "implement X in src/module.py with tests" /tmp/result.md feature/my-branch

# YAML spec file (preferred for complex tasks)
bash cerit-worker.sh tasks/task-001.yaml /tmp/result.md feature/my-branch
```

## Parallel implementation

```bash
# Spawns 3 workers on the same task, judge picks the best, winner merged
bash parallel-implement.sh "implement the data loader with caching" main
```

## Generator-evaluator refinement loop

```bash
# Iteratively implements and evaluates until PASS or max rounds
bash implement-and-refine.sh "fix the authentication bug in auth/jwt.py" main 3
```

## Vault / librarian

**Before complex tasks – get a reading list:**
```bash
BRIEFING=$(librarian-retrieve.sh "implement feature X" my-project)
cat "$BRIEFING"
```

**After completing work – archive to vault:**
```bash
# Write a brief markdown summary first
cat > /tmp/summary.md << EOF
# Session summary
What was done: implemented X
Key decisions: used approach Y because Z
Results: tests passing
EOF
librarian-archive.sh worker-result /tmp/summary.md my-project
```

**Weekly vault health check:**
```bash
vault-health.sh
# Report at: $VAULT/agents/vault-health-report-YYYY-MM-DD.md
```

## Vault structure

```
$VAULT/
├── 000-INDEX.md          ← start here – master navigation hub
├── atlas/                ← stable reference knowledge (methods, datasets, infrastructure)
├── projects/             ← one directory per project
│   └── INDEX.md          ← project list with status
├── inbox/                ← temporary captures, unprocessed
└── archive/              ← completed/abandoned projects
```

**Always start from `$VAULT/000-INDEX.md`** when you need vault context.

## Adding a new project to the vault

```bash
mkdir -p $VAULT/projects/my-project/context
cp $VAULT/agents/templates/project-index.md $VAULT/projects/my-project/INDEX.md
# Edit the INDEX.md – fill in project name, goal, status
# Add a row to $VAULT/projects/INDEX.md and $VAULT/000-INDEX.md
touch $VAULT/projects/my-project/CHANGELOG.md
```

## Skills – adding and managing

Skills are slash-commands for Claude Code. Each skill lives in a directory containing `SKILL.md`.

**Where they live:** `claude-config/skills/` (symlinked to `~/.claude/skills/`)

**Currently installed skills:** see [claude-config/skills/README.md](claude-config/skills/README.md)

**To add a skill:**
1. Download or create a skill directory (e.g. from [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code))
2. Drop it into `claude-config/skills/`
3. `git add` the directory and commit

**Built-in skills:**
- `/parallel-implement` – best-of-3 parallel coding with judge
- `/implement-and-refine` – generator-evaluator refinement loop

## Editing CLAUDE.md

`~/.claude/CLAUDE.md` (symlinked from `claude-config/CLAUDE.md`) has two zones:

- **Zone A** (~lines 1–150): Infrastructure rules. Don't edit unless you understand the implications.
- **Zone B** (rest): Your configuration. Fill this in with your role, projects, preferences, and environment quirks. It is never overwritten by `git pull`.

## Updating

```bash
cd agent_infra
git pull
# Symlinks pick up changes automatically
# Zone B of CLAUDE.md is never touched by updates
```

## Troubleshooting

**CERIT key not set:**
```bash
source ~/.bashrc   # or re-run install.sh
echo $CERIT_API_KEY   # should print the key
```

**gh not authenticated:**
```bash
gh auth login
```

**Worktree conflicts (from parallel-implement.sh):**
```bash
# List and remove stale worktrees
git worktree list
git worktree remove .claude/worktrees/<name> --force
git branch -D impl/<branch-name>
```

**Context limit with CERIT models:**
CERIT models may have smaller context windows than Anthropic models. If a worker
fails with context errors, reduce `max_turns` or break the task into smaller pieces.

**Stop hook blocking session close:**
The stop-gate hook blocks if tests are failing. Fix the failures (or use Ctrl+C to
force-close if genuinely stuck). Do not use `/clear` to escape – fix the root cause.
