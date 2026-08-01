#!/usr/bin/env python3
"""Bake the theme palette into a static @keyframes block in main.css.

The 20 hexes below are the single source of truth for the site's colours.
Edit them here, run this script, commit the result. CI runs --check.

    python3 scripts/bake_palette.py            write into main.css
    python3 scripts/bake_palette.py --check    fail if main.css is stale
    python3 scripts/bake_palette.py --contrast print the contrast table
"""

import math
import os
import sys

PALETTE = [
    "#ac4142", "#d28445", "#f4bf75", "#90a959", "#75b5aa",
    "#6a9fb5", "#aa759f", "#8f5536", "#586ba4", "#324376",
    "#f68e5f", "#f76c5e", "#14342b", "#60935d", "#ff579f",
    "#330c2f", "#37323e", "#6d6a75", "#2a2d34", "#09814a",
]

EPOCH_S = 70
TRANSITION_S = 55
CYCLE_S = len(PALETTE) * EPOCH_S

CLAMPS = {
    ("fill", "light"): (0.0, 0.62),
    ("fill", "dark"): (0.22, 0.32),
    ("text", "light"): (0.35, 0.55),
    ("text", "dark"): (0.62, 0.85),
}

BEGIN = "/* BEGIN generated - scripts/bake_palette.py */"
END = "/* END generated */"

CSS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "assets", "css", "main.css")


def _to_linear(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _from_linear(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def hex_to_oklch(hexv):
    h = hexv.lstrip("#")
    r, g, b = (_to_linear(int(h[i:i + 2], 16)) for i in (0, 2, 4))
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = (math.copysign(abs(v) ** (1 / 3), v) for v in (l, m, s))
    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    bb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return L, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def oklch_to_linear(L, C, H):
    a = C * math.cos(math.radians(H))
    b = C * math.sin(math.radians(H))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


def oklch_to_srgb255(L, C, H):
    return tuple(round(_from_linear(v) * 255) for v in oklch_to_linear(L, C, H))


def rgb_to_hex(r, g, b):
    return "#%02x%02x%02x" % (r, g, b)


def in_gamut(L, C, H, eps=1e-4):
    return all(-eps <= v <= 1 + eps for v in oklch_to_linear(L, C, H))


def map_chroma(L, C, H):
    if in_gamut(L, C, H):
        return C
    lo, hi = 0.0, C
    for _ in range(40):
        mid = (lo + hi) / 2
        if in_gamut(L, mid, H):
            lo = mid
        else:
            hi = mid
    return lo


def clamp_for(token, scheme, L):
    lo, hi = CLAMPS[(token, scheme)]
    return min(max(L, lo), hi)


def _oklch(L, C, H):
    return "oklch(%.4f %.4f %.2f)" % (L, C, H)


def _pair(hexv, token):
    L, C, H = hex_to_oklch(hexv)
    out = []
    for scheme in ("light", "dark"):
        Lc = clamp_for(token, scheme, L)
        out.append(_oklch(Lc, map_chroma(Lc, C, H), H))
    return "light-dark(%s, %s)" % tuple(out)


def tokens(hexv):
    return ("--accent-fill: %s;" % _pair(hexv, "fill"),
            "--accent-text: %s;" % _pair(hexv, "text"))


def stops():
    out = [(0.0, PALETTE[-1])]
    for i, hexv in enumerate(PALETTE):
        out.append(((i * EPOCH_S + TRANSITION_S) / CYCLE_S * 100, hexv))
        out.append(((i + 1) * EPOCH_S / CYCLE_S * 100, hexv))
    return out


def _pct(x):
    s = ("%.6f" % x).rstrip("0").rstrip(".")
    return (s or "0") + "%"


def generate():
    lines = ["@keyframes theme-cycle {"]
    for pct, hexv in stops():
        fill, text = tokens(hexv)
        lines.append("  %-11s { %s" % (_pct(pct), fill))
        lines.append("  %-11s   %s }" % ("", text))
    lines.append("}")
    lines.append("")
    fill, text = tokens(PALETTE[0])
    lines.append("body {")
    lines.append("  animation: theme-cycle %ds ease infinite;" % CYCLE_S)
    lines.append("  %s" % fill)
    lines.append("  %s" % text)
    lines.append("}")
    return "\n".join(lines)


def _split(path):
    with open(path) as f:
        content = f.read()
    if BEGIN not in content or END not in content:
        raise SystemExit("markers not found in %s" % path)
    head, rest = content.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    return head, tail


def write(path=CSS_PATH):
    head, tail = _split(path)
    with open(path, "w") as f:
        f.write("%s%s\n%s\n%s%s" % (head, BEGIN, generate(), END, tail))
    return 0


def check(path=CSS_PATH):
    with open(path) as f:
        content = f.read()
    if BEGIN not in content or END not in content:
        print("markers missing in %s" % path)
        return 1
    current = content.split(BEGIN, 1)[1].split(END, 1)[0].strip()
    if current == generate().strip():
        return 0
    print("%s is stale - run: python3 scripts/bake_palette.py" % path)
    return 1


def _relative_luminance(rgb_linear):
    r, g, b = (max(0.0, min(1.0, v)) for v in rgb_linear)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _ratio(a, b):
    la, lb = _relative_luminance(a), _relative_luminance(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def contrast_rows():
    white = (1.0, 1.0, 1.0)
    rows = []
    for hexv in PALETTE:
        L, C, H = hex_to_oklch(hexv)
        Lf = clamp_for("fill", "light", L)
        Lt = clamp_for("text", "light", L)
        fill = oklch_to_linear(Lf, map_chroma(Lf, C, H), H)
        text = oklch_to_linear(Lt, map_chroma(Lt, C, H), H)
        rows.append((hexv, _ratio(white, fill), _ratio(text, white)))
    return rows


def print_contrast():
    print("%-9s %-16s %-16s" % ("", "white on fill", "text on white"))
    below = 0
    for hexv, sidebar, link in contrast_rows():
        flag = "  <4.5" if sidebar < 4.5 else ""
        below += sidebar < 4.5
        print("%-9s %6.2f:1          %6.2f:1%s" % (hexv, sidebar, link, flag))
    print("\n%d/%d below 4.5:1 (known trade-off), %d below 3:1"
          % (below, len(PALETTE), sum(r[1] < 3.0 for r in contrast_rows())))


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--check":
        sys.exit(check())
    if arg == "--contrast":
        print_contrast()
        sys.exit(0)
    sys.exit(write())
