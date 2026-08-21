#!/usr/bin/env bash

# Post-Plan-Approval Hook (PostToolUse: ExitPlanMode)
# Fires when a plan is approved. Injects context steering the model to run
# the amux plan-review skill on the approved plan before implementing.

set -euo pipefail

cat > /dev/null  # consume hook input; the nudge is unconditional

cat <<'EOF'
{
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": "Plan approved. Before implementing a non-trivial plan, stress-test it: persist the plan to plans/{slug}/prd.md (slug: lowercase-hyphenated feature name) if it is not already there, then invoke the amux plan-review skill on it. Empirical findings get fact-checked, verified mechanical fixes are applied, and scope questions come back to the user before any code is written. Skip only for trivial single-file changes."
    }
}
EOF
exit 0
