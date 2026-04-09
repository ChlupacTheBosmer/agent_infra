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
echo "Parallel Implementation – $TIMESTAMP"
echo "Task: $TASK"
echo "Base branch: $BASE_BRANCH"
echo "Workers: $N_WORKERS"
echo "Results dir: $RESULTS_DIR"
echo "================================================================"

# Track all worktrees and PIDs for cleanup
declare -a WORKER_PIDS=()
declare -a WORKER_BRANCHES=()
declare -a WORKER_WORKTREES=()

# ── Cleanup function – always runs on exit ──────────────────────────────────
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
    echo $$ # return current PID as placeholder – wait will handle it
    return 1
  fi

  local TASK_FILE=$(mktemp /tmp/cerit-task-XXXXXX.md)
  cat > "$TASK_FILE" << TASKEOF
# Parallel Implementation Task – Attempt $WORKER_ID of $N_WORKERS
# Run: $TIMESTAMP

## Context
You are one of $N_WORKERS agents implementing the SAME task independently.
Your implementation will be judged against the others on:
- Correctness (tests pass, task fully solved)
- Code quality (readable, maintainable, follows codebase conventions)
- Robustness (edge cases handled, error handling)
- Elegance (appropriately simple or appropriately thorough)

Write the BEST code you can. Be creative where appropriate. Don't be
conservative just to be safe – make real design decisions.

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
TEST_RESULT: (pass/fail – include number of tests run)
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

# ── Phase 2: Spawn CERIT judge ───────────────────────────────────────────────
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
# Judge Task – Parallel Implementation Evaluation
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
Do NOT rely solely on worker self-reports – they may be inaccurate.
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
  attempt-1: <X>/10 – <one sentence reason>
  attempt-2: <X>/10 – <one sentence reason>
  attempt-3: <X>/10 – <one sentence reason>
RATIONALE: (2-4 sentences explaining why the winner is best)
IMPROVEMENTS: (specific things the orchestrator should ask the winner to fix, if any)
FAILED_WORKERS: (list any workers that failed or had test failures)
JUDGEEOF

# Judge uses thinker model – picking the best implementation requires real reasoning
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
  echo "NOTE: Nothing to commit – winner may have had no changes, or changes already merged."
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
