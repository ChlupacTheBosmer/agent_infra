---
name: cerit-coder
description: >
  Delegate here for ANY coding task: implementing features, writing scripts,
  fixing bugs, refactoring. Works on an isolated git branch and opens a PR.
  Use for tasks producing more than 30 lines of code. Free and unlimited tokens.
  CERIT-powered worker – spawned via bash, not native subagent.
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
