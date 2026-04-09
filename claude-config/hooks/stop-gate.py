#!/usr/bin/env python3
"""
Stop hook – fires when Claude attempts to stop/close the session.
Runs the project test suite. If tests fail, blocks the stop (exit code 2)
and injects failure details so Claude fixes them before closing.

Uses stop_hook_active guard to prevent infinite loops.
"""
import json
import os
import sys
import subprocess
import shutil
from pathlib import Path


def detect_test_command(cwd: str) -> list | None:
    """Detect the project test command from config files."""
    cwd_path = Path(cwd)

    # Python: pytest
    if (cwd_path / "pyproject.toml").exists():
        try:
            content = (cwd_path / "pyproject.toml").read_text()
            if "[tool.pytest" in content or "pytest" in content:
                if shutil.which("pytest"):
                    return ["pytest", "--tb=short", "-q", "--no-header"]
        except Exception:
            pass

    if (cwd_path / "pytest.ini").exists() or (cwd_path / "setup.cfg").exists():
        if shutil.which("pytest"):
            return ["pytest", "--tb=short", "-q", "--no-header"]

    # Node/TypeScript
    if (cwd_path / "package.json").exists():
        try:
            import json as _json
            pkg = _json.loads((cwd_path / "package.json").read_text())
            if "test" in pkg.get("scripts", {}):
                npm = shutil.which("npm")
                if npm:
                    return [npm, "test", "--", "--passWithNoTests"]
        except Exception:
            pass

    # Makefile with test target
    if (cwd_path / "Makefile").exists():
        try:
            content = (cwd_path / "Makefile").read_text()
            if "test:" in content or "test :" in content:
                if shutil.which("make"):
                    return ["make", "test"]
        except Exception:
            pass

    return None


def main():
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    # CRITICAL: prevent infinite loop
    if hook_input.get("stop_hook_active"):
        sys.exit(0)

    cwd = hook_input.get("cwd", os.getcwd())

    test_cmd = detect_test_command(cwd)
    if not test_cmd:
        # No test suite found – don't block, just let it stop
        sys.exit(0)

    try:
        result = subprocess.run(
            test_cmd,
            capture_output=True, text=True,
            timeout=120,  # 2 min max for stop gate
            cwd=cwd
        )

        if result.returncode == 0:
            # Tests pass – allow stop
            sys.exit(0)

        # Tests failed – block the stop
        output = (result.stdout + result.stderr).strip()
        lines = output.split("\n")

        # Show last 40 lines (most relevant: failures are at the end)
        relevant = "\n".join(lines[-40:]) if len(lines) > 40 else output

        error_msg = (
            f"STOP BLOCKED: Tests are failing. Fix before closing this session.\n\n"
            f"Command: {' '.join(test_cmd)}\n"
            f"Exit code: {result.returncode}\n\n"
            f"Test output (last 40 lines):\n{relevant}\n\n"
            f"Do not use /clear to escape – fix the failures."
        )

        print(json.dumps({
            "decision": "block",
            "reason": error_msg
        }))
        sys.exit(2)

    except subprocess.TimeoutExpired:
        # Test suite timed out – allow stop (don't punish for slow tests)
        sys.exit(0)
    except Exception:
        # Any other error – allow stop (don't block on hook failure)
        sys.exit(0)


if __name__ == "__main__":
    main()
