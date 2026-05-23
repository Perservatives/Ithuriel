# SLIDES/

Self-contained hackathon deck for **Ithuriel**.

## Files

- `index.html` — 10-slide presentation. Single file, no dependencies.
  Keyboard nav: `←` / `→` / `Space` / `PageUp` / `PageDown` / `Home` /
  `End`. Click the right half to advance, left half to go back.
- `script.md` — 3-minute speaking script for 3 presenters.

## To present

Open `index.html` in any modern browser (Safari, Chrome, Firefox, Arc).
Press `F` for browser fullscreen. The deck adapts to any aspect ratio
and prints to PDF cleanly (each slide one page).

## Customising

- Brand colour lives in the `:root --accent` variable.
- Page background is `--bg` (`#F8F8F7`, the same off-white the app
  uses for its launch backdrop).
- The 8-petal asterisk is an inline SVG `<symbol id="burst">` —
  reference it anywhere with `<svg><use href="#burst"/></svg>`.
