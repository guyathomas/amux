# amux — contributor notes

A Claude Code plugin: skills, agents, commands, and hooks. There is no build step; the files are the product.

## Layout

- `skills/<name>/SKILL.md` — orchestration. A skill decides what to dispatch and what to do with the results; it should not restate an agent's lenses.
- `agents/<name>.md` — one reviewer, verifier, or researcher role with a fixed JSON output. Frontmatter `name` must equal the filename; the output JSON's `"agent"` field must equal it too. Skills reference agents as `amux:<name>`.
- `commands/<name>.md` — thin `/amux:<name>` entry points that invoke a skill.
- `hooks/` — `hooks.json` plus the scripts it runs. Nothing here enforces automatically; the session-start banner announces, the task-loop hook keeps a long-running skill alive until it declares completion.
- `docs/dual-engine.md` — the canonical Codex standard and the one place the Codex model name is authoritative.
- `scripts/validate.sh` — structural checks; CI runs it on every push.

## Conventions

- Every skill separates *finding* from *judging*: a reviewer or researcher produces claims, an independent verifier or challenger with fresh context tries to break them, and only evidence-backed verdicts drive action. Keep that shape when adding a stage.
- Judgment findings (design, scope) are the user's decision at any verdict; only implementation findings are ever auto-fixed.
- Skills don't prescribe research MCPs; they use whatever the environment provides. Don't hard-code tool names beyond `codex` and the built-ins.
- Codex is optional everywhere: every path has a Claude-only fallback and says so.
- Agent teams are optional: teammates fall back to subagents with the same roles and protocol.

## Before committing

```
bash scripts/validate.sh
```

Bump `version` in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, and add a `## [x.y.z]` entry to `CHANGELOG.md`. Removing or renaming a command, hook, or artifact format is a major bump.
