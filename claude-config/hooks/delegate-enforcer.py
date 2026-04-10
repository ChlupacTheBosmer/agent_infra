#!/usr/bin/env python3
"""
PreToolUse hook – fires before Write, Edit, MultiEdit.

ORCHESTRATOR DELEGATION ENFORCEMENT:
If the orchestrator (Anthropic session) attempts to write a substantial code
file directly, block it and instruct it to use cerit-worker.sh instead.

Workers (CERIT sessions) are exempt: they SHOULD write code directly.
Workers are identified by the CERIT base URL in ANTHROPIC_BASE_URL.

Exit codes:
  0 → allow
  2 → block (Claude receives the message and must change approach)
"""
import json
import os
import sys
from pathlib import Path

# Extensions that count as "code files" requiring CERIT delegation
CODE_EXTENSIONS = {
    # .sh excluded — shell scripts are infrastructure, not delegatable code
    ".py", ".js", ".ts", ".jsx", ".tsx", ".go", ".rs", ".java",
    ".c", ".cpp", ".h", ".hpp", ".cs", ".rb", ".php", ".swift",
    ".kt", ".scala", ".r", ".m", ".sh", ".bash",
}

# Files the orchestrator IS allowed to write directly (task specs, docs, config)
EXEMPT_PATTERNS = [
    # Agent infra repo is always editable (infrastructure, not user code)
    "agent_infra/", "claude-config/", "scripts/",
    "CLAUDE.md", "tasks/", ".yaml", ".yml", ".md", ".txt",
    ".json", ".toml", ".cfg", ".ini", ".env", ".log",
    "vault/", ".gitignore", "Makefile", "Dockerfile",
    "requirements", "pyproject", "setup.py", "setup.cfg",
    "package.json", "tsconfig", ".eslint",
]

MIN_LINES_TO_BLOCK = 30  # Below this, orchestrator can write directly


def is_worker_context() -> bool:
    """True if running inside a CERIT worker (not the orchestrator)."""
    base_url = os.environ.get("ANTHROPIC_BASE_URL", "")
    return "e-infra.cz" in base_url


def is_exempt(file_path: str) -> bool:
    """True if this file is exempt from delegation enforcement."""
    for pattern in EXEMPT_PATTERNS:
        if pattern in file_path:
            return True
    return False


def is_code_file(file_path: str) -> bool:
    """True if the file extension marks it as source code."""
    return Path(file_path).suffix.lower() in CODE_EXTENSIONS


def count_lines(content: str) -> int:
    return len(content.strip().splitlines())


def main():
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, Exception):
        sys.exit(0)

    # Workers may always write code
    if is_worker_context():
        sys.exit(0)

    tool_name = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input", {})
    file_path = tool_input.get("file_path", "")

    if not file_path:
        sys.exit(0)

    if is_exempt(file_path):
        sys.exit(0)

    if not is_code_file(file_path):
        sys.exit(0)

    # Check content size
    content = tool_input.get("content", "") or tool_input.get("new_string", "")
    lines = count_lines(content)

    if lines < MIN_LINES_TO_BLOCK:
        sys.exit(0)

    # Block: orchestrator is about to write a substantial code file directly
    message = (
        f"DELEGATION REQUIRED — do not write '{Path(file_path).name}' directly.\n\n"
        f"This file has {lines} lines of code. The orchestrator must delegate "
        f"implementation to a CERIT worker, not write code itself.\n\n"
        f"Required action:\n"
        f"  1. Write a task spec to tasks/task-NNN.yaml\n"
        f"  2. Run: cerit-worker.sh tasks/task-NNN.yaml /tmp/result-$(date +%s).md\n"
        f"  3. Read the output file when the worker finishes\n\n"
        f"The orchestrator's role is to PLAN and DIRECT, not to implement.\n"
        f"CERIT workers are free and unlimited — use them."
    )
    print(json.dumps({"decision": "block", "reason": message}))
    sys.exit(2)


if __name__ == "__main__":
    main()
