# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for this project.
ADRs are read by the architecture-guardian agent before every PR merge to
prevent architectural drift in multi-agent codebases.

## Format

Each ADR is a markdown file named `adr-NNN-short-title.md` where NNN is a
zero-padded sequential number (001, 002, etc.).

## Writing effective ADRs

An ADR must be machine-readable as well as human-readable. Write it so that
an LLM can definitively answer: "Does this code change comply with this decision?"

Good ADRs are:
- **Specific**: "All database queries go through the Repository layer" not "use clean architecture"
- **Checkable**: the guardian can look at code and say yes or no
- **Scoped**: one decision per ADR, not a bundle of principles
- **Consequential**: captures decisions that would be hard to reverse

## What to capture

- Module/layer boundaries and what can cross them
- Which libraries/frameworks are approved (and which are banned)
- Interface contracts between components
- Files or directories that must not be modified without explicit approval
- Performance constraints (e.g., "no synchronous database calls in request handlers")
- Security requirements (e.g., "all user input must be validated through pydantic")
