#!/bin/bash
# Librarian Retriever – explores vault and returns a reading list briefing
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
ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" \
ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" \
ANTHROPIC_MODEL="${CERIT_LIBRARIAN_MODEL}" \
ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" \
ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_LIBRARIAN_MODEL}" \
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
claude -p "$(cat "$TASK_FILE")" \
  --allowedTools "Read,Write,Glob,Grep" \
  --max-turns 25 \
  --dangerously-skip-permissions \
  --output-format text \
  >> "${HOME}/logs/librarian.log" 2>&1

rm -f "$TASK_FILE"

if [ -f "$OUTPUT" ]; then
  echo "[librarian-retrieve] Briefing written to: $OUTPUT"
  echo "$OUTPUT"  # Print path so caller can read it
else
  echo "[librarian-retrieve] WARNING: No briefing written" >&2
  exit 1
fi
