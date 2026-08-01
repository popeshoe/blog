#!/usr/bin/env bash
# Browser checks for the baked theme cycle. Needs playwright-cli on PATH.
#   ./scripts/theme-test.sh
set -uo pipefail

PORT="${PORT:-1414}"
URL="http://localhost:$PORT"
CYCLE_MS=1400000
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0

cleanup() {
  playwright-cli -s=themetest close >/dev/null 2>&1
  [ -n "${HUGO_PID:-}" ] && kill "$HUGO_PID" 2>/dev/null
  wait "${HUGO_PID:-}" 2>/dev/null
}
trap cleanup EXIT

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  \033[32mpass\033[0m  %s\n' "$name"
    pass=$((pass + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s\n        expected %s, got %s\n' "$name" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

evaluate() {
  playwright-cli -s=themetest --raw eval "$1" 2>/dev/null | sed 's/^"//; s/"$//; s/\\"/"/g'
}

cd "$ROOT"
hugo server -D --port "$PORT" --disableFastRender >/dev/null 2>&1 &
HUGO_PID=$!

for _ in $(seq 1 40); do
  curl -sf -o /dev/null "$URL/" && break
  sleep 0.25
done
curl -sf -o /dev/null "$URL/" || { echo "hugo server did not start"; exit 1; }

playwright-cli -s=themetest open "$URL/" >/dev/null 2>&1

echo "theme engine"

check "1 --accent-fill is a real colour" true "$(evaluate "
  (() => {
    const v = getComputedStyle(document.body).getPropertyValue('--accent-fill').trim();
    return String(v !== '' && !/^(#fff(fff)?|rgb\(255,\s*255,\s*255\)|white)\$/i.test(v));
  })()")"

check "2 sidebar is painted" true "$(evaluate "
  (() => {
    const bg = getComputedStyle(document.querySelector('.sidebar')).backgroundColor;
    return String(bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent' && bg !== 'rgb(255, 255, 255)');
  })()")"

# Seeked into a transition segment on purpose: 15s of every 70s is a hold,
# where sampling would legitimately return one value and look like a failure.
check "3 interpolates rather than jumps" true "$(evaluate "
  (() => {
    const a = document.body.getAnimations().find(x => x.animationName === 'theme-cycle');
    const seen = new Set();
    for (let i = 0; i < 12; i++) {
      a.currentTime = 10000 + i * 2000;
      seen.add(getComputedStyle(document.body).getPropertyValue('--accent-fill').trim());
    }
    a.currentTime = Date.now() % $CYCLE_MS;
    return String(seen.size > 5);
  })()")"

check "4 two loads agree on position" true "$(
  a=$(evaluate "String(Math.round(document.body.getAnimations()[0].currentTime - (Date.now() % $CYCLE_MS)))")
  playwright-cli -s=themetest goto "$URL/" >/dev/null 2>&1
  b=$(evaluate "String(Math.round(document.body.getAnimations()[0].currentTime - (Date.now() % $CYCLE_MS)))")
  python3 -c "print(str(abs(${a:-99999} - ${b:-99999}) < 500).lower())"
)"

check "5 seek tracks wall-clock" true "$(evaluate "
  String(Math.abs(document.body.getAnimations()[0].currentTime - (Date.now() % $CYCLE_MS)) < 1000)")"

echo "colour lab"

playwright-cli -s=themetest goto "$URL/colour-lab/" >/dev/null 2>&1

check "6 timeline renders 20 swatches" 20 "$(evaluate "
  String(document.querySelectorAll('.lab-swatch').length)")"

check "7 swatches sampled from the palette" 20 "$(evaluate "
  String(new Set([...document.querySelectorAll('.lab-swatch')]
    .map(b => b.style.background)).size)")"

check "8 clicking a swatch holds the page" "paused,frozen,running,synced" "$(evaluate "
  (async () => {
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const anim = () => document.body.getAnimations().find(x => x.animationName === 'theme-cycle');
    const fill = () => getComputedStyle(document.body).getPropertyValue('--accent-fill').trim();
    const out = [];
    document.querySelectorAll('.lab-swatch')[14].click();
    await wait(60);
    out.push(anim().playState);
    const before = fill();
    await wait(250);
    out.push(fill() === before ? 'frozen' : 'moving');
    document.getElementById('lab-resume').click();
    await wait(60);
    out.push(anim().playState);
    out.push(Math.abs(anim().currentTime - (Date.now() % $CYCLE_MS)) < 500 ? 'synced' : 'adrift');
    return out.join(',');
  })()")"

check "9 hovering a swatch reveals both schemes" "2,true" "$(evaluate "
  (async () => {
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const d = document.getElementById('lab-detail');
    const at = async i => {
      const sw = document.querySelectorAll('.lab-swatch')[i];
      sw.dispatchEvent(new PointerEvent('pointerenter', { bubbles: true }));
      await wait(60);
      return { left: parseFloat(d.style.left), hex: d.querySelector('b').textContent };
    };
    const a = await at(2), b = await at(15);
    return d.querySelectorAll('.lab-cell').length + ',' +
      String(a.left !== b.left && a.hex !== b.hex);
  })()")"

check "10 the scrub bar follows the animation" true "$(evaluate "
  (async () => {
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const s = document.getElementById('lab-scrub');
    const before = Number(s.value);
    await wait(700);
    return String(Number(s.value) !== before && s.max === '$CYCLE_MS');
  })()")"

check "11 a custom colour overrides the cycle" changed "$(evaluate "
  (async () => {
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const fill = () => getComputedStyle(document.body).getPropertyValue('--accent-fill').trim();
    const before = fill();
    const input = document.getElementById('lab-input');
    input.value = '#00ff88';
    input.dispatchEvent(new Event('change'));
    await wait(80);
    const held = fill();
    document.getElementById('lab-resume').click();
    await wait(80);
    return held !== before && fill() !== held ? 'changed' : 'stuck';
  })()")"

# The style guide is render:never, so this also proves site.GetPage still
# reaches it without the server needing -D.
# Real pointer events from here, not dispatched PointerEvents: synthetic ones
# skip hit-testing and passed while the popup was genuinely unreachable.
centre() {
  evaluate "(() => {
    const el = $1;
    if (!el) return '';
    const r = el.getBoundingClientRect();
    return Math.round(r.x + r.width / 2) + ' ' + Math.round(r.y + r.height / 2);
  })()"
}

tap() {
  playwright-cli -s=themetest mousemove $1 >/dev/null 2>&1
  playwright-cli -s=themetest mousedown >/dev/null 2>&1
  playwright-cli -s=themetest mouseup >/dev/null 2>&1
  sleep 0.4
}

playwright-cli -s=themetest mousemove $(centre "document.querySelectorAll('.lab-swatch')[9]") >/dev/null 2>&1
sleep 0.3

SWATCH=$(centre "document.querySelectorAll('.lab-swatch')[9]")

away() { playwright-cli -s=themetest mousemove 400 200 >/dev/null 2>&1; sleep 0.3; }
hover() { away; playwright-cli -s=themetest mousemove $1 >/dev/null 2>&1; sleep 0.4; }
hidden() { evaluate "String(document.getElementById('lab-detail').hidden)"; }

hover "$SWATCH"
check "12 hovering a swatch opens the popup" false "$(hidden)"

# A click also focuses the button, and that focus event lands after the
# document handler has closed the popup - it reopened it every time until the
# focus listener was narrowed to :focus-visible.
tap "$SWATCH"
check "13 clicking a swatch dismisses but still pins" "true,true" "$(evaluate "
  String(document.getElementById('lab-detail').hidden) + ',' +
  /held on entry/.test(document.getElementById('lab-status').textContent)")"

hover "$SWATCH"
DARK_CELL=$(centre "[...document.querySelectorAll('#lab-detail .lab-cell')].find(c => c.dataset.scheme === 'dark')")
playwright-cli -s=themetest mousemove $DARK_CELL >/dev/null 2>&1
sleep 0.3

check "14 the popup survives moving onto it" false "$(hidden)"

tap "$DARK_CELL"

check "15 clicking a cell adopts colour and scheme, stays open" "false,dark" "$(evaluate "
  String(document.getElementById('lab-detail').hidden) + ',' +
  document.documentElement.dataset.theme")"

away
tap "400 300"
check "16 clicking anywhere else dismisses" true "$(hidden)"

hover "$SWATCH"
playwright-cli -s=themetest press Escape >/dev/null 2>&1
sleep 0.3
check "16b Escape dismisses" true "$(hidden)"

evaluate "delete document.documentElement.dataset.theme;
  setTimeout(function () { document.getElementById('lab-resume').click(); }, 80); 'reset'" >/dev/null
sleep 0.4

check "17 every component renders" "1,1,2,6,1,1" "$(evaluate "
  [document.querySelectorAll('.lab .post-title').length,
   document.querySelectorAll('.lab .lead').length,
   document.querySelectorAll('.lab .project-card').length,
   document.querySelectorAll('.lab blockquote.alert').length,
   document.querySelectorAll('.lab table').length,
   document.querySelectorAll('.lab figure').length].join(',')")"

echo "colour scheme"

# The animation must be paused first: --accent-fill moves continuously, so
# two samples taken moments apart differ whatever the scheme does, and the
# check passes even with the colour-scheme wiring deleted.
check "18 dark scheme changes the fill" different "$(evaluate "
  (async () => {
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const anim = () => document.body.getAnimations().find(x => x.animationName === 'theme-cycle');
    const fill = () => getComputedStyle(document.body).getPropertyValue('--accent-fill').trim();
    // Start from a known state: earlier checks leave a pin and a scheme set,
    // and setting data-theme to what it already is changes nothing.
    delete document.documentElement.dataset.theme;
    document.body.style.removeProperty('--accent-fill');
    document.body.style.removeProperty('--accent-text');
    document.body.style.animation = '';
    await wait(150);
    anim().pause();
    anim().currentTime = 45000;
    await wait(60);
    const light = fill();
    document.documentElement.dataset.theme = 'dark';
    await wait(150);
    const a = anim();
    a.pause();
    a.currentTime = 45000;
    await wait(60);
    const dark = fill();
    delete document.documentElement.dataset.theme;
    await wait(120);
    const restored = anim();
    restored.currentTime = Date.now() % $CYCLE_MS;
    restored.play();
    return dark !== light ? 'different' : 'same';
  })()")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
