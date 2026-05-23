# AGENTS.md — Ithuriel

Agent guidance for anyone (human or AI) working in this repo. Read this first.

---

## 1. What this project is

Ithuriel is a macOS-native AI context orchestration tool. A menu bar agent
silently captures workspace state (open files, git, terminal, recent edits)
and injects formatted context into the active AI coding tool (Claude Code,
Cursor, ChatGPT, Claude desktop, Copilot, Gemini) the moment it gains focus.

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
└── Ithuriel/                       # Swift app source
    ├── IthurielApp.swift           # entry point, AppDelegate, timer loop
    ├── MenuBarManager.swift        # NSStatusItem + popover
    ├── Capture/                    # FSEvents, NSWorkspace, git, terminal
    ├── Privacy/                    # Redactor (regex + path filter)
    ├── Injection/                  # Pasteboard + CGEvent type-inject
    ├── API/                        # IthurielClient (REST + WebSocket)
    ├── Models/                     # ContextSnapshot, UserPrefs (SwiftData)
    ├── Views/                      # StatusBarView, SettingsView
    ├── AgentControl/               # opt-in computer-use hand-off
    └── Resources/                  # Info.plist, Localizable.strings
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

## 6. Agent control (opt-in feature)

`Ithuriel/AgentControl/AgentController.swift` can focus a target AI tool,
paste context, and press Return on the user's behalf. It is **off by default**
and only fires on explicit user invocation. The `submitPrompt` action always
shows an `NSAlert` for one-shot consent. See PRD §4.8.

---

## 7. Definition of done

A change is done when:

- All new files compile without warnings.
- Code matches existing style (4-space indent, no trailing whitespace).
- New user-facing strings are added to `Localizable.strings`.
- A commit has been created and pushed to the remote.
- If the remote had diverged, the pull-and-combine workflow was used.
