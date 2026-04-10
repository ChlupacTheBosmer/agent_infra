#!/bin/bash
# CERIT Worker Spawner
# Usage: cerit-worker.sh <task_or_spec_file> <output_file> [branch_name] [max_turns]
#
# <task_or_spec_file> can be:
#   - A path to a task YAML spec file (tasks/task-NNN.yaml) – PREFERRED
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
TASK_FILE=$(mktemp /tmp/cerit-task-XXXXXX)

# ── Parse task input: YAML spec file or inline string ───────────────────────
if [ -f "$TASK_INPUT" ] && (echo "$TASK_INPUT" | grep -qE '\.(yaml|yml)$'); then
  # YAML spec file – parse and format into task markdown
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
# Worker Task – $TIMESTAMP
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
# Worker Task – $TIMESTAMP

## Your assignment
$TASK

## Mandatory workflow – follow this sequence exactly

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

fi

echo "[cerit-worker] Starting task at $TIMESTAMP"
echo "[cerit-worker] Output: $OUTPUT_FILE"
echo "[cerit-worker] Branch: ${BRANCH:-none}"

# ── Write a launcher script and execute it in background via nohup ─────────
# This returns immediately — the claude process runs detached.
# The orchestrator must poll $OUTPUT_FILE until STATUS: appears.
LAUNCHER=$(mktemp /tmp/cerit-launch-XXXXXX)
cat > "$LAUNCHER" << LAUNCHEOF
#!/bin/bash
ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" \\
ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" \\
ANTHROPIC_MODEL="${CERIT_CODER_MODEL}" \\
ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" \\
ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_CODER_MODEL}" \\
ANTHROPIC_DEFAULT_HAIKU_MODEL="${CERIT_FAST_MODEL}" \\
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \\
claude -p "\$(cat '${TASK_FILE}')" \\
  --allowedTools "Read,Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch" \\
  --max-turns "${MAX_TURNS}" \\
  --dangerously-skip-permissions \\
  --output-format text \\
  >> "${HOME}/logs/cerit-workers.log" 2>&1
EXIT_CODE=\$?
rm -f "${TASK_FILE}" "${LAUNCHER}"
if [ \$EXIT_CODE -ne 0 ] && ! grep -q "^STATUS:" "${OUTPUT_FILE}" 2>/dev/null; then
  printf "STATUS: failed\nSUMMARY: Worker exited with code %s\nISSUES: Check %s/logs/cerit-workers.log\n" \
    "\$EXIT_CODE" "${HOME}" >> "${OUTPUT_FILE}"
fi
LAUNCHEOF
chmod +x "$LAUNCHER"

nohup "$LAUNCHER" &>/dev/null &
WORKER_PID=$!

echo "[cerit-worker] Worker launched (PID $WORKER_PID)"
echo "[cerit-worker] POLL: while ! grep -q '^STATUS:' '$OUTPUT_FILE' 2>/dev/null; do sleep 30; echo 'still waiting...'; done && cat '$OUTPUT_FILE'"
