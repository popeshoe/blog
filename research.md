# Blog styling research

Deep dive into how `porkcullis.com` (this repo) is styled — the Hugo setup, the theme, and
the custom animation system layered on top of it. Written after reading every layout,
partial, and stylesheet in `themes/hyde/` plus the git history behind the recent styling
commits.

## 1. Stack overview

- **Static site generator:** Hugo (built with `hugo --minify` in CI, version pinned to
  `0.164.0` in `.github/workflows/main.yaml`).
- **Theme:** `themes/hyde` — a heavily modified fork of the classic [Poole/Hyde](https://github.com/poole/hyde)
  Jekyll-turned-Hugo theme. It is *not* a git submodule (no `.gitmodules`); it's vendored
  directly into the repo and has its own commit history (`git log -- themes/hyde` shows the
  same commits as the main log — it's edited in place as part of this repo).
- **Config:** `hugo.json` (not TOML/YAML — this project uses the JSON config format). Key
  params: `themeColor: "theme-base-0f layout-reverse"` (initial/fallback body class — see
  §4), `mainSections: ["post"]`, `disqusShortname`, canonified URLs, `baseurl:
  https://porkcullis.com/`.
- **Content:** plain Markdown files under `content/`, front matter in **JSON**, not YAML/TOML
  (e.g. `content/post/guessr.md` starts with a `{ ... }` block). Hugo's goldmark markdown
  renderer has `parser.attribute.block: true` enabled in config, which is what lets Markdown
  blocks carry attributes (used for the alert-blockquote syntax, §6).
- **Deploy:** GitHub Actions builds with Hugo then `rsync`s `public/` to a host over SSH on
  every push to `master`.

There are three stylesheets, loaded in this order from `head.html`:
`poole.css` → `syntax.css` → `hyde.css`. All three are cache-busted with `?{{ now.Unix }}`
query strings baked in at *build* time (see §7).

## 2. File map

```
themes/hyde/
  layouts/
    404.html                  full page, standalone (no theme-color body class!)
    index.html                homepage: latest 3 posts + "More posts…" link
    _default/list.html        generic list page (used for /post index): bare title+date list
    _default/single.html      generic single page/post template
    partials/
      head.html                <head>, CSS links, GA snippet, noscript fallback, random tagline JS
      sidebar.html              site name, nav links, social links, copyright
      colours.html              the whole colour-cycling engine (JS, inlined into <head> via partial)
      disqus.html                comments embed (conditionally included)
    projects/list.html         special list template for the /projects section (project cards)
    _markup/render-blockquote.html   goldmark render-hook: turns blockquotes into GitHub-style
                                      alert callouts, or a <figure><blockquote> with citation/caption
  static/css/
    poole.css                 upstream Poole base styles (resets, typography, masthead, pagination)
    hyde.css                  Hyde-specific + this-repo's custom layer (sidebar, theme colour
                               system, project cards, alert callouts, link-underline animations)
    syntax.css                Pygments/Chroma syntax highlighting theme (classic Solarized-ish palette)
```

Every page-level layout (`index.html`, `_default/single.html`, `_default/list.html`,
`projects/list.html`) repeats the same skeleton by hand rather than using a `baseof.html`:
`partial "head.html"` → `<body class="{{ .Site.Params.themeColor }}">` → `partial
"colours.html"` → `partial "sidebar.html"` → page content. `404.html` is the one page that
skips the body class entirely, so it always renders with whatever the CSS custom property's
`initial-value` resolves to until JS colours it in (in practice this is invisible since
`colours.html` runs almost immediately, but it's a small inconsistency worth knowing about).

## 3. Layout system (poole.css + hyde.css structural rules)

Classic Hyde two-column layout:

- `.sidebar` — full width, colour-filled banner on mobile; becomes a **fixed** `18rem`-wide
  column pinned to the left (or right, see reverse layout) once the viewport passes `48em`.
- `.content` — the article/page column. Below `48em` it just flows under the sidebar. At
  `48em`+ it gets `max-width: 38rem` and `margin-left: 20rem` to clear the fixed sidebar; at
  `64em`+ the margins widen further (`22rem`/`4rem`) for breathing room on big screens.
- **Reverse layout:** adding `.layout-reverse` to `<body>` (which is *always* present — see
  §4) flips the sidebar to the right and mirrors `.content`'s margins. This class is baked
  into `hugo.json`'s `themeColor` param and is also hardcoded into the `body.className`
  string that `colours.html` writes on every colour transition (`colours.html:140`), so it's
  effectively a permanent, non-optional layout choice rather than a live toggle.
- **`.content.full`**: used only by `projects/list.html`. Removes the `38rem` max-width cap
  and turns the container into a CSS container (`container-type: inline-size`) so the
  project-card grid below can size itself with container query units (`cqw`).
- Two breakpoints govern everything: `47.999em` (mobile ceiling) / `48em` (desktop floor),
  and a second bump at `64em` for wide desktop margins. `html { font-size }` itself steps up
  twice too (16px → 16px @48em → 20px @58em is defined in `hyde.css`; note `poole.css`
  separately sets `20px` at `38em` — the two files' breakpoints don't perfectly line up, an
  artifact of merging upstream Poole rules with Hyde's own media queries).
- **Mobile sidebar-as-header quirk:** below `48em`, `.content::before` synthesizes a fading
  gradient strip (`background-image: linear-gradient(var(--theme-color) 15%, transparent)`)
  positioned with a large negative `margin-top` so it overlaps the bottom of the sidebar
  banner and fades page content in underneath it smoothly, rather than having a hard colour
  cutoff where the sidebar ends. It sits at `z-index: 5`, above ordinary content but below
  `.sidebar` (`z-index: 10`) so it can never paint over the header itself.
- **Mobile nav layout:** `.sidebar-nav` becomes a `grid-auto-flow: column` grid with 3 rows
  on mobile, splitting the flat `<ul>` of 6 links (About/Blog/Projects/Twitter/YouTube/GitHub)
  into two visual columns (site links, then social links) so it doesn't take up the whole
  screen height. `.sidebar-copyright` gets pulled out of flow and pinned to the header's
  bottom-right corner on mobile for the same space-saving reason.

## 4. The colour-cycling system (the standout feature)

This is the most distinctive and heavily-engineered part of the site. Every page's accent
colour (sidebar background, headings, link underlines, project-card headers) is driven by a
single CSS custom property, `--theme-color`, which continuously animates through a rotating
palette — forever, on every page load, synchronized across all visitors by wall-clock time.

### 4.1 Mechanism

- `hyde.css` registers `--theme-color` via `@property` as an animatable `<color>`
  (`inherits: true`, `initial-value: #fff`), and puts a single `@keyframes theme-cycle`
  animation on `<body>` (duration/delay driven by CSS vars, default 55s). Because the
  property is *inherited*, every rule in the stylesheet that reads `var(--theme-color)`
  (sidebar background, headings, link colour, project-card chrome, etc.) updates from this
  one animation — no per-element animations needed.
- `colours.html` (a `<script>` block inlined straight into `<head>`, not a separate .js file)
  owns the actual colour selection:
  - `COLOURS` is a hardcoded array of 20 hex colours (there's a commented-out earlier version
    using base16 codes — `"08".."0f"` mapped through a `THEME_HEX` dict — left in as a
    historical breadcrumb).
  - Colours advance in **70-second epochs** (`ROTATE_INTERVAL`), computed from
    `Date.now()`, so every open tab/visitor lands on the same colour at the same wall-clock
    time rather than drifting independently per page load.
  - Each "round" (a full pass through all 20 colours) is a Fisher–Yates shuffle seeded
    deterministically via `seededRandom(round * 1000 + i)` (a `Math.sin`-based PRNG), so the
    shuffle order is reproducible from the epoch alone — no state needs to be persisted
    anywhere.
  - `correctedPermutationForRound` swaps the shuffle's first two entries if the new round
    would otherwise start on the same colour the previous round just ended on, avoiding a
    visible "stall" where the colour doesn't appear to change across a round boundary.
  - Transitioning between colours is a 55s eased animation (`TRANSITION_DURATION`), restarted
    every 70s (`ROTATE_INTERVAL`) — so there's a ~15s pause at the target colour before the
    next transition begins.
  - On page load, `applyInitialColour()` computes how far into the *current* epoch we already
    are and seeks the animation to that exact point using a **negative** `animation-delay`,
    so a freshly loaded page joins the cycle already in progress instead of restarting from
    colour 1 — this is what keeps all visitors in sync.
  - A `visibilitychange` listener re-runs `applyInitialColour()` whenever a backgrounded tab
    becomes visible again (commit `40176b6`, "Fix colour drift while window isn't visible").
    Browsers throttle `setTimeout`/`setInterval` in background tabs, so the recurring
    `scheduleRotation()` timer can fire late or in a backlogged burst; without this fix a
    long-backgrounded tab would show a stale/incorrect colour, or hard-jump via the
    zero-delay reset path instead of properly re-seeking.

### 4.2 The Firefox workaround (notable piece of the codebase)

The single largest comment block in the whole theme (`colours.html:81-113`) documents a
Firefox-specific rendering bug: animating a registered custom property whose `@keyframes`
values are themselves `var()`-indirected (e.g. `--theme-color: var(--theme-color-from)`)
animates smoothly in Chrome but **snaps discretely** (holds, then jumps ~50% through the
`ease` curve) in Firefox 152, rather than easing. The workaround — and the reason
`colours.html` reaches into the CSSOM at all — is to skip the indirection and write **literal**
colour values directly into the `@keyframes theme-cycle` rule via
`findThemeCycleKeyframesRule()` before every transition restart, instead of the simpler
"set two custom properties on body and reference them via `var()`" approach that would
otherwise be preferred. The comment explicitly flags this as revertable if Firefox ever fixes
the underlying bug.

### 4.3 Dev-server hot-reload handling

Hugo's LiveReload swaps just the `<link rel="stylesheet">` tag on CSS-only edits, without a
full page reload and without re-running the inline `<script>`. Since the freshly-swapped
stylesheet's `@keyframes theme-cycle` rule reverts to its literal `#fff` placeholders, a
`MutationObserver` (gated behind `{{ if hugo.IsServer }}`, so this code never ships to
production) watches `<head>` for new `<link>` nodes, waits for the new stylesheet's `load`
event, finds its (fresh) `theme-cycle` rule, and re-runs `applyInitialColour()` against it —
otherwise `--theme-color` would go white and stay white after any CSS-only save during local
dev.

### 4.4 Static/no-JS fallback

`head.html` wraps a `<noscript>` block that disables the animation entirely
(`animation: none !important`) and pins `--theme-color` to a fixed blue (`#6a9fb5`) — one of
the 20 palette entries. Without this, a no-JS visitor would see the `@property` initial value
(`#fff`, i.e. an invisible white sidebar) forever, since only the JS ever writes literal
colours into the keyframes.

### 4.5 Naming residue / minor inconsistency

`body.className` is rewritten on every transition to
`"layout-reverse theme-base-" + toColour.slice(1) + (fadeIn ? " theme-fade-in" : "")`. The
`theme-base-XX` class is explicitly documented in `hyde.css` (§"Themes") as now purely
cosmetic/semantic labeling — it carries **no CSS** of its own anymore, kept only so the
current colour is identifiable in devtools, and deliberately kept *out* of the cascade so it
can't fight the animation on specificity. `theme-fade-in` is dead code: `colours.html` checks
for it (`body.classList.contains("theme-fade-in")`) and re-appends it if present, but nothing
in the current codebase (CSS or templates) ever adds that class in the first place — it's a
carried-over hook. `hugo.json`'s `themeColor: "theme-base-0f layout-reverse"` is only the
class the server-rendered HTML ships with before JS takes over on first paint; JS overwrites
it immediately with a computed colour.

## 5. Link and heading treatment

- **Body/post links (`.post a`)**: no underline; instead a custom animated "grow from the
  bottom" highlight using a second registered custom property, `--link-highlight`
  (`@property`, animatable `<color>`, `initial-value: transparent`). It's implemented as a
  1px-tall `background-image: linear-gradient(...)` positioned at the bottom of the text,
  which expands to `100% 100%` (filling the whole line) on hover, with both the colour and
  the size separately transitioned (`0.16s ease-out` / `0.16s ease-in-out`). `-webkit-box-decoration-break:
  clone` / `box-decoration-break: clone` ensures the highlight renders correctly on links that
  wrap across multiple lines.
- Default (non-hover) highlight colour is `color-mix(in oklab, var(--theme-color) 50%,
  white)` — a lightened tint of whatever the current cycling colour is. On hover it swaps to
  an even paler tint (`15%`) while growing to full height, i.e. hover states use a lighter
  colour but a bigger box, not a darker one.
- `.content a` (broader selector, catches non-`.post` links too, e.g. sidebar-adjacent
  content) gets a flat `color: var(--theme-color)`; `.content a:visited` explicitly resets to
  `inherit` to suppress the browser default purple.
- **Sidebar nav links** (`.sidebar-nav a`) use the *same* grow-from-bottom technique as post
  links but with different colour math, because they sit on a solid `--theme-color`
  background rather than a white page: the highlight has to stay visibly lighter than its own
  background (`color-mix(... 80%, white)`) and can't get anywhere near as pale as the
  post-link version, or white link text would vanish into it once the highlight fills the
  line.
- **Headings** (`.content h1`–`h6`) are flat-coloured with `var(--theme-color)`.
- **`hr`/post separators**: `.post + .post::before` draws a horizontal rule between
  consecutive posts (e.g. on the homepage) using `color-mix(in oklab, var(--theme-color) 50%,
  white)` — same "50% tint" formula as the default link highlight, for visual consistency.

## 6. GitHub-style alert callouts

`layouts/_markup/render-blockquote.html` is a Hugo **render hook** (goldmark, enabled by the
`parser.attribute.block: true` config option) that intercepts every blockquote at render time
and branches on `.Type`:

- If the blockquote carries `{alert} caution|important|note|tip|warning|wat` (a Markdown
  attribute block), it's rendered as `<blockquote class="alert alert-{type}">` with an emoji
  icon (`ⓘ`, `💡`, `⚠️`, `🛑`, `!`) and a bold heading line, styled in `hyde.css` with a
  colour-coded left border and heading colour per type (blue note, green tip, purple
  important, amber warning, red caution). There's also a bespoke, non-standard `wat` type
  (pink, 😐 icon) — not part of GitHub's actual alert spec, a custom addition.
- Otherwise it falls back to a `<figure><blockquote cite="...">` with optional
  `{caption="..."}` rendered as a `<figcaption>` — standard attributed-quote markup, used for
  things like the Megapriz "design doc" excerpt.

No content file in the repo currently uses the alert syntax (checked all of `content/post/*`)
— it's present and styled but unexercised by current posts.

## 7. Project cards (`/projects`)

`projects/list.html` is a bespoke list template (not `_default/list.html`) that iterates
`site.RegularPages` filtered to those with a non-nil `Params.project.url` — i.e. any blog
post can *also* register itself as a "project" by adding a `project: {name, url, description,
icon, repo}` block to its JSON front matter (see `content/post/guessr.md` and
`content/post/on-the-menu.md` for the two live examples). This means projects aren't a
separate content type; they're posts that opt into also appearing on `/projects`.

Styling notes (`hyde.css`):

- `.project-list` is a `grid` with `repeat(auto-fit, minmax(clamp(...), clamp(...)))` columns
  sized in **container query units** (`cqw`) rather than viewport units, because `.content`
  gets `container-type: inline-size` only when `.full` (§3) — the grid resizes relative to
  its own column width, not the whole viewport, which matters given the sidebar eats a
  variable amount of horizontal space depending on breakpoint.
- Each `.project-card` gets a small deterministic rotation via `:nth-child(3n+1/2/3n)`
  (-2deg/1.5deg/-1deg) so the grid reads as "hand-placed" rather than perfectly gridded, then
  straightens out and lifts (`scale(1.1)`, `translateY(-4px)`, bigger shadow) on hover.
  `transition` covers `border-color, transform, box-shadow, scale` together.
- Card header background is `var(--theme-color)` directly (full-strength, unlike the tinted
  links elsewhere); the art/icon block underneath uses a light tint
  (`color-mix(in oklab, var(--theme-color) 12%, white)`, brightening to `22%` on hover).
- Icon links (blog-post / GitHub-source) use inline SVGs plus a **native HTML popover**
  (`popover="manual"`, `showPopover()`/`hidePopover()`) driven by a small script at the bottom
  of the template — shown on hover/focus on desktop only (gated by a `matchMedia('(max-width:
  47.999em)')` check), manually positioned above the trigger via `getBoundingClientRect()`.
  On mobile, the popover mechanism is skipped entirely and a plain inline `.icon-label` text
  ("About"/"Source") is shown instead — a responsive fallback rather than trying to make
  hover-triggered popovers work on touch.

## 8. Cache-busting

`head.html` appends `?{{ now.Unix }}` to all three stylesheet URLs. `now.Unix` is evaluated
at **Hugo build time**, so every deploy gets a fresh cache-busting query string shared across
all three files for that build — not a per-file content hash, just "when was this built."
Commit `cfc129b` ("Add css cachebusters") introduced this after apparently running into stale
CSS being served post-deploy (rsync deploys overwrite files in place with no filename
change, so without this a CDN/browser cache could easily keep serving old CSS after a push).

## 9. Syntax highlighting

`syntax.css` is a fairly plain, mostly-unmodified Pygments/Chroma stylesheet (classic
`.hll`/`.c`/`.k`/`.o`/etc. token classes with hand-picked hex colours — blues for
keywords/comments, orange for numbers, red/orange for strings). It does not participate in
the `--theme-color` cycling system at all — code block colours are static regardless of the
current cycling accent colour. One small addition at the bottom targets `.css .o` /
`.css .o + .nt` / `.css .nt + .nt` specifically to grey out CSS selector punctuation.

## 10. Fonts and misc

- Body font stack: `"PT Sans", Helvetica, Arial, sans-serif` (loaded from Google Fonts in
  `head.html`, weights 400/400italic/700) — but note `poole.css`'s own `html` rule sets
  `"Helvetica Neue", Helvetica, Arial, sans-serif` with no PT Sans; `hyde.css`'s later `html`
  rule (higher in cascade order since it loads last) is what actually wins and applies PT
  Sans. This is upstream Hyde/Poole layering, not something introduced by this repo.
- Sidebar site title (`.sidebar-about h1`) uses a distinct display font, `'Abel', sans-serif`,
  also pulled from the same Google Fonts request.
- `head.html` also contains a small vanity feature unrelated to layout/colour: a
  `DOMContentLoaded` listener that picks a random tagline from a ~16-entry array of jokes and
  injects it into `.sidebar .lead` (the actual sidebar description text is commented out in
  `sidebar.html` in favour of this — the Hugo `site.Params.description` is defined in
  `hugo.json` but effectively unused for on-page display, only used for the `<meta>`/RSS
  `description` presumably... actually checking, no meta description tag exists in
  `head.html` at all currently, so `Site.Params.description` appears to be fully unused on
  the front end today).
- Google Analytics (`gtag.js`, property `G-RZ5CZGXNH6`) and a Disqus partial (conditionally
  rendered if `disqusShortname` is set — it is, `"porkcullis"`) round out the non-styling
  head/body additions.

## 11. Summary of "specificities" worth remembering

1. Layout is Poole/Hyde's classic fixed-sidebar two-column design, permanently in **reverse**
   mode (sidebar on the right) via a class baked into both the server-rendered fallback and
   every client-side colour transition.
2. The entire accent-colour system is one CSS `@property` + one `@keyframes` animation on
   `<body>`, driven entirely by inline JS in `colours.html` that deterministically computes a
   shared, wall-clock-synchronized colour cycle (20-colour palette, 70s epochs, 55s eased
   transitions) with no server or storage state — every visitor independently derives the
   same colour from `Date.now()`.
3. There's a deliberate, well-documented Firefox-only workaround (literal keyframe rewriting
   via CSSOM instead of `var()`-indirected keyframes) and a dev-only LiveReload compatibility
   shim, both isolated so they're easy to strip out later if no longer needed.
4. Link styling everywhere (post body, sidebar nav) uses the same animated
   "growing underline/highlight" pattern via a second registered custom property
   (`--link-highlight`), just tuned differently per context (light-on-white vs. white-on-color).
5. "Projects" aren't a separate content type — they're ordinary blog posts with an optional
   `project` front-matter block, surfaced onto `/projects` by a template that filters
   `site.RegularPages`.
6. Alert-style callout blockquotes (GitHub-flavoured, plus a custom `wat` type) are fully
   wired up via a goldmark render hook but currently unused by any actual post content.
7. Minor rough edges present in the code as-is: dead `theme-fade-in` class hook, unused
   `Site.Params.description`, inconsistent breakpoints between `poole.css` (`38em`) and
   `hyde.css` (`48em`/`58em`) for the `html` font-size bump, and `404.html` being the only
   template that omits the `themeColor` body class.
