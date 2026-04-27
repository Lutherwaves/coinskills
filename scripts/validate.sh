#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

require_frontmatter_field() {
  local file="$1"
  local field="$2"
  if ! awk '/^---$/{c++} c==1 && /^'"$field"': /' "$file" | grep -q .; then
    echo "❌ $file — missing frontmatter field: $field"
    FAIL=1
  fi
}

# Validate plugin.json
if ! jq -e '.name == "coinskills" and .version' "$ROOT/.claude-plugin/plugin.json" > /dev/null; then
  echo "❌ .claude-plugin/plugin.json — missing name or version"
  FAIL=1
fi

# Validate every SKILL.md
EXPECTED_SKILLS=(init start goals plan afford log analyze review)
for skill in "${EXPECTED_SKILLS[@]}"; do
  file="$ROOT/skills/$skill/SKILL.md"
  if [[ ! -f "$file" ]]; then
    echo "❌ Missing skill: $skill"
    FAIL=1
    continue
  fi
  require_frontmatter_field "$file" "name"
  require_frontmatter_field "$file" "description"

  # Verify name field matches directory
  actual_name=$(awk '/^---$/{c++} c==1 && /^name: /{sub(/^name: /,""); print; exit}' "$file")
  if [[ "$actual_name" != "$skill" ]]; then
    echo "❌ $file — name field is '$actual_name', expected '$skill'"
    FAIL=1
  fi
done

if [[ $FAIL -eq 0 ]]; then
  echo "✅ coinskills validation passed"
else
  exit 1
fi
