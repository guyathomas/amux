# amux — contributor notes

A Claude Code plugin: four skills and four agents. There is no build step; the files are the product.

## Layout

- `skills/<name>/SKILL.md` — orchestration and the `/amux:<name>` entry point (frontmatter `name` equals the directory). A skill decides what to dispatch and what to do with the results; it does not restate an agent's instructions. Keep a skill to roughly a thousand words: the model does not need to be told to skip malformed JSON.
- `agents/<name>.md` — one role with a fixed JSON output. Frontmatter `name` must equal the filename; the output JSON's `"agent"` field must equal it too. Skills reference agents as `amux:<name>`. Agents carry no `tools:` line, so they inherit every tool in the user's environment, including research MCPs; `scripts/validate.sh` enforces that.
- `scripts/validate.sh` — structural checks; CI runs it on every push.

## Conventions

- Every skill separates *finding* from *judging*: one reviewer or researcher produces claims, an independent verifier or challenger with fresh context tries to break them, and only cited evidence drives action. Keep that shape when adding a stage; do not add specialist finders, add a section to the existing one.
- Judgment findings (design, scope) are the user's decision at any verdict; only implementation findings are ever auto-fixed.
- Pre-stated failure conditions everywhere they apply: kill criteria on approaches, falsified-if on spikes, RED tests before a gate opens.
- Codex is used only where it argues against something (verify, pre-mortem, research challengers, planning's optional dual-engine spike), called as `codex exec` through Bash with the CLI's default model, and every path has a Claude-only fallback that says so.
- Skills prescribe evidence standards, not tools. Don't hard-code tool names beyond `codex exec` and the built-ins; agents check their tool list and honor any preferences in the user's own instructions.
- One state file per run (`plans/{slug}/plan.json`, `research/{slug}/state.json`) with the phase and what is done, so a context reset can resume. No counters, no per-phase files.
- Agents use `model: inherit`. Pin `fable` only where a wrong judgment silently drops a finding or misdirects the build: `verify`, `premortem`, `build-plan`. `scripts/validate.sh` enforces that list. Fable is optional: switch those files to `inherit` and everything still works.

## Before committing

```
bash scripts/validate.sh
```

Bump `version` in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, and add a `## [x.y.z]` entry to `CHANGELOG.md`. Removing or renaming a skill, agent, or artifact format is a major bump.
