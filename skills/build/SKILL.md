---
name: build
description: Executes a plan (plans/{slug}/prd.md) gate by gate under TDD. Each gate opens with failing tests and closes only when lint, format, test, and build pass. Progress persists in plan.json so a context reset can resume; the skill replans when the plan meets reality and loses, and finishes with the code-review pipeline.
argument-hint: "[slug]"
---

# Build

The plan is the contract: one gate at a time, tests first, quality commands green before moving on, review at the end. Report deviations instead of absorbing them; stop and replan rather than force a plan the code has refuted.

**Use when** a plan exists and the user asks to build it. Otherwise run the planning skill.

## State

Under `build` in `plans/{slug}/plan.json`:

```json
"build": { "phase": "VERIFY|BUILDING|REPLAN|REVIEW|DONE", "currentGate": 2,
  "qualityCommands": { "lint": "...", "format": "...", "test": "...", "build": "..." },
  "preBuildChecks": [{ "claim": "...", "result": "verified|false|unverifiable", "evidence": "file:line" }],
  "gates": [{ "index": 1, "name": "...", "status": "pending|red|green|closed|blocked", "redEvidence": "...", "exitEvidence": "...", "deviations": [], "attempts": 1 }],
  "learned": [], "toolsDegraded": [] }
```

Write it after every gate transition. On resume, trust the working tree over the record: a gate is closed only if its tests exist and pass. Keep going gate after gate until DONE or REPLAN; do not stop to ask between gates.

**Tool check.** Before starting, say whether every quality command and test runner the gates need (including the browser E2E runner for UI gates) is installed, and whether Codex is available. A missing one goes in `build.toolsDegraded` and is reported; never skip a level of the test mix because its runner is missing — install it as the gate's first step or REPLAN.

## Process

### LOAD
Resolve the plan (argument, else the most recent `plans/*/plan.json` with `review.buildReady: true`). Read `prd.md` and `plan.json`. If `review` is missing, `buildReady` is false, or `pendingConfirm` is non-empty, say what is unresolved and ask whether to proceed. Use the quality commands from `prd.md`, detecting them if absent. Announce: "Building {feature}: {N} gates."

### VERIFY
Settle `review.guessedAssumptions` and any inconclusive spike: read, Grep, run the command. Record each as verified, false, or unverifiable with evidence. A false load-bearing assumption means REPLAN; an unverifiable one becomes a note its gate's RED tests must cover.

### GATE
Per gate, in order; never open one before the previous is closed.

- **RED.** Write the failing tests the gate declares, nothing for later gates. Confirm each fails for the right reason (an assertion, not an import error). If a constant-returning stub would pass them, sharpen them. Record `redEvidence`.
- **GREEN.** Implement only what turns them green. When the code forces a different route, take it and record a deviation; one that changes scope or approach is REPLAN.
- **EXIT.** Run lint, format, the full test suite (including click tests and axe-core scans for UI gates), and build. Fix this gate's failures inside the gate; a failure needing another gate's scope, or a third attempt, is `blocked`: REPLAN. Record `exitEvidence`, with the click-test trace or screenshot path for UI gates.
- **Record.** Write `plan.json`, append to `learned`, say "Gate {N} closed: {name}." Commit per gate only if the user asked.

### REPLAN
Triggers: a false pre-build check, a blocked gate, a RED that makes no sense against the code, a scope-changing deviation, a materialized pre-mortem failure mode. Stop, record why, and hand off to the planning skill at FORMULATE with `learned`. Closed gates stay closed.

### REVIEW
Run the quality commands on the whole tree, then invoke the **code-review-pipeline** skill on the branch diff with the plan directory. Tell it to skip design when the plan passed review and no gate recorded a deviation. Re-run the commands if the review changed code. Present gates closed, deviations, pre-build checks, Tools degraded, and the review summary. Set `phase: "DONE"`.

## Never

Write implementation before its tests are red; weaken, skip, or delete a test to close a gate; build ahead of the current gate; absorb a scope-changing deviation; loop on a blocked gate; close a gate with a quality command red or unrun; skip the final review because the gates passed.
