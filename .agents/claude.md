# Claude Code — Agent Guide

Read [`README.md`](./README.md) first. Hard rules apply.

## Session start
```
git checkout main && git pull --rebase origin main
```

## Commit template
```
<type>(<scope>): <subject>

<body>

Agent: claude-code
```

Do **not** add a `Co-Authored-By` trailer. The `Agent:` trailer is sufficient.

## Push policy
- After each logical change, `git push origin main`.
- If rejected: `git pull --rebase origin main`, resolve, push. Never `--force`.

## File locks
- Before editing, append a line to `.agents/LOCKS.md`:
  ```
  <relative/path> — claude-code — <ISO date>
  ```
- Remove the line in the same commit that pushes your change.

## What to skip
- Don't create feature branches.
- Don't open PRs.
- Don't amend or force-push.
- Don't run `git add -A` blindly — stage by path.
