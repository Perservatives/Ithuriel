# Ithuriel

> *"Open palm, sees what is hidden. Your computer, on your behalf."*

**Product Requirements Document & Technical Architecture**

| | |
|---|---|
| Product | Ithuriel |
| Version | 2.0 — PRD (agent-first pivot) |
| Author | Rishith |
| Platform | macOS (primary), GCP (optional backend) |
| Agent brain | Google Gemini (function-calling, vision) |
| Status | Pre-build / Draft |
| Date | May 23, 2026 |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Users & Goals](#3-users--goals)
4. [Core Features](#4-core-features)
5. [Technical Architecture](#5-technical-architecture)
6. [Google Cloud Platform Architecture](#6-google-cloud-platform-architecture)
7. [Development Roadmap](#7-development-roadmap)
8. [Success Metrics](#8-success-metrics)
9. [Risks & Mitigations](#9-risks--mitigations)
10. [Open Questions](#10-open-questions)
- [Appendix A: Full Tech Stack](#appendix-a-full-tech-stack)

---

## 1. Executive Summary

Ithuriel is a macOS-native computer-use agent that runs on your Mac with **full project context already loaded**. You type a task into a menu bar prompt — "refactor this file", "run the tests and fix what fails", "draft a PR description from my recent commits" — and Ithuriel uses Google Gemini to drive your keyboard, mouse, file system, and apps to get it done.

Unlike browser-based or sandboxed agents, Ithuriel **lives on the same machine you work on**, with continuous knowledge of your active workspace, git state, recent edits, open files, and terminal history. The agent never starts cold. It picks up where you left off and acts as you would.

> **Core value proposition:** A computer-use agent (openclaw-style) that already knows what you've been doing. One prompt, full execution.

### 1.1 Key differentiators

- **Agent-first, not chat-first** — the headline surface is a single text field that triggers real keyboard/mouse/file actions
- **Full local context** — fed by a passive workspace monitor (FSEvents, NSWorkspace, git, terminal) so prompts don't need re-explaining
- **Gemini brain** — function-calling + vision; screenshots feed back into the loop for true GUI control
- **macOS-native** — pure Swift / SwiftUI, zero third-party dependencies, menu bar app with `LSUIElement`
- **Hard safety gates** — destructive actions (write_file, delete_file, run_shell, quit_app) require modal confirmation; non-destructive actions (type/click/screenshot/read) are fast and silent
- **Global kill switch** — ⌃⌥⌘. instantly halts the agent mid-loop

---

## 2. Problem Statement

### 2.1 Computer-use agents don't know what you're doing

Today's computer-use agents (Claude computer-use, Anthropic Claude desktop, OpenAI Operator, openclaw, browser-based Devin clones) start every session cold. They see a screenshot, guess at the task, and grope around with mouse clicks. They have no memory of your project, your branch, your recent edits, or what you tried five minutes ago.

This means:
- Every prompt has to over-specify ("the file I was just editing", "the test that just failed", "the function I added yesterday")
- The agent burns turns running `ls`, opening files, re-discovering basic state
- Multi-step tasks compound the cost: every step re-explores the same project

### 2.2 Existing computer-use products

| Product | Limitation |
|---|---|
| openclaw | Strong action surface but no continuous context — every session starts blank |
| Claude computer-use | Cloud-hosted in a VM, can't touch your real workspace, expensive per action |
| Anthropic Claude desktop | Chat-first, not action-first; no native filesystem or app control |
| OpenAI Operator | Browser-only, no local file or app access |
| Cursor / Claude Code | Code-editing focus, not general computer use; locked to a single editor |

### 2.3 The gap Ithuriel fills

A computer-use agent that lives natively on macOS **and** carries continuous project context — git state, open files, recent edits, terminal history — into every action it takes. The agent doesn't need to be told what you're working on; it already knows.

---

## 3. Users & Goals

### 3.1 Primary user

| Attribute | Detail |
|---|---|
| Who | Individual software developer or student using 2+ AI coding tools |
| OS | macOS Sonoma 14+ (Sequoia 15 target) |
| Tools used | Any combination of Claude Code, Cursor, Copilot, ChatGPT, Gemini |
| Pain felt | Spends 10–20 min re-explaining project context after every tool switch or rate limit hit |
| Goal | Jump directly into AI-assisted work without preamble |

### 3.2 Secondary users

- Small engineering teams sharing context across developers on the same codebase
- CS students switching between personal AI tools and school-mandated ones
- Freelancers managing multiple client codebases simultaneously

### 3.3 User stories

1. As a developer, I want to type "run the failing test, find the bug, fix it" into Ithuriel and have it execute end-to-end without me describing the project.
2. As a developer, I want Ithuriel to know my active git branch and recent edits without my having to mention them in the prompt.
3. As a developer, I want a global kill switch I can hit if the agent does something I didn't intend.
4. As a developer, I want destructive actions (file writes, shell commands, app quits) to ask before they fire.
5. As a developer, I want all file operations sandboxed to my current workspace so the agent can't accidentally touch `.ssh/` or `~/`.

---

## 4. Core Features

### 4.1 Agent control loop `[MVP — headline feature]`

The primary surface. A menu bar popover with a single prompt field. The user types a task; the agent runs.

**Loop:**

```
1. User types task into menu bar prompt
2. AgentLoop gathers:
     - latest CachedSnapshot (workspace, git, recent edits, terminal)
     - optionally: screenshot of main display
3. POST to Gemini with task + context + tool declarations
4. Parse functionCall(s) from response
5. For each call:
     - if destructive (write_file / delete_file / run_shell / quit_app) → NSAlert
     - else → execute silently via AgentController
     - feed result back as functionResponse
6. Repeat until Gemini calls done() or step budget (25) hits, or kill switch fires
```

**Brain:** Google Gemini (`gemini-3.5-flash` default). User supplies their own API key in Settings → Agent. Stored locally in SwiftData; never uploaded.

**Tool surface (all available to the agent):**

| Tool | Action | Destructive |
|---|---|---|
| `type(text)` | Type literal text via CGEvent | No |
| `press_keys(keys)` | Send a chord like `["cmd","shift","p"]` | No |
| `click(x, y)` | Mouse click at screen coordinates | No |
| `move_cursor(x, y)` | Move the cursor | No |
| `screenshot()` | Capture main display, return base64 JPEG to Gemini for vision | No |
| `focus_app(bundle_id)` | Bring app to front (launch if needed) | No |
| `launch_app(bundle_id)` | Launch app | No |
| `quit_app(bundle_id)` | Terminate app | **Yes** |
| `read_file(path)` | Read UTF-8 file inside workspace sandbox | No |
| `write_file(path, content)` | Write/overwrite file inside workspace sandbox | **Yes** |
| `delete_file(path)` | Delete file inside workspace sandbox | **Yes** |
| `run_shell(command)` | Run zsh command, return stdout+stderr | **Yes** |
| `done(summary)` | Signal task complete | No |

**Safety:**

- Destructive actions raise an `NSAlert` synchronously; agent waits for the modal response before continuing.
- File operations are hard-sandboxed to `UserPrefs.activeWorkspace`. Paths matching the Redactor's sensitive list (`.env`, `.ssh/`, `secrets/`, `private/`) are refused even inside the sandbox.
- Global hotkey **⌃⌥⌘.** (`KillSwitch`) sets `AgentController.killed = true`; the loop checks before every step.
- Accessibility permission is mandatory for any keyboard/mouse action.

### 4.2 Passive workspace monitor `[MVP — context feedstock]`

A background macOS agent (Swift, NSWorkspace + FSEvents) that continuously captures:

- Active VS Code / Xcode / Cursor workspace path and open files
- Recent file edits (last 10 files changed, with diff summaries)
- Active git branch, recent commits, and current diff
- Terminal command history (last 20 commands, configurable)
- Recent clipboard contents when they contain code (opt-in)

### 4.3 Context-aware system prompt `[MVP]`

Before each Gemini turn, the AgentLoop assembles a system prompt that includes:

- Active workspace path
- Git branch, last commit, uncommitted files
- Recently edited files (last 5)
- Recent terminal commands (last 5)
- Hard safety rules (sandbox, destructive-action policy)

This means the user's prompt does not need to repeat any of that — "fix the test" is enough because Gemini already knows which tests, on which branch, in which workspace.

### 4.4 Context-bridge injection `[v1.1 — secondary feature]`

The original Ithuriel use case is preserved as a secondary feature. When the user focuses a supported external AI tool (Claude Code, Cursor, ChatGPT, Claude desktop), Ithuriel formats the current context for that tool and copies it to the pasteboard.

**Supported injection targets:** Claude Code CLI, Cursor, ChatGPT (web + desktop), GitHub Copilot Chat, Claude desktop. Format per target (CLAUDE.md / `.cursorrules` / system message) is selected automatically.

### 4.5 Privacy controls `[MVP]`

- **Sensitive path redaction:** the Redactor scrubs API-key patterns (`sk-`, `ghp_`, `AIza`, `xoxb-`, `api_key=…`) from anything sent to Gemini or any cloud backend.
- **Path filter:** paths containing `.env`, `.ssh/`, `secrets/`, `private/` are excluded from context snapshots AND refused by the agent file sandbox.
- **Local-only mode:** disables the optional cloud backend (§6). The Gemini API call still happens — disclose this clearly in onboarding.
- **Workspace sandbox:** all `read_file` / `write_file` / `delete_file` calls are pinned to `UserPrefs.activeWorkspace`.

### 4.6 Context history & snapshots `[v1.1]`

Every captured `ContextSnapshot` is persisted to SwiftData locally (last 50 entries kept). Optional Firestore sync for cross-device. The popover shows the latest workspace and lets the user copy the formatted context manually.

### 4.7 Team context sync `[v2.0]`

Developers on the same Git repository can opt-in to a shared context channel. When one developer's agent solves a tricky bug, the resulting reasoning + diff is broadcast to teammates.

---

## 5. Technical Architecture

### 5.1 System overview

The app runs entirely on macOS. The agent loop is the centre; the workspace monitor feeds it context; Gemini drives decision-making; AgentController executes actions on the real machine. Cloud backend (§6) is optional.

```
Agent loop:

  ┌──────────── menu bar prompt ────────────┐
  │   "fix the failing test and re-run"      │
  └──────────────────┬───────────────────────┘
                     ▼
              AgentLoop.run(task)
                     │
                     │  1. gather context (CachedSnapshot)
                     │  2. build system prompt
                     │  3. POST to Gemini /v1beta/generateContent
                     ▼
              ┌──────────────┐
              │  Gemini API  │  (function-calling, vision)
              └──────┬───────┘
                     │  functionCall(s)
                     ▼
              AgentController
                ├── type / press_keys / click / move_cursor
                ├── screenshot          → base64 JPEG back to Gemini
                ├── focus / launch / quit app
                ├── read_file / write_file / delete_file  (sandboxed)
                └── run_shell                            (destructive → NSAlert)
                     │  functionResponse
                     ▼
              loop until done() OR kill switch OR step budget

Background, continuous:

  FSEvents / NSWorkspace / git / terminal
                     │
                     ▼
              ContextSnapshot
                     │  (Redactor)
                     ▼
              SwiftData CachedSnapshot   ← read by AgentLoop on every run

Optional cloud (§6):
  ContextSnapshot ──► Cloud Run API ──► Pub/Sub ──► Firestore / GCS
```

### 5.2 Component breakdown

| Component | Technology | Responsibility |
|---|---|---|
| macOS Agent (host) | Swift 5.9 / SwiftUI | Menu bar app. Hosts the agent loop. Monitors FSEvents, NSWorkspace, terminal. |
| AgentLoop | Swift, `@MainActor` | Drives Gemini turn-by-turn. Parses function calls, dispatches to AgentController, feeds responses back. Step budget 25. |
| AgentController | Swift + CGEvent + NSWorkspace | Executes type / click / hotkey / screenshot / launch / file / shell actions. Hard-sandboxed file ops. NSAlert on destructive actions. |
| KillSwitch | Carbon RegisterEventHotKey | Global ⌃⌥⌘. hotkey. Sets `AgentController.killed`. |
| GeminiClient | URLSession + JSON | v1beta `generateContent` with function-calling + inlineData (vision). |
| ContextSnapshot store | SwiftData | Local persistence of last 50 snapshots. Feeds the agent system prompt. |
| VS Code Extension | TypeScript / VS Code API | Captures open file tree, cursor position, recent edits, workspace config. Posts to API on change events. |
| Ithuriel API | Node.js + TypeScript / Cloud Run | REST + WebSocket API. Receives snapshots, triggers processing pipeline, serves formatted context. |
| Context Processor | Python / Cloud Functions gen2 | Subscribes to Pub/Sub. Calls Vertex AI. Writes to Firestore + GCS. |
| Context Store | Firestore + Cloud Storage | Firestore: metadata, user prefs, snapshot index. GCS: raw and processed snapshot blobs. |
| Real-time sync | Cloud Pub/Sub | Decouples ingestion from processing. Enables team broadcast for v2.0. |
| Web Dashboard | React + Vite / Cloud Run | Context history, integration settings, privacy controls, team sync management. |
| Auth | Firebase Auth + Cloud IAM | Google/GitHub OAuth for users. Service account for agent-to-API. |

### 5.3 macOS agent deep dive

#### Capture subsystems

| Subsystem | API / Method | Detail |
|---|---|---|
| File watcher | `FSEventStream` | Watches active workspace directory, 5-second debounce |
| App detection | `NSWorkspace.shared.frontmostApplication` | Detects active app switches in real time |
| Terminal history | `ProcessInfo` + `libproc` | Reads terminal PID, extracts recent shell history via `$HISTFILE` |
| Git state | Git CLI subprocess | Runs `git status`, `git log --oneline -10`, `git diff --stat` on 30s timer |
| Clipboard | `NSPasteboard` monitoring | Opt-in capture of code-shaped clipboard contents |

#### Privacy scrubbing (on-device, pre-upload)

- Regex pass removes any token matching API key patterns (`sk-`, `ghp_`, `xoxb-`, `AIza`, etc.)
- Path filter excludes files in `.env`, `.ssh/`, `secrets/`, `private/` subdirectories
- Local-only mode: SwiftData local store only, Vertex AI replaced with on-device CoreML DistilBERT summarizer

#### Injection mechanism

- Accessibility API (`AXUIElement`) detects target tool focus events
- Clipboard injection: `NSPasteboard.general.setString()` writes formatted context
- Type-injection (allowlisted apps only): `CGEventPost` with keystroke simulation
- Configurable per-app: clipboard-only, auto-type, or manual trigger via hotkey

### 5.4 API design

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/v1/context/snapshot` | Bearer JWT | Receive raw context snapshot from macOS agent or VS Code extension |
| `GET` | `/v1/context/current` | Bearer JWT | Return latest processed context, formatted for specified target tool |
| `GET` | `/v1/context/history` | Bearer JWT | Return paginated list of past snapshots |
| `GET` | `/v1/context/:id` | Bearer JWT | Return specific snapshot by ID |
| `POST` | `/v1/context/inject` | Bearer JWT | Generate tool-specific injection payload (cursor|claude|chatgpt|copilot) |
| `WS` | `/v1/context/stream` | Bearer JWT | WebSocket — pushes real-time context updates to connected agent |
| `POST` | `/v1/team/broadcast` | Bearer JWT | Broadcast context snapshot to all team members on same repo |
| `GET` | `/v1/health` | None | Health check for Cloud Run load balancer |

### 5.5 Data model

#### Firestore: `users/{uid}`

```json
{
  "id": "string — Firebase Auth UID",
  "email": "string",
  "plan": "free | pro | team",
  "prefs": {
    "redactKeys": true,
    "localOnly": false,
    "targetTools": ["claude", "cursor", "chatgpt"],
    "excludePaths": [".env", "secrets/"]
  },
  "createdAt": "Timestamp"
}
```

#### Firestore: `users/{uid}/snapshots/{snapshotId}`

```json
{
  "id": "string — UUID v4",
  "capturedAt": "Timestamp",
  "source": "vscode | xcode | cursor | terminal",
  "rawRef": "string — GCS object path",
  "summaryShort": "string — 100-token Vertex AI summary",
  "summaryMedium": "string — 500-token summary",
  "summaryFull": "string — 2000-token summary",
  "embeddingRef": "string — GCS path to 1536-dim vector",
  "gitBranch": "string",
  "gitCommit": "string — latest commit SHA",
  "activeFiles": ["string — redacted paths"],
  "recentEdits": [{ "path": "", "linesAdded": 0, "linesRemoved": 0, "summary": "" }],
  "terminalHistory": ["string — last N commands"]
}
```

#### Firestore: `teams/{teamId}`

```json
{
  "id": "string",
  "repoUrl": "string — used to match members by Git remote",
  "memberUids": ["string"],
  "sharedSnapshotId": "string — latest team broadcast snapshot"
}
```

---

## 6. Google Cloud Platform Architecture

### 6.1 GCP services inventory

| GCP Service | Tier / Config | Usage in Ithuriel |
|---|---|---|
| Cloud Run | min 0 / max 10 instances, 1 vCPU 512 MB | Hosts Ithuriel REST API (Node.js) and Web Dashboard (React). Auto-scales to zero on inactivity. |
| Cloud Pub/Sub | Standard tier, global topic | Decouples snapshot ingestion from Vertex AI processing. Enables async team broadcast. |
| Cloud Firestore | Native mode, us-central1 | Primary database for users, snapshot metadata, team state. Real-time listeners for agent sync. |
| Cloud Storage | Standard storage, us-central1 | Raw snapshot blobs and embedding vectors. Lifecycle: auto-delete after 90 days. |
| Vertex AI Gemini Flash | `gemini-1.5-flash-001` | Fast summarization for short + medium context lengths. |
| Vertex AI Gemini Pro | `gemini-1.5-pro-001` | High-quality full summaries and tool-specific formatting. |
| Vertex AI Embeddings | `text-embedding-005` | 1536-dim embeddings for semantic context search and dedup detection. |
| Cloud Functions gen2 | Python 3.12, 2 vCPU, 4 GB | Context processing subscriber — Pub/Sub → Vertex AI → Firestore + GCS. |
| Firebase Auth | Google + GitHub OAuth | User authentication. Issues JWTs validated by Cloud Run API. |
| Secret Manager | 1 version per secret, auto-rotation | Stores Vertex AI keys, GitHub OAuth secrets, service account credentials. |
| Cloud Build | E2 machine type | CI/CD: lint + test → Docker build → Artifact Registry → Cloud Run deploy. |
| Artifact Registry | Docker format, us-central1 | Versioned Docker images for API and Dashboard containers. |
| Cloud Monitoring | Custom dashboards + uptime checks | API latency, Pub/Sub lag, Vertex AI quota, error rates. |
| Cloud Logging | 30-day retention | Structured JSON logs from all Cloud Run instances and Cloud Functions. |
| Cloud IAM | Least-privilege service accounts | Separate accounts for API, Cloud Functions, and CI/CD. |
| Cloud Armor | WAF on Load Balancer | Rate limiting 100 req/min per IP, SQLi/XSS rule sets. |

### 6.2 Ingestion pipeline (step by step)

```
1. macOS agent POSTs snapshot  →  POST /v1/context/snapshot
2. Cloud Run API validates JWT, redacts PII
3. API publishes message to Pub/Sub topic: ithuriel-snapshots
4. Cloud Function pulls message within <2s
5. Function calls Vertex AI Gemini Flash  →  short + medium summaries  (<1s)
6. Function calls Vertex AI Gemini Pro    →  full summary              (<3s)
7. Function calls Embeddings API          →  1536-dim vector           (<1s)
8. Writes metadata + summaries  →  Firestore
9. Writes raw blob + embedding  →  Cloud Storage
10. Publishes completion event  →  ithuriel-processed topic
11. Cloud Run WebSocket pushes update  →  macOS agent
```

Total end-to-end latency target: **< 4 seconds**

### 6.3 CI/CD pipeline

```
GitHub push to main
    │
    ▼
Cloud Build trigger
    ├── ESLint + Jest unit tests
    ├── Docker multi-stage build  →  minimal production image
    ├── Push to Artifact Registry  (tagged with commit SHA)
    └── Cloud Run deploy
            └── 10% canary traffic split
                    └── 100% after 15-min health check passes
```

### 6.4 Security architecture

| Layer | Control |
|---|---|
| API auth | Firebase Auth JWT validation middleware on all endpoints |
| Database | Firestore security rules: users read/write own documents only |
| Object storage | GCS bucket private; access via signed URLs generated by Cloud Run |
| Messaging | Pub/Sub: service account auth only, no public access |
| Secrets | Secret Manager injects env vars at Cloud Run startup — never in image |
| Network perimeter | VPC Service Controls: Firestore, GCS, Pub/Sub locked to Ithuriel project |
| WAF | Cloud Armor: 100 req/min/IP rate limit, SQLi/XSS rules |

### 6.5 Cost estimate (per 1,000 active users/month)

| Service | Estimated cost |
|---|---|
| Cloud Run (API) | ~$12 |
| Firestore | ~$8 |
| Cloud Storage | ~$5 |
| Vertex AI Gemini Flash | ~$45 |
| Vertex AI Embeddings | ~$10 |
| Cloud Functions | ~$4 |
| Cloud Pub/Sub | ~$3 |
| **Total** | **~$87 / month (~$0.09 / user / month)** |

---

## 7. Development Roadmap

### Phase 1 — MVP (Weeks 1–4)

> Goal: A working macOS menu bar app that captures VS Code context and injects it into Claude Code via clipboard.

- **Week 1:** macOS agent skeleton (Swift menu bar, FSEvents, NSWorkspace)
- **Week 1:** GCP project setup — Terraform, Firebase Auth, Cloud Run scaffold, Firestore schema
- **Week 2:** VS Code extension — workspace capture, file tree, git status, API post
- **Week 2:** Cloud Run API — `/v1/context/snapshot` and `/v1/context/current` endpoints
- **Week 3:** Pub/Sub → Cloud Function → Vertex AI Gemini summarization pipeline
- **Week 3:** Clipboard injection for Claude Code target
- **Week 4:** Privacy scrubbing, local-only mode toggle, menu bar status UI
- **Week 4:** End-to-end integration test: VS Code edit → API → Vertex AI → Claude Code clipboard

### Phase 2 — Multi-tool + Web Dashboard (Weeks 5–8)

- Tool-specific formatting: Cursor (`.cursorrules`), ChatGPT (system message), Copilot Chat
- Rate-limit detection and resume prompt generation
- Web dashboard: context history timeline, snapshot viewer
- Firestore-powered context history with 90-day retention
- Cloud Monitoring dashboards + uptime alerts

### Phase 3 — Polish + Team (Weeks 9–12)

- Xcode integration (in addition to VS Code)
- Semantic search over context history (Vertex AI Embeddings)
- Team context sync via Pub/Sub broadcast channel
- Homebrew Cask distribution + onboarding flow
- Performance: context snapshot latency target < 4 seconds end-to-end

---

## 8. Success Metrics

| Metric | Target |
|---|---|
| Daily active agents | 500 installs with agent running daily by end of Month 2 |
| Context injection rate | > 80% of tool switches result in successful injection |
| End-to-end latency | < 4 seconds from file edit to context ready |
| Vertex AI accuracy | > 90% of users rate injected summary as "relevant" |
| Privacy compliance | 0 API keys or secrets stored in Firestore / GCS |
| API uptime | 99.5% monthly uptime on Cloud Run |
| Cost per user | < $0.15 / active user / month at 1,000 users |
| Time saved | Users report saving > 10 min/day of re-explanation (NPS survey) |

---

## 9. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| macOS Accessibility API restrictions | Clipboard-only mode as fallback; direct DMG/Homebrew distribution (no App Store dependency for v1) |
| Developer trust / privacy concerns | Local-only mode as first-class option; open-source the agent; visible on-screen capture indicator |
| Vertex AI cost spikes | Client-side debouncing (min 30s between snapshots); quota alerts in Cloud Monitoring; Gemini Flash for non-full summaries |
| Context quality degradation | User feedback loop (thumbs up/down); prompt iteration using low-rated examples as training signal |
| Competitive response from Cursor/Claude Code | Ship fast; deep macOS integration that web-first companies deprioritize; multi-tool angle as core differentiator |
| Rate limit detection fragility | Manual hotkey trigger as primary UX; auto-detection as bonus layer |

---

## 10. Open Questions

1. Should the workspace sandbox be strict (one directory) or allow multiple allowlisted roots (e.g. `~/Developer/*`)?
2. Should we offer an "autonomous mode" toggle that suppresses destructive-action prompts after N confirmations on similar actions in the same session?
3. Is Gemini 2.0 Flash sufficient for multi-step reasoning, or should Pro be the default with Flash as a fast-path?
4. How should we expose recent agent runs — a transcript log in the popover only, or a full timeline view in Settings?
5. Should Ithuriel support a no-screenshot mode for users who don't want screen captures sent to Google?
6. What is the right pricing model — bring-your-own-Gemini-key free tier, $10/mo for managed Gemini quota?

---

## Appendix A: Full Tech Stack

| Component | Technology | Notes |
|---|---|---|
| macOS Agent | Swift 5.9 / SwiftUI 5 | Menu bar app, FSEvents, NSWorkspace, Accessibility API, SwiftData local store |
| VS Code Extension | TypeScript 5 / VS Code Extension API | Workspace capture, file watcher, git integration, HTTP client |
| Cloud Run API | Node.js 20 + TypeScript + Fastify | REST endpoints, WebSocket, Firebase Auth middleware, Pub/Sub publisher |
| Context Processor | Python 3.12 + google-cloud-aiplatform | Pub/Sub subscriber, Vertex AI calls, Firestore + GCS writes |
| Web Dashboard | React 18 + Vite + TailwindCSS | Context timeline, snapshot viewer, settings, team management |
| Database | Cloud Firestore (Native mode) | User data, snapshot metadata, team state |
| Object Storage | Cloud Storage (Standard) | Raw snapshot blobs, embedding vectors, 90-day lifecycle |
| AI / ML | Vertex AI Gemini 1.5 Flash/Pro + text-embedding-005 | Summarization (3 lengths), 1536-dim embeddings |
| Auth | Firebase Authentication | Google + GitHub OAuth, JWT issuance |
| Messaging | Cloud Pub/Sub | Async pipeline decoupling, team broadcast |
| Serverless | Cloud Functions gen2 (Python) | Context processing subscriber |
| IaC | Terraform 1.7 + google provider | All GCP resources defined as code |
| CI/CD | Cloud Build + Artifact Registry | Automated test → build → deploy pipeline |
| Monitoring | Cloud Monitoring + Cloud Logging | Metrics, dashboards, alerts, structured logs |
| Security | Secret Manager + Cloud Armor + VPC SC | Secrets, WAF, service perimeter |
| Distribution | Homebrew Cask + GitHub Releases | Direct DMG + Homebrew tap for macOS agent |

---

*Ithuriel — named for the angel in Paradise Lost whose spear reveals what is hidden. Your AI sees what you've been doing.*
