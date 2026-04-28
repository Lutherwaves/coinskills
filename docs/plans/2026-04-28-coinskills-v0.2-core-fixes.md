# coinskills v0.2 Core Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.2 of coinskills with a state foundation (changes.jsonl + snapshots cache + JSON schemas), goal model v2 (structured prerequisites + funding_mode + status enum), and afford v2 (goal-detection heuristic + prereq auto-eval + recognition-over-recall).

**Architecture:** This is a Claude Code plugin — implementation is markdown skill files (`skills/<name>/SKILL.md`) that instruct the LLM, JSON schemas the skills validate against, and bash scripts in `scripts/` that smoke-test against fixture workspaces. There is no compiled language and no test runner — "tests" are bash scripts asserting exit codes and grep'd output against fixtures. Each task ships a fixture or assertion alongside its skill change so behavior is verifiable without a live workspace.

**Tech Stack:** Markdown (CommonMark, YAML frontmatter), JSON Schema draft-07, bash, jq, ajv-cli (or python jsonschema as fallback) for schema validation in tests, gh/git for repo operations.

**Spec:** `docs/specs/2026-04-28-coinskills-v0.2-core-fixes-design.md`

---

## File map

**New files (plugin):**
- `schemas/account.schema.json`
- `schemas/goal.schema.json`
- `schemas/plan.schema.json`
- `schemas/profile.schema.json`
- `schemas/recurring.schema.json`
- `schemas/income.schema.json`
- `schemas/holding.schema.json`
- `schemas/change-event.schema.json`
- `schemas/snapshot.schema.json`
- `skills/edit/SKILL.md`
- `skills/migrate/SKILL.md`
- `skills/_shared/path-guard.md` — referenced from every mutating skill
- `skills/_shared/mutation-pipeline.md` — referenced from every mutating skill
- `skills/_shared/snapshot-compute.md` — referenced from every read skill
- `scripts/test-isolation.sh` — CI smoke test
- `scripts/test-schemas.sh` — schema fixture tests
- `scripts/fixtures/v1-workspace/` — minimal v0.1 workspace for migration tests
- `scripts/fixtures/v2-workspace/` — minimal v0.2 workspace for afford/edit tests

**Modified files (plugin):**
- `.gitignore` — defense-in-depth patterns
- `.gitattributes` — `merge=union` for changes.jsonl in user workspace (template)
- `scripts/validate.sh` — add edit + migrate to expected skills
- `skills/init/SKILL.md` — write v2 frontmatter, seed `changes.jsonl` and `snapshots/`
- `skills/goals/SKILL.md` — write v2 goal frontmatter (funding_mode, status enum, prerequisites)
- `skills/plan/SKILL.md` — read goal funding_mode
- `skills/start/SKILL.md` — schema_version gate, snapshot reuse, recognition-over-recall, blocked goals section
- `skills/afford/SKILL.md` — Step 0 goal-detection, Step 4.5 prereq eval, snapshot reuse, recognition-over-recall
- `skills/log/SKILL.md` — mutation pipeline (changes.jsonl + snapshot stale)
- `skills/analyze/SKILL.md` — schema_version gate, snapshot reuse, recognition-over-recall
- `skills/review/SKILL.md` — schema_version gate
- `README.md` — v0.2 features + migration note
- `CHANGELOG.md` — v0.2 entry
- `.claude-plugin/plugin.json` — bump version to 0.2.0

---

## Task 1: JSON schemas

**Files:**
- Create: `schemas/account.schema.json`
- Create: `schemas/goal.schema.json`
- Create: `schemas/plan.schema.json`
- Create: `schemas/profile.schema.json`
- Create: `schemas/recurring.schema.json`
- Create: `schemas/income.schema.json`
- Create: `schemas/holding.schema.json`
- Create: `schemas/change-event.schema.json`
- Create: `schemas/snapshot.schema.json`
- Test: `scripts/test-schemas.sh`
- Test: `scripts/fixtures/v2-workspace/accounts.json` (and other fixtures)

- [ ] **Step 1: Write `scripts/test-schemas.sh` (failing test)**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/scripts/fixtures/v2-workspace"
SCHEMAS="$ROOT/schemas"
FAIL=0

if ! command -v ajv >/dev/null 2>&1; then
  echo "ajv-cli not installed — run: npm i -g ajv-cli ajv-formats"
  exit 2
fi

validate() {
  local schema="$1"
  local data="$2"
  if ! ajv validate -s "$schema" -d "$data" --strict=false >/dev/null 2>&1; then
    echo "❌ $data does not validate against $schema"
    ajv validate -s "$schema" -d "$data" --strict=false || true
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

# Negative cases — should fail validation
NEG="$ROOT/scripts/fixtures/invalid"
if ajv validate -s "$SCHEMAS/account.schema.json" -d "$NEG/account-bad-type.json" --strict=false >/dev/null 2>&1; then
  echo "❌ negative: account-bad-type.json should have failed validation"
  FAIL=1
fi

[[ $FAIL -eq 0 ]] && echo "✅ schemas validation passed" || exit 1
```

Make it executable: `chmod +x scripts/test-schemas.sh`

- [ ] **Step 2: Run test to verify it fails (no schemas yet)**

```bash
bash scripts/test-schemas.sh
```

Expected: FAIL with "ajv: schema not found" or missing-file errors for `schemas/*.json`.

- [ ] **Step 3: Write `schemas/account.schema.json`**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "coinskills:account",
  "title": "Account",
  "description": "Single account entry in accounts.json. accounts.json is an array of these.",
  "type": "object",
  "required": ["id", "type", "name", "currency", "module"],
  "properties": {
    "id": {"type": "string", "pattern": "^[a-z0-9][a-z0-9-]*$"},
    "type": {"enum": ["bank", "savings", "credit_card", "e_money", "broker", "crypto_wallet", "loan", "mortgage", "other"]},
    "name": {"type": "string", "minLength": 1},
    "currency": {"type": "string", "pattern": "^[A-Z]{3}$"},
    "balance": {"type": "number"},
    "limit": {"type": "number"},
    "apr": {"type": "number", "minimum": 0, "maximum": 1},
    "billing_cycle_day": {"type": "integer", "minimum": 1, "maximum": 31},
    "rewards": {"type": "string"},
    "monthly_payment": {"type": "number", "minimum": 0},
    "module": {"enum": ["personal", "investments", "business"]},
    "_estimated": {"type": "array", "items": {"type": "string"}, "uniqueItems": true}
  },
  "additionalProperties": false
}
```

- [ ] **Step 4: Write `schemas/goal.schema.json`**

Goal files are markdown with YAML frontmatter. The schema validates the frontmatter object only; body is freeform. Skills are responsible for parsing frontmatter out before validating.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "coinskills:goal",
  "title": "Goal Frontmatter",
  "type": "object",
  "required": ["id", "title", "type", "target_amount", "currency", "priority", "status", "created", "funding_mode"],
  "properties": {
    "id": {"type": "string", "pattern": "^[a-z0-9][a-z0-9-]*$", "maxLength": 30},
    "title": {"type": "string", "minLength": 1},
    "type": {"enum": ["savings", "debt-payoff", "investment", "retirement", "purchase", "custom"]},
    "target_amount": {"type": "number", "minimum": 0},
    "currency": {"type": "string", "pattern": "^[A-Z]{3}$"},
    "deadline": {"oneOf": [{"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"}, {"const": "none"}]},
    "priority": {"type": "integer", "minimum": 1},
    "status": {"enum": ["active", "blocked", "paused", "complete", "retired"]},
    "linked_accounts": {"type": "array", "items": {"type": "string"}},
    "created": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"},
    "funding_mode": {"enum": ["monthly", "windfall-only", "hybrid"]},
    "windfall_sources": {"type": "array", "items": {"type": "string"}},
    "prerequisites": {
      "type": "array",
      "items": {
        "oneOf": [
          {"type": "object", "required": ["type", "ref"], "properties": {"type": {"const": "goal-complete"}, "ref": {"type": "string"}}, "additionalProperties": false},
          {"type": "object", "required": ["type", "ref", "op", "value", "currency"], "properties": {"type": {"const": "account-balance"}, "ref": {"type": "string"}, "op": {"enum": ["gte", "lte", "eq"]}, "value": {"type": "number"}, "currency": {"type": "string", "pattern": "^[A-Z]{3}$"}}, "additionalProperties": false},
          {"type": "object", "required": ["type", "label", "confirmed_at"], "properties": {"type": {"const": "attestation"}, "label": {"type": "string"}, "confirmed_at": {"oneOf": [{"type": "null"}, {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"}]}}, "additionalProperties": false},
          {"type": "object", "required": ["type", "ref", "months"], "properties": {"type": {"const": "time-since"}, "ref": {"type": "string"}, "months": {"type": "integer", "minimum": 1}}, "additionalProperties": false}
        ]
      }
    },
    "_estimated": {"type": "array", "items": {"type": "string"}, "uniqueItems": true}
  },
  "additionalProperties": false,
  "allOf": [
    {
      "if": {"properties": {"funding_mode": {"enum": ["windfall-only", "hybrid"]}}},
      "then": {"required": ["windfall_sources"]}
    }
  ]
}
```

- [ ] **Step 5: Write `schemas/plan.schema.json`**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "coinskills:plan",
  "title": "Plan Frontmatter",
  "type": "object",
  "required": ["goal_ids", "version", "created", "status", "monthly_contribution", "contribution_sources", "projection"],
  "properties": {
    "goal_ids": {"type": "array", "items": {"type": "string"}, "minItems": 1},
    "version": {"type": "integer", "minimum": 1},
    "created": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"},
    "status": {"enum": ["active", "blocked", "paused", "superseded"]},
    "monthly_contribution": {"type": "number", "minimum": 0},
    "contribution_sources": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["account", "amount", "frequency"],
        "properties": {
          "account": {"type": "string"},
          "amount": {"type": "number", "minimum": 0},
          "frequency": {"enum": ["monthly", "quarterly", "annual", "irregular"]}
        },
        "additionalProperties": false
      }
    },
    "projection": {"type": "string"}
  },
  "additionalProperties": false
}
```

- [ ] **Step 6: Write `schemas/profile.schema.json`**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "coinskills:profile",
  "title": "Profile Frontmatter",
  "type": "object",
  "required": ["name", "created", "schema_version", "modules", "currency", "locale", "emergency_fund_months", "preferences"],
  "properties": {
    "name": {"type": "string", "minLength": 1},
    "created": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"},
    "schema_version": {"type": "integer", "enum": [1, 2]},
    "modules": {"type": "array", "items": {"enum": ["personal", "investments", "business"]}, "minItems": 1, "uniqueItems": true},
    "currency": {"type": "string", "pattern": "^[A-Z]{3}$"},
    "locale": {"type": "string"},
    "risk_tolerance": {"enum": ["conservative", "moderate", "aggressive"]},
    "emergency_fund_months": {"type": "integer", "minimum": 1, "maximum": 24},
    "variable_spending_estimate": {"type": "number", "minimum": 0},
    "preferences": {
      "type": "object",
      "required": ["review_cadence", "decision_style"],
      "properties": {
        "review_cadence": {"enum": ["monthly", "quarterly", "yearly"]},
        "decision_style": {"enum": ["data-first", "gut-first", "balanced"]}
      },
      "additionalProperties": false
    }
  },
  "additionalProperties": false
}
```

- [ ] **Step 7: Write `schemas/recurring.schema.json`**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "coinskills:recurring",
  "type": "array",
  "items": {
    "type": "object",
    "required": ["id", "name", "amount", "currency", "category", "frequency", "due_day", "last_paid"],
    "properties": {
      "id": {"type": "string", "pattern": "^[a-z0-9][a-z0-9-]*$"},
      "name": {"type": "string", "minLength": 1},
      "amount": {"type": "number", "minimum": 0},
      "currency": {"type": "string", "pattern": "^[A-Z]{3}$"},
      "category": {"type": "string"},
      "frequency": {"enum": ["monthly", "quarterly", "annual"]},
      "due_day": {"type": "integer", "minimum": 1, "maximum": 31},
      "last_paid": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"}
    },
    "additionalProperties": false
  }
}
```

- [ ] **Step 8: Write `schemas/income.schema.json`**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "coinskills:income",
  "type": "array",
  "items": {
    "type": "object",
    "required": ["id", "type", "name", "amount", "currency", "frequency", "account_id"],
    "properties": {
      "id": {"type": "string", "pattern": "^[a-z0-9][a-z0-9-]*$"},
      "type": {"enum": ["salary", "freelance", "rental", "dividends", "other"]},
      "name": {"type": "string", "minLength": 1},
      "amount": {"type": "number", "minimum": 0},
      "currency": {"type": "string", "pattern": "^[A-Z]{3}$"},
      "frequency": {"enum": ["monthly", "quarterly", "annual", "irregular"]},
      "account_id": {"type": "string"}
    },
    "additionalProperties": false
  }
}
```

- [ ] **Step 9: Write `schemas/holding.schema.json`**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "coinskills:holding",
  "type": "array",
  "items": {
    "type": "object",
    "required": ["ticker", "shares", "avg_cost", "currency", "account", "asset_class"],
    "properties": {
      "ticker": {"type": "string", "minLength": 1},
      "shares": {"type": "number", "minimum": 0},
      "avg_cost": {"type": "number", "minimum": 0},
      "currency": {"type": "string", "pattern": "^[A-Z]{3}$"},
      "account": {"type": "string"},
      "asset_class": {"enum": ["equity", "bond", "cash", "crypto", "commodity", "other"]}
    },
    "additionalProperties": false
  }
}
```

- [ ] **Step 10: Write `schemas/change-event.schema.json`**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "coinskills:change-event",
  "title": "Change Event",
  "type": "object",
  "required": ["id", "timestamp", "skill", "op", "target", "validation"],
  "properties": {
    "id": {"type": "string", "pattern": "^chg_\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z_[a-z0-9]+$"},
    "timestamp": {"type": "string", "format": "date-time"},
    "skill": {"type": "string"},
    "op": {"enum": ["create", "update", "delete", "confirm", "undo", "migrate"]},
    "target": {"type": "string"},
    "before": {},
    "after": {},
    "validation": {"enum": ["ok", "warn"]},
    "note": {"type": "string"},
    "reverses": {"type": "string"}
  },
  "additionalProperties": false
}
```

- [ ] **Step 11: Write `schemas/snapshot.schema.json`**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "coinskills:snapshot",
  "type": "object",
  "required": ["computed_at", "stale", "last_event_id", "liquidity", "goals", "warnings"],
  "properties": {
    "computed_at": {"type": "string", "format": "date-time"},
    "stale": {"type": "boolean"},
    "last_event_id": {"oneOf": [{"type": "null"}, {"type": "string"}]},
    "liquidity": {
      "type": "object",
      "required": ["disposable", "emergency_buffer", "monthly_expenses", "monthly_capacity"],
      "properties": {
        "disposable": {"type": "number"},
        "emergency_buffer": {"type": "number"},
        "monthly_expenses": {"type": "number"},
        "monthly_capacity": {"type": "number"}
      }
    },
    "goals": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "status", "prereqs_met"],
        "properties": {
          "id": {"type": "string"},
          "status": {"type": "string"},
          "prereqs_met": {"oneOf": [{"type": "null"}, {"type": "object"}]},
          "projected_completion": {"type": "string"},
          "delay_days_from_deadline": {"type": "integer"}
        }
      }
    },
    "warnings": {"type": "array", "items": {"type": "string"}}
  }
}
```

- [ ] **Step 12: Create fixtures**

```bash
mkdir -p scripts/fixtures/v2-workspace/{goals,plans,snapshots,modules/personal/transactions,modules/investments,.backups}
mkdir -p scripts/fixtures/invalid
```

Write `scripts/fixtures/v2-workspace/profile.json` (used as fixture content; the actual profile.md is markdown, but for schema testing we extract frontmatter as JSON):

```json
{
  "name": "fixture",
  "created": "2026-04-28",
  "schema_version": 2,
  "modules": ["personal", "investments"],
  "currency": "EUR",
  "locale": "en-US",
  "risk_tolerance": "moderate",
  "emergency_fund_months": 6,
  "variable_spending_estimate": 1200,
  "preferences": {"review_cadence": "quarterly", "decision_style": "balanced"}
}
```

Write `scripts/fixtures/v2-workspace/accounts.json`:

```json
[
  {"id": "bank-main", "type": "bank", "name": "Main Bank", "currency": "EUR", "balance": 1000, "module": "personal"},
  {"id": "card-main", "type": "credit_card", "name": "Card", "currency": "EUR", "limit": 5000, "balance": -200, "apr": 0.21, "billing_cycle_day": 15, "module": "personal", "_estimated": ["apr"]}
]
```

Write `scripts/fixtures/v2-workspace/modules/personal/recurring.json`:

```json
[{"id": "rent", "name": "Rent", "amount": 800, "currency": "EUR", "category": "housing", "frequency": "monthly", "due_day": 1, "last_paid": "2026-04-01"}]
```

Write `scripts/fixtures/v2-workspace/modules/personal/income.json`:

```json
[{"id": "salary", "type": "salary", "name": "Salary", "amount": 3000, "currency": "EUR", "frequency": "monthly", "account_id": "bank-main"}]
```

Write `scripts/fixtures/v2-workspace/modules/investments/holdings.json`:

```json
[{"ticker": "IWDA", "shares": 10, "avg_cost": 100, "currency": "EUR", "account": "broker", "asset_class": "equity"}]
```

Write `scripts/fixtures/v2-workspace/snapshots/latest.json`:

```json
{
  "computed_at": "2026-04-28T10:00:00Z",
  "stale": false,
  "last_event_id": null,
  "liquidity": {"disposable": 500, "emergency_buffer": 4800, "monthly_expenses": 800, "monthly_capacity": 2200},
  "goals": [],
  "warnings": []
}
```

Write `scripts/fixtures/invalid/account-bad-type.json`:

```json
[{"id": "x", "type": "savngs", "name": "typo", "currency": "EUR", "module": "personal"}]
```

- [ ] **Step 13: Run test to verify it passes**

```bash
bash scripts/test-schemas.sh
```

Expected: each `validate` line prints `✅`, negative test rejected, final `✅ schemas validation passed`. If `ajv` is missing, install with `npm i -g ajv-cli ajv-formats` and retry.

- [ ] **Step 14: Commit**

```bash
git add schemas/ scripts/test-schemas.sh scripts/fixtures/
git commit -m "schemas: v0.2 JSON schemas + fixtures + test-schemas.sh"
```

---

## Task 2: Shared mutation pipeline + path guard markdown

These are reference snippets that every mutating skill will include verbatim near the top. They live in `skills/_shared/` and are referenced by path from each skill.

**Files:**
- Create: `skills/_shared/path-guard.md`
- Create: `skills/_shared/mutation-pipeline.md`
- Create: `skills/_shared/snapshot-compute.md`
- Modify: `scripts/validate.sh` (allow `_shared` directory under `skills/`)

- [ ] **Step 1: Write `skills/_shared/path-guard.md`**

```markdown
# Path Guard (privacy invariant)

Every mutating skill MUST run this guard before any write.

## Procedure

1. Read `~/.coinskills-workspace`. If missing, abort with: "Workspace not initialized. Run /coinskills:init first."
2. Resolve the absolute path: `WORKSPACE=$(realpath "$(cat ~/.coinskills-workspace)")`. If `realpath` fails, abort.
3. For every file you intend to write or append to, compute its `realpath`. If the result does NOT start with `$WORKSPACE/`, abort with: "Refusing to write outside workspace: <attempted path>".
4. Refuse paths containing `/.git/`, `/.backups/<other-version>/` (backups are read-only after creation), and any path resolving outside `$WORKSPACE`.

## Why

The plugin repo is public. The user workspace is private. A bug or misroute that wrote financial data into the plugin install location would leak it on the next plugin push. This guard prevents that, even if every other part of the skill is wrong.

## Negative test

`scripts/test-isolation.sh` sets `~/.coinskills-workspace` to a tmpdir, runs each mutating skill against fixtures, then asserts no files were written outside the tmpdir.
```

- [ ] **Step 2: Write `skills/_shared/mutation-pipeline.md`**

```markdown
# Mutation Pipeline

Every write to a state file (accounts.json, goals/*.md, plans/*.md, profile.md, modules/*/*.json, assets-illiquid.json) MUST go through this pipeline.

## Steps

1. **Path guard** (see `skills/_shared/path-guard.md`).
2. **Validate against schema.** Resolve schema absolute path: `<plugin-root>/schemas/<entity>.schema.json`. Run `ajv validate -s <schema> -d <staged-data> --strict=false`. If validation fails:
   - For required-field/type/enum/cross-ref errors → abort the mutation, print the error, do NOT touch any file.
   - For business-rule warnings (negative balance on savings, etc.) → continue, but record `validation: "warn"` in the change-log entry and add to snapshot warnings.
3. **Append to `changes.jsonl`.** Resolve `<workspace>/changes.jsonl`. Append exactly one JSON line with this structure (matches `schemas/change-event.schema.json`):

   ```json
   {"id":"chg_<UTC-iso>_<6-hex>","timestamp":"<UTC-iso>","skill":"<skill-name>","op":"<op>","target":"<file>#<jsonpath>","before":<old>,"after":<new>,"validation":"ok"}
   ```

   Use `python3 -c 'import secrets; print(secrets.token_hex(3))'` for the hex suffix, or any equivalent.
4. **Mutate the state file.** Use `Edit`, `Write`, or `jq` as appropriate. Atomic: write to a temp file in the same directory, then `mv` over the destination.
5. **Mark snapshot stale.** Resolve `<workspace>/snapshots/latest.json`. Update its top-level `stale: true` and `last_event_id: <new event id>`. If the file doesn't exist, create one with `stale: true` and empty `liquidity`/`goals`/`warnings`.
6. **Commit (optional).** Skills that complete a logical unit (init, migrate, an interactive edit session, a log entry) `git add` and `git commit` the changed files. Skills that are part of a longer flow defer commit to the user.

## Cross-ref validation (step 2 detail)

For accounts.json: every `linked_accounts` entry in any goal frontmatter must point to an existing account `id`. For income.json: `account_id` must exist. Cross-ref check is part of validation, not a separate step.

## Atomic write helper (bash)

```bash
write_atomic() {
  local target="$1"
  local content="$2"
  local tmp
  tmp=$(mktemp -p "$(dirname "$target")")
  printf '%s\n' "$content" > "$tmp"
  mv "$tmp" "$target"
}
```

## When NOT to run the pipeline

- Read-only operations (`start`, `analyze`, `review` in read mode) — never write changes.jsonl.
- Plan/spec doc writes within the plugin repo — never targets the workspace.
- Backups during `migrate` — write to `.backups/` directly without a change-log entry; the migrate event itself is a single change-log entry covering the whole migration.
```

- [ ] **Step 3: Write `skills/_shared/snapshot-compute.md`**

```markdown
# Snapshot Compute

Every read skill that needs aggregate state (`start`, `afford`, `analyze`, parts of `review`) MUST follow this pattern.

## Procedure

1. **Resolve workspace and snapshot path.** `SNAP=<workspace>/snapshots/latest.json`.
2. **If `SNAP` exists and `.stale == false`** → use it directly. Skip recomputation. Return its `liquidity`, `goals`, `warnings`.
3. **Otherwise (missing or stale)** → recompute:
   - `monthly_expenses`: average of last 3 months' outflows from `modules/personal/transactions/*.md`, excluding `goal-contribution`, `investment-buy`, `investment-sell`, and rows tagged `[one-off]`. If <3 months of data: fallback to `sum(recurring normalized to monthly) + profile.variable_spending_estimate` (require `variable_spending_estimate` set; if absent, prompt user to set via `/coinskills:edit profile`).
   - `liquid_cash`: sum of bank/savings/e_money balances.
   - `emergency_buffer`: `monthly_expenses * profile.emergency_fund_months`.
   - `disposable`: `liquid_cash - emergency_buffer - sum(recurring due in next 30d) - sum(card balances closing in next 30d)`.
   - `monthly_capacity`: `sum(income normalized to monthly) - sum(recurring normalized to monthly) - profile.variable_spending_estimate`.
   - For each active goal: load active plan, compute `projected_completion`, `delay_days_from_deadline`, evaluate `prerequisites` (see `prereq-evaluation` below).
   - `warnings`: list every `_estimated` field across all account/goal/plan files.
4. **Write the new snapshot.** Atomic write per the mutation pipeline's atomic helper, but DO NOT log this as a change-event (snapshots are derived, not source-of-truth). Set `stale: false`, `computed_at: <now>`, `last_event_id: <id of last event in changes.jsonl>` (or `null` if changes.jsonl is empty).

## Prereq evaluation (referenced from step 3)

For each goal's `prerequisites` array, evaluate each entry:

- `goal-complete`: lookup `goals/<ref>.md` frontmatter. Met iff `status == "complete"`.
- `account-balance`: lookup account by `ref` in accounts.json. Met iff balance satisfies `op` against `value` (and currencies match; if not, fail with a warning, do not auto-convert).
- `attestation`: met iff `confirmed_at != null` AND (months between `confirmed_at` and today) ≤ a reasonable freshness window (default 24 months — attestations expire to force reconfirmation).
- `time-since`: lookup the matching attestation (by `ref` matching its label). Met iff `months_elapsed >= months`.

Result per goal: `prereqs_met: {met: N, total: M, unmet: [{type, ref, reason}, ...]}`. Stored on the snapshot's goal entry.

## Cost

Recompute is O(N) over accounts + goals + 3 months of transactions. Acceptable for tens-to-hundreds-of-records workspaces. If a workspace ever exceeds that scale, snapshot becomes a separate concern.
```

- [ ] **Step 4: Update `scripts/validate.sh` to allow `_shared` and require new skills**

Edit `scripts/validate.sh` lines 22-39 to update `EXPECTED_SKILLS` and skip `_shared/`:

Replace:

```bash
EXPECTED_SKILLS=(init start goals plan afford log analyze review)
for skill in "${EXPECTED_SKILLS[@]}"; do
```

with:

```bash
EXPECTED_SKILLS=(init start goals plan afford log analyze review edit migrate)
for skill in "${EXPECTED_SKILLS[@]}"; do
```

(`_shared/` has no SKILL.md so the existing loop already ignores it; we don't need extra skip logic.)

- [ ] **Step 5: Run validate.sh — expected to fail because edit/migrate don't exist yet**

```bash
bash scripts/validate.sh
```

Expected: `❌ Missing skill: edit` and `❌ Missing skill: migrate`. Exits 1. This is correct — those tasks come later.

- [ ] **Step 6: Commit**

```bash
git add skills/_shared/ scripts/validate.sh
git commit -m "skills: shared path-guard, mutation-pipeline, snapshot-compute references"
```

---

## Task 3: Plugin .gitignore + .gitattributes hardening

**Files:**
- Modify: `.gitignore`
- Create: `.gitattributes`

- [ ] **Step 1: Append financial-data patterns to plugin `.gitignore`**

Read the current `.gitignore`, then append:

```
# Defense in depth: never commit financial-shaped files into the plugin repo.
# Workspaces live elsewhere — these patterns catch any accidental write that
# resolves into the plugin tree.
**/accounts.json
**/changes.jsonl
**/snapshots/
**/goals/*.md
**/plans/*.md
**/profile.md
**/assets-illiquid.json
**/modules/personal/
**/modules/investments/holdings.json
**/.backups/
*-finances*
*-coinscious*

# Allow fixtures (controlled, no real data) — these MUST exist for tests.
!scripts/fixtures/**
```

- [ ] **Step 2: Create `.gitattributes` template documentation**

The user workspace gets its own `.gitattributes` written by `init` (Task 5). The plugin doesn't need one for itself. We document the template here so init can copy it:

Create `skills/_shared/workspace-gitattributes.txt`:

```
changes.jsonl merge=union
```

This will be written verbatim into the workspace by `init` and `migrate`.

- [ ] **Step 3: Test the .gitignore**

```bash
cd /tmp && rm -rf test-coinskills && mkdir test-coinskills && cd test-coinskills
git init -q
cp -a /home/blox-master/business/lutherwaves/coinskills/.gitignore .
mkdir -p some/where && echo '[]' > some/where/accounts.json
git status --porcelain | grep -F 'accounts.json' && { echo "❌ .gitignore failed to ignore accounts.json"; exit 1; } || echo "✅ accounts.json correctly ignored"
echo '[]' > scripts/fixtures/accounts.json 2>/dev/null || mkdir -p scripts/fixtures && echo '[]' > scripts/fixtures/accounts.json
git status --porcelain | grep -F 'scripts/fixtures/accounts.json' >/dev/null && echo "✅ fixture allow-list works" || { echo "❌ fixture should be tracked"; exit 1; }
cd - && rm -rf /tmp/test-coinskills
```

Expected: both checks pass.

- [ ] **Step 4: Commit**

```bash
git add .gitignore skills/_shared/workspace-gitattributes.txt
git commit -m "gitignore: defense-in-depth patterns against financial-data leaks"
```

---

## Task 4: scripts/test-isolation.sh

A bash smoke test that asserts no skill writes outside the workspace path resolved from `~/.coinskills-workspace`.

**Files:**
- Create: `scripts/test-isolation.sh`

- [ ] **Step 1: Write the test**

```bash
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
```

`chmod +x scripts/test-isolation.sh`

- [ ] **Step 2: Run test**

```bash
bash scripts/test-isolation.sh
```

Expected: `✅ isolation test passed`. (At this stage we're only running schema validation against fixtures, which writes nothing — the test is establishing the harness for later tasks to run real skills against.)

- [ ] **Step 3: Commit**

```bash
git add scripts/test-isolation.sh
git commit -m "scripts: test-isolation.sh CI smoke test"
```

---

## Task 5: init skill — write v2 frontmatter + seed changes.jsonl/snapshots

The init skill currently writes v0.1 profile + state files. v0.2 must:
- Stamp `schema_version: 2` in profile.md
- Capture `variable_spending_estimate` (new question between locale and review_cadence)
- Seed empty `changes.jsonl` with a single `op: create` event for "workspace initialized"
- Seed `snapshots/latest.json` as `stale: true`
- Copy `.gitattributes` template into workspace
- Run path guard before any write

**Files:**
- Modify: `skills/init/SKILL.md`
- Modify: `scripts/fixtures/v2-workspace/profile.json` (add `variable_spending_estimate` — already done in Task 1)

- [ ] **Step 1: Read current init skill to find profile.md write step**

```bash
grep -n 'schema_version\|variable_spending\|profile.md\|## Step' skills/init/SKILL.md
```

Locate the section that writes `profile.md` (Step 2f in the existing skill).

- [ ] **Step 2: Update profile.md template in init skill**

In `skills/init/SKILL.md`, find the YAML profile template and update it:

Replace:

```yaml
---
name: <user name>
created: <YYYY-MM-DD>
schema_version: 1
modules: [<enabled modules, comma-separated>]
currency: <currency>
locale: <locale, e.g. en-US or bg-BG>
risk_tolerance: <conservative | moderate | aggressive>
emergency_fund_months: <number>
preferences:
  review_cadence: <monthly | quarterly | yearly>
  decision_style: <data-first | gut-first | balanced>
---
```

with:

```yaml
---
name: <user name>
created: <YYYY-MM-DD>
schema_version: 2
modules: [<enabled modules, comma-separated>]
currency: <currency>
locale: <locale, e.g. en-US or bg-BG>
risk_tolerance: <conservative | moderate | aggressive>
emergency_fund_months: <number>
variable_spending_estimate: <user-provided monthly EUR estimate excluding fixed bills>
preferences:
  review_cadence: <monthly | quarterly | yearly>
  decision_style: <data-first | gut-first | balanced>
---
```

- [ ] **Step 3: Add Question 5b to init's Step 1**

In `skills/init/SKILL.md`, after Question 5 (emergency_fund_months + locale), add:

```markdown
5b. **"What's a rough monthly total for variable spending — groceries, dining, kids' costs, miscellaneous — EXCLUDING rent, utilities, insurance, and other fixed bills?"** Store as `variable_spending_estimate` (currency = profile.currency).

This number is critical for `afford` to compute monthly capacity before transaction history exists. The user can correct it later via `/coinskills:edit profile`. If unsure, suggest a starting point of `0.4 × monthly net income` and let them confirm.
```

- [ ] **Step 4: Add seed-files step at end of Step 2 (Create Workspace Repo)**

After Step 2g (write pointer file), insert a new step in `skills/init/SKILL.md`:

```markdown
### 2h. Seed v0.2 state files

Resolve the workspace root (already in `<absolute-path-to-workspace>` from earlier).

Generate a UTC timestamp now: `TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)`. Generate a 6-hex suffix: `HEX=$(python3 -c 'import secrets; print(secrets.token_hex(3))')`.

Write `<workspace>/changes.jsonl` with exactly one line:

```json
{"id":"chg_<TS>_<HEX>","timestamp":"<TS>","skill":"init","op":"create","target":"workspace","before":null,"after":{"schema_version":2},"validation":"ok","note":"workspace initialized"}
```

Write `<workspace>/snapshots/latest.json`:

```json
{
  "computed_at": "<TS>",
  "stale": true,
  "last_event_id": "chg_<TS>_<HEX>",
  "liquidity": {"disposable": 0, "emergency_buffer": 0, "monthly_expenses": 0, "monthly_capacity": 0},
  "goals": [],
  "warnings": []
}
```

Write `<workspace>/.gitattributes`:

```
changes.jsonl merge=union
```

(Copy the template from the plugin's `skills/_shared/workspace-gitattributes.txt`.)

Create the directory: `mkdir -p <workspace>/snapshots <workspace>/.backups`.
```

- [ ] **Step 5: Add path-guard reference at top of Step 3 (Financial Snapshot Interview)**

In `skills/init/SKILL.md`, prepend to Step 3:

```markdown
**Before any write below**, resolve the workspace root and apply the path guard from `skills/_shared/path-guard.md`. Every file written in this section must be inside the workspace root.

**For every account/goal/plan/recurring/income/holding write below**, follow `skills/_shared/mutation-pipeline.md`: validate against the relevant schema in `<plugin-root>/schemas/`, append a `changes.jsonl` event, then write the file. Mark `snapshots/latest.json` stale at the end of the entire init flow (one stale-mark, not per-write — init is one logical unit).
```

- [ ] **Step 6: Smoke test**

```bash
bash scripts/validate.sh
```

Expected: still fails on missing edit/migrate skills (that's fine — Tasks 6 & 7 add those). The init SKILL.md still passes its own frontmatter checks.

- [ ] **Step 7: Commit**

```bash
git add skills/init/SKILL.md
git commit -m "init: write v2 frontmatter + seed changes.jsonl + snapshots"
```

---

## Task 6: edit skill

Implements the full `/coinskills:edit` family per spec Section 4.

**Files:**
- Create: `skills/edit/SKILL.md`

- [ ] **Step 1: Write `skills/edit/SKILL.md`**

```markdown
---
name: edit
description: Edit account, goal, plan, profile, recurring, income, holding, or attestation values via guided forms. Supports undo. Auto-clears _estimated flags on confirm.
---

# Edit — Guided State Editor with Undo

## When to use

User wants to correct a value, confirm an estimated field, set an attestation date, or undo a recent change. Triggered explicitly via slash command:

- `/coinskills:edit account <id>`
- `/coinskills:edit goal <id>`
- `/coinskills:edit plan <goal-id>`
- `/coinskills:edit profile`
- `/coinskills:edit recurring <id>`
- `/coinskills:edit income <id>`
- `/coinskills:edit holding <ticker>`
- `/coinskills:edit attestation <goal-id> "<prereq-label>"`
- `/coinskills:edit undo` (last change) or `/coinskills:edit undo <event-id>`

## Step 1: Setup

Apply `skills/_shared/path-guard.md`. Read profile.md frontmatter; if `schema_version != 2`, abort: "v0.2 features require migration. Run /coinskills:migrate first."

## Step 2: Dispatch by subcommand

Parse the user's argument string. Dispatch:

| Subcommand | File | Schema |
|---|---|---|
| `account <id>` | `accounts.json` (single entry by id) | `account.schema.json` |
| `goal <id>` | `goals/<id>.md` (frontmatter) | `goal.schema.json` |
| `plan <goal-id>` | active plan in `plans/` matching goal-id | `plan.schema.json` |
| `profile` | `profile.md` (frontmatter) | `profile.schema.json` |
| `recurring <id>` | entry in `modules/personal/recurring.json` | `recurring.schema.json` |
| `income <id>` | entry in `modules/personal/income.json` | `income.schema.json` |
| `holding <ticker>` | entry in `modules/investments/holdings.json` | `holding.schema.json` |
| `attestation <goal-id> <label>` | nested prereq inside `goals/<goal-id>.md` frontmatter | `goal.schema.json` |
| `undo` | last entry in `changes.jsonl` | `change-event.schema.json` |
| `undo <event-id>` | specific entry | `change-event.schema.json` |

If the target doesn't exist (account id, goal id, ticker not found), respond: "<target> not found. Did you mean: <closest 3 matches>?" then exit.

## Step 3: Guided form (for non-undo subcommands)

1. Print the current entry as a numbered table:

   ```
   Editing account 'card-unicredit-bulbank':
     1. id              card-unicredit-bulbank   (immutable)
     2. type            credit_card
     3. name            UniCredit Bulbank
     4. currency        EUR
     5. limit           10000
     6. balance         -2000
     7. apr             0.199                    ⚠ estimated
     8. billing_cycle_day  15                    ⚠ estimated
     9. rewards         (none)
    10. module          personal
   ```

2. Prompt: "Pick a field number to edit, type 'confirm <field>' to clear the ⚠ estimated flag without changing the value, or type 'cancel' to exit."

3. On field selection:
   - If field is in `_estimated`, ask explicitly: "This field is currently flagged as estimated. Are you (a) confirming the existing value as accurate, or (b) entering a corrected value?" Two paths:
     - (a) → no value change. Proceed with `op: confirm`. Remove field from `_estimated` array.
     - (b) → prompt for new value. Proceed with `op: update`. Remove field from `_estimated` array.
   - If field is NOT in `_estimated`, prompt for new value. Proceed with `op: update`.

4. Validate the proposed change:
   - Run schema validation per `skills/_shared/mutation-pipeline.md` step 2.
   - Show a diff:
     ```
     - apr: 0.199  (estimated)
     + apr: 0.185  (confirmed)
     ```
   - Ask: "Apply this change? (yes / no)"

5. On yes → run mutation pipeline steps 3-5 (append to changes.jsonl, atomic write, mark snapshot stale). Print:

   ```
   ✅ Applied. Event id: chg_2026-04-28T11:02:14Z_b7c
   To undo: /coinskills:edit undo chg_2026-04-28T11:02:14Z_b7c
   ```

6. On no → exit without writing anything.

## Step 4: attestation subcommand

`/coinskills:edit attestation <goal-id> "<prereq-label>"` is a fast-path that:

1. Loads `goals/<goal-id>.md` frontmatter.
2. Finds the prereq entry where `type == "attestation"` AND `label == "<prereq-label>"` (case-insensitive). If not found, list available attestation labels and exit.
3. Prompts: "Confirm '<label>' as true today (<YYYY-MM-DD>)?"
4. On yes → set `confirmed_at: <today>`. Run mutation pipeline. `op: confirm`.
5. On no → exit.

## Step 5: undo subcommand

### `/coinskills:edit undo`

1. Read last line of `changes.jsonl`.
2. If `op == "undo"` already → ask the user: "Last change was already an undo. Undo the undo? (yes / no)". On yes, treat its `reverses` field as the event to redo. On no, exit.
3. Otherwise, treat last change as the target.

### `/coinskills:edit undo <event-id>`

1. Find the event with matching id in `changes.jsonl`.
2. **Conflict detection:** scan all later events for any whose `target` overlaps the original event's target (same file + same JSON path or a prefix match). If any exist, print:

   ```
   ⚠ This change has been overwritten by later edits. Reverting it would also revert:
     - chg_<id> on <target> (<op>, <timestamp>)
   Proceed anyway? (yes / no / cancel)
   ```

   On yes → continue. On no/cancel → exit.

### Apply the reversal

1. Construct the reverse mutation: write `before` back as the new state.
2. Validate against the schema (the `before` state must still be valid in v0.2 — if not, error: "Cannot undo: pre-change state is invalid under current schema.").
3. Append a new event:

   ```json
   {"id":"chg_<now>_<hex>","timestamp":"<now>","skill":"edit","op":"undo","target":"<original target>","before":<original after>,"after":<original before>,"validation":"ok","reverses":"<original event id>"}
   ```

4. Atomic-write the reverted state. Mark snapshot stale.
5. Print:

   ```
   ✅ Reverted chg_<original id>. Event id: chg_<new id>
   To redo: /coinskills:edit undo chg_<new id>
   ```

## Step 6: Commit

After any successful edit/confirm/undo, ask: "Commit this change to git? (yes / no — defaults to no)". On yes:

```bash
git -C <workspace> add changes.jsonl <touched-file> snapshots/latest.json
git -C <workspace> commit -m "edit: <op> <target>"
```

## Self-check

- Path guard ran before any write.
- Schema validation ran before any write.
- changes.jsonl line is exactly one valid JSON object matching change-event.schema.json.
- snapshots/latest.json `stale: true` after the write.
- No file written outside `<workspace>`.
```

- [ ] **Step 2: Verify with validate.sh**

```bash
bash scripts/validate.sh
```

Expected: edit skill found, frontmatter valid. May still fail on `migrate` (next task).

- [ ] **Step 3: Commit**

```bash
git add skills/edit/SKILL.md
git commit -m "skill: add edit (guided forms + attestation + undo)"
```

---

## Task 7: migrate skill

**Files:**
- Create: `skills/migrate/SKILL.md`
- Create: `scripts/fixtures/v1-workspace/` (mirror v0.1 layout for migration tests)

- [ ] **Step 1: Create v0.1 fixture**

```bash
mkdir -p scripts/fixtures/v1-workspace/{goals,plans,modules/personal,modules/investments}
```

`scripts/fixtures/v1-workspace/profile.md`:

```markdown
---
name: fixture
created: 2026-04-01
schema_version: 1
modules: [personal, investments]
currency: EUR
locale: en-US
risk_tolerance: moderate
emergency_fund_months: 6
preferences:
  review_cadence: quarterly
  decision_style: balanced
---
# Notes
v1 fixture for migrate testing.
```

`scripts/fixtures/v1-workspace/accounts.json`:

```json
[
  {"id": "bank-main", "type": "bank", "name": "Main Bank", "currency": "EUR", "balance": 1000, "module": "personal"}
]
```

`scripts/fixtures/v1-workspace/goals/example-goal.md`:

```markdown
---
id: example-goal
title: Example Goal
type: savings
target_amount: 5000
currency: EUR
deadline: 2027-01-01
priority: 1
status: active
linked_accounts: [bank-main]
created: 2026-04-01
---
# Why
Test fixture.

## Prerequisites for purchase
Do not draw down until ALL of these are true:

1. emergency-fund-6mo complete
2. savings-revolut balance >= 25500 EUR
```

(Plans/recurring/income files are minimal copies of v2 fixtures — same structure, no v2-only fields, schema_version absent.)

- [ ] **Step 2: Write `skills/migrate/SKILL.md`**

```markdown
---
name: migrate
description: One-shot migration from v0.1 workspace to v0.2 schema. Creates changes.jsonl, snapshots/, .backups/, adds funding_mode + prerequisites + status enum to goals, prompts for _estimated flags on accounts.
---

# Migrate — v0.1 → v0.2 Workspace Migration

## When to use

User runs `/coinskills:migrate`. Idempotent: detects schema_version and refuses to re-run on already-migrated workspaces.

## Step 1: Setup

Apply `skills/_shared/path-guard.md`. Read profile.md frontmatter:

- If `schema_version: 2` already → print "Workspace already migrated. Nothing to do." and exit 0.
- If `schema_version: 1` (or missing → assume 1) → proceed.

Compute the timestamp `TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)`.

## Step 2: Backup

```bash
BACKUP="<workspace>/.backups/v1-pre-migration-${TS//[:T]/-}"
mkdir -p "$BACKUP"
rsync -a --exclude='.backups' --exclude='.git' "<workspace>/" "$BACKUP/"
```

Print: `✅ Backup created at $BACKUP`. Tell the user: "If anything goes wrong, you can restore by `rsync -a $BACKUP/ <workspace>/` (and reverting git)."

## Step 3: Seed v2 artifacts

Generate `HEX=$(python3 -c 'import secrets; print(secrets.token_hex(3))')`.

Write `<workspace>/changes.jsonl` (overwriting any existing — there shouldn't be one in v0.1):

```json
{"id":"chg_<TS>_<HEX>","timestamp":"<TS>","skill":"migrate","op":"migrate","target":"workspace","before":{"schema_version":1},"after":{"schema_version":2},"validation":"ok","note":"v0.1 → v0.2 migration"}
```

Write `<workspace>/snapshots/latest.json`:

```json
{
  "computed_at": "<TS>",
  "stale": true,
  "last_event_id": "chg_<TS>_<HEX>",
  "liquidity": {"disposable": 0, "emergency_buffer": 0, "monthly_expenses": 0, "monthly_capacity": 0},
  "goals": [],
  "warnings": []
}
```

Write `<workspace>/.gitattributes`:

```
changes.jsonl merge=union
```

`mkdir -p <workspace>/.backups <workspace>/snapshots`.

## Step 4: Migrate goal frontmatter

For each `goals/*.md`:

1. Parse the YAML frontmatter.
2. Add `funding_mode: monthly` if absent. If the body text contains "windfall" (case-insensitive), prompt: "Goal `<id>` mentions 'windfall' in its body. Set funding_mode to (a) monthly, (b) windfall-only, (c) hybrid?" Apply the user's choice.
3. If `funding_mode != monthly`, prompt: "What windfall sources fund this goal? (free-form, comma-separated, e.g. 'annual-bonus, equity-vest')". Set `windfall_sources` to the parsed list.
4. Add `prerequisites: []` as an empty list IF none exists.
5. If the goal body contains a `## Prerequisites` (or similar) section, prompt: "Goal `<id>` has prose prerequisites:\n\n<excerpt>\n\nConvert to structured form now? (interactive / later / leave as prose)". On `interactive`, walk through each line and propose a structured entry per the schema (the user picks the type — goal-complete, account-balance, attestation, time-since — and confirms fields).
6. Validate the resulting frontmatter against `schemas/goal.schema.json`. If invalid, print the error and prompt for corrections.
7. Atomic-write the file. Append a `changes.jsonl` event per migrated goal: `{op: update, target: "goals/<id>.md#frontmatter", before: <old>, after: <new>}`.

## Step 5: Migrate plan frontmatter

For each `plans/*.md`: validate against `schemas/plan.schema.json`. Most v0.1 plans should already conform. Fix any drift inline (status enum mismatches → prompt user). Append change-events as needed.

## Step 6: Account `_estimated` seeding

For each account in `accounts.json`, prompt:

> "Were any fields on `<id>` (<name>) estimated rather than user-confirmed at init time? Pick a comma-separated list from: apr, billing_cycle_day, rewards, monthly_payment / type 'none' / type 'all'."

Apply: set `_estimated: [<fields>]` (or omit the field if `none`/empty). Append a `changes.jsonl` event for each account that gets `_estimated` added.

## Step 7: Update profile.md

1. Set `schema_version: 2` in frontmatter.
2. If `variable_spending_estimate` is absent, prompt: "What's a rough monthly total for variable spending (groceries, dining, kids, misc), excluding fixed bills?". Set field.
3. Validate against `schemas/profile.schema.json`. Atomic-write. Append change-event.

## Step 8: Schema validation pass

Run schema validation against every file in the workspace:

- accounts.json, profile.md frontmatter, every goals/*.md frontmatter, every plans/*.md frontmatter, modules/personal/recurring.json, modules/personal/income.json, modules/investments/holdings.json (if present).

Collect every violation. Print:

```
Schema validation report:
  ✅ accounts.json
  ✅ profile.md
  ❌ goals/example-goal.md — prerequisites[1] missing required field "currency"
  ...
```

DO NOT auto-fix. Tell the user: "Run /coinskills:edit goal <id> to fix flagged items. Re-run /coinskills:migrate after fixes — it's idempotent."

## Step 9: Print summary

```
Migration v0.1 → v0.2 complete.

Files touched:    <N>
Goals migrated:   <N> (<N> with prereqs converted, <N> deferred as prose, <N> still passing as prose)
Accounts flagged: <N> with _estimated fields
Validation:       <N> ok, <N> with issues (see above)

Backup:           <BACKUP path>

Next steps:
  /coinskills:start    — see your status under v0.2
  /coinskills:edit     — fix any flagged items
```

## Step 10: Commit

Ask: "Commit migration to git? (yes / no)". On yes:

```bash
git -C <workspace> add -A
git -C <workspace> commit -m "migrate: v0.1 → v0.2 schema"
```

## Self-check

- Backup exists at `.backups/v1-pre-migration-<ts>/`.
- profile.md frontmatter has `schema_version: 2`.
- changes.jsonl exists with at least the migration seed event.
- snapshots/latest.json exists with `stale: true`.
- No file written outside the workspace.
- Re-running the skill is a no-op (it sees schema_version: 2 and exits early).
```

- [ ] **Step 3: Verify validate.sh now passes**

```bash
bash scripts/validate.sh
```

Expected: `✅ coinskills validation passed`.

- [ ] **Step 4: Commit**

```bash
git add skills/migrate/SKILL.md scripts/fixtures/v1-workspace/
git commit -m "skill: add migrate (v0.1 → v0.2 with backup + interactive prereq conversion)"
```

---

## Task 8: goals skill — write v2 frontmatter

**Files:**
- Modify: `skills/goals/SKILL.md`

- [ ] **Step 1: Locate goal-creation template in goals skill**

```bash
grep -n 'frontmatter\|target_amount\|status:\|funding_mode\|prerequisites' skills/goals/SKILL.md
```

- [ ] **Step 2: Update template to v2 shape**

In `skills/goals/SKILL.md`, find the goal-file template and replace it with:

```yaml
---
id: <id>
title: <title>
type: <savings | debt-payoff | investment | retirement | purchase | custom>
target_amount: <number>
currency: <ISO code>
deadline: <YYYY-MM-DD or "none">
priority: <integer ≥ 1>
status: <active | blocked | paused | complete | retired>
linked_accounts: [<ids>]
created: <YYYY-MM-DD>
funding_mode: <monthly | windfall-only | hybrid>
windfall_sources: [<source-1>, <source-2>]   # only when funding_mode != monthly
prerequisites: []                              # see schemas/goal.schema.json for shape
---
# Why
<purpose, constraints, what "done" looks like beyond the number>
```

- [ ] **Step 3: Add new questions in goal-creation interview**

In `skills/goals/SKILL.md`, add to the per-goal interview (after collecting linked_accounts):

```markdown
- **Funding mode:** "Will this goal be funded from monthly contributions (`monthly`), only from windfalls like bonuses or equity vests (`windfall-only`), or both (`hybrid`)?"

- **Windfall sources** (only if mode != monthly): "List the windfall sources that should fund this goal — comma-separated. Examples: annual-bonus, equity-vest, severance-overflow, side-income, avgo-rebalance."

- **Prerequisites** (optional, defer if user is unsure): "Does this goal have hard prerequisites that must be met before it can complete or be drawn down? Examples: another goal must be done first, an account must reach a balance, a stable-income period must be confirmed. (yes / no / later)"

  On yes, walk through prereq creation: for each prereq, ask which type (goal-complete / account-balance / attestation / time-since), then collect the type-specific fields from `schemas/goal.schema.json`.

  On no/later, set `prerequisites: []`.
```

- [ ] **Step 4: Add mutation-pipeline reference**

At the top of the goals skill's "write goal file" section, add:

```markdown
**Before writing**, apply path guard from `skills/_shared/path-guard.md` and follow the mutation pipeline from `skills/_shared/mutation-pipeline.md`. Validate the frontmatter against `schemas/goal.schema.json` before writing. Append a `changes.jsonl` event with `op: create` and `target: "goals/<id>.md"`. Mark snapshot stale.
```

- [ ] **Step 5: Validate**

```bash
bash scripts/validate.sh
```

Expected: still passes.

- [ ] **Step 6: Commit**

```bash
git add skills/goals/SKILL.md
git commit -m "goals: write v2 frontmatter (funding_mode, prerequisites, status enum)"
```

---

## Task 9: log skill — mutation pipeline

**Files:**
- Modify: `skills/log/SKILL.md`

- [ ] **Step 1: Add mutation-pipeline reference at top of log's write step**

In `skills/log/SKILL.md`, prepend to the section that writes the transaction file and updates accounts.json:

```markdown
**Apply path guard** from `skills/_shared/path-guard.md` before any write. **Run the mutation pipeline** from `skills/_shared/mutation-pipeline.md` for every state change:

- Transaction append → `op: create`, `target: modules/personal/transactions/YYYY-MM.md#<row>`
- Account balance update → `op: update`, `target: accounts.json#<account-id>.balance`

Mark snapshot stale at the end of the log invocation (one mark, even if multiple writes happened).
```

- [ ] **Step 2: Validate**

```bash
bash scripts/validate.sh
```

- [ ] **Step 3: Commit**

```bash
git add skills/log/SKILL.md
git commit -m "log: route writes through mutation pipeline + snapshot stale mark"
```

---

## Task 10: read-side skills — schema_version gate + snapshot reuse + recognition-over-recall

**Files:**
- Modify: `skills/start/SKILL.md`
- Modify: `skills/afford/SKILL.md`
- Modify: `skills/analyze/SKILL.md`
- Modify: `skills/review/SKILL.md`

- [ ] **Step 1: Add gate prelude to each read skill**

For each of `start`, `afford`, `analyze`, `review`, prepend before any data-loading step:

```markdown
**Schema version gate.** Read `<workspace>/profile.md` frontmatter. If `schema_version != 2` (or absent), print:

> v0.2 features require migration. Run `/coinskills:migrate` first.

Exit. Do NOT proceed.
```

- [ ] **Step 2: Add snapshot-reuse step to start, afford, analyze**

For `start`, `afford`, `analyze`, replace their "compute liquidity" / "load state" preamble with a reference:

```markdown
**Load aggregate state via snapshot.** Follow `skills/_shared/snapshot-compute.md`. The snapshot provides `liquidity` (disposable, emergency_buffer, monthly_expenses, monthly_capacity), per-goal `prereqs_met` and `projected_completion`, and `warnings` (every `_estimated` field). Use these values directly — do not recompute unless the snapshot is stale.
```

For `start`, the existing "show status" rendering uses the snapshot's goals array.

For `afford`, Step 3 (Compute Liquidity) is replaced by snapshot read; the rest of afford's algorithm stays.

For `analyze`, the per-mode (allocation, spending, networth) sections all read from the snapshot's pre-computed fields where applicable; only mode-specific aggregations (e.g. category breakdowns) recompute.

- [ ] **Step 3: Recognition-over-recall in output**

For `start`, `afford`, `analyze`: every place that prints a goal id, render as `<title> (<id>)`. Add this convention to the rendering instructions.

In `skills/start/SKILL.md`, add an explicit example:

```markdown
**Goal references in output:** always render as `<title> (<id>)`. Example: `Emergency fund 6mo (emergency-fund-6mo)`. Never bare ids.
```

Repeat the same line in `skills/afford/SKILL.md` and `skills/analyze/SKILL.md`.

- [ ] **Step 4: start — add "Waiting on prereqs" section**

In `skills/start/SKILL.md`, after the active-goals section, add:

```markdown
### Blocked goals (waiting on prerequisites)

For every goal where `snapshot.goals[].status == "blocked"`:

- Render `<title> (<id>)` with the unmet-prereqs list from `snapshot.goals[].prereqs_met.unmet`. Show count: "<N>/<M> prereqs met".
- Suggest the next user action: for any unmet `attestation` prereq, suggest `/coinskills:edit attestation <id> "<label>"`.

Example:

```
Blocked (waiting on prerequisites):
  Mustang Dark Horse (mustang-dark-horse) — 2/5 prereqs met
    ✗ finish-consumer-credit not complete
    ✗ savings-revolut < €25,500
    ○ Praven salary stable for 12 months — attestation pending
        run: /coinskills:edit attestation mustang-dark-horse "Praven salary stable for 12 months"
    ✗ future-house-2030 not in active construction
    ✗ bridge-fund-untouched: 0mo since attestation
```

Hide blocked goals from `start --concise` (default). Show with `start --all` or always when prereqs newly satisfied.
```

- [ ] **Step 5: Validate**

```bash
bash scripts/validate.sh
```

- [ ] **Step 6: Commit**

```bash
git add skills/start/SKILL.md skills/afford/SKILL.md skills/analyze/SKILL.md skills/review/SKILL.md
git commit -m "read-skills: schema_version gate + snapshot reuse + recognition-over-recall"
```

---

## Task 11: afford v2 — Step 0 goal-detection + Step 4.5 prereq eval

**Files:**
- Modify: `skills/afford/SKILL.md`

- [ ] **Step 1: Insert Step 0 (goal-detection heuristic)**

In `skills/afford/SKILL.md`, add a new section between "Overview" and "Step 1: Parse the Ask":

```markdown
## Step 0: Goal-detection heuristic (runs before Step 1)

After parsing the user's message into `{amount, currency, item, frequency, urgency, deadline}`, evaluate whether this is really a goal:

```
goal_detected = (
  classification == "one-off purchase" AND
  deadline == "none" AND
  urgency == "nice-to-have" AND
  amount > 6 * snapshot.liquidity.monthly_capacity AND
  snapshot.liquidity.disposable < amount AND
  no active goal title/notes fuzzy-matches the item
)
```

Fuzzy match: case-insensitive substring match between item description and goal `title` OR `# Why` body, considering common synonyms (car/vehicle, house/property, studio/space).

If `goal_detected == true`, pause before continuing the algorithm and ask:

> This looks more like a goal than a one-off decision: €<amount> is <amount/monthly_capacity>× your monthly capacity, no deadline, no rush. Want to add it as a goal instead, or run the affordability check anyway?
>
> (a) goal — add it via /coinskills:goals (this skill ends, that one starts)
> (b) afford — continue with the affordability check
> (c) cancel — exit

On (a): chain to `/coinskills:goals` with the parsed item pre-filled (suggested title = item, target_amount = amount, currency = currency, type = purchase, deadline = none). End this skill invocation.
On (b): proceed to Step 1 normally.
On (c): exit, no log entry.
```

- [ ] **Step 2: Insert Step 4.5 (prereq auto-evaluation)**

In `skills/afford/SKILL.md`, add a new subsection at the end of "Pass B — Goal Impact":

```markdown
### Pass B (continued) — Prereq status for blocked/windfall-only goals

The snapshot's per-goal `prereqs_met` is already computed. For each goal where `prereqs_met` is non-null:

Render after the impact line:

```
  Mustang Dark Horse (mustang-dark-horse) — prereqs: 2/5 met
       ✗ finish-consumer-credit not complete (active, balance €33,000)
       ✗ savings-revolut balance €1,949 < €25,500
       ○ Praven salary stable for 12 months — attestation pending
            (confirm via /coinskills:edit attestation mustang-dark-horse "Praven salary stable for 12 months")
       ✗ future-house-2030 not in active construction
       ✗ bridge-fund-untouched: 0mo since attestation
       Impact: none (windfall-only, gates unmet)
```

**Verdict rules update:**
- If the user's affordability question is *about a gated goal itself* (the parsed item fuzzy-matches a `windfall-only` or `blocked` goal AND prereqs are unmet) → verdict is automatic NO with the gate list.
- If the user's question is about something else, gated goals show `impact: none` (you can't slow what isn't moving) per the funding-mode rule.
```

- [ ] **Step 3: Validate**

```bash
bash scripts/validate.sh
```

- [ ] **Step 4: Commit**

```bash
git add skills/afford/SKILL.md
git commit -m "afford: Step 0 goal-detection + Step 4.5 prereq auto-eval"
```

---

## Task 12: README + CHANGELOG + plugin.json

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Bump version**

Edit `.claude-plugin/plugin.json`: change `"version": "0.1.0"` (or whatever current is) to `"version": "0.2.0"`.

- [ ] **Step 2: Add Skills entries to README**

In `README.md`, find the `## Skills` section and add two new entries:

```markdown
- `/coinskills:edit` — Guided editor for any account/goal/plan/profile field. Confirms estimated values, supports undo.
- `/coinskills:migrate` — One-shot v0.1 → v0.2 workspace migration. Run once after upgrading the plugin.
```

- [ ] **Step 3: Add v0.2 features section to README**

After the `## Skills` section, before `## Quickstart`:

```markdown
## v0.2 features

- **Recoverability.** Every mutation is logged to `changes.jsonl`. `/coinskills:edit undo` reverses any change with conflict detection.
- **Estimated-value tracking.** Fields you guessed at init time are flagged with `_estimated`. The edit skill prompts you to confirm or correct them over time.
- **Structured prerequisites.** Goals can specify hard prereqs (other goals complete, account balance thresholds, attestations, time-since) and `afford` evaluates them automatically.
- **Funding modes.** `monthly`, `windfall-only` (Mustang-style aspirational goals), `hybrid`. Afford's goal-impact analysis respects funding mode — windfall-only goals don't get "delayed" by everyday spending.
- **Goal-detection in afford.** When you ask about a big-ticket item with no deadline and no rush, afford suggests creating a goal first instead of forcing a YES/NO verdict.
- **Snapshot cache.** Liquidity and per-goal projections are computed once and cached at `snapshots/latest.json`. Any mutation marks it stale; the next read recomputes.

## Upgrading

If you have a v0.1 workspace, run `/coinskills:migrate` after installing v0.2. The migration is idempotent, creates a backup at `.backups/`, and walks you through converting prose prerequisites to structured form.
```

- [ ] **Step 4: Write CHANGELOG entry**

If `CHANGELOG.md` exists, prepend; otherwise create:

```markdown
# Changelog

## v0.2.0 — 2026-04-28

**Added**
- `edit` skill — guided editor for accounts, goals, plans, profile, recurring, income, holdings, attestations. Supports undo with conflict detection.
- `migrate` skill — one-shot v0.1 → v0.2 migration with workspace backup.
- `changes.jsonl` append-only event log at workspace root.
- `snapshots/latest.json` derived aggregate cache with stale flag.
- JSON schemas for every state file under `schemas/`.
- `_estimated` field on accounts/goals/plans for provenance tracking.
- Goal frontmatter additions: `funding_mode`, `prerequisites` (structured), `windfall_sources`.
- Goal status enum: `active | blocked | paused | complete | retired`.
- Afford Step 0 goal-detection heuristic and Step 4.5 prerequisite auto-evaluation.
- Recognition-over-recall: all goal references in output use `<title> (<id>)`.
- `scripts/test-isolation.sh` and `scripts/test-schemas.sh` smoke tests.
- Defense-in-depth `.gitignore` patterns to prevent financial-data leaks into the plugin repo.

**Changed**
- `init` writes `schema_version: 2`, captures `variable_spending_estimate`, seeds `changes.jsonl` and `snapshots/latest.json`.
- `goals` writes v2 frontmatter (funding_mode + prerequisites + status enum).
- `log` routes all writes through the mutation pipeline.
- All read skills (`start`, `afford`, `analyze`, `review`) gate on `schema_version: 2` and reuse the snapshot.

**Fixed**
- Affordability calls no longer recompute liquidity from scratch on every invocation.
- Estimated values at init time can now be marked, displayed, and confirmed over time.
- Prose-style goal prerequisites are now machine-evaluable.

## v0.1.0 — 2026-04-27

Initial release.
```

- [ ] **Step 5: Validate, commit**

```bash
bash scripts/validate.sh
git add README.md CHANGELOG.md .claude-plugin/plugin.json
git commit -m "release: v0.2.0 — README + CHANGELOG + version bump"
```

---

## Task 13: Final smoke tests + run order

**Files:**
- None (verification only)

- [ ] **Step 1: Run validate.sh**

```bash
bash scripts/validate.sh
```

Expected: `✅ coinskills validation passed`. All 10 skills present (init, start, goals, plan, afford, log, analyze, review, edit, migrate).

- [ ] **Step 2: Run test-schemas.sh**

```bash
bash scripts/test-schemas.sh
```

Expected: every fixture validates, negative case rejected, `✅ schemas validation passed`.

- [ ] **Step 3: Run test-isolation.sh**

```bash
bash scripts/test-isolation.sh
```

Expected: `✅ isolation test passed — no writes leaked outside <tmpdir>`.

- [ ] **Step 4: Commit any test fixes**

If any of the three failed, fix inline and:

```bash
git add -A
git commit -m "fixes from final smoke tests"
```

- [ ] **Step 5: Tag the release**

```bash
git tag v0.2.0
```

(Do NOT push the tag without user confirmation — that's a public action.)

---

## Self-review notes

**Spec coverage check:** every spec section maps to at least one task —
- Privacy invariant → Tasks 2 (path-guard), 3 (.gitignore), 4 (test-isolation).
- Architecture → Tasks 2 (mutation pipeline + snapshot compute), 5 (init seeding).
- Data model (`changes.jsonl`, snapshots, `_estimated`) → Tasks 1 (schemas), 5 (init seed), 6 (edit), 7 (migrate).
- Goal model v2 → Tasks 1 (goal schema), 8 (goals skill), 7 (migrate goals).
- `edit` skill → Task 6.
- `afford` v2 → Tasks 10 (snapshot reuse, recognition-over-recall), 11 (Step 0, Step 4.5).
- Migration → Task 7.
- Privacy patterns extension to all skills → Tasks 5, 9, 10, 11 (each adds the path-guard reference).

**Type consistency check:** `funding_mode` enum used identically in spec, schema (Task 1), goals skill (Task 8), migrate (Task 7). `_estimated` is an array of field names everywhere. Event id format `chg_<UTC-iso>_<6-hex>` matches in mutation-pipeline (Task 2), init (Task 5), edit (Task 6), migrate (Task 7), and the `change-event.schema.json` regex.

**No-placeholder check:** every task has explicit code or markdown content. The migrate skill's "interactive prereq conversion" sub-flow is the most LLM-driven — that's appropriate, since the conversion is genuinely interactive and the skill is markdown instructions for an LLM, not deterministic code.
