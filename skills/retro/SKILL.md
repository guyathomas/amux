---
name: retro
description: End-of-session retrospective. Reads what happened in this session (and any amux plan, review, or research state it produced) and proposes specific changes to CLAUDE.md files, project skills, or amux itself, each backed by a quoted moment from the session. Nothing is applied without the user's approval. Use when the user asks for a retro or what to improve about the workflow.
argument-hint: "[focus | transcript path]"
---

# Retro

Turn friction from this session into one-line changes that stop it recurring. Fewer, sharper proposals beat a long list: if nothing would have changed the outcome, say so.

## Process

### GATHER
Source: this conversation, or the transcript path given (`~/.claude/projects/{project}/{session}.jsonl`). Also read what amux runs recorded, limited to files this session created or changed (`git status`, modification time): `plans/*/plan.json` (`build.learned`, deviations, replans, blocked gates, `review.refuted`), `reviews/*.md` (refuted and PLAUSIBLE findings), `research/*/state.json`, and any `toolsDegraded`. Read the current `~/.claude/CLAUDE.md`, the project `CLAUDE.md`, and any project skills, so you never propose something that is already there.

### FIND
Look for moments where the session lost time or quality:
- The user corrected, redirected, or repeated an instruction.
- A tool was missing, failed, or was the wrong choice.
- A finding was refuted, a gate blocked, a plan replanned, or a step was redone.
- Something was discovered by hand that a rule, command, or check could have provided.
- A step added no value.

### PROPOSE
For each moment worth acting on, write one proposal:
- **Evidence:** the quoted message or output. A proposal without a quote is an opinion; drop it.
- **Target:** the narrowest place that fixes it. Use `~/.claude/CLAUDE.md` for a personal preference across projects, the project `CLAUDE.md` for a repo convention, a project skill for a repeated multi-step procedure, and amux for a defect in an amux skill or agent.
- **Change:** the exact text to add, edit, or remove, as a diff.
- **Would have prevented:** one sentence.

Do not propose rules for one-off events, restate defaults the model already follows, or add a rule where deleting a stale one fixes it.

### DECIDE
Present the proposals, most valuable first, and let the user accept, edit, or reject each one. Apply only the accepted ones. Never edit amux's installed files: they are overwritten on update. Write accepted amux changes to the report as an upstream suggestion instead.

### REPORT
Write `retros/{YYYY-MM-DD}-{slug}.md` with the proposals, their evidence, the decisions, and what was applied where. End with one line: "{N} applied, {M} rejected, {K} suggested upstream."
