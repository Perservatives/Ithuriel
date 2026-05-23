# .agents — Multi-Agent Conventions for Ithuriel

This directory holds the shared rules every AI coding agent working on this repo must follow. It is the single source of truth for cross-agent coordination across Claude Code, Cursor, Codex, and any other agent.

Project: **Ithuriel**
Repo: **https://github.com/Perservatives/Ithuriel**
Default branch: **`main`**

---

## Hard Rules (all agents)

1. **Always commit directly to `main`.** No feature branches, no PRs.
   - Branch must be `main` before every commit.
   - `git push origin main` after every commit (or batched commits) so other agents see the state.
   - If the push is rejected (non-fast-forward), `git pull --rebase origin main`, resolve, then push. Never `--force` push to `main`.

2. **Pull before you work.** First action of every session:
   ```
   git checkout main && git pull --rebase origin main
   ```

3. **Identify yourself in commits.** Use a trailer so we can attribute work:
   ```
   Agent: <claude-code | cursor | codex | other>
   ```
   Plus a conventional-style subject: `feat(scope): …`, `fix(scope): …`, `docs(scope): …`, `chore(scope): …`.

4. **Small, atomic commits.** One logical change per commit. Avoid bundling unrelated edits — multiple agents are reading the log.

5. **Never rewrite shared history.** No `git rebase -i`, `git reset --hard`, `git push --force`, or amending a commit that has been pushed.

6. **Respect locks.** Before editing a file, check `.agents/LOCKS.md`. If another agent has claimed it, pick something else or coordinate. Release the lock when you push.

7. **Sensitive files stay out.** No `.env`, credentials, `*.pem`, `*.key`, service-account JSON. Use `.env.example` for shape, real secrets live in the user's secret store.

8. **Tests and typechecks must pass before push.** If the project has them wired up, run them. If you can't run them, say so in the commit body.

9. **Surface conflicts, don't paper over them.** If you find another agent's in-progress work that conflicts with your task, stop and write a note in `.agents/HANDOFF.md` rather than rewriting it.

---

## Per-Agent Guides

- [`claude.md`](./claude.md) — Claude Code
- [`cursor.md`](./cursor.md) — Cursor
- [`codex.md`](./codex.md) — OpenAI Codex / Codex CLI

Each guide is a thin wrapper: it just tells that agent how to obey the rules above using its own primitives.

---

## Coordination Files

- `LOCKS.md` — current file-level claims (`path — agent — since`). Append to claim, remove to release.
- `HANDOFF.md` — short notes between agents ("started X, blocked on Y, please continue").

Keep both short. They are working memory, not documentation.
