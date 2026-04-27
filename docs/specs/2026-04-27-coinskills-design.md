# coinskills — Design

**Date:** 2026-04-27
**Status:** Approved (pending implementation plan)
**Author:** Martin Yankov (martin@yankovs.com)

## Summary

`coinskills` is a Claude Code plugin that turns Claude into a personal financial advisor. Architecture: an `init` skill builds a user profile and creates a private git repo as the user's financial workspace, then domain skills operate on that workspace ad-hoc.

The plugin is goal-centric: every analysis, plan, decision, and review is framed against the user's active financial goals. The killer skill is `/coinskills:afford`, which auto-triggers on natural-language affordability questions and recommends whether/how to finance a purchase, with full goal-impact accounting.

No external accounting software (no beancount/hledger). Pure markdown + JSON, with Claude as the analysis engine.

## Scope

**In scope (v1)**
- Personal finance, investments, and small-business / freelance financials — modular, opt-in.
- Goal-centric workflow: define goals, build plans, track progress, decide affordability against them.
- Affordability decisions with auto-trigger.
- Ad-hoc transaction logging, periodic reviews, on-demand analysis.

**Out of scope (v1, deferred)**
- `/coinskills:import` (statement parsing — brittle, defer to v2)
- Tax calculation / capital gains reporting
- Multi-user / household profiles
- Real-time price fetching for holdings
- Encryption at rest beyond GitHub private-repo guarantees

## Architecture

### Plugin repo (`coinskills`, what users install)

```
coinskills/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── skills/
│   ├── init/SKILL.md
│   ├── start/SKILL.md
│   ├── goals/SKILL.md
│   ├── plan/SKILL.md
│   ├── afford/SKILL.md
│   ├── log/SKILL.md
│   ├── analyze/SKILL.md
│   └── review/SKILL.md
├── docs/
│   └── specs/
├── README.md
└── LICENSE
```

Each `SKILL.md` uses YAML frontmatter (`name`, `description`) + a body that tells Claude how to execute. The `description` field is the trigger — `afford`'s description is crafted to match natural-language affordability questions.

No code, no runtime. All logic is Claude reading/writing the user's workspace repo.

### User workspace repo (created by `init`, hybrid layout — Approach C)

```
workspace/
├── profile.md                      # who, modules, preferences, schema_version
├── goals/                          # one .md per goal (cross-cutting)
├── plans/                          # versioned strategies; reference goal-ids
├── snapshots/                      # auto-generated JSON time-series
├── accounts.json                   # cards, banks, credit lines (cross-cutting)
├── assets-illiquid.json            # real estate, vehicles, equity
├── reviews/                        # YYYY-MM-review.md, etc.
├── .gitignore                      # ignores .env, raw .csv, tmp/, *.pdf
└── modules/
    ├── personal/
    │   ├── transactions/YYYY-MM.md
    │   ├── recurring.json
    │   └── income.json
    ├── investments/
    │   ├── holdings.json
    │   └── transactions/YYYY-MM.md
    └── business/
        ├── invoices/
        ├── expenses/YYYY-MM.md
        └── pnl/
```

Goals, plans, profile, accounts, and snapshots are top-level because they cut across modules. Domain data lives in `modules/<m>/` and only exists for enabled modules.

## Data schemas

### `profile.md`
```yaml
---
name: Martin
created: 2026-04-27
schema_version: 1
modules: [personal, investments]      # subset of {personal, investments, business}
currency: EUR
locale: bg-BG
risk_tolerance: moderate              # conservative | moderate | aggressive
emergency_fund_months: 6
preferences:
  review_cadence: monthly
  decision_style: data-first          # data-first | gut-first | balanced
---
# Notes
Free-form context (life situation, dependents, upcoming events).
```

### `goals/<id>.md`
```yaml
---
id: house-deposit
title: House deposit
type: savings                         # savings | debt-payoff | investment | retirement | purchase | custom
target_amount: 50000
currency: EUR
deadline: 2028-06-01
priority: 1
status: active                        # active | paused | achieved | abandoned
linked_accounts: [savings-revolut, investments-trading212]
created: 2026-04-27
---
# Why
Why this matters. Constraints. What "done" looks like beyond the number.
```

### `plans/<goal-id>-vN.md`
```yaml
---
goal_ids: [house-deposit]
version: 1
created: 2026-04-27
status: active                        # active | superseded | abandoned
monthly_contribution: 1400
contribution_sources:
  - {account: salary, amount: 900, frequency: monthly}
  - {account: freelance, amount: 500, frequency: monthly}
projection: on-track                  # on-track | behind | ahead
---
# Strategy
Narrative: how this plan works, assumptions, what triggers a v2.
```

### `accounts.json`
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

### `modules/personal/transactions/YYYY-MM.md`
```markdown
| date       | amount | account            | category   | note               |
|------------|--------|--------------------|------------|---------------------|
| 2026-04-03 | -42.50 | card-amex-gold     | groceries  | Lidl                |
| 2026-04-05 |  3200  | bank-revolut-main  | salary     | April salary        |
```

### `modules/investments/holdings.json`
```json
[
  {"ticker": "VWCE", "shares": 120, "avg_cost": 105.40, "currency": "EUR", "account": "trading212"}
]
```

### `snapshots/`
Auto-generated by `analyze` and `review`. JSON time-series — net worth, allocation, goal progress per period. Never hand-edited; regenerated on demand.

## Skills

### `init`
Profile interview → workspace repo → financial snapshot interview → seed goals → optional first plan → initial commit.

**Steps:**
1. Verify `gh auth status` and `git config user.name`. Bail with instructions if missing.
2. Profile interview (one question at a time): name, currency, modules, risk tolerance (if investments), emergency fund months, review cadence, decision style, free-form context.
3. Create private workspace repo. Suggest 3 fun names (`coin-vault`, `gold-ledger`, `wealth-forge`). Run `gh repo create <user>/<name> --private --clone --add-readme`. Initialize directory structure for enabled modules only.
4. **Financial snapshot interview** — walk these categories, "type done when finished":
   - Liquid cash (banks, savings, e-money)
   - Credit lines (cards, overdrafts) with limits, balances, APR, billing cycle, rewards
   - Investments (per holding: ticker, broker, shares, avg cost) — if module enabled
   - Other liquid assets (crypto, metals, collectibles)
   - Illiquid assets (real estate, vehicles, business equity)
   - Loans/debts beyond cards (mortgages, personal loans, family debt)
   - Recurring obligations (subscriptions, fixed bills)
   - Income streams (salary, freelance, rental, dividends)
5. Goals interview — collect 1-N goals; if none, suggest defaults (emergency fund → debt payoff → investment → specific savings).
6. Optional first plan per goal.
7. Warn user about sensitivity, confirm private, initial commit + push.

### `start`
*Description:* Главно меню на coinskills — статус спрямо целите, налични инструменти. Използва се при стартиране на нова сесия.

Reads profile + active goals + latest snapshot. Prints status: net worth, goal progress, modules enabled, suggested next actions.

### `goals`
*Description:* Управление на финансови цели — създаване, редакция, преглед, приключване. Използва се за CRUD върху goals/.

Sub-actions: list / new / edit / achieve / abandon. New: interview for type, target, deadline, priority, linked accounts. Writes `goals/<id>.md`. Surfaces impact on existing plans.

### `plan`
*Description:* Създава или ревизира стратегия за постигане на цели — месечни вноски, ред на изплащане, what-if сценарии. Използва се след поставяне на цели.

Select goal(s) → analyze current state → propose contribution schedule + sources → optionally what-if (raise, new debt, market drop). Writes `plans/<goal-id>-vN.md`, marks prior plan `superseded`.

### `afford`
*Description:* Решава дали потребителят може да си позволи покупка/разход/разсрочване. Използва се автоматично при въпроси като "мога ли да си позволя X", "should I buy Y", "how should I finance Z", "can I afford", "трябва ли да купя". Препоръчва карта/сметка/план и обяснява влиянието върху целите.

**Algorithm:**

1. **Parse the ask** — amount, currency, item, frequency (one-off vs recurring), urgency, deadline.
2. **Load workspace state** — profile, accounts, all goals, active plans, recurring, income, last 3 months of transactions, holdings.
3. **Compute true available liquidity:**
   ```
   monthly_expenses    = avg of last 3 months' total outflows from
                          modules/personal/transactions/, excluding
                          one-off categories (e.g. goal contributions,
                          large purchases flagged at log-time)
   liquid_cash         = sum(bank/savings/e_money balances)
   emergency_buffer    = monthly_expenses * profile.emergency_fund_months
   disposable          = liquid_cash - emergency_buffer
                          - sum(recurring obligations due in next 30d)
                          - sum(card balances whose statement closes
                                within next 30d)
   credit_headroom     = sum(card.limit - |card.balance|) per card
   ```
   If fewer than 3 months of transactions exist, fall back to the
   sum of `recurring.json` + a user-confirmed estimate captured at
   `init` time.
4. **Classify the ask:** one-off purchase / recurring commitment / financing decision / liquidation question.
5. **Three-pass evaluation:**
   - *Pass A — hard affordability:* affordable from cash, affordable with credit, or not without liquidation/breaking buffer.
   - *Pass B — goal impact:* per active goal+plan, recompute monthly contribution capacity, project new completion date, tag impact (none / minor <1mo / material 1-3mo / severe >3mo).
   - *Pass C — payment method ranking* (only if affordable): for each viable method (card, bank, installment, liquidation): cost score (interest + opportunity cost), reward score (cashback/points by category match), cashflow fit (billing cycle vs next income), risk score (utilization, lock-in). Rank by `(reward - cost) * cashflow_fit - risk_penalty`.
6. **Render decision** in a fixed shape:
   - Verdict: YES / YES-WITH-CAVEATS / NO
   - Why: liquidity, goal impact, cashflow
   - If YES: recommended payment method + alternatives, with reward/cost numbers
   - If NO: what would change the answer (wait until X, reduce goal Y, liquidate Z)
   - Action: confirm to log decision, append to current month's review under "afford-decisions".
7. **Optional log chain** — if user confirms purchase, chain to `/log`.

Tone driven by `profile.preferences.decision_style`.

### `log`
*Description:* Бързо вписване на транзакция, доход или промяна в баланс. Използва се ad-hoc при харчене, получаване на пари, или корекция на сметка.

Parse free-form ("платих 42 в Lidl", "received 3200 salary") → identify account, category, amount → append row to `modules/<m>/transactions/YYYY-MM.md` → update `accounts.json` balance → commit. For transactions >10% of monthly disposable, prompt: "this looks significant — should we revisit any goal/plan?"

### `analyze`
*Description:* Анализ на финансовото състояние спрямо целите — тенденции в харчене, нетна стойност, разпределение, паричен поток. Използва се при въпроси за "как се справям", "къде харча най-много", "каква е алокацията ми".

Read transactions + holdings + goals + plans → compute requested view → frame against goal progress ("Spending up 12% MoM, this puts Goal A 3 weeks behind plan v2") → optionally write to `snapshots/`.

### `review`
*Description:* Периодичен преглед — месечен/тримесечен/годишен доклад. Използва се при затваряне на период или при заявка за отчет.

Aggregate period transactions → compute deltas → goal progress per goal → wins/concerns → recommendations → write `reviews/<period>.md` + commit. Goal progress is the top section; transactions/spending come second.

## Cross-cutting concerns

### Privacy & sensitivity
- Workspace repo is **always private** — `init` enforces `--private` and refuses to proceed otherwise.
- No account numbers, no card PANs, no credentials anywhere. Account `id` is a slug.
- `init` warns user explicitly before first commit.
- `.gitignore` template ships in workspace seed: `.env`, raw `*.csv`, `tmp/`, `*.pdf`.

### Git workflow inside workspace
- Every state-mutating skill commits at end with a structured message:
  - `log: +€3200 salary 2026-04-05`
  - `goals: new goal house-deposit (€50k by 2028-06)`
  - `plan: house-deposit v2 (raise factored in)`
  - `afford: decided YES on espresso machine, paid via card-amex-gold`
- Push is **opt-in per session** — Claude asks at session end, never automatic.
- `review` walks git history to diff current state against same period last cycle.

### Goal-centric coupling (the rule)
Every output-producing skill MUST frame results against active goals:
- `analyze` — never just "you spent X"; always tied to goal contribution capacity.
- `afford` — already enforced.
- `review` — top section is goal-progress; transactions come second.
- `log` — large transactions prompt goal/plan revisit.

This is what makes coinskills different from a budgeting app.

### Module gating
Every skill reads `profile.modules` first. If a skill needs a disabled module, it offers to enable it and seed data.

### Versioning
- Plugin uses semver in `plugin.json`, starts at `0.1.0`.
- Workspace has `schema_version` in `profile.md` frontmatter for future migrations.

## Open questions

None at design time. Implementation plan will surface any.

## Next step

Hand off to a step-by-step implementation plan.
