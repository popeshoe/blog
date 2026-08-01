# Plan: bake the theme cycle into CSS

Branch: `theme-baked-cycle`. Reference prototype: `static/theme-prototype-2.html`.

## Goal

Replace the JS-driven keyframe-rewrite engine with one baked `@keyframes` rule
covering all 20 colours, positioned by wall-clock. Kills in one change:

- the Safari failure (`keyText` matching against `from`/`to` + CSSOM mutation)
- the Firefox `var()`-in-keyframes workaround
- `oklch(from ...)` at runtime, the other Safari suspect
- the 70s rotation timer, the `<noscript>` block, and the dev-palette monkeypatch

## Timings

20 colours x 70s = **1400s loop**. Per colour: 55s transition (3.928571%) then
15s hold. Epoch = 5%. 41 keyframe stops: one at 0%, then "reached"/"held" per
colour. 100% and 0% carry the same colour, which makes the wrap seamless.

## Steps

### 1. Generator — `scripts/bake_palette.py`

The 20 hexes live **only** here — moved out of `colours.html`, not duplicated
anywhere. One place to edit means the generated block can't drift from a
palette changed elsewhere.

Two modes:

- default — write the generated block into `main.css` between the markers
- `--check` — regenerate, diff against what's committed, exit non-zero on
  mismatch. This is what CI runs.

Per colour it emits `--accent-fill` and `--accent-text`, each a `light-dark()`
pair, applying the same clamps `main.css` uses today:

| token | light | dark |
|---|---|---|
| `--accent-fill` | `min(l, 0.62)` | `clamp(0.22, l, 0.32)` |
| `--accent-text` | `clamp(0.35, l, 0.55)` | `clamp(0.62, l, 0.85)` |

Then chroma-map each result into sRGB (binary search on C) so no browser has to
gamut-map — engines differ in strategy, and baking is what lets us settle it
once. Emit as absolute `oklch()`, not hex: only the *relative* `from` syntax is
the Safari suspect, and staying in oklch keeps the precision.

**No contrast assertion.** 10 of the 20 entries are already below 4.5:1 for
sidebar text and 0 are below 3:1 — the 4.5 shortfall is the deliberate
trade-off documented at `main.css:126`, not a defect. A gate would fail on day
one and get suppressed. Judgement moves to the colour lab (step 6).

Output goes into `main.css` between `/* BEGIN generated */` markers and is
**committed**. Hugo has no shell escape so it can't run this itself; the
generated CSS living in the repo keeps `hugo server` working with no
prerequisite step and keeps Python off the deploy path.

### 2. `assets/css/main.css`

- Delete `@property --theme-color`, the four `oklch(from ...)` lines, and
  `--accent-fill-dark` (it was only the dark branch of the fill).
- Add `@property --accent-fill` and `--accent-text`, `syntax: "<color>"`,
  `inherits: true`.
- Replace the placeholder `@keyframes theme-cycle` with the generated block.
- `body { animation: theme-cycle 1400s ease infinite; }` plus a static
  `--accent-fill` / `--accent-text` pair. That pair is the **old-browser safety
  net**: anything without `@property` or without animatable custom properties
  falls back to one real colour instead of an unthemed page.
- Rewrite the section 2 header comment — it documents the Firefox workaround
  that no longer exists.
- Reduced motion becomes `body { animation-play-state: paused; }` instead of
  `animation: none`. The JS seek still positions it, so those visitors get the
  same colour as everyone else with zero movement, and it changes between page
  loads exactly as it does today. This is a **fix**, not just a port: `animation:
  none` would have frozen them on one colour forever.
- Leave every `color-mix()` consumer alone. Different feature, far better
  support, and they keep tracking the interpolating value.

### 3. `layouts/partials/colours.html`

Collapses to roughly:

```js
var CYCLE_MS = 1400000;
var anim = document.body.getAnimations()
  .find(a => a.animationName === "theme-cycle");
if (anim) anim.currentTime = Date.now() % CYCLE_MS;
```

Seek by `currentTime`, not `animation-delay` — delay is measured from the
animation's own start time, so re-seeking later lands at `elapsed + position`
instead of `position`. (Hit this in prototype 2; the "jump" was the bug.)
Fallback where `getAnimations` is missing: restart the animation, then negative
delay.

Deleted: `COLOURS`, `seededRandom`, `permutationForRound`,
`correctedPermutationForRound`, `colourForEpoch`, `currentEpoch`,
`findThemeCycleKeyframesRule`, `startTransition`, `applyInitialColour`,
`scheduleRotation`, the `visibilitychange` handler, the reduced-motion branch,
and the `theme-base-*` class swap.

No timer: a CSS animation advances on the document timeline, so a throttled tab
can't desynchronise it. **This is assumed, not verified** — see Risks.

### 4. `layouts/partials/dev-palette.html`

Pin = `anim.pause(); anim.currentTime = holdPosition(i)`. Resume = seek to
wall-clock, then `play()`. Delete the `realStart`/`realSeek` monkeypatch: it
only existed to stop the rotation timer stomping the pin, and there is no timer
now.

Swatches: sample a hidden probe running the same animation, paused at each hold
position, reading back computed `--accent-fill`. The `COLOURS` global it reads
today won't exist.

### 5. `layouts/partials/head.html` + `hugo.json`

- Delete the `<noscript>` block. Without JS the animation runs unsynchronised,
  which beats a pinned static colour.
- `themeColor` param drops `theme-base-0f`, keeps `layout-reverse`. The class
  has been a devtools label with no matching CSS since `18edf2c`.

### 6. Colour lab — `/colour-lab/`

`content/colour-lab.md` (`_build: { list: never }`) plus
`layouts/colour-lab.html`, the whole layout wrapped in `{{ if hugo.IsServer }}`
like `dev-palette.html`. Real page under `hugo server`, blank and unlisted in
production.

Shows, for both light and dark:

- all 20 baked entries — fill, text, and their WCAG ratios against white and
  against the page surface
- a free-text colour input that previews a candidate through the same clamps
- contrast numbers flagged but **not** treated as pass/fail, so you can see the
  4.5:1 shortfall and decide per colour

The browser does all the maths: real entries are sampled from the baked CSS
(hidden probe, same trick as the dev-palette swatches), custom input goes
through `oklch(from ...)` live, and ratios are ~10 lines of WCAG over the
resolved rgb. Nothing duplicates `bake_palette.py`. Using `oklch(from ...)`
here is fine precisely because this page never ships.

### 7. CI — `.github/workflows/main.yaml`

One step before `Build`:

```yaml
      - name: Check baked palette
        run: python3 scripts/bake_palette.py --check
```

`ubuntu-latest` ships Python 3, so no setup step. Runs on `pull_request` too,
so a stale generated block is caught before master. Deploy stays
`hugo --minify` — the script never runs on the deploy path, so a Python error
can't break a release.

No commit hook: the failure it would catch happens about twice a year,
`--check` already catches it, and `.git/hooks` isn't versioned so it would
silently not exist on a fresh clone.

### 8. Tests — `scripts/theme-test.sh`

`playwright-cli` is installed globally, so no `package.json` and no npm deps in
a Hugo blog. The script starts `hugo server`, drives chromium, asserts via
`playwright-cli --raw eval`, tears down.

1. `--accent-fill` computes to a real colour — not empty, not white.
   *The exact Safari symptom.*
2. `.sidebar` background is neither transparent nor white.
3. Sampling `--accent-fill` across ~2s yields >5 distinct values.
   *Proves interpolation rather than a discrete jump — the Firefox symptom.*
4. Two loads seconds apart sit at the same cycle position. *Wall-clock sync.*
5. `anim.currentTime % CYCLE` tracks `Date.now() % CYCLE`. *Seek correctness.*
6. Dev palette: pin freezes the colour, resume unfreezes.
7. `data-theme=dark` changes `--accent-fill`.
   *`light-dark()` inside a registered, animated property — the one combination
   with no precedent on the live site.*

Chromium only.

### 9. Cleanup

Delete `static/theme-prototype.html` and `static/theme-prototype-2.html` before
merging. They're untracked, they live in `static/` so committing them would
publish them, and the colour lab plus the test script supersede their readouts.

## What we give up

The per-round reshuffle. Fixed order, repeating every 23m20s. Mitigated by the
loop being wall-clock-anchored: a visitor enters at a different point each
visit, so repetition is only perceptible within a single long sitting on one
page.

## Risks

**Drift is unverified.** The `visibilitychange` re-seek is deleted on the theory
that the document timeline can't diverge from wall-clock, and the WebKit test
run was dropped, so nothing checks it. Test 5 runs for seconds — it catches a
mis-seek, not slow divergence. Symptom would be two devices quietly disagreeing
on colour; fix is restoring three lines.

## Rollback

Single branch, no data migration, no persisted state. `git checkout master`.

---

# Tasks

Phase 1 gates everything — the generated block is an input to every later
phase. Phases 2 and 3 together are the smallest change that leaves a working
site; stop and smoke-test there before touching dev tooling.

## Phase 1 — Generator

- [x] Create `scripts/bake_palette.py`
- [x] Move the 20 hexes out of `colours.html` into it as the single source
- [x] sRGB -> linear -> OKLab -> OKLCH conversion
- [x] Apply the four lightness clamps (fill/text x light/dark)
- [x] Chroma gamut-map into sRGB by binary search on C
- [x] Emit 41 stops: `0%`, then `reached`/`held` per colour, at
      `(i*70+55)/1400` and `(i+1)*70/1400`
- [x] Verify `0%` and `100%` carry the same colour (seamless wrap)
- [x] Emit the static `--accent-fill` / `--accent-text` fallback pair
- [x] Write between `/* BEGIN generated */` / `/* END generated */` markers
- [x] `--check` mode: regenerate, diff against committed, non-zero on mismatch
- [x] Print a contrast table (informational only, never fails)
- [x] Run it; sanity-check a few values against the current site's colours
- [x] `scripts/test_bake_palette.py` — 15 tests, all green

## Phase 2 — CSS

- [x] Add the generated-block markers to `main.css`
- [x] Add `@property --accent-fill` and `--accent-text` (`<color>`, inherits)
- [x] Delete `@property --theme-color`
- [x] Delete the four `oklch(from ...)` lines and `--accent-fill-dark`
- [x] Run the generator to populate the block
- [x] `body { animation: theme-cycle 1400s ease infinite; }`
- [x] Add the static fallback pair to `body` (old-browser safety net)
- [x] Reduced motion: `animation-play-state: paused`, not `animation: none`
- [x] Rewrite the section 2 header comment (Firefox workaround is gone)
- [x] Confirm no `color-mix()` consumer was touched
- [x] `hugo` builds clean

## Phase 3 — Runtime JS

- [x] Rewrite `colours.html` to the `currentTime` seek
- [x] Add the no-`getAnimations` fallback (restart, then negative delay)
- [x] Delete `COLOURS`, `seededRandom`, `permutationForRound`,
      `correctedPermutationForRound`, `colourForEpoch`, `currentEpoch`,
      `findThemeCycleKeyframesRule`, `startTransition`, `applyInitialColour`,
      `scheduleRotation`, the `visibilitychange` handler, the reduced-motion
      branch, the `theme-base-*` class swap
- [x] Delete the `<noscript>` block from `head.html`
- [x] `hugo.json`: `themeColor` keeps only `layout-reverse`
- [x] **Smoke test**: colours cycle and ease; light/dark toggle works; no
      console errors; JS disabled still shows a colour; reduced motion shows a
      static colour that changes on reload
- [x] **Scheme re-resolution**: an early measurement suggested `light-dark()`
      in keyframes never re-resolves on a `color-scheme` change. Re-testing in
      phase 5 disproved that — Chromium does re-resolve, just not within the
      two animation frames the first probe waited. `colours.html` still
      restarts the animation on a `data-theme` change (MutationObserver) and on
      an OS scheme change: two lines of insurance for engines that may not, in
      a combination the plan flagged as having no precedent on the live site.

## Phase 4 — Dev tooling

- [x] `dev-palette.html`: pin = `pause()` + `currentTime = holdPosition(i)`
- [x] Resume = seek to wall-clock + `play()`
- [x] Delete the `realStart` / `realSeek` monkeypatch
- [x] Swatches sampled from a hidden paused probe, not the `COLOURS` global
- [x] `content/colour-lab.md` is `draft: true`, so the lab needs
      `hugo server -D`
- [x] `layouts/colour-lab.html` at root level, not `_default/`: Hugo 0.164
      resolves the `layout` front matter there, and `_default/single.html`
      wins otherwise. Guarded by `draft: true` on the content file rather than
      `hugo.IsServer` in the template — the page then doesn't exist at all in
      production instead of existing as a blank shell.
- [x] Render all 20 baked entries, sampled from the CSS
- [x] WCAG ratios in JS from resolved rgb, flagged not gated
- [x] Custom-colour input previewed through `oklch(from ...)`
- [x] Show light and dark side by side
- [x] Confirm the page is blank in a production build (`hugo` without server)

## Phase 5 — Tests and CI

- [x] `scripts/theme-test.sh` scaffold: start `hugo server`, wait for ready,
      trap-based teardown
- [x] Check 1 — `--accent-fill` is a real colour
- [x] Check 2 — `.sidebar` background not white/transparent
- [x] Check 3 — >5 distinct fills sampled over ~2s
- [x] Check 4 — two loads agree on cycle position
- [x] Check 5 — `currentTime` tracks `Date.now()`
- [x] Check 6 — dev-palette pin freezes, resume unfreezes
- [x] Check 7 — `data-theme=dark` changes `--accent-fill`
- [x] Run it green
- [x] **Prove it can fail** — ran four deliberate breaks:
      - seek pinned to 0 -> checks 4 and 5 red
      - MutationObserver removed -> all green (Chromium self-heals; see phase 3)
      - seek-only engine, no restart -> all green (same reason)
      - `color-scheme` rule deleted -> check 8 red **only after being fixed**
- [x] **Check 8 was worthless and is now real.** It compared two `--accent-fill`
      samples 120ms apart, but the value moves continuously, so it passed even
      with the colour-scheme wiring deleted. Now pauses the animation and pins
      `currentTime` to 45000 on both reads, so scheme is the only variable.
- [x] Confirm the suite is stable — 3 consecutive clean runs, 9/9
- [x] Add the `--check` step to `.github/workflows/main.yaml` before `Build`
- [x] Verify `--check` fails on a deliberately stale block, then revert

## Phase 6 — Cleanup

- [x] Delete `static/theme-prototype.html` and `static/theme-prototype-2.html`
- [x] Final `hugo --minify` build
- [x] Read the whole diff
- [x] Gitignore `.playwright-cli/` and `__pycache__/` — both leaked into the
      first `git add -A`
- [ ] Merge to master  *(left for you)*

## Phase 7 — Lab replaces the dev palette

- [x] Baked swatches are buttons: click holds the whole page on that colour
      (pause + `currentTime` on the hold segment)
- [x] Custom colours pin too, but by cancelling the animation and setting the
      properties inline — a running animation outranks inline style on the
      property it animates, even while paused
- [x] "Resume cycling" releases and re-seeks to wall-clock
- [x] Delete `layouts/partials/dev-palette.html` and its call in `sidebar.html`
- [x] Every component on the page: post index, lead, project cards, and the
      whole style guide pulled in with `site.GetPage "/styleguide"` rather than
      duplicated — headings, all six alert types, quotes, lists, code, tables
- [x] Style guide is `draft: true`, so the lab needs `hugo server -D`; the page
      says so in place when it isn't there, and `theme-test.sh` passes `-D`
- [x] Contrast chips for `--accent-text` moved onto the page surface — they were
      invisible whenever the text colour resolved close to the fill
- [x] Tests rewritten against the lab: 11 checks, all green

## Phase 8 — Timeline redesign

- [x] Style guide switched from `draft: true` to
      `build: { list: never, render: never }` — headless, so `site.GetPage`
      reaches it with a plain `hugo server` and it still has no public URL.
      The `-D` requirement is gone, including from `theme-test.sh`.
- [x] Palette grid replaced by a fixed bottom bar: 20 mini swatches showing the
      light fill, a native range input scrubbing the 1400s cycle, custom colour
      input and Resume
- [x] Scrub tracks the animation via rAF, and dragging it pins
- [x] Hover, focus or touch a swatch to reveal the full light + dark cells with
      contrast, positioned over that swatch
- [x] Content is the page again: post index, cards, and the whole style guide
      are read without scrolling past a colour grid
- [x] Tests updated to the new UI — 13 checks, all green

## Phase 9 — Polish

- [x] Popup dismissal: leaving the strip (mouse and pen only — touch fires
      `pointerleave` on lift, which would close it in the same gesture that
      opened it), tapping outside, Escape, or scrolling
- [x] Fixed the bar resizing when a swatch is clicked — the status text and
      button label both change length, so both now have a min-width floor
- [x] `hugo.IsServer` dropped: `content/colour-lab.md` is `draft: true`, so
      the page is absent from production rather than rendered blank.
      `theme-test.sh` runs the server with `-D`.
- [x] 14 checks, all green
- [x] Popup cells are buttons: clicking one adopts that colour *and* the scheme
      it was shown in. The pin is applied on the next tick, since changing
      `data-theme` restarts the animation and rebuilds the strip, both of which
      would otherwise drop it.
- [x] Popup sits flush against the bar and dismissal moved from the strip to
      the whole bar — with clickable cells, a gap would be a dead zone that
      closed the popup before the pointer could reach it
