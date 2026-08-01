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
hugo server --port "$PORT" --disableFastRender >/dev/null 2>&1 &
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

echo "dev palette"

check "6 pin freezes, resume restores" "paused,frozen,running,synced" "$(evaluate "
  (async () => {
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const anim = () => document.body.getAnimations().find(x => x.animationName === 'theme-cycle');
    const fill = () => getComputedStyle(document.body).getPropertyValue('--accent-fill').trim();
    const out = [];
    document.querySelectorAll('.dev-palette-swatch')[7].click();
    await wait(60);
    out.push(anim().playState);
    const before = fill();
    await wait(250);
    out.push(fill() === before ? 'frozen' : 'moving');
    document.querySelector('[data-dev-palette-resume]').click();
    await wait(60);
    out.push(anim().playState);
    out.push(Math.abs(anim().currentTime - (Date.now() % $CYCLE_MS)) < 500 ? 'synced' : 'adrift');
    return out.join(',');
  })()")"

check "7 swatches sampled from the palette" 20 "$(evaluate "
  String(new Set([...document.querySelectorAll('.dev-palette-swatch')].map(b => b.style.background)).size)")"

echo "colour scheme"

# The animation must be paused first: --accent-fill moves continuously, so
# two samples taken moments apart differ whatever the scheme does, and the
# check passes even with the colour-scheme wiring deleted.
check "8 dark scheme changes the fill" different "$(evaluate "
  (async () => {
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const anim = () => document.body.getAnimations().find(x => x.animationName === 'theme-cycle');
    const fill = () => getComputedStyle(document.body).getPropertyValue('--accent-fill').trim();
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

echo "colour lab"

check "9 lab renders 20 baked entries" 40 "$(
  playwright-cli -s=themetest goto "$URL/colour-lab/" >/dev/null 2>&1
  evaluate "String(document.querySelectorAll('#lab-baked .lab-cell').length)")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
