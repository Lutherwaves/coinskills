# Path Guard (privacy invariant)

Every mutating skill MUST run this guard before any write.

## Procedure

1. Read `~/.coinskills-workspace`. If missing, abort with: "Workspace not initialized. Run /coinskills:init first."
2. Resolve the absolute path: `WORKSPACE=$(realpath "$(cat ~/.coinskills-workspace)")`. If `realpath` fails, abort.
3. For every file you intend to write or append to, compute its `realpath`. If the result does NOT start with `$WORKSPACE/`, abort with: "Refusing to write outside workspace: <attempted path>".
4. Refuse paths containing `/.git/`, `/.backups/<other-version>/` (backups are read-only after creation), and any path resolving outside `$WORKSPACE`.

## Why

The plugin repo is public. The user workspace is private. A bug or misroute that wrote financial data into the plugin install location would leak it on the next plugin push. This guard prevents that, even if every other part of the skill is wrong.

## Negative test

`scripts/test-isolation.sh` sets `~/.coinskills-workspace` to a tmpdir, runs each mutating skill against fixtures, then asserts no files were written outside the tmpdir.
