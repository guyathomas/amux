---
name: retro
description: End-of-session retrospective. Reads what happened in this session and proposes specific changes to CLAUDE.md files, project skills, or amux itself, each backed by a quoted moment from the session. Nothing is applied without the user's approval. Use when the user asks for a retro or what to improve about the workflow.
argument-hint: "[focus | transcript path]"
---

# Retro

Turn friction from this session into one-line changes that stop it recurring. A few sharp proposals beat a long list; if nothing would have changed the outcome, say so.

## Sources

This conversation, or the transcript path given (`~/.claude/projects/{project}/{session}.jsonl`). Also what the session left behind: plans it created or changed, under `$(git rev-parse --path-format=absolute --git-path amux)/` while they exist and in the PR description once shipped (deviations, spikes, returns to planning), challenge findings that were declined or disputed, and PR review threads. Read the current `~/.claude/CLAUDE.md`, the project `CLAUDE.md`, and any project skills first, so you never propose what is already there.

## What to look for

- The user corrected, redirected, or repeated an instruction.
- A tool was missing, failed, or was the wrong choice.
- A finding was refuted, a plan was reworked, or a step was redone.
- Something was found by hand that a rule, command, or check could have provided.
- A step added nothing.

## Proposals

Each one has:

- **Evidence:** the quoted message or output. A proposal without a quote is an opinion; drop it.
- **Target:** the narrowest place that fixes it. `~/.claude/CLAUDE.md` for a personal preference, the project `CLAUDE.md` for a repo convention, a project skill for a repeated procedure, amux for a defect in an amux skill.
- **Change:** the exact text to add, edit, or remove, as a diff.
- **Would have prevented:** one sentence.

Do not propose rules for one-off events, restate what the model already does unprompted, or add a rule where deleting a stale one fixes it.

Present them most valuable first; the user accepts, edits, or rejects each. Apply only the accepted ones. Never edit amux's installed files, which are overwritten on update: record an accepted amux change as an upstream suggestion.

Write no report file: the applied edits are the record. Your final message lists the proposals, their evidence, the decisions, what was applied where, and any upstream suggestion in full so the user can file it. End with: "{N} applied, {M} rejected, {K} suggested upstream."
