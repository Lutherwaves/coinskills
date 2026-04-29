---
name: init
description: Use when setting up coinskills for the first time — profiles the user's finances, creates a private GitHub workspace repo via gh, walks through accounts/holdings/debts/income, and seeds initial goals.
---

# Init — Profile & Workspace Setup

## Overview

This skill sets up the user's personal coinskills workspace from scratch. It interviews them to capture their financial profile and preferences, creates a private GitHub repo as their workspace (so all financial state is version-controlled and private), walks through a complete financial snapshot covering cash, credit, investments, debts, obligations, and income, then seeds their first goals and optionally drafts an initial plan for each. At the end the user has a fully initialized workspace and a clear picture of where they stand relative to their goals.

## Prerequisites

Before starting, verify both tools are present and configured:

```bash
gh auth status
git config user.name
```

If `gh` is not authenticated, tell the user to run `gh auth login` and complete the browser flow before continuing. If `git config user.name` is empty, ask the user to run `git config --global user.name "Your Name"`. Do not proceed until both checks pass.

---

## Step 1: Profile Interview

Ask the user these **8 questions one at a time**. Wait for each answer before asking the next. Do not bundle questions.

1. **"What name should I use for your profile?"**

2. **"What is your primary currency? (e.g. EUR, USD, BGN)"**

3. **"Which modules do you want to enable?"**
   - A) Personal finance — income, expenses, budgets, cash flow
   - B) Investments — portfolio, holdings, allocation
   - C) Business / freelance — invoices, expenses, P&L
   (Accept any combination. Store as a list, e.g. `[personal, investments]`.)

4. **"How would you describe your risk tolerance?"** (only ask if investments module is enabled)
   - conservative
   - moderate
   - aggressive

5. **"How many months of expenses do you want to keep as an emergency buffer? (common: 3, 6, or 12)"**

   After this, also collect locale: **"What locale should I format dates and numbers in? (e.g. `en-US`, `bg-BG`, `de-DE`)"** — if the user is unsure, infer a default from currency (EUR → `en-IE`, BGN → `bg-BG`, USD → `en-US`, GBP → `en-GB`) and confirm.

5b. **"What's a rough monthly total for variable spending — groceries, dining, kids' costs, miscellaneous — EXCLUDING rent, utilities, insurance, and other fixed bills?"** Store as `variable_spending_estimate` (currency = profile.currency).

This number is critical for `afford` to compute monthly capacity before transaction history exists. The user can correct it later via `/coinskills:edit profile`. If unsure, suggest a starting point of `0.4 × monthly net income` and let them confirm.

6. **"How often do you want to do a formal financial review?"**
   - monthly
   - quarterly
   - yearly

7. **"How do you prefer financial decisions to be presented to you?"**
   - data-first — numbers up front, narrative second
   - gut-first — narrative up front, numbers to back it
   - balanced — mixed

8. **"Any free-form context I should know? (life situation, dependents, upcoming life events, constraints — or just press Enter to skip)"**

After collecting all answers, confirm a summary and ask "Does this look right?" before proceeding.

---

## Step 2: Create Workspace Repo

### 2a. Choose parent directory

Ask: **"Where should I create your workspace? (default: ~/finances/)"**

Use the user's answer, or `~/finances/` if they press Enter.

### 2b. Choose repo name

Suggest 6 fun names the user can pick from (or they can provide their own):

- `coin-vault`
- `gold-ledger`
- `wealth-forge`
- `coin-keep`
- `goldsight`
- `ledgermind`

Ask: **"Pick a repo name from the suggestions above, or type your own:"**

### 2c. Create the repo

Get the user's GitHub username:

```bash
gh api user --jq '.login'
```

Then create the private repo and clone it:

```bash
gh repo create <github-username>/<repo-name> --private --clone --add-readme
cd <parent-directory>/<repo-name>
```

If `gh repo create` fails, check:
- The user is authenticated (`gh auth status`)
- The repo name doesn't already exist under their account
- They have permission to create repos

### 2d. Initialize directory structure

Create the top-level directories that exist for all configurations:

```bash
mkdir -p goals plans snapshots reviews
```

Then create module directories **only for enabled modules**:

- If `personal` is enabled:
  ```bash
  mkdir -p modules/personal/transactions
  ```

- If `investments` is enabled:
  ```bash
  mkdir -p modules/investments/transactions
  ```

- If `business` is enabled:
  ```bash
  mkdir -p modules/business/invoices modules/business/expenses modules/business/pnl
  ```

### 2e. Write workspace `.gitignore`

Create `.gitignore` in the workspace root with this content:

```
.env
*.csv
tmp/
*.pdf
.DS_Store
*.log
```

### 2f. Write `profile.md`

Write `profile.md` using the following template, substituting the user's answers:

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
# Notes
<user's free-form context, or leave blank>
```

If investments module was not enabled, omit the `risk_tolerance` field. `locale` is always written (collected in question 5).

### 2g. Write a pointer file

Write the absolute path of the workspace to `~/.coinskills-workspace` so other skills can find it without asking:

```bash
echo "<absolute-path-to-workspace>" > ~/.coinskills-workspace
```

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

Create the directories: `mkdir -p <workspace>/snapshots <workspace>/.backups`.

---

## Step 3: Financial Snapshot Interview

**Before any write below**, resolve the workspace root and apply the path guard from `skills/_shared/path-guard.md`. Every file written in this section must be inside the workspace root.

**For every account/goal/plan/recurring/income/holding write below**, follow `skills/_shared/mutation-pipeline.md`: validate against the relevant schema in `<plugin-root>/schemas/`, append a `changes.jsonl` event, then write the file. Mark `snapshots/latest.json` stale at the end of the entire init flow (one stale-mark, not per-write — init is one logical unit).

Tell the user: "Now let's capture a snapshot of where you stand financially. I'll go through 8 categories — type **done** at any point within a category to move to the next."

Work through each category below one at a time. For each category, collect the fields listed, write the results to the specified file, and then move on.

---

### Category 1 — Liquid cash (banks, savings, e-money)

For each account, collect:
- `id` (slug, e.g. `bank-revolut-main`)
- `type`: `bank`, `savings`, or `e_money`
- `name` (display name, e.g. "Revolut Main")
- `currency`
- `balance` (current balance, positive number)
- `module`: `personal`

Append each account as an entry in **`accounts.json`** (create or extend the array).

---

### Category 2 — Credit lines (cards, overdrafts)

For each account, collect:
- `id` (slug, e.g. `card-amex-gold`)
- `type`: `credit_card`
- `name`
- `currency`
- `limit`
- `balance` (current statement balance — negative means you owe money, e.g. `-340`)
- `apr` (as a decimal, e.g. `0.219` for 21.9%)
- `billing_cycle_day` (day of month statement closes)
- `rewards` (free text, e.g. "4x dining, 2x groceries")
- `module`: `personal`

Append to **`accounts.json`**.

---

### Category 3 — Investments (only if investments module is enabled)

For each holding, collect:
- `ticker`
- `shares`
- `avg_cost` (average cost per share)
- `currency`
- `account` (broker slug, e.g. `trading212`)
- `asset_class`: `equity`, `bond`, `cash`, `crypto`, `commodity`, or `other` (used by `analyze: allocation` to compute drift vs target)

Write to **`modules/investments/holdings.json`** as a JSON array.

Also add each broker as an account entry in **`accounts.json`**:
- `type`: `broker`
- `module`: `investments`
- `balance`: approximate total value (optional at this stage)

---

### Category 4 — Other liquid assets (crypto, metals, collectibles)

For each, collect:
- `id` (slug)
- `type`: `crypto_wallet` or `other`
- `name`
- `currency`
- `balance` (approximate current value)
- `module`: `personal`

Append to **`accounts.json`**.

---

### Category 5 — Illiquid assets (real estate, vehicles, business equity)

For each, collect:
- `id` (slug)
- `type`: `real_estate`, `vehicle`, `business_equity`, or `other`
- `name`
- `currency`
- `estimated_value`
- `notes` (optional)

Write to **`assets-illiquid.json`** as a JSON array.

---

### Category 6 — Loans and debts (mortgages, personal loans, family debt)

For each, collect:
- `id` (slug)
- `type`: `mortgage`, `loan`, or `other`
- `name`
- `currency`
- `balance` (negative — amount owed, e.g. `-12000`)
- `apr` (decimal)
- `monthly_payment`
- `module`: `personal`

Append to **`accounts.json`**.

---

### Category 7 — Recurring obligations (subscriptions, fixed bills)

For each, collect:
- `id` (slug)
- `name`
- `amount` (monthly cost, positive number)
- `currency`
- `category` (e.g. `housing`, `utilities`, `subscriptions`, `insurance`, `transport`)
- `frequency`: `monthly`, `quarterly`, or `annual`
- `due_day` (day of month it's due — for monthly; for quarterly/annual, this is the day of the month it falls in)
- `last_paid` (ISO date `YYYY-MM-DD` of the last payment; if unknown, ask the user to estimate or set to one full period before today)

Write to **`modules/personal/recurring.json`** as a JSON array. If the user types `done` immediately with no obligations, write an empty array `[]` so consumers don't hit a missing-file path.

---

### Category 8 — Income streams (salary, freelance, rental, dividends)

For each, collect:
- `id` (slug)
- `type`: `salary`, `freelance`, `rental`, `dividends`, `other`
- `name`
- `amount` (net monthly amount)
- `currency`
- `frequency`: `monthly`, `quarterly`, `annual`, or `irregular`
- `account_id` (where it lands)

Write to **`modules/personal/income.json`** as a JSON array. If the user types `done` immediately with no income streams, write an empty array `[]`.

---

### Target file reference

| Category | Target file |
|---|---|
| Liquid cash | `accounts.json` |
| Credit lines | `accounts.json` |
| Investments | `modules/investments/holdings.json` + `accounts.json` |
| Other liquid assets | `accounts.json` |
| Illiquid assets | `assets-illiquid.json` |
| Loans/debts | `accounts.json` |
| Recurring obligations | `modules/personal/recurring.json` |
| Income streams | `modules/personal/income.json` |

### `accounts.json` shape

The full `accounts.json` is a JSON array. Each entry follows this structure (example):

```json
[
  {
    "id": "card-amex-gold",
    "type": "credit_card",
    "name": "Amex Gold",
    "currency": "EUR",
    "limit": 5000,
    "balance": -340,
    "apr": 0.219,
    "billing_cycle_day": 15,
    "rewards": "4x dining, 2x groceries",
    "module": "personal"
  }
]
```

Account types: `bank`, `savings`, `credit_card`, `e_money`, `broker`, `crypto_wallet`, `loan`, `mortgage`, `other`.

Fields that don't apply to a given account type (e.g. `limit` on a bank account) should be omitted.

---

## Step 4: Goals Interview

Tell the user: "Now let's set your financial goals. Tell me about each goal — I'll record them one by one. Type **done** when you've listed them all."

For each goal, collect:
- Title
- Type: `savings` | `debt-payoff` | `investment` | `retirement` | `purchase` | `custom`
- Target amount and currency
- Deadline (`YYYY-MM-DD` or `none`)
- Priority (1 = most important; auto-assign if not specified)
- Linked accounts (comma-separated ids from accounts.json)
- Why it matters (free-form — becomes the body of the goal file)

Generate an `id` from the title: kebab-case, max 30 chars (e.g. "House Deposit 2028" → `house-deposit-2028`).

Write each goal to **`goals/<id>.md`** using this template:

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

### If the user provides no goals

Suggest defaults in this priority order and ask which to adopt:

1. **Emergency fund** — 3-6 months of expenses in a savings account
2. **High-interest debt payoff** — clear any credit card or loan with APR > 10%
3. **Investment baseline** — start or increase regular investment contributions
4. **Specific savings goal** — e.g. travel, home purchase, car

For each adopted default, fill in the fields from context already collected (amounts from snapshot, linked accounts, etc.) and write the goal file.

---

## Step 5: Optional First Plan Per Goal

For each goal just created, ask: **"Would you like to draft an initial plan for '{goal title}' now, or later via /coinskills:plan? (now / later)"**

If the user chooses **now**:

1. Compute available monthly contribution capacity based on income and recurring obligations already captured:
   `monthly_capacity = sum(income.amount) − sum(recurring.amount)`

2. Ask: "Which income sources and amounts do you want to direct toward this goal each month?" — present the income streams collected in Step 3.

3. Walk through the contribution schedule and confirm the projected completion date:
   `months_to_goal = target_amount / monthly_contribution`
   `projected_date = today + months_to_goal`

4. Write **`plans/<goal-id>-v1.md`** using this template:

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

If the user chooses **later**, move on. They can run `/coinskills:plan` at any time.

---

## Step 6: Privacy Warning and Initial Commit

Before committing, display this warning verbatim:

> ⚠️ This repo will contain your real financial state. Verify it's private (`gh repo view --json visibility`). Never push to a public remote.

Then run:

```bash
gh repo view --json visibility
```

Confirm the output shows `"visibility": "PRIVATE"`. If it does not, stop and instruct the user to make the repo private before continuing:

```bash
gh repo edit --visibility private
```

Once confirmed private, stage and commit everything:

```bash
git add .
git commit -m "Initial coinskills workspace"
git push
```

If `git push` fails because no upstream is set, run:

```bash
git push -u origin main
```

---

## Step 7: Print Summary

Print a clean summary:

```
Workspace:      <absolute path>
Repo:           <github-username>/<repo-name> (private)
Modules:        <list of enabled modules>
Goals seeded:   <N> — <list of goal titles>
Plans drafted:  <N> — <list of goal ids with v1 plans>

Suggested next steps:
  /coinskills:start    — see status snapshot vs goals any time
  /coinskills:plan     — build or revise a strategy for any goal
  /coinskills:afford   — "can I afford X?" — full goal-impact decision
```

If no plans were drafted, remind the user: "Run `/coinskills:plan` when you're ready to build a contribution strategy for your goals."
