# Changelog

All notable changes to the amux plugin. Versions follow semver: breaking changes to commands, hooks, or artifact formats bump the major version.

## [9.0.0] - 2026-10-09

A simplification release: the same finding-versus-judging architecture with a third of the machinery. Agent and artifact formats changed, hence the major bump.

### Changed
- **Thirteen agents become five.** `review-change` replaces the three implementation lenses plus the design, tests, and docs reviewers: one pass with six sections that must each be filled. `review-plan` replaces the four plan reviewers. `verify` replaces the three verifiers and takes a batch of findings that share a file or section, so verification cost scales with files, not findings. `premortem` and `build-plan` stay.
- **Codex only argues against things.** Reviewers and researchers no longer call it; the verifier, the pre-mortem, research challengers, and the optional dual-engine spike do. The AGREE / CHALLENGE / COMPLEMENT merge taxonomy, `crossValidated`, `engines` on findings, and self-reported confidence scores are gone; severity plus verification is the gate.
- **Verification is sized to severity.** Critical and high findings are verified by default; `thorough` adds medium; low passes through as PLAUSIBLE. Large diffs fan out by file group with the same prompt instead of by specialty.
- **One state file per plan.** `plans/{slug}/plan.json` holds scope, approaches, evaluation, spikes, review, and build progress; `prd.md` is the plan; `notes/` is free-form. `state.json`, `approaches.json`, `claude-eval.json`, `codex-eval.json`, `merged-eval.json`, `spikes.json`, `plan-review.json`, and `build.json` are no longer written. Research state drops its counters.
- **Agents declare no `tools:` list**, so they inherit the environment's research MCPs; previously the whitelist hid every installed tool from reviewers and verifiers. Skills state evidence standards instead of tool names and honor tool preferences from the user's own instructions. Validation enforces the no-whitelist rule and the new Fable list (`verify`, `premortem`, `build-plan`).
- **build** warns instead of refusing when a plan has not cleared review, and skips the design section of the final review when the plan was reviewed and no gate recorded a deviation.
- **Prompts cut to roughly a third**: the dual-engine standard and tools menu are no longer injected into every teammate prompt; the agent-teams-versus-subagents prose is gone from every skill (dispatch in parallel; the harness decides).
- `planning` EVALUATE is a Claude evaluation plus the pre-mortem; the cooperative Codex evaluation is removed.
- Research challengers are batched per source URL (the citation check is per source), capped at four batches per round; default iterations drop from 5 to 3.

### Added
- **`spike` skill and `/amux:spike`**, split out of planning: a time-boxed experiment with a pre-stated falsification criterion, optionally run independently on Codex (in a `workspace-write` sandbox confined to the spike directory) and Claude, with disagreement recorded as inconclusive.

### Fixed
- **Dual-engine mode was dead on current Codex CLI.** The plugin declared `codex mcp-server` as its `codex` MCP server; Codex deprecated that command in 0.149.1 and removed it in 0.154.0 (on current versions the old declaration launches the interactive TUI with `mcp-server` as the prompt, so the MCP connection hangs instead of failing). The plugin now ships its own server, `mcp/codex.py`: a standard-library Python stdio MCP shim that runs one `codex exec` per call and returns the final message, keeping the tool name and parameters. It accepts `output-schema` and `timeout-seconds`, honours `AMUX_CODEX_BIN` and `AMUX_CODEX_TIMEOUT` (default 900 s), runs parallel calls concurrently, and kills the whole Codex process tree on client cancel or timeout (the npm wrapper spawns the native binary as a child, which a plain kill leaves holding the pipes). `scripts/test-codex-shim.py` is its protocol smoke test; `scripts/validate.sh` runs it. `python3` is now a prerequisite for the second engine and the session-start banner says when it is missing.

### Removed
- Agents `review-implementation`, `review-design`, `review-tests`, `review-docs`, `review-plan-assumptions`, `review-plan-completeness`, `review-plan-structure`, `review-plan-scope`, `verify-finding`, `verify-design-finding`, `verify-plan-finding`.

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
