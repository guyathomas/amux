---
name: plan-review
description: Creates an agent team of parallel dual-engine reviewers on a written plan (plans/{slug}/prd.md), fact-checks empirical findings with an independent dual-engine verifier, auto-applies verified mechanical fixes, and gates scope/approach changes for the user. Run after BUILD-PLAN or standalone on any plan directory. The plan-equivalent of the code-review pipeline.
---

<objective>
Orchestrate parallel review of a *written plan* — not code — using an agent team of specialist plan reviewers, then verify what they find before it touches the plan. Each reviewer performs its own Claude analysis and calls `codex` for cross-validation. Read the plan directory, dispatch the four plan reviewers concurrently, dedupe and pool findings, fact-check the empirical ones against the actual repo and current docs, auto-apply only verified mechanical fixes, gate scope/approach judgments for the user, and converge.
</objective>

<quick_start>
1. Run after `BUILD-PLAN` produces `plans/{slug}/prd.md`, or standalone via `/plan-review {slug}`
2. Four reviewers dispatch in parallel — assumptions, completeness, structure, scope
3. Each cross-validates findings with Codex via the `codex` MCP tool
4. Empirical findings are fact-checked by independent `core:verify-plan-finding` teammates; judgment findings have their *premise* fact-checked and always route to the user for the judgment itself
5. Only CONFIRMED mechanical fixes are applied to the plan; scope/approach changes are surfaced for the user
6. Re-review converges until no critical/high findings remain (max 2 rounds)
</quick_start>

<when_to_use>
Use when:
- A plan has been written (`plans/{slug}/prd.md` exists) and you want it stress-tested before implementation
- The planning skill reaches its `REVIEW-PLAN` phase (it delegates here)
- The user asks to review, critique, or harden a plan

Don't use when:
- No plan artifact exists yet — run the planning skill first
- The change is a single-line fix with no plan
- Reviewing implemented code (a git diff) — that's the `code-review` skill (code-review-pipeline)
</when_to_use>

<workflow>

<phase name="LOCATE">
1. Resolve the plan directory:
   - If a slug/path is given, use `plans/{slug}/`.
   - Else read `plans/*/state.json` and pick the most recently updated, or ask the user which plan.
2. Read the plan artifacts: `prd.md` (the gates), `approaches.json`, `state.json`, and `merged-eval.json` if present. These are the review target — the equivalent of the git diff.
3. Determine the repository root: `git rev-parse --show-toplevel`. Required context for all teammates.
4. If `prd.md` has no gates yet (review invoked before BUILD-PLAN), note it — the structure reviewer will review only approach-level shape, and gate-level lenses are limited.
5. Record which round this is (default round 1).
</phase>

<phase name="DISPATCH">
Create an agent team of four plan reviewers in parallel. Each runs as an independent teammate with its own context window and independently calls `codex` for cross-validation.

**Reviewer → teammate role:**

| Reviewer | Teammate role | Owns |
|---|---|---|
| assumptions | `core:review-plan-assumptions` | assumption audit, codebase-fit, evidence freshness |
| completeness | `core:review-plan-completeness` | gap sweep, non-functional coverage, definition-of-done per gate |
| structure | `core:review-plan-structure` | dependency ordering, vertical-slice, right-sizing, real RED tests |
| scope | `core:review-plan-scope` | scope-drift, over/under-engineering, simpler alternative |

Always dispatch all four — unlike code review, the plan reviewers aren't file-type gated; every plan benefits from all four lenses. (Skip a reviewer only if its inputs are entirely absent, e.g. skip `structure` when there are no gates.)

**Announce:** `"Dispatching plan reviewers: assumptions, completeness, structure, scope. Each cross-validates with Codex via the codex MCP tool."`

Spawn all four as teammates in a single request; their agent definitions pin the model.

For EACH teammate, provide:
1. The reviewer role name (from the table)
2. The full contents of the plan artifacts (`prd.md`, `approaches.json`, `state.json`, `merged-eval.json`)
3. The **repository root path**
4. The two shared blocks below (`<collab_standard>` and `<tools_menu>`) — the agent definitions reference these rather than restating them, so they must be injected here.

```
You are a {reviewer-role} teammate. Review the following written plan. Return your findings as JSON per your agent definition's output schema.

## Repository root
{repo_root}

## Plan directory
plans/{slug}/

## prd.md
{prd_contents}

## approaches.json
{approaches_contents}

## state.json (UNDERSTAND-phase scope, selected approach)
{state_contents}

## merged-eval.json (approaches that were compared)
{merged_eval_contents}

{collab_standard}

{tools_menu}
```
</phase>

<collab_standard>
## Dual-engine collaboration standard

After your Claude review, get a second opinion from Codex and merge.

1. Call the `codex` MCP tool with `model: gpt-5-codex`, `sandbox: read-only`, `cwd: {repo_root}`. Prompt: include the plan artifacts, ask Codex to critique the plan for your lenses, returning findings as JSON (fields `severity`, `confidence`, `section`, `lens`, `issue`, `recommendation`, `category`, `applyMode`) using `@` repo-relative file refs (e.g. `@plans/{slug}/prd.md`) resolved via `cwd`.
2. Treat Codex as **unavailable** if the call throws/times out, or the response is empty, non-JSON, or contains MCP error text (e.g. `"Codex CLI Not Found"`). If unavailable, return Claude-only findings with `crossValidated: false` and `"engines": ["claude"]`.
3. If Codex returned valid JSON, merge by `section` + semantic similarity:
   - **AGREE** — both found it → `crossValidated: true`, confidence = max(claude, codex). Agreement is a display signal, not a score bump — two engines can share a blind spot, and verification is the gate.
   - **CHALLENGE** — same section, differing severity → keep higher, set `severityDispute: true`
   - **COMPLEMENT** — one engine only → include with `crossValidated: false`
</collab_standard>

<tools_menu>
## Suggested research (reach for whatever tools you have; the skill prescribes none)

Verify claims however your environment lets you. Kinds of evidence worth chasing:
- Confirm an assumed API exists / isn't deprecated; confirm a simpler library-native approach is real.
- Source-level patterns and conventions from the actual code the plan integrates with.
- Real-world implementations that confirm a simpler alternative is an established pattern.
- Analogous plans/implementations in production repos.
- **Read / Glob / Grep** — the actual repo: do the files, modules, and patterns the plan names exist?

Pick the tools installed in your environment that fit; none are mandatory.
</tools_menu>

<phase name="AGGREGATE">
1. Collect JSON responses from all four reviewer teammates (if malformed, skip with a warning).
2. **Dedupe across reviewers:** pool all findings and merge duplicates by `section` + semantic similarity (completeness and structure especially overlap). Keep the highest severity; union the `engines` lists.
3. **Pre-filter:** discard findings with `confidence < 50` — obvious noise not worth a verifier spawn. Self-reported confidence is NOT the quality gate; verification is.
4. **Group by severity:** critical (must fix before building) / high (should fix) / medium (worth considering) / low (minor).
5. **Split by `applyMode`:**
   - **auto** — mechanical tightening: clarity, missing exit criteria, error-path steps, gate reordering, sharpening RED tests. (Right-sizing and trimming gold-plating are judgment calls — VERIFY forces those to `confirm`.)
   - **confirm** — anything that changes scope or the selected approach (scope additions/cuts, simpler-approach swaps, new phases). These never get applied silently.
6. **Surface disagreements** (`severityDispute: true` / `classification: CHALLENGE`) separately — cross-model gain concentrates where engines diverge; these are the highest-value items to inspect.
7. **Collect the assumption ledger** from the assumptions reviewer — list every `guessed` load-bearing assumption as a pre-build verification task.
8. Compute `buildReady = true` only if no critical/high findings remain across all reviewers (after VERIFY drops the refuted ones).
</phase>

<phase name="VERIFY">
Plan findings split into two kinds, and only one of them can be adversarially verified:

**1. Empirical findings — claims about reality.** Lenses `assumption-audit`, `codebase-fit`, `evidence-freshness`, and structural claims that are checkable against the plan text (dependency ordering, missing exit criteria, unreal RED tests). Either the file exists or it doesn't; either gate 3 consumes gate 4's output or it doesn't.

1. Spawn one `core:verify-plan-finding` teammate per empirical critical/high/medium finding, all in a single request (parallel). Give each: the finding as JSON, the repository root, and the relevant `prd.md` excerpt. (Low findings pass through as `verdict: PLAUSIBLE` unverified.)
2. Each verifier fact-checks against the authoritative source — the repo (`Read`/`Grep`), the plan text itself, or current docs (Context7/web) — and independently asks Codex to refute. Verdicts per its agent definition: `CONFIRMED` requires cited evidence; `REFUTED` (either engine, with evidence) is dropped; no evidence → `PLAUSIBLE`.
3. **Verdict gates applyMode:** only `CONFIRMED` findings may keep `applyMode: auto`. A `PLAUSIBLE` finding marked auto is demoted to `confirm` — an unverified claim never silently edits the plan.

**2. Judgment findings — claims about proportionality.** Lenses `scope-drift`, `over-under-engineering`, `simpler-alternative`, right-sizing calls. The judgment itself isn't a refutable fact — arguing "too much abstraction" against "about right" is opinion-vs-opinion noise, and the user is the verifier for that. But every judgment finding rests on a **premise** that *is* checkable: "the original ask never mentioned X" (checkable against `state.json`'s UNDERSTAND scope), "a simpler library-native pattern exists" (checkable against current docs), "this abstraction has one consumer" (checkable against the repo).

1. For each critical/high judgment finding, spawn a `core:verify-plan-finding` teammate with the finding's `premise` (the scope reviewer supplies one; for other judgment findings, extract the factual claim the recommendation depends on) and the instruction to verify **the premise only**. Medium/low judgment findings pass through unverified as `PLAUSIBLE`.
2. A **REFUTED premise drops the finding** — the user should not be asked to rule on cutting a "scope addition" the original ask actually requested, or on switching to a "simpler pattern" the library doesn't offer. List it in the refuted section with the evidence.
3. Everything else keeps `applyMode: confirm` regardless of verdict. Verification filters the noise out of the user's decision list; it never makes the decision. Do not spawn verifiers to argue the proportionality call itself.
</phase>

<phase name="ACT">
### Auto-apply (CONFIRMED mechanical findings)
For each finding with `applyMode: auto` AND `verdict: CONFIRMED`:
1. Read the relevant section of `prd.md` (or `approaches.json`).
2. Apply the recommendation as an edit to the plan document.
3. Record what changed, with the verifier's evidence.

Never auto-apply a `confirm` finding, and never auto-apply a `PLAUSIBLE` or unverified one — the convergence loop must re-review a plan mutated only by verified edits.

### Gate for the user (scope/approach findings)
Present every `applyMode: confirm` finding for an explicit decision. These change the user's intent — adding/cutting scope, swapping to a simpler approach. Per the planning skill's rule, never decompose or rewrite a plan's intent the user hasn't blessed. If the user accepts one that invalidates the approach, loop back to the planning skill's FORMULATE/EVALUATE.

### Converge
After auto-applying edits, if any critical/high `auto` findings were fixed this round and this is round 1, re-run DISPATCH→VERIFY on the updated plan (round 2). Stop when `buildReady` is true or after round 2. Don't loop on `confirm` findings — those wait on the user.

### Persist & present
Write the merged result to `plans/{slug}/plan-review.json`:
```json
{
  "round": 2,
  "buildReady": true,
  "enginesUsed": ["claude", "codex"],
  "applied": [{ "section": "gate-3", "change": "reordered before gate-2 (dependency)", "finding": "...", "verdict": "CONFIRMED", "evidence": "gate-3 step 2 consumes gate-4's migration output (prd.md)" }],
  "pendingConfirm": [{ "section": "gate-4", "issue": "adds unrequested caching layer", "recommendation": "cut or confirm", "verdict": "judgment" }],
  "refuted": [{ "section": "gate-2", "issue": "claimed missing rollback step", "refutedBy": "claude", "evidence": "prd.md gate-2 step 4 already specifies rollback" }],
  "guessedAssumptions": [{ "claim": "...", "consequence": "...", "verifyBefore": "gate-3" }],
  "disagreements": [{ "section": "approach", "claude": "high", "codex": "low", "issue": "..." }],
  "summary": "1 verified dependency reorder applied; 1 finding refuted; 1 scope addition pending user; 1 assumption to verify."
}
```

Present the summary:

```
## Plan Review Summary

**Reviewers:** assumptions, completeness, structure, scope (dual-engine)  ·  **Verifiers:** 3
**Plan:** plans/{slug}/  ·  Round 2  ·  Build-ready: yes/no
**Findings:** 5 (2 high, 3 medium: 2 confirmed-applied, 2 judgment-pending, 1 unverified)  ·  1 refuted  ·  Cross-validated: 2

### Applied to the plan (CONFIRMED mechanical)
- [high] gate-3 — reordered before gate-2 (depended on its output; evidence: prd.md gate-3 step 2)
- [medium] gate-2 — added measurable exit criterion

### Refuted (dropped — no action taken)
- gate-2 — "missing rollback step" — refuted: prd.md gate-2 step 4 already specifies rollback

### Needs your decision (scope / approach — not applied)
- [high] gate-4 — adds a caching layer the original ask never mentioned → cut or confirm?
- [medium] approach — a simpler library-native pattern exists (confirmed against current docs) → switch?

### Verify before building (guessed assumptions)
- users table soft-delete column — Gate 3 query assumes it; confirm it exists

### Disagreements (one engine challenged the other — inspect)
- approach — Claude: high (migration risk); Codex: low

### Suggestions (medium/low)
| Severity | Verdict | Reviewer | Section | Issue | Recommendation | Engines |
|---|---|---|---|---|---|---|
| medium | PLAUSIBLE | completeness | gate-5 | no load-test note | add perf check | claude, codex |
```

If `buildReady` and no `pendingConfirm`, report "Plan review complete — plan is build-ready." Otherwise ask the user to resolve the pending decisions and verify the flagged assumptions before implementation.
</phase>

</workflow>

<error_handling>
| Error | Action |
|---|---|
| Teammate returns malformed JSON | Log warning, continue with other teammates |
| Teammate times out | Log warning, continue with other teammates |
| No plan directory found | Report "No plan to review — run the planning skill first" and stop |
| `prd.md` missing (pre-BUILD-PLAN) | Review approach-level only; skip `structure` gate lenses; note in summary |
| All teammates fail | Report error, suggest running an individual reviewer manually |
| Verifier fails or times out | Keep the finding as `PLAUSIBLE` (demoted to `confirm` if it was auto) with a warning — never silently promote or drop |
| `codex` unavailable, empty, or error text | Teammates return Claude-only findings (`"engines": ["claude"]`); verifiers verify Claude-only; pipeline continues |
</error_handling>
