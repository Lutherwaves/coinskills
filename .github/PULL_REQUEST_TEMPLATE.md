## Summary

<!-- What does this PR change and why? Link the issue: Closes #123 -->

## Type of change

- [ ] Bug fix
- [ ] New feature / skill
- [ ] Schema or data-model change (requires migration plan)
- [ ] Refactor
- [ ] Docs
- [ ] Infra / CI

## Areas touched

<!-- init / start / goals / plan / afford / log / analyze / review / edit / migrate / schemas / shared / infra / docs -->

## Privacy invariant check

- [ ] No financial data, account ids, or workspace paths committed in fixtures, tests, or screenshots
- [ ] Any new mutating skill writes only to paths under `~/.coinskills-workspace`
- [ ] `.gitignore` defense-in-depth patterns still cover any new state-file shape introduced

## How was this tested?

<!-- Schema validation, isolation test, smoke against a fixture workspace, etc. Redact user-specific data. -->

- [ ] `bash scripts/validate.sh`
- [ ] `bash scripts/test-schemas.sh` (if schemas changed)
- [ ] `bash scripts/test-isolation.sh` (if any mutating skill changed)

## Checklist

- [ ] Linked to an issue (or explained why standalone)
- [ ] Skill/command docs updated if behavior changed
- [ ] CHANGELOG entry added under the unreleased section
- [ ] Tested end-to-end against at least one fixture workspace
- [ ] No real account ids, balances, or personal financial data in commits
