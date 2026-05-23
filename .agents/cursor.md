# Cursor — Agent Guide

Read [`README.md`](./README.md) first. Hard rules apply.

## Session start
In Cursor's terminal pane:
```
git checkout main && git pull --rebase origin main
```

## Rules for Cursor's AI (Composer / Chat / Agent mode)
Paste this into Cursor Rules (`.cursor/rules` or project rules) or reference this file:

- Always work on `main`. Never create branches.
- After every accepted change, commit and push to `origin main`.
- Commit trailer: `Agent: cursor`.
- Before editing a file, add it to `.agents/LOCKS.md`. Remove on push.
- If a push is rejected, `git pull --rebase origin main` then push. Never `--force`.

## Commit template
```
<type>(<scope>): <subject>

<body>

Agent: cursor
```

## What to skip
- No feature branches, no PRs.
- No amending pushed commits.
- No bundling unrelated edits.
