# Amux

Plan, ship, and challenge skills for Claude Code. Each skill states a contract (what is permitted, what done means, when to stop, what must come to you) and leaves the method to the model. Whoever writes the work never judges it: an independent judge with fresh context argues against it, and Codex is that judge when installed.

## What's Included

### Skills (4)

Invoke as `/amux:<name>` or let Claude pick one when the request matches.

- **plan** — Researches approaches against real sources, states what would rule each one out before recommending any, runs a pre-mortem through `challenge`, spikes open feasibility questions against a pre-stated falsifier, and once you choose writes a checklist mapping every acceptance criterion and surviving risk to the proof that closes it.
- **ship** — Takes a change from wherever it stands to a merged PR: finishes it (one checklist item at a time when there is a plan), proves it, has it challenged, files the PR, watches CI and review, and merges when the merge gate passes. `no-merge` stops when the PR is ready. It returns to `plan` when the code refutes the plan.
- **challenge** — An independent judge argues against a diff or a plan. You get a budgeted loop of three rounds in which every finding is checked, then fixed, disputed with evidence, or declined. Design findings always come to you.
- **retro** — End-of-session retrospective: finds where the session lost time or quality and proposes exact changes to your CLAUDE.md files, project skills, or amux, each backed by a quoted moment. Nothing is applied without your approval.

### Artifacts written to your repo

| Path | Written by | Suggested handling |
|---|---|---|
| `plans/{slug}/prd.md` | plan, ship | Commit: the record of why the code looks the way it does |
| `plans/{slug}/spikes/` | plan | Throwaway; delete once recorded |
| `retros/{date}-{slug}.md` | retro | Commit or ignore |

## How it stays honest

- **Proof is observed, not asserted.** A fix counts when the reproduction that failed now passes, or a test written first failed on an assertion and now passes. Mocked tests do not prove a UI works.
- **Failure conditions come first.** Approaches carry kill criteria before one is recommended; spikes carry a falsifier before they run.
- **The judge has fresh context.** It receives a written brief and the work, never the author's reasoning. Its findings are leads until checked, and a timeout or an exhausted budget is not approval.
- **Design is your call.** Only implementation findings are fixed without asking.

## What ship is allowed to do

Invoking `ship` permits branching, committing, pushing the PR's branch (force-pushing it with `--force-with-lease` after a rebase), and merging once the merge gate passes: proof for every change, required checks green, the challenge agreed, review findings settled, and the branch up to date and mergeable. It never uses `--admin` or bypasses branch protection, and never touches production, data, other branches, or anything outside the repo. Your own and your project's instructions override it, so a rule that says to ask before merging still holds. Pass `no-merge` to keep the merge for yourself.

## Codex

Codex argues against things; it never co-authors. `challenge` runs `codex exec` through Bash in a read-only sandbox with your Codex CLI's default model, and `plan` can give it an independent spike confined to its own directory. Without Codex the judge is a fresh Claude subagent and the report says so. Unless you run in auto mode, allow `Bash(codex exec:*)` in your settings to avoid a permission prompt per call.

## Prerequisites

- **Claude Code** with plugin support
- **GitHub CLI** (`gh`), authenticated, for `ship`
- **Codex CLI** (optional): `npm i -g @openai/codex`

## Installation

```bash
/plugin marketplace add guyathomas/amux
/plugin install amux@amux
```

## Validation

`bash scripts/validate.sh` checks the manifests, skill names, the per-skill word limit, references, stale references to removed components, and the count in this README. CI runs it on every push and pull request.

## License

MIT — see [LICENSE](LICENSE)
