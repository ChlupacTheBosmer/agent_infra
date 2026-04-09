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
echo "Implement-and-Refine – $TIMESTAMP"
echo "Max rounds: $MAX_ROUNDS"
echo "Results: $RESULTS_DIR"
echo "================================================================"

# Helper: spawn a CERIT implementer
run_implementer() {
  local ROUND=$1
  local CRITIQUE_FILE="${2:-}"
  local OUTPUT="$RESULTS_DIR/impl-round-${ROUND}.md"
  local LOG="${HOME}/logs/refine-impl-${TIMESTAMP}-r${ROUND}.log"
  local TASK_FILE=$(mktemp /tmp/refine-impl-XXXXXX)

  cat > "$TASK_FILE" << TASKEOF
# Implementation Task – Round $ROUND of $MAX_ROUNDS
# Timestamp: $TIMESTAMP

## Task
$TASK_INPUT

$([ -n "$CRITIQUE_FILE" ] && [ -f "$CRITIQUE_FILE" ] && echo "## Evaluator critique from previous round (address ALL points)
$(cat "$CRITIQUE_FILE")

IMPORTANT: Do not just acknowledge the critique – actually fix each issue.")
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

  echo "[refine] Round $ROUND – implementer starting..."

  ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" \
  ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" \
  ANTHROPIC_MODEL="${CERIT_CODER_MODEL}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_CODER_MODEL}" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="${CERIT_FAST_MODEL}" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  claude -p "$(cat "$TASK_FILE")" \
    --allowedTools "Read,Edit,Write,Bash,Glob,Grep" \
    --max-turns 60 \
    --dangerously-skip-permissions \
    --output-format text \
    >> "$LOG" 2>&1

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
  local TASK_FILE=$(mktemp /tmp/refine-eval-XXXXXX)

  cat > "$TASK_FILE" << TASKEOF
# Evaluation Task – Round $ROUND
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
- Issue 1: [specific, actionable – what file/function, what's wrong, how to fix]
- Issue 2: [...]
PRIORITY: (which issues are blocking vs nice-to-have)
TASKEOF

  echo "[refine] Round $ROUND – evaluator starting..."

  # Evaluator uses thinker model – needs good judgment
  ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" \
  ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" \
  ANTHROPIC_MODEL="${CERIT_THINKER_MODEL}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_CODER_MODEL}" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="${CERIT_FAST_MODEL}" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  claude -p "$(cat "$TASK_FILE")" \
    --allowedTools "Read,Bash,Glob,Grep" \
    --max-turns 25 \
    --dangerously-skip-permissions \
    --output-format text \
    >> "$LOG" 2>&1

  rm -f "$TASK_FILE"
  echo "[refine] Round $ROUND evaluator done. Output: $OUTPUT"
  echo "$OUTPUT"
}

# ── Main refinement loop ────────────────────────────────────────────────────

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

  # FAIL – prepare for next round
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
  ARCHIVE_FILE=$(mktemp /tmp/refine-archive-XXXXXX)
  cat > "$ARCHIVE_FILE" << ARCHEOF
# Implement-and-Refine Session – $TIMESTAMP
Rounds: $ROUND_NUM / $MAX_ROUNDS
Final status: $FINAL_STATUS
Task: $TASK_INPUT
Results dir: $RESULTS_DIR
ARCHEOF
  librarian-archive.sh worker-result "$ARCHIVE_FILE" "general" &
  rm -f "$ARCHIVE_FILE"
fi
