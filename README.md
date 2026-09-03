# Amux

Research, planning, and code review skills for Claude Code with dual-engine cross-validation (Claude + Codex).

## What's Included

### Skills (5)

- **research** — Deep research with 20+ sources and confidence tracking, powered by agent teams with Codex cross-validation. A CHALLENGE phase spawns independent challengers that try to break the load-bearing findings (verify the citation, search for counter-evidence) before anything reaches the report; only findings that survive count as high confidence.
- **planning** — Pre-implementation planning that researches approaches against real sources (current docs, web search, analogous codebases) — the skill prescribes no specific research MCPs; you use whatever your environment provides — with dual-engine evaluation via Codex MCP. Every approach states its kill criteria, and a pre-mortem attacks the recommendation (Claude writes the post-mortems, Codex argues for the alternative) before the user sees it. When a feasibility question survives research, an optional SPIKE phase runs a time-boxed, throwaway experiment with its falsification criterion stated up front — the code is never merged, only the result. Once an approach is selected, a BUILD-PLAN step writes a PRD broken into TDD-gated vertical slices — each gate opens with failing tests and closes only when lint, format, test, and build pass — then a multi-agent REVIEW-PLAN step (delegating to **plan-review**) stress-tests the assembled plan before any code is written.
- **plan-review** — Multi-reviewer critique of a *written plan* (the plan-equivalent of code-review-pipeline): four parallel dual-engine reviewers (assumptions, completeness, structure, scope) audit `plans/{slug}/prd.md`, fact-check empirical findings and the premises of judgment findings with independent verifiers, auto-apply verified mechanical fixes, and gate scope/approach changes for the user. Runs at planning's REVIEW-PLAN phase or standalone via `/plan-review`.
- **build** — Executes a build-ready plan gate by gate under TDD: verifies the plan's guessed assumptions first, opens each gate with failing tests at its declared mix (and checks they can't be passed by a stub), closes it only when lint, format, test, and build pass, records deviations, replans through the planning skill when the code refutes the plan, and finishes by running the code-review pipeline with the plan directory. Progress persists in `plans/{slug}/build.json` under the task loop, so it survives context resets.
- **code-review-pipeline** — Multi-reviewer review of both the *implementation* and the *design* of a change using agent teams (code, design, tests, docs), each cross-validated with Codex. Every finding is adversarially verified: implementation findings by a verifier that tries to refute them against the code, design findings by a verifier that defends the design as implemented and tests the finding's premises. Confirmed implementation issues are fixed; design findings are always the user's decision. The skill owns the dual-engine collaboration standard and the suggested-tools menu, injecting both into every reviewer.

### Agents (11)

Agents are registered as `amux:<name>` (the plugin prefix is added by Claude Code; frontmatter names carry no prefix). Skills dispatch them; none are meant to be invoked directly.

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

### Commands (5)

- `/amux:research` — Start a deep research session
- `/amux:planning` — Plan a non-trivial feature before implementation
- `/amux:plan-review` — Stress-test a written plan with parallel dual-engine reviewers
- `/amux:build` — Execute a build-ready plan gate by gate under TDD, then review it
- `/amux:code-review-pipeline` — Run the full review pipeline on a diff

### Hooks

Nothing runs automatically. The hooks announce and keep long-running skills alive; they don't enforce.

- **session-start** — Announces the skills and reports whether Codex (dual-engine) and agent teams are available in this session (Codex CLI presence does not guarantee MCP usability)
- **task-loop-hook** — Generic task loop that blocks exit while any skill's `task-loop.json` has `complete: false`, so research and build runs aren't abandoned mid-flight. Opt out per session with `AMUX_SKIP_TASK_LOOP=1`.

### Artifacts written to your repo

| Directory | Written by | Suggested handling |
|---|---|---|
| `plans/{slug}/` | planning, plan-review, build | Commit — it's the record of why the code looks the way it does. `plans/*/spikes/` holds throwaway experiment code; ignore or delete it once the spike is recorded |
| `research/{slug}/` | research | Commit the report; `state.json`, `findings.json`, and `task-loop.json` are working files you can ignore |
| `reviews/{branch}.md` | code-review-pipeline | Commit or ignore per taste; it's regenerated on every review of the branch |

### Validation

`bash scripts/validate.sh` checks the manifests, hooks, agent names and references, the Codex model name against `docs/dual-engine.md`, and the counts in this README. CI runs it on every push and pull request.

### Dual-Engine Architecture

The canonical standard lives in [`docs/dual-engine.md`](docs/dual-engine.md); the code-review-pipeline and plan-review skills carry a copy that they inject into every reviewer's task context, so each agent definition stays thin, and validation checks that every copy names the same Codex model. Following that standard, each reviewer independently:
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
| build | the gate's implementation | the gate's RED tests, written first and checked against a stub that returns a constant; the plan's guessed assumptions verified before the gate that needs them; the review pipeline on the finished change | a gate closes only with tests that failed first and quality commands green; a refuted assumption or blocked gate sends the plan back to planning |

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
