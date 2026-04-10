#!/usr/bin/env python3
"""
SubagentStop hook – fires when an internal Claude Code subagent finishes.
Extracts the subagent's final result and archives it to the vault.
Runs async so it does not delay the subagent result returning to the parent.
"""
import json
import os
import sys
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path

# CERIT workers must not archive — only the orchestrator session archives.
if "e-infra.cz" in os.environ.get("ANTHROPIC_BASE_URL", ""):
    sys.exit(0)


def main():
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    # Extract subagent info
    agent_id = hook_input.get("agent_id", "unknown")
    agent_type = hook_input.get("agent_type", "subagent")
    transcript_path = hook_input.get("transcript_path", "")
    cwd = hook_input.get("cwd", "")
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")

    # Build archive content
    archive_content = f"""# Subagent Log – {timestamp}
Agent ID: {agent_id}
Agent type: {agent_type}
Working directory: {cwd}
"""

    # Try to read final message from transcript
    if transcript_path and os.path.exists(transcript_path):
        try:
            lines = open(transcript_path).readlines()
            # Get last few lines (the final exchange)
            for line in lines[-10:]:
                try:
                    entry = json.loads(line)
                    if entry.get("type") == "assistant":
                        content = entry.get("message", {}).get("content", "")
                        if isinstance(content, list):
                            text = " ".join(
                                c.get("text", "") for c in content
                                if isinstance(c, dict) and c.get("type") == "text"
                            )
                        else:
                            text = str(content)
                        if text.strip():
                            archive_content += f"\n## Subagent final output\n{text.strip()[:1000]}\n"
                            break
                except json.JSONDecodeError:
                    continue
        except Exception:
            pass

    with tempfile.NamedTemporaryFile(
        mode='w', suffix='.md', prefix='subagent-archive-', delete=False
    ) as f:
        f.write(archive_content)
        tmp_path = f.name

    try:
        infra_dir = os.environ.get("AGENT_INFRA_DIR", str(Path.home() / "agent-infra"))
        script = os.path.join(infra_dir, "scripts", "librarian-archive.sh")

        if os.path.exists(script):
            # Detect project from cwd
            project = Path(cwd).name if cwd else "unknown"
            subprocess.Popen(
                ["bash", script, "subagent-log", tmp_path, project],
                stdout=open(os.path.join(Path.home(), "logs", "librarian.log"), "a"),
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
    except Exception as e:
        log_path = Path.home() / "logs" / "librarian-hook-errors.log"
        log_path.parent.mkdir(exist_ok=True)
        with open(log_path, "a") as f:
            f.write(f"{timestamp}: SubagentStop hook error: {e}\n")

    sys.exit(0)


if __name__ == "__main__":
    main()
