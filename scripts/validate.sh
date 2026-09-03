#!/usr/bin/env bash
# Structural validation for the amux plugin. Run before committing; CI runs it on every push.
#
# Checks: JSON manifests parse and agree on version; CHANGELOG has the version;
# hook scripts referenced by hooks.json exist, are executable, and pass bash -n;
# agent frontmatter names match filenames; every amux:<name> reference in skills,
# commands, and README resolves to an agent or skill; command agent: fields resolve;
# every agent's JSON "agent" identifier equals its filename and is unique;
# agents use model: inherit except the judge roles allowed to pin fable;
# the Codex model named anywhere matches docs/dual-engine.md; README agent/skill/
# command counts match the files on disk.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }
ok()  { echo "ok:   $*"; }

for tool in jq python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "validate.sh needs $tool" >&2; exit 2; }
done

# --- JSON manifests --------------------------------------------------------
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null && ok "$f parses" || err "$f is not valid JSON"
done

plugin_version=$(jq -r '.version' .claude-plugin/plugin.json)
market_version=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)
[[ "$plugin_version" == "$market_version" ]] && ok "version $plugin_version consistent" \
    || err "plugin.json version ($plugin_version) != marketplace.json version ($market_version)"

grep -q "^## \[$plugin_version\]" CHANGELOG.md && ok "CHANGELOG has $plugin_version" \
    || err "CHANGELOG.md has no entry for $plugin_version"

# --- Hooks -------------------------------------------------------------------
while IFS= read -r cmd; do
    script=${cmd#\$\{CLAUDE_PLUGIN_ROOT\}/}
    if [[ ! -f "$script" ]]; then err "hooks.json references missing script $script"; continue; fi
    [[ -x "$script" ]] || err "$script is not executable"
    bash -n "$script" 2>/dev/null && ok "$script syntax" || err "$script fails bash -n"
done < <(jq -r '.. | .command? // empty' hooks/hooks.json)

for script in hooks/*.sh; do
    grep -q "hooks/$(basename "$script")" hooks/hooks.json || err "$script exists but hooks.json never runs it"
done

# --- Agents -------------------------------------------------------------------
declare -A seen_ids
for a in agents/*.md; do
    base=$(basename "$a" .md)
    name=$(awk 'NR>1 && /^---/{exit} /^name:/{sub(/^name:[ ]*/,""); print; exit}' "$a")
    [[ "$name" == "$base" ]] && ok "agent $base name matches file" \
        || err "$a: frontmatter name '$name' != filename '$base'"

    id=$(grep -oE '"agent": *"[^"]+"' "$a" | head -1 | sed -E 's/.*"agent": *"([^"]+)"/\1/')
    [[ -n "$id" ]] || { err "$a: no \"agent\" identifier in its output JSON"; continue; }
    [[ "$id" == "$base" ]] || err "$a: output identifier '$id' != filename '$base'"
    [[ -n "${seen_ids[$id]:-}" ]] && err "duplicate agent identifier '$id' in $a and ${seen_ids[$id]}"
    seen_ids[$id]=$a
done

# --- Model policy ---------------------------------------------------------------
# Agents inherit the user's default model. Only judge roles whose wrong verdict
# would silently drop a finding may pin fable; everything else must be inherit.
FABLE_ROLES="review-design verify-finding verify-design-finding verify-plan-finding premortem build-plan"
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
done < <(grep -rhoE 'amux:[a-z0-9-]+' skills commands README.md docs 2>/dev/null | sort -u)

if grep -rnE '\bcore:[a-z-]+' skills commands agents README.md >/dev/null 2>&1; then
    err "stale 'core:' agent references remain:"; grep -rnE '\bcore:[a-z-]+' skills commands agents README.md >&2
fi

for c in commands/*.md; do
    ag=$(awk 'NR>1 && /^---/{exit} /^agent:/{sub(/^agent:[ ]*/,""); print; exit}' "$c")
    [[ -z "$ag" ]] && continue
    [[ -f "agents/${ag#amux:}.md" ]] && ok "$c agent '$ag' resolves" || err "$c: agent '$ag' does not exist"
done

# --- Codex model single source -------------------------------------------------
canon=$(grep -oE 'gpt-[a-z0-9.-]+' docs/dual-engine.md | head -1)
[[ -n "$canon" ]] || err "docs/dual-engine.md names no Codex model"
while IFS= read -r line; do
    model=$(grep -oE 'gpt-[a-z0-9.-]+' <<<"$line" | head -1)
    [[ "$model" == "$canon" ]] || err "Codex model '$model' != canonical '$canon' at $line"
done < <(grep -rnoE 'gpt-[a-z0-9.-]+' skills agents | grep -v "$canon" || true)
ok "Codex model '$canon' consistent"

# --- README counts -------------------------------------------------------------
count_files() { find "$1" -maxdepth "${3:-1}" -name "$2" | wc -l | tr -d ' '; }
agents_n=$(count_files agents '*.md'); skills_n=$(count_files skills SKILL.md 2); commands_n=$(count_files commands '*.md')
for pair in "Agents:$agents_n" "Skills:$skills_n" "Commands:$commands_n"; do
    label=${pair%%:*}; n=${pair##*:}
    grep -q "### $label ($n)" README.md && ok "README says $label ($n)" \
        || err "README heading '### $label (N)' does not say $n"
done

if [[ $fail -ne 0 ]]; then echo "validation FAILED" >&2; exit 1; fi
echo "validation passed"
