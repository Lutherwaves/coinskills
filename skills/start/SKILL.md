---
name: start
description: Главно меню на coinskills — статус спрямо целите, налични инструменти. Използва се при стартиране на нова сесия с coinskills.
---

# Start — Status Snapshot & Main Menu

## Overview

This skill is the front door to coinskills. Every session begins here. It locates your workspace, loads your profile and active goals, computes net worth against the latest snapshot, and renders a concise status block so you can see at a glance where you stand. It then suggests the most relevant next action based on the state of your goals and review cadence — no manual navigation required. After rendering the status block and suggestion, it waits for your input.

---

## Step 1: Locate the Workspace

Read the file `~/.coinskills-workspace`. This file is a plain text file or symlink written by `/coinskills:init` containing the absolute path to the user's workspace repo (one line, no trailing newline required).

```bash
cat ~/.coinskills-workspace
```

- If the file exists and contains a valid path, store that path as `<workspace>` and proceed.
- If the file does not exist, or the path it contains does not exist on disk, stop and display:

  > No coinskills workspace found. Run `/coinskills:init` to set one up — it will create your profile, a private GitHub repo, and seed your first goals.

  Do not proceed further.

- If the file exists but the path is a directory that has no `profile.md`, treat it as uninitialized and display the same message above.

---

## Step 2: Load Profile and Active Goals

Read the following files from `<workspace>`:

1. **`<workspace>/profile.md`** — parse the YAML frontmatter to extract:
   - `name`
   - `currency`
   - `modules` (list)
   - `preferences.review_cadence` (`monthly` | `quarterly` | `yearly`)
   - `preferences.decision_style`

2. **`<workspace>/goals/*.md`** — list all `.md` files in the `goals/` directory. For each file, parse the YAML frontmatter and keep only the files where `status: active`. For each active goal, extract:
   - `id`
   - `title`
   - `type`
   - `target_amount`
   - `currency`
   - `deadline`
   - `priority`

3. **Latest snapshot (if present)** — look for files in `<workspace>/snapshots/`. The relevant snapshot for the status block is a net-worth snapshot. Look for `snapshots/net-worth.json` or any file in `snapshots/` whose name contains `net-worth`. If found, parse the JSON array and take the last entry (highest index). Extract:
   - `date` → store as `<snapshot_date>`
   - `value` → store as `<snapshot_net_worth>`
   - `breakdown` → optional, used for display

   If no snapshot exists, `<snapshot_net_worth>` and `<snapshot_date>` are `null`.

4. **`<workspace>/accounts.json`** — read the JSON array. Compute current net worth:
   ```
   net_worth = sum(balance for all accounts)
   ```
   Positive balances add, negative balances (debts/credit cards) subtract. This is the current net worth.

5. **Delta** — if `<snapshot_net_worth>` is not null:
   ```
   delta = net_worth - snapshot_net_worth
   ```
   Format as `+{amount}` if positive, `-{amount}` if negative, `0` if zero.
   If no prior snapshot exists, display `Δ n/a (first session)`.

6. **Latest plan per active goal** — for each active goal with `id = <goal-id>`, look for files matching `<workspace>/plans/<goal-id>-v*.md`. Find the file with the highest version number. Parse its frontmatter to get:
   - `monthly_contribution`
   - `projection` (`on-track` | `behind` | `ahead`)
   - `status` — only use the plan if `status: active`

   If no active plan file exists for a goal, that goal has no plan.

7. **Progress per active goal** — for each active goal, compute `progress` as:
   - If the goal has `linked_accounts`, sum their balances from `accounts.json`. Use this as `progress`.
   - If no linked accounts are specified, `progress` is unknown — display as `?`.

8. **`status_tag` per active goal** — compute using the following rules:
   - If there is no active plan for this goal → `no-plan`
   - If plan's `projection` is `on-track` → `on-track`
   - If plan's `projection` is `behind`:
     - Compute days behind: estimate based on gap between current progress and where the plan says you should be by now. If the exact gap is not computable from available data, display `behind ?d`.
     - Display as `behind {N}d`
   - If plan's `projection` is `ahead` → `ahead {N}d` (same approach for N)
   - If you cannot determine days from the data, use `behind ?d` or `ahead ?d` rather than failing.

9. **Last review date** — list files in `<workspace>/reviews/*.md`. Recognise three filename shapes written by `/coinskills:review`: monthly `YYYY-MM.md`, quarterly `YYYY-QN.md` (N is 1–4), yearly `YYYY.md`. Parse the date from the filename (use the first day of the month / quarter / year as the comparison anchor) and pick the most recent. If no review files exist, `<last_review_date>` is `null`.

---

## Step 3: Render Status Block

Print the following status block exactly, substituting the values gathered in Step 2. Preserve the emoji characters, indentation, and line structure precisely:

```
👋 Hi {name}
📊 Net worth: {currency} {amount} (Δ {delta} vs last snapshot)
🎯 Active goals:
   • {title} — {progress}/{target} ({status_tag})
📦 Modules: {modules}
```

Rules for substitution:

- `{name}` — value of `name` from `profile.md`
- `{currency}` — value of `currency` from `profile.md`
- `{amount}` — `net_worth`, formatted as a number with two decimal places (e.g. `12450.00`). If `accounts.json` does not exist or is empty, display `unknown`.
- `{delta}` — formatted delta computed in Step 2 (e.g. `+340.00`, `-120.50`, `n/a (first session)`)
- `{title}` — goal title from goal frontmatter
- `{progress}` — computed progress value (numeric, or `?` if unknown)
- `{target}` — `target_amount` from goal frontmatter
- `{status_tag}` — one of: `on-track`, `behind {N}d`, `ahead {N}d`, `no-plan`
- `{modules}` — comma-separated list from `profile.modules` (e.g. `personal, investments`)

If there are multiple active goals, repeat the `• {title} — ...` line once per goal, sorted by `priority` ascending (priority 1 first).

If there are no active goals, replace the entire `🎯 Active goals:` section with:

```
🎯 Active goals: none
```

---

## Step 4: Suggest Next Action

After the status block, print one blank line, then suggest the next action based on the following rules in priority order. Apply the first matching rule:

**Rule 1 — No active goals:**
```
No goals yet. Run `/coinskills:goals` to set your first financial goal — goals are the spine of every skill.
```

**Rule 2 — Active goals without plans:**
Identify any active goal that has no active plan file (i.e. no `plans/<goal-id>-v*.md` with `status: active`).
```
Goal "{title}" has no plan yet. Run `/coinskills:plan` to build a contribution strategy.
```
If multiple goals lack plans, list only the highest-priority one (lowest `priority` number).

**Rule 3 — Overdue review:**
Compare `<last_review_date>` against today's date using `review_cadence`:
- `monthly` → overdue if `<last_review_date>` is more than 31 days ago (or null)
- `quarterly` → overdue if more than 92 days ago (or null)
- `yearly` → overdue if more than 366 days ago (or null)

If overdue:
```
Your last review was {N} days ago (cadence: {review_cadence}). Run `/coinskills:review` when you're ready.
```
If `<last_review_date>` is null, display: "No reviews recorded yet. Run `/coinskills:review` at period end."

**Rule 4 — Everything looks good — list all options:**
```
Everything looks on track. What would you like to do?

  /coinskills:log              — log a transaction or balance update
  /coinskills:afford <thing>   — "can I afford X?" — full goal-impact decision
  /coinskills:analyze          — spending trends, net worth, allocation
  /coinskills:review           — periodic review (monthly / quarterly / yearly)
```

---

## Step 5: Wait for Input

After rendering the status block and the next-action suggestion, stop and wait for the user's next message.

**Do not auto-execute any other skill.** Do not chain to `/coinskills:goals`, `/coinskills:plan`, `/coinskills:review`, or any other skill unless the user explicitly asks. The status block is informational — the next action is a suggestion, not a command.

If the user responds with a skill invocation (e.g. `/coinskills:log`, `/coinskills:afford ...`), proceed with that skill. If the user types free-form text, respond conversationally and help them decide what to do next, but still do not auto-execute a skill without their explicit request.
