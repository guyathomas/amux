# Amux

Research, planning, and code review skills for Claude Code with dual-engine cross-validation (Claude + Codex).

## What's Included

### Skills (4)

- **research** — Deep research with 20+ sources and confidence tracking, powered by agent teams with Codex cross-validation. A CHALLENGE phase spawns independent challengers that try to break the load-bearing findings (verify the citation, search for counter-evidence) before anything reaches the report; only findings that survive count as high confidence.
- **planning** — Pre-implementation planning that researches approaches against real sources (current docs, web search, analogous codebases) — the skill prescribes no specific research MCPs; you use whatever your environment provides — with dual-engine evaluation via Codex MCP. Every approach states its kill criteria, and a pre-mortem attacks the recommendation (Claude writes the post-mortems, Codex argues for the alternative) before the user sees it. When a feasibility question survives research, an optional SPIKE phase runs a time-boxed, throwaway experiment with its falsification criterion stated up front — the code is never merged, only the result. Once an approach is selected, a BUILD-PLAN step writes a PRD broken into TDD-gated vertical slices — each gate opens with failing tests and closes only when lint, format, test, and build pass — then a multi-agent REVIEW-PLAN step (delegating to **plan-review**) stress-tests the assembled plan before any code is written.
- **plan-review** — Multi-reviewer critique of a *written plan* (the plan-equivalent of code-review-pipeline): four parallel dual-engine reviewers (assumptions, completeness, structure, scope) audit `plans/{slug}/prd.md`, fact-check empirical findings and the premises of judgment findings with independent verifiers, auto-apply verified mechanical fixes, and gate scope/approach changes for the user. Runs at planning's REVIEW-PLAN phase or standalone via `/plan-review`.
- **code-review-pipeline** — Multi-reviewer review of both the *implementation* and the *design* of a change using agent teams (code, design, tests, docs), each cross-validated with Codex. Every finding is adversarially verified: implementation findings by a verifier that tries to refute them against the code, design findings by a verifier that defends the design as implemented and tests the finding's premises. Confirmed implementation issues are fixed; design findings are always the user's decision. The skill owns the dual-engine collaboration standard and the suggested-tools menu, injecting both into every reviewer.

### Agents (12)

**Code pipeline reviewers (4):** dispatched by the code-review-pipeline skill based on what the change needs.
- **code** — the generalist: bugs, logic, security, error handling, structure (coupling/cohesion/API surface), and framework best-practices in one pass
- **design** — the shape of the change rather than its lines: problem–solution fit, abstraction level, architectural fit, data/state ownership, extension vs. YAGNI, simpler designs, reversibility, and plan alignment. Reconstructs and steelmans the design before critiquing it; every finding carries checkable premises
- **tests** — coverage gaps, test antipatterns, missing cases
- **docs** — documentation staleness

**Plan reviewers (4):** dispatched by the plan-review skill — all four run on every plan.
- **review-plan-assumptions** — load-bearing assumptions (verified vs. guessed), codebase fit, evidence freshness
- **review-plan-completeness** — gap sweep, non-functional coverage (migration/rollback/observability/auth/perf/flags), per-gate definition-of-done
- **review-plan-structure** — gate dependency ordering, vertical-slice integrity, right-sizing, real RED tests
- **review-plan-scope** — scope drift vs. the original ask, over/under-engineering, simpler alternatives — each finding states the premise a verifier can check

**Adversarial verifiers (3):** one per finding, fresh context, no attachment to the reviewer that produced it. Verdicts are CONFIRMED / PLAUSIBLE / REFUTED and require cited evidence; REFUTED findings are dropped.
- **verify-finding** — tries to refute an implementation finding against the actual code (guards, types, callers, framework behavior)
- **verify-design-finding** — defends a design finding's target: tests each premise, hunts for the constraint the reviewer missed, tries the alternative on paper
- **verify-plan-finding** — fact-checks an empirical plan finding against the repo, the plan text, and current docs; in premise-only mode, checks the fact a judgment finding rests on

**Standalone reviewer (1):** **review-code** — reviews completed work against the original plan, design, and coding standards. Invoked via `/review-code`; carries its own cross-validation and an adversarial self-check (it refutes its own critical/high findings before reporting) since it runs outside the pipeline.

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

Cross-validated findings (flagged by both engines) are surfaced as a display signal, not a score bump — two engines can share a blind spot. Reviewers gracefully degrade to Claude-only when Codex is unavailable or returns unusable output.

### Adversarial Architecture

Agreement between engines is not verification, so every skill separates *finding* from *judging* and gives the judge no stake in the finding:

| Skill | Who finds | Who attacks | What survives |
|---|---|---|---|
| code-review-pipeline | code / design / tests / docs reviewers | `verify-finding` refutes implementation claims against the code; `verify-design-finding` defends the design and tests each premise | CONFIRMED implementation findings are fixed; design findings go to the user at any verdict |
| plan-review | assumptions / completeness / structure / scope reviewers | `verify-plan-finding` fact-checks empirical claims and the premises of judgment claims | CONFIRMED mechanical fixes are applied; judgment calls with intact premises go to the user |
| planning | dual-engine EVALUATE | a pre-mortem: Claude writes the post-mortems of the recommended approach, Codex argues for the alternative, both tested against each approach's kill criteria; an optional SPIKE turns a testable unknown into a fact, with the result that would falsify the approach stated before it runs | surviving failure modes become risks and build-plan input; a falsified spike kills the approach; an evidence-backed dissent changes or hedges the recommendation |
| research | researcher teammates | challenger teammates verify the citation and search for counter-evidence on every load-bearing finding | CONFIRMED findings are eligible for high confidence; DISPUTED go to Conflicting Information; REFUTED are dropped |
| review-code (standalone) | the reviewer itself | its own adversarial self-check, run after the Codex merge | findings it can't refute, tagged CONFIRMED or PLAUSIBLE |

Verdicts require cited evidence in every case; "seems fine" is not a refutation and "probably" is not a confirmation. PLAUSIBLE is always a legitimate verdict.

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
