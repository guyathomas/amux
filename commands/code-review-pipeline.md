---
description: "Review your changes: one reviewer covers correctness, security, structure, tests, docs, and design; an independent verifier attacks the critical and high findings; confirmed implementation issues are fixed and design decisions come to you. Add 'thorough' to verify medium findings too."
argument-hint: "[PR# | branch | path | thorough | focus notes]"
---

Run the code-review-pipeline skill. If the argument is a PR number, branch, or path, use it as the review target; `thorough` widens verification; anything else is a focus note for the reviewer. No argument reviews the current working tree changes.

$ARGUMENTS
