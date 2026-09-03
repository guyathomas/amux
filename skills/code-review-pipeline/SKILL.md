---
name: code-review
description: Creates an agent team of parallel dual-engine reviewers on a diff (working tree, branch, PR, or path) that review both the implementation and the design of the change, adversarially verifies every finding with an independent dual-engine verifier, fixes confirmed critical/high implementation issues, and routes design decisions to the user. Run after implementing a feature or before committing.
---

<objective>
Orchestrate parallel review of both the *implementation* and the *design* of a change using an agent team of specialist reviewers, then adversarially verify what they find. Implementation reviewers (code, tests, docs) ask whether the code is correct; the design reviewer asks whether the change should have been shaped this way at all. Each reviewer performs its own Claude analysis and calls `codex` for cross-validation. Resolve the review target to a diff, spawn reviewers as teammates based on what the change needs, pool and dedupe their findings, then spawn an independent verifier per critical/high/medium finding: implementation findings get a verifier that tries to refute them against the actual code; design findings get a verifier that defends the design as implemented and tests the finding's premises. Only verified implementation findings drive fixes; design findings are never auto-fixed — they go to the user.
</objective>

<quick_start>
1. Run `/code-review-pipeline` after making code changes (optionally with a PR number, branch, or path target)
2. Reviewers dispatch automatically based on file types, diff size, and whether the change makes a structural choice (new module, abstraction, data shape, or dependency → design reviewer)
3. Each reviewer cross-validates findings with Codex via `codex` MCP tool
4. Every pooled critical/high/medium finding is adversarially verified by an independent teammate — `core:verify-finding` refutes implementation findings against the code; `core:verify-design-finding` defends the design and checks each design finding's premises. REFUTED findings are dropped
5. CONFIRMED critical/high implementation findings are fixed inline; surviving design findings are presented as decisions for the user; everything else reported
</quick_start>

<when_to_use>
Use when:
- You've implemented a feature and want to catch issues before committing
- Before finalizing a branch or PR
- After a significant refactor
- User asks for a code review

Don't use when:
- Only config/docs changed (no code to review)
- Single-line trivial fix
- The diff only touches plan documents (`plans/*`) — that's a written plan, not code; use the `plan-review` skill
</when_to_use>

<workflow>

<phase name="TARGET">
1. Resolve the review target from the argument (default: current working tree):
   - **No argument** — `git diff HEAD` (staged + unstaged) and `git diff --name-only HEAD`
   - **PR number** (`123` or `#123`) — `gh pr diff {N}` and `gh pr diff {N} --name-only`. If the reviewers need to read surrounding code, note the PR's head branch (`gh pr view {N} --json headRefName`) and whether it's checked out locally.
   - **Branch** — `git diff {branch}...HEAD` and `git diff --name-only {branch}...HEAD` (changes on HEAD since diverging from the branch)
   - **Path** — `git diff HEAD -- {path}` scoped to that path
   Anything that isn't a PR number, branch, or path is a focus note — pass it through to reviewers as emphasis, with the default diff.
2. Determine the repository root: run `git rev-parse --show-toplevel` to get the absolute path. This is required context for all teammates.
3. If no code files changed, report "No code changes to review" and stop
4. **Size the pipeline to the diff.** Count changed lines (`git diff --shortstat` on the resolved target). Under ~50 changed lines, the full team rarely earns its cost: dispatch a single `core:review-implementation` teammate (one generalist pass, no lens fan-out) and still run VERIFY on its findings. Above that, run the full pipeline below. This is judgment guidance, not a hard rule — a 30-line auth change deserves the full team; a 200-line generated snapshot doesn't. Diff size says nothing about design, though: a 40-line diff that adds a new module or dependency still gets the `design` reviewer (step 5).
5. Decide which reviewers fit this diff. Use judgment about what the change actually needs — the table below is a suggested mapping, not a rule. Skip reviewers that don't apply and add ones the change warrants.

| File pattern / change shape | Reviewers worth considering |
|---|---|
| `.svelte, .tsx, .jsx, .vue, .html, .css` | code, test |
| `.ts, .js, .py, .rs, .go` | code, test, docs |
| Changed public API, config, env vars, CLI flags | docs |
| New module or file, new abstraction or public API, new data shape / schema / persisted format, new dependency, changed layering — or any change with a `plans/{slug}/` directory behind it | design |

The `code` reviewer covers correctness (bugs, logic, security, error handling), structure (coupling, cohesion, API surface), framework best-practices, and accessibility (a11y) for UI changes. Dispatch it for any non-trivial code change.

The `design` reviewer covers the *choice* of shape rather than its execution: problem–solution fit, abstraction level, architectural fit, data and state ownership, extension vs. YAGNI, simpler designs, reversibility, and plan alignment. Dispatch it whenever the change makes a structural decision — something a future reader will have to live with — rather than editing within shapes that already exist. A rename, a bug fix inside one function, or a generated file rarely needs it; a new module, a new boundary, a new dependency, or a schema change always does.

6. **Locate the plan, if any.** If `plans/*/state.json` exists, find the plan whose feature matches this change (branch name, commit messages, or ask). Its directory goes to the `design` reviewer for plan-alignment review. No plan is fine — the design reviewer reconstructs the design from the code.
7. Deduplicate into the set of reviewers to dispatch
</phase>

<phase name="DISPATCH">
Create an agent team to run specialist reviewers in parallel. Each reviewer runs as an independent teammate with its own context window. Each reviewer independently calls `codex` for Codex cross-validation.

**Category → teammate role:**

| Category | Teammate role |
|---|---|
| code | `core:review-implementation` |
| design | `core:review-design` |
| test | `core:review-tests` |
| docs | `core:review-docs` |

**Lens fan-out for the `code` reviewer.** A single generalist pass dilutes attention across too many concerns. For a full-pipeline diff, spawn `core:review-implementation` as up to 3 teammates, each with ONE lens injected into its prompt:

| Lens | Focus |
|---|---|
| error-handling / edge-cases | missing error paths, boundary conditions, null/undefined, off-by-one |
| security / data-flow | injection, authz, secrets, unvalidated input tracing from entry to sink |
| concurrency / state / structure | races, stale state, coupling, API surface — plus a11y when UI files changed |

Spawn only the lenses the diff warrants (a pure-backend diff doesn't need a11y attention; a config-only diff may need just one lens). `design`, `test`, and `docs` reviewers are dispatched once each.

**The `design` reviewer is not a fourth lens of the code reviewer.** The code lenses find defects in how the code is written; the design reviewer questions whether it should have been written that way. It gets the whole diff plus the plan directory (if any), and is told to reconstruct and steelman the design before critiquing it — its findings carry `premise[]` (the checkable facts each rests on) so VERIFY can test them.

Spawn the reviewers you selected in TARGET.

**Announce:** `"Dispatching reviewers: {list}. Each reviewer will cross-validate with Codex via codex MCP tool."`

Spawn all applicable reviewers as teammates in a single request; their agent definitions pin the model.

For EACH teammate, provide:
1. The reviewer role name (from the dispatch map)
2. The full git diff
3. The list of files relevant to that reviewer
4. The **repository root path** (from `git rev-parse --show-toplevel`)
5. For the `design` reviewer: the plan directory from TARGET step 6, if one exists, and any focus note from the argument
6. Instructions to return JSON in the standard output format

**Instructions for each teammate.** Build the prompt from the diff context plus the two shared blocks below (`<collab_standard>` and `<tools_menu>`) — the agent definitions reference these rather than restating them, so they must be injected here:

```
You are a {reviewer-role} teammate. Review the following code changes. Return your findings as JSON per your agent definition's output schema.

## Lens (code reviewers only — omit for design/test/docs)
Your single focus this pass: {lens}. Report findings outside your lens only when severity is critical.

## Plan directory (design reviewer only — omit if no plan exists)
plans/{slug}/ — read prd.md, approaches.json, and state.json for plan-alignment review.

## Repository root
{repo_root}

## Changed files
{file_list}

## Diff
{diff_content}

{collab_standard}

{tools_menu}
```
</phase>

<collab_standard>
## Dual-engine collaboration standard

After your Claude review, get a second opinion from Codex and merge.

1. Call the `codex` MCP tool with `model: gpt-5-codex`, `sandbox: read-only`, `cwd: {repo_root}`. Prompt: include the diff + file list, ask for findings as JSON (fields `severity`, `confidence`, `file`, `line`, `issue`, `recommendation`, `category`) using `@` repo-relative file refs (e.g. `@src/auth.ts`) resolved via `cwd`. The design reviewer additionally asks Codex to defend the design as implemented and to propose a materially simpler one.
2. Treat Codex as **unavailable** if the call throws/times out, or the response is empty, non-JSON, or contains MCP error text (e.g. `"Codex CLI Not Found"`). If unavailable, return Claude-only findings with `crossValidated: false` and `"engines": ["claude"]`.
3. If Codex returned valid JSON, merge by `file` + `line` (±3) + semantic similarity:
   - **AGREE** — both found it → `crossValidated: true`, confidence = max(claude, codex). Agreement is a display signal, not a score bump — two engines can share a blind spot, and verification is the gate.
   - **CHALLENGE** — same location, differing severity → keep higher, set `severityDispute: true`
   - **COMPLEMENT** — one engine only → include with `crossValidated: false`
</collab_standard>

<tools_menu>
## Suggested research (reach for whatever tools you have; the skill prescribes none)

Verify findings however your environment lets you. Kinds of evidence worth chasing:
- Current library/framework API docs and deprecations.
- Source-level patterns and conventions from the actual code.
- Real-world implementations and current best-practice articles.
- Analogous code in production repos.

Pick the tools installed in your environment that fit; none are mandatory.
</tools_menu>

<phase name="AGGREGATE">
1. Collect JSON responses from all reviewer teammates
2. Parse each response (if malformed, skip with warning)
3. **Dedupe across reviewers:** pool all findings and merge duplicates by `file` + `line` (±3) + semantic similarity (lens fan-out means several reviewers may hit the same spot). Keep the highest severity; union the `engines` lists. Design findings (`category: design`) may carry `line: null` — dedupe those by `file` + `lens` + semantic similarity. When a code reviewer's structure finding and a design finding describe the same decision, keep the design finding (it carries the premises VERIFY needs) and union the engines.
4. **Split by kind:** implementation findings (from the code, test, and docs reviewers) and design findings (`category: design`, always `applyMode: confirm`). They take different verifiers in VERIFY and different actions in ACT. Keep the design reviewer's `designSummary`, `steelman`, and `planAlignment` for the report.
5. **Pre-filter:** discard findings with `confidence < 50` — obvious noise not worth a verifier spawn. Everything else goes to VERIFY; self-reported confidence is NOT the quality gate, verification is.
6. **Group by severity** from teammate outputs:
   - **Critical** — Must fix before proceeding
   - **High** — Should fix now
   - **Medium** — Suggestions worth considering
   - **Low** — Minor improvements
7. **Surface disagreements** (`classification: CHALLENGE` / `severityDispute: true`) separately — cross-model gain concentrates where the engines diverge, so these are the highest-value items to look at, not noise to reconcile away.
8. **Compile missing tests** list from all teammates
9. **Compile stale docs** from docs reviewer findings — list doc files with staleness issues
</phase>

<phase name="VERIFY">
The reviewer that produced a finding also graded its own confidence — a number generated by the same pass that made any error. Verification separates finding from judging: an independent teammate with fresh context tries to refute each claim against the actual code.

1. Take every deduped critical/high/medium finding from AGGREGATE. **Low findings skip verification** — pass them through tagged `verdict: PLAUSIBLE` (not worth a spawn).
2. Spawn one verifier per finding, all in a single request (they run in parallel). The verifier depends on the finding's kind:

   **Implementation findings → `core:verify-finding`.** The claim is about the code, and the code is ground truth: the verifier tries to refute it. Give each:
   - The finding as JSON (`severity`, `file`, `line`, `issue`, `recommendation`, `category`)
   - The repository root
   - The diff hunk that triggered the finding
   - For PR/branch targets: the target note from TARGET (head branch and whether it's checked out) — a verifier refuting against the wrong working tree produces false refutations

   **Design findings → `core:verify-design-finding`.** The claim is a judgment, so "refute against the code" doesn't apply directly — but every design finding rests on checkable premises and is beaten by a constraint the reviewer missed. The verifier acts as the design's defense: it tests each `premise`, hunts the plan/tests/docs/adjacent code for the constraint that justifies the design as implemented, tries the proposed alternative on paper, and asks Codex to defend the design. Give each:
   - The finding as JSON (`severity`, `file`, `line`, `issue`, `cost`, `recommendation`, `premise[]`, `lens`)
   - The repository root, the full diff, and the plan directory if one exists
   - The design reviewer's `designSummary` and `steelman`
   - The same target note for PR/branch targets

3. Verdicts per the agent definitions: `CONFIRMED` (implementation: failure scenario reproduced with cited evidence; design: premises verified, no cited constraint defends the design, and the predicted cost is concrete), `REFUTED` (either engine refuted with cited evidence — for design findings, a false load-bearing premise, a cited constraint, or an alternative that fails here), `PLAUSIBLE` (neither — for design findings this is the "reasonable engineers could differ" verdict and is common).
4. **Drop REFUTED findings** — list them in the report's refuted section with the refuting evidence, but they drive no fixes and don't count in severity totals. A refuted design finding is listed with the verifier's `defense`, so the user sees why the design held.
5. Tag survivors with their verdict. If a verifier fails or times out, keep the finding as `PLAUSIBLE` with a warning — never silently promote to CONFIRMED.
</phase>

<phase name="ACT">
Based on verified findings:

### CONFIRMED critical/high implementation findings — fix
For each implementation finding with `verdict: CONFIRMED` and severity critical/high:
1. Read the file at the specified line
2. Apply the recommendation to fix the issue
3. Report what was fixed

**Never auto-fix a PLAUSIBLE finding**, regardless of severity — report it prominently for the user instead. A fix applied on an unverified claim is how reviews break working code.

### Design findings — decide, never auto-fix
A design finding changes what the code *is*, not whether it works — so it is the user's call at every verdict, including CONFIRMED critical. Present every surviving design finding (CONFIRMED and PLAUSIBLE) as a decision: the issue, the concrete cost, the alternative, the verifier's `defense` of the current design, and the verdict. Lead with the design reviewer's `designSummary` so the user sees the design being judged, and with any unjustified plan deviations. If the user accepts a design change, that's new work — implement it, then re-run this pipeline on the result rather than treating the old review as current. A critical CONFIRMED design finding is a merge blocker to raise, not a fix to apply.

### Everything else — report
Rank most-severe first (verdict breaks ties: CONFIRMED above PLAUSIBLE). Cap the table at ~20 findings; state the overflow count and point to the persisted file for the rest.

```
## Review Summary

**Target:** working tree (or PR #N / branch)
**Reviewers dispatched:** code ×3 lenses, design, test (dual-engine) · **Verifiers:** 6 (5 implementation, 1 design)
**Files reviewed:** 5
**Findings:** 4 verified (1 critical, 2 high, 1 medium) · 1 design decision · 1 refuted · 1 low unverified

### Fixed (CONFIRMED critical/high)
- [critical] src/auth.ts:42 — SQL injection via string interpolation -> switched to parameterized query (evidence: raw string reaches db.query, src/db.ts:17)
- [high] src/api.ts:15 — Uncaught promise rejection -> added try/catch

### Needs attention (PLAUSIBLE critical/high — not auto-fixed)
- [high] src/cache.ts:30 — possible race on concurrent writes; verifier could neither refute nor reproduce — inspect before merging

### Design (your decision — never auto-fixed)
**As implemented:** adds a bespoke retry queue (src/sync/queue.ts) wrapping every outbound call in src/sync/*; callers enqueue closures and a timer drains them.
**Plan alignment:** plans/offline-sync — deviates from selected approach 2 (existing job runner); deviation not justified.
- [high · CONFIRMED] src/sync/queue.ts — second retry mechanism alongside the job runner. Cost: two retry policies to keep consistent; sync failures invisible to runner metrics. Alternative: enqueue on the job runner with a sync-specific policy. Defense tested: "runner can't express per-call backoff" — refuted, src/jobs/runner.ts:52 takes a policy per job. → keep or switch?

### Refuted (dropped — no action taken)
- src/utils.ts:23 — "missing null check" — refuted by claude: input validated by zod schema at src/routes/api.ts:12
- [design] src/api/v2/ — "new API version is premature" — refuted by codex: plans/offline-sync/prd.md gate 4 requires wire-format compatibility with v1 clients; a versioned path is the stated constraint

### Disagreements (one engine challenged the other — highest-value to inspect)
- src/cache.ts:30 — Claude: high (race on concurrent writes); Codex: low — verify before dismissing

### Suggestions (Medium/Low)
| Severity | Verdict | Agent | File | Line | Issue | Recommendation | Engines |
|---|---|---|---|---|---|---|---|
| medium | CONFIRMED | code | src/utils.ts | 25 | Missing boundary check | Validate input range | codex |
| low | PLAUSIBLE | code | src/config.ts | 8 | Magic number | Extract to named constant | claude, codex |

### Stale Documentation
- [high] README.md:42 — `AUTH_SECRET` env var renamed to `JWT_SECRET`

### Missing Tests
- Test error path when fetchUser throws in src/auth.ts:42
```

If nothing survives verification: report "Review complete — no verified issues found" (still show the design summary and list any refuted findings so the work is visible).

### Persist the summary
Write the same summary (fixed, needs-attention, design decisions with the design summary and plan alignment, refuted, suggestions with verdicts, disagreements, stale docs, missing tests — uncapped) to `reviews/{branch}.md`, where `{branch}` is `git rev-parse --abbrev-ref HEAD`. Re-reviewing the same branch overwrites it. This keeps deferred medium/low findings and open design decisions from evaporating when the chat scrolls, and gives the standalone `review-code` agent a record to read alongside `plans/{slug}/`.
</phase>

</workflow>

<error_handling>
| Error | Action |
|---|---|
| Teammate returns malformed JSON | Log warning, continue with other teammates |
| Teammate times out | Log warning, continue with other teammates |
| No git diff available | Report "No changes to review" and stop |
| PR/branch target doesn't resolve (`gh` fails, unknown branch) | Report the resolution error; offer the default working-tree diff |
| All teammates fail | Report error, suggest running individual reviewer manually |
| Verifier fails or times out | Keep the finding as `PLAUSIBLE` with a warning — never silently promote or drop |
| Design reviewer fails or returns no `designSummary` | Report implementation findings normally; note that the design was not reviewed rather than implying it passed |
| Plan directory can't be matched to the change | Run the design reviewer without a plan (it reconstructs the design from the code); note that plan alignment was not checked |
| `codex` unavailable, empty, or error text | Teammate returns Claude-only findings (`"engines": ["claude"]`); verifiers verify Claude-only; pipeline continues |
</error_handling>
