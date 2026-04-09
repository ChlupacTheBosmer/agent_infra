#!/bin/bash
# Vault Health Agent – periodic curation of the second brain
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

TASK_FILE=$(mktemp /tmp/vault-health-task-XXXXXX)

cat > "$TASK_FILE" << TASKEOF
# Vault Health Check – $DATE
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

# Vault Health Report – $DATE

## Executive summary
(2-3 sentences: overall vault health, most urgent issues)

## Index issues (fix these first – they break navigation)
- [ ] [specific actionable fix]

## Stale hub pages
- [ ] [project]: INDEX.md says "X" but CHANGELOG shows "Y" – update needed

## Content gaps (atlas/ documentation missing)
- [ ] [project] uses [method] – document in atlas/methods/[method].md

## Inbox backlog
- [ ] [n] files in inbox/ older than 14 days – review and file or delete

## Stale known-failures (may be resolved)
- [ ] [project]/context/known-failures.md: "[issue]" – verify if still relevant

## Potential duplicates
- [ ] [file1] and [file2] – may be the same topic

## What's healthy (no action needed)
(brief list of vault areas that look good)

## Recommended next actions
1. [highest priority action]
2. [second priority]
3. [third priority]
TASKEOF

ANTHROPIC_BASE_URL="${CERIT_BASE_URL}" \
ANTHROPIC_AUTH_TOKEN="${CERIT_API_KEY}" \
ANTHROPIC_MODEL="${CERIT_LIBRARIAN_MODEL}" \
ANTHROPIC_DEFAULT_OPUS_MODEL="${CERIT_THINKER_MODEL}" \
ANTHROPIC_DEFAULT_SONNET_MODEL="${CERIT_LIBRARIAN_MODEL}" \
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
claude -p "$(cat "$TASK_FILE")" \
  --allowedTools "Read,Write,Bash,Glob,Grep" \
  --max-turns 30 \
  --dangerously-skip-permissions \
  --output-format text \
  >> "$LOG" 2>&1

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
