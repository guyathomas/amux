---
name: build
description: Executes a plan (plans/{slug}/prd.md) gate by gate under TDD. Each gate opens with failing tests at its declared mix and closes only when lint, format, test, and build pass. Progress persists in plan.json so the loop survives context resets; the skill replans when the plan meets reality and loses, and finishes with the code-review pipeline.
---

<objective>
Turn a reviewed plan into working code without losing the plan's discipline: one gate at a time, tests first, quality commands green before moving on, review at the end. The plan is the contract; this skill reports deviations instead of absorbing them and stops to replan rather than forcing a plan the code has refuted.
</objective>

<when_to_use>
When a plan exists and the user asks to build, implement, or execute it. Not when no plan exists (run the planning skill) or the change never needed one.
</when_to_use>

<state>
Progress lives under `build` in `plans/{slug}/plan.json`:

```json
"build": {
  "phase": "VERIFY|BUILDING|REPLAN|REVIEW|DONE",
  "currentGate": 2,
  "qualityCommands": { "lint": "...", "format": "...", "test": "...", "build": "..." },
  "preBuildChecks": [{ "claim": "users table has deleted_at", "result": "verified|false|unverifiable", "evidence": "src/db/schema.ts:88" }],
  "gates": [{ "index": 1, "name": "...", "status": "pending|red|green|closed|blocked", "redEvidence": "...", "exitEvidence": "...", "deviations": [{ "what": "...", "why": "...", "changesScope": false }], "attempts": 1 }],
  "learned": []
}
```

`plans/{slug}/task-loop.json` (`active`, `complete`, `continuationPrompt`, `statusMessage`, `completionMessage`) keeps the session on the job: the task-loop hook blocks ending while `complete` is false. Set `complete: true` at DONE or REPLAN, so the loop always terminates. Write `plan.json` after every gate transition. On resume, trust the working tree over the recorded status: check the gate's tests exist and pass before believing it is closed.
</state>

<workflow>

<phase name="LOAD">
1. Resolve the plan directory (argument, else the most recent `plans/*/plan.json` with `review.buildReady: true`).
2. Read `prd.md` (goal, approach, quality commands, gates) and `plan.json` (`review`, `spikes`, `evaluation.preMortem`).
3. If `review` is missing, `buildReady` is false, or `pendingConfirm` is non-empty, say exactly what is unresolved and ask whether to proceed anyway. Building an unreviewed plan is the user's call, not a silent default.
4. Use the quality commands from `prd.md`; if absent, detect them as the build-plan agent does and record them.
5. Initialize `build` (`phase: "VERIFY"`, every gate `pending`) and `task-loop.json`. Announce: "Building {feature}: {N} gates."
</phase>

<phase name="VERIFY">
Settle what the reviewers could not: `review.guessedAssumptions` with a `verifyBefore` gate and any `inconclusive` spike. Read, Grep, run the command, or hit the API. Record each as `verified`, `false`, or `unverifiable` with evidence. A false load-bearing assumption means REPLAN; an unverifiable one becomes a note on its gate, whose RED tests must cover it explicitly. Then `phase: "BUILDING"`, `currentGate: 1`.
</phase>

<phase name="GATE">
Repeat per gate in order; never open a gate while the previous one is not `closed`.

**RED.** Write the failing tests the gate declares at every level in its test mix, and nothing for later gates. Run them and confirm each fails for the right reason: an assertion on the missing behavior, not an import error or missing fixture. Ask whether a stub returning a constant would pass them; if so, sharpen them. Record `redEvidence`; status `red`.

**GREEN.** Implement only what turns these tests green, following the approach in `prd.md`. When the code forces a different route, take it and record a `deviation` with the reason and whether it changes scope. A deviation that changes scope or the approach is not yours to make: REPLAN. Status `green`.

**EXIT.** Run lint, format, the full test suite, and build. A failure from this gate's code is fixed inside the gate; one that needs another gate's scope, or shows the approach does not work, marks the gate `blocked`: REPLAN. Record `exitEvidence`; status `closed`. Count attempts; a third attempt on one gate is blocked, not stubborn.

**Record.** Write `plan.json`, append what the gate taught to `learned`, update `task-loop.json` with the next gate, and say one line: "Gate {N} closed: {name}." Commit per gate only if the user asked (`feat({slug}): gate {N}: {name}`).
</phase>

<phase name="REPLAN">
Triggers: a pre-build check came back false; a gate is blocked; a gate's RED cannot be written because the slice makes no sense against the code; a deviation would change scope or approach; a surviving pre-mortem failure mode materialized. Stop. Record `phase: "REPLAN"`, the blocking gate, and what was learned; set the task loop complete with a message saying why. Hand off to the planning skill at FORMULATE/EVALUATE with `learned` as its input. Closed gates stay closed.
</phase>

<phase name="REVIEW">
After the last gate: run the quality commands once more on the whole tree, then invoke the **`code-review-pipeline` skill** on the branch diff with the plan directory. Tell it to skip the design section when the plan passed review and no gate recorded a deviation; otherwise it reviews design and checks the deviations against the plan. Re-run the quality commands if the review changed code. Present gates closed, deviations with reasons, pre-build checks, and the review summary with its persisted path. Set `phase: "DONE"` and complete the task loop.
</phase>

</workflow>

<never>
Open a gate before the previous one is closed; write implementation before its tests are red; weaken, skip, or delete a test to close a gate; build ahead of the current gate; absorb a scope-changing deviation silently; loop on a blocked gate instead of replanning; mark a gate closed with a quality command red or unrun; skip the final review because the gates passed (the gates test what the plan anticipated, the review tests what it did not).
</never>
