# Changelog

## 0.2.1 (2026-05-12)

### Fixed
- goals status enum complete/retired, review snapshot+recognition, afford Step 4.5 label

## v0.2.0 — 2026-04-29

**Added**
- `edit` skill — guided editor for accounts, goals, plans, profile, recurring, income, holdings, attestations. Supports undo with conflict detection.
- `migrate` skill — one-shot v0.1 → v0.2 migration with workspace backup.
- `changes.jsonl` append-only event log at workspace root.
- `snapshots/latest.json` derived aggregate cache with stale flag.
- JSON schemas for every state file under `schemas/`.
- `_estimated` field on accounts/goals/plans for provenance tracking.
- Goal frontmatter additions: `funding_mode`, `prerequisites` (structured), `windfall_sources`.
- Goal status enum: `active | blocked | paused | complete | retired`.
- Afford Step 0 goal-detection heuristic and Step 4.5 prerequisite auto-evaluation.
- Recognition-over-recall: all goal references in output use `<title> (<id>)`.
- `scripts/test-isolation.sh` and `scripts/test-schemas.sh` smoke tests.
- Defense-in-depth `.gitignore` patterns to prevent financial-data leaks into the plugin repo.

**Changed**
- `init` writes `schema_version: 2`, captures `variable_spending_estimate`, seeds `changes.jsonl` and `snapshots/latest.json`.
- `goals` writes v2 frontmatter (funding_mode + prerequisites + status enum).
- `log` routes all writes through the mutation pipeline.
- All read skills (`start`, `afford`, `analyze`, `review`) gate on `schema_version: 2` and reuse the snapshot.

**Fixed**
- Affordability calls no longer recompute liquidity from scratch on every invocation.
- Estimated values at init time can now be marked, displayed, and confirmed over time.
- Prose-style goal prerequisites are now machine-evaluable.

## 0.1.0 (2026-04-27)

### Added
- Initial release: 8 skills (init, start, goals, plan, afford, log, analyze, review)
- Goal-centric workflow with auto-triggered affordability decisions
- Bilingual (Bulgarian + English) trigger phrases for `/afford`
- Private git workspace seeded by `/init`
- Validator script for plugin + skill frontmatter
- Semantic-release CI pipeline
