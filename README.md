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
- `/coinskills:edit` — Guided editor for any account/goal/plan/profile field. Confirms estimated values, supports undo.
- `/coinskills:migrate` — One-shot v0.1 → v0.2 workspace migration. Run once after upgrading the plugin.

## v0.2 features

- **Recoverability.** Every mutation is logged to `changes.jsonl`. `/coinskills:edit undo` reverses any change with conflict detection.
- **Estimated-value tracking.** Fields you guessed at init time are flagged with `_estimated`. The edit skill prompts you to confirm or correct them over time.
- **Structured prerequisites.** Goals can specify hard prereqs (other goals complete, account balance thresholds, attestations, time-since) and `afford` evaluates them automatically.
- **Funding modes.** `monthly`, `windfall-only` (aspirational goals), `hybrid`. Afford's goal-impact analysis respects funding mode — windfall-only goals don't get "delayed" by everyday spending.
- **Goal-detection in afford.** When you ask about a big-ticket item with no deadline and no rush, afford suggests creating a goal first instead of forcing a YES/NO verdict.
- **Snapshot cache.** Liquidity and per-goal projections are computed once and cached at `snapshots/latest.json`. Any mutation marks it stale; the next read recomputes.

## Upgrading

If you have a v0.1 workspace, run `/coinskills:migrate` after installing v0.2. The migration is idempotent, creates a backup at `.backups/`, and walks you through converting prose prerequisites to structured form.

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
