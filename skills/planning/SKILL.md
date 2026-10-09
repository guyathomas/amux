---
name: planning
description: Use before implementing any non-trivial feature. Researches approaches against real sources, states what would rule each one out, evaluates them and attacks the recommendation with a pre-mortem, runs a spike when a feasibility question is still open, writes a TDD-gated plan once the user chooses, and stress-tests it before any code is written.
---

# Planning

No implementation without an evidence-backed approach that the user chose with the case against it in view. Announce at start: "I'm using the planning skill to research approaches before implementation."

**Use for:** features with architectural decisions, unfamiliar libraries or patterns, anything with more than one valid approach, "how should we build X?". **Not for:** one-line fixes, obvious bugs, tasks with explicit instructions.

## Artifacts

```
plans/{slug}/
  prd.md          # the plan: goal, approach, quality commands, TDD gates
  plan.json       # state: scope, approaches, evaluation, spikes, review, build
  notes/          # free-form working notes, organized however you like
  spikes/{name}/  # throwaway spike code, never merged
  task-loop.json  # written by the build skill
```

Slug: lowercase, hyphens, `a-z0-9-` only, at most 50 characters. `plan.json`:

```json
{
  "feature": "...",
  "phase": "UNDERSTAND|RESEARCH|FORMULATE|EVALUATE|SPIKE|PRESENT|SELECTED|BUILD-PLAN|REVIEW-PLAN",
  "scope": "the ask as understood: what it must do, constraints, technologies in play",
  "approaches": [],
  "evaluation": null,
  "spikes": [],
  "selectedApproach": null,
  "review": null,
  "build": null,
  "updatedAt": "ISO-8601"
}
```

Update `phase` and `updatedAt` as you go, so a context reset can resume. On invocation, if `plans/{slug}/plan.json` exists, offer to resume from its phase (or reuse, extend, or restart a plan past SELECTED).

## Research

Reach for whatever tools your environment provides; the skill prescribes none. Check your tool list for docs, search, and codebase tools before falling back to the built-ins, and use any tools the user's own instructions prefer. Evidence standards: current docs beat training data for version-specific claims; primary sources beat articles about them; cite a URL or doc section for library claims and `file:line` for repo claims.

Codex is used only where it argues against something: the pre-mortem, the verifier, and the optional dual-engine spike. See `docs/dual-engine.md`.

## Process

`UNDERSTAND → RESEARCH → FORMULATE → EVALUATE → [SPIKE] → PRESENT → SELECTED → BUILD-PLAN → REVIEW-PLAN`

### UNDERSTAND
Clarify with the user what the feature must do, its constraints, and the technologies already in use. Write it as `scope` in `plan.json`; the scope reviewer later measures drift against this text, so make it the ask, not a plan.

### RESEARCH
Gather evidence in parallel (subagents where it helps) on: current library and API docs for the pieces involved (signatures, version gotchas, deprecations); real-world implementations and comparisons; how production codebases structure this and the pitfalls they hit; and the conventions of the code you will integrate with. Keep notes under `notes/`.

### FORMULATE
Write genuinely distinct approaches, as many as the problem warrants, never a false simple-versus-complex binary. For each: how it works, evidence by kind (docs, prior art, production code, source), concrete pros and cons with sources, why it fits this codebase, and **kill criteria**: the evidence that would rule it out. State kill criteria now, while you have no favorite. Store them under `approaches` in `plan.json`:

```json
{ "index": 1, "name": "...", "howItWorks": "...", "evidence": { "docs": "...", "priorArt": "...", "productionCode": "...", "source": "..." }, "tradeoffs": { "pros": [], "cons": [] }, "fitReason": "...", "killCriteria": [] }
```

### EVALUATE
1. Evaluate each approach against the project (read `package.json`, the existing architecture, the relevant modules): feasibility, risks, strengths, implementation notes, and a preferred approach with the reason. Write it under `evaluation` in `plan.json`.
2. Dispatch one `amux:premortem` with `plan.json` and the repository root. It assumes the recommendation was built and failed, tests each failure mode against the evidence and the repo, checks the kill criteria, and asks Codex to argue for the strongest alternative. Store its result as `evaluation.preMortem`.
3. Act on it: surviving failure modes become risks the build plan must cover; a survivor marked `spikeCandidate` goes to SPIKE rather than to the user as a risk; if `recommendationShouldChange`, change the recommendation or lower its confidence and record the dissent. Never paper over a met kill criterion.

### SPIKE
Run only when a feasibility question is still open after EVALUATE: a surviving failure mode or kill criterion whose evidence is unknown rather than unfavourable; a recommendation whose confidence is low for an empirically testable reason; or two close approaches separated by a measurable property. Not for anything a docs lookup or Grep settles, not for judgment calls, and not for an experiment that would be a meaningful fraction of the build.

Delegate to the **`spike` skill** with the question, the approach it bears on, and the plan directory. It designs the experiment with a pre-stated falsification criterion, optionally runs it on both engines, records the result under `spikes` in `plan.json`, and updates the evaluation: a confirmed spike raises feasibility and retires the failure mode; a falsified one meets the kill criterion and changes the recommendation (loop back to FORMULATE/EVALUATE if nothing else holds up); an inconclusive one stays a risk with its confound noted.

### PRESENT
Show the user: the approaches with their evidence, the evaluation and recommendation, the pre-mortem (surviving failure modes, any kill criterion met, Codex's dissent), and spike results or the one-line note that none was needed. A recommendation without its surviving failure modes is a sales pitch. Wait for the user's choice before writing any code.

### SELECTED
Record `selectedApproach` and `phase: "SELECTED"`. One quick check: is the chosen approach obviously infeasible against the codebase (names a module or API that does not exist, contradicts a hard constraint)? If the user chose something other than the recommendation, re-read its kill criteria and the pre-mortem, and offer a spike if it carries an open feasibility question. If the check trips, loop back to FORMULATE/EVALUATE.

### BUILD-PLAN
Dispatch one `amux:build-plan` with `plan.json` and the repository root. It detects the real quality commands, slices the work into vertical TDD gates with a declared test mix and named RED tests, carries every surviving failure mode into a test or verification step, carries spike learnings into gate notes, and writes `prd.md`. If it returns `blockers`, loop back to FORMULATE/EVALUATE; do not present a plan its author says cannot be built. Check that every surviving failure mode appears in its `riskCoverage`.

### REVIEW-PLAN
Delegate to the **`plan-review` skill** on the plan directory. It reviews assumptions, completeness, structure, and scope; verifies the critical and high findings; applies confirmed mechanical fixes; and records the rest under `review` in `plan.json`. Resolve every `pendingConfirm` item with the user (an accepted change that invalidates the approach loops back to FORMULATE/EVALUATE), surface `guessedAssumptions` as pre-build checks, and present the final gate list once `buildReady`. Offer `/amux:build {slug}`.

**Replan on failure.** When the build hits a wall the plan did not anticipate, the build skill hands back here at FORMULATE/EVALUATE with what it learned. Do not force the original plan through.

## Never

Present approaches without evidence or without kill criteria; present a recommendation without its pre-mortem; run a spike without a pre-stated falsification criterion or merge spike code; collapse the options before the user chooses; start implementation before the user selects and the plan clears REVIEW-PLAN; skip the pre-mortem or the review because Codex is unavailable (Claude-only still adds value).
