#!/usr/bin/env bash

# Review Gate Hook (Stop)
# Blocks ending the turn when code files have changed but no fresh code review
# exists. Fresh = reviews/{branch}.md (written by the code-review-pipeline
# skill's persist step) is newer than every changed code file.
#
# One nudge only: if this stop is already a continuation from a stop-hook
# block (stop_hook_active), it allows exit instead of looping forever.
#
# Skips: non-git dirs, no jq, doc/config-only diffs, diffs under 5 changed
# code lines. Opt out per-session: export AMUX_SKIP_REVIEW_GATE=1
#
# No `set -e`: the gate must fail open, and every guard handles its own errors.

set -u

command -v jq >/dev/null 2>&1 || exit 0
if [[ "${AMUX_SKIP_REVIEW_GATE:-0}" == "1" ]]; then exit 0; fi

HOOK_INPUT=$(cat)

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$repo_root" || exit 0

CODE_EXT='\.(ts|tsx|js|jsx|mjs|cjs|py|rs|go|rb|java|kt|swift|c|cc|cpp|h|hpp|cs|php|svelte|vue)$'

# Changed code files: tracked modifications vs HEAD plus untracked (gitignore-respecting)
changed_files=$(
    { git diff HEAD --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } \
    | grep -E "$CODE_EXT" | sort -u
)
if [[ -z "$changed_files" ]]; then exit 0; fi

# Total changed code lines; under 5 is below the skill's own "trivial fix" bar
changed_lines=$(git diff HEAD --numstat 2>/dev/null | grep -E "$CODE_EXT" \
    | awk '{ if ($1 != "-") s += $1; if ($2 != "-") s += $2 } END { print s + 0 }')
changed_lines=${changed_lines:-0}
while IFS= read -r f; do
    if [[ -f "$f" ]] && ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        untracked_lines=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
        changed_lines=$((changed_lines + ${untracked_lines:-0}))
    fi
done <<< "$changed_files"
if [[ "$changed_lines" -lt 5 ]]; then exit 0; fi

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
review_file="reviews/${branch}.md"

review_fresh="false"
if [[ -f "$review_file" ]]; then
    review_fresh="true"
    review_mtime=$(mtime "$review_file")
    while IFS= read -r f; do
        if [[ -f "$f" && $(mtime "$f") -gt "$review_mtime" ]]; then
            review_fresh="false"
            break
        fi
    done <<< "$changed_files"
fi
if [[ "$review_fresh" == "true" ]]; then exit 0; fi

file_count=$(printf '%s\n' "$changed_files" | wc -l | tr -d ' ')

# Already continuing from a stop-hook block — warn but don't loop
stop_active=$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [[ "$stop_active" == "true" ]]; then
    cat <<EOF
{
    "systemMessage": "amux review gate: still no fresh review for ${file_count} changed code file(s) — allowing exit (one nudge per turn)"
}
EOF
    exit 0
fi

cat <<EOF
{
    "decision": "block",
    "reason": "Code changed this session without a fresh code review (${file_count} code file(s), ~${changed_lines} lines vs HEAD). Run the amux code-review-pipeline skill now — it reviews the diff, adversarially verifies findings, and writes ${review_file}, which satisfies this gate.",
    "systemMessage": "amux review gate: ${file_count} code file(s) changed without a fresh review — requesting code-review-pipeline"
}
EOF
exit 0
