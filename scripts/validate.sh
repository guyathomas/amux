#!/usr/bin/env bash
# Structural validation for the amux plugin. Run before committing; CI runs it on every push.
#
# Checks: JSON manifests parse and agree on version; CHANGELOG has the version;
# skill frontmatter names match their directories; every skill stays under the
# word limit; every amux:<name> reference resolves to a skill; no stale
# references to removed components; the README skill count matches disk.

set -uo pipefail
cd "$(dirname "$0")/.."

MAX_SKILL_WORDS=900

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }
ok()  { echo "ok:   $*"; }

for tool in jq python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "validate.sh needs $tool" >&2; exit 2; }
done

# --- JSON manifests --------------------------------------------------------
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null && ok "$f parses" || err "$f is not valid JSON"
done

plugin_version=$(jq -r '.version' .claude-plugin/plugin.json)
market_version=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)
[[ "$plugin_version" == "$market_version" ]] && ok "version $plugin_version consistent" \
    || err "plugin.json version ($plugin_version) != marketplace.json version ($market_version)"

grep -q "^## \[$plugin_version\]" CHANGELOG.md && ok "CHANGELOG has $plugin_version" \
    || err "CHANGELOG.md has no entry for $plugin_version"

# --- Skills -------------------------------------------------------------------
for d in skills/*/; do
    base=$(basename "$d")
    name=$(awk 'NR>1 && /^---/{exit} /^name:/{sub(/^name:[ ]*/,""); print; exit}' "$d/SKILL.md")
    [[ "$name" == "$base" ]] && ok "skill $base name matches directory" \
        || err "skills/$base/SKILL.md: frontmatter name '$name' != directory '$base'"

    words=$(wc -w < "$d/SKILL.md" | tr -d ' ')
    [[ "$words" -le "$MAX_SKILL_WORDS" ]] && ok "skill $base is $words words" \
        || err "skills/$base/SKILL.md: $words words, limit $MAX_SKILL_WORDS (state the contract, not the procedure)"
done

[[ ! -d agents ]] && ok "no agents directory" \
    || err "agents/ exists; skills start subagents with an inline brief (see CLAUDE.md)"

# --- References ---------------------------------------------------------------
while IFS= read -r ref; do
    name=${ref#amux:}
    [[ -d "skills/$name" ]] && ok "reference $ref resolves" \
        || err "reference '$ref' matches no skill"
done < <(grep -rhoE 'amux:[a-z0-9-]+' skills README.md CLAUDE.md 2>/dev/null | sort -u)

stale='plan\.json|toolsDegraded|code-review-pipeline|build-plan|amux:(planning|build|research|review|verify|premortem)|claude-opus-5-5'
if grep -rnE "$stale" skills README.md CLAUDE.md >/dev/null 2>&1; then
    err "stale references to removed components:"; grep -rnE "$stale" skills README.md CLAUDE.md >&2
else
    ok "no stale references to removed components"
fi

# --- README count --------------------------------------------------------------
skills_n=$(find skills -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
grep -q "### Skills ($skills_n)" README.md && ok "README says Skills ($skills_n)" \
    || err "README heading '### Skills (N)' does not say $skills_n"

if [[ $fail -ne 0 ]]; then echo "validation FAILED" >&2; exit 1; fi
echo "validation passed"
