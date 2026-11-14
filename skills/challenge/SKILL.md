---
name: challenge
description: Has an independent judge with fresh context argue against a diff or a plan, then answers each finding with evidence in a budgeted loop. Codex is the judge when installed; otherwise a fresh subagent. Use when the user asks for a review, a second opinion, or a pre-mortem, and before shipping.
argument-hint: "[PR# | branch | path | plan slug | focus notes]"
---

# Challenge

Whoever wrote the work does not judge it. A judge that has seen none of your reasoning argues against the work; you check every finding yourself and answer with evidence. Agreement is reached, not assumed.

## Scope

- **Diff:** no argument means base to working tree, including untracked files that belong to the change (not build output or caches). A PR number, branch, or path narrows it. Use the same diff command every round.
- **Plan:** a slug, which resolves to `$(git rev-parse --path-format=absolute --git-path amux)/{slug}/prd.md`, or a path to a `prd.md`. Give the judge the absolute path.

Do not stash, discard, or include unrelated changes. State the intent and what is out of scope in one or two sentences. For a diff, run the repo's checks first and do not send code they fail on.

## The judge

Always fresh context. The judge gets the brief below and nothing else: never this conversation, your reasoning, or your opinion of the work.

- **Codex**, when `command -v codex` succeeds. Write the filled-in brief to a scratch file outside the repo, then through Bash with a 600000 ms timeout:

  ```
  out=$(mktemp)
  codex exec --skip-git-repo-check -s read-only -C {repo_root} -o "$out" - < {brief_file}
  ```

  Read the answer from the `-o` file. A non-zero exit, a timeout, or an empty answer means Codex is unavailable for this run.
- **Otherwise a fresh subagent**, started with the same brief as its whole prompt. Say in the report that the judge was Claude-only and why.

Brief:

```
Review only. Do not edit, commit, push, or start other reviewers.
Repo: {abs path}  Base: {sha}  Intent: {intent}  Out of scope: {scope}  Checks: {results; none for a plan}
See: {diff command} and git status --short (read untracked files) | {plan path}
Read the surrounding code. Argue against this work with file:line evidence.
Diff: bugs, broken callers, mismatch with intent, tests a constant-returning stub would pass.
  Flag code the intent does not need. Skip style unless it hides a bug.
Plan: assume the recommended approach was built and failed. Write the likely post-mortems
  and test each against the plan's evidence, its kill criteria, and the repo. Name any
  acceptance criterion with no proof and any guessed assumption a step depends on.
  "No surviving failure modes" is a valid answer; do not invent one.
Mark each finding implementation or design.
blocker = the intended case is wrong. should = a real bug in normal use. nit = the rest.
Reply:
VERDICT: APPROVE or CHANGES
F1 [blocker|should|nit] [implementation|design] file:line claim. Fix: suggestion
```

Do not edit the files under review while the judge runs. A timeout, an error, or no reply is not approval.

## Answering

A finding is a lead until you have checked it against the code or the source. Settle the severity and the implementation-or-design label yourself: another path, a rare case, or a small cost is a nit, and a mechanical fix is not a design decision, whatever label it arrived with.

- **Agree, implementation:** the smallest fix, with one focused test that fails without it.
- **Disagree:** say why, citing `file:line`, a test, or output.
- **Nit or out of scope:** decline in one line and list it as a follow-up.
- **Design** (structure, abstraction, scope, approach): never fixed on your own authority. Before it goes to the user, make the strongest case for the work as it stands. Then give them the finding, its cost, the alternative, and that defense. In a plan, apply only mechanical tightening; anything that changes scope or approach is the user's decision.

Do not agree to end the loop, and do not let the loop grow the change. If the diff grew, cut before the next round.

## Budget

Three rounds. Round one is full. A later round's brief is the same header, the ledger (each id as fixed, disagreed, or declined, with evidence), and what changed since; it asks the judge to mark each old id resolved or still open and to cover only open ids and changed code. The judge may reopen anything you declined or downgraded; your label does not close it. Stop early when a round returns only nits and reopens nothing. An item still disputed after two exchanges goes to the user with both sides in a few lines each. The budget running out is not approval.

## Report

The judge used; rounds; fixed, declined, and disputed findings with reasons; design decisions waiting on the user; diff size before and after.
