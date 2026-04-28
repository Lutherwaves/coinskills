# coinskills v0.2 — Core Fixes Design

**Status:** Draft
**Date:** 2026-04-28
**Scope:** Sub-projects 1+2+3 from the v0.2 roadmap — State foundation, Goal model v2, Afford v2.
**Out of scope:** init split, variable_spending_estimate capture flow, windfall skill, currency model. Those are separate specs.

## Motivation

A live `/coinskills:init` + `/coinskills:afford` session surfaced concrete gaps:

- No way to recover from data-entry mistakes without hand-editing JSON.
- Estimated values (APRs, dates) became authoritative once written — no provenance.
- Goal prerequisites lived as prose; `afford` could not actually evaluate them.
- Aspirational big-ticket questions ("can I afford a Mustang?") got routed through `afford` when they were really goals.
- No state cache — every `afford` call recomputed liquidity from scratch.

This spec addresses those gaps directly.

## Privacy invariant (non-negotiable)

The coinskills plugin repo (`Lutherwaves/coinskills`, public) MUST never receive any financial data. The user workspace (e.g. `Lutherwaves/coinscious`, private) is the only destination for state, change-log, snapshots, or attestations.

**Enforcement:**

1. **Single source of truth for workspace path.** Every mutating skill resolves the absolute workspace root from `~/.coinskills-workspace` at the start of execution. No cwd-relative paths, no `../` traversal, no path concatenation that doesn't start from that root.
2. **Path guard at every write.** Before any write operation, the skill asserts the target path's `realpath` starts with the workspace root from the pointer file. Refuse with a hard error otherwise. Lives in each mutating skill's "validate-and-write" prelude.
3. **Plugin repo `.gitignore` defense in depth.** Add patterns: `**/accounts.json`, `**/changes.jsonl`, `**/snapshots/`, `**/goals/*.md`, `**/plans/*.md`, `**/profile.md`, `**/assets-illiquid.json`, `**/modules/`, `*-finances*`, `*-coinscious*`. So even a misfiring skill can't stage financial data.
4. **Smoke test in `scripts/test-isolation.sh`.** Creates a tmpdir workspace, runs each skill via fixtures, asserts nothing outside the tmpdir was written. Runs in CI.
5. **No telemetry, no analytics, no remote calls.** Explicit non-feature. Skills only read/write within the workspace and (when the user explicitly asks) call `git`/`gh` against the user's private remote.

## Architecture

Three-layer workspace data model:

1. **Current-state files** (unchanged from v0.1): `accounts.json`, `goals/*.md`, `plans/*.md`, `profile.md`, `assets-illiquid.json`, `modules/*/*.json`. Canonical source readable by humans and skills.
2. **`changes.jsonl`** (new, repo root): append-only event log. One JSON object per line. Every mutating skill writes here before touching state files. Enables undo, audit, and `_estimated` provenance tracking.
3. **`snapshots/latest.json`** (new): derived aggregate cache — `disposable`, `monthly_expenses`, `monthly_capacity`, per-goal projections, prereq evaluations. Marked `{stale: true, ...}` after any write. Read-skills (`start`, `afford`, `analyze`) rebuild lazily on first read after staleness.

**Mutation pipeline** (every write goes through this):

```
input → validate against JSON schema (strict, reject on violation)
      → append to changes.jsonl
      → mutate state file
      → mark snapshots/latest.json stale
```

JSON schemas ship with the plugin at `schemas/` and are referenced by absolute path from each mutating skill.

**Validation strictness:**
- **Reject:** missing required fields, type mismatches, unknown enum values, broken cross-refs (linked_account → nonexistent ID).
- **Warn but write:** business-rule oddities (negative savings balance, etc.).

## Data model

### `changes.jsonl` entry shape

```json
{"id":"chg_2026-04-28T10:15:33Z_a3f","timestamp":"2026-04-28T10:15:33Z","skill":"edit","op":"update","target":"accounts.json#card-unicredit-bulbank.apr","before":0.199,"after":0.185,"validation":"ok","note":"user-confirmed via edit"}
```

- `op`: `create | update | delete | confirm | undo | migrate`
- `target`: file path + JSON-pointer-ish suffix
- `before`/`after`: scalar or sub-object — whatever was actually changed
- One file at repo root, never rotated, never compacted
- `.gitattributes` sets `changes.jsonl merge=union` so cross-machine merges concatenate cleanly

### `snapshots/latest.json` shape

```json
{
  "computed_at": "2026-04-28T10:15:35Z",
  "stale": false,
  "last_event_id": "chg_2026-04-28T10:15:33Z_a3f",
  "liquidity": {
    "disposable": 4280,
    "emergency_buffer": 25500,
    "monthly_expenses": 4254,
    "monthly_capacity": 1096
  },
  "goals": [
    {
      "id": "emergency-fund-6mo",
      "status": "active",
      "prereqs_met": null,
      "projected_completion": "2027-12-15",
      "delay_days_from_deadline": -180
    }
  ],
  "warnings": ["account 'card-unicredit-bulbank' apr is _estimated"]
}
```

Read-skills check `stale` first; if true, recompute and overwrite.

### `_estimated` flag representation

Lives alongside the value in the same object, as an array of field names:

```json
{
  "id": "card-unicredit-bulbank",
  "apr": 0.199,
  "billing_cycle_day": 15,
  "_estimated": ["apr", "billing_cycle_day"]
}
```

- `edit` skill displays `⚠ estimated` next to those fields and removes the entry from `_estimated` when the user confirms a value (with or without changing it).
- Snapshot's `warnings` lists every `_estimated` field across all accounts.

### Schema files (ship with plugin)

`schemas/account.schema.json`, `schemas/goal.schema.json`, `schemas/plan.schema.json`, `schemas/profile.schema.json`, `schemas/recurring.schema.json`, `schemas/income.schema.json`, `schemas/holding.schema.json`, `schemas/change-event.schema.json`. Each mutating skill's prelude references the relevant schema by absolute path resolved from the plugin install location.

## Goal model v2

### Frontmatter additions to `goals/<id>.md`

```yaml
status: active | blocked | paused | complete | retired
funding_mode: monthly | windfall-only | hybrid
prerequisites:
  - {type: goal-complete, ref: finish-consumer-credit}
  - {type: account-balance, ref: savings-revolut, op: gte, value: 25500, currency: EUR}
  - {type: attestation, label: "Praven salary stable for 12 months", confirmed_at: null}
  - {type: time-since, ref: bridge-fund-untouched, months: 6}
windfall_sources:
  - praven-equity-vest
  - annual-bonus-50pct
  - avgo-rebalance
  - side-income
  - severance-overflow
```

`windfall_sources` is required when `funding_mode != monthly`, otherwise omitted.

### Status semantics

| status | meaning | inclusion in views |
|---|---|---|
| `active` | counts in projections, contributions flow | shown in `start` |
| `blocked` | prereqs unmet | "Waiting on prereqs" section |
| `paused` | user-initiated hold | hidden by default; `--all` shows |
| `complete` | target reached | archived from default view |
| `retired` | abandoned | hidden by default |

Status is **derived from prereqs + plan** when possible:
- `blocked` if any prereq is unmet AND `funding_mode != monthly`
- User can manually override to `paused` via `/coinskills:edit goal <id>`

### Prerequisite types

| type | required fields | evaluator |
|---|---|---|
| `goal-complete` | `ref` | other goal's `status == complete` |
| `account-balance` | `ref, op (gte/lte/eq), value, currency` | account's balance satisfies op |
| `time-since` | `ref` (free-form event label), `months` | months since `confirmed_at` on a matching attestation |
| `attestation` | `label, confirmed_at` (nullable) | user confirms via `edit attestation`; sets timestamp |

### Funding modes

- `monthly` — plan has `monthly_contribution > 0`, contributions auto-flow per plan.
- `windfall-only` — plan's `monthly_contribution: 0`, status defaults to `blocked` until prereqs + a windfall arrives. Mustang fits this.
- `hybrid` — both. e.g. house goal with €500/mo + bonus accelerators.

### Afford Pass B impact rule update

For `windfall-only` goals with unmet prereqs, the impact tag is always `none` (you can't slow what isn't moving). Once prereqs are met, evaluated normally.

## `edit` skill

### Invocation forms

- `/coinskills:edit account <id>`
- `/coinskills:edit goal <id>`
- `/coinskills:edit plan <goal-id>`
- `/coinskills:edit profile`
- `/coinskills:edit recurring <id>` / `income <id>` / `holding <ticker>`
- `/coinskills:edit attestation <goal-id> <prereq-label>` — sets `confirmed_at: <today>`
- `/coinskills:edit undo` — pop last entry from `changes.jsonl`, reverse it, append a new `op: undo` event referencing the popped id
- `/coinskills:edit undo <event-id>` — targeted undo with conflict detection

### Guided editor flow

1. Print all current fields with values; mark `_estimated` ones with `⚠`.
2. Print numbered menu — user picks field number or types field name; can type `confirm <field>` to clear `_estimated` flag without changing value.
3. Prompt new value, validate against schema, show diff, confirm.
4. Run mutation pipeline (validate → append change-log → mutate → mark snapshot stale).
5. Show one-line confirmation + the new event id.

### Estimated-flag UX

When the field has `_estimated: true`, the editor explicitly asks: *"is this still an estimate, or are you confirming the value?"* — picking "confirm" removes the field from the `_estimated` array even if the value didn't change. This is what makes the estimated-flag system clear over time.

### `op` values for edit's change-log entries

`update | confirm | undo`. `confirm` is the no-value-change-but-removed-_estimated case.

### Refusals

- Files outside the workspace path → security guard error.
- Files that don't exist → suggest `goals` skill instead for create.
- Stale schemas → "v0.2 features require migration. Run `/coinskills:migrate` first."

## `afford` v2

### Step 0 — goal-detection heuristic (new, runs before Step 1 parse)

After parsing inputs, if ALL of these hold:
- `classification == one-off purchase`
- `deadline == none` AND `urgency == nice-to-have`
- `amount > 6 × monthly_capacity`
- `disposable < amount` (can't pay cash today)
- No active goal already matches the item (fuzzy match on title/notes)

…afford pauses and asks:

> "This looks more like a goal than a one-off decision (€{amount} is {N}× your monthly capacity, no deadline, no rush). Want to add it as a goal instead, or run the affordability check anyway?"

User picks:
- `goal` → chains to `/coinskills:goals` skill with the item pre-filled
- `afford` → continues normally to Step 1
- `cancel` → exits

### Step 4.5 — prerequisite auto-evaluation

For every active goal (especially `windfall-only`/`blocked` ones), evaluate the structured prerequisites against current state. The result is part of `snapshots/latest.json` so it's cheap to read.

```
Pass B — Goal impact (with prereq status):
  emergency-fund-6mo "Emergency fund 6mo" — prereqs: n/a — 2027-12-15 → 2028-01-12 (+28d) — minor
  mustang-dark-horse "Mustang Dark Horse" — prereqs: 2/5 met
       ✗ finish-consumer-credit not complete (active, balance €33,000)
       ✗ savings-revolut balance €1,949 < €25,500
       ○ Praven salary stable for 12 months (attestation pending — run /coinskills:edit attestation mustang-dark-horse to confirm)
       ✗ future-house-2030 not in active construction
       ✗ bridge-fund-untouched: 0mo since attestation
       Impact: none (windfall-only, gates unmet)
```

Verdict against gated goals is automatic NO with the gate list when the user is asking about the gated goal itself. Asking about something else → gated goals show `impact: none` per the funding-mode rule.

### Recognition over recall

Every goal reference in afford output uses `<title> (<id>)`:

```
Goal impact:  Emergency fund 6mo (emergency-fund-6mo) delayed 28d — minor
              Future house 2030 (future-house-2030) delayed 0d — none
```

Same convention applied to `start` and `analyze` for consistency.

### Snapshot reuse

Step 3 (compute liquidity) reads `snapshots/latest.json` first. If `stale: false`, use it. If stale or missing, recompute and write. Same for Pass B's projections — derived once, cached.

## Migration from v0.1 workspaces

### Migration skill — `/coinskills:migrate`

Idempotent, run-once-per-version. Stamps `schema_version: 2` in `profile.md` when done so it's not re-run.

### Migration steps

1. **Backup** — copy the entire workspace to `<workspace>/.backups/v1-pre-migration-<timestamp>/` (gitignored). Hard rollback path.
2. **Create `changes.jsonl`** — empty file with a single seed event: `{op: migrate, target: workspace, before: {schema_version: 1}, after: {schema_version: 2}, ...}`.
3. **Initialize `snapshots/latest.json`** — marked `stale: true` so the next read-skill recomputes from scratch.
4. **Goal frontmatter migration** — for each `goals/*.md`:
   - Add `funding_mode: monthly` as default (unless body contains "windfall" — then prompts user).
   - Add `prerequisites: []` as empty list. Migration does NOT auto-parse prose prerequisites. Instead prints: *"Goal `mustang-dark-horse` has prose prerequisites in its body. Convert to structured form now? (interactive) / later / leave as prose"* — interactive walks the user through each line and proposes a structured entry.
   - Normalize `status` to v2 enum (`active|blocked|paused|complete|retired`); old `active` stays, anything else prompted.
5. **Account `_estimated` seeding** — for each account in `accounts.json`, asks: *"Were any fields on `card-unicredit-bulbank` estimated rather than confirmed? (apr, billing_cycle_day, rewards / none / all)"*. Adds `_estimated` array accordingly. This is the explicit one-time pass that lets the user mark previously-guessed values as estimates.
6. **Schema validation pass** — runs every state file through its v2 schema. Reports violations. Does NOT auto-fix; user runs `/coinskills:edit` against flagged items.
7. **Print summary** — files touched, prereqs converted vs deferred, `_estimated` flags added, validation issues remaining.

### Skill version detection

Every read-skill checks `profile.schema_version` at start. If `1` → prints "v0.2 features require migration. Run `/coinskills:migrate` first." and exits. If `2` → proceeds. If missing entirely → assume `1` and same prompt.

### Out of scope for migration

- Automated prose-to-structured prereq parsing (interactive only).
- Currency migration.
- Module-level migrations (only `personal` is touched here).

## Open questions

None at this stage. Spec is implementation-ready.

## Summary of new artifacts

- `changes.jsonl` (workspace root)
- `snapshots/latest.json` (workspace)
- `.backups/` directory (workspace, gitignored)
- `_estimated` field on account/goal/plan objects
- `funding_mode`, `prerequisites`, `windfall_sources` frontmatter on goals
- v2 status enum on goals
- `schemas/*.schema.json` (plugin)
- `scripts/test-isolation.sh` (plugin CI)
- `/coinskills:edit` skill
- `/coinskills:migrate` skill
- `afford` Step 0 (goal-detection) + Step 4.5 (prereq auto-eval) + recognition-over-recall rendering
