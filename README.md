# Amux

Research, planning, build, and review skills for Claude Code. One agent finds, an independent agent with fresh context tries to break what it found, and only cited evidence drives action. Codex, when installed, is asked for a second opinion wherever something is being argued against.

## What's Included

### Skills (4)

Invoke as `/amux:<name>` or let Claude pick one when the request matches.

- **planning** — Researches approaches against real sources, states what would rule each one out, attacks the recommendation with a fresh-context pre-mortem, spikes any feasibility question still open (optionally on Codex and Claude independently; disagreement means inconclusive), writes a TDD-gated plan once you choose, then reviews it with an independent verifier and applies only confirmed mechanical fixes. `/amux:planning review {slug}` re-reviews an existing plan.
- **build** — Executes a plan gate by gate under TDD: verifies guessed assumptions first, opens each gate with failing tests, closes it only when lint, format, test, and build pass, records deviations, replans when the code refutes the plan, and ends with the review pipeline. Progress lives in `plan.json`, so it survives context resets.
- **code-review-pipeline** — One reviewer covers correctness, security, structure, tests, docs, and (for structural changes) design; a verifier batched per file tries to refute the critical and high findings. Confirmed implementation issues are fixed; design findings are always your decision. Add `thorough` to verify medium findings too.
- **research** — Decomposes a topic into the questions that matter, researches them in parallel, has independent challengers verify each load-bearing citation and search for counter-evidence, iterates until the questions are answered, and writes a report with source attribution and confidence.

### Agents (4)

Registered as `amux:<name>`; skills dispatch them. Agents declare no tool list, so they inherit whatever research MCPs your environment has. Three roles pin Claude Fable, where a wrong judgment silently drops a finding or misdirects the build; switching those files to `model: inherit` changes nothing else.

- **review** — the single reviewer, in mode `change` (six sections over a diff) or `plan` (assumptions, completeness, gate graph, scope); every judgment carries a checkable premise
- **verify** (Fable) — the adversary, per batch of findings sharing a file or section: refutes implementation claims against the code, defends the design, fact-checks plan claims, and asks Codex once to argue the other side
- **premortem** (Fable) — assumes the recommended approach was built and failed, tests each post-mortem against the evidence and kill criteria, and gets Codex's dissent
- **build-plan** (Fable) — writes `prd.md`: real quality commands, vertical TDD gates with named RED tests, every surviving risk covered

### Artifacts written to your repo

| Path | Written by | Suggested handling |
|---|---|---|
| `plans/{slug}/prd.md`, `plan.json`, `notes/` | planning, build | Commit: the record of why the code looks the way it does |
| `plans/{slug}/spikes/` | planning | Throwaway; delete once recorded |
| `research/{slug}/report.md` | research | Commit the report; `state.json` and `findings.json` are working files |
| `reviews/{branch}.md` | code-review-pipeline | Commit or ignore; regenerated on every review |

## How it stays honest

| Skill | Who finds | Who attacks | What survives |
|---|---|---|---|
| planning | the evaluation; the plan reviewer | premortem with Codex dissent; spikes with a pre-stated falsifier; verify on plan findings | surviving failure modes become risks the plan must cover; only CONFIRMED mechanical fixes edit the plan |
| build | the gate's implementation | RED tests written first and checked against a constant stub; the review pipeline at the end | a gate closes only with tests that failed first and quality commands green |
| code-review-pipeline | review | verify refutes against the code and defends the design | CONFIRMED implementation findings are fixed; design goes to you |
| research | researchers | challengers verify citations and search for counter-evidence | CONFIRMED may be high confidence; DISPUTED are reported as conflicts; REFUTED are dropped |

Verdicts require cited evidence everywhere. "Seems fine" is not a refutation; "probably" is not a confirmation; PLAUSIBLE is always legitimate.

### Codex

Codex argues against things; it never co-authors a finding. `verify`, `premortem`, research challengers, and planning's optional dual-engine spike run `codex exec` directly through Bash (read-only sandbox, except the spike's `workspace-write` run confined to its directory) using your Codex CLI's default model. Without Codex every path runs Claude-only and says so.

### Validation

`bash scripts/validate.sh` checks the manifests, skill and agent names, model and tool-list policy, references, stale references to removed components, and the counts in this README. CI runs it on every push and pull request.

## Prerequisites

- **Claude Code** with plugin support
- **Codex CLI** (optional, for second opinions): `npm i -g @openai/codex`
- **Research MCPs** (optional): the skills use whatever docs, search, or codebase tools you have; the built-in `WebSearch` and `WebFetch` always work

## Installation

```bash
/plugin marketplace add guyathomas/amux-marketplace
/plugin install amux@amux-marketplace
```

## License

MIT — see [LICENSE](LICENSE)
