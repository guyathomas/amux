---
name: code-review
description: Reviews a diff (working tree, branch, PR, or path) in one pass covering correctness, security, structure, tests, docs, and design, then adversarially verifies the critical and high findings with an independent verifier, fixes confirmed implementation issues, and routes design decisions to the user. Run after implementing a feature or before committing.
---

<objective>
One reviewer finds; an independent verifier with fresh context judges; only cited evidence drives a fix. Implementation findings ask whether the code is correct and are fixed when confirmed. Design findings ask whether the change should have been shaped this way and are always the user's decision.
</objective>

<when_to_use>
After implementing a feature, before finalizing a branch or PR, after a refactor, or when asked for a review. Not for config-only or docs-only diffs, single-line fixes, or a diff that only touches `plans/*` (use `plan-review`).
</when_to_use>

<workflow>

<phase name="TARGET">
1. Resolve the diff. No argument: `git diff HEAD` (staged and unstaged). PR number: `gh pr diff N`, noting the head branch and whether it is checked out. Branch: `git diff {branch}...HEAD`. Path: `git diff HEAD -- {path}`. The word `thorough` widens VERIFY (below); anything else is a focus note for the reviewer.
2. Repository root: `git rev-parse --show-toplevel`.
3. If no code files changed, say "No code changes to review" and stop.
4. Locate a plan, if any: a `plans/*/plan.json` whose feature matches the branch or commit messages. Its directory goes to the reviewer for plan alignment; the `build` skill passes it explicitly and says whether design review is needed.
5. Size: `git diff --shortstat`. Up to roughly 800 changed lines is one review. Above that, split the diff into file groups that fit one context window each (by directory or concern) and review the groups in parallel with the same prompt; the reviewer's design section runs on whichever group holds the structural change, with the whole file list for context.
</phase>

<phase name="REVIEW">
Dispatch `amux:review-change` (one per file group, all in one request). Give each: the diff (or its group), the full changed-file list, the repository root, the plan directory and focus note if any, and whether to run the design section (always when the change adds a module, abstraction, boundary, data shape, dependency, or layering change, or a plan exists; skip when the `build` skill says the plan was reviewed and no deviations were recorded).

Pool the results. Dedupe by `file` + `line` (±3) + meaning, keeping the highest severity; dedupe design findings by file and meaning. Keep `designSummary`, `steelman`, `planAlignment`, `missingTests`, and `staleDocs` for the report. Assign stable ids.
</phase>

<phase name="VERIFY">
The reviewer graded its own work; verification separates finding from judging.

1. Select critical and high findings. With `thorough`, add medium. Everything else passes through as `verdict: PLAUSIBLE`, unverified.
2. Group the selected findings by file (a design finding joins the group of the file that best represents the decision). Dispatch one `amux:verify` per group, all in one request. Give each: its findings with ids and `kind`, the repository root, the diff hunks for that file, the reviewer's `designSummary` and `steelman` when the batch holds a design finding, the plan directory if any, and for PR or branch targets the head-branch note so the verifier refutes against the right tree.
3. Apply verdicts. Drop REFUTED findings from the action list but keep them for the report with the refuting evidence. A verifier that fails or times out leaves its findings PLAUSIBLE with a warning; never promote silently.
</phase>

<phase name="ACT">
- **CONFIRMED critical and high implementation findings**: read the file at the line, apply the recommendation, note what changed. Never fix a PLAUSIBLE finding, whatever its severity; report it prominently instead.
- **Design findings**: the user's call at every verdict, including CONFIRMED critical. Present each as a decision: issue, cost, alternative, the verifier's `defense`, verdict. Lead with `designSummary` and any unjustified plan deviations. An accepted design change is new work: implement it, then re-run this skill. A CONFIRMED critical design finding is a merge blocker to raise, not a fix to apply.
- **Everything else**: report, most severe first, CONFIRMED above PLAUSIBLE. Cap the table at about 20 rows and point to the persisted file for the rest.
</phase>

<phase name="REPORT">
Write the full summary to `reviews/{branch}.md` (`git rev-parse --abbrev-ref HEAD`; re-reviewing overwrites) and present it:

```
## Review Summary
**Target:** working tree · **Files:** 5 · **Findings:** 4 verified (1 critical, 2 high, 1 medium) · 1 design decision · 1 refuted · 2 unverified

### Fixed (CONFIRMED critical/high)
- [critical] src/auth.ts:42 — SQL injection via string interpolation → parameterized query (evidence: raw string reaches db.query, src/db.ts:17)

### Needs attention (PLAUSIBLE critical/high, not fixed)
- [high] src/cache.ts:30 — possible race on concurrent writes; verifier could neither refute nor reproduce

### Design (your decision)
**As implemented:** {designSummary}
**Plan alignment:** {deviations, or "no plan"}
- [high · CONFIRMED] src/sync/queue.ts — second retry mechanism beside the job runner. Cost: … Alternative: … Defense tested: … → keep or switch?

### Refuted (dropped)
- src/utils.ts:23 — "missing null check" — refuted by claude: validated by zod at src/routes/api.ts:12

### Suggestions (medium/low)
| Severity | Verdict | File | Line | Issue | Recommendation |

### Missing tests / Stale docs
```

If nothing survives: "Review complete, no verified issues" with the design summary and the refuted list still shown.
</phase>

</workflow>

<error_handling>
Malformed reviewer JSON: retry once, then report what parsed. Diff fails to resolve: report the error and offer the working tree. Verifier fails: findings stay PLAUSIBLE with a warning. Codex unavailable inside a verifier: it verifies Claude-only and says so; the pipeline continues.
</error_handling>
