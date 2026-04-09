# Agent Infrastructure — Complete Implementation Specification

**Document purpose:** This is a full specification for a Claude Code agent to implement. The agent should implement everything described here as a standalone git repository that can be cloned or submoduled into any project.

**Before starting:** Read this entire document from start to finish before writing any file. The document is long but comprehensive — each section either defines a file to create or provides essential context. The "Order of implementation" section near the end tells you the correct build order. The "Testing checklist" tells you exactly what to verify when done.

**Key conventions used in this document:**
- Code blocks containing file content are meant to be created verbatim as the specified file
- `[FILL IN: ...]` markers appear only in user-facing templates (Zone B of CLAUDE.md files, project templates) — leave them as-is; they are for the human user to complete after setup
- Section headers like `### \`scripts/foo.sh\`` mean "create this file with the content in the following code block"
- The "Librarian system — complete specification" section near the end elaborates on components already listed in the repository structure — do not create duplicate files
- All `AGENT_INFRA_DIR_PLACEHOLDER` strings in settings.json must be replaced with the actual absolute path during `install.sh` execution, not hardcoded in the file itself

---

## Overview and philosophy

This repository provides a multi-agent development infrastructure that combines:

- An **Anthropic-powered orchestrator** (the main Claude Code session the user chats with via VSCode) for high-level reasoning, decisions, PR review, and coordination
- **CERIT-powered worker agents** (free, OpenAI-compatible endpoint at `https://llm.ai.e-infra.cz/`) for all heavy work: coding, research, data processing, testing
- An **Obsidian-compatible second brain** (a vault of `.md` files) for persistent knowledge across all projects and sessions
- A **librarian agent** that serves as the vault's sole gatekeeper: it receives content to archive (from agents and hooks automatically), structures it into the right vault files, maintains hub/index pages, and provides reading lists to agents before they start work
- A **parallel implementation pattern** (best-of-3 with a judge) for high-quality output on complex tasks
- **Claude Code hooks** that automatically feed session transcripts and subagent logs to the librarian at the end of every session — no manual effort required

The core principle: spend Anthropic tokens only on decisions that genuinely require Claude's reasoning quality. Everything else runs free on CERIT. The second brain accumulates automatically — the user never has to manually document anything.

---

## Repository structure to create

```
agent-infra/
│
├── README.md                          ← human-readable setup guide
├── AGENT_INFRASTRUCTURE_SPEC.md       ← this file (keep in repo for reference)
├── install.sh                         ← one-shot install script
│
├── claude-config/
│   ├── CLAUDE.md                      ← global orchestrator brain (symlinked to ~/.claude/CLAUDE.md)
│   ├── agents/                        ← subagent definitions (symlinked to ~/.claude/agents/)
│   │   ├── cerit-coder.md
│   │   ├── cerit-researcher.md
│   │   ├── cerit-reviewer.md
│   │   ├── cerit-data.md
│   │   ├── architecture-guardian.md   ← NEW: checks PRs against ADRs
│   │   ├── deep-explorer.md
│   │   └── test-verifier.md
│   ├── hooks/
│   │   ├── session-end-archivist.py   ← Stop hook: archives session to vault
│   │   ├── subagent-end-archivist.py  ← SubagentStop hook: archives subagent result
│   │   ├── quality-check.py           ← NEW: PostToolUse linter feedback after every write
│   │   └── stop-gate.py               ← NEW: Stop hook — blocks if tests failing
│   └── skills/                        ← user skills library (symlinked to ~/.claude/skills/)
│       ├── README.md                  ← how to add skills; lists installed skills
│       ├── parallel-implement/
│       │   └── SKILL.md              ← built-in: best-of-3 parallel pattern
│       ├── implement-and-refine/
│       │   └── SKILL.md              ← NEW: generator-evaluator refinement loop
│       └── .gitkeep-community/        ← placeholder; user drops downloaded skill dirs here
│
├── scripts/
│   ├── cerit-worker.sh                ← CERIT worker spawner (accepts task spec YAML or string)
│   ├── parallel-implement.sh          ← best-of-3 parallel pattern
│   ├── implement-and-refine.sh        ← NEW: generator-evaluator loop
│   ├── librarian-archive.sh           ← archivist entry point (push content to vault)
│   ├── librarian-retrieve.sh          ← retriever entry point (pull reading list)
│   ├── vault-health.sh                ← NEW: weekly vault cleanup agent
│   └── send-report.py                 ← email reporting
│
├── vault-template/                    ← Obsidian second brain scaffold
│   ├── 000-INDEX.md
│   ├── atlas/
│   │   ├── INDEX.md
│   │   ├── methods/
│   │   ├── datasets/
│   │   ├── infrastructure/
│   │   └── decisions/
│   ├── projects/
│   │   └── INDEX.md
│   ├── inbox/
│   ├── archive/
│   │   └── INDEX.md
│   └── agents/
│       ├── librarian-archive-prompt.md
│       ├── librarian-retrieve-prompt.md
│       ├── templates/
│       │   ├── project-index.md
│       │   ├── changelog-entry.md
│       │   └── briefing.md
│       └── sessions/
│
└── project-template/                  ← drop into any new project repo
    ├── .claude/
    │   ├── agents/
    │   │   ├── deep-explorer.md       ← project-scoped (same as global but here for portability)
    │   │   └── test-verifier.md
    │   └── settings.json              ← enables agent teams, sets env
    ├── docs/
    │   └── adr/                       ← NEW: Architecture Decision Records
    │       ├── README.md              ← how to write ADRs
    │       └── adr-template.md        ← template for new ADRs
    ├── tasks/                         ← NEW: structured task spec files
    │   └── task-template.yaml         ← template for new task specs
    └── CLAUDE.md                      ← project-level supplement to global CLAUDE.md
```

### Skills directory — key design points

The `claude-config/skills/` directory is symlinked to `~/.claude/skills/` by the installer. Claude Code automatically discovers any `SKILL.md` file inside a subdirectory of this folder and makes it available as a `/skill-name` slash-command.

**The directory serves two purposes:**
- Ships a small set of **built-in infrastructure skills** (currently just `parallel-implement`)
- Acts as the **drop zone for community/downloaded skills** the user gathers over time

**How a user adds a skill:**
1. Download or create a skill directory (e.g. `git-workflow/SKILL.md`)
2. Drop it into `agent-infra/claude-config/skills/`
3. `git add` and commit — the skill is immediately available via symlink in all sessions, and versioned in the infra repo

**The `claude-config/skills/README.md`** (implement this file) should contain:
- One-paragraph explanation of what skills are and how Claude Code loads them
- Table listing all currently installed skills with their trigger command and purpose
- Instructions for adding a new skill (3 steps above)
- Link to community skill sources (e.g. `github.com/hesreallyhim/awesome-claude-code`)
- Note that skills in `~/.claude/skills/` are global (all projects); project-local skills go in `.claude/skills/` inside the project repo

**The `claude-config/skills/README.md` table template:**

```markdown
| Skill directory | Trigger | Purpose |
|----------------|---------|---------|
| parallel-implement/ | /parallel-implement | Best-of-3 parallel coding with judge |
| implement-and-refine/ | /implement-and-refine | Generator-evaluator refinement loop |
| (add rows as you install community skills) | | |
```

---

## Environment variables required

The install script should write these to `~/.bashrc`. **CERIT credentials are pre-configured** — the installer does not need to prompt for them. Only the Anthropic API key and vault path require user input.

```bash
# Anthropic (orchestrator) — user must supply this
export ANTHROPIC_API_KEY="sk-ant-..."

# CERIT endpoint — pre-configured, do not change
export CERIT_API_KEY="REPLACE_WITH_CERIT_API_KEY"
export CERIT_BASE_URL="https://llm.ai.e-infra.cz/v1"

# Vault location — prompted during install
export VAULT="$HOME/vault"

# Agent infra repo location — set by install.sh to actual absolute path
export AGENT_INFRA_DIR="<set-by-install>"

# Agent Teams (experimental but useful)
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# Logging
mkdir -p "$HOME/logs"
```

**Note on CERIT_BASE_URL:** The correct URL is `https://llm.ai.e-infra.cz/v1` (with `/v1` suffix — this is the OpenAI-compatible endpoint). Earlier parts of this spec used the URL without `/v1`; the `/v1` form is correct.

Also add these shell aliases. The model name placeholders (`CERIT_CODER_MODEL` etc.) are filled in by the installer after the user selects models in the interactive model selection step:

```bash
# Provider switching — model names filled in by install.sh after model selection
alias ca='claude'                               # Anthropic native (default)
alias cc='ANTHROPIC_BASE_URL="$CERIT_BASE_URL" ANTHROPIC_AUTH_TOKEN="$CERIT_API_KEY" ANTHROPIC_MODEL="$CERIT_CODER_MODEL" ANTHROPIC_DEFAULT_OPUS_MODEL="$CERIT_THINKER_MODEL" ANTHROPIC_DEFAULT_SONNET_MODEL="$CERIT_CODER_MODEL" ANTHROPIC_DEFAULT_HAIKU_MODEL="$CERIT_FAST_MODEL" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude'
```

---

## File contents to implement

### `install.sh`

One-shot installer. Implements all steps below in order. Must be idempotent.

**Step 1 — Prerequisites check**
Check for: `claude`, `git`, `python3`, `curl`, `jq`. Print clear error if missing. `gh` is optional — note if absent.

**Step 2 — User input (minimal — CERIT is pre-configured)**
Prompt for:
- `ANTHROPIC_API_KEY` (required)
- Vault path (default: `$HOME/vault`)
- Email address for agent reports (optional, can be blank)

Do NOT prompt for CERIT credentials — they are hardcoded in the env vars section above.

**Step 3 — Dynamic model selection (critical step)**

Query the CERIT endpoint to get available models:
```bash
curl -s -H "Authorization: Bearer REPLACE_WITH_CERIT_API_KEY" \
  https://llm.ai.e-infra.cz/v1/models | jq -r '.data[].id' | sort
```

Display the model list to the user. Then for each of the following roles, show the list and ask the user to pick (with the implementing agent's recommendation clearly marked):

| Role | What it does | Recommended model | Why |
|------|-------------|-------------------|-----|
| `CERIT_CODER_MODEL` | Main coding work, agentic tasks | (agent recommends after seeing list) | Needs strong tool use and long context |
| `CERIT_THINKER_MODEL` | Complex reasoning, planning, judge | (agent recommends after seeing list) | Needs best reasoning quality |
| `CERIT_FAST_MODEL` | Simple/fast tasks, explore subagents | (agent recommends after seeing list) | Needs speed over quality |
| `CERIT_LIBRARIAN_MODEL` | Archivist and retriever operations | (agent recommends after seeing list) | Needs strong comprehension and writing, NOT mini |

**The implementing agent's job:** After fetching the model list, examine the available models and provide concrete recommendations for each role based on model names (e.g. models with "coder" in the name for CERIT_CODER_MODEL, models with "thinker" or reasoning indicators for CERIT_THINKER_MODEL, etc.). Present these recommendations clearly before asking the user to confirm or override.

Store selections as environment variables written to `~/.bashrc`:
```bash
export CERIT_CODER_MODEL="<selected>"
export CERIT_THINKER_MODEL="<selected>"
export CERIT_FAST_MODEL="<selected>"
export CERIT_LIBRARIAN_MODEL="<selected>"
```

**Step 4 — Write environment variables to `~/.bashrc`**
Write all env vars from the "Environment variables required" section. Set `AGENT_INFRA_DIR` to the actual absolute path of the repo (use `$(pwd)` or `$(dirname "$0")` resolved to absolute). Make idempotent with guard markers.

**Step 5 — Create `~/.claude/` structure and symlinks**
```bash
mkdir -p ~/.claude/agents ~/.claude/skills ~/.claude/hooks
ln -sf "$AGENT_INFRA_DIR/claude-config/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$AGENT_INFRA_DIR/claude-config/agents" ~/.claude/agents
ln -sf "$AGENT_INFRA_DIR/claude-config/skills" ~/.claude/skills
```

**Step 6 — Write global `~/.claude/settings.json` with permissions and hooks**

The full hooks configuration to merge includes: `UserPromptSubmit` (cost-estimator), `PostToolUse` on Write/Edit/MultiEdit (quality-check), `Stop` (stop-gate blocking + archivist async), and `SubagentStop` (archivist async). See the settings.json spec below for the complete JSON. Remember to substitute `AGENT_INFRA_DIR_PLACEHOLDER` with the actual absolute path.

Also add the `cost-estimator.py` to the hook files to make executable.

Write (or merge into) `~/.claude/settings.json`:
```json
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "deny": [
      "Bash(rm -rf *)",
      "Bash(rm -f /*)",
      "Bash(dd *)",
      "Bash(mkfs*)",
      "Bash(fdisk*)",
      "Bash(shred*)",
      "Bash(wipefs*)",
      "Bash(:(){:|:&};:)",
      "Bash(chmod -R 777 /*)",
      "Bash(chown -R * /*)"
    ]
  },
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 AGENT_INFRA_DIR_PLACEHOLDER/claude-config/hooks/cost-estimator.py",
            "async": false
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 AGENT_INFRA_DIR_PLACEHOLDER/claude-config/hooks/quality-check.py",
            "async": false
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 AGENT_INFRA_DIR_PLACEHOLDER/claude-config/hooks/stop-gate.py"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 AGENT_INFRA_DIR_PLACEHOLDER/claude-config/hooks/session-end-archivist.py",
            "async": true
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 AGENT_INFRA_DIR_PLACEHOLDER/claude-config/hooks/subagent-end-archivist.py",
            "async": true
          }
        ]
      }
    ]
  }
}
```
Replace `AGENT_INFRA_DIR_PLACEHOLDER` with the actual absolute path of `$AGENT_INFRA_DIR`. The install script must do this substitution — `settings.json` does not expand shell variables.

**Hook execution order and behaviour:**
- `PostToolUse` (quality-check): runs synchronously after every Write/Edit — provides linter feedback injected back to Claude as `additionalContext`. Non-blocking (never prevents the write from happening, only provides feedback).
- `Stop` (stop-gate): runs synchronously before session close — if tests are failing, exits with code 2 to block the stop and inject error message as feedback. The `session-end-archivist` runs async after the stop is confirmed.
- `SubagentStop` (archivist): runs async after subagent completion — never blocks result return.

**Step 7 — Copy vault template**
Copy `vault-template/` to the user-specified vault path. Do NOT overwrite if vault already exists and contains files.

**Step 8 — Scripts setup**
Add the repo's `scripts/` directory to PATH in `~/.bashrc`. Make all `.sh` and `.py` files in `scripts/` and `claude-config/hooks/` executable.

**Step 9 — Vault git init**
`git init` in the vault directory (skip if already a git repo). Make initial commit with all template files.

**Step 10 — Summary and next steps**
Print:
```
════════════════════════════════════════════
Agent Infrastructure — Setup Complete
════════════════════════════════════════════
CERIT models configured:
  Coder:     <selected>
  Thinker:   <selected>
  Fast:      <selected>
  Librarian: <selected>

Next steps:
1. Run: source ~/.bashrc
2. Edit ~/.claude/CLAUDE.md — fill in Zone B with your details
3. For each project: copy project-template/ into the repo and fill in CLAUDE.md
4. Seed the vault: open $VAULT in Obsidian and add your knowledge to atlas/

To add a new skill: drop a directory into claude-config/skills/ and git commit.
````
```

---

### `claude-config/CLAUDE.md`

This is the global agent brain. **Every `claude` process — Anthropic or CERIT, orchestrator or worker — reads this at startup.** It has two clearly separated zones:

- **Zone A (lines 1–~150):** Infrastructure rules. Written by this spec. Do not change without understanding the implications. Kept ruthlessly short because it costs tokens on every single session.
- **Zone B (lines ~150–end):** User configuration. Clearly marked. The user fills this in with project context, personal preferences, and domain knowledge. The agent reads it as authoritative instruction.

The implementing agent must create the file with exactly this structure and content:

```markdown
# ═══════════════════════════════════════════════════════════════
# ZONE A — INFRASTRUCTURE RULES
# Maintained by agent-infra. Do not edit unless you know what
# you're doing. Changes here affect every agent session.
# ═══════════════════════════════════════════════════════════════

## System identity
You are part of a multi-agent development system. You may be running as:
- ORCHESTRATOR — the top-level session the user chats with in VSCode
- CERIT WORKER — a bash-spawned session using the free CERIT endpoint
- INTERNAL SUBAGENT — spawned by either of the above via the Task tool

These infrastructure rules apply in all three roles.

## Multi-agent system overview

### Providers and cost model
- Anthropic (orchestrator): expensive — reserve for planning, decisions,
  PR review, architectural choices, and user communication
- CERIT (workers): free — use without restraint for all heavy work:
  coding, research, data processing, testing, git operations

### Available agents (defined in ~/.claude/agents/)
- cerit-coder: implements features on isolated branches, opens PRs
- cerit-researcher: deep web research, no token limits
- cerit-reviewer: code quality review, runs tests, read-only
- cerit-data: data processing, ML pipelines, dataset work
- deep-explorer: thorough codebase exploration (read-only subagent)
- test-verifier: runs test suite, returns pass/fail verdict

### Available scripts (in PATH via agent-infra)
- cerit-worker.sh <task_or_spec> <output> [branch]       — spawn a CERIT worker
- parallel-implement.sh "<task>" [branch] [n_workers]    — best-of-N with judge
- implement-and-refine.sh <task_or_spec> [branch] [rounds] — generator-evaluator loop
- librarian-retrieve.sh "<task>" <project>               — vault reading list briefing
- librarian-archive.sh <type> <file> <project>           — archive content to vault
- vault-health.sh [project]                              — weekly vault curation report
- send-report.py "subject" [file]                        — email progress report

### Available skills (in ~/.claude/skills/)
Skills are loaded on demand. Check ~/.claude/skills/README.md for the
current list. Use /skill-name to invoke. Key built-in skills:
- /parallel-implement — best-of-3 parallel coding with judge
- /implement-and-refine — generator-evaluator refinement loop

## Tool use doctrine — use the RIGHT tool, not the EASY tool

### Always explore before writing code
NEVER write code for a codebase you haven't read.
Use the Explore subagent (or deep-explorer) for:
- Finding all files relevant to a task
- Understanding how a module or subsystem works
- Discovering existing tests for the area you're touching
- Learning codebase patterns and conventions

Spawn Explore subagents IN PARALLEL when investigating multiple
independent areas. Do not read files sequentially in your main context.

### Mandatory work sequence for non-trivial tasks
1. EXPLORE  — use Explore/deep-explorer subagent(s)
2. PLAN     — write a numbered plan before acting
3. IMPLEMENT — delegate to subagents or CERIT workers
4. VERIFY   — use test-verifier subagent or bash
5. REPORT   — write structured result summary

### Subagent decomposition rules
Use subagents when a task has separable phases:
  Research     → Explore subagent (read-only, isolated context)
  Implementation → general-purpose subagent or CERIT worker
  Verification → test-verifier subagent
Do NOT run research + implementation + verification in your main context.

### CERIT worker dispatch (ORCHESTRATOR only)
Delegate via bash to CERIT for ANY of:
- Code files longer than ~30 lines
- Deep or exhaustive web research
- Running tests, linters, formatters
- Data processing / ML pipeline work
- Git operations (commit, push, PR creation)

Parallel dispatch — ALL conditions must be met:
  ✓ Tasks are independent with no shared state
  ✓ Clear file boundaries, no overlap
  ✓ Each task is fully self-contained

Sequential dispatch — if ANY is true:
  ✗ Tasks have dependencies (B needs A's output)
  ✗ Shared files or risk of merge conflict

### Parallel implementation pattern (ORCHESTRATOR only)
Use parallel-implement.sh when:
  ✓ Task > ~50 lines, approach is non-obvious, quality matters
Do NOT use for: obvious bug fixes, config changes, documentation

## Context discipline
- Grep for what you need; do not read entire large files
- Redirect verbose bash output to temp files and summarise
- Use subagents for work that produces long output
- Run /compact proactively at ~60% context usage — not reactively at 95%
- When compacting, ALWAYS include this in the compact instruction:
  "Preserve: (1) list of all files modified this session, (2) current task
  spec and acceptance criteria, (3) all test results seen so far, (4) any
  unresolved error messages, (5) all decisions made and why."

## Quality gates — enforced automatically
PostToolUse hooks run the project linter after every file write. You will
receive linting output as feedback — fix issues immediately, do not defer.
The Stop hook blocks session close if tests are failing. Fix failures before
attempting to stop. Do NOT use /clear to escape a failing test situation.

## Architecture discipline (ORCHESTRATOR role)
Before merging any PR from a CERIT worker: invoke the architecture-guardian
agent to check the changes against docs/adr/ Architecture Decision Records.
Do not merge PRs that violate recorded architectural decisions without
explicit user approval. When making significant architectural decisions,
write a new ADR to docs/adr/ immediately.

## Task specification (ORCHESTRATOR role)
For non-trivial tasks, write a task YAML spec to tasks/ before spawning
a worker. Use tasks/task-template.yaml as the template. Pass the spec
file path to cerit-worker.sh instead of an inline task string.
This ensures workers have acceptance criteria and constraints they can
verify against, not just a vague description.

## Second brain (vault)
Vault: $VAULT — run librarian-retrieve.sh before complex tasks
Read $VAULT/000-INDEX.md first whenever you need vault context.
After completing work: call librarian-archive.sh with a summary of what was done.

### Retriever
  BRIEFING=$(librarian-retrieve.sh "<task>" <project>)
  cat "$BRIEFING"   # read before starting

### Archivist (call after significant work)
  Create a brief markdown file with: what was done, decisions, results, failures.
  librarian-archive.sh worker-result /path/to/summary.md <project>

## Worker communication standard (WORKER/SUBAGENT role)
Write results to the output file specified in your task:
  STATUS:    done | failed | needs_review | needs_clarification
  BRANCH:    (branch name if code committed, else none)
  PR:        (PR URL if opened, else none)
  SUMMARY:   (3-5 sentences: what you did, key decisions made)
  ISSUES:    (anything unexpected or needing orchestrator attention)
  ARTEFACTS: (key files created/modified, test result summary)
  FAILED_APPROACHES: (what you tried that didn't work and why)
  NEXT:      (suggested next step for the orchestrator)


# ═══════════════════════════════════════════════════════════════
# ZONE B — USER CONFIGURATION
#
# Fill this section in for YOUR setup. The agent reads everything
# below as authoritative instruction. Be specific and concrete.
# This section is never overwritten by infrastructure updates.
#
# Tips:
#   - Keep total CLAUDE.md under ~250 lines (context budget)
#   - Prefer concrete facts over vague guidance
#   - Include things that would trip up a new collaborator
#   - Delete placeholder sections you don't need
# ═══════════════════════════════════════════════════════════════

## About me and my work
<!-- Who are you, what do you work on, what domains matter? -->
<!-- Example: PhD researcher in computational ecology. Primary languages: -->
<!-- Python, R. Work spans ML, GIS, HPC cluster (Metacentrum/CERIT). -->
[FILL IN: your role, research area, primary languages and tools]


## My infrastructure
<!-- Pod/server setup, GPU access, cluster details, key paths -->
<!-- Example: Remote dev pod via VSCode Remote SSH. GPU: A100 80GB. -->
<!-- Datasets at /data/. Training code at ~/projects/. -->
[FILL IN: your compute environment, key paths, GPU, cluster setup]


## Active projects
<!-- Brief list so the agent understands your current context -->
<!-- Add/remove as projects change. Keep to one line each. -->
<!-- Example: insect-detector — YOLO/DEIMv2 training optimisation -->
[FILL IN: project name — one sentence description]


## Communication preferences
<!-- How do you want the agent to behave? -->
<!-- Example: Be concise. Prefer bullet summaries over prose. -->
<!-- Warn me before running anything that modifies data. -->
[FILL IN: your preferences for tone, verbosity, caution level]


## Domain conventions and standards
<!-- Coding style, naming, testing requirements, banned practices -->
<!-- Example: Python with ruff formatting. Type hints required. -->
<!-- Tests with pytest. No bare except clauses. -->
[FILL IN: your coding standards and conventions]


## Known environment quirks
<!-- Things that trip people up in your specific setup -->
<!-- Example: PBS jobs need --mem=32gb minimum. -->
<!-- PostGIS uses EPSG:5514 not 4326 for Czech data. -->
[FILL IN: gotchas, environment-specific requirements]


## Vault project mapping
<!-- Which vault project name corresponds to which repo? -->
<!-- Used by librarian-retrieve.sh and librarian-archive.sh to find the right vault context. -->
<!-- Example: insect-detector → vault project "insect-detector" -->
[FILL IN: repo-name → vault-project-name mappings]
```

---

### `claude-config/agents/cerit-coder.md`

```yaml
---
name: cerit-coder
description: >
  Delegate here for ANY coding task: implementing features, writing scripts,
  fixing bugs, refactoring. Works on an isolated git branch and opens a PR.
  Use for tasks producing more than 30 lines of code. Free and unlimited tokens.
  CERIT-powered worker — spawned via bash, not native subagent.
tools: Bash
permissionMode: acceptEdits
---
To spawn this worker, call:
  bash ~/scripts/cerit-worker.sh "<exact task specification>" \
    /tmp/cerit-result-$(date +%s).md \
    feature/<short-branch-name>

Include in the task specification:
- Exact files to create or modify
- Expected behaviour and acceptance criteria
- Any relevant context (paste key snippets if needed)
- Where to write output files

Wait for the process to exit, then read the output file.
```

---

### `claude-config/agents/cerit-researcher.md`

```yaml
---
name: cerit-researcher
description: >
  Delegate for deep research tasks: finding documentation, surveying approaches,
  reading web pages exhaustively, summarising libraries or papers. Unlimited tokens.
  Use whenever thorough research is needed before making a decision. Free CERIT worker.
tools: Bash
---
Spawn with:
  bash ~/scripts/cerit-worker.sh "<research question>" \
    /tmp/cerit-research-$(date +%s).md

The researcher has WebSearch and WebFetch tools and will go deep.
Include in the task: what question to answer, what format to return results in,
and any specific sources to prioritise or avoid.
```

---

### `claude-config/agents/cerit-reviewer.md`

```yaml
---
name: cerit-reviewer
description: >
  Delegate for code review: checking quality, running tests, linting,
  checking a PR diff for bugs or issues. Read-only. Use after any
  implementation worker finishes. Free CERIT worker.
tools: Bash
---
Spawn with:
  bash ~/scripts/cerit-worker.sh \
    "Review PR #<number> or branch <name>. Run tests. Report issues." \
    /tmp/cerit-review-$(date +%s).md
```

---

### `claude-config/agents/cerit-data.md`

```yaml
---
name: cerit-data
description: >
  Delegate for data processing tasks: filtering datasets, combining sources,
  running ML preprocessing pipelines, computing statistics, generating hard
  negatives, annotating data. Unlimited compute. Free CERIT worker.
tools: Bash
---
Spawn with:
  bash ~/scripts/cerit-worker.sh "<data task specification>" \
    /tmp/cerit-data-$(date +%s).md

Include: input data paths, output paths, processing logic, acceptance criteria.
```

---

### `claude-config/agents/deep-explorer.md`

```yaml
---
name: deep-explorer
description: >
  Use for thorough codebase exploration before implementation. Reads files,
  searches patterns, maps dependencies. Returns a structured understanding
  report. Use when you need to understand a subsystem before touching it.
tools: Read, Glob, Grep, Bash
model: sonnet
permissionMode: readOnly
---
You are a codebase explorer. Your job is to understand, not to change.

When invoked, produce a structured report covering:
1. Relevant files and their purpose
2. Key functions/classes and what they do  
3. How data flows through the relevant subsystem
4. Existing tests for this area
5. Patterns and conventions you observe
6. Anything that might affect the implementation task

Be thorough. Read the actual code, not just filenames.
Your findings will guide the implementation agent — be precise.
```

---

### `claude-config/agents/test-verifier.md`

```yaml
---
name: test-verifier
description: >
  Use after any implementation to verify correctness. Runs tests, checks
  linting, reports failures with specific error messages. Use this instead
  of running tests in your main context to keep verbose output out of your window.
tools: Read, Bash, Glob
model: sonnet
---
You are a verification specialist. Your job is to confirm code works.

Steps:
1. Identify the test command from pyproject.toml / Makefile / package.json
2. Run the full test suite
3. Run linting if configured (ruff, flake8, mypy, eslint)
4. Report results clearly:
   - How many tests passed / failed
   - Exact error messages for any failures
   - Linting issues if any
5. If failures exist, read the failing test and relevant code, diagnose
   whether the issue is in the implementation or the test

Return a concise pass/fail verdict with specifics.
```

---

### `claude-config/agents/architecture-guardian.md`

```yaml
---
name: architecture-guardian
description: >
  Invoke before merging any PR from a CERIT worker. Reads docs/adr/
  Architecture Decision Records and checks whether the PR diff violates
  any recorded architectural decisions. Returns PASS or FAIL with
  specific violations. Use to prevent architectural drift in multi-agent
  codebases. Also use when evaluating a proposed design change.
tools: Read, Bash, Glob, Grep
model: sonnet
permissionMode: readOnly
---
You are an architecture guardian. Your job is to enforce recorded
architectural decisions and detect drift.

## Your process

1. Read all ADR files in docs/adr/ (glob for *.md files)
2. Read the PR diff: `git diff main...<branch>` or the diff provided
3. For each ADR, check whether the changes comply with the decision
4. Check for:
   - New dependencies not approved by any ADR
   - Patterns that contradict recorded architectural choices
   - Changes to files marked as "do not modify" in CLAUDE.md
   - API surface changes that violate interface contracts
   - Database/schema changes without migration strategy

## Output format

VERDICT: PASS | FAIL | WARN

VIOLATIONS:
- [ADR-XXX] <description of violation> in <file:line>
(empty if none)

WARNINGS:
- <concern that doesn't violate a decision but should be reviewed>
(empty if none)

SUMMARY: <2-3 sentences explaining the verdict>

RECOMMENDATION: approve | request-changes | needs-discussion
```

---

### `project-template/docs/adr/README.md`

```markdown
# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for this project.
ADRs are read by the architecture-guardian agent before every PR merge to
prevent architectural drift in multi-agent codebases.

## Format

Each ADR is a markdown file named `adr-NNN-short-title.md` where NNN is a
zero-padded sequential number (001, 002, etc.).

## Writing effective ADRs

An ADR must be machine-readable as well as human-readable. Write it so that
an LLM can definitively answer: "Does this code change comply with this decision?"

Good ADRs are:
- **Specific**: "All database queries go through the Repository layer" not "use clean architecture"
- **Checkable**: the guardian can look at code and say yes or no
- **Scoped**: one decision per ADR, not a bundle of principles
- **Consequential**: captures decisions that would be hard to reverse

## What to capture

- Module/layer boundaries and what can cross them
- Which libraries/frameworks are approved (and which are banned)
- Interface contracts between components
- Files or directories that must not be modified without explicit approval
- Performance constraints (e.g., "no synchronous database calls in request handlers")
- Security requirements (e.g., "all user input must be validated through pydantic")
```

---

### `project-template/docs/adr/adr-template.md`

```markdown
# ADR-NNN: [Short title]

**Date:** YYYY-MM-DD
**Status:** proposed | accepted | deprecated | superseded
**Supersedes:** (ADR number if applicable)

## Context

[What situation forced this decision? What was the problem?]

## Decision

[The decision made, stated clearly and specifically.]

**In concrete terms, this means:**
- [Specific rule 1 that code must follow]
- [Specific rule 2]
- [Files/modules affected]

## Enforcement

The architecture-guardian agent checks this by:
- [How to detect compliance: what to grep for, what patterns to look for]
- [What a violation looks like]

## Consequences

**Do:** [What is now allowed/required]
**Do not:** [What is now forbidden]

## Rationale

[Why this decision was made over the alternatives]
```

---

### `claude-config/skills/parallel-implement/SKILL.md`

```markdown
---
name: parallel-implement
description: >
  Use when a task would benefit from multiple independent implementations
  being compared. Spawns 3 CERIT workers on the same task in parallel,
  then a CERIT judge picks the best. All cost is CERIT (free).
  Best for: complex algorithms, data pipelines, anything where approach
  matters and you want the best solution rather than the first solution.
---

# Parallel Implementation with Judge

Invoke by running:
  bash ~/scripts/parallel-implement.sh "<task>" <base-branch>

The task description must be self-contained — workers get no other context.
Always include in the task:
- What to implement (specific and precise)
- Where in the codebase (specific files/modules)
- Acceptance criteria (what does "correct" mean?)
- Any constraints (performance, API compatibility, style)

Wait for the script to complete. It takes 2-5x longer than a single
implementation but produces significantly better results for complex tasks.

Read the judge verdict when done and report the winner and scores to the user.

## When to use
- Task is non-trivial (>50 lines of new code expected)
- The approach or algorithm is not obvious
- Quality matters more than speed
- Core logic: data processing, training steps, API design

## When NOT to use
- Simple bug fixes with an obvious solution
- Configuration changes, documentation
- Anything touching shared state workers would conflict on
- Tasks where "correct" has only one obvious shape
```

---

### `claude-config/skills/implement-and-refine/SKILL.md`

```markdown
---
name: implement-and-refine
description: >
  Generator-evaluator loop: one CERIT worker implements, a second reviews
  against acceptance criteria, the first revises, repeat until quality bar
  is met or max rounds reached. Use for iterative refinement tasks where
  quality matters more than diversity of approaches. Complementary to
  parallel-implement: use this for refinement, use parallel-implement for
  approach diversity.
---

# Implement and Refine

Invoke by running:
  bash implement-and-refine.sh <task_spec_or_string> [branch] [max_rounds]

Default max_rounds: 3. Each round costs ~2x a single implementation.
The loop stops when the evaluator returns PASS or max_rounds is reached.

## When to use (vs parallel-implement)
- **implement-and-refine**: task has clear acceptance criteria, approach is
  known, quality/correctness is the goal. Best for bug fixes, well-specified
  features, and anything with measurable success criteria.
- **parallel-implement**: approach is non-obvious, want diversity of solutions,
  willing to trade time for choosing the best approach.

## When NOT to use
- Tasks without clear acceptance criteria (evaluator can't give useful feedback)
- Simple tasks where a single well-specified implementation is sufficient
- Tasks already using parallel-implement (don't double-nest these patterns)
```

---

### `scripts/implement-and-refine.sh`

```bash
#!/bin/bash
# Generator-Evaluator Refinement Loop
# Usage: implement-and-refine.sh <task_spec_or_string> [branch] [max_rounds]
#
# Round 1: CERIT implementer writes the code
# Round N: CERIT evaluator reviews against acceptance criteria, outputs PASS or critique
# Round N+1: CERIT implementer reads critique and revises
# Stops when evaluator returns PASS or max_rounds is hit.

set -euo pipefail

TASK_INPUT="$1"
BRANCH="${2:-}"
MAX_ROUNDS="${3:-3}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULTS_DIR=$(mktemp -d /tmp/refine-XXXXXX)
ROUND=0
LAST_CRITIQUE=""

echo "================================================================"
echo "Implement-and-Refine — $TIMESTAMP"
echo "Max rounds: $MAX_ROUNDS"
echo "Results: $RESULTS_DIR"
echo "================================================================"

# Helper: spawn a CERIT implementer
run_implementer() {
  local ROUND=$1
  local CRITIQUE_FILE="${2:-}"
  local OUTPUT="$RESULTS_DIR/impl-round-${ROUND}.md"
  local LOG="${HOME}/logs/refine-impl-${TIMESTAMP}-r${ROUND}.log"
  local TASK_FILE=$(mktemp /tmp/refine-impl-XXXXXX.md)

  cat > "$TASK_FILE" << TASKEOF
# Implementation Task — Round $ROUND of $MAX_ROUNDS
# Timestamp: $TIMESTAMP

## Task
$TASK_INPUT

$([ -n "$CRITIQUE_FILE" ] && [ -f "$CRITIQUE_FILE" ] && echo "## Evaluator critique from previous round (address ALL points)
$(cat "$CRITIQUE_FILE")

IMPORTANT: Do not just acknowledge the critique — actually fix each issue.")
$([ "$ROUND" -gt 1 ] && echo "Previous implementation: $RESULTS_DIR/impl-round-$((ROUND-1)).md
Read it before revising so you understand what was already done.")

## Requirements
- Implement or revise to address all acceptance criteria and constraints
- Run tests and verify they pass before writing your result
$([ -n "$BRANCH" ] && echo "- Work on branch: $BRANCH")

## Output
Write result to: $OUTPUT
Use format: STATUS / SUMMARY / ARTEFACTS / TEST_RESULT / REMAINING_ISSUES
TASKEOF

  echo "[refine] Round $ROUND — implementer starting..."

  ANTHROPIC_BASE_URL="${CERIT_BASE_URL}"   ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}"   ANTHROPIC_MODEL="${CERIT_CODER_MODEL}"   ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}"   ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_CODER_MODEL}"   ANTHROPIC_DEFAULT_HAIKU_MODEL="${CERIT_FAST_MODEL}"   CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1   claude -p "$(cat "$TASK_FILE")"     --allowedTools "Read,Edit,Write,Bash,Glob,Grep"     --max-turns 60     --dangerously-skip-permissions     --output-format text     >> "$LOG" 2>&1

  rm -f "$TASK_FILE"
  echo "[refine] Round $ROUND implementer done. Output: $OUTPUT"
  echo "$OUTPUT"
}

# Helper: spawn a CERIT evaluator
run_evaluator() {
  local ROUND=$1
  local IMPL_FILE="$2"
  local OUTPUT="$RESULTS_DIR/eval-round-${ROUND}.md"
  local LOG="${HOME}/logs/refine-eval-${TIMESTAMP}-r${ROUND}.log"
  local TASK_FILE=$(mktemp /tmp/refine-eval-XXXXXX.md)

  cat > "$TASK_FILE" << TASKEOF
# Evaluation Task — Round $ROUND
# Timestamp: $TIMESTAMP

## Original task and requirements
$TASK_INPUT

## Implementer's report
$(cat "$IMPL_FILE" 2>/dev/null || echo "(no output)")

## Your job
Evaluate the implementation rigorously against the acceptance criteria and constraints.
Read the actual code files (not just the report) before making your verdict.

Evaluation criteria:
1. Does it meet every acceptance criterion? (check each one explicitly)
2. Does it violate any constraints?
3. Do the tests actually pass? (run them yourself if not clear from the report)
4. Code quality: readable, maintainable, follows project conventions?
5. Are there edge cases not handled?

## Output (write to $OUTPUT)
VERDICT: PASS | FAIL

If PASS:
VERDICT: PASS
SUMMARY: (what was implemented and why it meets the bar)

If FAIL:
VERDICT: FAIL
ISSUES:
- Issue 1: [specific, actionable — what file/function, what's wrong, how to fix]
- Issue 2: [...]
PRIORITY: (which issues are blocking vs nice-to-have)
TASKEOF

  echo "[refine] Round $ROUND — evaluator starting..."

  # Evaluator uses thinker model — needs good judgment
  ANTHROPIC_BASE_URL="${CERIT_BASE_URL}"   ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}"   ANTHROPIC_MODEL="${CERIT_THINKER_MODEL}"   ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}"   ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_CODER_MODEL}"   ANTHROPIC_DEFAULT_HAIKU_MODEL="${CERIT_FAST_MODEL}"   CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1   claude -p "$(cat "$TASK_FILE")"     --allowedTools "Read,Bash,Glob,Grep"     --max-turns 25     --dangerously-skip-permissions     --output-format text     >> "$LOG" 2>&1

  rm -f "$TASK_FILE"
  echo "[refine] Round $ROUND evaluator done. Output: $OUTPUT"
  echo "$OUTPUT"
}

# ── Main refinement loop ──────────────────────────────────────────────────────

CRITIQUE_FILE=""
FINAL_STATUS="failed"

for ROUND_NUM in $(seq 1 $MAX_ROUNDS); do
  echo ""
  echo "--- Round $ROUND_NUM of $MAX_ROUNDS ---"

  # Implementer
  IMPL_OUT=$(run_implementer "$ROUND_NUM" "$CRITIQUE_FILE")

  if [ ! -s "$IMPL_OUT" ]; then
    echo "[refine] ERROR: implementer produced no output in round $ROUND_NUM"
    break
  fi

  # Evaluator
  EVAL_OUT=$(run_evaluator "$ROUND_NUM" "$IMPL_OUT")

  if [ ! -s "$EVAL_OUT" ]; then
    echo "[refine] WARNING: evaluator produced no output in round $ROUND_NUM"
    break
  fi

  # Check verdict
  VERDICT=$(grep "^VERDICT:" "$EVAL_OUT" | head -1 | awk '{print $2}')
  echo "[refine] Round $ROUND_NUM verdict: $VERDICT"

  if [ "$VERDICT" = "PASS" ]; then
    echo ""
    echo "================================================================"
    echo "PASS achieved in round $ROUND_NUM"
    echo "================================================================"
    cat "$EVAL_OUT"
    FINAL_STATUS="done"
    break
  fi

  # FAIL — prepare for next round
  CRITIQUE_FILE="$EVAL_OUT"

  if [ "$ROUND_NUM" -eq "$MAX_ROUNDS" ]; then
    echo ""
    echo "================================================================"
    echo "Max rounds reached without PASS. Last evaluation:"
    echo "================================================================"
    cat "$EVAL_OUT"
    FINAL_STATUS="needs_review"
  fi
done

echo ""
echo "================================================================"
echo "Implement-and-refine complete"
echo "Final status: $FINAL_STATUS"
echo "Rounds completed: $ROUND_NUM"
echo "Results: $RESULTS_DIR"
echo "================================================================"

# Archive to vault if available
if [ "$FINAL_STATUS" != "failed" ] && command -v librarian-archive.sh &>/dev/null; then
  ARCHIVE_FILE=$(mktemp /tmp/refine-archive-XXXXXX.md)
  cat > "$ARCHIVE_FILE" << ARCHEOF
# Implement-and-Refine Session — $TIMESTAMP
Rounds: $ROUND_NUM / $MAX_ROUNDS
Final status: $FINAL_STATUS
Task: $TASK_INPUT
Results dir: $RESULTS_DIR
ARCHEOF
  librarian-archive.sh worker-result "$ARCHIVE_FILE" "general" &
  rm -f "$ARCHIVE_FILE"
fi
```

---

### `scripts/cerit-worker.sh`

```bash
#!/bin/bash
# CERIT Worker Spawner
# Usage: cerit-worker.sh <task_or_spec_file> <output_file> [branch_name] [max_turns]
#
# <task_or_spec_file> can be:
#   - A path to a task YAML spec file (tasks/task-NNN.yaml) — PREFERRED
#   - An inline task description string (legacy, still supported)
#
# Spawns a Claude Code process pointed at the CERIT OpenAI-compatible endpoint.
# The worker reads its task spec, does the work, and writes a structured result.

set -euo pipefail

TASK_INPUT="$1"
OUTPUT_FILE="$2"
BRANCH="${3:-}"
MAX_TURNS="${4:-80}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TASK_FILE=$(mktemp /tmp/cerit-task-XXXXXX.md)

# ── Parse task input: YAML spec file or inline string ─────────────────────────
if [ -f "$TASK_INPUT" ] && (echo "$TASK_INPUT" | grep -qE '\.(yaml|yml)$'); then
  # YAML spec file — parse and format into task markdown
  SPEC_FILE="$TASK_INPUT"
  SPEC_CONTENT=$(cat "$SPEC_FILE")
  
  # Extract fields from YAML (simple grep-based parsing)
  TASK_TITLE=$(grep '^title:' "$SPEC_FILE" | sed 's/title: *//' | tr -d '"')
  TASK_TYPE=$(grep '^type:' "$SPEC_FILE" | sed 's/type: *//')
  TASK_TURNS=$(grep '^estimated_turns:' "$SPEC_FILE" | sed 's/estimated_turns: *//')
  VAULT_PROJECT=$(grep 'vault_project:' "$SPEC_FILE" | head -1 | sed 's/.*vault_project: *//')
  
  # Use estimated_turns from spec if larger than default
  if [ -n "$TASK_TURNS" ] && [ "$TASK_TURNS" -gt "$MAX_TURNS" ] 2>/dev/null; then
    MAX_TURNS=$TASK_TURNS
  fi
  
  # Auto-fetch vault briefing if vault_project is specified
  BRIEFING_CONTENT=""
  if [ -n "$VAULT_PROJECT" ] && [ -n "${VAULT:-}" ] && command -v librarian-retrieve.sh &>/dev/null; then
    echo "[cerit-worker] Fetching vault briefing for project: $VAULT_PROJECT"
    BRIEFING_PATH=$(librarian-retrieve.sh "$TASK_TITLE" "$VAULT_PROJECT" 2>/dev/null || true)
    if [ -n "$BRIEFING_PATH" ] && [ -f "$BRIEFING_PATH" ]; then
      BRIEFING_CONTENT="$(cat "$BRIEFING_PATH")"
      echo "[cerit-worker] Vault briefing loaded: $BRIEFING_PATH"
    fi
  fi
  
  cat > "$TASK_FILE" << TASKEOF
# Worker Task — $TIMESTAMP
# Spec: $SPEC_FILE

## Task specification
\`\`\`yaml
$SPEC_CONTENT
\`\`\`

## Your assignment
$TASK_TITLE (type: $TASK_TYPE)

$([ -n "$BRIEFING_CONTENT" ] && echo "## Vault context (read these files first)
$BRIEFING_CONTENT
")
TASKEOF

else
  # Inline task string (legacy mode)
  TASK="$TASK_INPUT"
  cat > "$TASK_FILE" << TASKEOF
# Worker Task — $TIMESTAMP

## Your assignment
$TASK

## Mandatory workflow — follow this sequence exactly

### Step 1: Explore before acting
Before writing a single line of code, use the Explore subagent to understand
the relevant codebase areas. Specifically:
- What files are relevant to this task?
- What existing code already does related things?
- What patterns does this codebase use (naming, structure, testing)?
- Are there existing tests for the area you're touching?

Spawn Explore subagents IN PARALLEL if you need to understand multiple
independent areas. Do not read files one by one in your main context.

### Step 2: Plan explicitly
Write a brief numbered plan before implementing anything.
State what you will create/modify and why.

### Step 3: Implement
Write the code. Use subagents for self-contained sub-tasks where helpful.
$(if [ -n "$BRANCH" ]; then echo "Work on branch: $BRANCH (create from main if needed: git checkout -b $BRANCH)"; fi)

### Step 4: Verify
Run the test suite. Run linting if configured. Fix failures before continuing.
A task is NOT done until tests pass. Use the test-verifier subagent or run
tests directly via bash.

### Step 5: Commit and report
$(if [ -n "$BRANCH" ]; then echo "git add -A && git commit -m '<clear message describing what you built>'
git push -u origin $BRANCH
gh pr create --fill --base main"; fi)
Write your result to: $OUTPUT_FILE

## Context budget reminder
You have a finite context window. Protect it:
- Use Explore subagents for discovery (their output stays out of your context)
- Redirect verbose bash output to temp files, summarise key parts
- Stop reading when you understand enough

## Output format (write to $OUTPUT_FILE when done)
STATUS: done|failed|needs_review|needs_clarification
BRANCH: $BRANCH
PR: (URL if opened, else none)
SUMMARY: (3-5 sentences: what you built/changed, key decisions made)
ISSUES: (anything unexpected or requiring orchestrator attention)
ARTEFACTS: (key files created or modified, test results summary)
NEXT: (what should happen next)
TASKEOF

# Append git instructions if branch specified
if [ -n "$BRANCH" ]; then
  cat >> "$TASK_FILE" << GITEOF

## Git context
- Base branch: main (or whatever the default branch is)
- Your branch: $BRANCH
- Create it fresh: git checkout -b $BRANCH
- After work: git add -A && git commit && git push && gh pr create --fill --base main
GITEOF
fi

echo "[cerit-worker] Starting task at $TIMESTAMP"
echo "[cerit-worker] Output: $OUTPUT_FILE"
echo "[cerit-worker] Branch: ${BRANCH:-none}"

ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" \
ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" \
ANTHROPIC_MODEL="${CERIT_CODER_MODEL}" \
ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" \
ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_CODER_MODEL}" \
ANTHROPIC_DEFAULT_HAIKU_MODEL="${CERIT_FAST_MODEL}" \
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
claude -p "$(cat "$TASK_FILE")" \
  --allowedTools "Read,Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch" \
  --max-turns "$MAX_TURNS" \
  --dangerously-skip-permissions \
  --output-format text \
  2>&1 | tee -a "${HOME}/logs/cerit-workers.log"

EXIT_CODE=${PIPESTATUS[0]}

rm -f "$TASK_FILE"

if [ $EXIT_CODE -ne 0 ]; then
  echo "STATUS: failed" >> "$OUTPUT_FILE"
  echo "SUMMARY: Worker process exited with code $EXIT_CODE" >> "$OUTPUT_FILE"
  echo "ISSUES: Check ${HOME}/logs/cerit-workers.log for details" >> "$OUTPUT_FILE"
fi

echo "[cerit-worker] Done (exit $EXIT_CODE). Output at: $OUTPUT_FILE"
exit $EXIT_CODE
```

---

### `scripts/parallel-implement.sh`

This is the best-of-3 pattern with a judge. Implements robust cleanup for failed workers.

```bash
#!/bin/bash
# Parallel Implementation with Judge
# Usage: parallel-implement.sh "<task description>" [base_branch] [n_workers]
#
# Spawns N CERIT workers implementing the same task independently in isolated
# git worktrees, then spawns a CERIT judge to pick the best implementation.
# The winner is squash-merged to base_branch. Losers are cleaned up.

set -euo pipefail

TASK="$1"
BASE_BRANCH="${2:-main}"
N_WORKERS="${3:-3}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
RESULTS_DIR=$(mktemp -d /tmp/parallel-impl-XXXXXX)
WORKTREES_DIR="$REPO_ROOT/.claude/worktrees"

mkdir -p "$WORKTREES_DIR"
mkdir -p "${HOME}/logs"

echo "================================================================"
echo "Parallel Implementation — $TIMESTAMP"
echo "Task: $TASK"
echo "Base branch: $BASE_BRANCH"
echo "Workers: $N_WORKERS"
echo "Results dir: $RESULTS_DIR"
echo "================================================================"

# Track all worktrees and PIDs for cleanup
declare -a WORKER_PIDS=()
declare -a WORKER_BRANCHES=()
declare -a WORKER_WORKTREES=()

# ── Cleanup function — always runs on exit ──────────────────────────────────
cleanup_failed_workers() {
  local WINNER_BRANCH="${1:-}"
  echo ""
  echo "[cleanup] Removing failed/losing worktrees and branches..."

  for i in "${!WORKER_BRANCHES[@]}"; do
    local BRANCH="${WORKER_BRANCHES[$i]}"
    local WORKTREE="${WORKER_WORKTREES[$i]}"

    # Skip the winner
    if [ -n "$WINNER_BRANCH" ] && [ "$BRANCH" = "$WINNER_BRANCH" ]; then
      echo "[cleanup] Keeping winner: $BRANCH"
      continue
    fi

    # Remove worktree
    if [ -d "$WORKTREE" ]; then
      git worktree remove "$WORKTREE" --force 2>/dev/null && \
        echo "[cleanup] Removed worktree: $WORKTREE" || \
        echo "[cleanup] WARNING: Could not remove worktree: $WORKTREE"
    fi

    # Delete branch
    if git branch --list "$BRANCH" | grep -q "$BRANCH"; then
      git branch -D "$BRANCH" 2>/dev/null && \
        echo "[cleanup] Deleted branch: $BRANCH" || \
        echo "[cleanup] WARNING: Could not delete branch: $BRANCH"
    fi
  done

  echo "[cleanup] Done"
}

# ── Emergency cleanup on script error ──────────────────────────────────────
emergency_cleanup() {
  echo ""
  echo "[emergency] Script failed. Cleaning up all worktrees..."
  cleanup_failed_workers ""
  echo "[emergency] Results preserved at: $RESULTS_DIR"
  echo "[emergency] Logs at: ${HOME}/logs/cerit-workers.log"
  exit 1
}
trap emergency_cleanup ERR

# ── Phase 1: Spawn N workers in parallel ───────────────────────────────────

spawn_worker() {
  local WORKER_ID=$1
  local BRANCH="impl/${TIMESTAMP}-attempt-${WORKER_ID}"
  local OUTPUT="$RESULTS_DIR/worker-${WORKER_ID}.md"
  local WORKTREE="$WORKTREES_DIR/${TIMESTAMP}-attempt-${WORKER_ID}"
  local LOG="${HOME}/logs/cerit-worker-${TIMESTAMP}-${WORKER_ID}.log"

  # Register for cleanup
  WORKER_BRANCHES[$WORKER_ID]="$BRANCH"
  WORKER_WORKTREES[$WORKER_ID]="$WORKTREE"

  echo "[worker-$WORKER_ID] Setting up worktree: $WORKTREE"

  # Create isolated worktree on a fresh branch
  if ! git worktree add "$WORKTREE" -b "$BRANCH" "$BASE_BRANCH" 2>/dev/null; then
    echo "STATUS: failed" > "$OUTPUT"
    echo "SUMMARY: Failed to create git worktree for attempt $WORKER_ID" >> "$OUTPUT"
    echo "ISSUES: Git worktree creation failed. Check if branch $BRANCH already exists." >> "$OUTPUT"
    echo "[worker-$WORKER_ID] FAILED to create worktree"
    echo $$ # return current PID as placeholder — wait will handle it
    return 1
  fi

  local TASK_FILE=$(mktemp /tmp/cerit-task-XXXXXX.md)
  cat > "$TASK_FILE" << TASKEOF
# Parallel Implementation Task — Attempt $WORKER_ID of $N_WORKERS
# Run: $TIMESTAMP

## Context
You are one of $N_WORKERS agents implementing the SAME task independently.
Your implementation will be judged against the others on:
- Correctness (tests pass, task fully solved)
- Code quality (readable, maintainable, follows codebase conventions)
- Robustness (edge cases handled, error handling)
- Elegance (appropriately simple or appropriately thorough)

Write the BEST code you can. Be creative where appropriate. Don't be
conservative just to be safe — make real design decisions.

## Task
$TASK

## Your workspace
Working directory: $WORKTREE
Branch: $BRANCH
Base branch: $BASE_BRANCH

## Mandatory workflow
1. EXPLORE: Use Explore subagent to understand relevant codebase areas first.
   Spawn multiple Explore subagents in parallel if investigating multiple areas.
2. PLAN: Write a numbered plan before implementing.
3. IMPLEMENT: Write the code. Make conscious design decisions.
4. VERIFY: Run the test suite. Fix failures. Tests MUST pass.
5. COMMIT: git add -A && git commit -m "attempt-$WORKER_ID: <description>"
6. REPORT: Write your result to $OUTPUT

## Output format (required, write to $OUTPUT)
STATUS: done|failed
BRANCH: $BRANCH
APPROACH: (2-3 sentences describing your KEY design decisions and WHY)
TRADEOFFS: (what you prioritised, what you consciously sacrificed)
TEST_RESULT: (pass/fail — include number of tests run)
CONFIDENCE: high|medium|low
SUMMARY: (what you built in plain language)
TASKEOF

  echo "[worker-$WORKER_ID] Spawning CERIT process..."

  # Run CERIT worker in background subshell
  (
    cd "$WORKTREE"
    ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" \
    ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" \
    ANTHROPIC_MODEL="${CERIT_CODER_MODEL}" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_CODER_MODEL}" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="${CERIT_FAST_MODEL}" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    claude -p "$(cat "$TASK_FILE")" \
      --allowedTools "Read,Edit,Write,Bash,Glob,Grep" \
      --max-turns 80 \
      --dangerously-skip-permissions \
      --output-format text \
      >> "$LOG" 2>&1

    WORKER_EXIT=$?

    # Write failure report if worker didn't write its own
    if [ ! -s "$OUTPUT" ]; then
      cat > "$OUTPUT" << FAILEOF
STATUS: failed
BRANCH: $BRANCH
APPROACH: Worker failed to complete
TRADEOFFS: N/A
TEST_RESULT: N/A
CONFIDENCE: low
SUMMARY: Worker process did not produce output. Exit code: $WORKER_EXIT. Check log: $LOG
FAILEOF
    fi

    # Append exit code marker
    echo "" >> "$OUTPUT"
    echo "EXIT_CODE: $WORKER_EXIT" >> "$OUTPUT"

  ) &

  local WORKER_PID=$!
  rm -f "$TASK_FILE"
  echo "[worker-$WORKER_ID] Running as PID $WORKER_PID on branch $BRANCH"
  echo $WORKER_PID
}

# Spawn all workers and collect PIDs
echo ""
echo "--- Spawning $N_WORKERS workers in parallel ---"
for i in $(seq 1 $N_WORKERS); do
  PID=$(spawn_worker $i)
  WORKER_PIDS[$i]=$PID
  echo "[coordinator] Worker $i PID: $PID"
done

# Wait for all workers, collect exit codes
echo ""
echo "--- Waiting for all workers to complete ---"
declare -a WORKER_EXIT_CODES=()
declare -a SUCCESSFUL_WORKERS=()

for i in $(seq 1 $N_WORKERS); do
  echo -n "[coordinator] Waiting for worker $i (PID ${WORKER_PIDS[$i]})... "
  if wait "${WORKER_PIDS[$i]}"; then
    echo "OK"
    WORKER_EXIT_CODES[$i]=0
    SUCCESSFUL_WORKERS+=($i)
  else
    EXIT_CODE=$?
    echo "FAILED (exit $EXIT_CODE)"
    WORKER_EXIT_CODES[$i]=$EXIT_CODE
  fi
done

echo ""
echo "--- Worker summary ---"
for i in $(seq 1 $N_WORKERS); do
  STATUS_LINE=$(grep "^STATUS:" "$RESULTS_DIR/worker-${i}.md" 2>/dev/null || echo "STATUS: no output")
  echo "Worker $i: $STATUS_LINE (process exit: ${WORKER_EXIT_CODES[$i]:-unknown})"
done

# Check if we have enough successful workers to proceed
N_SUCCESSFUL=${#SUCCESSFUL_WORKERS[@]}
echo ""
echo "$N_SUCCESSFUL of $N_WORKERS workers completed successfully."

if [ $N_SUCCESSFUL -eq 0 ]; then
  echo "ERROR: All workers failed. Cannot proceed to judge phase."
  echo "Check logs in: ${HOME}/logs/"
  cleanup_failed_workers ""
  exit 1
fi

if [ $N_SUCCESSFUL -eq 1 ]; then
  echo "WARNING: Only 1 worker succeeded. Judge will still evaluate but has only one option."
fi

# ── Phase 2: Spawn CERIT judge ──────────────────────────────────────────────
echo ""
echo "--- Spawning judge ---"

JUDGE_OUTPUT="$RESULTS_DIR/judge-verdict.md"
JUDGE_LOG="${HOME}/logs/cerit-judge-${TIMESTAMP}.log"
JUDGE_TASK=$(mktemp /tmp/cerit-judge-XXXXXX.md)

# Build worker reports section dynamically
WORKER_REPORTS=""
for i in $(seq 1 $N_WORKERS); do
  WORKER_REPORTS+="### Worker $i (branch: ${WORKER_BRANCHES[$i]:-unknown})\n"
  if [ -s "$RESULTS_DIR/worker-${i}.md" ]; then
    WORKER_REPORTS+="$(cat "$RESULTS_DIR/worker-${i}.md")\n\n"
  else
    WORKER_REPORTS+="No output produced.\n\n"
  fi
done

# Build worktree paths section
WORKTREE_PATHS=""
for i in $(seq 1 $N_WORKERS); do
  if [ -d "${WORKER_WORKTREES[$i]:-}" ]; then
    STATUS=$(grep "^STATUS:" "$RESULTS_DIR/worker-${i}.md" 2>/dev/null | head -1 || echo "STATUS: unknown")
    WORKTREE_PATHS+="- Worker $i: ${WORKER_WORKTREES[$i]} ($STATUS)\n"
  fi
done

cat > "$JUDGE_TASK" << JUDGEEOF
# Judge Task — Parallel Implementation Evaluation
# Run: $TIMESTAMP

## Your role
You are a senior code reviewer. Three agents implemented the same task
independently. You must evaluate all implementations and select the best one.
Be rigorous and objective. The orchestrator will merge your winner.

## Original task
$TASK

## Worker self-reports
$(echo -e "$WORKER_REPORTS")

## Worktrees to examine (read the ACTUAL CODE)
$(echo -e "$WORKTREE_PATHS")

## Your evaluation process

### Step 1: Read all implementations
For each worktree that has STATUS: done, read the actual code files.
Do NOT rely solely on worker self-reports — they may be inaccurate.
Use Glob and Read tools to find and read the relevant files in each worktree.

### Step 2: Run each implementation's tests
For each successful implementation, cd to its worktree and run the test suite.
Note actual pass/fail counts (workers may have been optimistic in self-reports).

### Step 3: Evaluate each on these criteria (score 1-10 each)
- Correctness: does it actually solve the task fully and correctly?
- Code quality: readable, maintainable, follows codebase conventions?
- Test coverage: are tests thorough and meaningful?
- Robustness: are edge cases handled? Error paths?
- Elegance: appropriately simple or appropriately thorough?

### Step 4: Pick the winner
Consider overall quality across all criteria, with correctness weighted highest.

Write your verdict to: $JUDGE_OUTPUT

## Output format (required, write to $JUDGE_OUTPUT)
WINNER: attempt-<N>
WINNER_BRANCH: ${TIMESTAMP}-... (exact branch name)
SCORES:
  attempt-1: <X>/10 — <one sentence reason>
  attempt-2: <X>/10 — <one sentence reason>
  attempt-3: <X>/10 — <one sentence reason>
RATIONALE: (2-4 sentences explaining why the winner is best)
IMPROVEMENTS: (specific things the orchestrator should ask the winner to fix, if any)
FAILED_WORKERS: (list any workers that failed or had test failures)
JUDGEEOF

# Judge uses thinker model — picking the best implementation requires real reasoning
ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" \
ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" \
ANTHROPIC_MODEL="${CERIT_THINKER_MODEL}" \
ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" \
ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_CODER_MODEL}" \
ANTHROPIC_DEFAULT_HAIKU_MODEL="${CERIT_FAST_MODEL}" \
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
claude -p "$(cat "$JUDGE_TASK")" \
  --allowedTools "Read,Glob,Grep,Bash" \
  --max-turns 40 \
  --dangerously-skip-permissions \
  --output-format text \
  > "$JUDGE_LOG" 2>&1

JUDGE_EXIT=$?
rm -f "$JUDGE_TASK"

if [ $JUDGE_EXIT -ne 0 ] || [ ! -s "$JUDGE_OUTPUT" ]; then
  echo "ERROR: Judge failed (exit $JUDGE_EXIT) or produced no output."
  echo "All worktrees preserved for manual review."
  echo "Worktrees: $WORKTREES_DIR"
  echo "Results: $RESULTS_DIR"
  exit 1
fi

# ── Phase 3: Apply winner ───────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "JUDGE VERDICT"
echo "================================================================"
cat "$JUDGE_OUTPUT"
echo "================================================================"

# Extract winner information
WINNER_ATTEMPT=$(grep "^WINNER:" "$JUDGE_OUTPUT" | head -1 | grep -oP 'attempt-\K\d+' || echo "")
WINNER_BRANCH=$(grep "^WINNER_BRANCH:" "$JUDGE_OUTPUT" | head -1 | awk '{print $2}' || echo "")

# Validate winner
if [ -z "$WINNER_ATTEMPT" ] || [ -z "$WINNER_BRANCH" ]; then
  echo "WARNING: Could not parse winner from judge output."
  echo "Manual review required. All worktrees preserved:"
  for i in $(seq 1 $N_WORKERS); do
    echo "  Worker $i: ${WORKER_WORKTREES[$i]:-unknown}"
  done
  echo "Results: $RESULTS_DIR"
  exit 1
fi

# Verify winner branch actually has commits
WINNER_WORKTREE="${WORKER_WORKTREES[$WINNER_ATTEMPT]:-}"
if [ ! -d "$WINNER_WORKTREE" ]; then
  echo "ERROR: Winner worktree not found: $WINNER_WORKTREE"
  echo "Manual review required."
  exit 1
fi

echo ""
echo "Merging winner (attempt-$WINNER_ATTEMPT, branch: $WINNER_BRANCH) into $BASE_BRANCH..."

git checkout "$BASE_BRANCH"

# Get rationale for commit message
RATIONALE=$(grep "^RATIONALE:" "$JUDGE_OUTPUT" | sed 's/^RATIONALE: //' || echo "Best of $N_WORKERS parallel implementations")

git merge --squash "$WINNER_BRANCH" 2>/dev/null || {
  echo "ERROR: Squash merge failed. This may mean the winner had no commits."
  echo "Attempting regular merge..."
  git merge "$WINNER_BRANCH" --no-ff -m "feat: parallel impl winner (attempt-$WINNER_ATTEMPT) from $TIMESTAMP" || {
    echo "ERROR: Merge failed entirely. Manual intervention required."
    git merge --abort 2>/dev/null || true
    echo "Winner branch preserved: $WINNER_BRANCH"
    echo "Worktree: $WINNER_WORKTREE"
    exit 1
  }
}

git commit -m "feat: parallel impl winner (attempt-$WINNER_ATTEMPT) from $TIMESTAMP

Task: $TASK

$RATIONALE

Parallel run: $RESULTS_DIR/judge-verdict.md" 2>/dev/null || {
  echo "NOTE: Nothing to commit — winner may have had no changes, or changes already merged."
}

# Clean up losing worktrees and branches
echo ""
echo "Cleaning up losing implementations..."
cleanup_failed_workers "impl/${TIMESTAMP}-attempt-${WINNER_ATTEMPT}"

# Clean up winner worktree too (changes are now in base branch)
if [ -d "$WINNER_WORKTREE" ]; then
  git worktree remove "$WINNER_WORKTREE" --force 2>/dev/null && \
    echo "[cleanup] Removed winner worktree (changes merged)" || \
    echo "[cleanup] WARNING: Could not remove winner worktree: $WINNER_WORKTREE"
fi

# Archive results
echo ""
echo "================================================================"
echo "COMPLETE"
echo "================================================================"
echo "Winner: attempt-$WINNER_ATTEMPT merged into $BASE_BRANCH"
echo "Results archived: $RESULTS_DIR"
echo "Judge verdict: $RESULTS_DIR/judge-verdict.md"
echo ""

# Print improvements if any
IMPROVEMENTS=$(grep -A5 "^IMPROVEMENTS:" "$JUDGE_OUTPUT" || echo "")
if [ -n "$IMPROVEMENTS" ] && ! echo "$IMPROVEMENTS" | grep -qi "none\|n/a\|no improvements"; then
  echo "⚠️  Judge recommends follow-up improvements:"
  echo "$IMPROVEMENTS"
  echo ""
fi

echo "Done."
```

---

---

### `scripts/send-report.py`

```python
#!/usr/bin/env python3
"""
Agent email reporter.
Usage: echo "report content" | python send-report.py "Subject"
   or: python send-report.py "Subject" report_content.txt
"""
import sys
import os
import smtplib
import argparse
from email.mime.text import MIMEText
from datetime import datetime

def send_report(subject: str, body: str, to_addr: str, from_addr: str, smtp_host: str, smtp_port: int):
    msg = MIMEText(body, 'plain', 'utf-8')
    msg['Subject'] = f"[Agent] {subject} — {datetime.now().strftime('%Y-%m-%d %H:%M')}"
    msg['From'] = from_addr
    msg['To'] = to_addr

    try:
        with smtplib.SMTP(smtp_host, smtp_port) as server:
            server.send_message(msg)
        print(f"[report] Sent: {msg['Subject']}")
    except Exception as e:
        print(f"[report] ERROR: Failed to send email: {e}", file=sys.stderr)
        # Don't fail hard — agent continues even if email fails
        sys.exit(0)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('subject', help='Email subject')
    parser.add_argument('file', nargs='?', help='File with report body (or stdin)')
    args = parser.parse_args()

    # Read body from file or stdin
    if args.file and os.path.exists(args.file):
        with open(args.file) as f:
            body = f.read()
    else:
        body = sys.stdin.read()

    # Get config from environment
    to_addr = os.environ.get('AGENT_REPORT_EMAIL', '')
    from_addr = os.environ.get('AGENT_FROM_EMAIL', 'agent@localhost')
    smtp_host = os.environ.get('SMTP_HOST', 'localhost')
    smtp_port = int(os.environ.get('SMTP_PORT', '25'))

    if not to_addr:
        print(f"[report] AGENT_REPORT_EMAIL not set. Would have sent:\nSubject: {args.subject}\n\n{body}")
        return

    send_report(args.subject, body, to_addr, from_addr, smtp_host, smtp_port)

if __name__ == '__main__':
    main()
```

---

### `vault-template/000-INDEX.md`

```markdown
# Vault Index — last updated SETUP-DATE

## What this vault is
[Your name]'s research and development second brain.
Domains: [fill in your main research/work areas]

## Active projects
→ See projects/INDEX.md for details and current status

| Project | Status | Last active |
|---------|--------|-------------|
| (none yet — add as you start projects) | | |

## Where to find things

| Need | Go to |
|------|-------|
| How a method/algorithm works | atlas/methods/ |
| Dataset documentation | atlas/datasets/ |
| Infrastructure/cluster setup | atlas/infrastructure/ |
| Architecture decisions | atlas/decisions/ |
| Full project history | projects/[name]/CHANGELOG.md |
| Recent agent briefing | projects/[name]/briefings/ |
| Raw captures to process | inbox/ |

## Atlas contents summary
atlas/methods/ — computational methods, algorithms, tools
atlas/datasets/ — dataset documentation and characteristics
atlas/infrastructure/ — pod setup, HPC, K8s, CERIT docs
atlas/decisions/ — architectural decision records (ADRs)

## Write rules (agents MUST follow)
- NEVER edit atlas/ without explicit instruction
- Append to CHANGELOG.md, never rewrite it
- New notes go to inbox/ first if unsure where they belong
- Briefings go to projects/[name]/briefings/YYYY-MM-DD-HHmm-briefing.md
- Keep this index under 60 lines — update summary tables, not content
```

---

### `vault-template/agents/librarian-prompt.md`

```markdown
# Librarian Agent Instructions

You are a vault librarian. Your only job is to find relevant notes.

Given a task description, you:
1. Read 000-INDEX.md (always first)
2. Read the relevant INDEX.md files it points to
3. Read the CHANGELOG.md for the relevant project (last 50 lines)
4. Identify which specific files in atlas/ and projects/[name]/context/ are relevant
5. Write a concise briefing to the specified output path

## Your briefing format
```
# Briefing: [task summary]
Generated: [date]

## Reading list (priority order)
1. [file path] — [one sentence: WHY this is relevant to the task]
2. [file path] — [why]
...

## Critical facts
[Any immediately relevant facts you found — past failures, known constraints,
prior decisions that affect this task. Max 10 bullet points.]

## Known failure modes relevant to this task
[Past approaches that failed, from CHANGELOG or known-failures.md files]
```

## Rules
- Do NOT summarise file contents — just identify them and explain relevance
- Do NOT make implementation decisions — just retrieve
- Maximum briefing length: 200 lines
- If a file doesn't exist yet, note it as "not yet documented"
- Prefer files from the specific project over general atlas files
```

---

### `vault-template/agents/templates/project-index.md`

```markdown
# [Project Name] — Index

**Status:** active | paused | complete
**Started:** YYYY-MM-DD
**Last updated:** YYYY-MM-DD

## One-line summary
[What this project is and its current goal]

## Current state
[2-3 sentences: where things stand right now, what's blocking or next]

## Key files
| File | Purpose |
|------|---------|
| CHANGELOG.md | Full history of all agent activity |
| context/experiment-results.md | Running table of results |
| context/known-failures.md | Approaches tried and failed |
| context/dataset-strategy.md | Dataset decisions |

## Active experiments / tasks
- [ ] [current task or experiment]

## Links
- Code: [path to project code]
- Data: [path to datasets]
```

---

### `vault-template/agents/templates/changelog-entry.md`

```
## YYYY-MM-DD HH:MM — [Agent type: Orchestrator|cerit-coder|cerit-researcher|etc.]

**What was done:** [1-2 sentences]
**Outcome:** [result, metric, or finding]
**Key decision:** [any important choice made and why]
**Failed approaches this session:** [what didn't work]
**Next:** [what should happen next]
**Worker output:** [path to detailed result file if applicable]
```

---

### `project-template/.claude/settings.json`

Project-level settings. The `bypassPermissions` mode is set globally in `~/.claude/settings.json` by the installer, so project settings just need to enable Agent Teams and ensure the env is set. Project-level deny rules can add project-specific protections on top of the global ones.

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "deny": [
      "Bash(rm -rf *)",
      "Bash(rm -f /*)",
      "Bash(git push --force-with-lease origin main)",
      "Bash(git push --force origin main)"
    ]
  },
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

The project-level deny list adds two extra protections specific to code repos: blocking force-pushes to main (always destructive). The global deny list (in `~/.claude/settings.json`) covers system-level destructive operations.

---

### `project-template/CLAUDE.md`

This file lives in individual project repos. It supplements (not replaces) the global `~/.claude/CLAUDE.md`. Claude Code loads both: global first, then project-level on top. Everything in Zone B of the global CLAUDE.md is general; this file is where project-specific detail lives.

Same dual-zone structure as the global file. Zone A (infrastructure) is minimal here because it's already covered globally. Zone B is where the user puts project-specific content.

```markdown
# ═══════════════════════════════════════════════════════════════
# ZONE A — PROJECT INFRASTRUCTURE NOTES
# Brief pointers to project-specific agent tooling.
# Usually needs little or no editing.
# ═══════════════════════════════════════════════════════════════

## Project-level agents (in .claude/agents/)
Project-specific subagent definitions override global ones with the same name.
See .claude/agents/ for any agents defined specifically for this project.

## Project-level skills (in .claude/skills/)
Project-specific skills take precedence over global skills with the same name.
See .claude/skills/ for any skills specific to this project.

## Vault integration
Vault project name (for librarian-retrieve.sh and librarian-archive.sh): [FILL IN — must match vault/projects/<name>/]
Run before complex tasks: bash librarian-retrieve.sh "<task>" <vault-project-name>


# ═══════════════════════════════════════════════════════════════
# ZONE B — PROJECT CONFIGURATION
#
# Fill in everything below. This is what the agent reads to
# understand your project. Be specific. Be concrete.
# Delete sections you don't need. Keep total under ~150 lines.
# ═══════════════════════════════════════════════════════════════

## Project overview
<!-- What is this project? What problem does it solve? -->
<!-- What is the current primary goal? -->
[FILL IN]


## Tech stack
<!-- Primary language, framework, key libraries -->
<!-- Example: Python 3.11, PyTorch 2.3, ultralytics YOLO, -->
<!-- PostGIS for geodata, HPC via PBS scheduler -->
[FILL IN]


## Repository layout
<!-- Key directories and what lives in them -->
<!-- Example: -->
<!-- src/          — main source code -->
<!-- tests/        — pytest test suite -->
<!-- data/         — symlink to /data/project-name -->
<!-- notebooks/    — exploratory analysis -->
<!-- configs/      — training configuration YAMLs -->
[FILL IN]


## Build, test, and run commands
```bash
# Run tests
[FILL IN: e.g. pytest tests/ -v]

# Lint / format
[FILL IN: e.g. ruff check . && ruff format .]

# Type check
[FILL IN: e.g. mypy src/]

# Run the main pipeline / training
[FILL IN]

# Any other key commands
[FILL IN]
```


## Coding conventions
<!-- Things an agent needs to know to write code that fits in -->
<!-- Example: -->
<!-- - ruff formatting, 88-char line length -->
<!-- - type hints required on all public functions -->
<!-- - docstrings in Google style -->
<!-- - no bare except; always catch specific exceptions -->
<!-- - use pathlib.Path not os.path -->
[FILL IN]


## Current goals and priorities
<!-- What are you actively working on? What matters most right now? -->
<!-- Update this when priorities shift. Agents use this to make -->
<!-- decisions about what to focus on when not explicitly told. -->
[FILL IN]


## Key decisions already made
<!-- Architecture choices, approaches ruled out, and WHY -->
<!-- This prevents agents from re-litigating settled questions. -->
<!-- Example: We use DEIMv2 not YOLOv9 because of better small-object perf. -->
<!-- Example: Hard negative ratio is fixed at 30% — do not change. -->
[FILL IN]


## Known issues and gotchas
<!-- Things that trip up anyone new to this codebase -->
<!-- Example: Data loader assumes images pre-resized to 640px. -->
<!-- Example: Config YAML uses relative paths from project root. -->
[FILL IN]


## Out of scope / do not touch
<!-- Explicit list of things agents should NOT change or attempt -->
<!-- Example: Do not modify data/raw/ — those are immutable source files. -->
<!-- Example: Do not change the model architecture in model/backbone.py -->
<!--          without explicit instruction — it affects saved checkpoints. -->
[FILL IN]
```

---

### `project-template/tasks/task-template.yaml`

Structured task spec format. CERIT workers read this instead of an inline string description. Enforces completeness — workers cannot start without acceptance criteria and constraints.

```yaml
# Task specification — copy and fill in before spawning a worker
# Usage: cerit-worker.sh tasks/task-NNN.yaml <output_file> [branch]

id: task-NNN
title: "Short imperative description"
type: feature  # feature | bugfix | refactor | research | data | analysis

priority: high  # high | medium | low
estimated_turns: 40  # rough estimate; worker will stop at max_turns

# Context the worker needs before starting
context:
  project: my-project                  # vault project name for librarian
  vault_project: my-project            # may differ from project name
  
  # Files the worker should read before implementing
  read_first:
    - docs/adr/                        # always read ADRs
    - src/relevant_module.py           # specific files relevant to this task
    # - vault briefing is fetched automatically if vault_project is set
  
  # Files the worker is allowed to modify (others need justification)
  affected_files:
    - src/new_module.py
    - tests/test_new_module.py

# What "done" means — worker verifies against these before reporting done
acceptance_criteria:
  - "Description of observable behaviour 1"
  - "All existing tests still pass"
  - "New tests added for the new functionality"
  - "No new linting errors"

# Hard constraints the worker must not violate
constraints:
  - "No new pip dependencies without prior approval"
  - "Must maintain backward compatibility with existing API"
  - "Do not modify files outside affected_files without justification"
  - "Performance: no regression on benchmark X"

# How success is measured (the worker runs this to verify)
success_metric: "pytest tests/ -q exits 0 with all new tests passing"

# Optional: specific things to try or avoid
implementation_hints:
  approach: "Start by reading the existing data loader before implementing"
  avoid: "Do not use global state"
  reference: "Follow the pattern in src/existing_similar_module.py"
```

---

### `README.md`

Write a README covering:

1. **What this is** — one paragraph
2. **Prerequisites** — `claude` CLI, `gh` CLI, `git`, `python3`, CERIT API key, Anthropic API key
3. **Quick start** — `git clone` → `./install.sh` → answer prompts → done
4. **Using with a new project** — copy/symlink `project-template/.claude/` and `project-template/CLAUDE.md` into the new repo; fill in Zone B of CLAUDE.md
5. **Provider switching** — `ca` (Anthropic) vs `cc` (CERIT) aliases
6. **Spawning CERIT workers** — `bash cerit-worker.sh "task" output.md branch-name`
7. **Parallel implementation** — `bash parallel-implement.sh "task" main`
8. **Vault / librarian** — retrieve: `bash librarian-retrieve.sh "task" project-name`; archive: `bash librarian-archive.sh worker-result file.md project-name`
9. **Vault structure** — brief explanation of 000-INDEX.md and the atlas/projects split
10. **Adding a new project to the vault** — copy project-index.md template, add to 000-INDEX.md and projects/INDEX.md
11. **Skills — adding and managing**:
    - What skills are and how Claude Code loads them
    - Where they live: `claude-config/skills/` (symlinked to `~/.claude/skills/`)
    - How to add one: drop a skill directory in, `git add` + commit, done
    - Where to find community skills: link to `github.com/hesreallyhim/awesome-claude-code`
    - Currently installed skills: link to `claude-config/skills/README.md`
12. **Editing CLAUDE.md** — explain Zone A vs Zone B; Zone B is yours to fill in
13. **Updating** — `git pull` in the infra repo; symlinks pick up changes automatically; Zone B is never touched by updates
14. **Troubleshooting** — CERIT key not set, no gh auth, worktree conflicts, context limit with CERIT models

---

---

## Librarian system — complete specification

The librarian is the most architecturally important component of this system. It is the **sole agent that reads from and writes to the vault**. All other agents interact with the vault only through the librarian. This single-writer discipline prevents fragmentation, inconsistency, and structural decay of the second brain over time.

### Librarian responsibilities

**As archivist (receives content, writes to vault):**
- Receives session summaries, conversation excerpts, research findings, agent results
- Determines the correct vault location for each piece of content
- Maintains consistent structure, cross-links between notes, and index freshness
- Never creates redundant notes — checks for existing relevant files and updates them instead of creating duplicates
- Appends to CHANGELOG files; never rewrites them
- Keeps all hub/index pages accurate and up to date

**As retriever (explores vault, returns reading lists):**
- Given a task description, explores 000-INDEX.md and project indexes
- Identifies and ranks the most relevant files
- Returns a structured briefing: ordered reading list + critical facts + known failures
- Does NOT summarise file contents — only points to them

### Trigger mechanisms — how content reaches the librarian

The librarian is triggered in **three ways**:

1. **Stop hook (automatic)** — fires at the end of every Claude Code session. Reads the session transcript JSONL, extracts a summary of what happened, and calls the archivist.
2. **SubagentStop hook (automatic)** — fires when any internal subagent finishes. Captures what the subagent did.
3. **Explicit agent call (instructed)** — the orchestrator and CERIT workers are instructed in CLAUDE.md and their task prompts to explicitly call the archivist after completing significant work.

This means the vault grows automatically even if agents forget to call the librarian explicitly — the hooks guarantee a baseline capture at session end.

---

### Files overview

All files described in this section are already reflected in the main repository structure at the top of this document. The following sections specify the complete content of each file that belongs to the librarian system:

### `claude-config/hooks/cost-estimator.py`

A `UserPromptSubmit` hook that injects current context usage and an estimated cost into every prompt. This makes the orchestrator naturally more frugal as context grows, and provides running cost awareness for long sessions. Runs synchronously but returns very fast (no subprocess calls).

```python
#!/usr/bin/env python3
"""
UserPromptSubmit hook — fires before every user prompt is processed.
Injects current session context stats as additionalContext so the agent
is always aware of its context usage and can make informed decisions
about compaction and delegation.
"""
import json
import os
import sys
from pathlib import Path
from datetime import datetime


def estimate_cost_usd(input_tokens: int, output_tokens: int, provider: str = "anthropic") -> float:
    """Rough cost estimate. Anthropic Sonnet pricing as of 2026."""
    if provider == "cerit":
        return 0.0  # Free
    # Sonnet 4.6: ~$3/MTok input, ~$15/MTok output (approximate)
    return (input_tokens * 3.0 + output_tokens * 15.0) / 1_000_000


def read_session_stats(transcript_path: str) -> dict:
    """Parse the session transcript to count tokens seen so far."""
    stats = {"input_tokens": 0, "output_tokens": 0, "turns": 0, "tool_calls": 0}
    if not transcript_path or not os.path.exists(transcript_path):
        return stats
    
    try:
        with open(transcript_path) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    usage = entry.get("usage", {}) or entry.get("message", {}).get("usage", {})
                    if usage:
                        stats["input_tokens"] += usage.get("input_tokens", 0)
                        stats["output_tokens"] += usage.get("output_tokens", 0)
                    if entry.get("type") in ("user", "assistant"):
                        stats["turns"] += 1
                    if entry.get("type") == "tool_use":
                        stats["tool_calls"] += 1
                except (json.JSONDecodeError, AttributeError):
                    continue
    except Exception:
        pass
    return stats


def main():
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)
    
    transcript_path = hook_input.get("transcript_path", "")
    stats = read_session_stats(transcript_path)
    
    # Determine provider from env
    is_cerit = bool(os.environ.get("ANTHROPIC_AUTH_TOKEN") and 
                    "cerit" in os.environ.get("CERIT_BASE_URL", "").lower())
    provider = "cerit" if is_cerit else "anthropic"
    
    cost = estimate_cost_usd(stats["input_tokens"], stats["output_tokens"], provider)
    
    # Context window size (approximate — 200K for Anthropic Sonnet/Opus)
    ctx_window = 200_000
    ctx_pct = min(99, int(stats["input_tokens"] / ctx_window * 100)) if stats["input_tokens"] else 0
    
    # Build status line
    if stats["input_tokens"] == 0:
        # New session — no stats yet
        sys.exit(0)
    
    cost_str = f"${cost:.3f}" if provider == "anthropic" else "free (CERIT)"
    
    ctx_warning = ""
    if ctx_pct >= 60:
        ctx_warning = f" ⚠️ COMPACT NOW (≥60%)"
    elif ctx_pct >= 45:
        ctx_warning = " — consider /compact soon"
    
    status_line = (
        f"[Session: ~{ctx_pct}% context used"
        f"{ctx_warning}"
        f" | {stats['turns']} turns"
        f" | {stats['tool_calls']} tool calls"
        f" | est. cost: {cost_str}]"
    )
    
    output = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": status_line
        }
    }
    print(json.dumps(output))
    sys.exit(0)


if __name__ == "__main__":
    main()
```

Register this hook in settings.json by adding to the `install.sh` hook merge step:

```json
"UserPromptSubmit": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "python3 AGENT_INFRA_DIR_PLACEHOLDER/claude-config/hooks/cost-estimator.py",
        "async": false
      }
    ]
  }
]
```

---

### `claude-config/hooks/session-end-archivist.py`

This is a Python hook script that fires on the `Stop` event. It reads the session transcript, extracts a structured summary, and calls the librarian archivist.

```python
#!/usr/bin/env python3
"""
Stop hook — fires when a Claude Code session ends.
Reads the session JSONL transcript, extracts meaningful content,
and calls the librarian archivist to archive it to the vault.

Configured in ~/.claude/settings.json as an async Stop hook so it
does not block the session from closing.
"""
import json
import os
import sys
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path

def parse_transcript(transcript_path: str) -> dict:
    """Extract structured content from a Claude Code JSONL transcript."""
    messages = []
    summary = ""
    cwd = ""
    
    try:
        with open(transcript_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    entry_type = entry.get("type", "")
                    
                    # Extract summary from first line if present
                    if entry_type == "summary" and not summary:
                        summary = entry.get("summary", "")
                    
                    # Collect user messages (conversation content)
                    elif entry_type == "user":
                        content = entry.get("message", {}).get("content", "")
                        if isinstance(content, list):
                            text = " ".join(
                                c.get("text", "") for c in content 
                                if isinstance(c, dict) and c.get("type") == "text"
                            )
                        else:
                            text = str(content)
                        if text.strip():
                            messages.append({"role": "user", "text": text.strip()[:500]})
                    
                    # Collect assistant responses (decisions, plans)
                    elif entry_type == "assistant":
                        content = entry.get("message", {}).get("content", "")
                        if isinstance(content, list):
                            text = " ".join(
                                c.get("text", "") for c in content
                                if isinstance(c, dict) and c.get("type") == "text"
                            )
                        else:
                            text = str(content)
                        if text.strip():
                            messages.append({"role": "assistant", "text": text.strip()[:800]})
                    
                    # Track bash commands run (agent actions)
                    elif entry_type == "tool_use" and entry.get("name") == "Bash":
                        cmd = entry.get("input", {}).get("command", "")
                        if cmd:
                            messages.append({"role": "action", "text": f"bash: {cmd[:200]}"})
                            
                except json.JSONDecodeError:
                    continue
                    
    except FileNotFoundError:
        return {"summary": "Transcript not found", "messages": [], "cwd": ""}
    
    return {
        "summary": summary,
        "messages": messages[-40:],  # keep last 40 exchanges to avoid huge inputs
        "cwd": cwd,
        "transcript_path": transcript_path,
    }


def detect_project(cwd: str) -> str:
    """Try to detect the project name from the working directory."""
    if not cwd:
        return "unknown"
    path = Path(cwd)
    # Try to find a CLAUDE.md with vault project mapping
    claude_md = path / "CLAUDE.md"
    if claude_md.exists():
        content = claude_md.read_text()
        for line in content.splitlines():
            if "Vault project name" in line or "vault project" in line.lower():
                # Extract the value after the colon
                parts = line.split(":", 1)
                if len(parts) > 1:
                    val = parts[1].strip()
                    if val and not val.startswith("["):
                        return val
    # Fall back to directory name
    return path.name


def main():
    # Read hook input from stdin
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)  # Don't block session close on parse error
    
    # Don't re-trigger if stop_hook_active (prevents infinite loop)
    if hook_input.get("stop_hook_active"):
        sys.exit(0)
    
    transcript_path = hook_input.get("transcript_path", "")
    cwd = hook_input.get("cwd", "")
    session_id = hook_input.get("session_id", "unknown")
    
    if not transcript_path or not os.path.exists(transcript_path):
        sys.exit(0)
    
    transcript = parse_transcript(transcript_path)
    project = detect_project(cwd)
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    
    # Build the archive content — what the librarian receives
    archive_content = f"""# Session Archive — {timestamp}
Session ID: {session_id}
Project: {project}
Working directory: {cwd}

## Session summary
{transcript['summary'] or '(no summary available)'}

## Conversation and actions
"""
    for msg in transcript['messages']:
        role = msg['role'].upper()
        archive_content += f"
[{role}] {msg['text']}
"
    
    # Write to a temp file and call the archivist
    with tempfile.NamedTemporaryFile(
        mode='w', suffix='.md', prefix='session-archive-', delete=False
    ) as f:
        f.write(archive_content)
        tmp_path = f.name
    
    try:
        # Call the archivist asynchronously (don't block)
        infra_dir = os.environ.get("AGENT_INFRA_DIR", str(Path.home() / "agent-infra"))
        script = os.path.join(infra_dir, "scripts", "librarian-archive.sh")
        
        if os.path.exists(script):
            subprocess.Popen(
                ["bash", script, "session-transcript", tmp_path, project],
                stdout=open(os.path.join(Path.home(), "logs", "librarian.log"), "a"),
                stderr=subprocess.STDOUT,
                start_new_session=True,  # detach from parent
            )
        # tmp_path will be cleaned up by the librarian-archive.sh script
    except Exception as e:
        # Log but never fail the hook
        log_path = Path.home() / "logs" / "librarian-hook-errors.log"
        log_path.parent.mkdir(exist_ok=True)
        with open(log_path, "a") as f:
            f.write(f"{timestamp}: Stop hook error: {e}\n")
    
    sys.exit(0)  # Always exit 0 — never block session close


if __name__ == "__main__":
    main()
```

---

### `claude-config/hooks/subagent-end-archivist.py`

Fires on `SubagentStop`. Captures what the subagent did and archives it.

```python
#!/usr/bin/env python3
"""
SubagentStop hook — fires when an internal Claude Code subagent finishes.
Extracts the subagent's final result and archives it to the vault.
Runs async so it does not delay the subagent result returning to the parent.
"""
import json
import os
import sys
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path


def main():
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)
    
    # Extract subagent info
    agent_id = hook_input.get("agent_id", "unknown")
    agent_type = hook_input.get("agent_type", "subagent")
    transcript_path = hook_input.get("transcript_path", "")
    cwd = hook_input.get("cwd", "")
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    
    # Build archive content
    archive_content = f"""# Subagent Log — {timestamp}
Agent ID: {agent_id}
Agent type: {agent_type}
Working directory: {cwd}
"""
    
    # Try to read final message from transcript
    if transcript_path and os.path.exists(transcript_path):
        try:
            lines = open(transcript_path).readlines()
            # Get last few lines (the final exchange)
            for line in lines[-10:]:
                try:
                    entry = json.loads(line)
                    if entry.get("type") == "assistant":
                        content = entry.get("message", {}).get("content", "")
                        if isinstance(content, list):
                            text = " ".join(
                                c.get("text", "") for c in content
                                if isinstance(c, dict) and c.get("type") == "text"
                            )
                        else:
                            text = str(content)
                        if text.strip():
                            archive_content += f"\n## Subagent final output\n{text.strip()[:1000]}\n"
                            break
                except json.JSONDecodeError:
                    continue
        except Exception:
            pass
    
    with tempfile.NamedTemporaryFile(
        mode='w', suffix='.md', prefix='subagent-archive-', delete=False
    ) as f:
        f.write(archive_content)
        tmp_path = f.name
    
    try:
        infra_dir = os.environ.get("AGENT_INFRA_DIR", str(Path.home() / "agent-infra"))
        script = os.path.join(infra_dir, "scripts", "librarian-archive.sh")
        
        if os.path.exists(script):
            # Detect project from cwd
            project = Path(cwd).name if cwd else "unknown"
            subprocess.Popen(
                ["bash", script, "subagent-log", tmp_path, project],
                stdout=open(os.path.join(Path.home(), "logs", "librarian.log"), "a"),
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
    except Exception as e:
        log_path = Path.home() / "logs" / "librarian-hook-errors.log"
        log_path.parent.mkdir(exist_ok=True)
        with open(log_path, "a") as f:
            f.write(f"{timestamp}: SubagentStop hook error: {e}\n")
    
    sys.exit(0)


if __name__ == "__main__":
    main()
```

---

---

### `claude-config/hooks/quality-check.py`

This PostToolUse hook fires after every Write/Edit/MultiEdit operation. It runs the project's configured linter and returns the output as `additionalContext` so Claude receives immediate feedback on every file it writes. It is **non-blocking** — it never prevents the file write from completing, only provides feedback.

```python
#!/usr/bin/env python3
"""
PostToolUse hook — fires after Write, Edit, MultiEdit.
Detects and runs the project linter, injects output back to Claude
as additionalContext so linting errors are fixed immediately.

Never blocks (always exits 0). Only provides feedback via additionalContext.
"""
import json
import os
import sys
import subprocess
import shutil
from pathlib import Path


def detect_linter(cwd: str) -> tuple[list[str], str] | None:
    """Detect which linter/formatter to run based on project config."""
    cwd_path = Path(cwd)
    
    # Python: ruff (preferred), then flake8, then pylint
    if (cwd_path / "pyproject.toml").exists() or (cwd_path / "setup.py").exists():
        if shutil.which("ruff"):
            return (["ruff", "check", "--output-format=concise", cwd], "ruff")
        if shutil.which("flake8"):
            return (["flake8", "--max-line-length=120", cwd], "flake8")
    
    # TypeScript/JavaScript: eslint
    if (cwd_path / "package.json").exists():
        if (cwd_path / ".eslintrc.json").exists() or (cwd_path / ".eslintrc.js").exists():
            npx = shutil.which("npx")
            if npx:
                return ([npx, "eslint", "--max-warnings=0", cwd], "eslint")
    
    # Go
    if list(cwd_path.glob("*.go")) or (cwd_path / "go.mod").exists():
        if shutil.which("golangci-lint"):
            return (["golangci-lint", "run", "--fast", cwd], "golangci-lint")
    
    return None


def run_type_check(cwd: str) -> str | None:
    """Run mypy if configured, return output or None."""
    cwd_path = Path(cwd)
    pyproject = cwd_path / "pyproject.toml"
    if not pyproject.exists():
        return None
    
    try:
        content = pyproject.read_text()
        if "[tool.mypy]" not in content:
            return None
    except Exception:
        return None
    
    if not shutil.which("mypy"):
        return None
    
    try:
        result = subprocess.run(
            ["mypy", "--no-error-summary", cwd],
            capture_output=True, text=True, timeout=30, cwd=cwd
        )
        if result.returncode != 0 and result.stdout.strip():
            lines = result.stdout.strip().split("\n")
            # Limit to first 20 type errors to avoid overwhelming context
            limited = "\n".join(lines[:20])
            if len(lines) > 20:
                limited += f"\n... ({len(lines) - 20} more type errors)"
            return limited
    except Exception:
        pass
    return None


def main():
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)
    
    cwd = hook_input.get("cwd", os.getcwd())
    file_path = hook_input.get("tool_input", {}).get("file_path", "")
    
    # Skip non-source files
    if file_path:
        skip_patterns = [".git/", "__pycache__", ".pyc", "node_modules/",
                         "/tmp/", ".log", ".json", ".yaml", ".yml", ".md",
                         ".txt", ".csv"]
        if any(p in file_path for p in skip_patterns):
            sys.exit(0)
    
    feedback_parts = []
    
    # Run linter
    linter_info = detect_linter(cwd)
    if linter_info:
        cmd, linter_name = linter_info
        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=30, cwd=cwd
            )
            output = (result.stdout + result.stderr).strip()
            if output and result.returncode != 0:
                lines = output.split("\n")
                limited = "\n".join(lines[:30])
                if len(lines) > 30:
                    limited += f"\n... ({len(lines)-30} more issues)"
                feedback_parts.append(
                    f"[{linter_name.upper()} — {result.returncode} issues found]\n{limited}"
                )
        except subprocess.TimeoutExpired:
            feedback_parts.append(f"[{linter_name.upper()}] Linter timed out (30s)")
        except Exception as e:
            pass  # Silently skip linter errors — never block on hook failure
    
    # Run type checker
    type_output = run_type_check(cwd)
    if type_output:
        feedback_parts.append(f"[MYPY — type errors]\n{type_output}")
    
    if feedback_parts:
        feedback = "\n\n".join(feedback_parts)
        feedback += "\n\nFix these issues before proceeding."
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": feedback
            }
        }
        print(json.dumps(output))
    
    sys.exit(0)  # Always exit 0 — quality-check never blocks


if __name__ == "__main__":
    main()
```

---

### `claude-config/hooks/stop-gate.py`

This Stop hook fires before every session close. If tests are failing, it blocks the stop and injects the failure output as feedback, forcing Claude to fix tests before the session ends. This is the **enforcement mechanism** that guarantees workers don't deliver broken code.

```python
#!/usr/bin/env python3
"""
Stop hook — fires when Claude attempts to stop/close the session.
Runs the project test suite. If tests fail, blocks the stop (exit code 2)
and injects failure details so Claude fixes them before closing.

Uses stop_hook_active guard to prevent infinite loops.
"""
import json
import os
import sys
import subprocess
import shutil
from pathlib import Path


def detect_test_command(cwd: str) -> list[str] | None:
    """Detect the project test command from config files."""
    cwd_path = Path(cwd)
    
    # Python: pytest
    if (cwd_path / "pyproject.toml").exists():
        try:
            content = (cwd_path / "pyproject.toml").read_text()
            if "[tool.pytest" in content or "pytest" in content:
                if shutil.which("pytest"):
                    return ["pytest", "--tb=short", "-q", "--no-header"]
        except Exception:
            pass
    
    if (cwd_path / "pytest.ini").exists() or (cwd_path / "setup.cfg").exists():
        if shutil.which("pytest"):
            return ["pytest", "--tb=short", "-q", "--no-header"]
    
    # Node/TypeScript
    if (cwd_path / "package.json").exists():
        try:
            import json as _json
            pkg = _json.loads((cwd_path / "package.json").read_text())
            if "test" in pkg.get("scripts", {}):
                npm = shutil.which("npm")
                if npm:
                    return [npm, "test", "--", "--passWithNoTests"]
        except Exception:
            pass
    
    # Makefile with test target
    if (cwd_path / "Makefile").exists():
        try:
            content = (cwd_path / "Makefile").read_text()
            if "test:" in content or "test :" in content:
                if shutil.which("make"):
                    return ["make", "test"]
        except Exception:
            pass
    
    return None


def main():
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)
    
    # CRITICAL: prevent infinite loop
    if hook_input.get("stop_hook_active"):
        sys.exit(0)
    
    cwd = hook_input.get("cwd", os.getcwd())
    
    test_cmd = detect_test_command(cwd)
    if not test_cmd:
        # No test suite found — don't block, just let it stop
        sys.exit(0)
    
    try:
        result = subprocess.run(
            test_cmd,
            capture_output=True, text=True,
            timeout=120,  # 2 min max for stop gate
            cwd=cwd
        )
        
        if result.returncode == 0:
            # Tests pass — allow stop
            sys.exit(0)
        
        # Tests failed — block the stop
        output = (result.stdout + result.stderr).strip()
        lines = output.split("\n")
        
        # Show last 40 lines (most relevant: failures are at the end)
        relevant = "\n".join(lines[-40:]) if len(lines) > 40 else output
        
        error_msg = (
            f"STOP BLOCKED: Tests are failing. Fix before closing this session.\n\n"
            f"Command: {' '.join(test_cmd)}\n"
            f"Exit code: {result.returncode}\n\n"
            f"Test output (last 40 lines):\n{relevant}\n\n"
            f"Do not use /clear to escape — fix the failures."
        )
        
        print(json.dumps({
            "decision": "block",
            "reason": error_msg
        }))
        sys.exit(2)
        
    except subprocess.TimeoutExpired:
        # Test suite timed out — allow stop (don't punish for slow tests)
        sys.exit(0)
    except Exception:
        # Any other error — allow stop (don't block on hook failure)
        sys.exit(0)


if __name__ == "__main__":
    main()
```

---

### Hook registration in `~/.claude/settings.json`

The `install.sh` must write or merge these hook entries into `~/.claude/settings.json`. The hooks are registered as `async: true` so they never block session close or subagent return.

The implementing agent must write logic in `install.sh` to:
1. Read existing `~/.claude/settings.json` if it exists (parse as JSON)
2. Merge the hooks object into it (do not overwrite other settings)
3. Write the result back

The hooks JSON to merge:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 $AGENT_INFRA_DIR/claude-config/hooks/session-end-archivist.py",
            "async": true
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 $AGENT_INFRA_DIR/claude-config/hooks/subagent-end-archivist.py",
            "async": true
          }
        ]
      }
    ]
  }
}
```

Note: `$AGENT_INFRA_DIR` must be set to the actual absolute path of the `agent-infra` repository in the installed hooks — use string interpolation in `install.sh`, not a literal variable reference, since `settings.json` does not expand shell variables.

---

### `scripts/librarian-archive.sh`

The archivist entry point. Receives content of any kind, calls a CERIT-powered librarian to process it into the vault.

```bash
#!/bin/bash
# Librarian Archivist — receives content and files it into the vault
# Usage: librarian-archive.sh <content_type> <content_file> [project]
#
# content_type: session-transcript | worker-result | research-finding |
#               conversation-excerpt | agent-log | arbitrary
# content_file: path to a markdown file containing the content to archive
# project:      vault project name (defaults to "general")
#
# Called by: Stop hook, SubagentStop hook, CERIT workers (explicitly),
#            orchestrator (explicitly when instructed)

set -euo pipefail

if [ -z "${CERIT_API_KEY:-}" ]; then
  echo "ERROR: CERIT_API_KEY not set. Cannot call librarian." >&2
  exit 1
fi

CONTENT_TYPE="${1:-arbitrary}"
CONTENT_FILE="$2"
PROJECT="${3:-general}"
VAULT="${VAULT:-$HOME/vault}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DATE=$(date '+%Y-%m-%d')

if [ ! -f "$CONTENT_FILE" ]; then
  echo "ERROR: Content file not found: $CONTENT_FILE" >&2
  exit 1
fi

ARCHIVE_PROMPT="$VAULT/agents/librarian-archive-prompt.md"
if [ ! -f "$ARCHIVE_PROMPT" ]; then
  echo "ERROR: Librarian archive prompt not found at $ARCHIVE_PROMPT" >&2
  exit 1
fi

TASK_FILE=$(mktemp /tmp/librarian-archive-task-XXXXXX.md)

cat > "$TASK_FILE" << TASKEOF
# Librarian Archive Task — $TIMESTAMP

## Content to archive
Type: $CONTENT_TYPE
Project: $PROJECT
Vault root: $VAULT
Received at: $TIMESTAMP

## Content
$(cat "$CONTENT_FILE")

## Your instructions
$(cat "$ARCHIVE_PROMPT")

## Context for this specific archival
- Content type is: $CONTENT_TYPE
- Project context: $PROJECT
- Today's date: $DATE

## Required outputs
1. Write or update the appropriate vault files
2. Update $VAULT/projects/$PROJECT/CHANGELOG.md with a brief entry
3. If you created or updated hub/index files, note them in your response
4. Clean up the input file when done: rm -f $CONTENT_FILE
TASKEOF

echo "[librarian-archive] Archiving: $CONTENT_TYPE for project: $PROJECT"

# Librarian uses a full thinking model — NOT mini. Vault organisation is high-responsibility.
ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" ANTHROPIC_MODEL="${CERIT_LIBRARIAN_MODEL}" ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_LIBRARIAN_MODEL}" ANTHROPIC_DEFAULT_HAIKU_MODEL="${CERIT_LIBRARIAN_MODEL}" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude -p "$(cat "$TASK_FILE")"   --allowedTools "Read,Write,Edit,Glob,Grep,Bash"   --max-turns 40   --dangerously-skip-permissions   --output-format text   >> "${HOME}/logs/librarian.log" 2>&1

EXIT_CODE=$?
rm -f "$TASK_FILE"

if [ $EXIT_CODE -ne 0 ]; then
  echo "[librarian-archive] WARNING: Archive process exited with $EXIT_CODE" >&2
  # Do not propagate error — archival failures should never break the calling process
fi

exit 0
```

---

### `scripts/librarian-retrieve.sh`

The retriever entry point. Given a task, explores the vault and returns a reading list. This replaces the old `librarian.sh`.

```bash
#!/bin/bash
# Librarian Retriever — explores vault and returns a reading list briefing
# Usage: librarian-retrieve.sh "<task description>" <project_name>
# Output: writes briefing to $VAULT/projects/<project>/briefings/YYYY-MM-DD-HHmm-briefing.md
#         AND prints the briefing path to stdout for the caller to read

set -euo pipefail

if [ -z "${CERIT_API_KEY:-}" ]; then
  echo "ERROR: CERIT_API_KEY not set." >&2
  exit 1
fi

TASK="$1"
PROJECT="${2:-general}"
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H%M)
VAULT="${VAULT:-$HOME/vault}"
BRIEFING_DIR="$VAULT/projects/$PROJECT/briefings"
OUTPUT="$BRIEFING_DIR/${DATE}-${TIME}-briefing.md"

mkdir -p "$BRIEFING_DIR"

RETRIEVE_PROMPT="$VAULT/agents/librarian-retrieve-prompt.md"
if [ ! -f "$RETRIEVE_PROMPT" ]; then
  echo "ERROR: Librarian retrieve prompt not found at $RETRIEVE_PROMPT" >&2
  exit 1
fi

TASK_FILE=$(mktemp /tmp/librarian-retrieve-task-XXXXXX.md)

cat > "$TASK_FILE" << TASKEOF
# Librarian Retrieval Task

Task to research: $TASK
Project: $PROJECT
Vault root: $VAULT
Output briefing: $OUTPUT
Today's date: $DATE

$(cat "$RETRIEVE_PROMPT")

## Navigation instructions
Start at: $VAULT/000-INDEX.md
Then: $VAULT/projects/INDEX.md
Then: $VAULT/projects/$PROJECT/INDEX.md (if exists)
Then: $VAULT/projects/$PROJECT/CHANGELOG.md (read last 30 lines only)
Then: navigate to atlas/ files as indicated by the task and indexes

Write your briefing to: $OUTPUT
TASKEOF

echo "[librarian-retrieve] Researching vault for: $TASK"

# Librarian retriever also uses a full thinking model
ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" ANTHROPIC_MODEL="${CERIT_LIBRARIAN_MODEL}" ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_LIBRARIAN_MODEL}" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude -p "$(cat "$TASK_FILE")"   --allowedTools "Read,Write,Glob,Grep"   --max-turns 25   --dangerously-skip-permissions   --output-format text   >> "${HOME}/logs/librarian.log" 2>&1

rm -f "$TASK_FILE"

if [ -f "$OUTPUT" ]; then
  echo "[librarian-retrieve] Briefing written to: $OUTPUT"
  echo "$OUTPUT"  # Print path so caller can read it
else
  echo "[librarian-retrieve] WARNING: No briefing written" >&2
  exit 1
fi
```

---

### `vault-template/agents/librarian-archive-prompt.md`

The archivist's system prompt. This is what tells the CERIT-powered agent how to structure content into the vault.

````markdown
# Librarian Archivist — System Instructions

You are the vault archivist. You receive raw content (session transcripts,
conversation excerpts, agent results, research findings) and file it into
the correct location in the vault with proper structure.

## Your core principles

**One source of truth:** Before creating any new file, check whether a
relevant file already exists. Update existing files rather than creating
duplicates. The vault should grow in depth, not in redundant breadth.

**Preserve meaning, improve structure:** Never discard information. Your
job is to reformat and reorganise, not to summarise away detail.
Summaries go in index/hub files; full detail goes in the actual content files.

**Maintain hub pages:** After every archival operation, update the relevant
hub pages (000-INDEX.md, projects/INDEX.md, projects/<name>/INDEX.md) if
the new content changes what's findable there. Hub pages must stay accurate.

**Append-only CHANGELOG:** Always append to CHANGELOG.md files. Never
rewrite or restructure them. A CHANGELOG entry must be concise (max 5 lines).

## Vault structure reference

```
$VAULT/
├── 000-INDEX.md              ← Master hub: overview + table of what's where
├── atlas/                    ← Stable reference knowledge (slow-changing)
│   ├── INDEX.md              ← Hub for atlas
│   ├── methods/              ← How algorithms/methods work
│   ├── datasets/             ← Dataset documentation
│   ├── infrastructure/       ← Pod, HPC, cluster, environment setup
│   └── decisions/            ← Architecture decision records (ADRs)
├── projects/<name>/          ← One directory per project
│   ├── INDEX.md              ← Project hub: current state, goals, key files
│   ├── CHANGELOG.md          ← Append-only activity log
│   ├── context/              ← Rich detail files
│   │   ├── conversation-history.md  ← Running log of user-agent conversation
│   │   ├── research-log.md          ← Findings from research tasks
│   │   ├── experiment-results.md    ← ML/experiment outcomes
│   │   ├── known-failures.md        ← What has been tried and failed
│   │   ├── architecture.md          ← Current intended architecture
│   │   └── goals.md                 ← Project goals and requirements
│   └── briefings/            ← Reading lists generated by retriever
└── inbox/                    ← Unprocessed captures (temporary)
```

## Routing rules by content type

**session-transcript:**
- Extract conversation turns between user and orchestrator
- Append meaningful exchanges to `projects/<name>/context/conversation-history.md`
- Extract any decisions made → `projects/<name>/context/architecture.md` (update section)
- Extract any goals or requirements discussed → `projects/<name>/context/goals.md`
- Append one-line CHANGELOG entry
- If the session touched atlas topics (methods, datasets, infrastructure), update those files too

**worker-result:**
- File in `projects/<name>/context/` based on what the worker did:
  - Code implementation → note in CHANGELOG + update architecture.md if design changed
  - Research → append to research-log.md with source and findings
  - Data work → append to experiment-results.md
  - Failed attempt → append to known-failures.md with what was tried and why it failed
- Append CHANGELOG entry

**research-finding:**
- If general/reusable knowledge: `atlas/methods/` or `atlas/datasets/`
- If project-specific: `projects/<name>/context/research-log.md`
- If it changes architecture understanding: update `projects/<name>/context/architecture.md`

**conversation-excerpt:**
- Append to `projects/<name>/context/conversation-history.md`
- If it contains decisions: cross-reference in architecture.md
- If it contains new goals/requirements: update goals.md

**subagent-log:**
- Brief: one CHANGELOG entry only, unless the subagent produced significant findings
- If significant findings: same routing as worker-result

**arbitrary:**
- Read the content and determine the most appropriate location
- When uncertain, file in `projects/<name>/context/` or `inbox/`

## Hub page update rules

Update `projects/<name>/INDEX.md` when:
- The project's current state has changed meaningfully
- New key files have been created
- Active tasks or goals have changed

Update `000-INDEX.md` when:
- A new project directory has been created
- A project's status has changed (active/paused/complete)
- New atlas content has been added that changes navigation

Keep hub pages concise. They are navigation aids, not content.

## CHANGELOG entry format
```
## YYYY-MM-DD HH:MM — [source: session|worker|research|subagent]
**Action:** [1 sentence]
**Outcome:** [1 sentence, or "in progress"]
**Files updated:** [comma-separated list]
```

## What NOT to do
- Do not create files in atlas/ without explicit instruction (atlas = stable reference)
- Do not rewrite CHANGELOG entries — only append
- Do not summarise away numerical results, code snippets, or specific findings
- Do not create a new file if an existing one covers the same topic
````

---

### `vault-template/agents/librarian-retrieve-prompt.md`

Replaces the old `librarian-prompt.md`. The retriever's system prompt.

````markdown
# Librarian Retriever — System Instructions

You are the vault retriever. Your only job is to find relevant vault content
and produce a structured reading list for an agent about to start a task.

## Your core principles

**Do NOT write to the vault.** You are read-only. Do not create, edit,
or modify any file. If you find outdated information, note it in your
briefing but do not fix it.

**Navigate efficiently.** Start at 000-INDEX.md. Use it to find the right
areas. Do not read every file — use Grep to search before reading.

**Return a reading list, not a summary.** Your output tells the agent
WHAT to read and WHY, in priority order. Do not reproduce file contents.

## Navigation sequence
1. Read `$VAULT/000-INDEX.md` (always, always, always)
2. Read `$VAULT/projects/INDEX.md`
3. Read `$VAULT/projects/<project>/INDEX.md` if it exists
4. Read last 30 lines of `$VAULT/projects/<project>/CHANGELOG.md`
5. Grep atlas/ for terms relevant to the task
6. Identify specific files to recommend

## Briefing format (write to the specified output path)

```markdown
# Briefing: [task summary in one line]
Generated: [date and time]
Project: [project name]

## Reading list (priority order)
1. [full file path] — [one sentence: why this is relevant to THIS task]
2. [full file path] — [why]
...

## Critical facts (from what you read)
- [Specific fact directly relevant to the task — not a file reference]
- [Another specific fact]
(max 8 bullet points; include numbers, decisions, constraints — not vague generalities)

## Known failure modes for this task
- [Past approaches that failed, from CHANGELOG or known-failures.md]
- [Include WHY they failed if known]

## Gaps in the vault
- [Topics relevant to the task that are NOT yet documented]
- [Helps the agent know what to research from scratch]
```

## Rules
- Maximum briefing length: 150 lines
- Minimum reading list: 3 files (if they exist)
- Maximum reading list: 10 files
- Include `known-failures.md` in the reading list if it exists for this project
- Always include `CHANGELOG.md` in the reading list
- Prefer project-specific files over general atlas files
- If a recommended file doesn't exist yet, still list it with note "(not yet created)"
````

---

### `scripts/vault-health.sh`

Weekly vault curation agent. Runs automatically via cron or manually. Uses the librarian model to identify stale notes, structural issues, and missing documentation. Produces an actionable health report but does NOT automatically delete anything — it recommends actions for human or orchestrator review.

```bash
#!/bin/bash
# Vault Health Agent — periodic curation of the second brain
# Usage: vault-health.sh [project_filter]
# Recommended: run weekly via cron or /loop
#
# Produces: $VAULT/agents/vault-health-report-YYYY-MM-DD.md

set -euo pipefail

if [ -z "${CERIT_API_KEY:-}" ]; then
  echo "ERROR: CERIT_API_KEY not set." >&2
  exit 1
fi

VAULT="${VAULT:-$HOME/vault}"
PROJECT_FILTER="${1:-}"
DATE=$(date +%Y-%m-%d)
REPORT="$VAULT/agents/vault-health-report-${DATE}.md"
LOG="${HOME}/logs/vault-health.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[vault-health] Starting vault health check at $TIMESTAMP"
echo "[vault-health] Vault: $VAULT"
echo "[vault-health] Report: $REPORT"

TASK_FILE=$(mktemp /tmp/vault-health-task-XXXXXX.md)

cat > "$TASK_FILE" << TASKEOF
# Vault Health Check — $DATE
Vault root: $VAULT
Project filter: ${PROJECT_FILTER:-all projects}
Report output: $REPORT

## Your task
Perform a comprehensive health check of the Obsidian second brain vault.
Read vault structure, then check each dimension below.
Write a prioritised, actionable report.

## Health dimensions to check

### 1. Index accuracy
- Read $VAULT/000-INDEX.md
- Check: does every project listed there actually exist in projects/?
- Check: are there projects in projects/ NOT listed in 000-INDEX.md?
- Check: are status labels accurate (active projects that look inactive)?

### 2. Hub page freshness
- For each project in projects/: read INDEX.md and the last 20 lines of CHANGELOG.md
- Check: does INDEX.md "Current state" match what CHANGELOG.md shows?
- List projects where INDEX.md is clearly stale

### 3. Content gaps
- For each project with recent CHANGELOG entries: check whether corresponding
  atlas/ documentation exists for methods/tools mentioned
- List: "Project X uses method Y but Y has no atlas/ documentation"

### 4. Orphaned content
- Find notes in inbox/ older than 14 days (use file modification times via bash: find $VAULT/inbox/ -mtime +14)
- List files that are orphaned (no backlinks from any other note)

### 5. Stale known-failures
- Read known-failures.md files in projects/
- Flag: failures documented as "unresolved" that are older than 60 days
- These may be resolved but not updated

### 6. Duplicate detection
- Look for notes with very similar titles in the same directory
- List potential duplicates for human review

## Report format (write to $REPORT)

# Vault Health Report — $DATE

## Executive summary
(2-3 sentences: overall vault health, most urgent issues)

## Index issues (fix these first — they break navigation)
- [ ] [specific actionable fix]

## Stale hub pages
- [ ] [project]: INDEX.md says "X" but CHANGELOG shows "Y" — update needed

## Content gaps (atlas/ documentation missing)
- [ ] [project] uses [method] — document in atlas/methods/[method].md

## Inbox backlog
- [ ] [n] files in inbox/ older than 14 days — review and file or delete

## Stale known-failures (may be resolved)
- [ ] [project]/context/known-failures.md: "[issue]" — verify if still relevant

## Potential duplicates
- [ ] [file1] and [file2] — may be the same topic

## What's healthy (no action needed)
(brief list of vault areas that look good)

## Recommended next actions
1. [highest priority action]
2. [second priority]
3. [third priority]
TASKEOF

ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" ANTHROPIC_MODEL="${CERIT_LIBRARIAN_MODEL}" ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_LIBRARIAN_MODEL}" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude -p "$(cat "$TASK_FILE")"   --allowedTools "Read,Write,Bash,Glob,Grep"   --max-turns 30   --dangerously-skip-permissions   --output-format text   >> "$LOG" 2>&1

rm -f "$TASK_FILE"

if [ -f "$REPORT" ]; then
  echo "[vault-health] Report written to: $REPORT"
  echo ""
  echo "=== VAULT HEALTH SUMMARY ==="
  head -20 "$REPORT"
  echo "..."
  echo "Full report: $REPORT"
else
  echo "[vault-health] WARNING: No report produced. Check $LOG"
fi
```

To run weekly automatically, add to crontab:
```bash
# Run vault health check every Sunday at 8am
0 8 * * 0 VAULT="$HOME/vault" CERIT_API_KEY="..." bash /path/to/agent-infra/scripts/vault-health.sh
```

Or use Claude Code's `/loop` command in an interactive session:
```
/loop 7d run vault health check: bash vault-health.sh
```

---

## Implementation notes for the implementing agent

### Order of implementation

Work through these groups in order. Each group depends on the previous.

**Group 1 — Scripts (implement first, everything else references them)**
1. `scripts/cerit-worker.sh` — core CERIT worker spawner (accepts YAML spec or string)
2. `scripts/parallel-implement.sh` — best-of-3 with judge + cleanup
3. `scripts/implement-and-refine.sh` — generator-evaluator refinement loop
4. `scripts/librarian-archive.sh` — vault archivist entry point
5. `scripts/librarian-retrieve.sh` — vault retriever entry point
6. `scripts/vault-health.sh` — weekly vault curation agent
7. `scripts/send-report.py` — email reporter

**Group 2 — Hooks (implement before config, config references them)**
8. `claude-config/hooks/quality-check.py` — PostToolUse linter feedback
9. `claude-config/hooks/stop-gate.py` — Stop hook test enforcement
10. `claude-config/hooks/cost-estimator.py` — UserPromptSubmit context/cost stats
11. `claude-config/hooks/session-end-archivist.py` — Stop async vault archival
12. `claude-config/hooks/subagent-end-archivist.py` — SubagentStop async archival

**Group 3 — Agents and skills**
13. All `.claude/agents/*.md` files (6 agents + architecture-guardian)
14. `claude-config/skills/parallel-implement/SKILL.md`
15. `claude-config/skills/implement-and-refine/SKILL.md`
16. `claude-config/skills/README.md` (with the skills table populated)

**Group 4 — Vault template**
17. All `vault-template/` files (000-INDEX.md, atlas/, projects/, agents/ with prompts)

**Group 5 — Project template**
18. `project-template/.claude/settings.json`
19. `project-template/CLAUDE.md` (both Zone A and Zone B with placeholders)
20. `project-template/tasks/task-template.yaml`
21. `project-template/docs/adr/README.md` and `adr-template.md`

**Group 6 — Global CLAUDE.md (implement after all scripts are known)**
22. `claude-config/CLAUDE.md` — full dual-zone file with all Zone A content

**Group 7 — Installer and README (implement last)**
23. `install.sh` — references all the above; uses AGENT_INFRA_DIR absolute path substitution
24. `README.md` — documents the complete system for humans
25. `.gitignore` — ignores logs, .env, __pycache__, .DS_Store, *.pyc
26. Initial `git init && git add -A && git commit -m "initial: agent-infra scaffold"`

### Testing checklist
After implementation, verify:
- [ ] `install.sh` runs without errors on a fresh system (test in a temp dir)
- [ ] `cerit-worker.sh` syntax is valid: `bash -n scripts/cerit-worker.sh`
- [ ] `cerit-worker.sh` accepts both YAML file path and inline string as $1
- [ ] `parallel-implement.sh` syntax is valid: `bash -n scripts/parallel-implement.sh`
- [ ] `implement-and-refine.sh` syntax is valid: `bash -n scripts/implement-and-refine.sh`
- [ ] `librarian-archive.sh` syntax is valid: `bash -n scripts/librarian-archive.sh`
- [ ] `librarian-retrieve.sh` syntax is valid: `bash -n scripts/librarian-retrieve.sh`
- [ ] `vault-health.sh` syntax is valid: `bash -n scripts/vault-health.sh`
- [ ] `send-report.py` syntax is valid: `python3 -m py_compile scripts/send-report.py`
- [ ] `quality-check.py` syntax is valid: `python3 -m py_compile claude-config/hooks/quality-check.py`
- [ ] `stop-gate.py` syntax is valid: `python3 -m py_compile claude-config/hooks/stop-gate.py`
- [ ] `cost-estimator.py` syntax is valid: `python3 -m py_compile claude-config/hooks/cost-estimator.py`
- [ ] `session-end-archivist.py` syntax is valid: `python3 -m py_compile claude-config/hooks/session-end-archivist.py`
- [ ] `subagent-end-archivist.py` syntax is valid: `python3 -m py_compile claude-config/hooks/subagent-end-archivist.py`
- [ ] All agent `.md` files have valid YAML frontmatter
- [ ] `architecture-guardian.md` has `permissionMode: readOnly` (must not write)
- [ ] `vault-template/000-INDEX.md` exists and is well-formed
- [ ] `project-template/.claude/settings.json` is valid JSON with all 4 hook types
- [ ] `project-template/tasks/task-template.yaml` exists and is valid YAML
- [ ] `project-template/docs/adr/README.md` and `adr-template.md` exist
- [ ] `claude-config/skills/README.md` exists and contains the skills table
- [ ] `claude-config/skills/parallel-implement/SKILL.md` exists
- [ ] `claude-config/skills/implement-and-refine/SKILL.md` exists
- [ ] Global CLAUDE.md has both Zone A and Zone B sections clearly marked
- [ ] Global CLAUDE.md Zone A mentions: quality gates, compaction preservation, ADRs, task specs
- [ ] Project-template CLAUDE.md has both zones and all placeholder sections
- [ ] CLAUDE.md Zone A is under 180 lines (grew slightly to accommodate new content)
- [ ] settings.json hook list in spec matches exactly: UserPromptSubmit, PostToolUse, Stop (×2), SubagentStop

### Key design decisions already made (do not change)
- Workers use `--dangerously-skip-permissions` because they run headless with a well-defined task
- Workers log to `~/logs/cerit-workers.log` always (not just on failure)
- The parallel script uses `mktemp` for results dirs so concurrent runs don't collide
- Cleanup is always attempted even on failure (trap ERR)
- Worker output files are checked for existence AND size before trusting them
- The judge reads actual code, not just self-reports (workers may be inaccurate)
- Vault writes are append-only for CHANGELOG.md, never rewrite
- Global CLAUDE.md Zone A is kept under ~160 lines — every extra line costs every session
- Skills directory is under `claude-config/skills/` in the repo, symlinked to `~/.claude/skills/`
  so that `git pull` in the infra repo automatically propagates skill updates to all sessions
- The dual-zone CLAUDE.md structure is intentional: Zone A never changes without understanding
  the implications; Zone B is the user's domain and is never touched by infrastructure updates
- Permission model is `bypassPermissions` globally with a deny list for destructive shell operations.
  Agents should never stall waiting for permission — this is explicit user intent. The deny list
  blocks: `rm -rf /`, `dd`, `mkfs`, `fdisk`, `shred`, fork bombs, and force-pushes to main.
- CERIT model names are stored as env vars (`CERIT_CODER_MODEL`, `CERIT_THINKER_MODEL`,
  `CERIT_FAST_MODEL`, `CERIT_LIBRARIAN_MODEL`) set during install by interactive model selection.
  Scripts reference these vars, never hardcode model names. This allows model changes without
  editing any script files.
- Librarian (archivist + retriever) uses `CERIT_LIBRARIAN_MODEL` — a full reasoning model, not mini.
  max-turns is 40 for archivist, 25 for retriever. Poor vault organisation means knowledge is lost.
- The parallel judge uses `CERIT_THINKER_MODEL` — evaluating 3 implementations requires real reasoning.
- CERIT endpoint URL is `https://llm.ai.e-infra.cz/v1` (with `/v1`). The API key is pre-configured.
- CERIT credentials are baked into the spec; the only user-required credential is the Anthropic key.
- quality-check.py PostToolUse hook is non-blocking (always exits 0). It injects linting feedback
  as additionalContext. The agent receives it naturally as part of the tool result — it doesn't
  block the write, it just means the agent immediately knows about lint errors.
- stop-gate.py Stop hook blocks on test failure (exits 2) but has a timeout (120s) so slow
  test suites don't permanently prevent session close. It also guards against infinite loops
  via the stop_hook_active check.
- cost-estimator.py UserPromptSubmit hook reads the JSONL transcript to count tokens — it
  never makes API calls and returns in <50ms. The cost estimate is approximate but sufficient
  for the compaction trigger reminder. CERIT sessions always show "free (CERIT)".
- Task spec YAML format is optional, not mandatory. Inline strings still work in cerit-worker.sh
  for quick ad-hoc tasks. The YAML format is preferred for complex features where acceptance
  criteria need to be explicit.
- architecture-guardian runs permissionMode: readOnly and must never write to the codebase.
  It reads docs/adr/ and git diffs, produces a verdict, and reports to the orchestrator.
  The orchestrator decides whether to merge, request changes, or escalate to the user.
- vault-health.sh produces recommendations only — it never automatically deletes or modifies
  vault content. All vault modifications require human or orchestrator review of the report.
- implement-and-refine.sh uses CERIT_THINKER_MODEL for the evaluator and CERIT_CODER_MODEL
  for the implementer. The evaluator reads actual code files, not just self-reports. The
  max_rounds default of 3 means at most 3 implement+evaluate cycles (6 CERIT agent runs total).

### What to leave for the user to configure
- `ANTHROPIC_API_KEY` and `CERIT_API_KEY` — prompted by install.sh, never hardcoded
- `AGENT_REPORT_EMAIL`, `SMTP_HOST`, `SMTP_PORT` — optional, documented in README
- Vault content (atlas/, projects/) — scaffold only, user fills in their knowledge
- All `[FILL IN]` sections in both CLAUDE.md files — the agent should NOT fill these in
- Skills beyond `parallel-implement` — user downloads and drops in per README instructions

### Git repository setup
The agent-infra repo itself should have:
- `.gitignore` ignoring: `*.log`, `.env`, `__pycache__`, `.DS_Store`, `*.pyc`
- An initial commit with all files
- A `main` branch

The vault (separate from this repo) gets its own git repo initialised by install.sh.

---

## Frequently asked questions the implementing agent should anticipate

**Q: What if CERIT_API_KEY is not set when a worker script runs?**
A: The script should fail immediately with a clear error message. Add a check at the top of each script: `if [ -z "${CERIT_API_KEY:-}" ]; then echo "ERROR: CERIT_API_KEY not set. Run install.sh or set it manually."; exit 1; fi`

**Q: What if git is not initialised in the current directory when parallel-implement.sh runs?**
A: The script uses `git rev-parse --show-toplevel` with a fallback to `$PWD`. If not in a git repo, worktrees cannot be created — the script should fail with a clear error and suggest running `git init` first.

**Q: What if a CERIT worker runs out of context?**
A: The worker will stop and its output file may be incomplete. The cleanup function handles this by checking file size and writing a failure report if the output is empty. The parallel judge will mark that worker as failed.

**Q: Can the vault be on a remote filesystem (NFS, SSHFS)?**
A: Yes. The scripts only use standard bash file operations. The only requirement is that the path in `$VAULT` is accessible. Git operations in the vault are separate from git operations in the project repo.

**Q: What if the user doesn't have `gh` (GitHub CLI) installed?**
A: The cerit-worker.sh and parallel-implement.sh scripts use `gh` for PR creation. This should be optional — if `gh` is not found, workers should skip PR creation and just commit+push, noting in their output that PR creation was skipped.

**Q: How does the user add a community skill they found online?**
A: Download or clone the skill directory, place it inside `agent-infra/claude-config/skills/`, and `git add` + `git commit` it. Because `~/.claude/skills/` is a symlink to that directory, the skill is immediately available in all new Claude Code sessions. The user should also add a row to `claude-config/skills/README.md` for their own reference.

**Q: Should the implementing agent fill in the Zone B [FILL IN] placeholders in CLAUDE.md?**
A: No. The `[FILL IN]` markers are for the human user to complete. The implementing agent creates all files exactly as specified, with all `[FILL IN]` placeholders intact and unchanged. The same applies to `[FILL IN]` markers in project-template/CLAUDE.md, task-template.yaml, and the ADR templates — all of these are user-facing templates that the human fills in when starting a project. The install script should print a clear message listing which files still need to be filled in.

**Q: What is the relationship between the global CLAUDE.md and the project-template CLAUDE.md?**
A: Claude Code loads both files. The global `~/.claude/CLAUDE.md` (symlinked from `claude-config/CLAUDE.md`) contains infrastructure rules that apply everywhere. The project-level `CLAUDE.md` at the repo root contains project-specific context. They are additive — both are read every session, with the global file loaded first. Zone B in each file is purely human-maintained content that is never touched by infrastructure updates.

**Q: Will the stop-gate hook prevent session close forever if tests are broken?**
A: No. The stop-gate has a 120-second timeout — if tests take longer than 2 minutes, it exits 0 (allows stop). It also detects test framework configuration (pytest, npm test, make test) and skips if none is found. The guard against infinite loops (`stop_hook_active` check) prevents the hook from re-triggering when Claude is already trying to fix failures. If tests are genuinely broken and Claude cannot fix them, the agent can inform the user and the session can be ended manually via Ctrl+C.

**Q: What happens if a worker submits a PR that violates an ADR?**
A: The architecture-guardian agent returns FAIL with specific violations. The orchestrator then has three choices: (1) ask the CERIT worker to revise, (2) raise it with the user if the ADR itself might need updating, or (3) override if the user explicitly approves the deviation. The guardian never auto-rejects — it always reports back to the orchestrator, who decides. This preserves human judgment over architectural decisions.

**Q: How often should I run vault-health.sh?**
A: Weekly is the recommended cadence for active projects. The script is safe to run anytime — it only reads and writes the health report, never modifies vault content. For projects with high agent activity (multiple sessions per day), run it more frequently. For inactive projects, monthly is sufficient. Set up a cron job or use `/loop 7d bash vault-health.sh` in an active Claude Code session.

**Q: Should I use parallel-implement or implement-and-refine for a given task?**
A: Use `parallel-implement` when: the approach is unclear, you want creative diversity, multiple valid implementations exist, and you want the best one selected. Use `implement-and-refine` when: the approach is clear, acceptance criteria are specific and testable, and you want iterative quality improvement rather than approach diversity. For very important features, you can combine them: parallel-implement to find the best approach, then implement-and-refine to polish the winner.

**Q: The quality-check hook is running on every file write. Won't this slow things down?**
A: The hook runs the linter asynchronously from Claude's perspective but synchronously in execution — Claude doesn't proceed until the hook returns. Typical linter runs take 0.5-3 seconds. This is acceptable overhead because it prevents the much larger cost of accumulating lint errors and having to fix them at the end. For very large codebases where linting is slow, consider scoping the linter to the specific file being written rather than the entire project directory (modify `quality-check.py` to pass `file_path` to the linter instead of `cwd`).

**Q: Why `bypassPermissions` instead of `acceptEdits` or `default`?**
A: The user explicitly wants agents to run without interruption. `bypassPermissions` skips all permission prompts. The safety layer is the deny list of destructive shell patterns, not the permission dialog. This is appropriate for a controlled remote dev environment where the user is not sitting at the keyboard watching every action.

**Q: Can subagents (internal Claude Code subagents) also bypass permissions?**
A: Yes — when the parent session runs with `bypassPermissions`, subagents inherit that mode. The `permissionMode` in the subagent's frontmatter definition is ignored when the parent uses `bypassPermissions`. This is by design: the orchestrator's permission level propagates to all its children.

**Q: What if the implementing agent cannot fetch the model list during install?**
A: The install script should handle this gracefully: if the curl request fails (network, auth), print a warning and fall back to prompting the user to enter model names manually. Include the known CERIT model names from the CERIT documentation as default suggestions: `agentic`, `thinker`, `mini` are aliases that CERIT provides. The implementing agent should verify whether these aliases work and document this in the README.

**Q: Why is the librarian not on mini/fast model?**
A: The archivist makes decisions about where information belongs, how to merge it with existing content, and how to update hub pages. These are not simple append operations — a poor decision means knowledge is misrouted or lost. The retriever must distinguish between superficially relevant and actually relevant files. Both require genuine comprehension. Mini models optimised for speed will produce shallow, low-quality vault management. The CERIT_LIBRARIAN_MODEL should be a full reasoning-capable model.
