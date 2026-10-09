---
name: research
description: Use when the user explicitly asks for deep research or comprehensive analysis across many authoritative sources. Decomposes the topic, researches the questions in parallel, has independent challengers try to break the load-bearing findings, iterates until the questions are actually answered, and writes a report with source attribution and confidence. NOT for questions a single search answers.
---

<objective>
Decompose, research in parallel, challenge what the report will rest on, judge sufficiency, synthesize. Done when every question is answered at medium or better confidence by findings that survived CHALLENGE (or the gaps are documented) and `report.md` is written. Sufficiency is the bar, not a source count, and a finding nobody tried to break is never high confidence.
</objective>

<tools>
Use whatever search and page-fetch tools your environment provides; the built-in `WebSearch` and `WebFetch` always work, and a richer installed tool is better on JS-rendered pages. Check your tool list before falling back, and use any tools the user's own instructions prefer. Source quality: Tier 1 is .gov, .edu, journals, official docs; Tier 2 is Reuters, AP, BBC, industry publications; Tier 3 is company blogs and Wikipedia; skip forums, social media, and SEO spam. Primary sources beat articles about them.
</tools>

<state>
`research/{slug}/state.json` (slug: lowercase, hyphens, `a-z0-9-`, at most 50 characters):

```json
{ "topic": "...", "phase": "DECOMPOSE|RESEARCH|CHALLENGE|EVALUATE|SYNTHESIZE|DONE", "iteration": 1, "maxIterations": 3,
  "questions": [{ "id": 1, "text": "...", "status": "pending|done", "confidence": null }] }
```

`findings.json` holds every finding; `task-loop.json` (`active`, `complete`, `continuationPrompt`, `statusMessage`, `completionMessage`) keeps the session on the job until EVALUATE passes or the iteration ceiling is hit. Read state before acting and write it after each phase. On invocation with existing state, resume from its phase and say so.
</state>

<steps>

<phase name="DECOMPOSE">
Decompose the topic into the questions that matter for it; cover the angles the topic warrants (background, current state, mechanisms, evidence, criticisms, alternatives, trajectory) and skip the rest. Add them as `pending`. Set `maxIterations` (default 3; raise it for a broad topic). Initialize the task loop.
</phase>

<phase name="RESEARCH">
Dispatch researchers in parallel, one per pending question, giving closely related questions to one researcher. Each gets the instructions below and returns JSON only.

<researcher>
Research this question: {QUESTION}. Run enough searches to answer it well, fetch the best sources, and extract specific facts with their sources. Prefer higher-tier sources; continue past a failed fetch. Return:
```json
{ "questionId": 1, "findings": [{ "fact": "...", "sourceUrl": "...", "tier": 1 }], "gaps": ["..."], "contradictions": ["X says A, Y says B"], "confidence": "high|medium|low", "confidenceReason": "..." }
```
</researcher>

Append findings to `findings.json`, mark the question done with its confidence, then set `phase: "CHALLENGE"`.
</phase>

<phase name="CHALLENGE">
Researchers are motivated to answer, so their findings skew toward whatever confirmed the question's framing. Before judging sufficiency, try to break what the report will rest on. The researcher finds; the challenger judges; they never share a context window.

1. Select this iteration's load-bearing findings (no `verdict` yet): every high-confidence finding and any medium finding that answers a question by itself. Rank by how much the report changes if the finding is wrong. Group them by source URL, since the citation check is per source, and cap at 4 groups per round; unchallenged findings stay capped at medium confidence.
2. Dispatch one challenger per group, in parallel, with the instructions below. Challengers get the findings, their source, and the questions, never the researcher's reasoning.
3. Apply verdicts in `findings.json`: **CONFIRMED** (eligible for high confidence), **DISPUTED** (keep, attach `counterEvidence`, cap at medium, report under Conflicting Information), **REFUTED** (excluded from synthesis except the refuted list; if it answered a question, reopen the question), **UNSETTLED** (cap at medium). Then `phase: "EVALUATE"`.

<challenger>
You receive findings that cite one source. Your only job is to try to break them; you have no stake in the answer.
Findings: {findings with ids} · Source: {sourceUrl} (tier {tier}) · Questions: {questionTexts}
1. Fetch the source. Does it say each claim, with the same numbers, scope, and date? A misquote, an over-generalization, or a figure the source has since updated is a refutation. If the source cites something else, find the primary.
2. Search for the opposite: "{claim} debunked", "criticism", "retracted", "updated {year}", the competing figure. Favour Tier 1 and 2. Note newer data that supersedes the claim.
3. Call the `codex` MCP tool (`model: gpt-6-astra`, `sandbox: read-only`) once: "Argue against these claims: {facts}. What is the strongest evidence each is wrong, outdated, or overstated? Return JSON objections keyed by finding id." Unavailable means skip it. An objection is a lead; confirm it on the web before it counts.
Verdicts need evidence: REFUTED requires the source contradicting the finding or a Tier 1-2 counter-source you cite; DISPUTED requires a credible counter-source; CONFIRMED requires the source verified verbatim and a real search for the opposite that came up empty; otherwise UNSETTLED.
Return: `{ "verdicts": [{ "id": "...", "verdict": "CONFIRMED|DISPUTED|REFUTED|UNSETTLED", "sourceVerified": true, "counterEvidence": [{ "claim": "...", "sourceUrl": "...", "tier": 1 }], "note": "the decisive observation" }] }`
</challenger>
</phase>

<phase name="EVALUATE">
Synthesize when every question is answered at medium or better by findings that are not refuted, and significant gaps, contradictions, and DISPUTED findings are resolved or explicitly documented as limitations. Otherwise generate sharper follow-up questions from the gaps, refuted findings, and disputes, add them as pending, increment `iteration`, update the task loop with the open questions, and return to RESEARCH, unless `maxIterations` is reached, in which case synthesize with the gaps documented. Don't pad sources to hit a number and don't quit while a question is still thin.
</phase>

<phase name="SYNTHESIZE">
Write `research/{slug}/report.md`: executive summary (most important finding first, with confidence and caveats); background; key findings grouped by theme with inline citations; conflicting information (both sides, which is better sourced, every DISPUTED finding with its counter-evidence); gaps and limitations (including what was REFUTED and why, since the reader may have seen it elsewhere); source assessment (high confidence: CONFIRMED with multiple quality sources; medium: one or two sources, or DISPUTED, UNSETTLED, or unchallenged; low: single Tier 3 source); and the source list by tier. Footer: iterations, questions, findings challenged and refuted, date. Set `phase: "DONE"` and complete the task loop with the report path.
</phase>

</steps>

<error_handling>
Malformed JSON from a researcher or challenger: retry once, then mark the question low confidence or the finding UNSETTLED. A fetch fails: continue with other sources. A challenger cannot reach the claimed source: UNSETTLED, never taken on faith. Codex unavailable: the challenger proceeds without it.
</error_handling>
