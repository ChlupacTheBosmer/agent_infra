# ───────────────────────────────────────────────────────────────
# ZONE A – PROJECT INFRASTRUCTURE NOTES
# Brief pointers to project-specific agent tooling.
# Usually needs little or no editing.
# ───────────────────────────────────────────────────────────────

## Project-level agents (in .claude/agents/)
Project-specific subagent definitions override global ones with the same name.
See .claude/agents/ for any agents defined specifically for this project.

## Project-level skills (in .claude/skills/)
Project-specific skills take precedence over global skills with the same name.
See .claude/skills/ for any skills specific to this project.

## Vault integration
Vault project name (for librarian-retrieve.sh and librarian-archive.sh): [FILL IN – must match vault/projects/<name>/]
Run before complex tasks: bash librarian-retrieve.sh "<task>" <vault-project-name>


# ───────────────────────────────────────────────────────────────
# ZONE B – PROJECT CONFIGURATION
#
# Fill in everything below. This is what the agent reads to
# understand your project. Be specific. Be concrete.
# Delete sections you don't need. Keep total under ~150 lines.
# ───────────────────────────────────────────────────────────────

## Project overview
<!-- What is this project? What problem does it solve? -->
<!-- What is the current primary goal? -->
[FILL IN]


## Tech stack
<!-- Primary language, framework, key libraries -->
<!-- Example: Python 3.11, PyTorch 2.3, ultralytics YOLO, -->
<!-- PostGIS for geodata, HPC via PBS scheduler -->
[FILL IN]


## Repository layout
<!-- Key directories and what lives in them -->
<!-- Example: -->
<!-- src/          – main source code -->
<!-- tests/        – pytest test suite -->
<!-- data/         – symlink to /data/project-name -->
<!-- notebooks/    – exploratory analysis -->
<!-- configs/      – training configuration YAMLs -->
[FILL IN]


## Build, test, and run commands
```bash
# Run tests
[FILL IN: e.g. pytest tests/ -v]

# Lint / format
[FILL IN: e.g. ruff check . && ruff format .]

# Type check
[FILL IN: e.g. mypy src/]

# Run the main pipeline / training
[FILL IN]

# Any other key commands
[FILL IN]
```


## Coding conventions
<!-- Things an agent needs to know to write code that fits in -->
<!-- Example: -->
<!-- - ruff formatting, 88-char line length -->
<!-- - type hints required on all public functions -->
<!-- - docstrings in Google style -->
<!-- - no bare except; always catch specific exceptions -->
<!-- - use pathlib.Path not os.path -->
[FILL IN]


## Current goals and priorities
<!-- What are you actively working on? What matters most right now? -->
<!-- Update this when priorities shift. Agents use this to make -->
<!-- decisions about what to focus on when not explicitly told. -->
[FILL IN]


## Key decisions already made
<!-- Architecture choices, approaches ruled out, and WHY -->
<!-- This prevents agents from re-litigating settled questions. -->
<!-- Example: We use DEIMv2 not YOLOv9 because of better small-object perf. -->
<!-- Example: Hard negative ratio is fixed at 30% – do not change. -->
[FILL IN]


## Known issues and gotchas
<!-- Things that trip up anyone new to this codebase -->
<!-- Example: Data loader assumes images pre-resized to 640px. -->
<!-- Example: Config YAML uses relative paths from project root. -->
[FILL IN]


## Out of scope / do not touch
<!-- Explicit list of things agents should NOT change or attempt -->
<!-- Example: Do not modify data/raw/ – those are immutable source files. -->
<!-- Example: Do not change the model architecture in model/backbone.py -->
<!--          without explicit instruction – it affects saved checkpoints. -->
[FILL IN]
