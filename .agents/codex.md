# Codex — Agent Guide

Read [`README.md`](./README.md) first. Hard rules apply. Applies to OpenAI Codex CLI, ChatGPT Codex, and any Codex-driven workflow.

## Session start
```
git checkout main && git pull --rebase origin main
```

## Commit template
```
<type>(<scope>): <subject>

<body>

Agent: codex
```

## Push policy
- Push to `origin main` after each logical change.
- On non-fast-forward: `git pull --rebase origin main`, resolve, push.
- Never `--force`, never amend pushed commits.

## File locks
Before editing, append to `.agents/LOCKS.md`:
```
<relative/path> — codex — <ISO date>
```
Remove in the same commit that ships the change.

## What to skip
- No feature branches, no PRs.
- No interactive rebases on shared history.
- No silent dependency upgrades — call them out in the commit body.
