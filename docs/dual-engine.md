# Dual-engine standard (canonical)

How amux uses Codex as a second engine. This file is the single source of truth: `scripts/validate.sh` checks that every skill and agent names the same Codex model as this file, so change it here first.

## Model

`gpt-6-astra`

## Where Codex is used

Codex argues against something; it never co-authors the finding it would then be asked to confirm. Agreement between two cooperative passes is a display signal at best (they can share a blind spot), so the plugin spends Codex calls only where disagreement carries information:

| Role | Who calls it | What it is asked |
|---|---|---|
| Verification | `verify` agent, once per batch | Refute each implementation or plan claim; defend the design against each design finding; cite `file:line` |
| Pre-mortem | `premortem` agent | Argue the strongest case against the recommended approach and for the best alternative |
| Challenge | research challengers | The strongest evidence that a finding is wrong, outdated, or overstated |
| Spike | `spike` skill, optional | Run the same experiment independently in its own directory; disagreement with Claude's run makes the spike inconclusive |

Reviewers and researchers do not call Codex. A Codex objection is a lead, not evidence: it counts only once the Claude agent has checked it and cited the evidence.

## Transport

The `codex` MCP tool is served by the plugin itself: `mcp/codex.py`, declared in `.claude-plugin/plugin.json`, is a standard-library Python stdio MCP server that runs one `codex exec --skip-git-repo-check -C {cwd} -m {model} -s {sandbox} -o {file} -` per call and returns the agent's final message as text. Codex CLI deprecated its native `codex mcp-server` in 0.149.1 and removed it in 0.154.0; the replacement, `codex app-server`, is an experimental JSON-RPC protocol that is not MCP, so the shim keeps the old tool's name and parameters (`prompt`, `model`, `sandbox`, `cwd`, `profile`, `config`) and adds `output-schema` and `timeout-seconds`. It is one-shot: there is no `codex-reply`. Parallel calls run concurrently; a client cancel or the timeout (`AMUX_CODEX_TIMEOUT`, default 900 s) kills the whole Codex process tree. `AMUX_CODEX_BIN` points it at a Codex binary that is not on `PATH`.

## Call

`model: gpt-6-astra`, `cwd` set to the repository root (or the spike directory), `sandbox: read-only` everywhere except the spike's `workspace-write` run. Reference repo files with `@` repo-relative paths so Codex resolves them via `cwd`. Ask for JSON keyed the way the calling agent needs it.

## Availability

Treat Codex as unavailable if the call errors or times out, or the response is empty, non-JSON, or an error result (its text starts with `Codex`, for example `Codex CLI Not Found`). Every path then continues Claude-only and says so (`enginesUsed: ["claude"]`); no stage is skipped for a missing second engine.
