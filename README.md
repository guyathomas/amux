# Amux

Research, planning, and code review skills for Claude Code with dual-engine cross-validation (Claude + Codex).

## What's Included

### Skills (4)

- **research** — Deep research with 20+ sources and confidence tracking, powered by agent teams with Codex cross-validation
- **planning** — Pre-implementation planning that researches approaches against real sources (current docs, web search, analogous codebases) — the skill prescribes no specific research MCPs; you use whatever your environment provides — with dual-engine evaluation via Codex MCP. Once an approach is selected, a BUILD-PLAN step writes a PRD broken into TDD-gated vertical slices — each gate opens with failing tests and closes only when lint, format, test, and build pass — then a multi-agent REVIEW-PLAN step (delegating to **plan-review**) stress-tests the assembled plan before any code is written.
- **plan-review** — Multi-reviewer critique of a *written plan* (the plan-equivalent of code-review-pipeline): four parallel dual-engine reviewers (assumptions, completeness, structure, scope) audit `plans/{slug}/prd.md`, auto-apply mechanical fixes, and gate scope/approach changes for the user. Runs at planning's REVIEW-PLAN phase or standalone via `/plan-review`.
- **code-review-pipeline** — Multi-reviewer code review using agent teams (code, tests, docs), each cross-validated with Codex. The skill owns the dual-engine collaboration standard and the suggested-tools menu, injecting both into every reviewer.

### Agents (8)

**Code pipeline reviewers (3):** dispatched by the code-review-pipeline skill based on what the change needs.
- **code** — the generalist: bugs, logic, security, error handling, structure (coupling/cohesion/API surface), and framework best-practices in one pass
- **tests** — coverage gaps, test antipatterns, missing cases
- **docs** — documentation staleness

**Plan reviewers (4):** dispatched by the plan-review skill — all four run on every plan.
- **review-plan-assumptions** — load-bearing assumptions (verified vs. guessed), codebase fit, evidence freshness
- **review-plan-completeness** — gap sweep, non-functional coverage (migration/rollback/observability/auth/perf/flags), per-gate definition-of-done
- **review-plan-structure** — gate dependency ordering, vertical-slice integrity, right-sizing, real RED tests
- **review-plan-scope** — scope drift vs. the original ask, over/under-engineering, simpler alternatives

**Standalone reviewer (1):** **review-code** — reviews completed work against the original plan and coding standards. Invoked via `/review-code`; carries its own self-contained cross-validation since it runs outside the pipeline.

### Commands (5)

- `/research` — Start a deep research session
- `/planning` — Plan a non-trivial feature before implementation
- `/plan-review` — Stress-test a written plan with parallel dual-engine reviewers
- `/code-review-pipeline` — Run the full review pipeline
- `/review-code` — Standalone plan-alignment + standards review

### Hooks

- **session-start** — Announces available skills and detects Codex CLI presence (note: CLI presence does not guarantee MCP usability)
- **task-loop-hook** — Generic task loop that blocks exit while any skill's `task-loop.json` has `complete: false`. Used by research (and available for future long-running skills).
- **pre-commit-quality-gate** — Runs quality checks before commits

### Dual-Engine Architecture

The collaboration standard is defined once in the code-review-pipeline skill and injected into every reviewer's task context, so each agent definition stays thin. Following that standard, each reviewer independently:
1. Performs Claude-based domain review
2. Calls the native `codex` MCP tool with `cwd` set to the repo root
3. Validates the Codex response — empty, non-JSON, or MCP error-text responses are treated as Codex-unavailable
4. Merges findings with classification (AGREE/CHALLENGE/COMPLEMENT) only if Codex returned valid JSON
5. Returns unified JSON with engine tags and cross-validation status

Cross-validated findings (flagged by both engines) receive a confidence boost — these are the highest-signal issues. Reviewers gracefully degrade to Claude-only when Codex is unavailable or returns unusable output.

## Prerequisites

- **Claude Code** with plugin support
- **Codex CLI** (optional, for dual-engine mode): `npm i -g @openai/codex`
- **Codex MCP server** is declared as an MCP dependency (uses `codex mcp-server` — requires Codex CLI installed)
- **Research MCPs** (optional) — the research, planning, and review skills don't prescribe any specific research tools; they use whatever is installed (built-in `WebSearch`/`WebFetch` always work). Install any docs/search/scrape/codebase MCPs you like and the skills will use them.

## Installation

### Claude Code (via Plugin Marketplace)

```bash
/plugin marketplace add guyathomas/amux-marketplace
```

```bash
/plugin install amux@amux-marketplace
```

### Verify

```bash
/help
# Should list /amux:research, /amux:code-review-pipeline, etc.
```

## License

MIT — see [LICENSE](LICENSE)
