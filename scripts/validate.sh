#!/usr/bin/env bash
# Structural validation for the amux plugin. Run before committing; CI runs it on every push.
#
# Checks: JSON manifests parse and agree on version; CHANGELOG has the version;
# skill frontmatter names match their directories; agent frontmatter names match
# filenames; every amux:<name> reference resolves to an agent or skill; every
# agent's JSON "agent" identifier equals its filename and is unique; agents declare
# no tools: list; agents use model: inherit except the judge roles allowed to pin
# fable; no stale references to removed components; README counts match disk.

set -uo pipefail
cd "$(dirname "$0")/.."

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
done

# --- Agents -------------------------------------------------------------------
seen_ids=" "
for a in agents/*.md; do
    base=$(basename "$a" .md)
    name=$(awk 'NR>1 && /^---/{exit} /^name:/{sub(/^name:[ ]*/,""); print; exit}' "$a")
    [[ "$name" == "$base" ]] && ok "agent $base name matches file" \
        || err "$a: frontmatter name '$name' != filename '$base'"

    id=$(grep -oE '"agent": *"[^"]+"' "$a" | head -1 | sed -E 's/.*"agent": *"([^"]+)"/\1/')
    [[ -n "$id" ]] || { err "$a: no \"agent\" identifier in its output JSON"; continue; }
    [[ "$id" == "$base" ]] || err "$a: output identifier '$id' != filename '$base'"
    [[ "$seen_ids" == *" $id "* ]] && err "duplicate agent identifier '$id' in $a"
    seen_ids+="$id "
done

# --- Tool policy ----------------------------------------------------------------
# Agents declare no tools: list, so they inherit the environment's research MCPs.
# A whitelist silently hides every installed docs/search/codebase tool from them.
for a in agents/*.md; do
    if awk 'NR>1 && /^---/{exit} /^tools:/{found=1} END{exit !found}' "$a"; then
        err "$a: declares a tools: list; agents inherit all tools (see CLAUDE.md)"
    else
        ok "agent $(basename "$a" .md) inherits tools"
    fi
done

# --- Model policy ---------------------------------------------------------------
# Agents inherit the user's default model. Only judge roles whose wrong verdict
# would silently drop a finding or misdirect the build may pin fable.
FABLE_ROLES="verify premortem build-plan"
for a in agents/*.md; do
    base=$(basename "$a" .md)
    model=$(awk 'NR>1 && /^---/{exit} /^model:/{sub(/^model:[ ]*/,""); print; exit}' "$a")
    if [[ " $FABLE_ROLES " == *" $base "* ]]; then
        [[ "$model" == "fable" || "$model" == "inherit" ]] && ok "agent $base model '$model' (fable allowed)" \
            || err "$a: model '$model' — judge roles pin fable or inherit"
    else
        [[ "$model" == "inherit" ]] && ok "agent $base model inherit" \
            || err "$a: model '$model' — only judge roles ($FABLE_ROLES) may pin a model; use inherit"
    fi
done

# --- References ---------------------------------------------------------------
while IFS= read -r ref; do
    name=${ref#amux:}
    [[ -f "agents/$name.md" || -d "skills/$name" ]] && ok "reference $ref resolves" \
        || err "reference '$ref' matches no agent or skill"
done < <(grep -rhoE 'amux:[a-z0-9-]+' skills agents README.md 2>/dev/null | sort -u)

stale='mcp__plugin_amux_codex|codex MCP|task-loop|amux:(spike|plan-review|review-plan|review-change)|/amux:(spike|plan-review)|(spike|plan-review)\` skill|(spike|plan-review) skill|dual-engine\.md'
if grep -rnE "$stale" skills agents README.md CLAUDE.md >/dev/null 2>&1; then
    err "stale references to removed components:"; grep -rnE "$stale" skills agents README.md CLAUDE.md >&2
else
    ok "no stale references to removed components"
fi

# --- README counts -------------------------------------------------------------
count_files() { find "$1" -maxdepth "${3:-1}" -name "$2" | wc -l | tr -d ' '; }
agents_n=$(count_files agents '*.md'); skills_n=$(count_files skills SKILL.md 2)
for pair in "Agents:$agents_n" "Skills:$skills_n"; do
    label=${pair%%:*}; n=${pair##*:}
    grep -q "### $label ($n)" README.md && ok "README says $label ($n)" \
        || err "README heading '### $label (N)' does not say $n"
done

if [[ $fail -ne 0 ]]; then echo "validation FAILED" >&2; exit 1; fi
echo "validation passed"
