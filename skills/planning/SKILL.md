---
name: planning
description: Use before implementing any non-trivial feature. Researches approaches against real sources, states what would rule each one out, attacks the recommendation with a pre-mortem, spikes open feasibility questions, writes a TDD-gated plan once the user chooses, and reviews it with an independent verifier before any code is written. Pass `review {slug}` to re-review an existing plan.
argument-hint: "[feature | review {slug}]"
---

# Planning

No implementation without an evidence-backed approach the user chose with the case against it in view. Announce: "I'm using the planning skill to research approaches before implementation."

**Use for:** architectural decisions, unfamiliar libraries, more than one valid approach. **Not for:** one-line fixes, obvious bugs, explicit instructions.

## State

`plans/{slug}/` holds `prd.md` (the plan), `plan.json` (state), `notes/` (free-form), and `spikes/{name}/` (throwaway code, never merged). Slug: `a-z0-9-`, at most 50 characters.

```json
{ "feature": "...", "phase": "UNDERSTAND|RESEARCH|FORMULATE|EVALUATE|SPIKE|PRESENT|SELECTED|BUILD-PLAN|REVIEW-PLAN",
  "scope": "...", "acceptanceCriteria": [{ "id": "AC1", "text": "..." }], "nonGoals": [], "approaches": [], "evaluation": null, "spikes": [], "selectedApproach": null, "review": null, "build": null, "toolsDegraded": [], "updatedAt": "ISO-8601" }
```

Write `phase` after every phase. If `plan.json` exists, offer to resume from its phase. `review {slug}` jumps straight to REVIEW-PLAN.

Evidence standards: current docs beat training data for version-specific claims, primary sources beat articles, cite a URL for library claims and `file:line` for repo claims.

**Tool check.** Before starting, tell the user in one short block which tool will serve each capability in the Tools section, which are not installed or not running, and whether Codex is available (`command -v codex`). Pass the Tools section into every subagent prompt you write yourself. The final output lists every `toolsDegraded` entry from you and your agents under **Tools degraded**, or says none were; append them to `toolsDegraded` in the state file as they arrive.

<!-- tools -->
## Tools

Pick by job and use the first option your tool list has. Tool preferences in the user's own instructions override this order. The built-ins at the end of each line always work.

- **Library or framework behaviour:** a docs tool that serves the exact version (e.g. Context7). When the docs are vague, silent, or disagree with what you observe, read the library's source: `git clone --depth 1` into a scratch directory outside the repo, or a source-indexing tool, and cite upstream `file:line`. Built-in: WebFetch on the official docs.
- **Prior art:** analogous open-source implementations, found with a GitHub tool or `gh search repos` / `gh search code`. Clone the promising ones and read the code, not the README.
- **Web search:** a search tool (e.g. Serper, Firecrawl search). Built-in: WebSearch.
- **Reading a page:** a scraping tool that renders JavaScript (e.g. Firecrawl). Built-in: WebFetch.
- **This repo:** Grep, Glob, Read; an LSP or code-intelligence tool when present.

Call out every gap; never degrade silently. Record each in `toolsDegraded` in your output, `[{ "capability": "web search", "tool": "Firecrawl", "status": "not-installed|not-running|quota-exhausted|error|timeout", "detail": "...", "fellBackTo": "WebSearch" }]`:
- **not-installed:** no non-built-in option for a capability you needed is in your tool list.
- **not-running:** your context says the server failed to connect, or every call fails to reach it.
- **quota-exhausted:** the tool reports exhausted credits, quota, or a rate limit. Do not retry it this run.
- **error / timeout:** after one retry.
Then move to the next option. Omit the field when nothing degraded.
<!-- /tools -->


## Process

### UNDERSTAND
Clarify the problem, who it is for, numbered acceptance criteria (AC1, AC2, … — observable behaviour a test can check), non-goals, constraints, and the technologies in play. Write the ask as `scope` (not a plan; the reviewer measures drift against it), and the criteria and non-goals as `acceptanceCriteria` and `nonGoals`.

### RESEARCH
In parallel: current docs for the libraries in play or under consideration, read in source where the docs fall short; analogous open-source implementations, read in code; how comparable products expose this feature (their public docs and changelogs); and the conventions of the code you will touch. Notes go in `notes/`.

### FORMULATE
Genuinely distinct approaches, never a false simple-versus-complex binary. Each in `approaches`: `index`, `name`, `howItWorks`, `evidence`, `tradeoffs` (pros and cons with sources), `fitReason`, and **`killCriteria`**: the evidence that would rule it out, stated now while you have no favorite.

### EVALUATE
1. Evaluate each approach against the actual repo: feasibility, risks, a preferred approach and why. Write `evaluation`.
2. Dispatch one `amux:premortem` with `plan.json` and the repo root. Store its result as `evaluation.preMortem`.
3. Surviving failure modes become risks the build plan must cover; a `spikeCandidate` survivor goes to SPIKE; if `recommendationShouldChange`, change the recommendation or lower its confidence and record the dissent. Never paper over a met kill criterion.

### SPIKE
Only when a question survives EVALUATE that a small experiment would settle and docs or Grep would not: a kill criterion whose evidence is unknown, low confidence for a testable reason, or two close approaches separated by a measurable property. Not for judgment calls or anything that is a meaningful fraction of the build.

1. **Design**, before anything runs: the question (yes/no or a number), what it bears on, **falsified if** (the result that rules the approach out), a time box (a few files, no polish — blowing it is a result), and confounds that would make a pass meaningless. Ask the user first if it needs credentials, external services, or real data.
2. **Run** in `plans/{slug}/spikes/{name}/claude/`, capturing output verbatim. When passing for the wrong reason is likely or the answer decides the approach, also give Codex the identical brief, without Claude's code, credentials, or data the user has not approved: `mkdir -p` its directory, then through Bash with a timeout set from the time box (at most 600000 ms), `out=$(mktemp); codex exec --skip-git-repo-check -s workspace-write -C plans/{slug}/spikes/{name}/codex -o "$out" -` with the brief on stdin, asking for `{ "result": "confirmed|falsified|inconclusive", "evidence": "...", "assumptions": [] }`. A timeout is recorded as "blew the time box". Afterwards `git status` and discard anything written outside the spike directory. Codex unavailable means Claude only; say so.
3. **Judge**: one engine — the evidence against the falsification criterion. Two engines — confirmed or falsified only when both agree; disagreement or a blown box is **inconclusive**, with both evidence blocks. Never resolve a disagreement by picking the answer you preferred.
4. **Record** under `spikes`: name, question, bearsOn, falsifiedIf, timeBox, confounds, runs, result. Confirmed retires the failure mode; falsified meets the kill criterion and changes the recommendation (back to FORMULATE if nothing else holds); inconclusive stays a risk and a pre-build check.

### PRESENT
Approaches with evidence, the recommendation, the pre-mortem (survivors, met kill criteria, Codex's dissent), spike results, and Tools degraded. A recommendation without its surviving failure modes is a sales pitch. Wait for the user's choice.

### SELECTED
Record `selectedApproach`. If the user chose against the recommendation, re-read its kill criteria and the pre-mortem and offer a spike for any open feasibility question. Obviously infeasible against the repo: back to FORMULATE.

### BUILD-PLAN
Dispatch one `amux:build-plan` with `plan.json` and the repo root; it writes `prd.md`. Returned `blockers` send you back to FORMULATE; `uncoveredCriteria` go to the user (cut the criterion or revisit UNDERSTAND). Check every surviving failure mode appears in `riskCoverage` and every acceptance criterion in `acceptanceCoverage`.

### REVIEW-PLAN
1. **Review.** Dispatch `amux:review` in mode `plan` with `prd.md`, `plan.json`, and the repo root.
2. **Verify.** Group the critical and high findings by plan section and dispatch one `amux:verify` per group in one request, each with its findings (`kind: plan`, ids, premises), the repo root, the plan directory, and the relevant `prd.md` excerpt. Empirical findings are fact-checked; judgment findings on their premise only. Medium and low pass as PLAUSIBLE, and a PLAUSIBLE `auto` finding becomes `confirm`. REFUTED findings are dropped (kept in the report with evidence); a verifier failure leaves findings PLAUSIBLE.
3. **Act.** Apply only findings that are `applyMode: auto` and CONFIRMED. If any critical or high finding was applied, review and verify once more. Every `confirm` finding goes to the user as a decision; one that invalidates the approach loops to FORMULATE.
4. **Record** `review`: `round`, `buildReady` (no critical or high finding left), `applied`, `pendingConfirm`, `refuted`, `guessedAssumptions` (each with `verifyBefore` gate), `summary`. Present applied, refuted, decisions, checks to run before building, medium/low suggestions, and Tools degraded. Once build-ready, offer `/amux:build {slug}`.

**Replan on failure.** When the build hits a wall the plan did not anticipate, it hands back here at FORMULATE with what it learned. Do not force the original plan through.

## Never

Approaches without evidence or kill criteria; a recommendation without its pre-mortem; a spike without a pre-stated falsification criterion, or merged spike code; a two-engine disagreement called confirmed; an unverified finding applied to the plan; implementation before the user selects and the plan clears review; skipping a stage because Codex is unavailable.
