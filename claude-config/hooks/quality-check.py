#!/usr/bin/env python3
"""
PostToolUse hook – fires after Write, Edit, MultiEdit.
Detects and runs the project linter, injects output back to Claude
as additionalContext so linting errors are fixed immediately.

Never blocks (always exits 0). Only provides feedback via additionalContext.
"""
import json
import os
import sys
import subprocess
import shutil
from pathlib import Path


def detect_linter(cwd: str) -> tuple | None:
    """Detect which linter/formatter to run based on project config."""
    cwd_path = Path(cwd)

    # Python: ruff (preferred), then flake8, then pylint
    if (cwd_path / "pyproject.toml").exists() or (cwd_path / "setup.py").exists():
        if shutil.which("ruff"):
            return (["ruff", "check", "--output-format=concise", cwd], "ruff")
        if shutil.which("flake8"):
            return (["flake8", "--max-line-length=120", cwd], "flake8")

    # TypeScript/JavaScript: eslint
    if (cwd_path / "package.json").exists():
        if (cwd_path / ".eslintrc.json").exists() or (cwd_path / ".eslintrc.js").exists():
            npx = shutil.which("npx")
            if npx:
                return ([npx, "eslint", "--max-warnings=0", cwd], "eslint")

    # Go
    if list(cwd_path.glob("*.go")) or (cwd_path / "go.mod").exists():
        if shutil.which("golangci-lint"):
            return (["golangci-lint", "run", "--fast", cwd], "golangci-lint")

    return None


def run_type_check(cwd: str) -> str | None:
    """Run mypy if configured, return output or None."""
    cwd_path = Path(cwd)
    pyproject = cwd_path / "pyproject.toml"
    if not pyproject.exists():
        return None

    try:
        content = pyproject.read_text()
        if "[tool.mypy]" not in content:
            return None
    except Exception:
        return None

    if not shutil.which("mypy"):
        return None

    try:
        result = subprocess.run(
            ["mypy", "--no-error-summary", cwd],
            capture_output=True, text=True, timeout=30, cwd=cwd
        )
        if result.returncode != 0 and result.stdout.strip():
            lines = result.stdout.strip().split("\n")
            # Limit to first 20 type errors to avoid overwhelming context
            limited = "\n".join(lines[:20])
            if len(lines) > 20:
                limited += f"\n... ({len(lines) - 20} more type errors)"
            return limited
    except Exception:
        pass
    return None


def main():
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    cwd = hook_input.get("cwd", os.getcwd())
    file_path = hook_input.get("tool_input", {}).get("file_path", "")

    # Skip non-source files
    if file_path:
        skip_patterns = [".git/", "__pycache__", ".pyc", "node_modules/",
                         "/tmp/", ".log", ".json", ".yaml", ".yml", ".md",
                         ".txt", ".csv"]
        if any(p in file_path for p in skip_patterns):
            sys.exit(0)

    feedback_parts = []

    # Run linter
    linter_info = detect_linter(cwd)
    if linter_info:
        cmd, linter_name = linter_info
        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=30, cwd=cwd
            )
            output = (result.stdout + result.stderr).strip()
            if output and result.returncode != 0:
                lines = output.split("\n")
                limited = "\n".join(lines[:30])
                if len(lines) > 30:
                    limited += f"\n... ({len(lines)-30} more issues)"
                feedback_parts.append(
                    f"[{linter_name.upper()} – {result.returncode} issues found]\n{limited}"
                )
        except subprocess.TimeoutExpired:
            feedback_parts.append(f"[{linter_name.upper()}] Linter timed out (30s)")
        except Exception:
            pass  # Silently skip linter errors – never block on hook failure

    # Run type checker
    type_output = run_type_check(cwd)
    if type_output:
        feedback_parts.append(f"[MYPY – type errors]\n{type_output}")

    if feedback_parts:
        feedback = "\n\n".join(feedback_parts)
        feedback += "\n\nFix these issues before proceeding."
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": feedback
            }
        }
        print(json.dumps(output))

    sys.exit(0)  # Always exit 0 – quality-check never blocks


if __name__ == "__main__":
    main()
