#!/usr/bin/env python3
"""Batch-fill missing PNGs for paths referenced by code/data under assets/graphics/icons.

Style: flat strategy-game module/tech/event chips (PIL). Not art-director polish.
Records before/after counts when --report is set.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("PIL required", file=sys.stderr)
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]

# Color by domain/folder
FOLDER_COLORS = {
    "modules": (90, 110, 140),
    "tech": (70, 120, 160),
    "events": (140, 80, 100),
    "designer": (160, 120, 70),
    "space": (50, 40, 90),
    "buildings": (100, 100, 90),
    "bridges": (110, 100, 80),
    "construction": (150, 130, 70),
    "default": (80, 90, 100),
}

# Module category hint from id
HINT_COLORS = [
    (r"gun|cannon|howitzer|mm_|apfsds|torpedo|missile|bomb", (160, 70, 60)),
    (r"engine|diesel|radial|turbine|reactor|propulsion", (70, 130, 90)),
    (r"radar|sensor|sonar|aegis|optics|scanner", (60, 120, 170)),
    (r"armor|plate|skirt|reactive|composite", (110, 110, 100)),
    (r"radio|comms|antenna", (90, 90, 150)),
    (r"fuel|tank|battery|solar", (140, 140, 60)),
    (r"life_support|crew|habitat", (80, 140, 140)),
]


def collect_refs() -> set[str]:
    refs: set[str] = set()
    patterns = [
        r'res://assets/graphics/icons/[^"\']+\.png',
    ]
    # data + scripts
    for base in [ROOT / "data", ROOT / "scripts"]:
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.suffix.lower() not in {".json", ".gd", ".tres", ".cfg", ".md"}:
                continue
            try:
                t = p.read_text(encoding="utf-8", errors="replace")
            except Exception:
                continue
            for pat in patterns:
                for m in re.findall(pat, t):
                    refs.add(m)
    # module icon map explicit
    mimap = ROOT / "data/designers/module_icon_map.json"
    if mimap.is_file():
        data = json.loads(mimap.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            for v in data.values():
                if isinstance(v, str) and v.endswith(".png"):
                    if v.startswith("res://"):
                        refs.add(v)
                    else:
                        refs.add("res://assets/graphics/icons/modules/%s" % v if "/" not in v else v)
    return refs


def path_for_ref(ref: str) -> Path:
    return ROOT / ref.replace("res://", "")


def is_present(path: Path) -> bool:
    return path.is_file() and path.stat().st_size > 50


def color_for(path: Path) -> tuple:
    parts = path.parts
    folder = "default"
    for f in FOLDER_COLORS:
        if f in parts:
            folder = f
            break
    base = FOLDER_COLORS.get(folder, FOLDER_COLORS["default"])
    name = path.stem.lower()
    for pat, col in HINT_COLORS:
        if re.search(pat, name):
            return col
    return base


def label_for(stem: str) -> str:
    s = stem.replace("_", " ")
    parts = [p for p in re.split(r"[\s\-]+", s) if p]
    if not parts:
        return "?"
    if len(parts) == 1:
        return parts[0][:4].upper()
    # first letters / short
    if any(c.isdigit() for c in parts[0]):
        return (parts[0][:3] + (parts[1][:2] if len(parts) > 1 else "")).upper()[:5]
    return ("".join(p[0] for p in parts[:3])).upper()


def make_icon(path: Path, size: int = 64) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    col = color_for(path)
    # honor size from stem _64
    if path.stem.endswith("_64") or path.stem.endswith("_32"):
        try:
            size = int(path.stem.rsplit("_", 1)[-1])
        except ValueError:
            size = 64
    size = max(16, min(size, 128))
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = max(2, size // 16)
    d.rounded_rectangle([m, m, size - m - 1, size - m - 1], radius=max(3, size // 8), fill=col + (255,))
    d.rounded_rectangle(
        [m + 2, m + 2, size - m - 3, size // 2],
        radius=max(2, size // 12),
        fill=(255, 255, 255, 35),
    )
    lab = label_for(path.stem.replace("_64", "").replace("_32", ""))
    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            max(8, size // 4),
        )
    except Exception:
        font = ImageFont.load_default()
    bbox = d.textbbox((0, 0), lab, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((size - tw) // 2, (size - th) // 2 - 1), lab, fill=(255, 255, 255, 245), font=font)
    img.save(path, "PNG")


def scan(refs: set[str]) -> dict:
    missing = []
    present = []
    for r in sorted(refs):
        p = path_for_ref(r)
        if is_present(p):
            present.append(r)
        else:
            missing.append(r)
    cats = Counter()
    for m in missing:
        parts = m.replace("res://assets/graphics/icons/", "").split("/")
        cats[parts[0] if parts else "?"] += 1
    return {
        "referenced_total": len(refs),
        "referenced_present": len(present),
        "referenced_missing": len(missing),
        "missing_by_folder": dict(cats),
        "missing": missing,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", type=Path, default=None, help="Write JSON report path")
    ap.add_argument("--fill", action="store_true", help="Write missing PNGs")
    ap.add_argument("--limit", type=int, default=0, help="Max icons to fill (0=all)")
    args = ap.parse_args()
    refs = collect_refs()
    before = scan(refs)
    filled = 0
    if args.fill:
        miss = before["missing"]
        if args.limit > 0:
            miss = miss[: args.limit]
        for r in miss:
            p = path_for_ref(r)
            make_icon(p)
            filled += 1
    after = scan(refs)
    out = {
        "before": {k: before[k] for k in ("referenced_total", "referenced_present", "referenced_missing", "missing_by_folder")},
        "after": {k: after[k] for k in ("referenced_total", "referenced_present", "referenced_missing", "missing_by_folder")},
        "filled": filled,
    }
    print(json.dumps(out, indent=2))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        # full after scan without huge missing list for after file
        report = dict(after)
        report["filled"] = filled
        report["before_missing"] = before["referenced_missing"]
        report["missing_sample"] = after["missing"][:40]
        # drop full missing list from file size
        report.pop("missing", None)
        args.report.write_text(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
