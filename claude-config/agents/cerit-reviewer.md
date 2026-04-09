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
