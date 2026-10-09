---
name: spike
description: Runs a time-boxed, throwaway experiment that turns a feasibility question into a fact, with the result that would falsify it stated before it runs. Optionally runs the same experiment independently on Codex and Claude and treats disagreement as inconclusive. Used by the planning skill when a question survives research, or standalone via /amux:spike.
---

# Spike

Research answers "what do the docs say"; a spike answers "what actually happens here". A spike is small, isolated, and disposable: its only outputs are a result and what it taught. Announce at start: "Running a spike: {question}."

**Use for:** a feasibility question that docs, the repo, and prior art do not settle but a small experiment would (does the library support X under our version and config; does the API accept Y; is Z within budget; does the existing module tolerate being called that way). **Not for:** anything a docs lookup or Grep settles; a judgment call; an experiment that would be a meaningful fraction of the build (that is the first gate, plan it).

## Input

A question, optionally the approach it bears on and the plan directory (`plans/{slug}/`). Standalone spikes live in `spikes/{name}/` at the repository root.

## Process

### DESIGN
Write down, before anything runs:
1. **Question**: one sentence, answerable yes/no or with a number.
2. **Bears on**: the approach, kill criterion, or failure mode it tests.
3. **Falsified if**: the result that would rule the approach out. A spike with no pre-stated failure condition cannot fail, so it cannot inform anything.
4. **Time box**: a handful of files, no tests, no lint, no polish. Blowing the box is itself a result: "harder than it looked".
5. **Confounds**: what would make a pass meaningless (a mock standing in for the thing under test, a different version than production, measuring the wrong path).
6. **Engines**: Claude only, or Claude and Codex independently. Choose both when the question is one where passing for the wrong reason is likely, or when the answer decides the approach. Codex unavailable means Claude only; say so.

Optionally ask the `codex` MCP tool to attack the design: "Would this experiment settle the question? What result would pass for the wrong reason?" Fold any real hole into the confounds.

**Announce** the question, the falsification criterion, the time box, and the engines. Ask the user first if the spike needs credentials, external services, real data, or more than a small time box.

### RUN
Work in `{spike_dir}/claude/` (and `{spike_dir}/codex/` for the Codex run), a self-contained script or mini-project. If the experiment must touch the repo, use a throwaway worktree or branch. Capture evidence verbatim: command output, numbers, the error message.

**Codex run.** Call the `codex` MCP tool with `sandbox: workspace-write`, `cwd: {spike_dir}/codex/` (create it first), `model: gpt-6-astra`, and `timeout-seconds` set from the time box. Give it the identical brief: question, falsified-if, time box, confounds, and the instruction that the spike directory is the only writable location and that it must return JSON `{ "result": "confirmed|falsified|inconclusive", "evidence": "verbatim output", "assumptions": ["what it had to assume to run"] }`. Do not show it Claude's code. Afterwards run `git status` and discard anything written outside the spike directory. A timeout is recorded as "blew the time box".

### JUDGE
Single engine: the result is what the evidence shows against the falsification criterion.

Two engines: **confirmed** when both confirm with consistent evidence; **falsified** when both falsify; **inconclusive** when they disagree or either blew the box, with both evidence blocks attached. Two independent implementations rarely share the same wrong reason, so disagreement is the signal the dual run exists to produce; never resolve it by picking the answer you preferred.

### RECORD
Append to `spikes` in `plan.json` (or write `{spike_dir}/result.json` standalone):

```json
{
  "name": "streaming-upload-size",
  "question": "Does the storage SDK stream a 2 GB upload without buffering under Node 22?",
  "approachIndex": 1,
  "bearsOn": "kill criterion: memory > 512 MB on large uploads",
  "falsifiedIf": "RSS exceeds 512 MB during a 2 GB upload",
  "timeBox": "45 min / 2 files",
  "confounds": ["local disk, not the production object store"],
  "engines": ["claude", "codex"],
  "runs": [
    { "engine": "claude", "result": "confirmed", "evidence": "peak RSS 180 MB (run output)" },
    { "engine": "codex", "result": "confirmed", "evidence": "peak RSS 172 MB (run output)" }
  ],
  "result": "confirmed|falsified|inconclusive",
  "location": "plans/{slug}/spikes/streaming-upload-size/",
  "ranAt": "ISO-8601"
}
```

Then update the plan's evaluation when one exists: **confirmed** raises the approach's feasibility and marks the failure mode addressed with the spike as mitigation; **falsified** meets the kill criterion, so demote the approach and change the recommendation; **inconclusive** keeps the failure mode as a risk and a pre-build verification task, with the confound or disagreement noted. Report the question, the verdict, the evidence, and the limit on it in a few lines.

## Never

Run without a pre-stated falsification criterion; let a spike grow into the implementation; merge spike code; give Codex credentials or real data the user has not approved for the spike; call a two-engine disagreement "confirmed".
