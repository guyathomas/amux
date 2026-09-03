---
name: planning
description: Use before implementing any non-trivial feature - validates approaches against real sources (current docs, web search, analogous codebases) before committing. Evaluates with dual engines before committing to an implementation
---

# Planning

## Overview

Research-first planning. Validate approaches against real documentation, real codebases, and real implementations before writing code. Dual-engine evaluation cross-validates feasibility, and a pre-mortem attacks the recommendation before the user sees it.

**Core principle:** No implementation without evidence-backed, cross-validated approach selection that has survived its own pre-mortem.

**Announce at start:** "I'm using the planning skill to research approaches before implementation."

## When to Use

- New feature requiring architectural decisions
- Unfamiliar library or pattern
- Multiple valid approaches exist
- User asks "how should we build X?"

**Don't use for:** Single-line fixes, obvious bugs, tasks with explicit instructions.

## Suggested research

Reach for whatever tools you have available to gather evidence — which and how many is your call. The skill doesn't prescribe specific research tools; pick what fits the problem from what's installed. RESEARCH runs these in parallel as subagents.

Kinds of evidence worth gathering:
- Current library/framework API docs — version gotchas, deprecations
- Real-world implementations, best-practice articles, comparisons
- How production codebases structure this; common pitfalls
- Source-level patterns and conventions from the actual code

The one fixed tool is **Codex** (`gpt-5-codex`) — the second engine for EVALUATE (see the dual-engine standard). Everything else is your choice from what your environment provides.

## Dual-engine standard

Where this skill calls the `codex` MCP tool, use `model: gpt-5-codex`, `sandbox: read-only`, `cwd:` the repo root. Treat Codex as **unavailable** if the call throws/times out or returns empty/non-JSON/MCP-error text (e.g. `"Codex CLI Not Found"`) — then proceed Claude-only.

## State Persistence

All planning artifacts are persisted to enable plan-to-review linkage:

```
plans/{slug}/
  state.json          # phase, timestamp, selected approach
  approaches.json     # the candidate approaches with evidence
  claude-eval.json    # Claude's evaluation
  codex-eval.json     # Codex's evaluation (or skip marker)
  merged-eval.json    # merged evaluation result + pre-mortem of the recommendation
  spikes.json         # optional: time-boxed experiments that settled open feasibility questions
  spikes/{name}/      # optional: the throwaway spike code itself — never merged
  plan-review.json    # multi-agent critique of the selected plan
  prd.md              # destination doc: goal, approach, TDD-gated build plan
```

Generate slug from feature name: lowercase, hyphens for spaces, strip special chars, truncate to 50 chars.

**state.json:**
```json
{
  "feature": "description",
  "phase": "UNDERSTAND|RESEARCH|FORMULATE|EVALUATE|SPIKE|PRESENT|SELECTED|BUILD-PLAN|REVIEW-PLAN",
  "timestamp": "ISO-8601",
  "selectedApproach": null
}
```

## The Process

`UNDERSTAND → RESEARCH → FORMULATE → EVALUATE → [SPIKE] → PRESENT → SELECTED → BUILD-PLAN → REVIEW-PLAN`

SPIKE is optional: it runs only when EVALUATE leaves a feasibility question that research can't settle but a small, time-boxed experiment can. The full multi-agent plan critique runs **last**, on the assembled `prd.md` — gate-level lenses (dependency ordering, vertical-slice, right-sizing, real RED tests) need the gates to exist first. A lightweight sanity pass at SELECTED guards against decomposing an obviously-doomed approach.

### UNDERSTAND

Clarify scope with the user. Identify:
- What the feature needs to do
- Constraints (performance, compatibility, existing patterns)
- Technologies already in use

Check for an existing `plans/{slug}/` directory first. If one exists with `phase: "SELECTED"`, the feature was already planned — ask the user whether to reuse the existing plan, extend it, or start fresh. If it exists with an earlier phase, offer to resume from where it left off.

Create `plans/{slug}/` directory (if new) and initialize `state.json` with `phase: "UNDERSTAND"`.

### RESEARCH

Gather evidence from whatever research tools you have available (see **Suggested research** at top) that fit the problem — you decide which and how many. Run them in parallel using subagents, and read the codebase directly as warranted. Ground approaches in real evidence, not guesses.

Whatever tools you reach for, aim to establish:
- **Current library/API docs** — real signatures, version-specific gotchas, recommended patterns, deprecations for each relevant library.
- **Real-world implementations** — how others solve this; best-practice patterns; comparison articles and official guides.
- **Analogous production code** — how real codebases structure this and the pitfalls they hit.
- **Source-level conventions** — patterns in the actual code you'll integrate with (structure and conventions, not just API signatures).

Update `state.json` with `phase: "RESEARCH"`.

### FORMULATE

Formulate a set of genuinely distinct approaches — enough to give the user a real choice, as many as the problem warrants. Avoid a false "simple vs. complex" binary; surface meaningfully different options.

For each approach, provide:

```
### Approach N: [Name]

**How it works:** [2-3 sentences]

**Evidence:**
- Docs: [what current library/API docs say about this approach]
- Prior art: [what real-world implementations / articles recommend]
- Production code: [how real codebases do it]
- Source: [what the actual source reveals about patterns/structure] (if gathered)

**Trade-offs:**
- Pro: [concrete benefit with source]
- Pro: [concrete benefit with source]
- Con: [concrete drawback with source]

**Fits this project because:** [why this works for the specific codebase]

**Ruled out if:** [the concrete evidence that would make this the wrong choice — a constraint it can't meet, a dependency that turns out unsupported, a scale it can't reach]
```

State each approach's kill criteria up front, while you have no favorite. They're what EVALUATE's pre-mortem tests against, and an approach whose author can't say what would rule it out hasn't been thought through.

Write `plans/{slug}/approaches.json`:
```json
[
  {
    "index": 1,
    "name": "Approach Name",
    "howItWorks": "description",
    "evidence": { "docs": "...", "priorArt": "...", "productionCode": "...", "source": "..." /* include whichever evidence types you gathered */ },
    "tradeoffs": { "pros": ["..."], "cons": ["..."] },
    "fitReason": "...",
    "killCriteria": ["evidence that would rule this approach out"]
  }
]
```

Update `state.json` with `phase: "FORMULATE"`.

### EVALUATE

Dual-engine evaluation of the formulated approaches. Claude evaluates inline, then calls `codex` MCP tool for Codex's perspective, merges the results, and then attacks the merged recommendation with a pre-mortem before presenting it.

**Step 1 — Claude evaluation:**

Evaluate `approaches.json` against the project context. Read:
- `plans/{slug}/approaches.json`
- Relevant project files (package.json, existing architecture, etc.)

Produce evaluation as JSON:
```json
{
  "engine": "claude",
  "evaluations": [
    {
      "approachIndex": 1,
      "feasibility": "high|medium|low",
      "risks": ["risk 1", "risk 2"],
      "strengths": ["strength 1"],
      "implementationNotes": "specific details"
    }
  ],
  "preferredApproach": 1,
  "reason": "why this approach is best"
}
```

Write to `plans/{slug}/claude-eval.json`.

**Step 2 — Codex evaluation via MCP:**

Call the `codex` MCP tool per the **dual-engine standard** (see top), with `prompt`: include the contents of `approaches.json` and ask Codex to evaluate each approach for feasibility, risks, strengths, and implementation notes, returning the same evaluation JSON with `"engine": "codex"`. Use `@` repo-relative file references (e.g. `@package.json`, `@tsconfig.json`) resolved via `cwd`.

If valid, write it to `plans/{slug}/codex-eval.json`.

If unavailable, write a skip marker:
```json
{"engine": "codex", "status": "skipped — codex MCP unavailable"}
```
Report: `"Codex evaluation: skipped (unavailable)"`

**Step 3 — Inline merge:**

Compare the two evaluations by approach index:

| Pattern | Classification | Action |
|---|---|---|
| Both prefer same approach | **AGREE** | Strong signal. Merge rationales. |
| Different preferred approaches | **CHALLENGE** | Surface both rationales. Flag for human decision. |
| One engine identifies a risk/strength the other missed | **COMPLEMENT** | Merge into the approach's evaluation. |

Produce merged evaluation:
```json
{
  "approaches": [
    {
      "index": 1,
      "name": "approach name",
      "claudeEval": { "feasibility": "high", "risks": [], "strengths": [] },
      "codexEval": { "feasibility": "high", "risks": [], "strengths": [] },
      "merged": {
        "feasibility": "high",
        "risks": ["merged unique risks from both"],
        "strengths": ["merged unique strengths from both"],
        "classification": "AGREE|CHALLENGE|COMPLEMENT"
      }
    }
  ],
  "recommendation": {
    "approachIndex": 1,
    "confidence": "high|medium|low",
    "reason": "Both engines agree on approach 1 due to...",
    "dissent": null
  },
  "summary": {
    "agreement": "full|partial|none",
    "enginesUsed": ["claude", "codex"]
  }
}
```

If Codex was unavailable, pass through Claude eval with `"enginesUsed": ["claude"]` and `"confidence": "medium"` (single-engine, lower confidence).

**Step 4 — Pre-mortem (adversarial):**

Two engines agreeing is not proof: both evaluated cooperatively, from the same `approaches.json`, and can share a blind spot. Before the recommendation reaches the user, attack it.

1. **Claude pre-mortem.** Assume the recommended approach was built and failed. Write the most likely post-mortems (usually 2-4): for each, the failure scenario, what triggers it, the evidence gathered in RESEARCH (docs, repo, prior art) that makes it likely or unlikely, and the mitigation if one exists. Check the recommended approach against its own `killCriteria` from FORMULATE — does any evidence already on hand meet one?
2. **Codex dissent.** Call `codex` per the **dual-engine standard** with `prompt`: "Approach {N} was recommended over the others in `approaches.json` (contents included). Argue the strongest case AGAINST approach {N} and FOR the strongest alternative, citing `@` repo files and the evidence in the approaches. Return JSON: `{ "against": [{ "scenario": "...", "trigger": "...", "evidence": "..." }], "forAlternative": { "index": 2, "reason": "..." }, "wouldChangeRecommendation": true|false }`." If unavailable, the pre-mortem is Claude-only — say so.
3. **Judge what survives.** A failure mode survives when neither engine could cite evidence that mitigates it; one that is mitigated by cited evidence is recorded as addressed. Then:
   - Surviving failure modes become `risks` on the recommended approach, and their mitigations become build-plan input (BUILD-PLAN should give each a gate step or a verification task). A surviving failure mode that a small experiment could settle — "does the library actually do X under our config", "is Y fast enough" — is a SPIKE candidate; don't carry an empirically testable unknown into PRESENT as a risk when an hour's experiment would turn it into a fact.
   - If a surviving failure mode meets a kill criterion, or Codex's dissent is evidence-backed and `wouldChangeRecommendation` is true, do not paper over it: either change the recommendation or lower its confidence and set `recommendation.dissent` to the case against. The user chooses with the case against in view.

Record it in `merged-eval.json`:
```json
{
  "preMortem": {
    "target": 1,
    "failureModes": [
      { "scenario": "...", "trigger": "...", "evidence": "...", "mitigation": "...", "survives": true, "meetsKillCriterion": false }
    ],
    "codexDissent": { "forAlternative": 2, "reason": "...", "wouldChangeRecommendation": false },
    "recommendationChanged": false,
    "enginesUsed": ["claude", "codex"]
  }
}
```

Write the full merged evaluation (Step 3 plus `preMortem`) to `plans/{slug}/merged-eval.json`.

Update `state.json` with `phase: "EVALUATE"`.

### SPIKE (optional — only when a feasibility question is still open)

A spike is a time-boxed, throwaway experiment that turns an unknown into a fact. Research answers "what do the docs say"; a spike answers "what actually happens here." Run this phase only when it's earned:

**Triggers (any one):**
- A surviving pre-mortem failure mode, or a kill criterion, whose evidence is *unknown* rather than *unfavourable* — docs, the repo, and prior art don't settle it, but a small experiment would.
- The engines CHALLENGE each other on an approach's **feasibility** (not its taste), or the recommendation's `confidence` is `low`/`medium` for a reason that is empirically testable: does the library support X under our version and config; does the API accept Y; is Z within the performance budget; does the existing module tolerate being called that way.
- Two approaches are otherwise close and the deciding factor is a measurable property (latency, bundle size, migration time).

**Not triggers:** an unknown that a docs lookup or `Grep` settles (go back and look); a judgment call (simpler vs. more flexible — that's the user's); an experiment that would cost a meaningful fraction of the build itself (that's not a spike, it's the first gate — plan it).

**Design each spike adversarially before running it.** Write down, and record in `spikes.json`:
1. **Question** — one sentence, answerable yes/no or with a number.
2. **Which approach(es)** it bears on, and which kill criterion or failure mode it tests.
3. **Falsified if** — the result that would rule the approach out, stated *before* the experiment runs. A spike without a pre-stated failure condition can't fail, so it can't inform anything.
4. **Time box** — small: a handful of files, no tests, no lint, no polish. If it's blowing the box, the answer is "harder than it looked" — record that and stop.
5. **Confounds** — what would make a pass meaningless (mocked the thing under test; ran against a different version than production; measured the wrong path). Optionally ask `codex` per the **dual-engine standard** to poke holes in the design: "Would this experiment actually settle the question? What result would pass for the wrong reason?" A spike that passes for the wrong reason is worse than no spike.

**Announce before running:** the spike(s), the question each answers, the falsification criterion, and the time box. Ask the user first if a spike needs credentials, external services, real data, or more than a small time box.

**Run it in isolation.** Spike code lives in `plans/{slug}/spikes/{name}/` (a self-contained script or mini-project) or, if it must touch the repo, in a throwaway git worktree or branch. It is never merged: the real implementation is built through BUILD-PLAN's TDD gates, and the spike's only outputs are its result and what it taught. Capture the evidence — command output, numbers, the error message — not a summary of it.

**Record and act.** Write `plans/{slug}/spikes.json`:
```json
[
  {
    "name": "streaming-upload-size",
    "question": "Does the storage SDK stream a 2 GB upload without buffering in memory under Node 22?",
    "approachIndex": 1,
    "tests": "kill criterion: memory > 512 MB on large uploads",
    "falsifiedIf": "RSS exceeds 512 MB during a 2 GB upload",
    "timeBox": "45 min / 2 files",
    "location": "plans/{slug}/spikes/streaming-upload-size/",
    "result": "confirmed|falsified|inconclusive",
    "evidence": "peak RSS 180 MB over 2 GB upload (spike output, run 2026-09-03)",
    "confounds": ["local disk, not the production object store — network backpressure untested"],
    "ranAt": "ISO-8601"
  }
]
```
Then update the artifacts the result touches:
- **confirmed** — attach it as `evidence.spike` on the approach in `approaches.json`, raise the approach's feasibility in `merged-eval.json`, and mark the failure mode `survives: false` with the spike as the mitigation.
- **falsified** — the kill criterion is met: drop or demote the approach in `merged-eval.json` and change the recommendation. If the recommended approach dies and no other holds up, loop back to FORMULATE/EVALUATE with what the spike taught.
- **inconclusive** — keep the failure mode as a surviving risk and carry it as a pre-build verification task; note the confound that blocked a verdict so REVIEW-PLAN's assumptions reviewer can see it was tried.

Update `state.json` with `phase: "SPIKE"`. If no trigger fires, skip this phase entirely and say so in one line at PRESENT ("no spike needed — feasibility settled by research").

### PRESENT

Present the candidate approaches to the user with:
1. The original evidence from RESEARCH
2. The cross-validated evaluation from EVALUATE (merged-eval.json)
3. Highlight where engines agreed (strong signal) or disagreed (flag for human decision)
4. The pre-mortem: the surviving failure modes of the recommended approach, whether any met a kill criterion, and Codex's dissent if it argued for an alternative — the case *against* the recommendation, shown next to the case for it
5. Spike results, if any ran: the question, the verdict, the evidence, and any confound that limits it — or the one-line note that no spike was needed

State your recommendation, incorporating merge confidence and the pre-mortem. A recommendation presented without its surviving failure modes is a sales pitch, not an evaluation. Wait for user selection before writing any code.

### SELECTED

Record the user's choice:
- Update `state.json` with `phase: "SELECTED"` and `selectedApproach: N`

**Light sanity pass before decomposing.** Run one quick Claude check on the selected approach against the codebase: is it obviously infeasible (names a module/API that doesn't exist, contradicts a hard constraint)? If the user picked an approach other than the recommended one, re-read its `killCriteria` and the pre-mortem — the case against the *chosen* approach should be as visible as the case against the recommended one was, and if it carries an open feasibility question that only the recommended approach was spiked for, offer to run SPIKE on it before decomposing. This is cheap insurance so BUILD-PLAN doesn't decompose a doomed approach. If it trips, loop back to FORMULATE/EVALUATE. The full multi-agent critique comes later, in REVIEW-PLAN. Otherwise proceed to BUILD-PLAN.

### BUILD-PLAN

Turn the selected approach into a destination document the implementer (or an autonomous loop) executes gate by gate. Output a single `prd.md` — a summary of the shared understanding already reached, plus an ordered set of gates. You usually won't need to re-read it.

Detect the project's quality commands once, up front: read `package.json` scripts (or the repo's Makefile/CI config) for the real lint, format, test, and build commands. Record them in `prd.md` so every gate references the same ones.

Break the work into the fewest gates that each deliver a working vertical slice — small enough to fit one context window (keep tasks small). Every gate is TDD-gated: it opens by writing failing tests and closes only when lint, format, test, and build all pass.

Carry the pre-mortem forward: each surviving failure mode in `merged-eval.json` gets a home in the plan — a RED test that would catch it, a verification step before the gate that depends on it, or an explicit note in the gate's exit criteria. A risk the plan knows about and doesn't test for is a risk the implementer will rediscover the hard way.

Carry the spikes forward too, as knowledge rather than code: what a spike learned (the API shape that worked, the config that was needed, the gotcha it hit) goes into the notes of the gate that builds the real thing, and a confirmed spike's scenario usually becomes that gate's RED test. Spike code itself stays in `plans/{slug}/spikes/` — the gate rebuilds it properly, tests first.

**Per-gate test mix.** Each gate declares which test levels its Red phase uses, chosen from the changes in that gate — not a fixed quota:
- **Unit** — pure logic, transformations, edge cases. Almost every gate has some.
- **Integration** — the gate crosses a module/service/DB/API boundary, wires components together, or changes a contract between them.
- **E2E** — the gate completes a user-visible flow (UI path, CLI invocation, API endpoint end to end). Usually the final gate(s) of a slice; don't force E2E onto internal-only gates.

Prefer the cheapest level that would catch the gate's likely regressions; add a level only when the changes actually exercise it. State the mix and a one-line rationale in the gate so the implementer doesn't have to re-derive it.

Write `plans/{slug}/prd.md`:

```markdown
# {Feature}

## Goal
[2-3 sentences — the shared understanding from UNDERSTAND.]

## Selected approach
[1-2 sentences; references approach N in approaches.json.]

## Quality commands
- Lint: `<cmd>`
- Format: `<cmd>`
- Test: `<cmd>`
- Build: `<cmd>`

## Gates
Execute in order. Do not start a gate until the previous gate's exit criteria are green.

### Gate 1: [name]
**Test mix:** [unit / integration / E2E — the levels this gate's changes warrant, with one-line rationale]
**Red (tests first):** the failing tests that define "done" for this slice, at each level in the mix.
**Green:** the minimum implementation to pass them.
**Exit criteria:** lint, format, test, build all pass — including every level in the test mix.

### Gate 2: [name]
...
```

Update `state.json` with `phase: "BUILD-PLAN"`. Proceed to REVIEW-PLAN before presenting the plan as final — don't ship gates that haven't been stress-tested.

### REVIEW-PLAN

Stress-test the assembled `prd.md` (approach + gates together) with the **multi-agent plan critique** before any code is written. An approach can win EVALUATE yet still ship with unverified assumptions, missing non-functional work, out-of-order gates, or quiet scope creep — this phase catches that.

**Delegate to the `plan-review` skill** on `plans/{slug}/`. It dispatches four parallel dual-engine reviewers (assumptions, completeness, structure, scope), aggregates by severity, **auto-applies mechanical fixes** to `prd.md`, and **gates scope/approach changes** for your decision. It writes `plans/{slug}/plan-review.json` and converges (re-review until build-ready, max 2 rounds).

Scale to complexity: a small, well-specified plan may only need a quick pass; the four-reviewer team earns its cost on genuinely complex or risky work. Either way, run it through `plan-review` so the apply/confirm split and assumption ledger are consistent.

After it returns, update `state.json` with `phase: "REVIEW-PLAN"` and:
- Resolve every `pendingConfirm` finding with the user. If one invalidates the approach, loop back to FORMULATE/EVALUATE.
- Surface the `guessedAssumptions` ledger as pre-build verification tasks.
- Present the final gate list only once the plan is `buildReady`. Don't decompose or rewrite a plan's intent the user hasn't blessed.

**Replan on failure.** A plan rarely survives first contact with the code. If implementation hits a wall the plan didn't anticipate (wrong assumption, infeasible step, discovered constraint), stop and loop back to FORMULATE/EVALUATE with what you learned rather than forcing the original plan through.

## Plan-to-Review Linkage

The `core:review-code` agent can read `plans/{slug}/approaches.json` and `state.json` to validate that implementation matches the selected approach. When running code review after a planned feature, reference the plan directory.

## Red Flags

Never: guess approaches without evidence; present hypothetical (non-sourced) approaches; formulate an approach with no kill criteria; present a recommendation without its pre-mortem, or bury a surviving failure mode because both engines liked the approach; run a spike without a pre-stated falsification criterion, spike what a docs lookup would settle, let a spike grow into the implementation, or merge spike code; collapse the options into a single recommendation before the user has chosen; start implementation before the user selects and the plan clears REVIEW-PLAN; skip EVALUATE, the pre-mortem, or REVIEW-PLAN even when Codex is unavailable (Claude-only still adds value); start a gate's implementation before its tests are red, or close a gate with lint, format, test, or build failing; write a gate with no declared test mix, or a mix that ignores the gate's boundaries (e.g. unit-only for a gate that crosses a service/DB boundary, or no E2E on the gate that completes a user-facing flow).

If a resource is unavailable, note the gap and fall back (e.g. WebSearch) — still deliver evidence-backed approaches. If Codex is unavailable, proceed with Claude-only eval (`enginesUsed: ["claude"]`).
