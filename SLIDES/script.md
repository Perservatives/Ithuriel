# Ithuriel — 3-minute hackathon script (3 speakers)

Total: **about 3 minutes**. Three people, ~60 seconds each. Slide numbers
match `index.html` (← / → to move).

One line to remember if you forget everything else:
**"We got tired of re-explaining our project to every AI tool."**

Tone: talk to the room like they're engineers who've lived this problem.
No pitch voice. If something breaks in the demo, say so — that's fine.

---

## Speaker 1 — Why we built it  (≈ 60 s)

**Slides 1–2.**

> *(Slide 1)*
> Hey — we're **Ithuriel**. It's a small Mac app that sits in your menu bar
> and actually runs tasks on your machine: open files, run tests, click
> around, that kind of thing.
>
> The idea isn't "another chatbot." It's: you already have the project open,
> the terminal history, the git branch — the agent should know that before
> you type anything.
>
> *(Slide 2)*
> If you use Claude, ChatGPT, and Cursor in the same day, you know the drill.
> Every new session starts empty. You paste the same README paragraph. You
> re-describe the bug. You explain which repo folder matters.
>
> We built this because we were doing that four or five times a day and it
> felt stupid. That's the whole motivation.

Hand off: *"Okay — so what does using it actually look like?"*

---

## Speaker 2 — Demo walkthrough  (≈ 90 s)

**Slides 3–5.** This person has the keyboard / live build if you have one.

> *(Slide 3)*
> **Option-Space** opens a small prompt over whatever app you're in. Type a
> task, hit return. If you want the full chat window, escalate from there.
>
> Hold the same shortcut to talk — we send audio to **OpenAI Whisper**, run
> the agent, and optionally speak the answer back. **Control-Option-Command-period**
> is a kill switch. We wired it globally because computer-use agents need
> an off button you can hit without thinking.
>
> *(Slide 4)*
> The main window is a normal chat UI — sidebar, history, composer at the
> bottom. Settings is a gear in the corner. Nothing exotic; we wanted it to
> feel like software you've used before.
>
> *(Slide 5)*
> When the agent runs, we hide the noisy middle by default. You see the task,
> a compact "used N tools" chip if you want details, and the answer — not fifty
> lines of `run_shell` spam unless you expand it.
>
> *(Optional: live demo here — Option-Space, type something small like
> "what's my git status", let it run 10 seconds, then advance.)*

Hand off: *"Quick look at what's running under the hood."*

---

## Speaker 3 — How it works + wrap  (≈ 60 s)

**Slides 6–10.** Move quickly through 6–8; land the close on 10.

> *(Slide 6)*
> While you're working, Ithuriel quietly watches the workspace — file changes,
> open editor, git state, recent terminal commands. Before each agent turn we
> bundle that into a context snapshot. Secrets get scrubbed first; `.env` and
> `.ssh` never leave the machine.
>
> *(Slide 7)*
> The Mac app is Swift and SwiftUI — no npm in the agent core. Gemini handles
> planning and tool calls; screenshots go through vision when needed. If you're
> signed in, snapshots can sync to our GCP project for search across past work.
>
> *(Slide 8 — skim)*
> File writes stay in your chosen workspace. Destructive stuff can ask for
> confirmation. Permissions only when you actually need a feature — we're not
> going to nag you on every launch.
>
> *(Slide 9 — skip if tight on time)*
> Rough scale: on the order of seventy Swift files, about a dozen agent tools,
> macOS 14+. We cared more about it working on a real Mac than hitting slide
> metrics.
>
> *(Slide 10)*
> Repo is on GitHub. Try Option-Space, give it something you'd actually ask an
> intern to do, and see if it saves you the re-explaining step. Thanks.

---

## Timing

| Block | Slides | Time |
|---|---|---|
| Speaker 1 | 1–2 | 0:00 → 1:00 |
| Speaker 2 | 3–5 (+ demo?) | 1:00 → 2:30 |
| Speaker 3 | 6–10 | 2:30 → 3:00 |

## Rehearsal tips

- Read it out loud once. Cut any sentence that sounds like a landing page.
- Hand-offs matter more than perfect wording — keep momentum.
- Slide 9 is the first one to drop if you're over.
- A real 10-second demo beats five slides of architecture.

## Lines that actually help (not slogans)

- *"Every new session starts empty — we got tired of that."*
- *"Option-Space, type the task, get out of the way."*
- *"It reads like chat, not a debug log."*
- *"Kill switch because agents that type for you need an off button."*
