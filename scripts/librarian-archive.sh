#!/bin/bash
# Librarian Archivist – receives content and files it into the vault
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

TASK_FILE=$(mktemp /tmp/librarian-archive-task-XXXXXX)

cat > "$TASK_FILE" << TASKEOF
# Librarian Archive Task – $TIMESTAMP

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

# Librarian uses a full thinking model – NOT mini. Vault organisation is high-responsibility.
ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" \
ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" \
ANTHROPIC_MODEL="${CERIT_LIBRARIAN_MODEL}" \
ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" \
ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_LIBRARIAN_MODEL}" \
ANTHROPIC_DEFAULT_HAIKU_MODEL="${CERIT_LIBRARIAN_MODEL}" \
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
claude -p "$(cat "$TASK_FILE")" \
  --allowedTools "Read,Write,Edit,Glob,Grep,Bash" \
  --max-turns 40 \
  --dangerously-skip-permissions \
  --output-format text \
  >> "${HOME}/logs/librarian.log" 2>&1

EXIT_CODE=$?
rm -f "$TASK_FILE"

if [ $EXIT_CODE -ne 0 ]; then
  echo "[librarian-archive] WARNING: Archive process exited with $EXIT_CODE" >&2
  # Do not propagate error – archival failures should never break the calling process
fi

exit 0
