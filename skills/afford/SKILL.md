---
name: afford
description: Решава дали потребителят може да си позволи покупка/разход/разсрочване. Auto-triggered by natural language — use whenever the user asks "can I afford X", "should I buy Y", "how should I finance Z", "can I afford this", "трябва ли да купя", "мога ли да си позволя", "should I take this loan", "is this a good purchase". Recommends payment method (card/account/installments/liquidation) and explains impact on every active goal.
---

# Afford — Goal-Impact Affordability Decision

## Overview

`afford` is the killer skill of coinskills. It intercepts natural-language affordability questions and answers them properly: not just "do you have the cash" but "should you spend it here, what does it cost your goals, and if yes, how exactly should you pay." Every decision is framed against your active financial goals — a €400 dinner table isn't just a cash question, it's a question about whether your house deposit slips by six weeks.

The skill runs a deterministic seven-step algorithm: parse the ask, load workspace state, compute true liquidity, classify the purchase, run three evaluation passes (hard affordability, goal impact, payment method ranking), render a structured verdict, and optionally chain to `/coinskills:log` to record it.

Locate the workspace: read `~/.coinskills-workspace` for the absolute path. If the file doesn't exist, stop and tell the user to run `/coinskills:init` first.

---

## Step 1: Parse the Ask

Extract the following from the user's message. If any are missing, ask targeted clarifying questions before proceeding — do not guess.

| Field | What to extract | Clarifying question if missing |
|---|---|---|
| **amount** | Numeric value of the purchase/expense | "How much does it cost?" |
| **currency** | Currency of the amount | "In which currency? (default: {profile.currency})" |
| **item / purpose** | What is being bought or financed | "What exactly is this for?" |
| **frequency** | One-off vs recurring (monthly/annual) | "Is this a one-time payment or a recurring obligation?" |
| **urgency** | Must-have vs nice-to-have | "Is this a need or a want?" |
| **deadline** | Date by which the decision must be made, if any | "Is there a time pressure on this decision?" |

If the user's message contains all six fields implicitly (e.g. "can I afford a €1200 espresso machine" → amount=1200, currency=EUR, item=espresso machine, frequency=one-off, urgency=nice-to-have, deadline=none), proceed directly. Do not ask questions for fields that are clearly implied.

Print a brief summary of what was parsed before continuing:

```
Parsed: €{amount} — {item} — {one-off | recurring {frequency}} — {must-have | nice-to-have}{deadline note}
```

---

## Step 2: Load Workspace State

Read the following files from the workspace. Note any that are missing and proceed with the data available.

- `profile.md` — currency, emergency_fund_months, risk_tolerance, locale, modules, preferences.decision_style
- `accounts.json` — all accounts with type, balance, limit, apr, billing_cycle_day, rewards, module
- `goals/*.md` — all files where frontmatter `status: active`
- `plans/*.md` — all files where frontmatter `status: active`
- `modules/personal/recurring.json` — fixed recurring obligations
- `modules/personal/income.json` — income streams with amounts and frequencies
- `modules/personal/transactions/YYYY-MM.md` for the **last 3 calendar months** (e.g. if today is 2026-04-27, load 2026-02, 2026-03, 2026-04). If a month file doesn't exist, skip it and note the gap.
- `modules/investments/holdings.json` — only if `profile.modules` includes `investments`

If `accounts.json` doesn't exist or is empty, stop and tell the user: "I need your accounts set up to give you a real answer. Run `/coinskills:init` or `/coinskills:log` to seed accounts first."

---

## Step 3: Compute Liquidity

Compute the following values in order. Show your working — print the intermediate values so the user can verify.

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

**Cold-start fallback:** If fewer than 3 months of transaction files exist, fall back to: `monthly_expenses = sum of recurring.json amounts (normalised to monthly) + a user-confirmed spending estimate captured at init time`. If no init estimate exists, ask the user: "I don't have enough transaction history to compute your monthly spending. What's a rough monthly total (excluding rent/fixed bills)?" Use their answer as the variable spending component. Note in the output that this is an estimate.

**Exclusions from monthly_expenses:**
- Rows with category `goal-contribution`
- Rows with category `investment-buy` or `investment-sell`
- Any single row flagged as a large one-off purchase at log time (i.e. rows where the note contains `[one-off]` or where the amount exceeds 5× the per-category monthly average)

**Recurring obligations due in next 30d:** scan `modules/personal/recurring.json`, compute each obligation's next due date from its `frequency` and `last_paid` fields. Sum those falling within the next 30 calendar days.

**Card statement closes:** scan `accounts.json` for accounts with `type: credit_card`. For each, the statement close date this cycle = the next occurrence of `billing_cycle_day` on or after today. If that date falls within 30 days, include `|balance|` in the deduction.

Print the liquidity summary:

```
Liquidity snapshot
  Liquid cash:            €{liquid_cash}
  Emergency buffer:       €{emergency_buffer}  ({profile.emergency_fund_months}mo × €{monthly_expenses}/mo)
  Recurring due (30d):    €{sum_recurring_30d}
  Cards closing (30d):    €{sum_cards_closing_30d}
  ─────────────────────────────────────────────
  Disposable:             €{disposable}
  Credit headroom:        €{credit_headroom}  (across {N} cards)
```

---

## Step 4: Classify the Ask

Classify the purchase into exactly one of these four categories based on the fields parsed in Step 1. Print the classification label before continuing — this determines how the evaluation proceeds.

| Classification | Criteria |
|---|---|
| **one-off purchase** | Single payment, no ongoing obligation. Examples: appliance, trip, gift, repair. |
| **recurring commitment** | Ongoing monthly or annual expense. Examples: subscription, gym membership, insurance premium, rent increase. |
| **financing decision** | A loan, mortgage, instalment plan, or BNPL where repayments extend over time. |
| **liquidation question** | Considering selling an asset (investment, property, vehicle) to fund something. |

Print: `Classification: {label}`

If the ask could reasonably be classified as more than one (e.g. a car purchase with a loan), classify as the dominant type (financing decision) and note the secondary dimension.

---

## Step 5: Three-Pass Evaluation

Run all three passes. Do not skip any, even if Pass A returns NO.

### Pass A — Hard Affordability

Determine which of the following applies. Use the exact labels below.

**For one-off purchase:**
- `cash` — `disposable >= amount`. The purchase fits from available cash alone.
- `with-credit` — `disposable < amount` but `disposable + credit_headroom >= amount`. Needs a credit card or overdraft.
- `not-without-liquidation` — `disposable + credit_headroom < amount`. Cannot be funded without liquidating an asset or breaking the emergency buffer.

**For recurring commitment:**
- `cash` — monthly contribution capacity (`monthly_income − monthly_expenses`, where `monthly_expenses` already includes recurring obligations because they appear in transaction history) remains positive after adding the new obligation. For cold-start (no transaction history), use `monthly_income − sum(recurring.json normalised to monthly) − user-confirmed variable spending estimate`.
- `with-credit` — contribution capacity goes negative but credit headroom could cover it short-term (unsustainable, flag this).
- `not-without-liquidation` — cannot sustain this obligation without cutting another or liquidating.

**For financing decision:**
- `cash` — the monthly repayment fits within contribution capacity.
- `with-credit` — repayment fits only if another credit line is used (circular debt risk, flag this).
- `not-without-liquidation` — repayment requires liquidation to fund.

**For liquidation question:**
- Always classify as `not-without-liquidation` for Pass A — that's the nature of the question. Pass B and C carry the real analysis.

Print: `Pass A: {label}`

If the result is `not-without-liquidation`, do NOT stop. Continue to Pass B and Pass C — the user needs to know the goal impact and what options exist.

### Pass B — Goal Impact

This pass always runs, regardless of Pass A result.

For each active goal (every file in `goals/*.md` with `status: active`):

1. Load the goal's active plan from `plans/` (match by `goal_ids` containing this goal's id, `status: active`). If no active plan exists for a goal, note it as `no-plan` and skip the projection math.

2. **If the purchase is a one-off:** compute how much the lump sum reduces current liquid cash earmarked for this goal. If the goal uses a `linked_accounts` field in its frontmatter, check whether any of those accounts are the funding source. Recompute the goal's projected completion date: `new_completion = today + (target_amount - (current_saved - amount_from_linked)) / monthly_contribution`.

3. **If the purchase is a recurring commitment:** compute the reduction in `monthly_contribution_capacity`. Recompute each active plan's projected completion date using the reduced capacity.

4. **Compute the delay:** `delay_days = new_completion - old_completion` (in days).

5. **Tag the impact:**
   - `none` — delay_days == 0 (purchase draws from unrelated accounts, goal unaffected)
   - `minor` — 0 < delay_days < 30 (less than 1 month delay)
   - `material` — 30 ≤ delay_days ≤ 90 (1–3 month delay)
   - `severe` — delay_days > 90, OR the purchase breaks the goal entirely (e.g. empties the linked savings account, making completion impossible without new contributions)

Print for each goal:

```
Pass B — Goal impact:
  {goal-id} "{title}": {old_completion} → {new_completion}  (+{delay_days}d) — {tag}
```

If all goals show `none`, print: `No goal impact detected.`

### Pass C — Payment Method Ranking

**Only run if Pass A result is `cash` or `with-credit`.** If Pass A is `not-without-liquidation`, skip Pass C and go to Step 6.

For each viable payment method, compute four scores. A "viable" method is one where the account has sufficient headroom (for credit) or balance (for debit) to cover the amount.

**Viable methods to consider:**
- Each `credit_card` account in `accounts.json` with `credit_headroom >= amount` (or partial coverage)
- Each `bank` or `savings` account with `balance >= amount`
- Each `e_money` account with `balance >= amount`
- Instalment plan (0% or interest-bearing): only include if the user mentioned it, or if `amount > 500` and the vendor category plausibly offers BNPL (electronics, furniture, travel)
- Liquidation of holdings: only if module `investments` is enabled and Pass A was `not-without-liquidation`

**For each viable method, compute:**

```
cost_score      = interest cost if balance not paid in full by next statement
                   + opportunity cost (if debit: lost investment return on cash,
                     estimated at 7% annual / 12 per month × amount)
                   (lower is better)

reward_score    = if credit_card: parse accounts.json "rewards" field for category match
                    → if category matches (e.g. "4x dining" and item is a restaurant):
                        reward_value = amount × multiplier × point_value_in_currency
                    → if no match: reward_value = 0
                  if debit/bank: 0
                  (higher is better)

cashflow_fit    = score 1.0–0.0 based on billing cycle alignment:
                    1.0 → statement closes AFTER next income deposit
                         (you can pay in full before interest accrues)
                    0.5 → statement closes BEFORE next income deposit
                         (tight but manageable)
                    0.0 → next income deposit is > 30d away and balance would revolve

risk_score      = credit_utilisation_increase (amount / limit, as decimal)
                   + 0.2 if this pushes any card above 30% utilisation
                   + 0.3 if this is an instalment (locks recurring outflow)
                   + 0.1 if paying cash from savings (reduces emergency buffer ratio)
```

**Ranking formula:**

```
score = (reward_score - cost_score) * cashflow_fit - risk_score
```

Sort methods by score descending (highest score = best option). If two methods score within 0.01 of each other, prefer the one with lower `risk_score`.

Print:

```
Pass C — Payment method ranking:
  1. {method-id} — score {X.XX}
       Reward: ~€{reward_value} {reward_description}
       Cost:   €{cost} ({interest note or "€0 if paid in full"})
       Cashflow fit: {1.0 | 0.5 | 0.0} ({reason})
       Risk: {utilisation impact}
  2. {method-id} — ...
  3. {method-id} — ...
```

---

## Step 6: Render Decision

Produce the verdict in this exact format. Do not deviate from the template structure.

```
Verdict: YES / YES-WITH-CAVEATS / NO
```

**Verdict rules:**
- `YES` — Pass A is `cash`, all goal impacts are `none` or `minor`, and at least one viable payment method ranks positively.
- `YES-WITH-CAVEATS` — Pass A is `cash` or `with-credit`, but at least one goal impact is `material`; OR Pass A is `with-credit` with good cashflow fit; OR there are notable trade-offs the user should weigh.
- `NO` — Pass A is `not-without-liquidation`; OR at least one goal impact is `severe`; OR no viable payment method exists.

Full decision output:

```
Verdict: YES / YES-WITH-CAVEATS / NO

Why:
  Liquidity:    €{disposable} disposable after buffer & obligations  → ✓ / ✗
  Goal impact:  {goal-id-A} delayed {N}d (none/minor/material/severe), {goal-id-B} delayed {M}w (material)
  Cashflow:     Next salary {date}, this fits cycle / tight / does not fit cycle

If YES or YES-WITH-CAVEATS — recommended payment method:
  → {method-id} ({rewards rule}, statement closes {date}, paid by {pay-by-date} from {income-source})
     Reward: ~€{reward_value} {reward_description}
     Cost: €{cost} ({interest note or "€0 if paid in full by {date}"})
  Alternatives:
    {method-2} — {trade-off vs recommended}
    {method-3} — {trade-off vs recommended}

If NO — what would change the answer:
  - Wait until {date} ({reason, e.g. next quarterly bonus expected})
  - Reduce Goal {goal-id} target by €{amount} (would eliminate the severity tag)
  - Liquidate {N} shares of {ticker} (current gain €{gain}, tax estimate €{tax})

Action: confirm to log this decision. I'll record it under reviews/ so we revisit at next review.
```

**Tone — read `profile.preferences.decision_style`:**

Before rendering, check `profile.preferences.decision_style`:

- `data-first` — lead with the numbers block, put the narrative sentence last. Example: "€340 disposable, 2% utilisation increase, Goal A delayed 18d (minor). Verdict: YES-WITH-CAVEATS. The Amex Gold is your best option given the 4x dining reward — watch Goal A closely."
- `gut-first` — lead with a plain-language summary sentence, follow with the numbers. Example: "You can swing this, but your house deposit takes a small hit. Here's the breakdown…"
- `balanced` — interleave: one numbers line, one narrative sentence, alternating. This is the default if the field is missing.

---

## Step 7: Optional Log Chain

After rendering the decision, ask:

> "Confirm to proceed? I'll log this under your afford-decisions so it shows up in your next review. (yes / no / yes, log the transaction too)"

Handle the three responses:

**"no"** — Do nothing. The decision was informational only. Do not write any files.

**"yes"** — Append a one-liner to `reviews/{YYYY-MM}.md` (where YYYY-MM is the current month) under the heading `## afford-decisions`. Create the file and heading if they don't exist.

One-liner format:
```
- {YYYY-MM-DD}: {verdict} — {item} — €{amount} — {method or "no action"}
```

Example:
```
- 2026-04-27: YES-WITH-CAVEATS — espresso machine — €1200 — card-amex-gold
```

**"yes, log the transaction too"** — Append the one-liner to `reviews/{YYYY-MM}.md` as above, then chain to `/coinskills:log`. Pass the following context to the log skill:
- amount: `{amount}` (negative, it is an outflow)
- currency: `{currency}`
- account: `{recommended method id}`
- category: derive from item (e.g. "electronics", "dining", "travel", "home", "other")
- note: `{item} [afford-approved]`
- date: today

The `/coinskills:log` skill handles the rest (updating `accounts.json`, significance check, commit).

---

## Commit

Only run this commit if the user confirmed action (i.e. responded "yes" or "yes, log the transaction too" in Step 7).

From the workspace root:

```bash
git add reviews/
git commit -m "afford: decided {YES/NO/YES-WITH-CAVEATS} on {item}, paid via {method}"
```

If the log chain also ran and committed, do not double-commit — the log skill's commit covers the transaction file and accounts.json. This commit covers only `reviews/`.

If the user responded "no" to the Step 7 prompt, do not commit anything.

---

## Self-check before finishing

Before declaring done, verify:

- The verdict is one of `YES`, `YES-WITH-CAVEATS`, or `NO` — no other values
- All three passes (A, B, C) ran or were explicitly skipped with reason stated
- Every active goal has an impact tag in Pass B output
- The recommended method (if any) has reward, cost, and cashflow fit numbers
- If verdict is NO, at least one "what would change the answer" item is provided
- If user confirmed, `reviews/{YYYY-MM}.md` has been updated
- Commit ran only if user confirmed action
