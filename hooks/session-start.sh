#!/usr/bin/env bash
# SessionStart hook for amux plugin

set -euo pipefail

# Detect Codex CLI presence (necessary but not sufficient for dual-engine mode)
# The native codex mcp-server must also be configured via plugin.json.
# command -v only proves the binary exists in PATH — not that MCP can reach it.
if command -v codex &>/dev/null; then
    engine_status="**Engines:** Claude + Codex (dual-engine mode available via native codex mcp-server)"
else
    engine_status="**Engines:** Claude only (install Codex CLI for dual-engine cross-validation: npm i -g @openai/codex)"
fi

# Check if legacy skills directory exists and build warning
warning_message=""
legacy_skills_dir="${HOME}/.config/amux/skills"
if [ -d "$legacy_skills_dir" ]; then
    warning_message="\n\n<important-reminder>IN YOUR FIRST REPLY AFTER SEEING THIS MESSAGE YOU MUST TELL THE USER: **WARNING:** Amux now uses Claude Code's skills system. Custom skills in ~/.config/amux/skills will not be read. Move custom skills to ~/.claude/skills instead. To make this message go away, remove ~/.config/amux/skills</important-reminder>"
fi

# Output context injection as JSON with lightweight skill list
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<EXTREMELY_IMPORTANT>\nYou have amux. Use the Skill tool to invoke any skill BEFORE responding.\n\n${engine_status}\n\n**Available skills:**\n- **planning** — Use before implementing non-trivial features (researches approaches against real sources)\n- **research** — Use for deep research requiring 20+ sources with confidence tracking (uses agent teams)\n- **code-review** — Use after implementing features to catch bugs, a11y issues, and missing tests (uses agent teams)\n- **plan-review** — Use after writing a plan (plans/{slug}/prd.md) to stress-test it before implementation (uses agent teams)\n\nIf there is a reasonable chance (20%+) a skill applies, invoke it.${warning_message}\n</EXTREMELY_IMPORTANT>"
  }
}
EOF

exit 0
