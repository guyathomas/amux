# Amux

Research, planning, spike, build, and review skills for Claude Code. One agent finds, an independent agent with fresh context tries to break what it found, and only cited evidence drives action. Codex is the second engine where it argues against something.

## What's Included

### Skills (6)

- **research** — Decomposes a topic into the questions that matter, researches them in parallel, has independent challengers verify each load-bearing citation and search for counter-evidence, iterates until the questions are actually answered, and writes a report with source attribution and confidence.
- **planning** — Researches approaches against real sources, states what would rule each one out, evaluates them and attacks the recommendation with a fresh-context pre-mortem (Codex argues for the alternative), spikes any feasibility question still open, writes a TDD-gated plan once the user chooses, and stress-tests it with plan-review before any code is written.
- **spike** — A time-boxed, throwaway experiment with the falsifying result stated before it runs. Optionally runs the same experiment independently on Codex and Claude; two independent implementations rarely pass for the same wrong reason, so disagreement makes the spike inconclusive rather than confirmed.
- **plan-review** — One reviewer covers assumptions, completeness, gate structure, and scope; a verifier fact-checks the critical and high findings (judgment findings on their premise only); confirmed mechanical fixes are applied and scope or approach changes wait for the user.
- **build** — Executes a plan gate by gate under TDD: verifies guessed assumptions first, opens each gate with failing tests at its declared mix, closes it only when lint, format, test, and build pass, records deviations, replans when the code refutes the plan, and ends with the review pipeline. Progress lives in `plan.json` under the task loop, so it survives context resets.
- **code-review-pipeline** — One reviewer covers correctness, security, structure, tests, docs, and (when the change makes a structural choice) design; a verifier batched per file tries to refute the critical and high findings against the code and defends the design against design findings. Confirmed implementation issues are fixed; design findings are always the user's decision.

### Agents (5)

Registered as `amux:<name>`; skills dispatch them and none are meant to be invoked directly. Agents declare no tool list, so they inherit whatever research MCPs your environment has. Three roles pin Claude Fable, where a wrong judgment silently drops a finding or misdirects the build; Fable is optional, and switching those files to `model: inherit` changes nothing else.

- **review-change** — the single code reviewer: six sections, each filled even when empty, with design findings carrying checkable premises
- **review-plan** — the single plan reviewer: assumptions ledger, completeness, gate graph, scope drift, each judgment with a premise
- **verify** (Fable) — the adversary, per batch of findings sharing a file or section: refutes implementation claims against the code, defends the design, fact-checks plan claims, and asks Codex once to argue the other side
- **premortem** (Fable) — assumes the recommended approach was built and failed, tests each post-mortem against the evidence and kill criteria, and gets Codex's dissent
- **build-plan** (Fable) — writes `prd.md`: real quality commands, vertical TDD gates with named RED tests, every surviving risk covered

### Commands (6)

`/amux:research`, `/amux:planning`, `/amux:spike`, `/amux:plan-review`, `/amux:build`, `/amux:code-review-pipeline` (add `thorough` to verify medium findings too).

### Hooks

Nothing runs automatically. **session-start** announces the skills and whether Codex (needs the Codex CLI and `python3`) is available. **task-loop-hook** blocks exit while any `task-loop.json` has `complete: false`, so research and build runs aren't abandoned mid-flight; opt out per session with `AMUX_SKIP_TASK_LOOP=1`.

### Artifacts written to your repo

| Path | Written by | Suggested handling |
|---|---|---|
| `plans/{slug}/prd.md`, `plan.json`, `notes/` | planning, spike, plan-review, build | Commit: the record of why the code looks the way it does. `spikes/` holds throwaway code; ignore or delete it once recorded |
| `spikes/{name}/` | spike (standalone) | Throwaway; delete once the result is recorded |
| `research/{slug}/report.md` | research | Commit the report; `state.json`, `findings.json`, `task-loop.json` are working files |
| `reviews/{branch}.md` | code-review-pipeline | Commit or ignore; regenerated on every review of the branch |

## How it stays honest

| Skill | Who finds | Who attacks | What survives |
|---|---|---|---|
| code-review-pipeline | review-change | verify refutes implementation claims against the code and defends the design | CONFIRMED implementation findings are fixed; design findings go to the user at any verdict |
| plan-review | review-plan | verify fact-checks empirical claims and the premises of judgment claims | CONFIRMED mechanical fixes are applied; judgment calls with intact premises go to the user |
| planning | the evaluation | premortem, in fresh context, with Codex arguing for the alternative; spike turns a testable unknown into a fact | surviving failure modes become risks the build plan must cover; a falsified spike kills the approach |
| research | researchers | challengers verify each citation and search for counter-evidence, with Codex's objections as leads | CONFIRMED findings may be high confidence; DISPUTED go to Conflicting Information; REFUTED are dropped |
| build | the gate's implementation | the gate's RED tests, written first and checked against a constant-returning stub; the review pipeline at the end | a gate closes only with tests that failed first and quality commands green |

Verdicts require cited evidence everywhere. "Seems fine" is not a refutation; "probably" is not a confirmation; PLAUSIBLE is always legitimate.

### Codex

Codex argues against things; it never co-authors a finding. The verifier asks it to refute or defend, the pre-mortem asks it to dissent, challengers ask it for the case against, and the spike can ask it to run the experiment independently. Reviewers and researchers don't call it. The canonical standard is [`docs/dual-engine.md`](docs/dual-engine.md).

Codex CLI removed `codex mcp-server` in 0.154.0 and its replacement, `codex app-server`, is not MCP, so the plugin serves the `codex` tool itself: [`mcp/codex.py`](mcp/codex.py), a standard-library Python stdio MCP server that runs one `codex exec` per call (read-only sandbox by default) and returns the final message. Knobs: `AMUX_CODEX_BIN` (binary not on `PATH`) and `AMUX_CODEX_TIMEOUT` (seconds, default 900). A community wrapper over app-server such as [codex-app-mcp](https://github.com/abetoots/codex-app-mcp) exposes the same tool; register one under the server name `codex` in your own MCP config and it takes precedence.

### Tools

The skills prescribe evidence standards, not tools: current docs beat training data for version-specific claims, primary sources beat articles about them, repo claims cite `file:line`. Agents check their tool list for docs, search, and codebase tools before falling back to the built-ins. To prefer specific tools, say so in your own `CLAUDE.md`; the agents honor it and the plugin never goes stale when you swap one.

### Validation

`bash scripts/validate.sh` checks the manifests, hooks, the codex MCP shim (manifest wiring, syntax, and a protocol smoke test that needs no real Codex), agent names, model policy, and tool-list policy, references, the Codex model name against `docs/dual-engine.md`, and the counts in this README. CI runs it on every push and pull request.

## Prerequisites

- **Claude Code** with plugin support
- **Codex CLI** (optional, for the second engine): `npm i -g @openai/codex`, plus `python3` for the plugin's codex MCP shim
- **Research MCPs** (optional): the skills use whatever docs, search, scrape, or codebase tools you have installed; the built-in `WebSearch` and `WebFetch` always work

## Installation

```bash
/plugin marketplace add guyathomas/amux-marketplace
/plugin install amux@amux-marketplace
```

Verify with `/help`, which should list `/amux:research`, `/amux:planning`, and the rest.

## License

MIT — see [LICENSE](LICENSE)
