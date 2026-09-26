#!/usr/bin/env python3
"""Render RX-1 alignment + inspector-state evidence images (not live F5 Play)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from PIL import Image, ImageDraw, ImageFont  # noqa: E402

SPEC = ROOT / "data" / "map" / "rx1_rhine_crossings.json"
OUT = Path("/opt/cursor/artifacts")


def _font(size: int) -> ImageFont.ImageFont:
    for p in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ):
        if Path(p).is_file():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def _bbox(pts):
    xs = [float(p[0]) for p in pts]
    ys = [float(p[1]) for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def render_midzoom(spec: dict, out: Path) -> None:
    course = (spec.get("course") or {}).get("points") or []
    cities = ((spec.get("alignment") or {}).get("city_distances_canvas") or {})
    edges = spec.get("edges") or []
    if len(course) < 2:
        raise SystemExit("no course points")
    pad = 8.0
    minx, miny, maxx, maxy = _bbox(course)
    for c in cities.values():
        xy = c.get("canvas") or []
        if len(xy) >= 2:
            minx = min(minx, float(xy[0]))
            maxx = max(maxx, float(xy[0]))
            miny = min(miny, float(xy[1]))
            maxy = max(maxy, float(xy[1]))
    minx -= pad
    miny -= pad
    maxx += pad
    maxy += pad
    w, h = 1280, 720
    sx = (w - 80) / max(0.001, maxx - minx)
    sy = (h - 80) / max(0.001, maxy - miny)
    s = min(sx, sy)

    def xy(p):
        return (40 + (float(p[0]) - minx) * s, 40 + (float(p[1]) - miny) * s)

    img = Image.new("RGB", (w, h), (18, 24, 32))
    dr = ImageDraw.Draw(img)
    font = _font(16)
    small = _font(13)
    pts = [xy(p) for p in course]
    dr.line(pts, fill=(10, 26, 48), width=12)
    dr.line(pts, fill=(56, 148, 235), width=5)
    for row in edges:
        mid = row.get("midpoint") or []
        if len(mid) < 2:
            continue
        mx, my = xy(mid)
        bridged = bool(row.get("bridged_1936"))
        col = (108, 82, 41) if bridged else (184, 56, 41)
        half = 10 if bridged else 7
        dr.line([(mx - half, my), (mx + half, my)], fill=col, width=4 if bridged else 3)
        if not bridged:
            dr.line([(mx, my - 6), (mx, my + 6)], fill=col, width=2)
    for name, c in cities.items():
        canv = c.get("canvas") or []
        if len(canv) < 2:
            continue
        px, py = xy(canv)
        off = name == "Essen"
        fill = (220, 90, 70) if off else (240, 230, 180)
        dr.ellipse((px - 4, py - 4, px + 4, py + 4), fill=fill)
        label = "%s  d=%.2f" % (name, float(c.get("rhine_dist", 0)))
        dr.text((px + 7, py - 10), label, fill=fill, font=small)
    dr.text((20, 12), "RX-1 mid-zoom Rhine (reprojected NE 321)  Bonn → Köln → Düsseldorf → Duisburg", fill=(230, 230, 230), font=font)
    dr.text((20, h - 28), "Alignment evidence · not a live F5 Play screenshot · Essen is the off-river control", fill=(160, 160, 160), font=small)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)


def render_closezoom_with_units(spec: dict, out: Path) -> None:
    """Close-zoom mock: unit plates under a haloed Rhine through Köln. Not live F5."""
    course = (spec.get("course") or {}).get("points") or []
    cities = ((spec.get("alignment") or {}).get("city_distances_canvas") or {})
    koeln = (cities.get("Köln") or {}).get("canvas") or [4253.87, 944.58]
    cx, cy = float(koeln[0]), float(koeln[1])
    span = 6.0
    minx, miny, maxx, maxy = cx - span, cy - span, cx + span, cy + span
    w, h = 1280, 720
    sx = (w - 80) / max(0.001, maxx - minx)
    sy = (h - 80) / max(0.001, maxy - miny)
    s = min(sx, sy)

    def xy(p):
        return (40 + (float(p[0]) - minx) * s, 40 + (float(p[1]) - miny) * s)

    img = Image.new("RGB", (w, h), (22, 38, 28))
    dr = ImageDraw.Draw(img)
    font = _font(16)
    small = _font(13)
    # Unit plates first (under the river) — FIX1 order.
    for ox, oy, tag in ((-1.6, -0.8, "GER"), (1.2, 0.6, "GER"), (0.2, 1.8, "GER")):
        px, py = xy((cx + ox, cy + oy))
        dr.rectangle((px - 34, py - 22, px + 34, py + 22), fill=(196, 168, 78), outline=(40, 32, 16))
        dr.text((px - 16, py - 10), tag, fill=(30, 24, 10), font=small)
    pts = [xy(p) for p in course]
    dr.line(pts, fill=(10, 26, 48), width=16)
    dr.line(pts, fill=(56, 148, 235), width=7)
    kxy = xy(koeln)
    dr.ellipse((kxy[0] - 5, kxy[1] - 5, kxy[0] + 5, kxy[1] + 5), fill=(240, 230, 180))
    dr.text((kxy[0] + 10, kxy[1] - 12), "Köln", fill=(240, 230, 180), font=small)
    dr.text((20, 12), "RX-1 close-zoom Rhine through Köln · units under the river (z 36 > 28)", fill=(230, 230, 230), font=font)
    dr.text((20, h - 28), "Alignment / z-order mock · not a live F5 Play screenshot", fill=(160, 160, 160), font=small)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)


def render_inspector(title: str, lines: list[str], out: Path, button: str = "") -> None:
    w, h = 720, 420
    img = Image.new("RGB", (w, h), (28, 30, 36))
    dr = ImageDraw.Draw(img)
    font = _font(18)
    body = _font(15)
    dr.rectangle((16, 16, w - 16, h - 16), outline=(90, 100, 120), width=2)
    dr.text((28, 28), title, fill=(240, 236, 210), font=font)
    y = 70
    for line in lines:
        col = (120, 200, 140) if "bridged" in line.lower() and "no bridge" not in line.lower() else (230, 220, 200)
        if "no bridge" in line.lower():
            col = (220, 130, 110)
        dr.text((32, y), line, fill=col, font=body)
        y += 26
    if button:
        dr.rectangle((32, y + 8, 280, y + 42), fill=(52, 78, 110), outline=(180, 200, 220))
        dr.text((48, y + 14), button, fill=(235, 240, 250), font=body)
    dr.text((28, h - 30), "Inspector state mock · not a live F5 Play screenshot", fill=(140, 140, 140), font=_font(12))
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)


def main() -> None:
    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    render_midzoom(spec, OUT / "rx1_rhine_midzoom_bonn_koeln_duesseldorf_duisburg.png")
    render_closezoom_with_units(spec, OUT / "rx1_rhine_closezoom_koeln_units.png")
    render_inspector(
        "Neuss · #710413  (no IX-1 Road spine line)",
        [
            "Build Bridge",
            "Rhine bridge started · ETA 36 days",
            "Rhine crossing: no bridge (Rhein-Kreis Neuss ↔ Mettmann)",
            "  hop ×2.00 · attack −30%",
            "Rhine crossing: bridged (Rhein-Kreis Neuss ↔ Düsseldorf)",
            "  hop ×1.15 · attack −10%",
        ],
        OUT / "rx1_inspector_neuss_stacked.png",
    )
    render_inspector(
        "Neuss · #710413",
        [
            "Rhine crossing: no bridge (Rhein-Kreis Neuss ↔ Mettmann)",
            "  hop ×2.00 · attack −30%",
            "Rhine crossing: bridged (Rhein-Kreis Neuss ↔ Düsseldorf)",
            "  hop ×1.15 · attack −10%",
        ],
        OUT / "rx1_inspector_no_bridge_neuss.png",
        "Build Bridge",
    )
    render_inspector(
        "Köln · #710417",
        [
            "Rhine crossing: bridged (Köln ↔ Leverkusen)",
            "  hop ×1.15 · attack −10%",
            "Rhine crossing: bridged (Köln ↔ Rheinisch-Bergischer Kreis)",
            "  hop ×1.15 · attack −10%",
            "IX-1 Build Road Spine is unchanged on this hex.",
        ],
        OUT / "rx1_inspector_bridged_koeln.png",
    )
    print("wrote", OUT)


if __name__ == "__main__":
    main()
