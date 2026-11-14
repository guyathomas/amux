---
name: plan
description: Use before a change with more than one valid approach, an architectural decision, or an unfamiliar library. Researches approaches against real sources, states what would rule each one out before picking a favourite, runs a pre-mortem with an independent judge, spikes open feasibility questions, and writes a checklist that maps each acceptance criterion to its proof once the user chooses.
argument-hint: "[feature | slug]"
---

# Plan

The user chooses an approach with the case against it in view. No implementation before that choice.

**Not for** one-line fixes, obvious bugs, or explicit instructions.

## State

The plan is working state, not a repo artifact. It lives at `$(git rev-parse --git-path amux)/{slug}/prd.md`: inside the git directory, so it is never tracked, needs no ignore rule, and survives a context reset. Resolve that once and use the absolute path. It is the only state. Create it at the start and update it after every step below. Given an existing slug, or a path to a `prd.md` (older plans sit in `plans/{slug}/`), read it and continue from the first unfinished section.

The lasting record is the pull request description, which `amux:ship` writes from the plan before deleting it. Do not commit the plan unless the user asks.

Sections, in order: **Ask**, **Acceptance criteria**, **Non-goals**, **Approaches**, **Recommendation**, **Pre-mortem**, **Spikes**, **Decision**, **Checklist**, **Review**, **Open decisions**. Review holds the status of the last challenge (not run, in progress, agreed, or stopped without agreement) and its unsettled findings; Open decisions holds everything waiting on the user.

## Evidence

Current docs beat training data for anything version-specific, and primary sources beat articles. When the docs are vague or disagree with what you observe, read the library's source (a shallow clone outside the repo). Read prior art in code, not in READMEs. Cite a URL for library claims and `file:line` for repo claims. Use whatever docs, search, and code tools the environment has, fall back to the built-ins, and say which you wanted and could not use.

## Steps

1. **Understand.** Record the ask as the user stated it; the plan is measured against it later. Write numbered acceptance criteria (AC1, AC2, …), each an observable behaviour a test can check, and the non-goals. A non-goal or constraint you inferred from the repo, not from the user, is marked inferred and confirmed with them before anything depends on it.
2. **Research** the libraries in play, analogous implementations, and the conventions of the code you will touch.
3. **Approaches.** Genuinely distinct ones, never a simple-versus-complex pair. Each has how it works, evidence, tradeoffs, and **kill criteria**: the evidence that would rule it out, written before you recommend anything.
4. **Recommend** one against the actual repo, and say why.
5. **Pre-mortem.** Run `amux:challenge` on `prd.md`. A surviving failure mode becomes a risk the checklist must cover. A met kill criterion changes the recommendation; never argue around it.
6. **Spike** only a question a small experiment settles and docs would not. Before running anything, write the question, **falsified if** (the result that rules the approach out), and a time box; blowing the box is a result. Code lives in a scratch directory outside the repo and is never merged; the question, falsifier, and result are recorded in `prd.md`. Ask first if it needs credentials, external services, or real data. When the answer decides the approach and Codex is installed, give Codex the same written brief independently (`codex exec -s workspace-write -C` its own scratch directory, without your code); if the two runs disagree, the result is inconclusive, not whichever you preferred. An inconclusive spike stays a risk.
7. **Present** the approaches, the recommendation with its surviving failure modes, and the spike results. A recommendation without the case against it is a sales pitch. Wait for the user's choice. If they choose against the recommendation, re-read that approach's kill criteria first.
8. **Checklist.** Once chosen, write the build as vertical slices, each a checkbox naming the acceptance criteria and risks it closes and the proof that closes it: the test that will fail first, or the command and expected output. A UI criterion gets a committed browser test with an accessibility scan unless the user opts out. Every criterion and every surviving risk appears in some item. Include the repo's real lint, test, and build commands.
9. **Review.** Run `amux:challenge` on the finished plan, recording its status and findings in `prd.md` as they change. Offer `/amux:ship {slug}` only once it ended in agreement and Open decisions is empty.

When a build returns here because the code refuted the plan, record what it learned and restart at step 3. Do not force the original plan through.
