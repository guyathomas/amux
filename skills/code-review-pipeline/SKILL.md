---
name: review
description: Creates an agent team of parallel dual-engine code reviewers on your git diff, aggregates findings by severity, and fixes critical/high issues. Each reviewer cross-validates with Codex via MCP. Run after implementing a feature or before committing.
---

<objective>
Orchestrate parallel code review using an agent team of specialist reviewers. Each reviewer performs its own Claude analysis and calls `codex` for cross-validation. Read the git diff, determine which reviewers to spawn as teammates based on file types, run them concurrently, aggregate findings, filter low-confidence noise, and act on results.
</objective>

<quick_start>
1. Run `/code-review-pipeline` after making code changes
2. Reviewers dispatch automatically based on file types
3. Each reviewer cross-validates findings with Codex via `codex` MCP tool
4. Critical/high findings are fixed inline; medium/low reported as suggestions
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
</when_to_use>

<workflow>

<phase name="DIFF">
1. Run `git diff HEAD` to get the full diff (staged + unstaged)
2. Run `git diff --name-only HEAD` to get the list of changed files
3. Determine the repository root: run `git rev-parse --show-toplevel` to get the absolute path. This is required context for all teammates.
4. If no code files changed, report "No code changes to review" and stop
5. Decide which reviewers fit this diff. Use judgment about what the change actually needs — the table below is a suggested mapping, not a rule. Skip reviewers that don't apply and add ones the change warrants.

| File pattern | Reviewers worth considering |
|---|---|
| `.svelte, .tsx, .jsx, .vue, .html, .css` | code, test |
| `.ts, .js, .py, .rs, .go` | code, test, docs |
| Changed public API, config, env vars, CLI flags | docs |

The `code` reviewer is the generalist — it covers correctness (bugs, logic, security, error handling), structure (coupling, cohesion, API surface), framework best-practices, and accessibility (a11y) for UI changes in one pass. Dispatch it for any non-trivial code change.

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

Spawn the reviewers you selected in DIFF.

**Announce:** `"Dispatching reviewers: {list}. Each reviewer will cross-validate with Codex via codex MCP tool."`

Spawn all applicable reviewers as teammates in a single request. Use Opus for each teammate.

For EACH teammate, provide:
1. The reviewer role name (from the dispatch map)
2. The full git diff
3. The list of files relevant to that reviewer
4. The **repository root path** (from `git rev-parse --show-toplevel`)
5. Instructions to return JSON in the standard output format

**Instructions for each teammate.** Build the prompt from the diff context plus the two shared blocks below (`<collab_standard>` and `<tools_menu>`) — the agent definitions reference these rather than restating them, so they must be injected here:

```
You are a {reviewer-role} teammate. Review the following code changes. Return your findings as JSON per your agent definition's output schema.

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

1. Call the `codex` MCP tool with `model: gpt-5-codex`, `sandbox: read-only`, `cwd: {repo_root}`. Prompt: begin with `/fast`, include the diff + file list, ask for findings as JSON (fields `severity`, `confidence`, `file`, `line`, `issue`, `recommendation`, `category`) using `@` repo-relative file refs (e.g. `@src/auth.ts`) resolved via `cwd`.
2. Treat Codex as **unavailable** if the call throws/times out, or the response is empty, non-JSON, or contains MCP error text (e.g. `"Codex CLI Not Found"`). If unavailable, return Claude-only findings with `crossValidated: false` and `"engines": ["claude"]`.
3. If Codex returned valid JSON, merge by `file` + `line` (±3) + semantic similarity:
   - **AGREE** — both found it → `crossValidated: true`, confidence = max(claude, codex) + 10 (cap 100)
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
3. **Filter:** Remove findings with `confidence < 80`
4. **Group by severity** from teammate outputs:
   - **Critical** — Must fix before proceeding
   - **High** — Should fix now
   - **Medium** — Suggestions worth considering
   - **Low** — Minor improvements
5. **Highlight cross-validated findings** (`crossValidated: true`) — confirmed by both engines, but treat agreement as *moderate* confidence: two models can share blind spots, so don't auto-trust AGREE as ground truth.
6. **Surface disagreements** (`classification: CHALLENGE` / `severityDispute: true`) separately — cross-model gain concentrates where the engines diverge, so these are the highest-value items to look at, not noise to reconcile away.
7. **Compile missing tests** list from all teammates
8. **Compile stale docs** from docs reviewer findings — list doc files with staleness issues
</phase>

<phase name="ACT">
Based on aggregated findings:

### Critical and High findings
For each critical/high finding:
1. Read the file at the specified line
2. Apply the recommendation to fix the issue
3. Report what was fixed

### Medium and Low findings
Report as suggestions in a summary table:

```
## Review Summary

**Reviewers dispatched:** code, test (Opus, dual-engine)
**Files reviewed:** 5
**Findings:** 2 critical, 1 high, 3 medium, 1 low
**Cross-validated:** 2 findings confirmed by both Claude and Codex

### Cross-Validated (both engines agree — moderate-confidence, not ground truth)
- [critical] src/auth.ts:42 — SQL injection via string interpolation (AGREE)
- [high] src/api.ts:15 — Uncaught promise rejection (AGREE)

### Disagreements (one engine challenged the other — highest-value to inspect)
- src/cache.ts:30 — Claude: high (race on concurrent writes); Codex: low — verify before dismissing
- src/parse.ts:8 — Codex-only: off-by-one on empty input (Claude missed it)

### Fixed (Critical/High)
- [critical] src/auth.ts:42 — SQL injection via string interpolation -> switched to parameterized query
- [high] src/api.ts:15 — Uncaught promise rejection -> added try/catch

### Suggestions (Medium/Low)
| Severity | Agent | File | Line | Issue | Recommendation | Engines |
|---|---|---|---|---|---|---|
| medium | code | src/utils.ts | 23 | Potential null dereference | Add null check | claude |
| medium | code | src/utils.ts | 25 | Missing boundary check | Validate input range | codex |
| low | code | src/config.ts | 8 | Magic number | Extract to named constant | claude, codex |

### Stale Documentation
- [high] README.md:42 — `AUTH_SECRET` env var renamed to `JWT_SECRET`
- [medium] docs/api.md:15 — Missing `/auth/refresh` endpoint from API reference

### Missing Tests
- Test error path when fetchUser throws in src/auth.ts:42
- Test empty array input in src/utils.ts:23
```

If no findings above confidence threshold: report "Review complete — no issues found."

### Persist the summary
Write the same summary (fixed, suggestions, disagreements, stale docs, missing tests) to `reviews/{branch}.md`, where `{branch}` is `git rev-parse --abbrev-ref HEAD`. Re-reviewing the same branch overwrites it. This keeps deferred medium/low findings from evaporating when the chat scrolls, and gives the standalone `review-code` agent a record to read alongside `plans/{slug}/`.
</phase>

</workflow>

<error_handling>
| Error | Action |
|---|---|
| Teammate returns malformed JSON | Log warning, continue with other teammates |
| Teammate times out | Log warning, continue with other teammates |
| No git diff available | Report "No changes to review" and stop |
| All teammates fail | Report error, suggest running individual reviewer manually |
| `codex` unavailable, empty, or error text | Teammate returns Claude-only findings (`"engines": ["claude"]`), pipeline continues |
</error_handling>
