# Mutation Pipeline

Every write to a state file (accounts.json, goals/*.md, plans/*.md, profile.md, modules/*/*.json, assets-illiquid.json) MUST go through this pipeline.

## Steps

1. **Path guard** (see `skills/_shared/path-guard.md`).
2. **Validate against schema.** Resolve schema absolute path: `<plugin-root>/schemas/<entity>.schema.json`. Run `ajv validate -s <schema> -d <staged-data> --strict=false`. If validation fails:
   - For required-field/type/enum/cross-ref errors → abort the mutation, print the error, do NOT touch any file.
   - For business-rule warnings (negative balance on savings, etc.) → continue, but record `validation: "warn"` in the change-log entry and add to snapshot warnings.
3. **Append to `changes.jsonl`.** Resolve `<workspace>/changes.jsonl`. Append exactly one JSON line with this structure (matches `schemas/change-event.schema.json`):

   ```json
   {"id":"chg_<UTC-iso>_<6-hex>","timestamp":"<UTC-iso>","skill":"<skill-name>","op":"<op>","target":"<file>#<jsonpath>","before":<old>,"after":<new>,"validation":"ok"}
   ```

   Use `python3 -c 'import secrets; print(secrets.token_hex(3))'` for the hex suffix, or any equivalent.
4. **Mutate the state file.** Use `Edit`, `Write`, or `jq` as appropriate. Atomic: write to a temp file in the same directory, then `mv` over the destination.
5. **Mark snapshot stale.** Resolve `<workspace>/snapshots/latest.json`. Update its top-level `stale: true` and `last_event_id: <new event id>`. If the file doesn't exist, create one with `stale: true` and empty `liquidity`/`goals`/`warnings`.
6. **Commit (optional).** Skills that complete a logical unit (init, migrate, an interactive edit session, a log entry) `git add` and `git commit` the changed files. Skills that are part of a longer flow defer commit to the user.

## Cross-ref validation (step 2 detail)

For accounts.json: every `linked_accounts` entry in any goal frontmatter must point to an existing account `id`. For income.json: `account_id` must exist. Cross-ref check is part of validation, not a separate step.

## Atomic write helper (bash)

```bash
write_atomic() {
  local target="$1"
  local content="$2"
  local tmp
  tmp=$(mktemp -p "$(dirname "$target")")
  printf '%s\n' "$content" > "$tmp"
  mv "$tmp" "$target"
}
```

## When NOT to run the pipeline

- Read-only operations (`start`, `analyze`, `review` in read mode) — never write changes.jsonl.
- Plan/spec doc writes within the plugin repo — never targets the workspace.
- Backups during `migrate` — write to `.backups/` directly without a change-log entry; the migrate event itself is a single change-log entry covering the whole migration.
