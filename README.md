# coinskills

Goal-centric financial superpowers for Claude Code. Profile your finances, set goals, build plans, decide affordability — all in your own private git repo.

## Install

```bash
# Step 1: Add the marketplace
/plugin marketplace add Lutherwaves/coinskills

# Step 2: Install the plugin
/plugin install coinskills@coinskills
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

## Quickstart

````bash
/coinskills:init
# follow the interview — sets up your profile, creates a private GitHub repo,
# walks through accounts/holdings/debts/income, and seeds your first goals

/coinskills:start
# any time — see status against goals

# Then use ad-hoc:
"Can I afford a €1200 espresso machine?"      # auto-triggers /afford
"Платих 42 в Lidl"                             # /log
"How am I doing on the house deposit?"         # /analyze
````

## Modules (opt-in)

- **Personal finance** — income, expenses, budgets, cash flow
- **Investments** — portfolio, allocation, holdings
- **Business / freelance** — invoices, expenses, P&L

## Privacy

- Workspace repo is **always private** — `init` enforces `--private` and refuses to proceed otherwise.
- No account numbers, no card PANs, no credentials are ever stored. Account `id` is a slug.
- A `.gitignore` template ships in the workspace seed (ignores `.env`, raw `*.csv`, `tmp/`, `*.pdf`).
- Push is opt-in per session — Claude never auto-pushes without asking.

## Design

See `docs/specs/2026-04-27-coinskills-design.md`.
