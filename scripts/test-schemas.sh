#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/scripts/fixtures/v2-workspace"
SCHEMAS="$ROOT/schemas"
FAIL=0

AJV="npx --yes ajv-cli"

validate() {
  local schema="$1"
  local data="$2"
  if ! $AJV validate -s "$schema" -d "$data" --strict=false >/dev/null 2>&1; then
    echo "❌ $data does not validate against $schema"
    $AJV validate -s "$schema" -d "$data" --strict=false || true
    FAIL=1
  else
    echo "✅ $data ↔ $(basename "$schema")"
  fi
}

validate "$SCHEMAS/account.schema.json"      "$FIX/accounts.json"
validate "$SCHEMAS/profile.schema.json"      "$FIX/profile.json"
validate "$SCHEMAS/recurring.schema.json"    "$FIX/modules/personal/recurring.json"
validate "$SCHEMAS/income.schema.json"       "$FIX/modules/personal/income.json"
validate "$SCHEMAS/holding.schema.json"      "$FIX/modules/investments/holdings.json"
validate "$SCHEMAS/snapshot.schema.json"     "$FIX/snapshots/latest.json"

NEG="$ROOT/scripts/fixtures/invalid"
if $AJV validate -s "$SCHEMAS/account.schema.json" -d "$NEG/account-bad-type.json" --strict=false >/dev/null 2>&1; then
  echo "❌ negative: account-bad-type.json should have failed validation"
  FAIL=1
else
  echo "✅ negative case rejected"
fi

[[ $FAIL -eq 0 ]] && echo "✅ schemas validation passed" || exit 1
