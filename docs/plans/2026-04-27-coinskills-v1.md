# coinskills v1 Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `coinskills` v1 — a Claude Code plugin with 8 markdown skills (init, start, goals, plan, afford, log, analyze, review): profile + private workspace repo + ad-hoc skills, all goal-centric.

**Architecture:** Pure markdown plugin. No runtime code. Each skill is a `SKILL.md` file with YAML frontmatter (`name`, `description`) and a body that instructs Claude how to execute. Plugin metadata in `.claude-plugin/`. Spec is the source of truth for skill content — this plan tells the engineer exactly which files to create, what frontmatter to use, and which spec sections to draw the body from. A small `validate.sh` script confirms every SKILL.md is well-formed.

**Tech Stack:** Markdown + YAML frontmatter. `gh` CLI for repo creation (referenced inside `init` skill, not a build dependency). `bash` + `awk`/`grep` for validation script.

**Spec reference:** `docs/specs/2026-04-27-coinskills-design.md` — every skill task below references concrete sections of this file for body content. Engineer must read the spec before starting Task 2.

**Working directory:** `/home/blox-master/business/lutherwaves/coinskills`

---

## File structure

After this plan completes, the repo will contain:

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
│   ├── specs/2026-04-27-coinskills-design.md  (already exists)
│   └── plans/2026-04-27-coinskills-v1.md      (this file)
├── scripts/validate.sh
├── README.md
├── LICENSE
└── .gitignore
```

Each `SKILL.md` is self-contained — body must be complete instructions for Claude, not pointers to other files. Engineer copies the relevant spec section into the body and adapts.

---

### Task 1: Plugin scaffolding

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `LICENSE` (MIT)
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Write `.claude-plugin/plugin.json`**

```json
{
  "name": "coinskills",
  "description": "Goal-centric financial superpowers for Claude Code — profile your finances, set goals, build plans, decide affordability, log transactions, analyze and review. Modular: personal, investments, business.",
  "version": "0.1.0",
  "author": {
    "name": "Lutherwaves"
  },
  "homepage": "https://github.com/Lutherwaves/coinskills",
  "repository": "https://github.com/Lutherwaves/coinskills",
  "license": "MIT",
  "keywords": [
    "finance",
    "personal-finance",
    "budgeting",
    "investments",
    "goals",
    "affordability",
    "skills"
  ]
}
```

- [ ] **Step 2: Write `.claude-plugin/marketplace.json`**

Use the canonical marketplace structure:

```json
{
  "plugins": [
    {
      "name": "coinskills",
      "source": ".",
      "description": "Goal-centric financial superpowers for Claude Code"
    }
  ]
}
```

- [ ] **Step 3: Write `LICENSE`**

Standard MIT license, copyright holder `Lutherwaves`, year `2026`. Use the canonical MIT text from `https://opensource.org/license/mit`.

- [ ] **Step 4: Write `.gitignore`**

```
.DS_Store
*.log
node_modules/
.env
.env.local
tmp/
.idea/
.vscode/
```

- [ ] **Step 5: Write `README.md`**

```markdown
# coinskills

Goal-centric financial superpowers for Claude Code. Profile your finances, set goals, build plans, decide affordability — all in your own private git repo.

## Install

```bash
# Step 1: Add the marketplace
/plugin marketplace add Lutherwaves/coinskills

# Step 2: Install the plugin
/plugin install coinskills@Lutherwaves-coinskills
```

## Skills

- `/coinskills:init` — Profile + create private workspace repo + seed goals
- `/coinskills:start` — Status snapshot vs goals, main menu
- `/coinskills:goals` — Create, edit, retire goals
- `/coinskills:plan` — Build or revise strategy for a goal
- `/coinskills:afford` — Auto-triggers on "can I afford X" — full goal-impact decision
- `/coinskills:log` — Quick ad-hoc transaction / income / balance entry
- `/coinskills:analyze` — Spending, net worth, allocation — framed against goals
- `/coinskills:review` — Periodic review (monthly/quarterly/yearly)

## Modules (opt-in)

- **Personal finance** — income, expenses, budgets, cash flow
- **Investments** — portfolio, allocation, holdings
- **Business / freelance** — invoices, expenses, P&L

## Privacy

Your workspace repo is **always private**. No account numbers, no PANs, no credentials are ever stored.

## Design

See `docs/specs/2026-04-27-coinskills-design.md`.
```

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/ LICENSE .gitignore README.md
git commit -m "scaffold: coinskills plugin metadata, license, readme"
```

---

### Task 2: `init` skill

**Files:**
- Create: `skills/init/SKILL.md`

Spec source: design doc §"Skills" → `init` subsection (steps 1-7), plus §"Data schemas" for the file shapes the skill writes.

- [ ] **Step 1: Write `skills/init/SKILL.md`**

Frontmatter:

```yaml
---
name: init
description: Use when setting up coinskills for the first time — profiles the user's finances, creates a private GitHub workspace repo via gh, walks through accounts/holdings/debts/income, and seeds initial goals.
---
```

Body must be complete step-by-step instructions matching the spec's `init` subsection. Required sections in the body, in order:

1. **Overview** — one paragraph summarizing what init does.
2. **Prerequisites** — verify `gh auth status` and `git config user.name`. Bail with instructions if missing.
3. **Step 1: Profile interview** — list the 8 questions verbatim from spec §init step 2. One-at-a-time emphasis.
4. **Step 2: Create workspace repo** — exact commands:
   - Ask for parent directory (default `~/finances/`)
   - Suggest 3 fun names based on profile (give 6 example names: `coin-vault`, `gold-ledger`, `wealth-forge`, `coin-keep`, `goldsight`, `ledgermind`)
   - Run `gh repo create <user>/<name> --private --clone --add-readme`
   - Initialize directory structure per design doc §Architecture (only `modules/<m>/` for enabled modules)
   - Write `.gitignore` matching the spec
5. **Step 3: Financial snapshot interview** — list all 8 categories (liquid cash, credit lines, investments, other liquid assets, illiquid assets, loans/debts, recurring obligations, income streams) with exact fields to capture per spec §init step 4. For each, write to the corresponding JSON file as defined in §Data schemas.
6. **Step 4: Goals interview** — collect 1-N goals; if none provided, suggest defaults in priority order: emergency fund → high-interest debt payoff → investment baseline → specific savings goals. Write `goals/<id>.md` per spec schema.
7. **Step 5: Optional first plan** — for each goal ask "draft plan now or later via /plan?". If now, walk monthly contribution sources, write `plans/<goal-id>-v1.md`.
8. **Step 6: Privacy warning + initial commit** — show explicit warning text:
   > ⚠️ This repo will contain your real financial state. Verify it's private (`gh repo view --json visibility`). Never push to a public remote.
   Then `git add . && git commit -m "Initial coinskills workspace" && git push`.
9. **Step 7: Print summary** — workspace path, modules enabled, goals seeded, suggested next steps (`/coinskills:start`, `/coinskills:plan`, `/coinskills:afford`).

Body must include verbatim YAML/JSON templates for `profile.md`, `accounts.json`, `goals/<id>.md`, `plans/<goal-id>-v1.md` so Claude can produce them without re-reading the spec. Copy these templates directly from design doc §Data schemas.

- [ ] **Step 2: Commit**

```bash
git add skills/init/SKILL.md
git commit -m "feat(skills): add init — profile + workspace repo + financial snapshot"
```

---

### Task 3: `start` skill

**Files:**
- Create: `skills/start/SKILL.md`

Spec source: design doc §Skills → `start` subsection.

- [ ] **Step 1: Write `skills/start/SKILL.md`**

Frontmatter:

```yaml
---
name: start
description: Главно меню на coinskills — статус спрямо целите, налични инструменти. Използва се при стартиране на нова сесия с coinskills.
---
```

Body sections:

1. **Overview** — one paragraph: shows status snapshot and points the user to the right skill.
2. **Step 1: Locate the workspace** — read `~/.coinskills-workspace` symlink/file written by `init`, or prompt user for path; if not initialized, suggest `/coinskills:init`.
3. **Step 2: Load profile and active goals** — read `profile.md`, list all `goals/*.md` with `status: active`, read latest snapshot if present.
4. **Step 3: Render status block** — exact format:
   ```
   👋 Hi {name}
   📊 Net worth: {currency} {amount} (Δ {delta} vs last snapshot)
   🎯 Active goals:
      • {title} — {progress}/{target} ({status_tag})
   📦 Modules: {modules}
   ```
   Where `status_tag` is one of `on-track`, `behind {N}d`, `ahead {N}d`, `no-plan`.
5. **Step 4: Suggest next action** based on simple rules:
   - No goals → `/coinskills:goals`
   - Goals without plans → `/coinskills:plan`
   - Last review > review_cadence → `/coinskills:review`
   - Otherwise list all skills: `/log`, `/afford <thing>`, `/analyze`, `/review`
6. **Step 5: Wait for next user input** — do not auto-execute another skill.

- [ ] **Step 2: Commit**

```bash
git add skills/start/SKILL.md
git commit -m "feat(skills): add start — status snapshot vs goals"
```

---

### Task 4: `goals` skill

**Files:**
- Create: `skills/goals/SKILL.md`

Spec source: design doc §Skills → `goals` subsection, plus §Data schemas → `goals/<id>.md`.

- [ ] **Step 1: Write `skills/goals/SKILL.md`**

Frontmatter:

```yaml
---
name: goals
description: Управление на финансови цели — създаване, редакция, преглед, приключване (achieve/abandon). Използва се за CRUD върху goals/. Goals are the spine — every other skill references them.
---
```

Body sections:

1. **Overview** — goals are the spine; this skill is CRUD on them.
2. **Sub-actions** — ask user which: `list` / `new` / `edit <id>` / `achieve <id>` / `abandon <id>`. Default to `list` if input is just `/coinskills:goals`.
3. **list** — print table: id, title, type, target, deadline, priority, status, latest plan version (read from `plans/<id>-v*.md`).
4. **new** — interview verbatim:
   - "What's the goal title?"
   - "What type? (savings | debt-payoff | investment | retirement | purchase | custom)"
   - "Target amount and currency?"
   - "Deadline (YYYY-MM-DD or 'none')?"
   - "Priority (1 = most important)?"
   - "Which accounts are linked? (comma-separated ids from accounts.json)"
   - "Why does this matter? (free-form, becomes the body)"
   - Generate slug-id from title (kebab-case, ≤30 chars)
   - Write `goals/<id>.md` using exact template from spec §Data schemas
   - If active plans exist, prompt: "This new goal may compete with active plans. Run /coinskills:plan to revise?"
5. **edit** — load `goals/<id>.md`, ask which fields to change, rewrite file preserving unchanged fields.
6. **achieve** — set `status: achieved`, append achieved date to body, mark all linked active plans as `superseded`.
7. **abandon** — set `status: abandoned`, ask for reason (append to body).
8. **End-of-skill commit** with structured message:
   - new: `goals: new goal {id} ({target} {currency} by {deadline})`
   - edit: `goals: edit {id}`
   - achieve: `goals: achieved {id}`
   - abandon: `goals: abandoned {id}`

Embed the verbatim YAML template from spec §Data schemas → `goals/<id>.md` in the body.

- [ ] **Step 2: Commit**

```bash
git add skills/goals/SKILL.md
git commit -m "feat(skills): add goals — CRUD on the goal spine"
```

---

### Task 5: `plan` skill

**Files:**
- Create: `skills/plan/SKILL.md`

Spec source: design doc §Skills → `plan` subsection, plus §Data schemas → `plans/<goal-id>-vN.md`.

- [ ] **Step 1: Write `skills/plan/SKILL.md`**

Frontmatter:

```yaml
---
name: plan
description: Създава или ревизира стратегия за постигане на цели — месечни вноски, ред на изплащане (snowball/avalanche), what-if сценарии. Plans reference goals by id and are versioned (v1, v2, v3 as circumstances change).
---
```

Body sections:

1. **Overview** — plans are versioned strategies; goals are stable, plans iterate.
2. **Step 1: Select goal(s)** — list active goals from `goals/*.md` (`status: active`). User picks one or more (multi-goal plans allowed).
3. **Step 2: Analyze current state** — load profile, accounts, recurring, income, last 3 months of transactions. Compute available monthly contribution capacity = monthly_income − recurring obligations − essential spending baseline.
4. **Step 3: Propose contribution schedule** — based on goal type:
   - `savings` / `purchase` / `retirement`: monthly contribution from one or more sources (salary, freelance, side income).
   - `debt-payoff`: choose snowball (smallest balance first) or avalanche (highest APR first), justify the choice.
   - `investment`: monthly DCA amount + target allocation hooks.
5. **Step 4: What-if scenarios** — offer 3 optional what-ifs:
   - "What if I get a 10% raise?"
   - "What if a recession halves my freelance income for 6 months?"
   - "What if I take on a €X new obligation?"
   Each prints a revised projected completion date.
6. **Step 5: Versioning** — find existing `plans/<goal-id>-v*.md` files with `status: active`, mark them `superseded`, increment version, write new `plans/<goal-id>-v{N+1}.md` using exact template from spec.
7. **Step 6: Update goal projection** — read `goals/<goal-id>.md`, recompute `projection` field if present, save.
8. **End-of-skill commit:** `plan: {goal-id} v{N} ({trigger reason})`.

Embed verbatim YAML template from spec for `plans/<goal-id>-vN.md`.

- [ ] **Step 2: Commit**

```bash
git add skills/plan/SKILL.md
git commit -m "feat(skills): add plan — versioned strategies for goals"
```

---

### Task 6: `afford` skill (the killer)

**Files:**
- Create: `skills/afford/SKILL.md`

Spec source: design doc §Skills → `afford` subsection (full algorithm, 7 steps).

This is the largest, most important skill. Body must reproduce the full algorithm verbatim — Claude needs every detail at runtime.

- [ ] **Step 1: Write `skills/afford/SKILL.md`**

Frontmatter (CRITICAL — these phrases trigger the auto-match):

```yaml
---
name: afford
description: Решава дали потребителят може да си позволи покупка/разход/разсрочване. Auto-triggered by natural language — use whenever the user asks "can I afford X", "should I buy Y", "how should I finance Z", "can I afford this", "трябва ли да купя", "мога ли да си позволя", "should I take this loan", "is this a good purchase". Recommends payment method (card/account/installments/liquidation) and explains impact on every active goal.
---
```

Body sections (copy directly from spec §afford, expanded):

1. **Overview** — the killer skill: financial decisions framed against goals.
2. **Step 1: Parse the ask** — extract amount, currency, item/purpose, frequency (one-off vs recurring), urgency (must-have vs nice-to-have), deadline if any. Ask the user clarifying questions if any are missing.
3. **Step 2: Load workspace state** — exact files: `profile.md`, `accounts.json`, all `goals/*.md` with `status: active`, all `plans/*.md` with `status: active`, `modules/personal/recurring.json`, `modules/personal/income.json`, last 3 monthly transaction files, `modules/investments/holdings.json` (if module enabled).
4. **Step 3: Compute liquidity** — copy verbatim from spec §afford step 3 (the full code block including monthly_expenses derivation, fallback for cold-start workspaces).
5. **Step 4: Classify the ask** — one-off purchase | recurring commitment | financing decision | liquidation question. Print classification before continuing.
6. **Step 5: Three-pass evaluation** — copy verbatim from spec §afford step 5, including:
   - Pass A (hard affordability)
   - Pass B (goal impact, with `none` / `minor <1mo` / `material 1-3mo` / `severe >3mo or breaks goal` tagging)
   - Pass C (payment method ranking with the formula `(reward - cost) * cashflow_fit - risk_penalty`)
7. **Step 6: Render decision** — exact output template from spec §afford step 6:
   ```
   Verdict: YES / YES-WITH-CAVEATS / NO

   Why:
     Liquidity:    {disposable} disposable after buffer & obligations  → ✓/✗
     Goal impact:  Goal {A} delayed {N}d, Goal {B} delayed {M}w ({tag})
     Cashflow:     Next salary {date}, this fits cycle

   If YES — recommended payment method:
     → {method} ({rewards rule}, {billing detail})
        Reward: ~{value}
        Cost: {interest cost}
     Alternatives:
       {method2} — {trade-off}
       {method3} — {trade-off}

   If NO — what would change the answer:
     - Wait until {date} ({reason})
     - Reduce Goal {X} target by {amount}
     - Liquidate {Y} shares of {ticker} (gain/loss + tax estimate)

   Action: confirm to log this decision.
   ```
8. **Step 7: Optional log chain** — if user confirms, chain to `/coinskills:log` for the transaction. Always append a one-liner to `reviews/<current-month>.md` under an `## afford-decisions` section so it's captured for the next review.
9. **Tone** — read `profile.preferences.decision_style`:
   - `data-first` — numbers up front, narrative second
   - `gut-first` — narrative up front, numbers backing
   - `balanced` — mixed
10. **End-of-skill commit:** `afford: decided {YES/NO} on {item}, paid via {method}` (only if user confirmed action).

- [ ] **Step 2: Commit**

```bash
git add skills/afford/SKILL.md
git commit -m "feat(skills): add afford — auto-triggered affordability decision with goal impact"
```

---

### Task 7: `log` skill

**Files:**
- Create: `skills/log/SKILL.md`

Spec source: design doc §Skills → `log` subsection.

- [ ] **Step 1: Write `skills/log/SKILL.md`**

Frontmatter:

```yaml
---
name: log
description: Бързо вписване на транзакция, доход или промяна в баланс. Used ad-hoc — "платих 42 в Lidl", "received 3200 salary", "credit card balance is now -340". Parses free-form Bulgarian/English input, identifies account/category/amount, appends to monthly ledger, updates accounts.json balance.
---
```

Body sections:

1. **Overview** — quick entry point for any state change.
2. **Step 1: Parse input** — extract amount (sign convention: negative = outflow, positive = inflow), currency (default to `profile.currency`), account (match by id, name fragment, or last-used heuristic), category (groceries, dining, transport, salary, freelance, investment-buy, investment-sell, transfer, other), date (default today), note (free-form remainder).
3. **Step 2: Resolve account** — if ambiguous, list candidate accounts and ask. Match against `accounts.json` ids and `name` fields case-insensitively.
4. **Step 3: Determine target file** — `modules/<account.module>/transactions/YYYY-MM.md`. Create the file with table header if it doesn't exist.
5. **Step 4: Append row** — exact markdown table format from spec §Data schemas → transactions:
   ```
   | {YYYY-MM-DD} | {amount} | {account-id} | {category} | {note} |
   ```
6. **Step 5: Update account balance** — read `accounts.json`, find account, adjust `balance` field by amount, write back.
7. **Step 6: Significance check** — if `|amount| > 0.10 * monthly_disposable` (computed as in `afford`), prompt: "This is significant ({pct}% of monthly disposable). Should we revisit any goal/plan? (y/n)". If yes, suggest `/coinskills:plan` or `/coinskills:goals`.
8. **Step 7: Commit:** `log: {sign}{amount} {currency} {category} {YYYY-MM-DD}` (e.g. `log: -€42 groceries 2026-04-03`).

- [ ] **Step 2: Commit**

```bash
git add skills/log/SKILL.md
git commit -m "feat(skills): add log — ad-hoc transaction entry with significance check"
```

---

### Task 8: `analyze` skill

**Files:**
- Create: `skills/analyze/SKILL.md`

Spec source: design doc §Skills → `analyze` subsection.

- [ ] **Step 1: Write `skills/analyze/SKILL.md`**

Frontmatter:

```yaml
---
name: analyze
description: Анализ на финансовото състояние спрямо целите — тенденции в харчене, нетна стойност, разпределение, паричен поток. Triggered by "how am I doing", "where do I spend the most", "what's my allocation", "как се справям", "къде харча най-много", "каква е алокацията ми".
---
```

Body sections:

1. **Overview** — analysis is always framed against active goals.
2. **Step 1: Identify the question** — classify into one of: spending-trends | net-worth | allocation | cash-flow | goal-progress | custom. If custom, ask the user to scope.
3. **Step 2: Load relevant data** — accounts, goals, plans, transactions (last N months based on question), holdings (if relevant).
4. **Step 3: Compute** — concrete formulas for each view:
   - **spending-trends**: per-category sums per month, compare last month to 3-month average
   - **net-worth**: `sum(positive balances) + sum(holdings * last_known_price) - sum(|debt balances|) + sum(illiquid assets)`
   - **allocation**: holdings grouped by ticker / asset class as % of investment total
   - **cash-flow**: monthly inflows − monthly outflows, last 6 months
   - **goal-progress**: per active goal: current / target, days remaining, plan projection
5. **Step 4: Frame against goals (mandatory)** — every output must include at least one sentence connecting findings to goal progress. Examples:
   - "Spending up 12% MoM, this puts Goal A 3 weeks behind plan v2."
   - "Allocation drift to 78% equities exceeds the 70% target in your retirement goal — consider rebalancing."
6. **Step 5: Optionally write snapshot** — for net-worth and allocation views, append a JSON entry to `snapshots/<view>.json`:
   ```json
   {"date": "YYYY-MM-DD", "value": ..., "breakdown": {...}}
   ```
7. **Step 6: Commit (only if snapshot written):** `analyze: {view} snapshot {YYYY-MM-DD}`.

- [ ] **Step 2: Commit**

```bash
git add skills/analyze/SKILL.md
git commit -m "feat(skills): add analyze — goal-framed financial analysis"
```

---

### Task 9: `review` skill

**Files:**
- Create: `skills/review/SKILL.md`

Spec source: design doc §Skills → `review` subsection.

- [ ] **Step 1: Write `skills/review/SKILL.md`**

Frontmatter:

```yaml
---
name: review
description: Периодичен преглед — месечен/тримесечен/годишен доклад. Use at period close or whenever the user asks for a financial report ("monthly review", "how did Q1 go", "year in review", "месечен отчет"). Goal progress is the top section; transactions come second.
---
```

Body sections:

1. **Overview** — synthesis: where you stand, where you're going, what to change.
2. **Step 1: Determine period** — ask user: month / quarter / year. Default to current month if not specified, or to whatever is overdue based on `profile.preferences.review_cadence`.
3. **Step 2: Aggregate data** — for the period: all transactions across modules, holdings change, account balance deltas, all afford-decisions logged.
4. **Step 3: Compute deltas** — vs same period prior cycle (last month vs month before; Q1 vs Q4 last year; 2026 vs 2025). Use git history of `accounts.json` to find period-start balances if no prior snapshot exists.
5. **Step 4: Build report** — write to `reviews/<period>.md` with exact section order:
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
   {list 2-4 wins inferred from data}

   ## ⚠️ Concerns
   {list 1-3 concerns: overspend categories, behind-pace goals, missed contributions}

   ## 🧭 Recommendations
   {2-4 concrete actions tied to specific goals/skills}

   ## 🔄 Afford-decisions logged this period
   {list from `## afford-decisions` sections of monthly review files}
   ```
6. **Step 5: Commit:** `review: {period}`.

- [ ] **Step 2: Commit**

```bash
git add skills/review/SKILL.md
git commit -m "feat(skills): add review — periodic goal-first report"
```

---

### Task 10: Validation script

**Files:**
- Create: `scripts/validate.sh`

This script confirms every SKILL.md has well-formed frontmatter with required fields. It's the closest thing to a "test" for a markdown plugin.

- [ ] **Step 1: Write `scripts/validate.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

require_frontmatter_field() {
  local file="$1"
  local field="$2"
  if ! awk '/^---$/{c++} c==1 && /^'"$field"': /' "$file" | grep -q .; then
    echo "❌ $file — missing frontmatter field: $field"
    FAIL=1
  fi
}

# Validate plugin.json
if ! jq -e '.name == "coinskills" and .version' "$ROOT/.claude-plugin/plugin.json" > /dev/null; then
  echo "❌ .claude-plugin/plugin.json — missing name or version"
  FAIL=1
fi

# Validate every SKILL.md
EXPECTED_SKILLS=(init start goals plan afford log analyze review)
for skill in "${EXPECTED_SKILLS[@]}"; do
  file="$ROOT/skills/$skill/SKILL.md"
  if [[ ! -f "$file" ]]; then
    echo "❌ Missing skill: $skill"
    FAIL=1
    continue
  fi
  require_frontmatter_field "$file" "name"
  require_frontmatter_field "$file" "description"

  # Verify name field matches directory
  actual_name=$(awk '/^---$/{c++} c==1 && /^name: /{sub(/^name: /,""); print; exit}' "$file")
  if [[ "$actual_name" != "$skill" ]]; then
    echo "❌ $file — name field is '$actual_name', expected '$skill'"
    FAIL=1
  fi
done

if [[ $FAIL -eq 0 ]]; then
  echo "✅ coinskills validation passed"
else
  exit 1
fi
```

- [ ] **Step 2: Make executable and run**

```bash
chmod +x scripts/validate.sh
./scripts/validate.sh
```

Expected output: `✅ coinskills validation passed`

If any skill fails validation, fix its frontmatter and re-run.

- [ ] **Step 3: Commit**

```bash
git add scripts/validate.sh
git commit -m "chore: add validate.sh for plugin + skill frontmatter sanity"
```

---

### Task 11: README polish + smoke install

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add "Quickstart" and "Privacy" sections to README**

After the `## Skills` section, append:

```markdown
## Quickstart

```bash
/coinskills:init
# follow the interview — sets up your profile, creates a private GitHub repo,
# walks through accounts/holdings/debts/income, and seeds your first goals

/coinskills:start
# any time — see status against goals

# Then use ad-hoc:
"Can I afford a €1200 espresso machine?"      # auto-triggers /afford
"Платих 42 в Lidl"                             # /log
"How am I doing on the house deposit?"         # /analyze
```

## Privacy

- Workspace repo is **always private** — `init` enforces `--private` and refuses to proceed otherwise.
- No account numbers, no card PANs, no credentials are ever stored. Account `id` is a slug.
- A `.gitignore` template ships in the workspace seed (ignores `.env`, raw `*.csv`, `tmp/`, `*.pdf`).
- Push is opt-in per session — Claude never auto-pushes without asking.
```

- [ ] **Step 2: Run validation one more time**

```bash
./scripts/validate.sh
```

Expected: `✅ coinskills validation passed`

- [ ] **Step 3: Smoke-test install (manual)**

In a fresh Claude Code session:

```
/plugin marketplace add /home/blox-master/business/lutherwaves/coinskills
/plugin install coinskills@<marketplace-name>
```

Verify all 8 skills appear in the skills list. Try `/coinskills:start` (should fail gracefully with "no workspace, run /coinskills:init"). Try `/coinskills:init` and walk through prerequisites only — no need to actually create a repo for the smoke test.

If any step misbehaves, return to the relevant task and fix.

- [ ] **Step 4: Commit and push**

```bash
git add README.md
git commit -m "docs: add quickstart and privacy sections to README"
git push origin main
```

---

## Self-review checklist (engineer runs this before declaring done)

- [ ] All 8 SKILL.md files exist under `skills/<name>/SKILL.md`
- [ ] Every SKILL.md has `name` and `description` frontmatter fields
- [ ] `name` field matches directory name in every skill
- [ ] `afford` description contains all 8 trigger phrases (BG + EN) — without these the auto-trigger won't work
- [ ] `init` body contains verbatim YAML/JSON templates for `profile.md`, `accounts.json`, `goals/<id>.md`, `plans/<goal-id>-v1.md`
- [ ] `afford` body reproduces the full liquidity formula and the three-pass evaluation
- [ ] Every state-mutating skill (`init`, `goals`, `plan`, `log`, `analyze`, `review`, `afford`) ends with a structured commit message
- [ ] `validate.sh` passes
- [ ] README install instructions match the actual plugin name in `plugin.json`
- [ ] No skill body says "see the spec" — all instructions are inlined and self-contained

---

## Out of scope for this plan (deferred to v2)

- `/coinskills:import` — bank/broker statement parser
- Tax / capital gains computation
- Multi-user / household profiles
- Real-time price fetching for holdings
- Workspace schema migration tooling (only needed once `schema_version` bumps)

---

## Notes for the engineer

- This is a **markdown-only plugin**. No code to compile, no tests to run beyond `validate.sh`. The "implementation" is writing prose that Claude will execute at runtime.
- **Read the spec first.** `docs/specs/2026-04-27-coinskills-design.md` is the source of truth. Each task tells you which spec section to draw from.
- **Be verbose in skill bodies.** Claude executes these at runtime — every check, every file path, every edge case must be spelled out. Don't write "handle errors gracefully" — write what error and what fallback.
- **Keep frontmatter `description` fields rich for `afford`, `log`, `analyze`, `review`.** These are the auto-trigger surface — natural-language phrases the user might say must appear there.
- **Commits at the end of every task.** The plan deliberately commits per skill so progress is visible and reverts are easy.
