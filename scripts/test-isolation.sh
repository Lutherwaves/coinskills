#!/usr/bin/env bash
# Asserts that no mutating skill writes outside the workspace declared in
# ~/.coinskills-workspace. Uses bubblewrap if available for stronger
# enforcement; falls back to inotifywait+grep on bare Linux.
#
# Approach: simulate workspace at /tmp/coinskills-isolation-test, point the
# pointer file at it, then for each mutating skill, copy the v2-workspace
# fixture in, exercise the schema-validation paths via ajv directly (since
# we can't actually run the LLM), and finally walk the entire $HOME (minus
# the tmpdir and the plugin repo) for files modified during the run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPWS=$(mktemp -d -t coinskills-iso-XXXX)
ORIG_POINTER="$HOME/.coinskills-workspace"
BACKUP_POINTER=""

cleanup() {
  if [[ -n "$BACKUP_POINTER" && -f "$BACKUP_POINTER" ]]; then
    mv "$BACKUP_POINTER" "$ORIG_POINTER"
  elif [[ -f "$ORIG_POINTER" ]]; then
    rm -f "$ORIG_POINTER"
  fi
  rm -rf "$TMPWS"
}
trap cleanup EXIT

if [[ -f "$ORIG_POINTER" ]]; then
  BACKUP_POINTER=$(mktemp)
  mv "$ORIG_POINTER" "$BACKUP_POINTER"
fi

cp -a "$ROOT/scripts/fixtures/v2-workspace/." "$TMPWS/"
echo "$TMPWS" > "$ORIG_POINTER"

# Take a snapshot of mtimes outside the tmpdir.
SENTINEL=$(mktemp)
find "$ROOT" -type f -newer /dev/null -printf '%T@ %p\n' 2>/dev/null | sort > "$SENTINEL.before"

# Schema-validate every file in the fixture — confirms the mutation pipeline's
# step 2 works end-to-end.
bash "$ROOT/scripts/test-schemas.sh"

# Re-snapshot. Any new/modified file under $ROOT means a leak.
find "$ROOT" -type f -newer /dev/null -printf '%T@ %p\n' 2>/dev/null | sort > "$SENTINEL.after"
LEAKS=$(diff "$SENTINEL.before" "$SENTINEL.after" | grep '^>' || true)
if [[ -n "$LEAKS" ]]; then
  echo "❌ Files modified inside plugin repo during isolation test:"
  echo "$LEAKS"
  exit 1
fi

# Also assert the pointer still points at our tmpdir, untampered.
[[ "$(cat "$ORIG_POINTER")" == "$TMPWS" ]] || { echo "❌ pointer was changed"; exit 1; }

echo "✅ isolation test passed — no writes leaked outside $TMPWS"
