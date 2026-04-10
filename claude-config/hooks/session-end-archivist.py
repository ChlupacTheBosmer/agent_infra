#!/usr/bin/env python3
"""
Stop hook – fires when a Claude Code session ends.
Reads the session JSONL transcript, extracts meaningful content,
and calls the librarian archivist to archive it to the vault.

Configured in ~/.claude/settings.json as an async Stop hook so it
does not block the session from closing.
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

def parse_transcript(transcript_path: str) -> dict:
    """Extract structured content from a Claude Code JSONL transcript."""
    messages = []
    summary = ""
    cwd = ""

    try:
        with open(transcript_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    entry_type = entry.get("type", "")

                    # Extract summary from first line if present
                    if entry_type == "summary" and not summary:
                        summary = entry.get("summary", "")

                    # Collect user messages (conversation content)
                    elif entry_type == "user":
                        content = entry.get("message", {}).get("content", "")
                        if isinstance(content, list):
                            text = " ".join(
                                c.get("text", "") for c in content
                                if isinstance(c, dict) and c.get("type") == "text"
                            )
                        else:
                            text = str(content)
                        if text.strip():
                            messages.append({"role": "user", "text": text.strip()[:500]})

                    # Collect assistant responses (decisions, plans)
                    elif entry_type == "assistant":
                        content = entry.get("message", {}).get("content", "")
                        if isinstance(content, list):
                            text = " ".join(
                                c.get("text", "") for c in content
                                if isinstance(c, dict) and c.get("type") == "text"
                            )
                        else:
                            text = str(content)
                        if text.strip():
                            messages.append({"role": "assistant", "text": text.strip()[:800]})

                    # Track bash commands run (agent actions)
                    elif entry_type == "tool_use" and entry.get("name") == "Bash":
                        cmd = entry.get("input", {}).get("command", "")
                        if cmd:
                            messages.append({"role": "action", "text": f"bash: {cmd[:200]}"})

                except json.JSONDecodeError:
                    continue

    except FileNotFoundError:
        return {"summary": "Transcript not found", "messages": [], "cwd": ""}

    return {
        "summary": summary,
        "messages": messages[-40:],  # keep last 40 exchanges to avoid huge inputs
        "cwd": cwd,
        "transcript_path": transcript_path,
    }


def detect_project(cwd: str) -> str:
    """Try to detect the project name from the working directory."""
    if not cwd:
        return "unknown"
    path = Path(cwd)
    # Try to find a CLAUDE.md with vault project mapping
    claude_md = path / "CLAUDE.md"
    if claude_md.exists():
        content = claude_md.read_text()
        for line in content.splitlines():
            if "Vault project name" in line or "vault project" in line.lower():
                # Extract the value after the colon
                parts = line.split(":", 1)
                if len(parts) > 1:
                    val = parts[1].strip()
                    if val and not val.startswith("["):
                        return val
    # Fall back to directory name
    return path.name


def main():
    # Read hook input from stdin
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)  # Don't block session close on parse error

    # Don't re-trigger if stop_hook_active (prevents infinite loop)
    if hook_input.get("stop_hook_active"):
        sys.exit(0)

    transcript_path = hook_input.get("transcript_path", "")
    cwd = hook_input.get("cwd", "")
    session_id = hook_input.get("session_id", "unknown")

    if not transcript_path or not os.path.exists(transcript_path):
        sys.exit(0)

    transcript = parse_transcript(transcript_path)
    project = detect_project(cwd)
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")

    # Build the archive content – what the librarian receives
    archive_content = f"""# Session Archive – {timestamp}
Session ID: {session_id}
Project: {project}
Working directory: {cwd}

## Session summary
{transcript['summary'] or '(no summary available)'}

## Conversation and actions
"""
    for msg in transcript['messages']:
        role = msg['role'].upper()
        archive_content += f"\n[{role}] {msg['text']}\n"

    # Write to a temp file and call the archivist
    with tempfile.NamedTemporaryFile(
        mode='w', suffix='.md', prefix='session-archive-', delete=False
    ) as f:
        f.write(archive_content)
        tmp_path = f.name

    try:
        # Call the archivist asynchronously (don't block)
        infra_dir = os.environ.get("AGENT_INFRA_DIR", str(Path.home() / "agent-infra"))
        script = os.path.join(infra_dir, "scripts", "librarian-archive.sh")

        if os.path.exists(script):
            subprocess.Popen(
                ["bash", script, "session-transcript", tmp_path, project],
                stdout=open(os.path.join(Path.home(), "logs", "librarian.log"), "a"),
                stderr=subprocess.STDOUT,
                start_new_session=True,  # detach from parent
            )
        # tmp_path will be cleaned up by the librarian-archive.sh script
    except Exception as e:
        # Log but never fail the hook
        log_path = Path.home() / "logs" / "librarian-hook-errors.log"
        log_path.parent.mkdir(exist_ok=True)
        with open(log_path, "a") as f:
            f.write(f"{timestamp}: Stop hook error: {e}\n")

    sys.exit(0)  # Always exit 0 – never block session close


if __name__ == "__main__":
    main()
