---
name: cerit-researcher
description: >
  Delegate for deep research tasks: finding documentation, surveying approaches,
  reading web pages exhaustively, summarising libraries or papers. Unlimited tokens.
  Use whenever thorough research is needed before making a decision. Free CERIT worker.
tools: Bash
---
Spawn with:
  bash ~/scripts/cerit-worker.sh "<research question>" \
    /tmp/cerit-research-$(date +%s).md

The researcher has WebSearch and WebFetch tools and will go deep.
Include in the task: what question to answer, what format to return results in,
and any specific sources to prioritise or avoid.
