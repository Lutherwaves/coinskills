# Snapshot Compute

Every read skill that needs aggregate state (`start`, `afford`, `analyze`, parts of `review`) MUST follow this pattern.

## Procedure

1. **Resolve workspace and snapshot path.** `SNAP=<workspace>/snapshots/latest.json`.
2. **If `SNAP` exists and `.stale == false`** → use it directly. Skip recomputation. Return its `liquidity`, `goals`, `warnings`.
3. **Otherwise (missing or stale)** → recompute:
   - `monthly_expenses`: average of last 3 months' outflows from `modules/personal/transactions/*.md`, excluding `goal-contribution`, `investment-buy`, `investment-sell`, and rows tagged `[one-off]`. If <3 months of data: fallback to `sum(recurring normalized to monthly) + profile.variable_spending_estimate` (require `variable_spending_estimate` set; if absent, prompt user to set via `/coinskills:edit profile`).
   - `liquid_cash`: sum of bank/savings/e_money balances.
   - `emergency_buffer`: `monthly_expenses * profile.emergency_fund_months`.
   - `disposable`: `liquid_cash - emergency_buffer - sum(recurring due in next 30d) - sum(card balances closing in next 30d)`.
   - `monthly_capacity`: `sum(income normalized to monthly) - sum(recurring normalized to monthly) - profile.variable_spending_estimate`.
   - For each active goal: load active plan, compute `projected_completion`, `delay_days_from_deadline`, evaluate `prerequisites` (see `prereq-evaluation` below).
   - `warnings`: list every `_estimated` field across all account/goal/plan files.
4. **Write the new snapshot.** Atomic write per the mutation pipeline's atomic helper, but DO NOT log this as a change-event (snapshots are derived, not source-of-truth). Set `stale: false`, `computed_at: <now>`, `last_event_id: <id of last event in changes.jsonl>` (or `null` if changes.jsonl is empty).

## Prereq evaluation (referenced from step 3)

For each goal's `prerequisites` array, evaluate each entry:

- `goal-complete`: lookup `goals/<ref>.md` frontmatter. Met iff `status == "complete"`.
- `account-balance`: lookup account by `ref` in accounts.json. Met iff balance satisfies `op` against `value` (and currencies match; if not, fail with a warning, do not auto-convert).
- `attestation`: met iff `confirmed_at != null` AND (months between `confirmed_at` and today) ≤ a reasonable freshness window (default 24 months — attestations expire to force reconfirmation).
- `time-since`: lookup the matching attestation (by `ref` matching its label). Met iff `months_elapsed >= months`.

Result per goal: `prereqs_met: {met: N, total: M, unmet: [{type, ref, reason}, ...]}`. Stored on the snapshot's goal entry.

## Cost

Recompute is O(N) over accounts + goals + 3 months of transactions. Acceptable for tens-to-hundreds-of-records workspaces. If a workspace ever exceeds that scale, snapshot becomes a separate concern.
