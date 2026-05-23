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
2. **Always commit and push to the git remote.** When you finish a unit of
   work, create a commit with a clear message and `git push`. The owner has
   pre-authorized push.
3. **When push is rejected because remote diverged: pull and combine.**
   Run `git pull --rebase`, resolve any conflicts by combining both sides
   (never discard remote work or local work silently), then push again.
4. **Never force-push** (`--force`, `--force-with-lease`) unless the owner
   explicitly asks.
5. **Never skip hooks** (`--no-verify`) unless explicitly asked.

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
- A commit has been created and pushed to the remote.
- If the remote had diverged, the pull-and-combine workflow was used.
