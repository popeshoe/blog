# CSS refactor + dark mode — implementation plan

Goal: collapse `poole.css` / `hyde.css` / `syntax.css` into one well-ordered stylesheet,
flatten the vendored theme into the project, cut the accumulated dead code, reduce ~6 ad-hoc
breakpoints to 2, take a genuine pass at spacing and type, and add a dark mode that keeps
**every** current feature working — especially the wall-clock-synchronised colour cycle, the
growing-underline link effect, and the project cards.

Everything below is grounded in the current source. File:line references are to the tree as
of `fa96df0`.

---

## 0. Decisions taken

Settled up front; the plan below assumes all of these.

| # | Decision | Consequence |
|---|---|---|
| 1 | **Three-state theme control** — system / light / dark | Needs `localStorage`, a FOUC guard, and a sidebar control. "System" removes the attribute entirely (§6.4) |
| 2 | **Dark sidebar treatment deferred** — review live at the end | Built as a *single swappable token* with three candidate values ready to try (§6.3) |
| 3 | **Remove Disqus entirely** | Deletes `partials/disqus.html`, the conditional in `single.html`, and `disqusShortname` from config. Removes the dark-mode white-iframe problem outright (§2.3) |
| 4 | **Images unchanged in dark mode** | No filters. Screenshots and artwork render identically in both schemes |
| 5 | **Free to improve spacing and type** | Phase 3 is a real design pass — vertical rhythm, measure, card sizing — not just bug fixes (§4) |
| 6 | **Flatten `themes/hyde/` into the project root** | Removes the theme indirection; `hugo.json` drops `theme` (§3) |
| 7 | **Style the `/post` index properly** | Title left, muted date right; the dead `.pull-right` goes (§2.3) |
| 8 | **CI stays non-extended Hugo** | **No SCSS.** See the correction below — this does *not* cost you syntax highlighting |
| 9 | **Accept the modern browser floor** | `light-dark()` + `oklch(from …)`, no `@supports` fallback, no second palette |
| 10 | **Reduced motion → one fixed colour per page load** | Set `--theme-color` to the current epoch's colour and stop. No animation, no rotation timer. Colour changes only on navigation/refresh (§7.1) |
| 11 | **Keep PT Sans + Abel, fix loading only** | Add `preconnect` and `display=swap`. No visual change once fonts land |

> **Correction on decision 8.** Syntax highlighting does **not** require extended Hugo —
> `markup.highlight` and `hugo gen chromastyles` work fine on the standard build. Only
> SCSS/SASS compilation needs extended. So keeping CI non-extended costs you nothing here, and
> the §9 path to adding highlighting later stays fully open. CI is already non-extended
> (`extended: true` is commented out at `.github/workflows/main.yaml:22`), so **no workflow
> change is needed** — but note your local Hugo *is* extended (`v0.164.0+extended`), so avoid
> reaching for SCSS out of habit; it would build locally and break the deploy.

---

## 1. Constraints that shape the plan

| Constraint | Consequence |
|---|---|
| CI runs non-extended Hugo | Plain CSS only. `minify` and `fingerprint` both work on non-extended, so Hugo Pipes is still available (§8) |
| `colours.html` finds `@keyframes theme-cycle` by name via CSSOM (`colours.html:115-133`) | The keyframes rule must stay in a stylesheet reachable from `document.styleSheets` and keep that exact name. Renaming it, or burying it in an `@layer`, risks breaking the lookup |
| `colours.html:140` does `body.className = "layout-reverse theme-base-…"` — a **full clobber**, every 70s | Any class put on `<body>` by the theme control dies within one rotation. **Scheme state must live on `<html>`.** See §6.4 |
| Deploy is `rsync` over an existing tree, no cache headers under our control | Cache-busting must stay; content hashes are strictly better than the current build timestamp (§8) |
| `parser.attribute.block: true` (`hugo.json:23-31`) | The alert-blockquote render hook depends on this. Don't touch it |

---

## 2. Audit — what's actually wrong right now

Specific defects the refactor fixes. Each verified against source.

### 2.1 Real bugs

**A. Root font-size *shrinks* when crossing 48em.**
`poole.css:55-62` sets `html { font-size: 20px }` at `min-width: 38em`.
`hyde.css:73-77` sets `html { font-size: 16px }` at `min-width: 48em`.
Same specificity (0,0,1); `hyde.css` loads last, so above 48em it wins:

```
   <38em: 16px  →  38–48em: 20px  →  48–58em: 16px  ←  SHRINKS  →  58em+: 20px
```

Every `rem`-based dimension (the `18rem` sidebar, `20rem`/`22rem` content margins, `38rem`
content cap) drops 20% exactly at the breakpoint where the sidebar becomes a fixed column,
then jumps back at 58em.

**B. `.content` text size is pinned to an absolute 18px and ignores all of the above.**
`poole.css:59-61` — `html .content { font-size: 18px }` — specificity (0,0,2), beats every
`html` rule. Body copy never actually scales; only the chrome does.

**C. Every non-alert blockquote is indented by the UA `<figure>` margin.**
The render hook wraps plain blockquotes in `<figure>` (`render-blockquote.html:26-35`) — the
built `megapriz` page contains 7 — but **no stylesheet defines `figure`**. Browsers apply
`margin: 1em 40px`, so quotes get an unexplained ~40px indent on top of the blockquote's own
padding. `.blockquote-caption` (`render-blockquote.html:31`) is likewise unstyled.

**D. White sidebar text fails contrast on the pale palette colours.**
`.sidebar a { color: #fff }` (`hyde.css:134`) and `.sidebar-about h1 { color: #fff }` sit on
`background-color: var(--theme-color)`. Measured white-on-fill contrast:

| Colour | Ratio | |
|---|---|---|
| `#f4bf75` | **1.67** | unreadable |
| `#75b5aa`, `#f68e5f` | **2.35** | fails |
| `#90a959` | **2.62** | fails |
| `#f76c5e` | **2.89** | fails |
| `#6a9fb5` | **2.90** | fails |
| `#d28445`, `#ff579f` | **2.95** | fails |

8 of 20 palette entries drop the sidebar below 3:1. `.sidebar { color: color-mix(… 50%,
white) }` (`hyde.css:97`) is worse. Fixed in §6 by clamping fill lightness — no palette edits.

**E. Cache-busting defeats caching entirely.**
`head.html:24-26` appends `?{{ now.Unix }}` — a *build* timestamp shared by all three files.
Every deploy invalidates all CSS even when unchanged.

**F. No `prefers-reduced-motion` handling anywhere** — despite a permanent 55s colour
animation plus scale/rotate transforms on `.project-card:hover`.

**G. Latent config bug: `mainSections` is nested one level too deep.**
`hugo.json:17-21` puts it at `params.params.mainSections`, so `site.Params.mainSections`
(used at `index.html:10`) resolves to nothing. The homepage still shows 3 posts *by accident* —
Hugo auto-populates `mainSections` with the largest section when unset. If a second section
ever outgrows `post`, the homepage silently starts showing the wrong content. Fix while
flattening config (§3).

### 2.2 Dead code — safe to delete

Verified by cross-referencing every `class="…"` in `layouts/` + `content/` against both
stylesheets.

| Selector(s) | File:line | Why dead |
|---|---|---|
| `.masthead`, `.masthead-title`, `.masthead-title a/small` | `poole.css:279-297` | No template emits `masthead` |
| `.message` | `poole.css:250-255` | Never emitted |
| `.pagination`, `.pagination-item`, `a.pagination-item:hover` (+ its `30em` block) | `poole.css:364-406` | No template paginates |
| `.related`, `.related-posts*` | `poole.css:332-354` | No template emits `related` |
| `.related-posts li a:hover` | `hyde.css:312` | Same — and it's tangled into the `.content a` theme rule, so removing it simplifies that selector |
| `.sidebar-nav-item`, `a.sidebar-nav-item:hover/:focus`, `.sidebar-nav-item.active` | `hyde.css:155-164` | `sidebar.html:12-19` emits bare `<li><a>`; the class is never applied. Real styling is `.sidebar-nav a` (`hyde.css:172-187`) |
| **all of `syntax.css`** | — | Dead twice over: no content file has a code block, *and* Hugo's `markup.highlight.noClasses` defaults to `true`, emitting inline styles that ignore these classes. Keep `code`/`pre` base styles; §9 has the re-add path |
| `theme-fade-in` | `colours.html:137,140` | JS preserves it but nothing sets it and no CSS matches it |
| `partials/disqus.html` + `single.html:15-18` + `disqusShortname` | — | Decision 3 |
| `theme.toml`, `LICENSE.md`, `README.md`, `images/screenshot.png`, `images/tn.png`, `archetypes/default.md` | `themes/hyde/` | Theme-gallery metadata, meaningless once flattened. (The archetype is stale anyway — TOML front matter with `menu = "main"`, while all real content uses JSON.) Keep the MIT notice: fold Poole/Hyde attribution into the root `README.md` |

Keep (generic markdown element styles that content could use at any time, even if unused
today): `table`, `dl/dt/dd`, `abbr`, `hr`, `img`.

### 2.3 Emitted but unstyled — now in scope

| Class | Emitted at | Action |
|---|---|---|
| `.posts` | `list.html:8`, `index.html:8` | **Style it** (decision 7) — flex row, title left, muted date right |
| `.pull-right` | `list.html:11` | **Delete from template** — Bootstrap leftover, no CSS, dates don't float |
| `.post-list` | `list.html:11` | Fold into the `.posts` styling |
| `.blockquote-caption` | `render-blockquote.html:31` | **Style it** — muted, smaller, top-margin off the quote |
| `figure` | `render-blockquote.html:26` | **Style it** — zero the UA margin (bug C) |

### 2.4 Structural duplication

- `.content` and `.container` are always applied together (`class="content container"` in all
  four page templates), both set `max-width: 38rem` (`poole.css:264`, `hyde.css:263`) and
  fight over margins (`auto` vs `20rem`). **Merge into one class.**
- Font stacks disagree: `poole.css:51` Helvetica Neue, `hyde.css:71` PT Sans. Only the second
  matters. Collapse to one declaration.
- `hyde.css` interleaves concerns: the alert-colour block (`487-526`) is split in half by an
  unrelated `.post + .post::before` rule (`517-524`), and `@property --link-highlight` sits at
  line 529, ~490 lines below the other `@property`.
- Four page templates (`index.html`, `_default/single.html`, `_default/list.html`,
  `projects/list.html`) each hand-repeat the same `head → body → colours → sidebar` skeleton.
  **Introduce `_default/baseof.html`** while flattening (§3) — it removes four copies of the
  same five lines and makes the `<body>` class a single point of change, which matters for §6.4.

---

## 3. Flattening the theme

`themes/hyde/` is not a submodule (no `.gitmodules`) and is edited directly as part of this
repo. Move it to the root:

```
themes/hyde/layouts/   →  layouts/
themes/hyde/static/    →  static/          (merge; root already has favicon.ico)
                          new: assets/css/main.css   (§8)
```

Deleted in the move: `theme.toml`, `LICENSE.md`, `README.md`, `images/`, `archetypes/`,
`static/css/` (all three stylesheets superseded by `assets/css/main.css`).

Watch for: `themes/hyde/static/favicon.png` and `apple-touch-icon-144-precomposed.png` must
land in root `static/` alongside the existing `favicon.ico`, or the icons 404. `head.html:43`
references `/favicon.ico` with an absolute path — verify after the move.

**`hugo.json` cleanup at the same time:**

- Drop `"theme": "hyde"`.
- Drop `contentdir` / `layoutdir` / `publishdir` — all already the defaults.
- Drop `"indexes": {"tag": "tags"}` — a Hugo 0.11-era key, superseded by `taxonomies` and
  doing nothing today.
- Drop `disqusShortname` (decision 3).
- **Fix `mainSections`** — un-nest it from `params.params` to `params` (bug G).
- Keep `title`, `baseurl`, `canonifyurls`, `themeColor`, `description`, `markup.goldmark`.

Add `layouts/_default/baseof.html` and reduce the four page templates to their `{{ define
"main" }}` blocks (§2.4).

---

## 4. Target stylesheet structure

Single file: `assets/css/main.css`.

**Why one file, not `@import`:** `@import` costs an extra serial round trip. If you later want
authoring-time separation, `resources.Concat` (non-extended-safe) can build one file from
parts — but at ~700 lines post-cleanup, a single well-sectioned file is easier to navigate.

**On `@layer`:** tempting given the specificity fights this codebase has had — the
`theme-base-XX` comment at `hyde.css:302-309` documents exactly such a fight. But layers
change how the JS-set inline styles and keyframes interact in ways that need care, and a
single-author sheet doesn't need them. **Plain ordered sections with a contents index.**
Revisit only if specificity problems recur.

### Section order

```
 1. Contents index (comment)
 2. Config          @property declarations, :root tokens, color-scheme
 3. Theme engine    @keyframes theme-cycle + body animation   ← keep name & reachability
 4. Reset & base    box-sizing, html/body, headings, p, lists, hr, abbr,
                    code/pre, blockquote, figure, img, table, a, :focus-visible
 5. Layout          .sidebar, .content, reverse layout, the 2 breakpoints
 6. Components      sidebar nav, theme control, post/list index, project cards,
                    alerts, popover
 7. Motion & prefs  prefers-reduced-motion, print
```

**Rule: no colour literals below section 2.** Every colour in sections 4–6 is `var(--token)`.
That one discipline is what makes dark mode a ~40-line addition instead of a rewrite.

### Type and spacing pass (decision 5)

Since Phase 3 already reflows the layout, do the type work in the same pass rather than
disturbing it twice:

- **Root:** `html { font-size: 100% }` — respect the browser setting instead of the current
  hard `16px`/`20px` overrides, which override user preference (an accessibility fix as well
  as a bug fix).
- **Scale:** one step, at the desktop breakpoint —
  `body { font-size: 1rem }` → `1.125rem` at `48em`.
- **Measure:** the current `38rem` cap sits around 75–80 characters at 18px. With the root
  size stabilised, re-derive it to land at **62–70 characters** — likely a touch narrower.
- **Rhythm:** `line-height: 1.6` on body (up from `1.5`); set heading margins from a single
  spacing scale rather than the current mix of `.5rem`/`1rem`/`1.5rem` ad-hoc values.
- **Spacing scale:** define `--space-1` … `--space-6` in section 2 and use them for the
  component padding currently written as one-off `.35rem`/`.6rem`/`.75rem`/`1.25rem` values
  across the project cards and alerts.
- **Card sizing:** re-check the `clamp(160px, 22cqw, 200px)` / `clamp(220px, 28cqw, 260px)`
  grid bounds (`hyde.css:323`) against the new content width.

---

## 5. Breakpoint consolidation

Current set: `30em`, `38em`, `47.999em`, `48em`, `58em`, `64em` — six, two of which
(`38em`/`58em`) exist only to drive the buggy font-size ladder, and one of which is the
fragile `.999` inversion.

**Target: two, mobile-first, `min-width` only.**

```css
/* 48em / 768px  — sidebar becomes a fixed column ("desktop") */
/* 64em / 1024px — wider gutters ("wide")                     */
```

Dropping `max-width` queries removes the `47.999em` fragility entirely. The five current
mobile-only blocks become *base* styles, each undone inside `@media (min-width: 48em)`:

| Currently `max-width: 47.999em` | Reset needed at ≥48em |
|---|---|
| `.content::before` fade strip (`hyde.css:114-131`) | `display: none` |
| `.sidebar-nav` 3-row column grid (`hyde.css:202-207`) | `display: block` |
| `.sidebar-nav a` inline-block + `1.15rem` tap targets (`hyde.css:193-197`) | `display: inline`, `font-size: inherit`, `margin: 0` |
| `.sidebar-copyright` absolute corner pin (`hyde.css:216-222`) | `position: static`, restore margin |
| `.project-card-header` column stacking + `.icon-label` (`hyde.css:455-476`) | `flex-direction: row`, `.icon-label { display: none }` |

The `30em` blockquote-padding query (`poole.css:199-204`) folds into the 48em tier. The
`38em`/`58em` font queries are deleted, replaced by the §4 type scale — fixing bugs A and B.

**Expect visible reflow here.** The sidebar and margins will settle at consistent sizes rather
than the current 20%-jump behaviour. `18rem` / `20rem` / `22rem` / `38rem` all need re-tuning
once against the new stable root size.

---

## 6. Token layer and dark mode

### 6.1 Tokens

```css
:root {
  color-scheme: light dark;

  /* --- surfaces & text ------------------------------------------- */
  --surface:       light-dark(#fff,     #14161a);
  --surface-sunk:  light-dark(#f9f9f9,  #1e2126);  /* code, pre, table stripe */
  --text:          light-dark(#515151,  #c8ccd2);
  --text-strong:   light-dark(#313131,  #e8eaee);  /* headings, <strong> */
  --text-muted:    light-dark(#9a9a9a,  #8b9198);  /* dates, captions */
  --border:        light-dark(#e5e5e5,  #2c3038);
  --shadow:        light-dark(rgba(0,0,0,.15), rgba(0,0,0,.55));

  /* --- accent, derived from the animating --theme-color ----------- */
  --accent-fill:   light-dark(
                     oklch(from var(--theme-color) min(l, 0.62) c h),
                     var(--accent-fill-dark));            /* ← §6.3 */
  --accent-text:   light-dark(
                     oklch(from var(--theme-color) clamp(0.35, l, 0.55) c h),
                     oklch(from var(--theme-color) clamp(0.62, l, 0.85) c h));
  --on-accent:     #fff;
}
```

**The two rules that make this work:**

1. `--theme-color` stays exactly as it is — a registered `@property`, animated by literal
   keyframe values written by `colours.html`. **No JS changes are required for dark mode.** The
   wall-clock sync, epoch shuffle, Firefox CSSOM workaround and LiveReload shim are untouched.
   (JS *does* change for the theme control and reduced motion — §6.4, §7.1 — but nothing in
   the colour engine itself.)
2. Everything else reads `--accent-fill` / `--accent-text`, never `--theme-color` directly.
   The `oklch(from …)` clamp preserves each palette colour's hue and chroma — its identity —
   while forcing lightness into a band that's legible against the current surface.

That clamp fixes bug D for free: `min(l, 0.62)` caps `#f4bf75` and friends so white text
always clears 4.5:1, with no palette edits and no changes to `colours.html`.

### 6.2 Mix bases: page-relative vs accent-relative

The existing `color-mix(…, white)` calls are **not** all the same kind. Conflating them is the
easiest way to break dark mode:

| Rule | Current | Kind | New base |
|---|---|---|---|
| `.post a` highlight (`hyde.css:538`) | `mix(theme 50%, white)` | page-relative | `var(--surface)` |
| `.post a:hover` (`hyde.css:549`) | `mix(theme 15%, white)` | page-relative | `var(--surface)` |
| `.post + .post::before` (`hyde.css:522`) | `mix(theme 50%, white)` | page-relative | `var(--surface)` |
| `.project-card-art` (`hyde.css:432,440`) | `mix(theme 12/22%, white)` | page-relative | `var(--surface)` |
| `.sidebar` text (`hyde.css:97`) | `mix(theme 50%, white)` | **accent-relative** | keep `white` |
| `.sidebar-nav a` highlight (`hyde.css:174,185`) | `mix(theme 80%, white)` | **accent-relative** | keep `white` |

The sidebar sits *on* an accent-filled block, so its internal contrast is independent of the
page background — those two are already dark-mode-correct. Everything else tints toward the
page and must follow `--surface`.

### 6.3 The deferred sidebar decision (decision 2)

The dark sidebar treatment is isolated behind **one token**, `--accent-fill-dark`, so you can
try all three live at the end of Phase 5 by changing a single line:

```css
/* A — full accent fill (current character, boldest) */
--accent-fill-dark: oklch(from var(--theme-color) clamp(0.40, l, 0.60) c h);

/* B — dimmed: same hue, reads as a tinted dark panel */
--accent-fill-dark: oklch(from var(--theme-color) clamp(0.22, l, 0.32) c h);

/* C — flat neutral panel; accent moves to the type */
--accent-fill-dark: #1e2126;
```

Option C additionally needs `.sidebar-about h1` and `.sidebar a` to switch from
`var(--on-accent)` to `var(--accent-text)`. To keep C a one-line change too, write those two
rules against a second token — `--on-accent-fill`, defaulting to `--on-accent` — so swapping
to C means changing two token values, not hunting through component rules.

**Build for A initially** (it preserves current character), then review B and C side by side
before Phase 6.

**A later option, if you'd rather curate than clamp.** The lightness clamps above reshape all
twenty palette colours to fit whichever scheme is active. The alternative is to *segment the
palette* — keep every colour at its exact designed value, and simply don't select the bright
ones in dark mode or the near-black ones in light. That's arguably the better end state, and
it would let both clamps become plain passthroughs. It's out of scope here because it's the
first change that would **re-couple dark mode to the colour engine**: `COLOURS` becomes two
arrays and `colourForEpoch` has to know the current scheme, which touches the epoch-sync
logic this plan otherwise leaves alone. Worth revisiting once dark mode is landed and you've
seen the palette in both schemes.

### 6.4 Component changes

| Component | Change |
|---|---|
| `.sidebar` | `background: var(--accent-fill)`; bug D resolved by the clamp |
| `.content::before` fade strip | `linear-gradient(var(--accent-fill) 15%, transparent)` |
| Headings `.content h1-h6` | `var(--accent-text)` |
| `.post a` / `.content a` | colour `var(--accent-text)`; highlight mixes toward `var(--surface)` |
| `.project-card` | `border-color: var(--border)`; `box-shadow: 6px 6px 4px var(--shadow)`. Shadows read weakly on dark — lean on the border rather than fighting it |
| `.project-card-header` | `background: var(--accent-fill)`, text `var(--on-accent)` |
| `.project-card-art` | `mix(var(--accent-fill) 12%, var(--surface))` |
| `.icon-popover` | invert per scheme: `background: light-dark(#222, #e8eaee)`, `color: light-dark(#fff, #14161a)` |
| `code` / `pre` | `background: var(--surface-sunk)`; inline code `light-dark(#bf616a, #e88b93)` |
| `blockquote` | `border-left-color: var(--border)`, `color: var(--text-muted)` |
| `figure` | `margin: 0` — bug C |
| `.blockquote-caption` | `var(--text-muted)`, `.9em`, small top margin |
| `.posts` index | flex row, title `var(--accent-text)`, date `var(--text-muted)`, row separators `var(--border)` |
| `table` / `td` / `th` | borders `var(--border)`, odd-row stripe `var(--surface-sunk)` |
| `hr` | `border-top: 1px solid var(--border)`; drop the fake `border-bottom: 1px solid #fff` bevel (`poole.css:136`) — a light-only trick |
| `img` | **unchanged** (decision 4) |

### 6.5 Alert callouts need a second palette

The six alert colours (`hyde.css:504-526`) are GitHub's **light** palette and are too dark on
a dark surface:

| Type | Light (current) | Dark |
|---|---|---|
| note | `#0969da` | `#4493f8` |
| tip | `#1a7f37` | `#3fb950` |
| important | `#8250df` | `#ab7df8` |
| warning | `#9a6700` | `#d29922` |
| caution | `#cf222e` | `#f85149` |
| wat | `#ff1f8f` | `#ff6fb5` |

Express as six `light-dark()` tokens, then have both `border-color` and `.alert-heading` read
them. This collapses 12 rules into 6 and repairs the block that `.post + .post::before`
currently splits in half.

No content file uses alert syntax today, so this is unverifiable by eye. **Write a throwaway
post exercising all six types during Phase 5, review it in both schemes, then leave it as a
draft** (`draft: true`) as a permanent style reference.

### 6.6 The theme control — and the `body.className` trap

**The single thing most likely to break silently.** `colours.html:140` does:

```js
body.className = "layout-reverse theme-base-" + toColour.slice(1) + …
```

A full assignment, re-run every 70 seconds. Any class put on `<body>` survives less than one
rotation.

Two required changes:

1. **Scheme state goes on `<html>`** — `document.documentElement.dataset.theme`. Out of reach
   of the clobber entirely.
2. **Fix the clobber itself** while you're there — replace the string assignment with targeted
   `classList` calls so the element stops being hostile to future classes:

   ```js
   body.classList.forEach(c => { if (c.startsWith("theme-base-")) body.classList.remove(c); });
   body.classList.add("theme-base-" + toColour.slice(1));
   ```

   `layout-reverse` then comes from the template as it already does, and `theme-fade-in`
   handling is deleted with the rest of the dead code.

**Three-state control (decision 1):**

```css
:root[data-theme="light"] { color-scheme: only light; }
:root[data-theme="dark"]  { color-scheme: only dark;  }
/* no attribute = system, via `color-scheme: light dark` on :root */
```

`light-dark()` resolves against the *used* `color-scheme`, so flipping that one property
switches every token at once — no `!important`, no duplicated variable blocks.

Button cycles `system → light → dark → system`, writing `localStorage.theme` and
**removing** the attribute for system. Label it with the current state so "system" is
discoverable rather than an invisible third press.

**FOUC guard** — must run before first paint, or dark-mode users get a white flash on every
navigation:

```html
<script>
  try {
    var t = localStorage.getItem("theme");
    if (t) document.documentElement.dataset.theme = t;
  } catch (e) {}
</script>
```

Inline, in `<head>`, **before** the stylesheet `<link>`. Keep it inline — an external file
would race.

**Placement:** in `.sidebar-sticky` below the nav. On mobile the sidebar is the header and
`.sidebar-copyright` is already absolutely positioned into the bottom-right corner
(`hyde.css:216-222`) — check the control doesn't collide with it; the bottom-left corner is
free.

**`<noscript>`:** `head.html:33-40` currently pins `--theme-color: #6a9fb5` and kills the
animation. Keep it — `#6a9fb5` flows through the same `--accent-*` clamps and lands legible in
both schemes automatically, so it needs no scheme awareness.

---

## 7. Motion & accessibility

### 7.1 Reduced motion (decision 10)

Pick the current epoch's colour, apply it, and do nothing else — no animation, no rotation
timer, no `visibilitychange` re-seek. The colour changes only when a page is loaded, so
navigating or refreshing may show the next colour.

In `colours.html`, before `applyInitialColour()` / `scheduleRotation()`:

```js
if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
  document.body.style.setProperty("--theme-color", colourForEpoch(currentEpoch()));
  // skip startTransition / scheduleRotation / visibilitychange entirely
} else {
  applyInitialColour();
  scheduleRotation();
}
```

Setting `--theme-color` as an inline style on `<body>` beats the animation cleanly. Pair with:

```css
@media (prefers-reduced-motion: reduce) {
  body { animation: none; }
  .project-card, .project-card:hover { transition: none; transform: none; scale: 1; }
  .post a, .sidebar-nav a { transition: none; }
}
```

Note the `.project-card` rule must also neutralise the `:nth-child` rotations (`hyde.css:341-351`)
if you consider the static tilt itself motion — it isn't animated, so **leave the tilt in**;
only the hover transition goes.

### 7.2 Contrast verification

After the clamp lands, re-run the check across all 20 palette entries in both schemes.
Targets: white-on-`--accent-fill` ≥ 4.5:1; `--accent-text`-on-`--surface` ≥ 4.5:1 for body
links, ≥ 3:1 for large headings. Also check the static tokens (`--text`, `--text-muted`,
`--border`) against both surfaces. **Tune the clamp bounds in §6.1, not the palette.**

### 7.3 Focus states

`poole.css:77-80` ties `:focus` to `:hover` (underline only), so with the growing-underline
effect the focus ring is indistinguishable from hover. Add
`:focus-visible { outline: 2px solid var(--accent-text); outline-offset: 2px }`.

---

## 8. Build pipeline

`assets/css/main.css` + Hugo Pipes:

```go-html-template
{{ $css := resources.Get "css/main.css" | minify | fingerprint }}
<link rel="stylesheet" href="{{ $css.RelPermalink }}" integrity="{{ $css.Data.Integrity }}">
```

- `minify` and `fingerprint` both work on **non-extended** Hugo — CI is safe.
- Replaces `?{{ now.Unix }}` (`head.html:24-26`), fixing bug E: unchanged CSS keeps its URL
  across deploys and actually stays cached.
- The LiveReload `MutationObserver` shim (`colours.html:198-223`) still works — it matches on
  `<link rel="stylesheet">` regardless of URL shape.

**Verify in Phase 7:** run `hugo server`, edit `main.css`, confirm the hot-swap still
repopulates the keyframes. That shim is the easiest thing to break when moving files and it
**fails silently** — the symptom is the whole site going white after a CSS save.

**Fonts (decision 11)** — `head.html:27`:

```html
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=PT+Sans:400,400italic,700|Abel&display=swap">
```

---

## 9. Syntax highlighting

`syntax.css` is deleted (§2.2 — dead twice over). It does **not** need extended Hugo to come
back. When you want it:

1. `hugo.json` → `markup.highlight.noClasses: false`
2. `hugo gen chromastyles --style=github > light.css` and `--style=github-dark > dark.css`
3. Either scope each to a scheme, or convert the ~40 token colours to `light-dark()` pairs and
   fold them into section 6 of `main.css`.

Leave a one-line comment in `main.css` pointing here so the capability isn't silently lost.

---

## 10. Phased execution

Each phase is independently reviewable and committable. Phases 1–2 and 4 are
**behaviour-preserving** — rendered output should be pixel-identical.

| Phase | Work | Verification |
|---|---|---|
| **0. Baseline** | Branch. `hugo --minify`, keep `public/` aside. Reference screenshots: `/`, `/about`, `/post`, `/projects`, `/post/megapriz` (figures), `/post/nice-youtubes` (embeds), 404 — at 375 / 800 / 1400px | — |
| **1. Flatten + merge** | Move `themes/hyde/*` to root (§3), add `baseof.html`, clean `hugo.json` incl. the `mainSections` fix. Concatenate the two stylesheets into `assets/css/main.css` in §4 order — **no rule edits**. Single `<link>`, keep `now.Unix` for now | Diff against baseline — must be identical. Check favicons and `/` still resolve |
| **2. Delete dead code** | Everything in §2.2, incl. `syntax.css` and Disqus. Deduplicate `.content`/`.container` and the font stack (§2.4) | Screenshots identical. Grep templates for every removed class to confirm zero emissions |
| **3. Bugs, breakpoints, type** | Bugs A/B/C. Two breakpoints, invert the `47.999em` blocks (§5). Full type and spacing pass (§4). Style `.posts` + `.blockquote-caption`; drop `.pull-right` | **Screenshots will change — the review-carefully phase.** Especially 768–928px, where the shim bug lived. Re-tune `18rem`/`20rem`/`22rem`/`38rem` and re-derive the measure |
| **4. Token layer** | §6.1 `:root` block. Replace every colour literal in sections 4–6 with a token. **Light values only** — no `light-dark()` yet | Screenshots identical to end of Phase 3. This is the proof tokenisation is complete |
| **5. Dark mode** | `color-scheme` + wrap tokens in `light-dark()`. §6.4 components, §6.5 alerts. Build with sidebar option A. Write the all-alerts draft post | Toggle OS appearance; walk all 7 pages in both schemes. Run the §7.2 contrast check across all 20 colours |
| **5b. Colour review** | **Your call** — compare sidebar options A / B / C (§6.3) and the surface/text token values side by side | One-line token swaps; judge live |
| **6. Control + JS fixes** | `data-theme` on `<html>`, FOUC guard, three-state sidebar control. Fix the `body.className` clobber (§6.6). Reduced-motion path (§7.1) | Toggle, then **wait past a 70s rotation** and confirm the scheme survives — the specific regression §6.6 exists to prevent. Test with JS off, and with reduced-motion on |
| **7. Pipeline + polish** | Pipes fingerprinting, font `preconnect`/`display=swap`, `:focus-visible` | `hugo server` CSS-edit hot-swap test (§8). Push to a branch, confirm CI's **non-extended** Hugo builds |

**Rollback:** Phase 1 is the riskiest structural step (path churn) but is purely mechanical and
easy to verify. Phase 3 is the riskiest visually — commit it separately from Phase 4 so a bad
breakpoint or type decision can be undone without losing the token work.

---

## 11. What explicitly does not change

Stated so the refactor can't quietly regress the site's character:

- The 20-colour palette and its exact values (`colours.html:13-34`)
- 70s epoch / 55s transition timing, and wall-clock sync across visitors
- The seeded-shuffle round logic and the same-colour-across-rounds correction
- The Firefox literal-keyframes CSSOM workaround and its comment (`colours.html:81-133`) —
  still needed, still the reason the JS is shaped this way
- The LiveReload stylesheet-swap shim
- The `visibilitychange` drift correction (`40176b6`) — except under reduced motion, where
  there's no animation to correct
- Reverse layout (sidebar on the right)
- The growing-underline link effect and its two-property transition
- Hand-rotated project cards and the native-popover tooltips
- The random sidebar tagline (`head.html:49-70`)
- Google Analytics (`head.html:4-12`) — untouched; only Disqus is removed

---

## 12. Estimated shape of the result

| | Before | After (est.) |
|---|---|---|
| CSS files | 3 | 1 |
| CSS lines | ~1030 | ~700 (incl. ~60 dark-mode lines) |
| Breakpoints | 6 | 2 |
| Colour literals outside tokens | ~45 | 0 |
| Dead rulesets | ~30 | 0 |
| CSS requests | 3, cache-busted every deploy | 1, content-hashed |
| Directory depth | `themes/hyde/layouts/…` | `layouts/…` |
| Page templates | 4 hand-repeated skeletons | `baseof.html` + 4 `main` blocks |
| Third-party embeds | GA + Disqus + Google Fonts | GA + Google Fonts |
