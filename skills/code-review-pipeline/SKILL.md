---
name: code-review
description: Creates an agent team of parallel dual-engine code reviewers on a diff (working tree, branch, PR, or path), adversarially verifies every finding with an independent dual-engine verifier, and fixes confirmed critical/high issues. Run after implementing a feature or before committing.
---

<objective>
Orchestrate parallel code review using an agent team of specialist reviewers, then adversarially verify what they find. Each reviewer performs its own Claude analysis and calls `codex` for cross-validation. Resolve the review target to a diff, spawn reviewers as teammates based on file types and diff size, pool and dedupe their findings, then spawn an independent verifier per critical/high/medium finding that tries to refute it against the actual code. Only verified findings drive fixes.
</objective>

<quick_start>
1. Run `/code-review-pipeline` after making code changes (optionally with a PR number, branch, or path target)
2. Reviewers dispatch automatically based on file types and diff size
3. Each reviewer cross-validates findings with Codex via `codex` MCP tool
4. Every pooled critical/high/medium finding is adversarially verified by an independent `core:verify-finding` teammate — REFUTED findings are dropped
5. CONFIRMED critical/high findings are fixed inline; everything else reported
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
4. **Size the pipeline to the diff.** Count changed lines (`git diff --shortstat` on the resolved target). Under ~50 changed lines, the full team rarely earns its cost: dispatch a single `core:review-implementation` teammate (one generalist pass, no lens fan-out) and still run VERIFY on its findings. Above that, run the full pipeline below. This is judgment guidance, not a hard rule — a 30-line auth change deserves the full team; a 200-line generated snapshot doesn't.
5. Decide which reviewers fit this diff. Use judgment about what the change actually needs — the table below is a suggested mapping, not a rule. Skip reviewers that don't apply and add ones the change warrants.

| File pattern | Reviewers worth considering |
|---|---|
| `.svelte, .tsx, .jsx, .vue, .html, .css` | code, test |
| `.ts, .js, .py, .rs, .go` | code, test, docs |
| Changed public API, config, env vars, CLI flags | docs |

The `code` reviewer covers correctness (bugs, logic, security, error handling), structure (coupling, cohesion, API surface), framework best-practices, and accessibility (a11y) for UI changes. Dispatch it for any non-trivial code change.

6. Deduplicate into the set of reviewers to dispatch
</phase>

<phase name="DISPATCH">
Create an agent team to run specialist reviewers in parallel. Each reviewer runs as an independent teammate with its own context window. Each reviewer independently calls `codex` for Codex cross-validation.

**Category → teammate role:**

| Category | Teammate role |
|---|---|
| code | `core:review-implementation` |
| test | `core:review-tests` |
| docs | `core:review-docs` |

**Lens fan-out for the `code` reviewer.** A single generalist pass dilutes attention across too many concerns. For a full-pipeline diff, spawn `core:review-implementation` as up to 3 teammates, each with ONE lens injected into its prompt:

| Lens | Focus |
|---|---|
| error-handling / edge-cases | missing error paths, boundary conditions, null/undefined, off-by-one |
| security / data-flow | injection, authz, secrets, unvalidated input tracing from entry to sink |
| concurrency / state / structure | races, stale state, coupling, API surface — plus a11y when UI files changed |

Spawn only the lenses the diff warrants (a pure-backend diff doesn't need a11y attention; a config-only diff may need just one lens). `test` and `docs` reviewers are dispatched once each, as before.

Spawn the reviewers you selected in TARGET.

**Announce:** `"Dispatching reviewers: {list}. Each reviewer will cross-validate with Codex via codex MCP tool."`

Spawn all applicable reviewers as teammates in a single request; their agent definitions pin the model.

For EACH teammate, provide:
1. The reviewer role name (from the dispatch map)
2. The full git diff
3. The list of files relevant to that reviewer
4. The **repository root path** (from `git rev-parse --show-toplevel`)
5. Instructions to return JSON in the standard output format

**Instructions for each teammate.** Build the prompt from the diff context plus the two shared blocks below (`<collab_standard>` and `<tools_menu>`) — the agent definitions reference these rather than restating them, so they must be injected here:

```
You are a {reviewer-role} teammate. Review the following code changes. Return your findings as JSON per your agent definition's output schema.

## Lens (code reviewers only — omit for test/docs)
Your single focus this pass: {lens}. Report findings outside your lens only when severity is critical.

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

1. Call the `codex` MCP tool with `model: gpt-5-codex`, `sandbox: read-only`, `cwd: {repo_root}`. Prompt: include the diff + file list, ask for findings as JSON (fields `severity`, `confidence`, `file`, `line`, `issue`, `recommendation`, `category`) using `@` repo-relative file refs (e.g. `@src/auth.ts`) resolved via `cwd`.
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
3. **Dedupe across reviewers:** pool all findings and merge duplicates by `file` + `line` (±3) + semantic similarity (lens fan-out means several reviewers may hit the same spot). Keep the highest severity; union the `engines` lists.
4. **Pre-filter:** discard findings with `confidence < 50` — obvious noise not worth a verifier spawn. Everything else goes to VERIFY; self-reported confidence is NOT the quality gate, verification is.
5. **Group by severity** from teammate outputs:
   - **Critical** — Must fix before proceeding
   - **High** — Should fix now
   - **Medium** — Suggestions worth considering
   - **Low** — Minor improvements
6. **Surface disagreements** (`classification: CHALLENGE` / `severityDispute: true`) separately — cross-model gain concentrates where the engines diverge, so these are the highest-value items to look at, not noise to reconcile away.
7. **Compile missing tests** list from all teammates
8. **Compile stale docs** from docs reviewer findings — list doc files with staleness issues
</phase>

<phase name="VERIFY">
The reviewer that produced a finding also graded its own confidence — a number generated by the same pass that made any error. Verification separates finding from judging: an independent teammate with fresh context tries to refute each claim against the actual code.

1. Take every deduped critical/high/medium finding from AGGREGATE. **Low findings skip verification** — pass them through tagged `verdict: PLAUSIBLE` (not worth a spawn).
2. Spawn one `core:verify-finding` teammate per finding, all in a single request (they run in parallel). Give each:
   - The finding as JSON (`severity`, `file`, `line`, `issue`, `recommendation`, `category`)
   - The repository root
   - The diff hunk that triggered the finding
   - For PR/branch targets: the target note from TARGET (head branch and whether it's checked out) — a verifier refuting against the wrong working tree produces false refutations
3. Each verifier reads the real code, traces callers/guards, attempts to refute, and independently asks Codex to refute — verdicts per its agent definition: `CONFIRMED` (failure scenario reproduced with cited evidence), `REFUTED` (either engine refuted with cited evidence), `PLAUSIBLE` (neither).
4. **Drop REFUTED findings** — list them in the report's refuted section with the refuting evidence, but they drive no fixes and don't count in severity totals.
5. Tag survivors with their verdict. If a verifier fails or times out, keep the finding as `PLAUSIBLE` with a warning — never silently promote to CONFIRMED.
</phase>

<phase name="ACT">
Based on verified findings:

### CONFIRMED critical/high findings — fix
For each finding with `verdict: CONFIRMED` and severity critical/high:
1. Read the file at the specified line
2. Apply the recommendation to fix the issue
3. Report what was fixed

**Never auto-fix a PLAUSIBLE finding**, regardless of severity — report it prominently for the user instead. A fix applied on an unverified claim is how reviews break working code.

### Everything else — report
Rank most-severe first (verdict breaks ties: CONFIRMED above PLAUSIBLE). Cap the table at ~20 findings; state the overflow count and point to the persisted file for the rest.

```
## Review Summary

**Target:** working tree (or PR #N / branch)
**Reviewers dispatched:** code ×3 lenses, test (dual-engine) · **Verifiers:** 5
**Files reviewed:** 5
**Findings:** 4 verified (1 critical, 2 high, 1 medium) · 1 refuted · 1 low unverified

### Fixed (CONFIRMED critical/high)
- [critical] src/auth.ts:42 — SQL injection via string interpolation -> switched to parameterized query (evidence: raw string reaches db.query, src/db.ts:17)
- [high] src/api.ts:15 — Uncaught promise rejection -> added try/catch

### Needs attention (PLAUSIBLE critical/high — not auto-fixed)
- [high] src/cache.ts:30 — possible race on concurrent writes; verifier could neither refute nor reproduce — inspect before merging

### Refuted (dropped — no action taken)
- src/utils.ts:23 — "missing null check" — refuted by claude: input validated by zod schema at src/routes/api.ts:12

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

If nothing survives verification: report "Review complete — no verified issues found" (and list any refuted findings so the work is visible).

### Persist the summary
Write the same summary (fixed, needs-attention, refuted, suggestions with verdicts, disagreements, stale docs, missing tests — uncapped) to `reviews/{branch}.md`, where `{branch}` is `git rev-parse --abbrev-ref HEAD`. Re-reviewing the same branch overwrites it. This keeps deferred medium/low findings from evaporating when the chat scrolls, and gives the standalone `review-code` agent a record to read alongside `plans/{slug}/`.
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
| `codex` unavailable, empty, or error text | Teammate returns Claude-only findings (`"engines": ["claude"]`); verifiers verify Claude-only; pipeline continues |
</error_handling>
