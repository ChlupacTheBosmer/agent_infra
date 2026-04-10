#!/bin/bash
# CERIT Worker Spawner
# Usage: cerit-worker.sh <task_or_spec_file> <output_file> [branch_name] [max_turns]
#
# <task_or_spec_file> can be:
#   - A path to a task YAML spec file (tasks/task-NNN.yaml) – PREFERRED
#   - An inline task description string
#
# ORCHESTRATOR: always call via Bash with run_in_background=true.
# The script blocks until the worker exits; the notification fires on completion.
# Read the output file when notified.

set -euo pipefail

TASK_INPUT="$1"
OUTPUT_FILE="$2"
BRANCH="${3:-}"
MAX_TURNS="${4:-80}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TASK_FILE=$(mktemp /tmp/cerit-task-XXXXXX)

# ── Parse task input: YAML spec file or inline string ───────────────────────
if [ -f "$TASK_INPUT" ] && (echo "$TASK_INPUT" | grep -qE '\.(yaml|yml)$'); then
  # YAML spec file – parse and format into task prompt
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
    echo "[cerit-worker] Fetching vault briefing for: $VAULT_PROJECT"
    BRIEFING_PATH=$(librarian-retrieve.sh "$TASK_TITLE" "$VAULT_PROJECT" 2>/dev/null || true)
    if [ -n "$BRIEFING_PATH" ] && [ -f "$BRIEFING_PATH" ]; then
      BRIEFING_CONTENT="$(cat "$BRIEFING_PATH")"
    fi
  fi

  cat > "$TASK_FILE" << TASKEOF
# Worker Task – $TIMESTAMP
# Spec: $SPEC_FILE

## Task specification
\`\`\`yaml
$SPEC_CONTENT
\`\`\`

## Rules
- Do NOT spawn subagents or use the Agent tool. Work entirely inline.
- Use Read, Glob, Grep to explore. Use Write/Edit to implement.

## Your assignment
$TASK_TITLE (type: $TASK_TYPE)

$([ -n "$BRIEFING_CONTENT" ] && echo "## Vault context (read these files first)
$BRIEFING_CONTENT
")
$([ -n "$BRANCH" ] && echo "## Git context
- Base branch: main
- Your branch: $BRANCH
- Create it fresh: git checkout -b $BRANCH
- After work: git add -A && git commit && git push && gh pr create --fill --base main
")
## Output format (write to $OUTPUT_FILE when done)
STATUS: done|failed|needs_review|needs_clarification
BRANCH: ${BRANCH:-none}
PR: (URL if opened, else none)
SUMMARY: (3-5 sentences: what you built/changed, key decisions made)
ISSUES: (anything unexpected or requiring orchestrator attention)
ARTEFACTS: (key files created or modified, test results summary)
NEXT: (what should happen next)
TASKEOF

else
  # Inline task string
  TASK="$TASK_INPUT"
  cat > "$TASK_FILE" << TASKEOF
# Worker Task – $TIMESTAMP

## Your assignment
$TASK

## Rules
- Do NOT spawn subagents or use the Agent tool. Work entirely inline.
- Use Read, Glob, Grep to explore. Use Write/Edit to implement.
- Do everything in this single session.

$([ -n "$BRANCH" ] && echo "## Git context
- Your branch: $BRANCH
- Create: git checkout -b $BRANCH
- After work: git add -A && git commit && git push && gh pr create --fill --base main
")
## Output format (write to $OUTPUT_FILE when done)
STATUS: done|failed|needs_review|needs_clarification
BRANCH: ${BRANCH:-none}
PR: (URL if opened, else none)
SUMMARY: (3-5 sentences: what you built/changed, key decisions made)
ISSUES: (anything unexpected or requiring orchestrator attention)
ARTEFACTS: (key files created or modified, test results summary)
NEXT: (what should happen next)
TASKEOF
fi

echo "[cerit-worker] Starting task at $TIMESTAMP"
echo "[cerit-worker] Output: $OUTPUT_FILE"
echo "[cerit-worker] Branch: ${BRANCH:-none}"
echo "[cerit-worker] Model: ${CERIT_CODER_MODEL}"

# ── Run claude synchronously (orchestrator calls this via run_in_background=true) ──
export PATH="${PATH}"
ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" \
ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" \
ANTHROPIC_MODEL="${CERIT_CODER_MODEL}" \
ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" \
ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_CODER_MODEL}" \
ANTHROPIC_DEFAULT_HAIKU_MODEL="${CERIT_FAST_MODEL}" \
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
claude -p "$(cat "$TASK_FILE")" \
  --allowedTools "Read,Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch" \
  --max-turns "${MAX_TURNS}" \
  --dangerously-skip-permissions \
  --output-format text \
  >> "${HOME}/logs/cerit-workers.log" 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ] && ! grep -q "^STATUS:" "${OUTPUT_FILE}" 2>/dev/null; then
  printf "STATUS: failed\nSUMMARY: Worker exited with code %s\nISSUES: Check %s/logs/cerit-workers.log\n" \
    "$EXIT_CODE" "${HOME}" >> "${OUTPUT_FILE}"
fi

rm -f "$TASK_FILE"
echo "[cerit-worker] Done (exit $EXIT_CODE). Output at: $OUTPUT_FILE"
