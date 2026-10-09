# Changelog

All notable changes to the amux plugin. Versions follow semver: breaking changes to commands, hooks, or artifact formats bump the major version.

## [8.1.0] - 2026-10-09

### Fixed
- **Dual-engine mode was dead on current Codex CLI.** The plugin declared `codex mcp-server` as its `codex` MCP server; Codex deprecated that command in 0.149.1 and removed it in 0.154.0 (on current versions the old declaration launches the interactive TUI with `mcp-server` as the prompt, so the MCP connection hangs instead of failing). The plugin now ships its own server, `mcp/codex.py`: a standard-library Python stdio MCP shim that runs one `codex exec` per call and returns the final message. Tool name (`codex`) and parameters (`prompt`, `model`, `sandbox`, `cwd`, `profile`, `config`) are unchanged, so no skill or agent text changed. `codex app-server` was not adopted: it is an experimental non-MCP protocol, and wrapping it means a third-party dependency.

### Added
- `mcp/codex.py` accepts `output-schema` (Codex `--output-schema`) and `timeout-seconds`; honours `AMUX_CODEX_BIN` and `AMUX_CODEX_TIMEOUT` (default 900 s); runs parallel calls concurrently; kills the whole Codex process tree on client cancel or timeout (the npm wrapper spawns the native binary as a child, which a plain kill leaves holding the pipes).
- `scripts/test-codex-shim.py`, a protocol smoke test with a fake `codex` (handshake, tool list, missing-CLI error, success and non-zero-exit paths); `scripts/validate.sh` runs it and checks the manifest wiring and shim syntax.

### Changed
- `python3` is now a prerequisite for dual-engine mode; the session-start banner reports when Codex is installed but `python3` is missing.

## [8.0.1] - 2026-09-09

### Changed
- Codex model updated from `gpt-5-codex` to `gpt-6-astra` in `docs/dual-engine.md` and every skill/agent that calls the `codex` MCP tool.

## [8.0.0] - 2026-09-03

### Added
- **Design review** in `code-review-pipeline`: new `review-design` agent (reconstructs and steelmans the design before critiquing; findings carry checkable premises) and `verify-design-finding` verifier (defends the design as implemented, tests each premise). Design findings are never auto-fixed.
- **Adversarial stages in every skill**: planning kill criteria and pre-mortem; research CHALLENGE phase with challenger teammates; plan-review premise checks on judgment findings.
- **SPIKE phase** in planning (optional, between EVALUATE and PRESENT): time-boxed throwaway experiments with a pre-stated falsification criterion, recorded in `plans/{slug}/spikes.json`.
- **`build` skill and `/amux:build` command**: executes a build-ready plan gate by gate under TDD, verifies the plan's guessed assumptions first, replans on contact with reality, and ends with the review pipeline.
- `scripts/validate.sh` and a GitHub Actions workflow that run structural checks (manifests, hooks, agent names and references, Codex model consistency, README counts).
- `docs/dual-engine.md` as the canonical dual-engine standard; `CLAUDE.md` for contributors; this changelog.
- Session-start banner reports agent-teams availability; `code-review-pipeline` and `plan-review` state the agent-teams prerequisite and the subagent fallback.
- `AMUX_SKIP_TASK_LOOP=1` escape hatch for the task-loop hook.

### Changed
- Agents renamed from `core:*` to plain names; skills reference them as `amux:<name>`. Every agent's JSON `agent` identifier now equals its filename.
- Agents use `model: inherit` (the user's default) instead of all pinning Fable. Only the highest-value judgment roles — `verify-finding`, `verify-design-finding`, `verify-plan-finding`, `review-design`, `premortem`, `build-plan` — pin `fable`; validation enforces the list.
- Planning's pre-mortem and BUILD-PLAN phases are now agents (`premortem`, `build-plan`) instead of inline steps, so the pre-mortem attacks the recommendation from fresh context and the gate plan is written by a pinned model.
- `verify-plan-finding` no longer hard-codes a docs MCP; it uses whatever docs tool the environment provides.
- Plan reviewer agents no longer emit `buildReady` (the orchestrator computes it after verification).
- Codex agreement is a display signal everywhere, not a confidence bump.
- Session-start banner softened: skills are invoked explicitly, nothing runs automatically.

### Removed
- **`/review-code` command and `review-code` agent** — folded into `code-review-pipeline`, whose design reviewer handles plan alignment and whose small-diff path covers the standalone case.
- **`review-gate.sh`** (Stop hook forcing a review) and **`post-plan-approval.sh`** (auto-nudging plan-review).
- **`pre-commit-quality-gate.sh`** — the last automatically enforcing hook; the `build` skill runs the plan's quality commands at every gate instead.
- `hooks/run-hook.cmd` (deprecated polyglot wrapper) and the legacy `~/.config/amux/skills` warning.

## [7.6.0] and earlier

See git history.
