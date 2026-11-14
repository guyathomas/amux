---
name: ship
description: Takes a change from its current state to a merged pull request - finishes it, proves it, has it challenged, files the PR, watches CI and review, and merges once the merge gate passes. Use when the user asks to ship, finish, land, or merge a change, or to build a plan. Pass `no-merge` to stop when the PR is ready.
argument-hint: "[slug] [no-merge]"
---

# Ship

You own the work from where it stands to a merged PR. The user may not be watching, so decide what you can, prove what you change, and stop only for the reasons under "Asking".

## What this permits

Creating a branch, committing, pushing the PR's branch, force-pushing that branch with `--force-with-lease` after a rebase, and merging once the merge gate passes (not with `no-merge`).

It does not permit `--admin` or any other bypass of branch protection, touching production, deleting data, changing anything outside the repo, pushing to other branches, or closing a PR. The user's and the project's own instructions still apply and override this skill, including rules that say to ask first.

## Steps

1. **Finish the change** with the smallest change that works. On the default branch, create a branch first. Leave unrelated changes in the working tree alone.
   With a plan (a slug, resolved as `amux:plan` describes, or a path to its `prd.md`): if its Review section does not say agreed, or Open decisions is not empty, ask before building. Take one checklist item at a time, prove it, tick it in `prd.md`, and note any deviation beside it. On resume, trust the working tree over the ticks. Go back to `amux:plan` with what you learned when the code refutes the plan: a false assumption, a met kill criterion, a deviation that changes scope or approach, or a third failed attempt at the same item.
2. **Prove it.** See "Proof".
3. **Challenge it.** Run `amux:challenge` on the diff.
4. **File the PR.** Check whether one exists for the branch. Rebase onto the latest default branch. Follow the repo's title and description conventions; lead with the problem, not an inventory of changes, and add one line on how the change was proved. With a plan, the description is its lasting record: the ask, the approach chosen, the alternatives rejected and what ruled each out, and the risks that survived. Check the text for secrets. Open a real PR, not a draft, so checks and review bots run. If a PR cannot be filed (no remote, `gh` not authenticated), stop here and put the title and description you would have filed in your report.
5. **Watch it.** Do not end your turn while checks or reviews are pending; nothing will wake you. Wait with the Monitor tool or a background `gh pr checks {n} --watch`, never a hand-written sleep loop. Fix real CI failures and review findings, with proof for each fix before you push. On each wake, look for comments newer than your last push; a thread stays open until it is fixed or dismissed, whatever its age. Dismiss a wrong finding with a written reason. A reviewer's design finding is the user's decision, as in `amux:challenge`.
6. **Merge** when the merge gate passes, using the method the repo's recent merged PRs use. With a merge queue or auto-merge, stay until GitHub reports the PR merged. With `no-merge`, stop here and report it ready. Once the PR is merged, delete the plan's directory, naming it by its literal absolute path; until then it stays.
7. **Report:** the PR link, the merge commit, the proof, the challenge outcome, and every decision you made on the user's behalf.

## Proof

Proof is evidence you observed in this session, the most direct the change allows:

- Reproduce the failure, apply the fix, and watch the same reproduction pass.
- A test written first and seen to fail on an assertion, not an import error. If a constant-returning stub would pass it, sharpen it. A test that already passes before the change proves nothing until you break the code it guards and watch it fail. Never weaken, skip, or delete a test to get to green.
- The checks the repo's CI runs: lint, types, tests, build.
- For UI and runtime behaviour, run the app and look. Mocked tests passing do not prove the experience works. When the plan calls for a committed browser test, session proof does not replace it.

## Merge gate

All true on the latest commit:

- Proof covers every change in the diff.
- Required checks are green. CI that could not run is not green.
- The challenge ended in agreement, and no design decision from it or from a reviewer is waiting on the user.
- Every review finding is fixed or dismissed with a reason, and no human review requests changes.
- After a fresh fetch, the branch is up to date with the default branch and GitHub reports it mergeable.

## Asking

A question in an ordinary message goes unseen. Use the question tool, with the PR link, what blocks you, and the options, your recommendation first. Ask only when:

- you cannot prove the change;
- the merge gate cannot pass and you cannot fix why;
- the next step is outside what this skill permits;
- the goal is ambiguous in a way that changes the result;
- the challenge or a reviewer raised a design decision.

Decide everything else yourself and list it in the report. With no question tool, or no answer, take the safe path: leave the PR open and unmerged, and open your final message with the question.
