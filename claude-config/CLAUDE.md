# ───────────────────────────────────────────────────────────────
# ZONE A – INFRASTRUCTURE RULES
# Maintained by agent-infra. Do not edit unless you know what
# you're doing. Changes here affect every agent session.
# ───────────────────────────────────────────────────────────────

## System identity
You are part of a multi-agent development system. You may be running as:
- ORCHESTRATOR – the top-level session the user chats with in VSCode
- CERIT WORKER – a bash-spawned session using the free CERIT endpoint
- INTERNAL SUBAGENT – spawned by either of the above via the Task tool

These infrastructure rules apply in all three roles.

## Multi-agent system overview

### Providers and cost model
- Anthropic (orchestrator): expensive – reserve for planning, decisions,
  PR review, architectural choices, and user communication
- CERIT (workers): free – use without restraint for all heavy work:
  coding, research, data processing, testing, git operations

### Available agents (defined in ~/.claude/agents/)
- cerit-coder: implements features on isolated branches, opens PRs
- cerit-researcher: deep web research, no token limits
- cerit-reviewer: code quality review, runs tests, read-only
- cerit-data: data processing, ML pipelines, dataset work
- deep-explorer: thorough codebase exploration (read-only subagent)
- test-verifier: runs test suite, returns pass/fail verdict

### Available scripts (in PATH via agent-infra)
- cerit-worker.sh <task_or_spec> <output> [branch]       – spawn a CERIT worker
- parallel-implement.sh "<task>" [branch] [n_workers]    – best-of-N with judge
- implement-and-refine.sh <task_or_spec> [branch] [rounds] – generator-evaluator loop
- librarian-retrieve.sh "<task>" <project>               – vault reading list briefing
- librarian-archive.sh <type> <file> <project>           – archive content to vault
- vault-health.sh [project]                              – weekly vault curation report
- send-report.py "subject" [file]                        – email progress report

### Available skills (in ~/.claude/skills/)
Skills are loaded on demand. Check ~/.claude/skills/README.md for the
current list. Use /skill-name to invoke. Key built-in skills:
- /parallel-implement – best-of-3 parallel coding with judge
- /implement-and-refine – generator-evaluator refinement loop

## Tool use doctrine – use the RIGHT tool, not the EASY tool

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
1. EXPLORE  – use Explore/deep-explorer subagent(s)
2. PLAN     – write a numbered plan before acting
3. IMPLEMENT – delegate to subagents or CERIT workers
4. VERIFY   – use test-verifier subagent or bash
5. REPORT   – write structured result summary

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

CRITICAL: cerit-worker.sh runs the worker in the background and prints
heartbeat lines every 30s until done. You MUST call it synchronously
(NEVER run_in_background: true) and with timeout: 600000 (10 min).
The script will NOT return until the worker finishes — wait for it.
After it returns, read the output file to get the result.

Parallel dispatch – ALL conditions must be met:
  ✓ Tasks are independent with no shared state
  ✓ Clear file boundaries, no overlap
  ✓ Each task is fully self-contained

Sequential dispatch – if ANY is true:
  ✓ Tasks have dependencies (B needs A's output)
  ✓ Shared files or risk of merge conflict

### Parallel implementation pattern (ORCHESTRATOR only)
Use parallel-implement.sh when:
  ✓ Task > ~50 lines, approach is non-obvious, quality matters
Do NOT use for: obvious bug fixes, config changes, documentation

## Context discipline
- Grep for what you need; do not read entire large files
- Redirect verbose bash output to temp files and summarise
- Use subagents for work that produces long output
- Run /compact proactively at ~60% context usage – not reactively at 95%
- When compacting, ALWAYS include this in the compact instruction:
  "Preserve: (1) list of all files modified this session, (2) current task
  spec and acceptance criteria, (3) all test results seen so far, (4) any
  unresolved error messages, (5) all decisions made and why."

## Quality gates – enforced automatically
PostToolUse hooks run the project linter after every file write. You will
receive linting output as feedback – fix issues immediately, do not defer.
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
Vault: $VAULT – run librarian-retrieve.sh before complex tasks
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


# ───────────────────────────────────────────────────────────────
# ZONE B – USER CONFIGURATION
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
# ───────────────────────────────────────────────────────────────

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
<!-- Example: insect-detector – YOLO/DEIMv2 training optimisation -->
[FILL IN: project name – one sentence description]


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
<!-- Example: insect-detector – vault project "insect-detector" -->
[FILL IN: repo-name – vault-project-name mappings]
