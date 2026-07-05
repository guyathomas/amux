---
name: research
description: Use when user explicitly requests deep research or comprehensive analysis across many authoritative sources. Creates an agent team for parallel research, gated on answer sufficiency (not a source count), with confidence tracking and structured synthesis. NOT for simple questions answerable with a single search.
---

<objective>
Comprehensive research using an agent team, web search, and web scraping. Iteratively decomposes topics, gathers evidence from quality sources via parallel researcher teammates, and synthesizes findings into structured reports.

Core principle: Decompose questions, research in parallel with an agent team, evaluate confidence, iterate until sufficient, synthesize with source attribution.
</objective>

<success_criteria>
Done when: `state.json` `phase` is `"DONE"`, every question is answered at `medium`+ confidence (or remaining gaps are documented as limitations), and `report.md` synthesizes findings with source attribution, conflicts, gaps, and limitations. Sufficiency — not a source count — is the bar.
</success_criteria>

<when_to_use>
Use when the user explicitly asks for deep research / comprehensive analysis needing multiple authoritative sources, confidence tracking, and source attribution.

Don't use for simple factual questions a single search answers, or topics too narrow for an 8-question decomposition.
</when_to_use>

<required_tools>
| Tool / Feature | Purpose | Required |
|------|---------|----------|
| Web search | Run search queries | Yes |
| Web page fetch/scrape | Pull full page content from sources | Yes |
| Agent teams | Spawn parallel researcher teammates | Yes |

**Prerequisite:** Agent teams must be enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings or environment).

Tool Selection: Use whatever search and page-fetch tools your environment provides. The built-in `WebSearch` / `WebFetch` always work; if you have a richer search or scrape tool installed, prefer it for better extraction on JS-rendered pages. The skill doesn't prescribe a specific provider — pick what gives the best results for the sources you hit.
</required_tools>

<state_machine>
```
INIT → DECOMPOSE → RESEARCH → EVALUATE → [RESEARCH or SYNTHESIZE] → DONE
```

State File: `research/{slug}/state.json`

```json
{
  "topic": "string",
  "phase": "INIT|DECOMPOSE|RESEARCH|EVALUATE|SYNTHESIZE|DONE",
  "iteration": 0,
  "maxIterations": 5,
  "targetSources": 30,
  "sourcesGathered": 0,
  "totalSearches": 0,
  "teammateCompletions": 0,
  "codexCompletions": 0,
  "findingsCount": 0,
  "startTime": "ISO-8601 timestamp",
  "questions": [{"id": 1, "text": "...", "status": "pending|done", "confidence": null}]
}
```

Rule: Read `state.json` before acting. Write `state.json` after acting.
</state_machine>

<task_loop>
A generic task loop hook prevents the session from ending while `task-loop.json` has `complete: false`, so research isn't abandoned mid-flight.

How it works:
1. When you try to exit, the hook reads `research/{slug}/task-loop.json`
2. If `complete` is false, exit is blocked and `continuationPrompt` is re-injected
3. Once you set `complete: true`, exit is allowed and `completionMessage` is displayed

You manage `task-loop.json` alongside `state.json`. Update `statusMessage` and `continuationPrompt` as progress changes. Set `complete: true` when EVALUATE's sufficiency gate passes **or** the iteration ceiling is hit — both are legitimate exits, so the loop always terminates.
</task_loop>

<state_recovery>
On skill invocation, first check for existing state:

1. If `research/{slug}/state.json` exists:
   - Parse JSON; if invalid, offer to restart
   - Resume from current `phase`
   - Notify user: "Resuming research from {phase} phase"

2. Verify state consistency before resuming:
   - RESEARCH: Ensure pending questions exist
   - EVALUATE: Ensure `findings.json` has data
   - SYNTHESIZE: Ensure all questions marked "done"

3. If inconsistent, offer user choice:
   - Delete state and restart
   - Attempt repair (mark incomplete questions as pending)
</state_recovery>

<steps>

<phase name="INIT">
1. Generate slug from topic:
   - Lowercase the topic
   - Replace spaces with hyphens
   - Remove special characters (keep only `a-z`, `0-9`, `-`)
   - Truncate to 50 characters
   - Example: "AI in Healthcare 2024!" → `ai-in-healthcare-2024`

2. Note which search and page-fetch tools your environment provides (built-in `WebSearch` / `WebFetch` are always available; use a richer installed tool if you have one). No specific provider is required.

3. Create working directory:
   ```bash
   mkdir -p research/{slug}
   ```

4. Set `targetSources` as a rough expectation for the topic's breadth (narrow ~20, standard ~30, broad ~40) and `maxIterations` (default 5). These are signals/backstops, not the completion bar — sufficiency is.

5. Initialize state files:

   state.json: use the schema from `<state_machine>` with `phase: "DECOMPOSE"`, counters at 0, `startTime` set, `questions: []`.

   task-loop.json (activates the generic task loop hook):
   ```json
   {
     "active": true,
     "complete": false,
     "continuationPrompt": "Continue researching: {topic}. Check research/{slug}/state.json and continue the RESEARCH phase.",
     "statusMessage": "Research in progress: {topic}",
     "completionMessage": "Research complete."
   }
   ```

   findings.json:
   ```json
   []
   ```
</phase>

<phase name="DECOMPOSE">
Decompose the topic into the questions that actually matter for it. Use your judgment on count and framing — cover the angles the topic warrants and skip those it doesn't.

Common angles to draw from (a menu, not a checklist): definition/background, current state, key entities, core mechanisms, evidence and data, criticisms and limitations, comparisons to alternatives, future developments. Add others the specific topic demands.

Add questions to `state.json` with `status="pending"`. Set `phase="RESEARCH"`.
</phase>

<phase name="RESEARCH">
Create an agent team to research pending questions in parallel. Each teammate independently searches with Claude AND cross-validates with Codex via the `codex` MCP tool.

**Claude teammates:** One per pending question (up to 8 at a time). Each works independently with its own context window. Each teammate also calls the `codex` MCP tool to get Codex's perspective on the same question, providing genuine cross-validation — two engines may surface different sources and perspectives.

Spawn each Claude teammate with these instructions:

<teammate_instructions>
You are a researcher teammate. Use whatever web search and page-fetch tools you have available (the built-in `WebSearch` / `WebFetch` always work; prefer a richer installed tool if you have one).

**TASK:** {QUESTION}

Run enough searches to answer the question well, then fetch the best sources ("Extract main content and key facts") and extract specific facts with their sources. Continue if a fetch fails. Use your judgment on how many searches and sources are enough.

Quality guide (favour higher tiers): Tier 1 — .gov, .edu, journals, official docs · Tier 2 — Reuters, AP, BBC, industry pubs · Tier 3 — company blogs, Wikipedia · Skip — forums, social media, SEO spam.
</teammate_instructions>

<teammate_codex_crossvalidation>
## Cross-Validation with Codex

After web research, call the `codex` MCP tool (`model: gpt-5-codex`, `sandbox: read-only`) with prompt: "Research this question: {QUESTION}. Return JSON findings with fields: fact, sourceNote, confidence (high/medium/low). Focus on facts confirmable from training data."

Treat codex as unavailable if the call throws/times out, or returns empty/non-JSON/MCP-error text (e.g. `"Codex CLI Not Found"`) — then return Claude-only findings. If valid JSON, merge per question:
- **AGREE** (same fact): boost confidence, mark cross-validated.
- **CHALLENGE** (contradicts web fact): keep web version, document the contradiction.
- **COMPLEMENT (Codex-only)**: include with `"status": "hypothesis"` (no web citation).
- **COMPLEMENT (Claude-only)**: keep as-is.
</teammate_codex_crossvalidation>

<teammate_return_format>
**RETURN ONLY THIS JSON:**
```json
{
  "questionId": {ID},
  "questionText": "{QUESTION}",
  "searchQueries": ["query1", "query2", "query3", "query4"],
  "searchesRun": 4,
  "urlsScraped": 4,
  "scrapeFailures": [],
  "findings": [
    {
      "fact": "...",
      "sourceUrl": "...",
      "tier": 1,
      "crossValidated": false,
      "engines": ["claude"],
      "status": "confirmed|hypothesis|disputed"
    }
  ],
  "gaps": ["what you couldn't find"],
  "contradictions": ["X says A, Y says B"],
  "confidence": "high|medium|low",
  "confidenceReason": "...",
  "codexAvailable": true
}
```
</teammate_return_format>

After each Claude teammate completes:
1. Validate JSON. Retry once if malformed.
2. Append to `findings.json`
3. Update `state.json`:
   - Mark question done
   - Increment `totalSearches` by `searchesRun` from response
   - Increment `teammateCompletions` by 1
   - Increment `sourcesGathered` by `urlsScraped` from response
   - Increment `findingsCount` by length of `findings` array from response
   - If `codexAvailable` is true, increment `codexCompletions` by 1
4. Log progress: `"Sources: {sourcesGathered}/{targetSources}"`

After all teammates complete:
1. Set `phase="EVALUATE"`
</phase>

<phase name="EVALUATE">
Decide whether the research is **sufficient** — judged on whether the questions are actually answered, not on a source count.

**Sufficiency gate → SYNTHESIZE when both hold:**
- Every question is answered at `medium` confidence or better (high=3, medium=2, low=1).
- Significant gaps and contradictions are resolved, or explicitly documented as limitations.

`sourcesGathered` vs `targetSources` is a **sanity signal**, not a gate: if you'd synthesize with far fewer sources than expected, double-check you haven't stopped short; if you're well past target but still thin, keep going. Don't pad to hit a number.

**Otherwise → RESEARCH** another round, unless the **iteration ceiling** (`maxIterations`, default 5) is reached — then SYNTHESIZE with the remaining gaps documented as limitations (futility exit; never loop forever).

If continuing to RESEARCH:
1. Generate follow-up questions from gaps/contradictions (as many as the gaps warrant)
2. Add to questions with `status="pending"`; increment `iteration`; set `phase="RESEARCH"`
3. Update `task-loop.json`: set `statusMessage` and `continuationPrompt` to the specific open questions
4. Log: `"Continuing research: {N} questions still below confidence / {M} open gaps"`

Set `complete: true` in `task-loop.json` only when the sufficiency gate passes or the iteration ceiling is hit.
</phase>

<phase name="SYNTHESIZE">
Write `report.md`:

```markdown
# {Topic}

## Executive Summary
[300-400 words. Most important finding first. State confidence. Note caveats.]

## Background
[200 words. Key terms. Context.]

## Key Findings

### [Theme 1]
[Grouped findings. Inline citations. Note source strength.]

### [Theme 2]
[3-5 themes total]

## Conflicting Information
[Both sides. Which has better sourcing.]

## Gaps & Limitations
[What's unknown. What needs more research.]

## Source Assessment
- **High confidence:** [claims with 3+ quality sources]
- **Medium confidence:** [claims with 1-2 sources]
- **Low confidence:** [single source or Tier 3 only]

## Sources

### Primary
[Tier 1 sources with URLs]

### Secondary
[Tier 2-3 sources with URLs]

---
*Sources: {sourcesGathered} | Searches: {totalSearches} | Teammates: {teammateCompletions} | Iterations: {iteration} | Duration: {duration} | Date: {date}*
```

Set `phase="DONE"`.

Update `task-loop.json`:
```json
{
  "active": true,
  "complete": true,
  "completionMessage": "Research complete: \"{topic}\"\n\nResources used:\n  Searches: {totalSearches}\n  Sources: {sourcesGathered}/{targetSources}\n  Teammates: {teammateCompletions}\n  Iterations: {iteration}\n\nReport: research/{slug}/report.md"
}
```

The task loop hook will display this message when the session exits.
</phase>

</steps>

<error_handling>
| Error | Action |
|-------|--------|
| Malformed JSON | Retry once, then mark low confidence |
| Scrape fails | Continue with other URLs |
| Rate limit | Wait 60s, reduce batch to 2 |
| No results | Mark low confidence, rephrase as follow-up |
| Preferred fetch tool unavailable | Fall back to built-in `WebFetch` |
| `codex` MCP unavailable, empty, or error-text response | Teammate returns Claude-only findings, research continues |
</error_handling>

<limits>
| Resource | Guide | Notes |
|----------|-------|-------|
| Target sources | ~30 | Breadth signal, not a gate (set in INIT, ~20-40 by complexity) |
| Max iterations | 5 | Hard backstop — forces a futility exit so the loop always terminates |
| Teammates per batch | 8 | Parallelism cap — one teammate per pending question |

Searches per teammate, URLs scraped, and follow-ups per iteration are the agent's discretion. Completion is governed by the **sufficiency gate** (EVALUATE), bounded by `maxIterations`.
</limits>

<red_flags>
Stop on **sufficiency, not a number**: synthesize once every question is answered at `medium`+ confidence with gaps documented — don't pad sources to hit a target, and don't quit while questions are still thin (unless `maxIterations` is reached). Weight Tier 1 sources higher. If stuck, narrow scope or generate sharper follow-ups.
</red_flags>
