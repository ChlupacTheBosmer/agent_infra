#!/bin/bash
# Agent Infrastructure Installer
# One-shot setup script. Idempotent – safe to run multiple times.
# Usage: ./install.sh

set -euo pipefail

AGENT_INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="$HOME/.bashrc"
GUARD_START="# ── agent-infra BEGIN ──"
GUARD_END="# ── agent-infra END ──"

echo "╔══════════════════════════════════════════════╗"
echo "║   Agent Infrastructure Installer             ║"
echo "║   Repo: $AGENT_INFRA_DIR"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Step 1: Prerequisites check ─────────────────────────────────────────────
echo "Step 1: Checking prerequisites..."

MISSING=()
for cmd in claude git python3 curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING+=("$cmd")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: Missing required tools: ${MISSING[*]}"
  echo "Install them before running this script."
  exit 1
fi

if ! command -v gh &>/dev/null; then
  echo "NOTE: 'gh' (GitHub CLI) not found. PR creation in workers will be skipped."
fi

# Create ~/bin/claude wrapper that finds the macOS app bundle binary
# This survives Claude Code version updates and is added to PATH
mkdir -p "$HOME/bin"
cat > "$HOME/bin/claude" << 'CLAUDEWRAP'
#!/bin/bash
# Stable wrapper for Claude Code CLI – survives version updates
_CLAUDE=$(find "$HOME/Library/Application Support/Claude/claude-code" \
  -path "*/MacOS/claude" -type f 2>/dev/null | sort -V | tail -1)
if [ -z "$_CLAUDE" ] || [ ! -x "$_CLAUDE" ]; then
  _CLAUDE=$(find "$HOME/Library/Python" \
    -path "*/claude_agent_sdk/_bundled/claude" -type f 2>/dev/null | head -1)
fi
if [ -z "$_CLAUDE" ] || [ ! -x "$_CLAUDE" ]; then
  echo "ERROR: claude CLI not found" >&2
  exit 127
fi
exec "$_CLAUDE" "$@"
CLAUDEWRAP
chmod +x "$HOME/bin/claude"
export PATH="$HOME/bin:$PATH"
echo "  ✓ Created ~/bin/claude wrapper (stable across version updates)"

echo "  ✓ All required tools found"

# ── Step 2: User input ───────────────────────────────────────────────────────
echo ""
echo "Step 2: Configuration..."

# Anthropic API key (optional if using Claude Code with subscription auth)
read -r -p "  Anthropic API key (sk-ant-...) [leave blank if using subscription]: " ANTHROPIC_API_KEY
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "  (No API key provided – assuming Claude Code subscription auth)"
fi

# Vault path
read -r -p "  Vault path [default: $HOME/vault]: " VAULT_INPUT
VAULT="${VAULT_INPUT:-$HOME/vault}"

# Email (optional)
read -r -p "  Email for agent reports (leave blank to skip): " AGENT_REPORT_EMAIL

echo "  ✓ Configuration collected"

# ── Step 3: Dynamic model selection ─────────────────────────────────────────
echo ""
echo "Step 3: Querying CERIT models..."

# Pre-configured CERIT credentials
CERIT_API_KEY_FIXED="REPLACE_WITH_CERIT_API_KEY"
CERIT_BASE_URL_FIXED="https://llm.ai.e-infra.cz/"

MODEL_LIST=$(curl -s --max-time 15 \
  -H "Authorization: Bearer $CERIT_API_KEY_FIXED" \
  "$CERIT_BASE_URL_FIXED/models" 2>/dev/null | \
  jq -r '.data[].id' 2>/dev/null | sort || echo "")

if [ -z "$MODEL_LIST" ]; then
  echo "  WARNING: Could not fetch CERIT model list. You will need to enter model names manually."
  echo "  Common CERIT models: Qwen/Qwen2.5-Coder-32B-Instruct, meta-llama/Llama-3.3-70B-Instruct"
  MODEL_LIST="(could not fetch – enter manually)"
fi

echo ""
echo "  Available CERIT models:"
echo "$MODEL_LIST" | while read -r m; do echo "    - $m"; done
echo ""

# Provide recommendations based on model names
echo "  Recommendations based on available models:"
CODER_REC=$(echo "$MODEL_LIST" | grep -i "coder\|code" | head -1 || echo "")
THINKER_REC=$(echo "$MODEL_LIST" | grep -i "70b\|72b\|deepseek\|thinker\|llama-3" | head -1 || echo "")
FAST_REC=$(echo "$MODEL_LIST" | grep -i "7b\|8b\|mini\|small\|fast" | head -1 || echo "")
LIBRARIAN_REC=$(echo "$MODEL_LIST" | grep -i "70b\|72b\|llama-3\|qwen2.5" | grep -iv "coder" | head -1 || echo "")

# Fallback recommendations
[ -z "$CODER_REC" ] && CODER_REC=$(echo "$MODEL_LIST" | head -1)
[ -z "$THINKER_REC" ] && THINKER_REC=$(echo "$MODEL_LIST" | head -1)
[ -z "$FAST_REC" ] && FAST_REC=$(echo "$MODEL_LIST" | head -1)
[ -z "$LIBRARIAN_REC" ] && LIBRARIAN_REC=$(echo "$MODEL_LIST" | head -1)

echo "    Coder     (coding tasks):          ${CODER_REC:-<none available>}"
echo "    Thinker   (reasoning/judge):       ${THINKER_REC:-<none available>}"
echo "    Fast      (simple/explore):        ${FAST_REC:-<none available>}"
echo "    Librarian (vault management):      ${LIBRARIAN_REC:-<none available>}"
echo ""

read -r -p "  CERIT_CODER_MODEL [${CODER_REC}]: " CERIT_CODER_MODEL_INPUT
CERIT_CODER_MODEL="${CERIT_CODER_MODEL_INPUT:-$CODER_REC}"

read -r -p "  CERIT_THINKER_MODEL [${THINKER_REC}]: " CERIT_THINKER_MODEL_INPUT
CERIT_THINKER_MODEL="${CERIT_THINKER_MODEL_INPUT:-$THINKER_REC}"

read -r -p "  CERIT_FAST_MODEL [${FAST_REC}]: " CERIT_FAST_MODEL_INPUT
CERIT_FAST_MODEL="${CERIT_FAST_MODEL_INPUT:-$FAST_REC}"

read -r -p "  CERIT_LIBRARIAN_MODEL [${LIBRARIAN_REC}]: " CERIT_LIBRARIAN_MODEL_INPUT
CERIT_LIBRARIAN_MODEL="${CERIT_LIBRARIAN_MODEL_INPUT:-$LIBRARIAN_REC}"

echo "  ✓ Models selected"

# ── Step 4: Write environment variables to ~/.bashrc ─────────────────────────
echo ""
echo "Step 4: Writing environment variables to $BASHRC and ~/.zshrc..."

write_env_block() {
  local TARGET="$1"
  # Remove existing block if present (idempotency)
  if grep -q "$GUARD_START" "$TARGET" 2>/dev/null; then
    TMPFILE=$(mktemp)
    awk "/$GUARD_START/{found=1} !found{print} /$GUARD_END/{found=0}" "$TARGET" > "$TMPFILE"
    mv "$TMPFILE" "$TARGET"
  fi
  cat >> "$TARGET" << ENVEOF

$GUARD_START
# Agent Infrastructure – auto-generated by install.sh
# Re-run install.sh to update this block

# Anthropic (orchestrator) – only set if using API key auth
# If using Claude Code subscription, this is handled by the extension itself
$([ -n "$ANTHROPIC_API_KEY" ] && echo "export ANTHROPIC_API_KEY=\"$ANTHROPIC_API_KEY\"" || echo "# ANTHROPIC_API_KEY not set (using subscription auth)")

# CERIT endpoint – pre-configured
export CERIT_API_KEY="$CERIT_API_KEY_FIXED"
export CERIT_BASE_URL="$CERIT_BASE_URL_FIXED"

# CERIT model roles
export CERIT_CODER_MODEL="$CERIT_CODER_MODEL"
export CERIT_THINKER_MODEL="$CERIT_THINKER_MODEL"
export CERIT_FAST_MODEL="$CERIT_FAST_MODEL"
export CERIT_LIBRARIAN_MODEL="$CERIT_LIBRARIAN_MODEL"

# Vault location
export VAULT="$VAULT"

# Agent infra repo location
export AGENT_INFRA_DIR="$AGENT_INFRA_DIR"

# Agent Teams (experimental)
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# Logging
mkdir -p "\$HOME/logs"

# Email reporting (optional)
export AGENT_REPORT_EMAIL="${AGENT_REPORT_EMAIL:-}"
export AGENT_FROM_EMAIL="agent@localhost"
export SMTP_HOST="localhost"
export SMTP_PORT="25"

# Scripts and stable claude wrapper in PATH
export PATH="\$HOME/bin:\$PATH:$AGENT_INFRA_DIR/scripts"

# Provider switching aliases
alias ca='claude'
alias cc='ANTHROPIC_BASE_URL="\$CERIT_BASE_URL" ANTHROPIC_AUTH_TOKEN="\$CERIT_API_KEY" ANTHROPIC_MODEL="\$CERIT_CODER_MODEL" ANTHROPIC_DEFAULT_OPUS_MODEL="\$CERIT_THINKER_MODEL" ANTHROPIC_DEFAULT_SONNET_MODEL="\$CERIT_CODER_MODEL" ANTHROPIC_DEFAULT_HAIKU_MODEL="\$CERIT_FAST_MODEL" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude'

$GUARD_END
ENVEOF
} # end write_env_block

write_env_block "$BASHRC"
echo "  ✓ Written to $BASHRC"

# Also write to ~/.zshrc (macOS default shell)
if [ -f "$HOME/.zshrc" ] || [ "$(uname)" = "Darwin" ]; then
  write_env_block "$HOME/.zshrc"
  echo "  ✓ Written to ~/.zshrc (macOS default shell)"
fi

echo "  ✓ Environment variables written"

# ── Step 5: Create ~/.claude/ structure and symlinks ─────────────────────────
echo ""
echo "Step 5: Setting up ~/.claude/ symlinks..."

mkdir -p ~/.claude/hooks

# CLAUDE.md symlink
if [ -L ~/.claude/CLAUDE.md ]; then
  rm ~/.claude/CLAUDE.md
fi
ln -sf "$AGENT_INFRA_DIR/claude-config/CLAUDE.md" ~/.claude/CLAUDE.md
echo "  ✓ ~/.claude/CLAUDE.md → $AGENT_INFRA_DIR/claude-config/CLAUDE.md"

# agents symlink
if [ -L ~/.claude/agents ]; then
  rm ~/.claude/agents
fi
ln -sf "$AGENT_INFRA_DIR/claude-config/agents" ~/.claude/agents
echo "  ✓ ~/.claude/agents → $AGENT_INFRA_DIR/claude-config/agents"

# skills symlink
if [ -L ~/.claude/skills ]; then
  rm ~/.claude/skills
fi
ln -sf "$AGENT_INFRA_DIR/claude-config/skills" ~/.claude/skills
echo "  ✓ ~/.claude/skills → $AGENT_INFRA_DIR/claude-config/skills"

# ── Step 6: Write ~/.claude/settings.json ────────────────────────────────────
echo ""
echo "Step 6: Writing ~/.claude/settings.json..."

SETTINGS_FILE="$HOME/.claude/settings.json"
INFRA_HOOKS_DIR="$AGENT_INFRA_DIR/claude-config/hooks"

# Build the settings JSON with actual path substituted
python3 - << PYEOF
import json
import os

settings_file = "$SETTINGS_FILE"
hooks_dir = "$INFRA_HOOKS_DIR"

new_settings = {
    "permissions": {
        "defaultMode": "bypassPermissions",
        "deny": [
            "Bash(rm -rf *)",
            "Bash(rm -f /*)",
            "Bash(dd *)",
            "Bash(mkfs*)",
            "Bash(fdisk*)",
            "Bash(shred*)",
            "Bash(wipefs*)",
            "Bash(:(){:|:&};:)",
            "Bash(chmod -R 777 /*)",
            "Bash(chown -R * /*)"
        ]
    },
    "env": {
        "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
        # CERIT credentials injected here so the VS Code extension shell has them
        # regardless of whether ~/.bashrc or ~/.zshrc is sourced
        "CERIT_API_KEY": "$CERIT_API_KEY_FIXED",
        "CERIT_BASE_URL": "$CERIT_BASE_URL_FIXED",
        "CERIT_CODER_MODEL": "$CERIT_CODER_MODEL",
        "CERIT_THINKER_MODEL": "$CERIT_THINKER_MODEL",
        "CERIT_FAST_MODEL": "$CERIT_FAST_MODEL",
        "CERIT_LIBRARIAN_MODEL": "$CERIT_LIBRARIAN_MODEL",
        "VAULT": "$VAULT",
        "AGENT_INFRA_DIR": "$AGENT_INFRA_DIR",
        "PATH": "$HOME/bin:$AGENT_INFRA_DIR/scripts:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
    },
    "hooks": {
        "UserPromptSubmit": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": f"python3 {hooks_dir}/cost-estimator.py",
                        "async": False
                    }
                ]
            }
        ],
        "PostToolUse": [
            {
                "matcher": "Write|Edit|MultiEdit",
                "hooks": [
                    {
                        "type": "command",
                        "command": f"python3 {hooks_dir}/quality-check.py",
                        "async": False
                    }
                ]
            }
        ],
        "Stop": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": f"python3 {hooks_dir}/stop-gate.py"
                    }
                ]
            },
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": f"python3 {hooks_dir}/session-end-archivist.py",
                        "async": True
                    }
                ]
            }
        ],
        "SubagentStop": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": f"python3 {hooks_dir}/subagent-end-archivist.py",
                        "async": True
                    }
                ]
            }
        ]
    }
}

# Merge with existing settings if present
if os.path.exists(settings_file):
    try:
        with open(settings_file) as f:
            existing = json.load(f)
        # Preserve any existing settings not managed by us
        # But overwrite our managed keys
        for key in ['permissions', 'env', 'hooks']:
            existing[key] = new_settings[key]
        final = existing
    except Exception:
        final = new_settings
else:
    final = new_settings

with open(settings_file, 'w') as f:
    json.dump(final, f, indent=2)

print(f"  Written: {settings_file}")
PYEOF

echo "  ✓ settings.json written with all 4 hook types"

# ── Step 7: Copy vault template ───────────────────────────────────────────────
echo ""
echo "Step 7: Setting up vault at $VAULT..."

if [ -d "$VAULT" ] && [ "$(ls -A "$VAULT" 2>/dev/null)" ]; then
  echo "  Vault already exists and has content – skipping copy to preserve your data."
  echo "  To reset: remove $VAULT and re-run install.sh"
else
  mkdir -p "$VAULT"
  cp -r "$AGENT_INFRA_DIR/vault-template/." "$VAULT/"
  echo "  ✓ Vault template copied to $VAULT"
fi

# ── Step 8: Scripts setup ─────────────────────────────────────────────────────
echo ""
echo "Step 8: Making scripts executable..."

chmod +x "$AGENT_INFRA_DIR/scripts/"*.sh 2>/dev/null || true
chmod +x "$AGENT_INFRA_DIR/scripts/"*.py 2>/dev/null || true
chmod +x "$AGENT_INFRA_DIR/claude-config/hooks/"*.py 2>/dev/null || true

echo "  ✓ Scripts made executable"

# ── Step 9: Vault git init ────────────────────────────────────────────────────
echo ""
echo "Step 9: Initialising vault git repo..."

if [ -d "$VAULT/.git" ]; then
  echo "  Vault already a git repo – skipping init"
else
  git -C "$VAULT" init -q
  git -C "$VAULT" add -A
  git -C "$VAULT" commit -q -m "initial: vault scaffold from agent-infra"
  echo "  ✓ Vault git repo initialised with initial commit"
fi

# ── Step 10: Summary ──────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Agent Infrastructure – Setup Complete      ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "CERIT models configured:"
echo "  Coder:     $CERIT_CODER_MODEL"
echo "  Thinker:   $CERIT_THINKER_MODEL"
echo "  Fast:      $CERIT_FAST_MODEL"
echo "  Librarian: $CERIT_LIBRARIAN_MODEL"
echo ""
echo "Next steps:"
echo "1. Run: source ~/.bashrc"
echo "2. Edit ~/.claude/CLAUDE.md – fill in Zone B with your details"
echo "3. For each project: copy project-template/ into the repo and fill in CLAUDE.md"
echo "4. Seed the vault: open $VAULT in Obsidian and add your knowledge to atlas/"
echo ""
echo "Files still requiring your input:"
echo "  ~/.claude/CLAUDE.md  (Zone B)"
echo "  <each project>/CLAUDE.md  (Zone B)"
echo "  <each project>/tasks/task-template.yaml  (copy and fill in per task)"
echo "  <each project>/docs/adr/  (add ADRs as you make architectural decisions)"
echo ""
echo "To add a new skill: drop a directory into claude-config/skills/ and git commit."
echo "Community skills: https://github.com/hesreallyhim/awesome-claude-code"
echo ""
echo "Provider aliases (after source ~/.bashrc):"
echo "  ca  – Anthropic Claude (orchestrator)"
echo "  cc  – CERIT Claude (free workers)"
