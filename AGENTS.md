# AGENTS.md — Ithuriel

Agent guidance for anyone (human or AI) working in this repo. Read this first.

---

## 1. What this project is

Ithuriel is a macOS-native **computer-use agent** (openclaw-style) that
runs locally on your Mac with full project context already loaded. The
user types a task into the menu bar; the agent uses Google Gemini's
function-calling + vision to drive the keyboard, mouse, file system, and
apps until the task is done.

A passive workspace monitor (FSEvents, NSWorkspace, git, terminal) feeds
the agent's system prompt continuously, so prompts don't need to
re-explain the project. A context-bridge into other AI tools is a
**secondary** feature, not the headline.

The product spec lives in [PRD.md](./PRD.md). Read it before making
architectural decisions.

---

## 2. Workflow rules (mandatory)

These are standing instructions from the project owner. Follow them without
asking each time.

1. **Always read `AGENTS.md` (this file) and `PRD.md` before starting work.**
2. **Commit only when the user explicitly asks.** If unclear, ask first. Do not
   commit at the end of a task unless they requested it.
3. **Push only when the user explicitly asks** (e.g. "push", "pull before edit,
   push after"). Pre-authorized push does not mean push every time.
4. **Before editing:** always `git pull --rebase` first. If uncommitted changes
   block pull, stash → pull → stash pop. Narrate each step to the user (see §2.1).
5. **After editing, when they asked to push:** always `git pull --rebase` again,
   then `git push`. Never push without pulling first.
6. **When push is rejected because remote diverged:** pull and combine. Resolve
   conflicts by merging both sides (never discard remote or local work silently),
   then push again if they asked for push.
7. **Never force-push** (`--force`, `--force-with-lease`) unless the owner
   explicitly asks.
8. **Never skip hooks** (`--no-verify`) unless explicitly asked.
9. **Never change git config** or use interactive git (`-i`).

### 2.1 Git steps — tell the user what is happening

Agents must not run opaque stash/pull/commit/push chains. Use short **bold
labels** and one plain sentence per phase so the user can follow along.

| Phase | Tell the user |
|--------|----------------|
| Status check | **Checking git status** — any local changes? |
| Stash | **Stashing your work** — temporary; needed so pull can run. |
| Pull | **Pulling latest** — from `origin` (rebase). |
| Stash pop | **Restoring your work** — re-applying stashed files. |
| Review (commit) | **Reviewing changes** — status, diff, recent commits. |
| Stage | **Staging files** — which paths (no secrets). |
| Commit | **Creating commit** — one-line why (HEREDOC message). |
| Verify | **Verifying commit** — post-commit status. |
| Push | **Pushing to remote** — branch name; pull first if needed. |

Example narration:

> **Stashing your work** — You have uncommitted edits; saving them briefly.  
> **Pulling latest** — `git pull --rebase` on `main`. Already up to date.  
> **Restoring your work** — Stash popped; your local edits are back.

Full commit safety rules (parallel status/diff/log, no amend unless allowed,
no secrets in commits) live in the project Cursor rule
`.cursor/rules/git-workflow.mdc`.

---

## 3. Repo layout

```
Ithuriel/
├── PRD.md                          # product spec — source of truth
├── AGENTS.md                       # this file
├── DEPLOY.md                       # end-to-end GCP bootstrap
├── Ithuriel.xcodeproj/             # generated from project.yml via XcodeGen
├── project.yml                     # XcodeGen spec — regenerate xcodeproj with `xcodegen generate`
├── Ithuriel/                       # Swift app source
│   ├── IthurielApp.swift           # entry point, AppDelegate
│   ├── MenuBarManager.swift
│   ├── Agent/                      # AgentLoop, GeminiClient, ScreenCapture, KillSwitch
│   ├── AgentControl/               # AgentController (full action surface)
│   ├── Auth/                       # Keychain, AuthService, URLSchemeHandler
│   ├── Capture/                    # FSEvents, NSWorkspace, git, terminal
│   ├── Privacy/                    # Redactor
│   ├── Injection/                  # secondary: pasteboard hand-off
│   ├── API/                        # IthurielClient (REST + WS)
│   ├── Models/                     # ContextSnapshot, AgentRunRecord, UserPrefs
│   ├── Views/                      # StatusBarView (prompt-first), SettingsView
│   └── Resources/                  # Info.plist, Ithuriel.entitlements, Localizable.strings
├── services/
│   ├── api/                        # Cloud Run API (Node 20 + Fastify + TS)
│   ├── mcp/                        # MCP connector — Claude/ChatGPT/Cursor talk to Ithuriel
│   └── functions/processor/        # Pub/Sub-triggered Python function
└── infra/
    ├── terraform/                  # Full GCP stack as code
    ├── cloudbuild.yaml             # CI/CD
    ├── firebase.json
    ├── firestore.rules
    ├── firestore.indexes.json
    └── storage.rules
```

---

## 4. Tech stack constraints

- **Swift 5.9 / SwiftUI 5**, macOS 14+ deployment target
- **Zero third-party dependencies.** Pure Apple frameworks only.
  (SwiftUI, AppKit, SwiftData, CoreServices, ApplicationServices,
   UserNotifications, URLSession.)
- **No force-unwraps.** Use `guard let` / `if let`.
- **All user-facing strings** go in `Resources/en.lproj/Localizable.strings`.
- **All async work** on background `Task`; UI updates on `@MainActor`.
- **Accessibility-permission denial must be graceful** — capture continues,
  injection falls back to clipboard, settings panel surfaces the issue.

---

## 5. Privacy non-negotiables

- API keys / tokens / secrets are scrubbed by `Redactor` before any upload.
- Paths matching `.env`, `.ssh/`, `secrets/`, `private/` are skipped entirely.
- `localOnly` mode must short-circuit every network call.
- The `DEBUG` build logs captures but never POSTs to the API.

---

## 6. Agent control (the headline feature)

The agent is **the product**. `Ithuriel/AgentControl/AgentController.swift`
exposes a full openclaw-style action surface — type, press_keys, click,
move_cursor, screenshot, focus_app, launch_app, quit_app, read_file,
write_file, delete_file, run_shell.

`Ithuriel/Agent/AgentLoop.swift` orchestrates: gather context → POST to
Gemini → execute function calls → feed results back → loop until `done()`
or kill switch or step budget.

**Hard rules** (do not relax without explicit owner approval):

- **Destructive actions** (write_file, delete_file, run_shell, quit_app)
  *always* show an `NSAlert` synchronously. No silent destructive ops.
- **File ops are sandboxed** to `UserPrefs.activeWorkspace`. Outside that
  tree → throw `AgentControlError.fileOutsideSandbox`.
- **Redactor sensitive paths** are refused even inside the sandbox.
- **Kill switch ⌃⌥⌘.** must work mid-action. Check `AgentController.killed`
  at every step boundary.
- **Accessibility** is mandatory for any keyboard/mouse action; if denied,
  agent still loads but actions throw `.accessibilityDenied`.

See PRD §4.1 for the full table of tools.

---

## 7. Definition of done

A change is done when:

- All new files compile without warnings.
- Code matches existing style (4-space indent, no trailing whitespace).
- New user-facing strings are added to `Localizable.strings`.
- If the user asked to commit: a commit was created with a clear message and
  they were told what was staged (see §2.1).
- If the user asked to push: remote is updated after pull/rebase as needed,
  with each git phase narrated.
