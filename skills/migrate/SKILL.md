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
