# Security policy

## Supported versions

coinskills is a Claude Code plugin distributed from `main`. Only the latest commit on `main` is supported.

## Reporting a vulnerability

Please **do not** open public issues for security problems.

Report privately via GitHub's [Private vulnerability reporting](https://github.com/Lutherwaves/coinskills/security/advisories/new), or email **noreply@users.noreply.github.com**.

Include:
- A description of the issue and its impact
- Steps to reproduce (sample workspace shape, command sequence, or PoC)
- Affected version / commit

You should receive an acknowledgment within **5 business days**. We aim to ship a fix or mitigation within **30 days** for confirmed issues, faster for anything that exposes user financial data.

## Scope

In scope:
- Code execution, path traversal, or arbitrary write through any `/coinskills:*` skill
- Any path through which financial data (accounts, balances, goals, transactions) could leak out of the user's private workspace into the public plugin repo or any other unintended destination
- Supply-chain issues in skills, schemas, hooks, or shared markdown references (prompt injection that escalates privileges or exfiltrates state)
- Bypass of the `~/.coinskills-workspace` pointer / path-guard mechanism

Out of scope:
- Social engineering of plugin users
- Bugs in third-party MCP servers or Claude Code itself — report those upstream
- Issues in the user's own workspace repo configuration (visibility, branch protection, etc.) — those are the user's responsibility, though we welcome reports of misleading defaults or documentation
