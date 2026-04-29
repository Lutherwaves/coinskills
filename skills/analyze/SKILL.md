---
name: analyze
description: Анализ на финансовото състояние спрямо целите — тенденции в харчене, нетна стойност, разпределение, паричен поток. Triggered by "how am I doing", "where do I spend the most", "what's my allocation", "как се справям", "къде харча най-много", "каква е алокацията ми".
---

# Analyze — Goal-Framed Financial Analysis

## Overview

`analyze` answers financial questions about your current state — spending trends, net worth, portfolio allocation, cash flow, and goal progress — always framed against your active goals. A raw number without goal context is useless; every output from this skill includes at least one sentence connecting the finding to where you stand on a goal. The skill reads your workspace data, computes the requested view using concrete formulas, and optionally writes a timestamped snapshot to `snapshots/` for trend tracking.

Locate the workspace: read `~/.coinskills-workspace` for the absolute path. If the file doesn't exist, stop and tell the user to run `/coinskills:init` first.

---

## Step 0: Schema version gate

**Schema version gate.** Read `<workspace>/profile.md` frontmatter. If `schema_version != 2` (or absent), print:

> v0.2 features require migration. Run `/coinskills:migrate` first.

Exit. Do NOT proceed.

**Load aggregate state via snapshot.** Follow `skills/_shared/snapshot-compute.md`. The snapshot provides `liquidity` (disposable, emergency_buffer, monthly_expenses, monthly_capacity), per-goal `prereqs_met` and `projected_completion`, and `warnings` (every `_estimated` field). Use these values directly — do not recompute unless the snapshot is stale.

**Goal references in output:** always render as `<title> (<id>)`. Example: `Emergency fund 6mo (emergency-fund-6mo)`. Never bare ids.

## Step 1: Identify the Question

Classify the user's request into exactly one of these views:

| View | Triggers |
|---|---|
| **spending-trends** | "where do I spend", "how much did I spend on X", "am I overspending", "харча ли прекалено", "къде харча най-много" |
| **net-worth** | "what's my net worth", "how much am I worth", "колко струвам", "нетна стойност" |
| **allocation** | "what's my allocation", "how is my portfolio split", "каква е алокацията ми", "portfolio breakdown" |
| **cash-flow** | "how am I doing", "how is my cash flow", "inflows vs outflows", "как се справям", "паричен поток" |
| **goal-progress** | "how are my goals", "am I on track", "goal status", "цели", "напредък" |
| **custom** | Anything that doesn't fit cleanly into the above |

If the user's question maps to **custom**, ask: "Can you tell me more about what you want to analyze? (e.g. a specific account, date range, category, or comparison)"

Wait for scope clarification before loading data. Once scoped, map to the closest standard view or treat as a filtered variant of one.

Print the classification before continuing:

```
View: {view}
```

---

## Step 2: Load Relevant Data

Read only what the view requires. Do not load the entire workspace blindly.

**Always load:**
- `profile.md` — currency, modules, emergency_fund_months
- `goals/*.md` — all files with `status: active`
- `plans/*.md` — all files with `status: active` (to read projections and contribution schedules)

**Load by view:**

| View | Additional files to load |
|---|---|
| spending-trends | `modules/personal/transactions/` — last 4 months (current + 3 prior) |
| net-worth | `accounts.json`, `assets-illiquid.json` (if present), `modules/investments/holdings.json` (if investments module enabled) |
| allocation | `modules/investments/holdings.json`, `accounts.json` (investment-type accounts only) |
| cash-flow | `modules/personal/transactions/` — last 6 months; `modules/business/expenses/` (if business module enabled) |
| goal-progress | `accounts.json` (linked accounts per goal), latest `snapshots/net-worth.json` (if present) |
| custom | Determined by scoped question |

If a required file is missing (e.g. `modules/investments/holdings.json` but investments module is enabled), note the gap and continue with available data: "Holdings file not found — investment values excluded from calculation."

---

## Step 3: Compute

Apply the exact formula for the classified view.

### spending-trends

1. Parse all transaction rows from the last 4 months of `modules/personal/transactions/YYYY-MM.md`.
2. Group outflows (negative amounts) by `category`, by `YYYY-MM`.
3. For each category, compute:
   - **Last month total** = sum of that category for the most recent completed month.
   - **3-month average** = sum of that category over the 3 months prior to last month, divided by 3.
   - **MoM delta** = `(last_month - 3mo_avg) / 3mo_avg * 100` (as %).
4. Sort categories by last-month total (largest absolute outflow first).
5. Present as a table:

```
Category       | Last month | 3-mo avg | Delta
groceries      |    €380    |   €340   | +11.8%
dining         |    €210    |   €195   |  +7.7%
transport      |     €90    |   €105   | -14.3%
```

6. Flag any category with `|delta| > 20%` as notable.

### net-worth

Compute using:

```
net_worth = sum(positive balances across all accounts in accounts.json)
          + sum(holding.shares * holding.last_known_price for each holding in holdings.json)
          - sum(|balance| for accounts where balance < 0)
          + sum(estimated_value for each entry in assets-illiquid.json)
```

Notes:
- `last_known_price` is not fetched live. Use `avg_cost` from `holdings.json` as the price if no `last_known_price` field exists — note this clearly: "Using avg cost as price proxy (no live price available)."
- If `assets-illiquid.json` is absent, omit the illiquid term and note it.
- Present a breakdown by component (liquid cash / investments / illiquid / debts).

### allocation

1. Load `modules/investments/holdings.json`.
2. Compute total investment value: `sum(shares * last_known_price)` per holding (use `avg_cost` if no live price). If any holding falls back to `avg_cost`, print the caveat once at the top of the output: `Using avg cost as price proxy (no live price available).`
3. Group by ticker and by asset class (use a field `asset_class` if present on the holding; otherwise default to `equity` and note in the output that the default was applied).
4. Express each holding and each class as `%` of the total investment value.
5. Present both groupings:

```
By ticker:
  VWCE    120 shares × €112.40 = €13,488  →  68.4%
  ...

By asset class:
  equity    78.2%
  bonds      8.1%
  cash      13.7%
```

### cash-flow

1. Parse all transaction rows from the last 6 months.
2. For each month, compute:
   - **Inflows** = sum of positive amounts
   - **Outflows** = sum of absolute values of negative amounts
   - **Net** = Inflows − Outflows
3. Present a 6-row table, most recent month first:

```
Month    | Inflows | Outflows |   Net
2026-04  |  €3,400 |   €2,890 |  +€510
2026-03  |  €3,200 |   €3,050 |  +€150
...
```

4. Compute 6-month average net. Flag any month where net < 0 as a concern.

### goal-progress

For each active goal in `goals/*.md`:

1. Find the linked accounts from `linked_accounts`.
2. Compute `current_value` = sum of balances across linked accounts (positive only).
3. Load the active plan for this goal (if any) from `plans/<goal-id>-v*.md` with `status: active`.
4. Compute:
   - `pct_complete = current_value / target_amount * 100`
   - `days_remaining = (deadline - today)` in days (if deadline is not `none`)
   - `plan_projection` = read from plan's `projection` field; if absent, compute: `months_to_go = (target_amount - current_value) / plan.monthly_contribution`; compare to `days_remaining / 30`
5. Present per goal:

```
Goal: house-deposit
  Progress:   €18,400 / €50,000  (36.8%)
  Deadline:   2028-06-01  (762 days remaining)
  Plan:       v2, on-track — projected completion 2028-04 (2 months early)
```

---

## Step 4: Frame Against Goals (Mandatory)

Every output must include at least one sentence explicitly connecting the computed finding to goal progress. This is not optional — a number without goal context is incomplete.

**How to frame:**

- For spending-trends: identify which categories are consuming money that could go toward goal contributions. Connect to any plan that assumes a specific monthly contribution.
- For net-worth: compare to the sum of all active goal `target_amount` values to show aggregate coverage.
- For allocation: check if the allocation % for each asset class matches any targets stated in active plans or goals. Flag drift.
- For cash-flow: compare monthly net to required monthly contribution capacity across all active plans.
- For goal-progress: the framing is already built into the computation — make it explicit in the summary sentence.

**Examples of mandatory goal-framing sentences:**

> "Spending up 12% MoM, this puts Goal A 3 weeks behind plan v2."

> "Allocation drift to 78% equities exceeds the 70% target in your retirement goal — consider rebalancing."

Additional framing examples by view:

> "Net cash flow of +€150 in March is below the €400/month required across your two active plans — house-deposit and emergency fund fall further behind."

> "Net worth of €47,200 covers 56% of your combined active goal targets (€84,000). At the current savings rate, you reach full coverage in approximately 31 months."

Write the goal-framing section last, after the view's computed table/numbers, under a heading:

```
## Goal Impact
```

---

## Step 5: Optionally Write Snapshot

For the **net-worth** and **allocation** views, offer to write a snapshot after presenting results:

> "Write a snapshot to `snapshots/{view}.json` for trend tracking? (y/n)"

If yes (or if the user already indicated they want a snapshot):

1. Determine the snapshot file path: `{workspace_root}/snapshots/{view}.json` where `{view}` is `net-worth` or `allocation`.
2. If the file does not exist, create it with an empty JSON array: `[]`.
3. Append this entry to the array:

```json
{"date": "YYYY-MM-DD", "value": <computed_value>, "breakdown": {<key_value_pairs>}}
```

Concrete shapes by view:

**net-worth snapshot:**
```json
{
  "date": "2026-04-27",
  "value": 47200,
  "breakdown": {
    "liquid_cash": 12400,
    "investments": 28600,
    "illiquid": 9000,
    "debts": -2800
  }
}
```

**allocation snapshot:**
```json
{
  "date": "2026-04-27",
  "value": 28600,
  "breakdown": {
    "equity": 0.782,
    "bonds": 0.081,
    "cash": 0.137
  }
}
```

4. Write the updated array back to the file. Preserve all prior entries — append only.
5. Print: `Snapshot written to snapshots/{view}.json`

For other views (spending-trends, cash-flow, goal-progress), do not write a snapshot unless the user explicitly asks. If asked, use a shape that matches the view's output structure.

---

## Step 6: Commit (Only if Snapshot Written)

If and only if a snapshot was written in Step 5, commit from the workspace root:

```bash
git add snapshots/{view}.json
git commit -m "analyze: {view} snapshot {YYYY-MM-DD}"
```

Examples:
```
analyze: net-worth snapshot 2026-04-27
analyze: allocation snapshot 2026-04-27
```

If no snapshot was written, do not commit. The `analyze` skill is read-only unless a snapshot is explicitly written.

If `git commit` fails, print the error and tell the user: "Commit failed. The snapshot file has been updated — commit manually when ready."

---

## Self-check Before Finishing

Before declaring done, verify:

- The view was classified and printed.
- All 5 standard view formulas use the correct inputs (right files, right sign conventions, right date ranges).
- The Goal Impact section is present and contains at least one sentence connecting the finding to an active goal.
- If a snapshot was written: the JSON entry has `date`, `value`, and `breakdown` fields; the existing entries in the file were preserved.
- A commit was made if and only if a snapshot was written.
