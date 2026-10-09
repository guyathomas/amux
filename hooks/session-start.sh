#!/usr/bin/env bash
# SessionStart hook for amux plugin: announces the skills and reports whether
# the Codex second engine is available in this session.

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

cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<amux>\nYou have the amux plugin. Its skills are invoked explicitly — by slash command or when the user's request clearly matches one — and nothing runs automatically.\n\n${engine_status}\n\n**Skills:**\n- **planning** (/amux:planning) — before implementing a non-trivial feature: researches approaches, attacks the recommendation with a pre-mortem, spikes open feasibility questions, writes a TDD-gated plan, and stress-tests it\n- **spike** (/amux:spike) — a time-boxed throwaway experiment with its falsifying result stated up front, optionally run on Codex and Claude independently\n- **plan-review** (/amux:plan-review) — critique a written plan (plans/{slug}/prd.md) and fact-check the findings before they touch it\n- **build** (/amux:build) — execute a reviewed plan gate by gate under TDD, then run the review pipeline\n- **code-review-pipeline** (/amux:code-review-pipeline) — one reviewer across correctness, security, structure, tests, docs, and design; a verifier attacks the critical and high findings; confirmed implementation issues are fixed\n- **research** (/amux:research) — deep multi-source research with challengers that try to break the load-bearing findings\n\nIf the user's request clearly calls for one of these, invoke it with the Skill tool; otherwise proceed normally.\n</amux>"
  }
}
JSON

exit 0
