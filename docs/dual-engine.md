# Dual-engine standard (canonical)

This is the single source of truth for how amux skills and agents use Codex as a second engine. The skills that inject the standard into teammate prompts (`code-review-pipeline`, `plan-review`) carry a copy inline because prompts are assembled from the skill text; the `planning` and `research` skills and the verifier agents carry the short form. `scripts/validate.sh` checks that every copy names the same Codex model as this file, so change it here first.

## Model

`gpt-6-astra`

## Transport

The `codex` MCP tool is served by the plugin itself: `mcp/codex.py`, declared in `.claude-plugin/plugin.json`, is a standard-library Python stdio MCP server that runs one `codex exec --skip-git-repo-check -C {cwd} -m {model} -s {sandbox} -o {file} -` per call and returns the agent's final message as text. Codex CLI deprecated its native `codex mcp-server` in 0.149.1 and removed it in 0.154.0; the replacement, `codex app-server`, is an experimental JSON-RPC protocol that is not MCP, so the shim keeps the old tool's name and parameters (`prompt`, `model`, `sandbox`, `cwd`, `profile`, `config`) and adds `output-schema` and `timeout-seconds`. It is one-shot: there is no `codex-reply`, because no skill continues a Codex thread. Parallel calls run concurrently; a client cancel or the timeout (`AMUX_CODEX_TIMEOUT`, default 900 s) kills the whole Codex process tree. `AMUX_CODEX_BIN` points it at a Codex binary that is not on `PATH`. Every failure (CLI missing, not logged in, non-zero exit, timeout, cancel) is an error result whose text starts with `Codex`, which the availability rule below treats as unavailable.

## Call

Call the `codex` MCP tool with `model: gpt-6-astra`, `sandbox: read-only`, and `cwd` set to the repository root. Reference repo files with `@` repo-relative paths (e.g. `@src/auth.ts`, `@plans/{slug}/prd.md`) so Codex resolves them via `cwd`. Ask for JSON in the same shape the calling agent returns.

## Availability

Treat Codex as **unavailable** if the call throws or times out, or the response is empty, non-JSON, or contains MCP error text (e.g. `"Codex CLI Not Found"`). When unavailable, continue Claude-only: findings carry `"engines": ["claude"]` and `crossValidated: false`; evaluations carry `"enginesUsed": ["claude"]` with lowered confidence; the pipeline never stops for a missing second engine.

## Merge

Merge by location (`file` + `line` ±3 for code; `section` for plans; the question for research) plus semantic similarity:

- **AGREE** — both engines found it → `crossValidated: true`, confidence = max(claude, codex). Agreement is a display signal, not a score bump: two engines can share a blind spot, and adversarial verification is the gate.
- **CHALLENGE** — same location, differing severity or contradicting claim → keep the higher severity (or the web-cited version, for research), set `severityDispute: true`, and surface it separately — cross-model gain concentrates where the engines diverge.
- **COMPLEMENT** — one engine only → include with `crossValidated: false` (research: Codex-only facts are `status: "hypothesis"` until web-confirmed).

## Adversarial use

Beyond cross-validation, each skill also uses Codex *against* the primary result: the verifiers ask it to refute a finding or defend a design; the planning pre-mortem asks it to argue for the alternative; research challengers ask it for the case against a claim. A Codex objection is a lead, not evidence — it counts only once the verifier confirms it with cited evidence.
