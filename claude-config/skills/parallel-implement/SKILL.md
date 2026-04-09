---
name: parallel-implement
description: >
  Use when a task would benefit from multiple independent implementations
  being compared. Spawns 3 CERIT workers on the same task in parallel,
  then a CERIT judge picks the best. All cost is CERIT (free).
  Best for: complex algorithms, data pipelines, anything where approach
  matters and you want the best solution rather than the first solution.
---

# Parallel Implementation with Judge

Invoke by running:
  bash ~/scripts/parallel-implement.sh "<task>" <base-branch>

The task description must be self-contained – workers get no other context.
Always include in the task:
- What to implement (specific and precise)
- Where in the codebase (specific files/modules)
- Acceptance criteria (what does "correct" mean?)
- Any constraints (performance, API compatibility, style)

Wait for the script to complete. It takes 2-5x longer than a single
implementation but produces significantly better results for complex tasks.

Read the judge verdict when done and report the winner and scores to the user.

## When to use
- Task is non-trivial (>50 lines of new code expected)
- The approach or algorithm is not obvious
- Quality matters more than speed
- Core logic: data processing, training steps, API design

## When NOT to use
- Simple bug fixes with an obvious solution
- Configuration changes, documentation
- Anything touching shared state workers would conflict on
- Tasks where "correct" has only one obvious shape
