---
name: planning
description: Use before implementing any non-trivial feature - validates approaches against real sources (current docs, web search, analogous codebases) before committing. Evaluates with dual engines before committing to an implementation
---

# Planning

## Overview

Research-first planning. Validate approaches against real documentation, real codebases, and real implementations before writing code. Dual-engine evaluation cross-validates feasibility.

**Core principle:** No implementation without evidence-backed, cross-validated approach selection.

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

Where this skill calls the `codex` MCP tool, use `model: gpt-5-codex`, `sandbox: read-only`, `cwd:` the repo root, and begin the prompt with `/fast`. Treat Codex as **unavailable** if the call throws/times out or returns empty/non-JSON/MCP-error text (e.g. `"Codex CLI Not Found"`) — then proceed Claude-only.

## State Persistence

All planning artifacts are persisted to enable plan-to-review linkage:

```
plans/{slug}/
  state.json          # phase, timestamp, selected approach
  approaches.json     # the candidate approaches with evidence
  claude-eval.json    # Claude's evaluation
  codex-eval.json     # Codex's evaluation (or skip marker)
  merged-eval.json    # merged evaluation result
  plan-review.json    # multi-agent critique of the selected plan
  prd.md              # destination doc: goal, approach, TDD-gated build plan
```

Generate slug from feature name: lowercase, hyphens for spaces, strip special chars, truncate to 50 chars.

**state.json:**
```json
{
  "feature": "description",
  "phase": "UNDERSTAND|RESEARCH|FORMULATE|EVALUATE|PRESENT|SELECTED|BUILD-PLAN|REVIEW-PLAN",
  "timestamp": "ISO-8601",
  "selectedApproach": null
}
```

## The Process

`UNDERSTAND → RESEARCH → FORMULATE → EVALUATE → PRESENT → SELECTED → BUILD-PLAN → REVIEW-PLAN`

The full multi-agent plan critique runs **last**, on the assembled `prd.md` — gate-level lenses (dependency ordering, vertical-slice, right-sizing, real RED tests) need the gates to exist first. A lightweight sanity pass at SELECTED guards against decomposing an obviously-doomed approach.

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
```

Write `plans/{slug}/approaches.json`:
```json
[
  {
    "index": 1,
    "name": "Approach Name",
    "howItWorks": "description",
    "evidence": { "docs": "...", "priorArt": "...", "productionCode": "...", "source": "..." /* include whichever evidence types you gathered */ },
    "tradeoffs": { "pros": ["..."], "cons": ["..."] },
    "fitReason": "..."
  }
]
```

Update `state.json` with `phase: "FORMULATE"`.

### EVALUATE

Dual-engine evaluation of the formulated approaches. Claude evaluates inline, then calls `codex` MCP tool for Codex's perspective, and merges the results.

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

Call the `codex` MCP tool per the **dual-engine standard** (see top), with `prompt`: begin with `/fast`, include the contents of `approaches.json`, and ask Codex to evaluate each approach for feasibility, risks, strengths, and implementation notes, returning the same evaluation JSON with `"engine": "codex"`. Use `@` repo-relative file references (e.g. `@package.json`, `@tsconfig.json`) resolved via `cwd`.

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

Write to `plans/{slug}/merged-eval.json`.

If Codex was unavailable, pass through Claude eval with `"enginesUsed": ["claude"]` and `"confidence": "medium"` (single-engine, lower confidence).

Update `state.json` with `phase: "EVALUATE"`.

### PRESENT

Present the candidate approaches to the user with:
1. The original evidence from RESEARCH
2. The cross-validated evaluation from EVALUATE (merged-eval.json)
3. Highlight where engines agreed (strong signal) or disagreed (flag for human decision)

State your recommendation, incorporating merge confidence. Wait for user selection before writing any code.

### SELECTED

Record the user's choice:
- Update `state.json` with `phase: "SELECTED"` and `selectedApproach: N`

**Light sanity pass before decomposing.** Run one quick Claude check on the selected approach against the codebase: is it obviously infeasible (names a module/API that doesn't exist, contradicts a hard constraint)? This is cheap insurance so BUILD-PLAN doesn't decompose a doomed approach. If it trips, loop back to FORMULATE/EVALUATE. The full multi-agent critique comes later, in REVIEW-PLAN. Otherwise proceed to BUILD-PLAN.

### BUILD-PLAN

Turn the selected approach into a destination document the implementer (or an autonomous loop) executes gate by gate. Output a single `prd.md` — a summary of the shared understanding already reached, plus an ordered set of gates. You usually won't need to re-read it.

Detect the project's quality commands once, up front: read `package.json` scripts (or the repo's Makefile/CI config) for the real lint, format, test, and build commands. Record them in `prd.md` so every gate references the same ones.

Break the work into the fewest gates that each deliver a working vertical slice — small enough to fit one context window (keep tasks small). Every gate is TDD-gated: it opens by writing failing tests and closes only when lint, format, test, and build all pass.

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
**Red (tests first):** the failing tests that define "done" for this slice.
**Green:** the minimum implementation to pass them.
**Exit criteria:** lint, format, test, build all pass.

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

Never: guess approaches without evidence; present hypothetical (non-sourced) approaches; collapse the options into a single recommendation before the user has chosen; start implementation before the user selects and the plan clears REVIEW-PLAN; skip EVALUATE or REVIEW-PLAN even when Codex is unavailable (Claude-only still adds value); start a gate's implementation before its tests are red, or close a gate with lint, format, test, or build failing.

If a resource is unavailable, note the gap and fall back (e.g. WebSearch) — still deliver evidence-backed approaches. If Codex is unavailable, proceed with Claude-only eval (`enginesUsed: ["claude"]`).
