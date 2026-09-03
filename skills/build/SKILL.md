---
name: build
description: Executes a build-ready plan (plans/{slug}/prd.md) gate by gate under TDD — each gate opens with failing tests at its declared mix and closes only when lint, format, test, and build pass — persists progress so the loop survives context resets, replans when the plan meets reality and loses, and finishes by running the code-review pipeline on the whole change. Use after plan-review reports the plan build-ready.
---

<objective>
Turn a build-ready plan into working code without losing the plan's discipline: one gate at a time, tests first, quality commands green before moving on, and the review pipeline at the end. The plan is the contract. This skill executes it and reports deviations instead of quietly absorbing them, and it stops to replan rather than forcing a plan the code has already refuted.
</objective>

<quick_start>
1. Run `/build {slug}` after `plan-review` reports the plan build-ready (or `/build` to pick the most recent build-ready plan)
2. Each gate runs RED (write the declared tests, confirm they fail for the right reason) → GREEN (the minimum implementation) → EXIT (lint, format, test, build all pass) → record
3. Progress lives in `plans/{slug}/build.json`; a task loop keeps the session on the job until the last gate closes or a replan is needed
4. If a gate can't be built as planned, stop and hand back to the planning skill — don't patch the plan's intent inline
5. After the last gate, run the `code-review-pipeline` skill on the whole change with the plan directory, so the design reviewer checks plan alignment
</quick_start>

<when_to_use>
Use when:
- `plans/{slug}/plan-review.json` says `buildReady: true` and `pendingConfirm` is empty
- The user asks to implement, build, or execute a plan

Don't use when:
- No plan exists — run the planning skill first
- The plan isn't build-ready — resolve `pendingConfirm` with the user or re-run `plan-review`
- The change is trivial enough that it never needed a plan
</when_to_use>

<state>
`plans/{slug}/build.json`:
```json
{
  "phase": "VERIFY|BUILDING|REPLAN|REVIEW|DONE",
  "currentGate": 2,
  "qualityCommands": { "lint": "...", "format": "...", "test": "...", "build": "..." },
  "preBuildChecks": [{ "claim": "users table has deleted_at", "result": "verified|false|unverifiable", "evidence": "src/db/schema.ts:88" }],
  "gates": [
    {
      "index": 1,
      "name": "...",
      "status": "pending|red|green|closed|blocked",
      "redEvidence": "3 new tests fail: assertion on missing export (not import error)",
      "exitEvidence": "lint ok · format ok · test 42 passed · build ok",
      "deviations": [{ "what": "used middleware instead of decorator", "why": "decorator API removed in v5 (docs)", "changesScope": false }],
      "attempts": 1
    }
  ],
  "learned": ["what the code taught that the plan didn't know"],
  "startedAt": "ISO-8601",
  "updatedAt": "ISO-8601"
}
```

`plans/{slug}/task-loop.json` uses the same contract as the research skill (`active`, `complete`, `continuationPrompt`, `statusMessage`, `completionMessage`). The task-loop hook blocks ending the session while `complete` is false. Set `complete: true` when `phase` reaches `DONE` **or** `REPLAN` — both are legitimate exits, so the loop always terminates.

**Rules:** read `build.json` before acting; write it after every gate transition. On resume, don't trust a gate's recorded status blindly — check the working tree (are its tests present? do they pass? do the quality commands pass?) and downgrade the status if the tree disagrees.
</state>

<workflow>

<phase name="LOAD">
1. Resolve the plan directory (argument, or the most recent `plans/*/plan-review.json` with `buildReady: true`).
2. Read `prd.md` (goal, selected approach, quality commands, gates), `plan-review.json` (`buildReady`, `pendingConfirm`, `guessedAssumptions`), and, if present, `spikes.json` and the `preMortem` in `merged-eval.json`.
3. **Refuse to start** if `buildReady` is false or `pendingConfirm` is non-empty — say exactly what's pending and stop. Building an unblessed plan is how scope drifts.
4. Detect the quality commands from `prd.md`; if it doesn't record them, detect them the way BUILD-PLAN does (package.json scripts, Makefile, CI config) and record them in `build.json`.
5. Initialize `build.json` (`phase: "VERIFY"`, every gate `pending`) and `task-loop.json` (`active: true`, `complete: false`, continuation prompt naming the plan and phase).
6. Announce: `"Building {feature}: {N} gates. Quality commands: lint/format/test/build detected."`
</phase>

<phase name="VERIFY">
The plan's reviewers left a ledger of what they couldn't settle: `guessedAssumptions` with a `verifyBefore` gate, and `inconclusive` spikes. Settle them now, before the gate that depends on them — a false assumption found here costs minutes; found at gate 4 it costs the gates behind it.

1. For each item: `Read`/`Grep` the repo, run the command, or hit the API — whatever settles it. Record `verified`, `false`, or `unverifiable` with evidence in `preBuildChecks`.
2. A `false` load-bearing assumption → **REPLAN**. Don't reinterpret the plan to route around it.
3. `unverifiable` → carry it as a note on the dependent gate; its RED tests must cover the assumption explicitly.
4. Set `phase: "BUILDING"`, `currentGate: 1`.
</phase>

<phase name="GATE">
Repeat for each gate in order. Never open a gate while the previous one isn't `closed`.

**RED — tests first.**
1. Write the failing tests the gate declares, at every level in its **test mix** (unit / integration / E2E as stated). Don't write tests for later gates.
2. Run the test command. Confirm each new test **fails, and fails for the right reason**: an assertion on the missing behavior — not an import error, a typo, or a fixture that doesn't exist yet. A test that passes before the implementation exists isn't testing this slice; rewrite it.
3. **Adversarial check on the tests:** could a stub that returns a constant, or the obvious wrong implementation, pass them? If so the tests are too weak to gate anything — sharpen them before going green. This is the cheapest mutation test you'll ever run.
4. Record `redEvidence` (which tests, how they fail). Status `red`.

**GREEN — the minimum implementation.**
1. Implement only what turns this gate's tests green. Don't build ahead into later gates, don't add generality the gate didn't ask for.
2. Follow the approach `prd.md` describes. When the code forces a different route (API missing, pattern doesn't fit, a spike's gotcha), take it and record a `deviation` with the reason and whether it changes scope. A deviation that changes scope or the approach itself is not yours to make → **REPLAN**.
3. Status `green` once the gate's tests pass.

**EXIT — quality green.**
1. Run lint, format, test (the full suite, not just this gate's), and build. All four must pass.
2. A failure caused by this gate's code → fix it within the gate. A failure that requires touching another gate's scope, or that reveals the approach doesn't work → status `blocked` → **REPLAN**.
3. Record `exitEvidence`. Status `closed`. Increment `attempts` on every RED→GREEN→EXIT cycle; a gate on its third attempt is blocked, not stubborn → **REPLAN**.

**Record and advance.**
1. Write `build.json`; append anything the gate taught to `learned`.
2. Commit at the close of the gate only if the user asked for per-gate commits (message: `feat({slug}): gate {N} — {name}`); otherwise leave the tree as is and note the gate boundary in `build.json`.
3. Update `task-loop.json` — `statusMessage: "Gate {N}/{total} closed"`, `continuationPrompt` naming the next gate.
4. Announce one line: `"Gate {N} closed — {name}. {tests} tests, quality green."` Then open the next gate.
</phase>

<phase name="REPLAN">
Triggers: a pre-build check came back `false`; a gate is `blocked`; a gate's RED can't be written because the slice as described doesn't make sense against the code; a deviation would change scope or approach; a surviving pre-mortem failure mode materialized.

1. Stop building. Don't rewrite gates, don't reinterpret the goal, don't push through.
2. Write `build.json` with `phase: "REPLAN"`, the blocking gate, and what was learned.
3. Set `task-loop.json` `complete: true` with a `completionMessage` stating the replan and why.
4. Hand off to the **planning skill** at FORMULATE/EVALUATE with the finding (the `learned` list is its input). Edits to a plan's intent go through `plan-review`, never through the build loop. Closed gates stay closed; the replanned plan starts from the current tree.
</phase>

<phase name="REVIEW">
After the last gate closes:

1. Run the full quality commands one final time on the whole tree.
2. Invoke the **`code-review-pipeline` skill** on the entire change (branch diff vs. its base), passing the plan directory so the design reviewer checks plan alignment and sees the recorded `deviations`. The pipeline fixes CONFIRMED critical/high implementation findings and reports design decisions.
3. If the pipeline changed code, re-run the quality commands.
4. Present: gates closed, deviations with reasons, pre-build checks, review summary (fixed / needs attention / design decisions / refuted), and where the review persisted (`reviews/{branch}.md`).
5. Set `phase: "DONE"`, `task-loop.json` `complete: true` with a completion message summarizing gates, tests, and review outcome.
</phase>

</workflow>

<error_handling>
| Error | Action |
|---|---|
| Plan not build-ready / `pendingConfirm` non-empty | Stop; list what's pending; point to `plan-review` or the user decision |
| Quality command missing or fails to run (not a lint/test failure — the tool itself) | Detect an alternative as BUILD-PLAN would; if none, record it, tell the user, and proceed with the commands that exist — never mark a gate closed on a check that didn't run |
| New tests pass before implementation | Tests don't cover the slice; rewrite before going green |
| Test fails for the wrong reason (import/fixture) | Fix the scaffolding, re-run, confirm the assertion is what fails |
| Gate blocked after 2 full attempts | `blocked` → REPLAN |
| `build.json` disagrees with the working tree on resume | Trust the tree; downgrade the gate status and redo from there |
| Context reset mid-gate | The task loop re-injects the continuation prompt; resume from `build.json` and re-verify the current gate's state |
</error_handling>

<red_flags>
Never: open a gate before the previous one is closed; write implementation before its tests are red; weaken, skip, or delete a test to close a gate; build ahead of the current gate; absorb a scope- or approach-changing deviation silently; loop on a blocked gate instead of replanning; mark a gate closed with any quality command red or unrun; skip the final review pipeline because "the gates all passed" — the gates test what the plan anticipated, the review tests what it didn't.
</red_flags>
