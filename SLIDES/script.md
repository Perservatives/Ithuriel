# Ithuriel — 3-minute hackathon script (3 speakers)

Total runtime: **3:00**. Three speakers, ~60 seconds each, with hand-offs
on the slide-advance click. Slide numbers map to `index.html` (←/→ to
navigate).

Tagline to land repeatedly: *"Your AI never starts cold again."*

Tone: confident, conversational. Read it like you mean it. No selling
to the audience — let the demo do the work.

---

## Speaker 1 — Hook & Problem  (≈ 60 s)

**Slides 1–2.** Stand on slide 1 for the first three sentences while the
team is finding their seats.

> *(Slide 1 — title up.)*
> Hi — we're showing **Ithuriel**. The shortest pitch: it's a
> Mac-native agent that already knows what you're working on, so you
> stop explaining and start working.
>
> *(Click → Slide 2 — the cold-start tax.)*
> Here's the thing every AI tool gets wrong today. Claude, ChatGPT,
> Cursor — they all start every session blank. So you sit down and
> the first ten minutes of every conversation is you re-pasting files,
> re-explaining the architecture, telling it what branch you're on,
> what test failed last night. Stack Overflow's 2025 survey: 76% of
> developers use two or more AI tools daily. Multiply that by the
> re-explanation tax and we're losing 45 to 75 minutes a day per
> engineer. That's the problem we set out to solve.

Hand off — *"so what does that actually look like?"*

---

## Speaker 2 — Solution & Demo  (≈ 90 s)

**Slides 3–5.** This person drives the keyboard.

> *(Slide 3 — One prompt, full execution.)*
> One global shortcut — Control-Space — opens a floating prompt
> anywhere on macOS. The pill is draggable, the chrome is light, no
> heavy shadow. The icon on the left is our eight-point burst — it
> spins while the agent is thinking.
>
> *(Slide 4 — Headline surface.)*
> Tap to summon, hold to talk — that hold gesture routes through
> Google Cloud Speech-to-Text, runs the agent, and speaks the result
> back via Cloud TTS. Escape dismisses, and Control-Option-Command-
> period is a global kill switch we wired everywhere — long-running
> agent, mid-keystroke, anywhere on the machine.
>
> *(Slide 5 — Conversational rendering.)*
> The output is the part we're proudest of. By default Ithuriel does
> **not** show you every tool call. It hides them behind a single
> chip: "Used six tools — click to expand." Inside, a thinking row
> mutates in place from "thinking" to "still thinking" to "almost
> done thinking" — the Claude Code pattern. You only see the final
> answer unless you ask for more. It reads like a conversation, not
> a log.

Hand off — *"and here's how it actually knows what you're doing."*

---

## Speaker 3 — Under-the-hood & Close  (≈ 60 s)

**Slides 6–10.** Move fast through 6 → 7, slow down on 10.

> *(Slide 6 — Context plumbing.)*
> Five subsystems run in the background on every Mac: FSEvents for
> file changes, NSWorkspace for the active editor, a git capture
> probe, terminal-history scrape, and a Redactor that scrubs API
> keys and `.env` paths before anything leaves the machine. Every
> agent turn gets a fresh ContextSnapshot. The agent never re-asks
> "what file?".
>
> *(Slide 7 — Tech.)*
> Pure Swift, SwiftUI, macOS 14. Brain is Gemini 3.5 Flash, talking
> function-calls and vision. Snapshots stream into our Google Cloud
> project — **synthesis-hack26svl-121** — through Pub/Sub into a
> Cloud Function that hands every snapshot to Vertex AI for a 768-dim
> embedding. Semantic search across your project history is one
> cosine-similarity call away.
>
> *(Slide 8 — Safety, fast pass.)*
> File ops sandboxed to the workspace, destructive actions can prompt,
> permissions are lazy — Ithuriel never asks for what you've already
> granted. And the kill switch.
>
> *(Slide 9 — By the numbers, optional, ~10 s.)*
> Seventy Swift files, thirteen agent tools, 1.10-second launch
> animation that respects Reduce Motion, 768-dim Vertex AI vectors,
> one global shortcut.
>
> *(Slide 10 — Close.)*
> Tap Control-Space. Tell it what you want. Get back to work. Your
> AI never starts cold again. Thanks.

---

## Timing cheat sheet

| Block | Slides | Cumulative |
|---|---|---|
| Speaker 1 — Hook + Problem | 1–2 | 0:00 → 1:00 |
| Speaker 2 — Solution + Demo | 3–5 | 1:00 → 2:30 |
| Speaker 3 — Tech + Safety + Close | 6–10 | 2:30 → 3:00 |

## Rehearsal notes

- Practice the hand-offs out loud. The phrases above ("so what does
  that actually look like?" / "and here's how it actually knows what
  you're doing") are designed so the next speaker can start
  immediately without a beat of silence.
- If Speaker 2 over-runs, the easiest slide for Speaker 3 to skip is
  Slide 9 ("by the numbers"). The pitch still lands.
- The Spotlight pill on Slide 4 is a *static mock-up* of the live UI.
  If you have a working build, demo the real app between Slides 4
  and 5 — Control-Space, type "refactor the failing test", let it
  run for ~10 seconds, then advance to Slide 5 to explain what the
  audience just saw.
- Keep the eight-point burst on screen as much as possible. It's the
  thing the audience will remember an hour later.

## Lines worth memorising

- *"Your AI never starts cold again."*
- *"Tap Control-Space, tell it what you want, get back to work."*
- *"It reads like a conversation, not a log."*
- *"Permission-cheap, kill-switch-cheap."*
