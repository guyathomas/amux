---
name: research
description: Use when the user explicitly asks for deep research or comprehensive analysis across many authoritative sources. Decomposes the topic, researches the questions in parallel, has independent challengers try to break the load-bearing findings, iterates until the questions are answered, and writes a report with source attribution and confidence. NOT for questions a single search answers.
argument-hint: "[topic]"
---

# Research

Decompose, research in parallel, challenge what the report will rest on, judge sufficiency, synthesize. Done when every question is answered at medium or better by findings that survived CHALLENGE (or the gaps are documented) and `report.md` is written. A finding nobody tried to break is never high confidence.

Tier 1: .gov, .edu, journals, official docs. Tier 2: Reuters, AP, BBC, industry publications. Tier 3: company blogs, Wikipedia. Skip forums, social media, SEO spam. Primary sources beat articles about them.

**Tool check.** Before starting, tell the user in one short block which tool will serve each capability in the Tools section, which are not installed or not running, and whether Codex is available (`command -v codex`). Paste the Tools section into every researcher and challenger prompt. The final output lists every `toolsDegraded` entry from you and your agents under **Tools degraded**, or says none were; append them to `toolsDegraded` in the state file as they arrive.
<!-- tools -->
## Tools

Pick by job and use the first option your tool list has. Tool preferences in the user's own instructions override this order. The built-ins at the end of each line always work.

- **Library or framework behaviour:** a docs tool that serves the exact version (e.g. Context7). When the docs are vague, silent, or disagree with what you observe, read the library's source: `git clone --depth 1` into a scratch directory outside the repo, or a source-indexing tool, and cite upstream `file:line`. Built-in: WebFetch on the official docs.
- **Prior art:** analogous open-source implementations, found with a GitHub tool or `gh search repos` / `gh search code`. Clone the promising ones and read the code, not the README.
- **Web search:** a search tool (e.g. Serper, Firecrawl search). Built-in: WebSearch.
- **Reading a page:** a scraping tool that renders JavaScript (e.g. Firecrawl). Built-in: WebFetch.
- **This repo:** Grep, Glob, Read; an LSP or code-intelligence tool when present.

Call out every gap; never degrade silently. Record each in `toolsDegraded` in your output, `[{ "capability": "web search", "tool": "Firecrawl", "status": "not-installed|not-running|needs-auth|denied|quota-exhausted|error|timeout", "detail": "...", "fellBackTo": "WebSearch" }]`:
- **not-installed:** no non-built-in option for a capability you needed is in your tool list.
- **not-running:** your context says the server failed to connect, or every call fails to reach it.
- **needs-auth:** the tool asks for a login or API key you cannot provide.
- **denied:** the session's permissions blocked the call.
- **quota-exhausted:** the tool reports exhausted credits, quota, or a rate limit. Do not retry it this run.
- **error / timeout:** after one retry.
Then move to the next option. Omit the field when nothing degraded.
<!-- /tools -->


## State

`research/{slug}/state.json` (slug `a-z0-9-`, at most 50 characters):

```json
{ "topic": "...", "phase": "DECOMPOSE|RESEARCH|CHALLENGE|EVALUATE|SYNTHESIZE|DONE", "iteration": 1, "maxIterations": 3, "toolsDegraded": [],
  "questions": [{ "id": 1, "text": "...", "status": "pending|done", "confidence": null }] }
```

`findings.json` holds every finding. Write state after each phase; with existing state, resume from its phase and say so. Keep iterating until DONE; do not stop to ask between phases.

## Process

### DECOMPOSE
The questions that matter for this topic (background, current state, mechanisms, evidence, criticisms, alternatives, trajectory — only those it warrants), all `pending`. Raise `maxIterations` for a broad topic.

### RESEARCH
One researcher per pending question (related questions share one), in parallel:

> Research this question: {QUESTION}. Run enough searches to answer it well, fetch the best sources, extract specific facts with their sources, prefer higher tiers, continue past failed fetches. Return JSON only: `{ "questionId": 1, "findings": [{ "fact": "...", "sourceUrl": "...", "tier": 1 }], "gaps": [], "contradictions": [], "confidence": "high|medium|low", "confidenceReason": "..." }`

Append findings, mark questions done.

### CHALLENGE
Researchers skew toward whatever confirms the question's framing, so try to break what the report rests on. Select this iteration's unchallenged load-bearing findings (every high-confidence finding, and any medium one that answers a question alone), rank by how much the report changes if wrong, group by source URL, cap at 4 groups. Unchallenged findings stay capped at medium. One challenger per group, in parallel, given the findings, source, and questions — never the researcher's reasoning:

> You receive findings citing one source. Your only job is to break them. Findings: {findings with ids} · Source: {sourceUrl} (tier {tier}) · Questions: {questions}
> 1. Fetch the source. Does it say each claim with the same numbers, scope, and date? A misquote, over-generalization, or since-updated figure is a refutation. Chase citations to the primary.
> 2. Search for the opposite: debunked, criticism, retracted, updated figures. Favour Tier 1–2.
> 3. Once, run `codex exec --skip-git-repo-check -s read-only -o "$out" -` (with `out=$(mktemp)`) through Bash with the prompt "Argue against these claims: {facts}. Strongest evidence each is wrong, outdated, or overstated? JSON objections keyed by finding id." on stdin, and read the `-o` file. Codex unavailable: skip. An objection is a lead until you confirm it on the web.
> REFUTED needs the source contradicting the finding or a cited Tier 1–2 counter-source; DISPUTED a credible counter-source; CONFIRMED the source verified verbatim and an empty search for the opposite; else UNSETTLED. Return JSON only: `{ "verdicts": [{ "id": "...", "verdict": "CONFIRMED|DISPUTED|REFUTED|UNSETTLED", "sourceVerified": true, "counterEvidence": [{ "claim": "...", "sourceUrl": "...", "tier": 1 }], "note": "..." }] }`

Apply: CONFIRMED may be high confidence; DISPUTED keeps counter-evidence, capped at medium; REFUTED is excluded (reopen its question); UNSETTLED caps at medium. An unreachable source is UNSETTLED.

### EVALUATE
Synthesize when every question is answered at medium or better by unrefuted findings and gaps and disputes are resolved or documented. Otherwise add sharper follow-up questions from the gaps, refutations, and disputes, increment `iteration`, and return to RESEARCH — unless `maxIterations` is reached, then synthesize with the gaps documented.

### SYNTHESIZE
`research/{slug}/report.md`: executive summary (most important finding first, with confidence); background; key findings by theme with inline citations; conflicting information (every DISPUTED finding with its counter-evidence); gaps and limitations (including what was REFUTED and why); source assessment; sources by tier. Footer: iterations, questions, findings challenged and refuted, tools degraded, date. Set `phase: "DONE"`.

Malformed JSON from a researcher or challenger: retry once, then mark low confidence or UNSETTLED.
