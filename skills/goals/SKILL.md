---
name: goals
description: Управление на финансови цели — създаване, редакция, преглед, приключване (achieve/abandon). Използва се за CRUD върху goals/. Goals are the spine — every other skill references them.
---

# Goals — CRUD on the Goal Spine

## Overview

Goals are the spine of coinskills. Every other skill — plan, afford, analyze, review, log — frames its output against active goals. This skill owns the full lifecycle: list what you have, create new goals, edit existing ones, mark them achieved when you cross the finish line, or abandon ones that no longer matter. All state lives in `goals/<id>.md` inside the user's workspace repo.

Locate the workspace: read `~/.coinskills-workspace` for the absolute path. If the file doesn't exist, stop and tell the user to run `/coinskills:init` first.

---

## Sub-actions

If the user invoked `/coinskills:goals` with no argument, default to **list**.

Otherwise, read the argument and dispatch:

| Input | Action |
|---|---|
| `list` (or bare `/coinskills:goals`) | List all goals |
| `new` | Interview and create a new goal |
| `edit <id>` | Edit an existing goal by id |
| `achieve <id>` | Mark a goal as achieved |
| `abandon <id>` | Mark a goal as abandoned |

If the argument doesn't match any of the above, show the table above and ask the user which action they want.

---

## list

Read every file matching `goals/*.md` in the workspace. For each file, extract the frontmatter fields: `id`, `title`, `type`, `target_amount`, `currency`, `deadline`, `priority`, `status`.

For the **latest plan version** column: scan `plans/<id>-v*.md` — find the highest version number among files with `status: active`. If no active plan exists, show `—`. If any plan exists but all are superseded/abandoned, show the latest version number with a `(superseded)` note.

Print a markdown table:

```
| id | title | type | target | deadline | priority | status | latest plan |
|----|-------|------|--------|----------|----------|--------|-------------|
| house-deposit | House deposit | savings | €50,000 | 2028-06-01 | 1 | active | v2 |
| emergency-fund | Emergency fund | savings | €12,000 | none | 2 | active | — |
```

Sort by `priority` ascending (1 = most important first). Group: active goals first, then paused, then achieved/abandoned.

If `goals/` is empty or the directory doesn't exist, tell the user they have no goals yet and suggest running `/coinskills:goals new`.

---

## new

Interview the user with these **7 questions, one at a time**. Wait for each answer before asking the next.

1. **"What's the goal title?"**

2. **"What type? (savings | debt-payoff | investment | retirement | purchase | custom)"**

3. **"Target amount and currency?"**

4. **"Deadline (YYYY-MM-DD or 'none')?"**

5. **"Priority (1 = most important)?"**

6. **"Which accounts are linked? (comma-separated ids from accounts.json)"**

6b. **Funding mode:** "Will this goal be funded from monthly contributions (`monthly`), only from windfalls like bonuses or equity vests (`windfall-only`), or both (`hybrid`)?"

6c. **Windfall sources** (only if mode != monthly): "List the windfall sources that should fund this goal — comma-separated. Examples: annual-bonus, equity-vest, severance-overflow, side-income."

6d. **Prerequisites** (optional, defer if user is unsure): "Does this goal have hard prerequisites that must be met before it can complete or be drawn down? Examples: another goal must be done first, an account must reach a balance, a stable-income period must be confirmed. (yes / no / later)"

   On yes, walk through prereq creation: for each prereq, ask which type (goal-complete / account-balance / attestation / time-since), then collect the type-specific fields from `schemas/goal.schema.json`.

   On no/later, set `prerequisites: []`.

7. **"Why does this matter? (free-form, becomes the body)"**

### Generate the id

Convert the title to kebab-case, strip special characters, truncate to 30 characters. Examples:
- "House Deposit 2028" → `house-deposit-2028`
- "Pay off Amex Gold" → `pay-off-amex-gold`
- "Retire at 55" → `retire-at-55`

If the generated id already exists in `goals/`, append `-2` (or increment until unique).

### Parse target amount and currency

If the user gives "50000 EUR" or "€50,000", extract `target_amount: 50000` and `currency: EUR`. If currency is omitted, use `profile.currency` from `profile.md`.

### Write `goals/<id>.md`

**Before writing**, apply path guard from `skills/_shared/path-guard.md` and follow the mutation pipeline from `skills/_shared/mutation-pipeline.md`. Validate the frontmatter against `schemas/goal.schema.json` before writing. Append a `changes.jsonl` event with `op: create` and `target: "goals/<id>.md"`. Mark snapshot stale.

Use this exact template, substituting the user's answers:

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

Set `created` to today's date (`YYYY-MM-DD`). Set `status: active`. The body under `# Why` is the user's answer to question 7.

### Check for active plans

After writing the file, scan `plans/*.md` for any file with `status: active`. If any exist, prompt:

> "This new goal may compete with active plans. Run /coinskills:plan to revise?"

This is just a prompt — do not auto-execute `/coinskills:plan`.

### Commit

```
goals: new goal {id} ({target_amount} {currency} by {deadline})
```

Example: `goals: new goal house-deposit (50000 EUR by 2028-06-01)`

If deadline is `none`: `goals: new goal {id} ({target_amount} {currency} no deadline)`

---

## edit

Load `goals/<id>.md`. If the file doesn't exist, list available goal ids (from `goals/*.md`) and ask the user to pick one.

Display the current values of all frontmatter fields. Then ask:

**"Which fields do you want to change? (list field names, e.g. 'deadline, priority' — or 'body' to edit the Why section)"**

For each field named, ask for the new value. Leave all other fields unchanged.

Rewrite the file with the updated values. Preserve the `id` and `created` fields exactly — never change them during an edit.

If the user changes `target_amount`, `deadline`, or `type`, append a note to the `# Why` body:

```
_Edited {YYYY-MM-DD}: {field} changed from {old} to {new}._
```

### Commit

```
goals: edit {id}
```

---

## achieve

Load `goals/<id>.md`. If the file doesn't exist, list available ids and ask the user to pick one.

Confirm: **"Mark '{title}' as achieved? This will supersede all linked active plans. (y/n)"**

If confirmed:

1. Set `status: achieved` in the frontmatter.
2. Append to the body (after the existing `# Why` content):

```
## Achieved
Date: {YYYY-MM-DD}
```

3. Find all plan files in `plans/` where `goal_ids` includes this goal's id AND `status: active`. For each, set `status: superseded` and save the file.

4. If any plans were superseded, tell the user: "Marked N plan(s) as superseded: {list of plan filenames}."

### Commit

```
goals: achieved {id}
```

---

## abandon

Load `goals/<id>.md`. If the file doesn't exist, list available ids and ask the user to pick one.

Ask: **"Why are you abandoning '{title}'? (free-form — this gets appended to the goal file)"**

After the user answers:

1. Set `status: abandoned` in the frontmatter.
2. Append to the body:

```
## Abandoned
Date: {YYYY-MM-DD}
Reason: {user's reason}
```

3. Find all plan files in `plans/` where `goal_ids` includes this goal's id AND `status: active`. For each, set `status: superseded` and save. Inform the user how many plans were superseded.

### Commit

```
goals: abandoned {id}
```

---

## Commit message reference

| Sub-action | Commit message template |
|---|---|
| new | `goals: new goal {id} ({target_amount} {currency} by {deadline})` |
| edit | `goals: edit {id}` |
| achieve | `goals: achieved {id}` |
| abandon | `goals: abandoned {id}` |

Run `git add goals/ plans/` before committing (plans may be modified by achieve/abandon). Run `git commit -m "{message}"` from the workspace root.
