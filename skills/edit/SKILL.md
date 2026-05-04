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
   Editing account 'card-bank-a':
     1. id              card-bank-a   (immutable)
     2. type            credit_card
     3. name            Bank A
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
