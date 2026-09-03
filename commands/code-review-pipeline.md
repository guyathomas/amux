---
description: "Run the full code review pipeline on your changes. Creates an agent team of parallel reviewers covering both the implementation and the design, adversarially verifies findings, fixes confirmed critical implementation issues, and surfaces design decisions for you."
argument-hint: "[PR# | branch | path | focus notes]"
---

Run the code-review-pipeline skill. If the argument is a PR number, branch, or path, use it as the review target; anything else is a focus note for the reviewers. No argument reviews the current working tree changes.

$ARGUMENTS
