---
name: review
description: Периодичен преглед — месечен/тримесечен/годишен доклад. Use at period close or whenever the user asks for a financial report ("monthly review", "how did Q1 go", "year in review", "месечен отчет"). Goal progress is the top section; transactions come second.
---

# Review — Periodic Goal-First Report

## Overview

`review` synthesizes a complete picture of a closed period: where you stand against your goals, how money moved, what your net worth did, where spending went, and what to change. It is the one skill that connects every data source — transactions, holdings, goals, plans, and prior decisions — into a single narrative. Every review starts with goal progress (the mission) before touching any financial mechanics. The output is a permanent markdown file in `reviews/` and a commit to the workspace repo.

Locate the workspace: read `~/.coinskills-workspace` for the absolute path. If the file doesn't exist, stop and tell the user to run `/coinskills:init` first.

---

## Step 0: Schema version gate

**Schema version gate.** Read `<workspace>/profile.md` frontmatter. If `schema_version != 2` (or absent), print:

> v0.2 features require migration. Run `/coinskills:migrate` first.

Exit. Do NOT proceed.

**Load aggregate state via snapshot.** Follow `skills/_shared/snapshot-compute.md`. The snapshot provides `liquidity` (disposable, emergency_buffer, monthly_expenses, monthly_capacity), per-goal `prereqs_met` and `projected_completion`, and `warnings` (every `_estimated` field). Use these values directly — do not recompute unless the snapshot is stale.

**Goal references in output:** always render as `<title> (<id>)`. Example: `Emergency fund 6mo (emergency-fund-6mo)`. Never bare ids.

## Step 1: Determine Period

Ask the user which period to review:

> "Which period should I review? (e.g. 2026-04, Q1 2026, 2025, or just say 'this month')"

**Defaults and overdue detection:**

1. Read `profile.preferences.review_cadence` from `profile.md`. Valid values: `monthly`, `quarterly`, `yearly`. Default to `monthly` if the field is absent.
2. List all files in `reviews/` to find the most recent completed review.
3. Compute when the next review was due:
   - `monthly`: due on the 1st of the month following the last reviewed month.
   - `quarterly`: due on the 1st of the month following the last reviewed quarter.
   - `yearly`: due on January 1st of the year following the last reviewed year.
4. If today ≥ due date and the user has not specified a period, default to the overdue period and tell the user: "Your last review was {last_period}. Defaulting to {overdue_period} — say a different period to override."
5. If no prior review exists and the user says "this month" or gives no period, default to the current calendar month.

**Period label format:**
- Monthly: `YYYY-MM` (e.g. `2026-04`)
- Quarterly: `YYYY-QN` (e.g. `2026-Q1`)
- Yearly: `YYYY` (e.g. `2025`)

**Output file:** `reviews/<period>.md` (e.g. `reviews/2026-04.md`, `reviews/2026-Q1.md`, `reviews/2025.md`)

If the file already exists, print: "A review for {period} already exists at reviews/{period}.md. Overwrite? (y/n)" — wait for confirmation before proceeding.

---

## Step 2: Aggregate Data

Load all data for the period. Read `profile.md` first to know which modules are enabled.

**Always load:**
- `profile.md`
- `goals/*.md` — all files with `status: active` (and any achieved/abandoned during the period)
- `plans/*.md` — all files with `status: active` or `status: superseded` during the period
- `accounts.json`

**Load by period type (all modules that are enabled in `profile.modules`):**

For a **monthly** review covering `YYYY-MM`:
- `modules/personal/transactions/YYYY-MM.md` (if personal module enabled)
- `modules/investments/transactions/YYYY-MM.md` (if investments module enabled)
- `modules/business/expenses/YYYY-MM.md` (if business module enabled)
- `modules/investments/holdings.json` (if investments module enabled)

For a **quarterly** review covering `YYYY-QN` (months M1, M2, M3):
- All three monthly transaction files for each enabled module.
- `modules/investments/holdings.json`

For a **yearly** review covering `YYYY`:
- All 12 monthly transaction files for each enabled module.
- `modules/investments/holdings.json`

**Afford-decisions:** For monthly reviews, read the `## afford-decisions` section from `reviews/YYYY-MM.md` if it already exists (the `afford` skill appends there). For quarterly/yearly reviews, read that section from each month in the period.

If a transaction file is missing for a month within the period, note it: "No transaction data found for {YYYY-MM} — that month is excluded from totals."

---

## Step 3: Compute Deltas vs Prior Cycle

Compute all metrics for both the review period and the prior comparable period, then derive deltas.

**Determining the prior period:**

| Review period | Prior comparable period |
|---|---|
| Monthly: `YYYY-MM` | Previous calendar month |
| Quarterly: `YYYY-QN` | Previous quarter (Q1 → Q4 of prior year, Q2 → Q1, etc.) |
| Yearly: `YYYY` | `YYYY-1` (e.g. 2026 → 2025) |

**Finding period-start and period-end balances:**

1. First, look for a snapshot in `snapshots/net-worth.json` whose `date` is the first day of the review period (period-start) and last day of the review period (period-end). Use those values if present.
2. If no snapshot exists for the period start, use git history:
   ```bash
   git log --all --format="%H %ai" -- accounts.json
   ```
   Find the commit closest to (but not after) the period-start date. Then:
   ```bash
   git show <commit-hash>:accounts.json
   ```
   Sum the balances from that historical `accounts.json` to get period-start liquid balances. Note: "Period-start balance sourced from git history ({commit_hash})."
3. If no git history exists for `accounts.json` (e.g. first-ever review), use the current `accounts.json` balances and note: "No historical balance data — net worth delta cannot be computed for this period."
4. Period-end balances: use current `accounts.json`.

**Metrics to compute for both periods:**

- **Inflows**: sum of all positive-amount transaction rows across all enabled modules.
- **Outflows**: sum of absolute values of all negative-amount transaction rows.
- **Net cash flow**: Inflows − Outflows.
- **Net worth (end)**: `sum(positive balances in accounts.json) + sum(shares * avg_cost in holdings.json) - sum(|negative balances| in accounts.json)`. (Use `avg_cost` as price proxy; note this clearly.)
- **Net worth (start)**: derived from git history or snapshot as above.
- **Spending by category**: sum of outflows grouped by `category` field from transaction rows.
- **Goal progress per goal**: current value of linked accounts vs target_amount (same logic as `analyze:goal-progress`).
- **Holdings change** (investments module only): compare `holdings.json` at period start (from git history) vs current. Compute allocation drift per asset class.

**Delta notation:**
- Absolute: `+€500` or `−€200`
- Percentage: `+4.2%` or `−1.8%`
- Always show both for net worth.
- For spending categories, show absolute delta vs prior period.
- For goal progress, show % complete now vs % complete at period start.

---

## Step 4: Build Report

Write the report to `reviews/<period>.md`. Use **exactly** the section order below — do not reorder, add, or remove sections. All 9 sections are required.

```markdown
# Review — {period label}

## 🎯 Goal progress
{per goal: current/target, % complete, days to deadline, on-track/behind/ahead}

## 💰 Cash flow
{inflows, outflows, net, vs prior period delta}

## 📊 Net worth
{start, end, delta absolute and %}

## 🛒 Spending breakdown
{top 5 categories with totals + delta vs prior period}

## 📈 Investments (if module enabled)
{holdings change, allocation drift vs target}

## ✅ Wins
{2-4 wins inferred from data}

## ⚠️ Concerns
{1-3 concerns: overspend categories, behind-pace goals, missed contributions}

## 🧭 Recommendations
{2-4 concrete actions tied to specific goals/skills}

## 🔄 Afford-decisions logged this period
{list from `## afford-decisions` sections of monthly review files}
```

**Section-by-section instructions:**

### `## 🎯 Goal progress`

This is always the first section. For each active goal (plus any achieved or abandoned during the period):

```
**{goal title}** ({goal id})
  Target:     {currency} {target_amount}
  Current:    {currency} {current_value}  ({pct_complete}% complete)
  Deadline:   {deadline}  ({days_remaining} days remaining)
  Plan:       {plan version}, {projection field or computed projection}
  Status:     on-track | behind {N}d | ahead {N}d | no-plan | achieved | abandoned
```

If a goal was achieved or abandoned during the period, include it with a note: "(achieved {date})" or "(abandoned {date})".

If `days_remaining` is negative (deadline passed), show: "OVERDUE by {|days_remaining|} days".

### `## 💰 Cash flow`

```
Inflows:   {currency} {inflows}
Outflows:  {currency} {outflows}
Net:       {currency} {net}  ({delta_vs_prior} vs {prior_period_label})
```

If the net is negative, add a one-line note: "Negative cash flow — outflows exceeded inflows by {currency} {|net|}."

### `## 📊 Net worth`

```
Start ({period_start_date}):  {currency} {start_nw}
End   ({period_end_date}):    {currency} {end_nw}
Delta:  {delta_absolute}  ({delta_pct}%)
```

If net worth data for the start is unavailable, write: "Period-start net worth unavailable — delta cannot be computed." and show only the end value.

### `## 🛒 Spending breakdown`

Top 5 categories by total outflow for the period (largest first):

```
| Category    | Total     | vs prior period |
|-------------|-----------|-----------------|
| groceries   | €420      | +€38  (+9.9%)   |
| dining      | €195      | −€22  (−10.1%)  |
| transport   | €88       | +€5   (+6.0%)   |
| ...         | ...       | ...             |
```

Flag any category with `|delta| > 20%` as notable with "(notable)".

If fewer than 5 categories exist in the data, show all available categories.

### `## 📈 Investments (if module enabled)`

Only include this section if `investments` is in `profile.modules`. If the module is not enabled, write: "Investments module not enabled."

```
Holdings change:
  {ticker}:  {shares_start} → {shares_end} shares  (avg cost {avg_cost} {currency})

Allocation (end of period):
  {asset_class}:  {pct}%  (target: {target_pct}%,  drift: {drift_pct}%)
```

If no target allocation is defined in any active plan, skip the target/drift columns and note: "No target allocation defined — set one via /coinskills:plan."

If holdings data at period start is unavailable from git history, note: "Period-start holdings unavailable — showing end-of-period snapshot only."

### `## ✅ Wins`

Infer 2–4 concrete wins from the data. Do not fabricate — every win must be directly supported by the numbers. Sources of wins:
- Net cash flow was positive and above the prior period.
- A goal reached a milestone (e.g. crossed 25%, 50%, 75%).
- Net worth increased.
- A category's spending decreased significantly (> 10% down).
- A goal was achieved.
- Monthly contribution matched or exceeded the plan target.

Format as a bullet list. Be specific with numbers:

```
- Net cash flow of +€510, up +€360 vs March — best month in the period.
- house-deposit crossed 40% complete (was 36.8% at start of period).
- Dining spending down 10.1% vs prior period.
```

### `## ⚠️ Concerns`

List 1–3 concerns. Do not pad with invented concerns — only raise issues clearly supported by data. Sources of concerns:
- A category with notable overspend (|delta| > 20% or absolute > 30% of monthly disposable).
- A goal tagged `behind` by more than 2 weeks.
- Missed plan contribution (actual contributions to linked accounts < plan.monthly_contribution).
- Net cash flow negative.
- Net worth decreased.
- No transactions logged for the period (data gap).

Format as a bullet list with specifics:

```
- Groceries up 9.9% MoM (€420 vs €382) — not yet alarming but watch the trend.
- house-deposit contributions (€800) are €600 below the plan v2 target (€1,400/month).
```

If there are no concerns, write: "No significant concerns this period."

### `## 🧭 Recommendations`

List 2–4 concrete, actionable recommendations. Each must reference a specific goal or skill. No generic advice.

Examples:
- "Increase monthly contribution to house-deposit by €200 to get back on plan v2 — run `/coinskills:plan` to revise the contribution schedule."
- "Groceries spend is trending up — set a €380/month soft cap and log every transaction via `/coinskills:log`."
- "Allocation drift: equities at 78% vs 70% target — consider rebalancing, use `/coinskills:analyze allocation` to see full breakdown."
- "Emergency fund is at 4.2 months — below your 6-month target. Redirect €150/month from discretionary until it's covered."

### `## 🔄 Afford-decisions logged this period`

For each month in the period, read the `## afford-decisions` section from `reviews/YYYY-MM.md` (these are appended there by `/coinskills:afford`). Aggregate all entries into a flat list.

Format:
```
- {date} — {item}: {verdict} via {method} (Goal impact: {tag})
- {date} — {item}: {verdict} — not purchased
```

If no afford-decisions were logged, write: "No afford-decisions logged this period."

---

## Step 5: Commit

After writing the file, commit from the workspace root:

```bash
git add reviews/<period>.md
git commit -m "review: {period}"
```

Examples:
```
review: 2026-04
review: 2026-Q1
review: 2025
```

If `git commit` fails, print the error and tell the user: "Commit failed. The review file has been written to reviews/{period}.md — commit manually when ready."

---

## Self-check Before Finishing

Before declaring done, verify:

- `reviews/<period>.md` exists and contains all 9 sections in exact order: 🎯 Goal progress → 💰 Cash flow → 📊 Net worth → 🛒 Spending breakdown → 📈 Investments → ✅ Wins → ⚠️ Concerns → 🧭 Recommendations → 🔄 Afford-decisions.
- Goal progress is the first section — never move it.
- Every delta is shown as both absolute and percentage where applicable.
- Prior-period comparison is for the correct cycle (month-before for monthly, Q4-prior for Q1, etc.).
- Git history was used (or attempted) for period-start balances when no snapshot exists.
- Wins and Concerns are each supported by specific numbers from the data — no generic statements.
- Recommendations each name a specific goal id or skill command.
- The commit message is exactly `review: {period}`.
