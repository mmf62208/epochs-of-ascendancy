#!/usr/bin/env python3
"""FIRST20-P2 before/after evidence stills (not live F5 Play).

Start-zoom: full cards (before) vs 22x16 stack chips (after).
Mapmode strip: Ix/S/M/H/X overflow (before) vs Intensity + More + CYAN (after).
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "docs" / "evidence" / "first20_p2"

BG_DEEP = (15, 15, 30, 255)
BG_PANEL = (22, 33, 62, 255)
CYAN = (51, 230, 255, 255)
TEXT = (238, 242, 255, 255)
TEXT_DIM = (154, 168, 199, 255)
GER = (70, 78, 70, 255)
OWNER = (90, 110, 90, 255)


def _font(size: int) -> ImageFont.ImageFont:
    for p in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ):
        if Path(p).is_file():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def _card(dr: ImageDraw.ImageDraw, xy: tuple[int, int], n: int) -> None:
    x, y = xy
    dr.rectangle((x, y, x + 88, y + 80), fill=(40, 48, 42, 255), outline=OWNER, width=2)
    dr.text((x + 8, y + 10), "I", fill=TEXT, font=_font(18))
    dr.text((x + 28, y + 14), "Division 0", fill=TEXT, font=_font(11))
    dr.rectangle((x + 8, y + 44, x + 80, y + 48), fill=(70, 210, 110, 255))
    dr.rectangle((x + 8, y + 50, x + 70, y + 54), fill=(240, 180, 50, 255))
    dr.rectangle((x + 8, y + 56, x + 74, y + 60), fill=(90, 190, 240, 255))
    dr.ellipse((x + 70, y + 4, x + 86, y + 20), fill=BG_DEEP, outline=CYAN)
    dr.text((x + 74, y + 6), str(n), fill=CYAN, font=_font(10))


def _stack(dr: ImageDraw.ImageDraw, xy: tuple[int, int], n: int) -> None:
    x, y = xy
    dr.rectangle((x, y, x + 22, y + 16), fill=(15, 15, 30, 217), outline=OWNER, width=1)
    dr.text((x + 5, y + 1), str(n), fill=(255, 255, 255, 255), font=_font(11))


def render_start_zoom() -> None:
    w, h = 640, 360
    before = Image.new("RGBA", (w, h), (48, 92, 52, 255))
    after = Image.new("RGBA", (w, h), (48, 92, 52, 255))
    db = ImageDraw.Draw(before)
    da = ImageDraw.Draw(after)
    db.text((12, 8), "BEFORE  start zoom z=0.40  full cards", fill=TEXT, font=_font(14))
    da.text((12, 8), "AFTER  start zoom z=0.40  stack chips 22x16", fill=TEXT, font=_font(14))
    db.text((12, 28), "Germany  (covered)", fill=(220, 80, 80, 255), font=_font(22))
    da.text((12, 28), "Germany", fill=TEXT, font=_font(22))
    for i, pos in enumerate(((80, 70), (150, 90), (220, 60), (300, 110), (180, 160), (260, 180))):
        _card(db, pos, 8 + i)
        _stack(da, (pos[0] + 30, pos[1] + 40), 8 + i)
    before.save(OUT / "before_start_zoom.png")
    after.save(OUT / "after_start_zoom.png")


def _chip(dr: ImageDraw.ImageDraw, xy: tuple[int, int], label: str, active: bool) -> int:
    x, y = xy
    font = _font(12)
    tw = font.getlength(label) if hasattr(font, "getlength") else len(label) * 7
    w = int(tw + 16)
    if active:
        dr.rectangle((x, y, x + w, y + 28), fill=CYAN)
        dr.text((x + 8, y + 6), label, fill=BG_DEEP, font=font)
    else:
        dr.rectangle((x, y, x + w, y + 28), fill=BG_PANEL, outline=TEXT_DIM)
        dr.text((x + 8, y + 6), label, fill=TEXT, font=font)
    return w + 4


def render_mapmodes() -> None:
    modes = [
        "Political",
        "Strain",
        "Vitality",
        "Development",
        "Supply",
        "Munitions",
        "Loyalty",
        "Infra",
        "Naval",
        "Weather",
        "Resources",
        "States",
        "Terrain",
    ]
    for mode in modes:
        w, h = 900, 160
        before = Image.new("RGBA", (w, h), BG_DEEP)
        after = Image.new("RGBA", (w, h), BG_DEEP)
        db = ImageDraw.Draw(before)
        da = ImageDraw.Draw(after)
        tag = mode.lower()
        db.text((10, 6), "BEFORE  mapmode=%s  F2 stuck  Ix S/M/H/X  overflow" % mode, fill=TEXT_DIM, font=_font(12))
        da.text((10, 6), "AFTER  mapmode=%s  F2 toggles  Intensity  More" % mode, fill=TEXT_DIM, font=_font(12))
        x = 10
        for m in modes:
            x += _chip(db, (x, 28), m, m == mode)
        db.text((10, 64), "Preset Overview Logistics Corridor Fronts WarLoop Theater Climate Build Resources States Terrain Warpath StormOps BuildNet Society…", fill=TEXT_DIM, font=_font(11))
        db.text((10, 92), "Ix  [S] [M] [H] [X]", fill=TEXT_DIM, font=_font(13))
        x = 10
        for m in modes:
            x += _chip(da, (x, 28), m, m == mode)
        da.text((10, 64), "Preset  Overview  Logistics  Corridor  Fronts  WarLoop  Theater  Climate  More ▾", fill=TEXT, font=_font(12))
        da.text((10, 92), "Intensity  [Low]  [Med]  [High]  [Max]    min ████████ max", fill=TEXT, font=_font(12))
        stem = tag.replace(" ", "_")
        before.save(OUT / ("before_mapmode_%s.png" % stem))
        after.save(OUT / ("after_mapmode_%s.png" % stem))


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    render_start_zoom()
    render_mapmodes()
    print("wrote", OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
