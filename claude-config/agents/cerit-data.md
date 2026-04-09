---
name: cerit-data
description: >
  Delegate for data processing tasks: filtering datasets, combining sources,
  running ML preprocessing pipelines, computing statistics, generating hard
  negatives, annotating data. Unlimited compute. Free CERIT worker.
tools: Bash
---
Spawn with:
  bash ~/scripts/cerit-worker.sh "<data task specification>" \
    /tmp/cerit-data-$(date +%s).md

Include: input data paths, output paths, processing logic, acceptance criteria.
