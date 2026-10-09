#!/usr/bin/env bash
# SessionStart hook for amux plugin: announces the skills and reports which
# optional capabilities (Codex second engine, agent teams) this session has.

set -euo pipefail

# Dual-engine mode needs the Codex CLI and python3: the codex MCP server declared
# in plugin.json is the plugin's own shim (mcp/codex.py) over `codex exec`, since
# Codex CLI removed its native `codex mcp-server` in 0.154.0.
if ! command -v codex &>/dev/null; then
    engine_status="**Engines:** Claude only (install Codex CLI for dual-engine cross-validation: npm i -g @openai/codex)"
elif ! command -v python3 &>/dev/null; then
    engine_status="**Engines:** Claude only (Codex CLI found, but the codex MCP shim needs python3 on PATH)"
else
    engine_status="**Engines:** Claude + Codex (dual-engine cross-validation via the codex MCP tool, served by the plugin's shim over codex exec)"
fi

# Agent teams power the parallel reviewer/researcher teammates. Without the
# flag, the skills fall back to ordinary subagents (same roles, same protocol).
if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" == "1" ]]; then
    teams_status="**Agent teams:** enabled (reviewers and researchers run as parallel teammates)"
else
    teams_status="**Agent teams:** not enabled (skills fall back to subagents; set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 for teammates)"
fi

cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<amux>\nYou have the amux plugin. Its skills are invoked explicitly — by slash command or when the user's request clearly matches one — and nothing runs automatically.\n\n${engine_status}\n${teams_status}\n\n**Skills:**\n- **planning** (/amux:planning) — before implementing a non-trivial feature: researches approaches, evaluates them with two engines and a pre-mortem, spikes open feasibility questions, writes a TDD-gated plan, and stress-tests it\n- **plan-review** (/amux:plan-review) — critique a written plan (plans/{slug}/prd.md) with parallel reviewers and adversarial verification\n- **build** (/amux:build) — execute a build-ready plan gate by gate under TDD, then run the review pipeline\n- **code-review-pipeline** (/amux:code-review-pipeline) — review a diff's implementation and design with parallel reviewers, adversarially verify every finding, fix confirmed critical issues\n- **research** (/amux:research) — deep multi-source research with challengers that try to break the load-bearing findings\n\nIf the user's request clearly calls for one of these, invoke it with the Skill tool; otherwise proceed normally.\n</amux>"
  }
}
JSON

exit 0
