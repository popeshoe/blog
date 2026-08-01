ip := `hostname -I | awk '{print $1}'`

_default:
    @just --list

# -D is not optional here: /colour-lab/ is a draft page and 404s without it.

# Dev server, reachable from other devices on the network
dev:
    hugo server -D --bind 0.0.0.0 --baseURL=http://{{ ip }}

# Also the cure for a server whose public/ directory was deleted underneath
# it: it keeps serving 404s and no amount of editing brings it back.

# Kill any running server, then start a fresh one
restart:
    -pkill -f "hugo server"
    @sleep 1
    @just dev

# Production build, exactly as CI does it
build:
    hugo --minify

# The palette lives in scripts/bake_palette.py and nothing may hand-edit the
# generated block in main.css. Run this after changing a colour.

# Regenerate the baked @keyframes block
bake:
    python3 scripts/bake_palette.py

# Print the contrast of every palette entry
contrast:
    python3 scripts/bake_palette.py --contrast

# Stale-palette check, generator units, then browser checks
test: check-palette
    python3 scripts/test_bake_palette.py
    ./scripts/theme-test.sh

# What CI runs: fails if the committed CSS block is out of date
check-palette:
    python3 scripts/bake_palette.py --check
