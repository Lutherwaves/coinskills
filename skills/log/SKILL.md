---
name: log
description: Бързо вписване на транзакция, доход или промяна в баланс. Used ad-hoc — "платих 42 в Lidl", "received 3200 salary", "credit card balance is now -340". Parses free-form Bulgarian/English input, identifies account/category/amount, appends to monthly ledger, updates accounts.json balance.
---

# Log — Ad-hoc Transaction Entry

## Overview

`log` is the quick entry point for any state change in your finances — an expense, an income deposit, a balance correction, or an investment transaction. You speak naturally in Bulgarian or English; the skill parses it, resolves the account, appends the row to the right monthly ledger, and updates `accounts.json` to keep your balance current. For transactions that are large relative to your monthly disposable income, it prompts you to revisit goal or plan assumptions before moving on.

Locate the workspace: read `~/.coinskills-workspace` for the absolute path. If the file doesn't exist, stop and tell the user to run `/coinskills:init` first.

---

## Step 1: Parse Input

Extract the following fields from the user's free-form message. The message may be in Bulgarian or English — handle both.

| Field | How to extract | Default if absent |
|---|---|---|
| **amount** | Numeric value. **Sign convention: negative = outflow (expense, payment, purchase), positive = inflow (income, deposit, refund).** If the user says "платих", "spent", "paid", "bought" → negative. If they say "received", "got", "salary", "earned", "deposit" → positive. | None — required; ask if unclear. |
| **currency** | Explicit symbol (€, $, лв.) or code (EUR, USD, BGN) in the message. | `profile.currency` from `profile.md` |
| **account** | Any account name fragment, card name, or bank mentioned (e.g. "Lidl" is the merchant, not the account; "revolut", "amex", "dsk" are account hints). | Use last-used heuristic (see Step 2). |
| **category** | One of: `groceries`, `dining`, `transport`, `salary`, `freelance`, `investment-buy`, `investment-sell`, `transfer`, `other`. Infer from context — "Lidl" → groceries, "salary" → salary, "Bolt" → transport, "bought VWCE" → investment-buy. | `other` |
| **date** | Any date mentioned explicitly (e.g. "yesterday", "2026-04-03", "в петък"). Parse relative dates against today's date. | today (YYYY-MM-DD) |
| **note** | Everything remaining after amount/currency/account/category/date have been extracted. The merchant name, reason, or free-form context. | empty string |

Print a one-line parse summary before continuing:

```
Parsed: {amount} {currency} — {category} — {account hint} — {YYYY-MM-DD} — "{note}"
```

If amount is missing and cannot be inferred, ask: "How much was this transaction?"

---

## Step 2: Resolve Account

Load `accounts.json` from the workspace root. Match the account hint from Step 1 against:

1. **`id` field** — exact match (case-insensitive).
2. **`name` field** — case-insensitive substring match (e.g. "amex" matches "Amex Gold").
3. **Last-used heuristic** — if no hint was given, identify the most recently used account by scanning the current month's transaction file(s) for the most frequent `account` value. If the transaction files are empty, fall back to the first account in `accounts.json`.

**Ambiguous match** — if the hint matches more than one account name or id:

1. List all candidates in a short table:
   ```
   Which account?
     1. card-amex-gold    Amex Gold          (credit_card, balance -340, limit 5000)
     2. card-visa-dsk     DSK Visa           (credit_card, balance -120, limit 2000)
   ```
2. Ask: "Which account? (enter number or id)"
3. Wait for the user's response before continuing.

**No match at all** — if no account can be matched:

1. Print the full account list from `accounts.json`.
2. Ask: "Which account should I use?"
3. If the user says this is a new account, tell them: "Add the account via `/coinskills:init` or manually to `accounts.json`, then log this transaction."

Once resolved, print: `Account: {id} ({name})`

Store the resolved `account.module` (e.g. `personal`, `investments`, `business`) — used in Step 3.

---

## Step 3: Determine Target File

Compute the target transaction file path:

```
{workspace_root}/modules/{account.module}/transactions/{YYYY-MM}.md
```

Where `YYYY-MM` is derived from the transaction date resolved in Step 1.

Examples:
- A groceries expense on a `personal` module card → `modules/personal/transactions/2026-04.md`
- An investment buy from a `investments` module broker → `modules/investments/transactions/2026-04.md`

**If the file does not exist:**

1. Ensure the parent directory exists: `modules/{account.module}/transactions/`. Create it if needed.
2. Create the file with this exact table header (two lines — header row + separator row):

```markdown
| date       | amount | account            | category   | note               |
|------------|--------|--------------------|------------|---------------------|
```

Do not add any blank lines before the header. The file must start with `| date`.

---

## Step 4: Append Row

**Apply path guard** from `skills/_shared/path-guard.md` before any write. **Run the mutation pipeline** from `skills/_shared/mutation-pipeline.md` for every state change:

- Transaction append → `op: create`, `target: modules/personal/transactions/YYYY-MM.md#<row>`
- Account balance update → `op: update`, `target: accounts.json#<account-id>.balance`

Mark snapshot stale at the end of the log invocation (one mark, even if multiple writes happened).

Append exactly one row to the end of the target transaction file using this exact markdown table format:

```
| {YYYY-MM-DD} | {amount} | {account-id} | {category} | {note} |
```

Rules:
- `{YYYY-MM-DD}` — the resolved transaction date, zero-padded.
- `{amount}` — the signed numeric value (negative for outflows, positive for inflows). Use decimal notation; do not include the currency symbol in this field. Example: `-42.50` or `3200`.
- `{account-id}` — the `id` field from `accounts.json`, not the display name.
- `{category}` — the resolved category from Step 1.
- `{note}` — the free-form remainder from Step 1. If empty, leave the field blank (just `|  |`).

Concrete examples:
```
| 2026-04-03 | -42.50 | card-amex-gold    | groceries  | Lidl                |
| 2026-04-05 |  3200  | bank-revolut-main | salary     | April salary        |
| 2026-04-10 | -850   | broker-t212       | investment-buy | VWCE 8 shares   |
```

Append to the file — do not overwrite existing rows.

---

## Step 5: Update Account Balance

1. Read `accounts.json` from the workspace root.
2. Locate the account whose `id` matches the resolved account from Step 2.
3. Adjust the `balance` field:
   - `balance = balance + amount`
   - For credit cards, a negative amount (outflow/spend) makes the balance more negative. A positive amount (payment toward the card) makes it less negative.
   - For bank/savings accounts, a negative amount decreases the balance. A positive amount increases it.
4. Write the updated array back to `accounts.json`. Preserve all other fields and all other account objects unchanged. Use the same JSON formatting (indentation, key order) as the original file.

Print: `Balance updated: {account-id} → {new_balance} {currency}`

---

## Step 6: Significance Check

Compute `monthly_disposable` using the same method as the `afford` skill:

```
monthly_expenses    = avg of last 3 months' total outflows from
                       modules/personal/transactions/, excluding
                       categories: goal-contribution, investment-buy, investment-sell
liquid_cash         = sum(bank/savings/e_money balances)
emergency_buffer    = monthly_expenses * profile.emergency_fund_months
disposable          = liquid_cash - emergency_buffer
                       - sum(recurring obligations due in next 30d)
                       - sum(card balances whose statement closes within next 30d)
```

**Cold-start fallback:** If fewer than 3 months of transaction history exist, use `sum of recurring.json amounts (normalised to monthly)` as `monthly_expenses`. If `recurring.json` is also absent, skip the significance check and proceed to Step 7.

**Threshold check:**

```
if |amount| > 0.10 * monthly_disposable:
    pct = round(|amount| / monthly_disposable * 100, 1)
    prompt the user
```

Significance prompt:

> "This is significant ({pct}% of monthly disposable). Should we revisit any goal or plan? (y/n)"

**If yes:**
- If any active goals exist (`goals/*.md` with `status: active`) that have no active plan, suggest: "Run `/coinskills:plan` to build a plan for {goal-id}."
- If all active goals already have active plans, suggest: "Run `/coinskills:goals` to review your goals, or `/coinskills:plan` to revise a plan."
- Print the suggested command and stop — let the user decide whether to act now.

**If no:** proceed directly to Step 7.

**If monthly_disposable is zero or negative:** skip the significance check (a zero or negative disposable makes the percentage meaningless) and proceed to Step 7.

---

## Step 7: Commit

From the workspace root, run:

```bash
git add modules/{account.module}/transactions/{YYYY-MM}.md accounts.json
git commit -m "log: {sign}{amount}{currency_symbol} {category} {YYYY-MM-DD}"
```

Commit message rules:
- `{sign}` — `-` for outflows, `+` for inflows (or omit `+` if it looks cleaner — either is acceptable).
- `{amount}` — absolute value (no sign in the amount portion when the sign prefix is present).
- `{currency_symbol}` — use the symbol (€, $, лв.) rather than the code where possible.
- `{category}` — the resolved category.
- `{YYYY-MM-DD}` — the transaction date.

Examples:
```
log: -€42 groceries 2026-04-03
log: +€3200 salary 2026-04-05
log: -€850 investment-buy 2026-04-10
log: -лв120 transport 2026-04-07
```

If `git add` or `git commit` fails (e.g. nothing to commit, or git not initialized in workspace), print the error and tell the user: "Commit failed. The transaction file and accounts.json have been updated — commit manually when ready."

---

## Self-check before finishing

Before declaring done, verify:

- The parsed amount has the correct sign (negative for outflows, positive for inflows).
- The account was unambiguously resolved — no silent fallbacks if the user mentioned a specific account that didn't match.
- The transaction row was appended (not prepended, not overwritten).
- `accounts.json` balance was updated for the correct account.
- If `|amount| > 10% of monthly_disposable`, the significance prompt was shown.
- The commit message follows the format `log: {sign}{amount}{currency} {category} {YYYY-MM-DD}`.
