---
name: plan
description: Създава или ревизира стратегия за постигане на цели — месечни вноски, ред на изплащане (snowball/avalanche), what-if сценарии. Plans reference goals by id and are versioned (v1, v2, v3 as circumstances change).
---

# Plan — Versioned Strategies for Goals

## Overview

Plans are the tactical layer on top of goals. A goal is stable: it declares *what* you want and *when* you want it. A plan is a versioned strategy: it says *how much* to contribute per month, from *which sources*, and in *what order* if multiple goals compete. Plans iterate as life changes — a raise, a new obligation, a market drop all warrant a new plan version. The old plan is marked `superseded`, never deleted. Goals are stable; plans iterate.

Locate the workspace: read `~/.coinskills-workspace` for the absolute path. If the file doesn't exist, stop and tell the user to run `/coinskills:init` first.

---

## Step 1: Select Goal(s)

Scan `goals/*.md` in the workspace. Extract frontmatter from each file. List only goals with `status: active`.

Print the active goals table:

```
| id | title | type | target | deadline | priority | latest plan |
|----|-------|------|--------|----------|----------|-------------|
| house-deposit | House deposit | savings | €50,000 | 2028-06-01 | 1 | v2 |
| emergency-fund | Emergency fund | savings | €12,000 | none | 2 | — |
```

For **latest plan version**: scan `plans/<id>-v*.md` — find the highest version number among files with `status: active`. If none exists, show `—`.

Ask the user: **"Which goal(s) do you want to plan for? (enter one id or a comma-separated list — multi-goal plans are allowed)"**

Wait for the answer. Store the selected goal id(s) as `selected_goals`. If the user names a goal not in the active list, inform them and ask again.

If `goals/` is empty or no goals have `status: active`, tell the user they have no active goals and suggest `/coinskills:goals new`.

---

## Step 2: Analyze Current State

Load the following files from the workspace:

- `profile.md` — currency, emergency_fund_months, risk_tolerance, locale, modules
- `accounts.json` — all accounts with type, balance, apr, billing_cycle_day, limit
- `modules/personal/recurring.json` — fixed recurring obligations (subscriptions, rent, utilities, loan repayments)
- `modules/personal/income.json` — income streams (salary, freelance, rental, dividends) with amounts and frequencies
- `modules/personal/transactions/YYYY-MM.md` for the **last 3 calendar months** (e.g. if today is 2026-04-27, load 2026-02, 2026-03, 2026-04)

If a file doesn't exist (e.g. transactions not yet logged), note it and proceed with the data that is available. If `income.json` is missing, ask the user for monthly income before proceeding.

**Compute monthly contribution capacity:**

```
monthly_income         = sum of all income.json streams normalised to monthly frequency
                          (weekly * 52 / 12, annual / 12, etc.)

recurring_obligations  = sum of recurring.json amounts normalised to monthly
                          (include only obligations that are NOT goal contributions)

essential_spending_baseline =
    if 3 months of transactions exist:
        avg of last 3 months' total outflows, EXCLUDING:
        - rows with category "goal-contribution"
        - rows with category "investment-buy" or "investment-sell"
        - one-off large purchases (any single row > 5x the per-category monthly average)
    else:
        recurring_obligations  (conservative fallback — note this to the user)

monthly_contribution_capacity =
    monthly_income - recurring_obligations - essential_spending_baseline
```

Print a summary:

```
Monthly income:            €{monthly_income}
Recurring obligations:     €{recurring_obligations}
Essential spending:        €{essential_spending_baseline}
---
Available for goals:       €{monthly_contribution_capacity}
```

If `monthly_contribution_capacity` is zero or negative, warn the user: "Your obligations and spending currently leave nothing for contributions. We can still model a plan — but it will show a very long timeline unless something changes." Proceed anyway; the what-if scenarios in Step 4 may surface a path forward.

---

## Step 3: Propose Contribution Schedule

For each goal in `selected_goals`, propose a monthly contribution based on goal type.

### savings / purchase / retirement

1. Compute months remaining: `(deadline - today)` in months, or ask the user for a target horizon if deadline is `none`.
2. Required monthly contribution: `(target_amount - current_saved) / months_remaining`
   - `current_saved` = sum of balances of `linked_accounts` from `accounts.json` where account type is `bank`, `savings`, or `e_money`. If no accounts are linked, ask the user for the current saved amount.
3. Compare required vs available capacity. If required > capacity, show both numbers and say: "At your current capacity you'd reach this goal in {N} months rather than {deadline}. The what-if scenarios below may help."
4. Ask: **"Which income sources should fund this goal? (e.g. salary, freelance, side-income — or just 'all')"**
5. Build a `contribution_sources` list: split the monthly amount proportionally across the named sources by their weight in `income.json`. If the user says `all`, use all streams proportionally.

Print:

```
Goal: {title}
  Monthly contribution needed:  €{required}
  Monthly contribution feasible: €{min(required, capacity)}
  Projected completion:          {date}
  Sources:
    {account}: €{amount}/month
    ...
```

### debt-payoff

For each debt account in `accounts.json` (types: `credit_card`, `loan`, `mortgage`) that is linked to this goal:

1. Collect: balance (as positive), APR, minimum payment.
2. Present two strategies and **recommend one with a brief justification**:

   - **Snowball** (smallest balance first): pays off individual debts faster, gives psychological momentum. Recommended when the user has multiple small debts and motivation is a factor, or when APRs are similar (within 3 percentage points of each other).
   - **Avalanche** (highest APR first): minimises total interest paid. Recommended when there is a significant APR spread (>3pp) — mathematically optimal. Default recommendation unless snowball criteria apply.

3. State the recommendation clearly: "I recommend **avalanche** because the APR spread between your debts is {N}pp — over {timeline} this saves you approximately €{savings} in interest compared to snowball." Or: "I recommend **snowball** because your debts have similar APRs ({range}%) and you have {N} small accounts — the quick wins will help you stay on track."

4. Under the chosen strategy, schedule payments: minimum payments on all other debts, extra capacity goes entirely to the priority debt.

Print the payment schedule:

```
Strategy: Avalanche (highest APR first)
Rationale: {rationale}

Payment order:
  1. {debt-id} — APR {apr}% — balance €{balance} — payoff by {date}
  2. {debt-id} — APR {apr}% — balance €{balance} — payoff by {date}

Monthly allocation: €{total}
  Minimums:   €{sum_minimums}
  Extra:      €{extra} → {priority-debt-id}
```

### investment

1. Ask: **"What is your target allocation? (e.g. 70% equities / 20% bonds / 10% cash — or 'from profile' to use risk_tolerance defaults)"**
   - If `from profile`: conservative → 40/40/20, moderate → 60/30/10, aggressive → 80/15/5.
2. Propose a monthly DCA (dollar-cost averaging) amount = min(required, capacity).
3. Note any allocation drift: compare current holdings in `modules/investments/holdings.json` (if module enabled) to the target. If drift > 5pp on any asset class, surface it: "Your current allocation is {actual}% equities vs target {target}% — consider rebalancing as part of this plan."

Print:

```
Goal: {title}
  Monthly DCA: €{amount}
  Target allocation: {equities}% equities / {bonds}% bonds / {cash}% cash
  Current drift: {note or "within tolerance"}
  Projected portfolio value at {deadline}: €{estimate} (assumes {rate}% annual return)
```

For the projection, use 7% annual return for equities-heavy allocations (>60% equities), 4% for balanced, 2% for conservative. State the assumption explicitly.

### Multi-goal plans

If `selected_goals` contains more than one goal, allocate `monthly_contribution_capacity` across goals weighted by priority (priority 1 gets the largest share). Print the allocation table:

```
Total available: €{capacity}
  {goal-id-1} (priority 1): €{amount1}/month
  {goal-id-2} (priority 2): €{amount2}/month
```

Ask the user: **"Does this allocation look right, or would you like to adjust the split?"** Wait for confirmation or adjustment before proceeding.

---

## Step 4: What-If Scenarios

Tell the user: "I can model three what-if scenarios. Each shows how your projected completion date changes. Run all three, pick some, or skip."

Present the options:

```
1. What if I get a 10% raise?
2. What if a recession halves my freelance income for 6 months?
3. What if I take on a new €X/month obligation?
```

For option 3, ask: **"What monthly amount for the new obligation?"** before modelling.

Ask: **"Which what-ifs would you like to see? (1, 2, 3, any combination, or 'all' / 'skip')"**

For each selected scenario, recompute `monthly_contribution_capacity` with the changed assumption and print a revised projected completion date for each goal in `selected_goals`:

**Scenario 1 — 10% raise:**
```
New monthly income:        €{monthly_income * 1.10}
New capacity:              €{new_capacity}
Revised projections:
  {goal-id}: {old_date} → {new_date} ({delta} earlier)
```

**Scenario 2 — Recession halves freelance for 6 months:**
```
Freelance income for 6 months: €{freelance * 0.5}/month (then restores)
Reduced capacity for 6mo:      €{reduced_capacity}
Normal capacity from month 7:  €{normal_capacity}
Revised projections:
  {goal-id}: {old_date} → {new_date} ({delta} later)
```

**Scenario 3 — New €X/month obligation:**
```
New obligation:            €{X}/month
New capacity:              €{capacity - X}
Revised projections:
  {goal-id}: {old_date} → {new_date} ({delta} later)
```

If there is no freelance income stream in `income.json`, for Scenario 2 substitute the largest non-salary income stream, or if all income is salary, say "You have no variable income — a recession would not change your freelance income, but job loss would. Modelling 6-month salary reduction to 50% instead." and proceed with that assumption.

---

## Step 5: Versioning

For each goal id in `selected_goals`:

1. **Find existing active plan files.** Scan `plans/{goal-id}-v*.md`. For each file found, read the `status` frontmatter field. If `status: active`, mark it `superseded`:
   - Open the file.
   - Change the frontmatter field `status: active` to `status: superseded`.
   - Save the file.
   - Note the old version number (e.g. `v2`).

2. **Determine the new version number.** Find the highest version number across ALL plan files for this goal (active, superseded, or abandoned). Increment by 1. If no prior plans exist, start at `v1`.

3. **Write the new plan file** at `plans/{goal-id}-v{N+1}.md` using this exact template:

```yaml
---
goal_ids: [house-deposit]
version: 1
created: 2026-04-27
status: active
monthly_contribution: 1400
contribution_sources:
  - {account: salary, amount: 900, frequency: monthly}
  - {account: freelance, amount: 500, frequency: monthly}
projection: on-track
---
# Strategy
Narrative: how this plan works, assumptions, what triggers a v2.
```

Fill in the fields:
- `goal_ids`: list all ids from `selected_goals`
- `version`: the new version number (integer)
- `created`: today's date (YYYY-MM-DD)
- `status: active`
- `monthly_contribution`: total monthly contribution from Step 3
- `contribution_sources`: list from Step 3, one entry per source with `account`, `amount`, `frequency`
- `projection`: `on-track` if required ≤ capacity, `behind` if required > capacity

For the `# Strategy` body, write a 2-4 sentence narrative covering:
- What the plan does (monthly amount, sources, method for debt-payoff goals)
- Key assumptions (income stability, APR assumptions, return rate for investments)
- What would trigger a revision (a raise, a new obligation, a missed contribution for 2+ months)

For **multi-goal plans** (when `selected_goals` has more than one id), write a single plan file covering all goals. Name the file using the first goal id: `plans/{first-goal-id}-v{N+1}.md`. Set `goal_ids` to the full list.

4. **Tell the user** what happened:
   - "Marked prior plan(s) as superseded: {list of filenames}"
   - "Wrote new plan: plans/{goal-id}-v{N+1}.md"

---

## Step 6: Update Goal Projection

For each goal id in `selected_goals`:

1. Read `goals/{goal-id}.md`. If not found, fall back to `goals/archive/{goal-id}.md` — archived goals can be referenced for historical display but skip the projection update (an archived goal has no live projection).
2. Check if the frontmatter contains a `projection` field. If it does, recompute it:
   - If the new plan's projected completion date ≤ deadline: set `projection: on-track`
   - If projected completion date > deadline by ≤ 3 months: set `projection: behind`
   - If projected completion date > deadline by > 3 months: set `projection: at-risk`
   - If projected completion date < deadline by ≥ 1 month: set `projection: ahead`
3. If the `projection` field does not exist in the frontmatter, add it.
4. Save the file.

Tell the user: "Updated projection for {goal-id}: {projection value}."

---

## Commit

After all files are written and goals updated, stage and commit from the workspace root:

```bash
git add goals/ plans/
git commit -m "plan: {goal-id} v{N} ({trigger reason})"
```

Where `{trigger reason}` is a short phrase describing why a new plan was created. Derive it from context:
- First plan ever → `initial`
- User mentioned a raise → `raise factored in`
- User mentioned a new obligation → `new obligation: {description}`
- User mentioned changed income → `income revised`
- Plan revised after goal edit → `goal {id} revised`
- No explicit reason given → `revised`

Examples:
- `plan: house-deposit v3 (raise factored in)`
- `plan: house-deposit v1 (initial)`
- `plan: emergency-fund v2 (new obligation: car loan)`
- `plan: house-deposit emergency-fund v2 (income revised)`

For multi-goal plans, list the goal ids space-separated before the version: `plan: {goal-id-1} {goal-id-2} v{N} ({reason})`.

---

## Self-check before finishing

Before declaring done, verify:
- Every goal in `selected_goals` has a new plan file written at `plans/{goal-id}-v{N+1}.md` with `status: active`
- All previously active plans for those goals now have `status: superseded`
- The `projection` field in each `goals/{goal-id}.md` reflects the new plan
- The commit has been run and confirmed
