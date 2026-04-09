#!/usr/bin/env python3
"""
UserPromptSubmit hook – fires before every user prompt is processed.
Injects current session context stats as additionalContext so the agent
is always aware of its context usage and can make informed decisions
about compaction and delegation.
"""
import json
import os
import sys
from pathlib import Path
from datetime import datetime


def estimate_cost_usd(input_tokens: int, output_tokens: int, provider: str = "anthropic") -> float:
    """Rough cost estimate. Anthropic Sonnet pricing as of 2026."""
    if provider == "cerit":
        return 0.0  # Free
    # Sonnet 4.6: ~$3/MTok input, ~$15/MTok output (approximate)
    return (input_tokens * 3.0 + output_tokens * 15.0) / 1_000_000


def read_session_stats(transcript_path: str) -> dict:
    """Parse the session transcript to count tokens seen so far."""
    stats = {"input_tokens": 0, "output_tokens": 0, "turns": 0, "tool_calls": 0}
    if not transcript_path or not os.path.exists(transcript_path):
        return stats

    try:
        with open(transcript_path) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    usage = entry.get("usage", {}) or entry.get("message", {}).get("usage", {})
                    if usage:
                        stats["input_tokens"] += usage.get("input_tokens", 0)
                        stats["output_tokens"] += usage.get("output_tokens", 0)
                    if entry.get("type") in ("user", "assistant"):
                        stats["turns"] += 1
                    if entry.get("type") == "tool_use":
                        stats["tool_calls"] += 1
                except (json.JSONDecodeError, AttributeError):
                    continue
    except Exception:
        pass
    return stats


def main():
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    transcript_path = hook_input.get("transcript_path", "")
    stats = read_session_stats(transcript_path)

    # Determine provider from env
    is_cerit = bool(os.environ.get("ANTHROPIC_AUTH_TOKEN") and
                    "cerit" in os.environ.get("CERIT_BASE_URL", "").lower())
    provider = "cerit" if is_cerit else "anthropic"

    cost = estimate_cost_usd(stats["input_tokens"], stats["output_tokens"], provider)

    # Context window size (approximate – 200K for Anthropic Sonnet/Opus)
    ctx_window = 200_000
    ctx_pct = min(99, int(stats["input_tokens"] / ctx_window * 100)) if stats["input_tokens"] else 0

    # Build status line
    if stats["input_tokens"] == 0:
        # New session – no stats yet
        sys.exit(0)

    cost_str = f"${cost:.3f}" if provider == "anthropic" else "free (CERIT)"

    ctx_warning = ""
    if ctx_pct >= 60:
        ctx_warning = f" ⚠️ COMPACT NOW (≥60%)"
    elif ctx_pct >= 45:
        ctx_warning = " – consider /compact soon"

    status_line = (
        f"[Session: ~{ctx_pct}% context used"
        f"{ctx_warning}"
        f" | {stats['turns']} turns"
        f" | {stats['tool_calls']} tool calls"
        f" | est. cost: {cost_str}]"
    )

    output = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": status_line
        }
    }
    print(json.dumps(output))
    sys.exit(0)


if __name__ == "__main__":
    main()
