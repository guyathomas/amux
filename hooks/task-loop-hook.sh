#!/usr/bin/env bash

# Generic Task Loop Hook
# Prevents session exit when any active task-loop.json exists with complete=false.
# Skills write their own task-loop.json to opt into the loop. The hook is agnostic
# to what the skill does — it just reads the contract fields.
#
# Contract (task-loop.json):
#   {
#     "active": true,
#     "complete": false,
#     "continuationPrompt": "Keep going...",
#     "statusMessage": "Progress: 50%",        // shown when blocked
#     "completionMessage": "Done! Results in ..." // shown on completion
#   }
#
# Skills create task-loop.json when they start and set complete=true when finished.
# The hook blocks exit while active && !complete, re-injecting continuationPrompt.
# Opt out per-session: export AMUX_SKIP_TASK_LOOP=1

set -euo pipefail

# Fail-open if jq is not available
command -v jq >/dev/null 2>&1 || { exit 0; }

# Escape hatch: export AMUX_SKIP_TASK_LOOP=1 to let the session end even while a
# task-loop.json is active (e.g. a loop that cannot reach completion).
if [[ "${AMUX_SKIP_TASK_LOOP:-0}" == "1" ]]; then exit 0; fi

# Read hook input from stdin
HOOK_INPUT=$(cat)

# JSON string escaping
escape_for_json() {
    local input="$1"
    local output=""
    local i char
    for (( i=0; i<${#input}; i++ )); do
        char="${input:$i:1}"
        case "$char" in
            $'\\') output+='\\' ;;
            '"') output+='\"' ;;
            $'\n') output+='\n' ;;
            $'\r') output+='\r' ;;
            $'\t') output+='\t' ;;
            *) output+="$char" ;;
        esac
    done
    printf '%s' "$output"
}

# Find any active task-loop.json in the working directory tree.
# Returns the first active file (complete or not). Caller decides action.
find_active_task_loop() {
    while IFS= read -r task_file; do
        if [[ -f "$task_file" ]]; then
            local active
            active=$(jq -r 'if .active == true then "true" else "false" end' "$task_file" 2>/dev/null || echo "false")

            if [[ "$active" == "true" ]]; then
                echo "$task_file"
                return 0
            fi
        fi
    done < <(find . -maxdepth 4 -name "task-loop.json" -type f 2>/dev/null)

    return 1
}

main() {
    local task_file
    if ! task_file=$(find_active_task_loop); then
        # No active task loop — allow exit
        exit 0
    fi

    # Read the contract fields
    local complete continuation_prompt status_message completion_message
    complete=$(jq -r 'if .complete == true then "true" else "false" end' "$task_file" 2>/dev/null || echo "false")
    continuation_prompt=$(jq -r '.continuationPrompt // "Continue the current task. Check state files for progress."' "$task_file" 2>/dev/null)
    status_message=$(jq -r '.statusMessage // "Task in progress"' "$task_file" 2>/dev/null)
    completion_message=$(jq -r '.completionMessage // "Task complete."' "$task_file" 2>/dev/null)

    if [[ "$complete" == "true" ]]; then
        # Task is done — show completion message and allow exit
        local escaped_msg
        escaped_msg=$(escape_for_json "$completion_message")
        cat <<EOF
{
    "systemMessage": "${escaped_msg}"
}
EOF
        exit 0
    fi

    # Task not complete — block exit
    local escaped_status escaped_prompt
    escaped_status=$(escape_for_json "$status_message")
    escaped_prompt=$(escape_for_json "$continuation_prompt")

    cat <<EOF
{
    "decision": "block",
    "reason": "${escaped_prompt}",
    "systemMessage": "${escaped_status}"
}
EOF

    exit 0
}

main "$@"
