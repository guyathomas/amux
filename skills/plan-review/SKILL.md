---
name: plan-review
description: Reviews a written plan (plans/{slug}/prd.md) in one pass covering assumptions, completeness, gate structure, and scope; fact-checks the critical and high findings with an independent verifier; applies verified mechanical fixes; and gates scope or approach changes for the user. Runs at planning's REVIEW-PLAN phase or standalone.
---

<objective>
Stress-test a plan before any code is written. One reviewer finds; a verifier with fresh context fact-checks; only confirmed mechanical fixes touch the plan, and anything that changes intent waits for the user.
</objective>

<when_to_use>
When `plans/{slug}/prd.md` exists and should be hardened before building, when the planning skill reaches REVIEW-PLAN, or when asked to critique a plan. Not for reviewing code (use `code-review-pipeline`) or before a plan exists.
</when_to_use>

<workflow>

<phase name="LOCATE">
1. Resolve the plan directory: the given slug or path, else the most recently updated `plans/*/plan.json`, else ask.
2. Read `prd.md` and `plan.json`. If `prd.md` has no gates yet, note it: the structure section will be limited to approach-level shape.
3. Repository root: `git rev-parse --show-toplevel`. Record the round (default 1).
</phase>

<phase name="REVIEW">
Dispatch one `amux:review-plan` with `prd.md`, `plan.json`, the repository root, and the plan directory path. Assign stable ids to its findings. Keep `assumptions` (the ledger) and `scopeDrift` for the report.
</phase>

<phase name="VERIFY">
1. Select critical and high findings. Empirical ones are checked directly; judgment ones are checked on their `premise` only. Medium and low pass through as `verdict: PLAUSIBLE`, and a PLAUSIBLE finding marked `auto` is demoted to `confirm`: an unverified claim never edits the plan.
2. Group the selected findings by section (gate, approach, goal). Dispatch one `amux:verify` per group, all in one request, each with its findings (`kind: plan`, ids, premises where present), the repository root, the plan directory, and the relevant `prd.md` excerpt.
3. Apply verdicts. A REFUTED empirical finding is dropped. A REFUTED premise drops its judgment finding: the user should not be asked to cut a "scope addition" the ask actually requested, or to switch to a "simpler pattern" the library does not offer. Keep refuted items for the report with the evidence. Verifier failure leaves a finding PLAUSIBLE with a warning.
</phase>

<phase name="ACT">
- **Apply** each finding with `applyMode: auto` and `verdict: CONFIRMED` to `prd.md`, recording the change and the evidence. Nothing else is applied.
- **Converge**: if any critical or high finding was applied in round 1, re-run REVIEW and VERIFY once on the edited plan. Do not loop on `confirm` findings; those wait on the user.
- **Present** every `confirm` finding as a decision (one item each). If the user accepts one that invalidates the approach, hand back to the planning skill's FORMULATE/EVALUATE.
- `buildReady` is true only when no critical or high finding remains after refuted ones are dropped.
</phase>

<phase name="PERSIST">
Write the result under `review` in `plan.json` and set `phase: "REVIEW-PLAN"`:

```json
"review": {
  "round": 2,
  "buildReady": true,
  "applied": [{ "section": "gate-3", "change": "reordered before gate-2", "evidence": "gate-3 step 2 consumes gate-4's output (prd.md)" }],
  "pendingConfirm": [{ "section": "gate-4", "issue": "adds unrequested caching layer", "recommendation": "cut or confirm" }],
  "refuted": [{ "section": "gate-2", "issue": "claimed missing rollback step", "evidence": "prd.md gate-2 step 4 specifies rollback" }],
  "guessedAssumptions": [{ "claim": "...", "consequence": "...", "verifyBefore": "gate-3" }],
  "summary": "1 reorder applied; 1 refuted; 1 scope addition pending; 1 assumption to verify before gate 3."
}
```

Present:

```
## Plan Review
**Plan:** plans/{slug}/ · Round 2 · Build-ready: yes/no
### Applied (CONFIRMED mechanical)
### Refuted (dropped)
### Needs your decision (scope / approach)
### Verify before building (guessed assumptions)
### Suggestions (medium/low, unverified)
```

If build-ready with nothing pending: "Plan review complete, plan is build-ready." Otherwise ask the user to resolve the pending decisions.
</phase>

</workflow>

<error_handling>
No plan directory: "No plan to review, run the planning skill first." Malformed reviewer JSON: retry once. Verifier fails: findings stay PLAUSIBLE, auto demoted to confirm. Codex unavailable inside the verifier: Claude-only, noted; the review continues.
</error_handling>
