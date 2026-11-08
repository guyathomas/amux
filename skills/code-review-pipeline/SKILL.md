---
name: code-review-pipeline
description: Reviews a diff (working tree, branch, PR, or path) in one pass covering correctness, security, structure, tests, docs, and design, then has an independent verifier attack the critical and high findings, fixes confirmed implementation issues, and routes design decisions to the user. Run after implementing a feature or before committing. Add `thorough` to verify medium findings too.
argument-hint: "[PR# | branch | path | thorough | focus notes]"
---

# Code review pipeline

One reviewer finds; an independent verifier with fresh context judges; only cited evidence drives a fix. Implementation findings are fixed when confirmed. Design findings are always the user's decision.

**Not for** config-only or docs-only diffs, one-line fixes, or `plans/*` (use `planning review {slug}`).

**Tool check.** Before starting, say whether Codex is available (`command -v codex`). The report lists every `toolsDegraded` entry from the reviewer and verifiers under **Tools degraded**, or says none were.

## Process

### TARGET
Resolve the diff: none → `git diff HEAD`; PR number → `gh pr diff N` (note the head branch and whether it is checked out); branch → `git diff {branch}...HEAD`; path → `git diff HEAD -- {path}`. `thorough` widens VERIFY; any other words are a focus note. No code changed: say so and stop. Find a matching `plans/*/plan.json` if one exists (the build skill passes it). Over roughly 800 changed lines, split into file groups that each fit one context and review them in parallel.

### REVIEW
Dispatch `amux:review` in mode `change`, one per file group, in one request, with the diff, the full file list, the repo root, the plan directory and focus note, and whether to run design (yes when the change adds a module, abstraction, boundary, data shape, dependency, or layering change, or a plan exists; no when the build skill says the plan was reviewed with no deviations). Pool results, dedupe by file, line ±3, and meaning, keeping the highest severity.

### VERIFY
Select critical and high findings (plus medium with `thorough`); the rest pass as PLAUSIBLE. Group by file (a design finding joins the file that best represents the decision) and dispatch one `amux:verify` per group in one request, with the findings and their `kind`, the repo root, the hunks, `designSummary` and `steelman` for design findings, and the head-branch note for PRs. Drop REFUTED findings from action but keep them for the report. A verifier failure leaves findings PLAUSIBLE with a warning.

### ACT
- **CONFIRMED critical and high implementation findings:** fix them. Never fix a PLAUSIBLE finding; report it prominently.
- **Design findings:** a decision for the user at every verdict — issue, cost, alternative, the verifier's defense. A CONFIRMED critical design finding is a merge blocker to raise, not a fix to apply.
- **Everything else:** report, most severe first.

### REPORT
Write the summary to `reviews/{branch}.md` (overwrite on re-review) and present: target and counts; Fixed; Needs attention (PLAUSIBLE critical/high); Design (your decision), led by `designSummary` and plan alignment; Refuted, with the refuting evidence; Suggestions (about 20 rows, rest in the file); Missing tests and stale docs; Tools degraded. Nothing survived: "Review complete, no verified issues", still showing the design summary and refuted list.

Malformed reviewer JSON: retry once, then report what parsed.
