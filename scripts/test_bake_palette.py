import re
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_palette as b


def approx(a, x, tol=0.002):
    assert abs(a - x) <= tol, f"{a} != {x} (tol {tol})"


def test_oklch_roundtrip():
    for hexv in b.PALETTE:
        L, C, H = b.hex_to_oklch(hexv)
        r, g, bl = b.oklch_to_srgb255(L, C, H)
        assert b.rgb_to_hex(r, g, bl) == hexv.lower(), f"{hexv} -> {b.rgb_to_hex(r, g, bl)}"


def test_pure_colours_land_where_expected():
    L, C, H = b.hex_to_oklch("#ff0000")
    approx(L, 0.6280)
    approx(H, 29.23, 0.05)
    L, _, _ = b.hex_to_oklch("#ffffff")
    approx(L, 1.0)
    L, _, _ = b.hex_to_oklch("#000000")
    approx(L, 0.0)


def test_clamps():
    assert b.clamp_for("fill", "light", 0.90) == 0.62
    assert b.clamp_for("fill", "light", 0.40) == 0.40
    assert b.clamp_for("fill", "dark", 0.90) == 0.32
    assert b.clamp_for("fill", "dark", 0.10) == 0.22
    assert b.clamp_for("fill", "dark", 0.25) == 0.25
    assert b.clamp_for("text", "light", 0.10) == 0.35
    assert b.clamp_for("text", "light", 0.90) == 0.55
    assert b.clamp_for("text", "dark", 0.10) == 0.62
    assert b.clamp_for("text", "dark", 0.90) == 0.85


def test_palette_lightness_range():
    ls = [b.hex_to_oklch(h)[0] for h in b.PALETTE]
    assert min(ls) > 0.22, "no entry exercises the lower dark clamp"
    assert max(ls) > 0.62, "no entry exercises the light fill cap"


def test_gamut_mapping_lands_in_gamut():
    for hexv in b.PALETTE:
        L, C, H = b.hex_to_oklch(hexv)
        for token in ("fill", "text"):
            for scheme in ("light", "dark"):
                Lc = b.clamp_for(token, scheme, L)
                Cm = b.map_chroma(Lc, C, H)
                assert Cm <= C + 1e-9
                assert b.in_gamut(Lc, Cm, H), f"{hexv} {token} {scheme}"


def test_gamut_mapping_is_a_noop_when_already_inside():
    L, C, H = b.hex_to_oklch("#6a9fb5")
    approx(b.map_chroma(L, C, H), C, 1e-6)


def test_stop_percentages():
    stops = b.stops()
    assert len(stops) == 2 * len(b.PALETTE) + 1
    assert stops[0][0] == 0.0
    approx(stops[1][0], 55 / 1400 * 100, 1e-9)
    approx(stops[2][0], 70 / 1400 * 100, 1e-9)
    approx(stops[-1][0], 100.0, 1e-9)
    for i in range(1, len(stops)):
        assert stops[i][0] > stops[i - 1][0]


def test_wrap_is_seamless():
    stops = b.stops()
    assert stops[0][1] == stops[-1][1] == b.PALETTE[-1]


def test_each_colour_is_reached_then_held():
    stops = b.stops()
    for i, hexv in enumerate(b.PALETTE):
        assert stops[1 + 2 * i][1] == hexv
        assert stops[2 + 2 * i][1] == hexv


def test_generated_block_shape():
    css = b.generate()
    assert "@keyframes theme-cycle {" in css
    assert css.count("--accent-fill:") == 2 * len(b.PALETTE) + 2
    assert css.count("--accent-text:") == 2 * len(b.PALETTE) + 2
    assert "oklch(from" not in css
    assert re.search(r"^\s*0%\s", css, re.M)
    assert re.search(r"^\s*100%\s", css, re.M)
    for m in re.finditer(r"oklch\(([\d.]+) ([\d.]+) ([\d.]+)\)", css):
        L, C, H = (float(x) for x in m.groups())
        assert 0.0 <= L <= 1.0 and 0.0 <= C < 0.5 and 0.0 <= H < 360


def test_fallback_pair_is_first_colour():
    css = b.generate()
    tail = css.split("body {")[-1]
    fill, text = b.tokens(b.PALETTE[0])
    assert fill in tail and text in tail


def test_check_detects_staleness(tmp_path=None):
    import tempfile
    css = b.generate()
    with tempfile.NamedTemporaryFile("w", suffix=".css", delete=False) as f:
        f.write(f"a{{}}\n{b.BEGIN}\n{css}\n{b.END}\nb{{}}\n")
        path = f.name
    assert b.check(path) == 0
    with open(path) as f:
        content = f.read()
    with open(path, "w") as f:
        f.write(content.replace("theme-cycle", "theme-cycl3"))
    assert b.check(path) != 0
    os.unlink(path)


def test_write_replaces_only_between_markers():
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".css", delete=False) as f:
        f.write(f"KEEP_BEFORE\n{b.BEGIN}\nstale\n{b.END}\nKEEP_AFTER\n")
        path = f.name
    b.write(path)
    with open(path) as f:
        out = f.read()
    assert out.startswith("KEEP_BEFORE\n")
    assert out.endswith("KEEP_AFTER\n")
    assert "stale" not in out
    assert "@keyframes theme-cycle" in out
    assert b.check(path) == 0
    os.unlink(path)


def test_contrast_table_covers_every_entry():
    rows = b.contrast_rows()
    assert len(rows) == len(b.PALETTE)
    for hexv, sidebar, link in rows:
        assert 1.0 <= sidebar <= 21.0
        assert 1.0 <= link <= 21.0
    worst = min(r[1] for r in rows)
    assert worst >= 3.0, f"a palette entry dropped below 3:1 ({worst:.2f})"


if __name__ == "__main__":
    failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  pass  {name}")
            except AssertionError as e:
                failed += 1
                print(f"  FAIL  {name}: {e}")
    print(f"\n{failed} failed" if failed else "\nall passed")
    sys.exit(1 if failed else 0)
