---
name: implement-and-refine
description: >
  Generator-evaluator loop: one CERIT worker implements, a second reviews
  against acceptance criteria, the first revises, repeat until quality bar
  is met or max rounds reached. Use for iterative refinement tasks where
  quality matters more than diversity of approaches. Complementary to
  parallel-implement: use this for refinement, use parallel-implement for
  approach diversity.
---

# Implement and Refine

Invoke by running:
  bash implement-and-refine.sh <task_spec_or_string> [branch] [max_rounds]

Default max_rounds: 3. Each round costs ~2x a single implementation.
The loop stops when the evaluator returns PASS or max_rounds is reached.

## When to use (vs parallel-implement)
- **implement-and-refine**: task has clear acceptance criteria, approach is
  known, quality/correctness is the goal. Best for bug fixes, well-specified
  features, and anything with measurable success criteria.
- **parallel-implement**: approach is non-obvious, want diversity of solutions,
  willing to trade time for choosing the best approach.

## When NOT to use
- Tasks without clear acceptance criteria (evaluator can't give useful feedback)
- Simple tasks where a single well-specified implementation is sufficient
- Tasks already using parallel-implement (don't double-nest these patterns)
