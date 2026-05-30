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
| `achieve <id>` | Mark a goal as achieved (auto-archives) |
| `abandon <id>` | Mark a goal as abandoned (auto-archives) |
| `unarchive <id>` | Restore an archived goal back to active state |

If the argument doesn't match any of the above, show the table above and ask the user which action they want.

---

## list

Read every file matching `goals/*.md` in the workspace (non-recursive — this excludes `goals/archive/`). For each file, extract the frontmatter fields: `id`, `title`, `type`, `target_amount`, `currency`, `deadline`, `priority`, `status`.

If the user passed `--all` (i.e. `/coinskills:goals list --all`), also include files from `goals/archive/*.md` and add a final section to the output for archived goals.

For the **latest plan version** column: scan `plans/<id>-v*.md` — find the highest version number among files with `status: active`. If no active plan exists, show `—`. If any plan exists but all are superseded/abandoned, show the latest version number with a `(superseded)` note.

Print a markdown table:

```
| id | title | type | target | deadline | priority | status | latest plan |
|----|-------|------|--------|----------|----------|--------|-------------|
| house-deposit | House deposit | savings | €50,000 | 2028-06-01 | 1 | active | v2 |
| emergency-fund | Emergency fund | savings | €12,000 | none | 2 | active | — |
```

Sort by `priority` ascending (1 = most important first). Group active goals first, then paused. Archived (achieved/abandoned) goals only appear when `--all` is passed, in a separate table below labeled `### Archive`.

If `goals/` is empty or the directory doesn't exist, tell the user they have no goals yet and suggest running `/coinskills:goals new`.

### Goal id resolution

For all sub-actions below that take an `<id>` argument (`edit`, `achieve`, `abandon`, `unarchive`), resolve the file by checking:

1. `goals/<id>.md` (active/paused goal)
2. `goals/archive/<id>.md` (archived goal)

If neither exists, list available ids from both locations and ask the user to pick one. `unarchive` only operates on files in `goals/archive/`; reject otherwise. `achieve`/`abandon` only operate on files in `goals/` top-level; reject if the goal is already archived.

---

## new

Interview the user with these **7 questions, one at a time**. Wait for each answer before asking the next.

1. **"What's the goal title?"**

2. **"What type? (savings | debt-payoff | investment | retirement | purchase | custom)"**

3. **"Target amount and currency?"**

4. **"Deadline (YYYY-MM-DD or 'none')?"**

5. **"Priority (1 = most important)?"**

6. **"Which accounts are linked? (comma-separated ids from accounts.json)"**

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

Use this exact template, substituting the user's answers:

```yaml
---
id: house-deposit
title: House deposit
type: savings
target_amount: 50000
currency: EUR
deadline: 2028-06-01
priority: 1
status: active
linked_accounts: [savings-revolut, investments-trading212]
created: 2026-04-27
---
# Why
Why this matters. Constraints. What "done" looks like beyond the number.
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

Load `goals/<id>.md`. If the file doesn't exist in `goals/` top-level (e.g. already archived), tell the user and stop.

Confirm: **"Mark '{title}' as achieved? This will supersede all linked active plans and move the goal to goals/archive/. (y/n)"**

If confirmed:

1. Set `status: achieved` in the frontmatter.
2. Append to the body (after the existing `# Why` content):

```
## Achieved
Date: {YYYY-MM-DD}
```

3. Find all plan files in `plans/` where `goal_ids` includes this goal's id AND `status: active`. For each, set `status: superseded` and save the file.

4. **Archive**: create `goals/archive/` if it doesn't exist, then move the file from `goals/<id>.md` to `goals/archive/<id>.md` (use `git mv` so history is preserved).

5. If any plans were superseded, tell the user: "Marked N plan(s) as superseded: {list of plan filenames}."

### Commit

```
goals: achieved {id}
```

---

## abandon

Load `goals/<id>.md`. If the file doesn't exist in `goals/` top-level (e.g. already archived), tell the user and stop.

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

4. **Archive**: create `goals/archive/` if it doesn't exist, then `git mv goals/<id>.md goals/archive/<id>.md`.

### Commit

```
goals: abandoned {id}
```

---

## unarchive

Load `goals/archive/<id>.md`. If the file doesn't exist there, list ids in `goals/archive/` and ask the user to pick one.

Confirm: **"Restore '{title}' from archive? Status will reset to active. (y/n)"**

If confirmed:

1. Set `status: active` in the frontmatter.
2. Append to the body:

```
## Unarchived
Date: {YYYY-MM-DD}
```

3. `git mv goals/archive/<id>.md goals/<id>.md`.
4. Suggest: "Run /coinskills:plan to build a fresh plan for {id}." (Don't auto-execute.)

### Commit

```
goals: unarchived {id}
```

---

## Commit message reference

| Sub-action | Commit message template |
|---|---|
| new | `goals: new goal {id} ({target_amount} {currency} by {deadline})` |
| edit | `goals: edit {id}` |
| achieve | `goals: achieved {id}` |
| abandon | `goals: abandoned {id}` |
| unarchive | `goals: unarchived {id}` |

Run `git add goals/ plans/` before committing (plans may be modified by achieve/abandon; `git mv` already stages the rename). Run `git commit -m "{message}"` from the workspace root.
