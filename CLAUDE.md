# amux — contributor notes

A Claude Code plugin: four skills. There is no build step; the files are the product.

## Layout

- `skills/<name>/SKILL.md` — one skill and its `/amux:<name>` entry point (frontmatter `name` equals the directory). Skills reference each other as `amux:<name>`.
- `scripts/validate.sh` — structural checks; CI runs it on every push.

There is no `agents/` directory. A skill that needs fresh context starts a subagent with an inline brief.

## Conventions

- **A skill is a contract, not a procedure.** Write what the model cannot infer: what is permitted, what done means, when to stop, and what must go to the user. Do not tell it how to think, how to parse output, or which order to read files in. A skill stays under 900 words; `scripts/validate.sh` enforces that.
- **Whoever writes the work does not judge it.** The judge always has fresh context and gets a written brief, never the author's reasoning. Codex is the judge when installed because it is a different model; the fallback is a fresh subagent, and the report says which ran. A judge's finding is a lead until the author has checked it.
- **Design findings are the user's decision** at any verdict; only implementation findings are fixed without asking.
- **Failure conditions are stated before the work:** kill criteria on approaches, falsified-if on spikes, a failing test before the fix.
- **Codex only argues against things.** It is called as `codex exec` through Bash with the CLI's default model, read-only except a spike confined to its own directory.
- **The plugin works without the user's CLAUDE.md,** and the user's own instructions override any skill, including `ship`'s permissions.
- **One state file per plan,** `plans/{slug}/prd.md`, written from the first step so a context reset can resume. No JSON state, no counters.
- **No pinned models.** Skills and their subagents run on the session's model.
- **No skill depends on a Claude Code built-in skill or command** being present; installs differ.

## Before committing

```
bash scripts/validate.sh
```

Bump `version` in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, and add a `## [x.y.z]` entry to `CHANGELOG.md`. Removing or renaming a skill or artifact format is a major bump.
