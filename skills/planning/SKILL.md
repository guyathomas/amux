---
name: planning
description: Use before implementing any non-trivial feature - validates approaches against real sources using Context7, Serper, GitHub MCPs, and optionally btca for source-level codebase research. Evaluates with dual engines before committing to an implementation
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

## Suggested research tools

Reach for the tools that fit what you need to learn — which and how many is your call. RESEARCH runs these in parallel as subagents.

- **Context7** (`resolve-library-id`, `query-docs`) — current library/framework API docs, version gotchas, deprecations
- **Serper / WebSearch** — real-world implementations, best-practice articles, comparisons
- **GitHub** (`search-code`, `search-repositories`) — how production codebases structure this; common pitfalls
- **btca** (`listResources`, `ask`) — source-level patterns in indexed codebases; ask about conventions/structure, not API signatures (optional; only when resources are flagged in UNDERSTAND)
- **Codex** (`gpt-5-codex`) — second-engine evaluation in EVALUATE

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

#### btca Resource Check (optional)

If the btca MCP tools are available (`listResources`, `ask`):

1. Call `listResources` to see what codebase resources are indexed
2. Match resources against the project's tech stack (check `package.json`, import statements, config files)
3. If matching resources exist, flag them in `state.json` as `"btcaResources": ["resource-name"]` for the RESEARCH phase

**When btca adds value** (flag for RESEARCH):
- Feature involves framework conventions, patterns, or architecture (routing, auth, SSR, data loading)
- Project uses less-documented or rapidly evolving libraries
- Project depends on internal/private codebases with no public docs
- The question is "how should we structure X?" — not "what API does Y have?"

**Skip btca when:**
- The question is about API usage — Context7 already provides clear docs
- Libraries are mature and well-documented (React, Express, lodash, zod)
- No framework-level architectural decisions are involved

**If btca is available but no matching resources exist** and the feature involves framework patterns:
- Identify the canonical repo URL for relevant dependencies (run `npm view {pkg} repository.url` for npm packages)
- Suggest specific commands: `btca add -n {name} {repo-url}`
  - For monorepos, include `--searchPath`: `btca add -n sveltekit https://github.com/sveltejs/kit --searchPath packages/kit`
- Offer to run the commands if the user approves

**If btca MCP is not configured** but the btca CLI is detected (noted in session-start):
- Suggest one-time setup: `claude mcp add --transport stdio btca-local -- bunx btca mcp`

### RESEARCH

Gather evidence from the **Suggested research tools** (see top) that fit the problem — you decide which and how many. Run them in parallel using subagents, and add others (reading the codebase directly) as warranted. Ground approaches in real evidence, not guesses. Planning-specific usage of each:

#### Context7: Current Library Docs
```
1. resolve-library-id for each relevant library
2. query-docs for the specific feature/API needed
3. Note: version-specific gotchas, recommended patterns, deprecations
```

#### Serper Search: Real-World Implementations
```
1. Search for "[feature] [framework] implementation"
2. Search for "[feature] best practices [year]"
3. Look for: blog posts with code, official guides, comparison articles
```

#### GitHub: Analogous Codebases
```
1. search-code for the pattern/API in real projects
2. search-repositories for projects solving the same problem
3. Look for: how production codebases structure this, common pitfalls
```

#### btca: Source-Level Patterns (optional)

Only run this subagent if `state.json` has `btcaResources` flagged from the UNDERSTAND phase.

```
1. Call btca ask with the matched resources
2. Ask about patterns, conventions, and structure — not API signatures
   e.g. "How does SvelteKit handle server-side authentication?"
   NOT "What parameters does the redirect function accept?"
3. Note: answers are grounded in actual source code, not documentation
```

If btca `ask` fails or returns no useful results, continue without it.

Update `state.json` with `phase: "RESEARCH"`.

### FORMULATE

Formulate a set of genuinely distinct approaches — enough to give the user a real choice, as many as the problem warrants. Avoid a false "simple vs. complex" binary; surface meaningfully different options.

For each approach, provide:

```
### Approach N: [Name]

**How it works:** [2-3 sentences]

**Evidence:**
- Context7: [what the docs say about this approach]
- Serper: [what real-world articles recommend]
- GitHub: [how production codebases do it]
- btca: [what the source code reveals about patterns/structure] (if available)

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
    "evidence": { "context7": "...", "serper": "...", "github": "...", "btca": "..." /* omit if btca not used */ },
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
