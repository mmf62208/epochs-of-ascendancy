#!/usr/bin/env python3
"""Terrain + resource heuristics for provinces_world_accurate.

Lat/lon + adm0 + name based — not DEM. Safe re-run.

  python3 tools/map_generation/scripts/polish_world_accurate_terrain.py --dry-run
  python3 tools/map_generation/scripts/polish_world_accurate_terrain.py --terrain-only

BAVARIA-1: "berg" is not a mountain token. Short tokens (andes, alps, atlas,
tirol, tyrol, alpen) match a whole word so Landes cannot hit "andes".
Alpine Convention NUTS codes in alpine_nuts3.txt set mountains, or hills
when the file's second column says hills. A full --write still rewrites
resources; terrain regen uses --terrain-only and does not touch that file.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "data" / "provinces_world_accurate"
ALPINE_PATH = ROOT / "tools" / "map_generation" / "data" / "alpine_nuts3.txt"

W, H = 8192.0, 4096.0
LON0, LAT0 = -180.0, 83.0
LON1, LAT1 = 180.0, -56.0

WATER_T = frozenset({"sea", "ocean", "water", "lake"})
WATER_D = frozenset({"sea", "strait", "lake", "ocean"})

DESERT_ADM0 = {
    "SAU", "ARE", "OMN", "YEM", "QAT", "BHR", "KWT", "JOR", "IRQ", "LBY", "EGY",
    "SDN", "SDS", "NER", "MLI", "TCD", "MRT", "ESH", "SAH", "DZA", "TUN", "MAR",
    "AFG", "TKM", "UZB", "KAZ",
}
JUNGLE_ADM0 = {
    "BRA", "COD", "COG", "GAB", "CMR", "CAF", "GIN", "CIV", "GHA", "NGA", "IDN",
    "MYS", "BRN", "PNG", "COL", "PER", "ECU", "VEN", "GUY", "SUR", "THA", "LAO",
    "KHM", "VNM", "MMR", "PHL",
}

# BAVARIA1_WORD_MATCH: whole-word short tokens. "andes" must not match Landes.
_WORD_RE = re.compile(r"\b(?:alps|andes|atlas|tirol|tyrol|alpen)\b")

# Longer tokens stay substrings. "berg" is intentionally absent (BAVARIA-1).
_SUBSTR_TOKENS = (
    "himal",
    "rocky",
    "tibet",
    "caucas",
    "pyrene",
    "carpath",
    "zagros",
    "hindu kush",
    "pamir",
    "altai",
    "urals",
    "appalach",
    "cascade",
    "montblanc",
    "savoie",
    "valais",
    "graub",
    "mountain",
)

_US_MOUNTAIN_FIPS = frozenset({"08", "16", "30", "32", "35", "49", "56", "04"})
_US_SIERRA_FIPS = frozenset({"06", "41", "53"})
_US_SIERRA_NAME = ("sierra", "mountain", "inyo", "mono", "plumas")

_ID_RE = re.compile(r'"id"\s*:\s*(\d+)')
_TERR_RE = re.compile(r'("terrain"\s*:\s*")([^"]*)(")')
_LAYER_KEY_RE = re.compile(r'^(\s*)"(\d+)"\s*:\s*\{')


def _load(p: Path) -> Any:
    return json.loads(p.read_text(encoding="utf-8"))


def _write(p: Path, obj: Any) -> None:
    p.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def _is_water(p: dict) -> bool:
    terr = str(p.get("terrain", "")).lower()
    dom = str(p.get("domain", "land")).lower()
    return terr in WATER_T or dom in WATER_D


def _centroid(pts) -> Tuple[float, float]:
    if not pts:
        return 0.0, 0.0
    return sum(float(p[0]) for p in pts) / len(pts), sum(float(p[1]) for p in pts) / len(pts)


def canvas_to_latlon(x: float, y: float) -> Tuple[float, float]:
    lon = LON0 + (x / W) * (LON1 - LON0)
    lat = LAT0 + (y / H) * (LAT1 - LAT0)
    return lat, lon


def _meta(p: dict) -> dict:
    meta = p.get("meta")
    return meta if isinstance(meta, dict) else {}


def nuts_of(p: dict) -> str:
    nuts = str(p.get("nuts_id") or "").strip()
    if nuts:
        return nuts
    return str(_meta(p).get("nuts_id") or "").strip()


def _adm0(p: dict) -> str:
    adm0 = str(_meta(p).get("adm0_a3") or "").upper()
    if adm0:
        return adm0
    return str(p.get("cntr_code") or "").upper()


def load_alpine(path: Path = ALPINE_PATH) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if not path.is_file():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        code = parts[0].upper()
        kind = parts[1].lower() if len(parts) > 1 else "mountains"
        if kind not in ("mountains", "hills"):
            kind = "mountains"
        out[code] = kind
    return out


def _word_hit(low: str) -> bool:
    # BAVARIA1_WORD_MATCH
    return _WORD_RE.search(low) is not None


def name_is_mountain(nm: str) -> bool:
    low = str(nm or "").lower()
    if _word_hit(low):
        return True
    return any(tok in low for tok in _SUBSTR_TOKENS)


def alpine_terrain_for(nuts: str, alpine: Dict[str, str]) -> str:
    # BAVARIA1_ALPINE_LOOKUP
    return alpine.get(str(nuts or "").strip().upper(), "")


def geographic_fallback(p: dict, lat: float) -> str:
    """Desert, jungle, latitude, and US state ranges.

    Ignores the stored terrain and the mountain-name list. Sierra tokens stay
    inside the CA/OR/WA state block so Sierra Leone is not marked mountains.
    """
    adm0 = _adm0(p)
    new = "plains"
    if adm0 in DESERT_ADM0 and abs(lat) < 40:
        new = "desert"
    elif adm0 in JUNGLE_ADM0 and abs(lat) < 15:
        new = "jungle"
    elif adm0 in JUNGLE_ADM0 and abs(lat) < 25:
        new = "forest"
    elif lat > 65 or lat < -55:
        new = "tundra"
    elif lat > 55 or lat < -45:
        new = "forest"
    pid = int(p["id"])
    # 905849-905851 are US islands in the RoW id band. Oahu 800094 stays in the US band.
    if 800000 <= pid < 900000 or pid in (905849, 905850, 905851):
        st = str(_meta(p).get("statefp") or "")
        nm = str(p.get("name") or "").lower()
        if st == "02":
            new = "tundra" if lat > 60 else "forest"
        elif st == "15" or pid in (905849, 905850, 905851):
            # GAP-HAWAII: the volcanic islands are mountains. Oahu stays plains.
            if pid == 800094:
                new = "plains"
            elif pid in (905849, 905850, 905851):
                new = "mountains"
        elif st in _US_MOUNTAIN_FIPS:
            new = "mountains"
        elif st in _US_SIERRA_FIPS and any(k in nm for k in _US_SIERRA_NAME):
            new = "mountains"
    return new


def classify_land(p: dict, lat: float, alpine: Dict[str, str]) -> str:
    stored = str(p.get("terrain") or "plains")
    if stored in WATER_T:
        stored = "plains"
    alpine_t = alpine_terrain_for(nuts_of(p), alpine)
    if alpine_t:
        return alpine_t
    if name_is_mountain(str(p.get("name") or "")):
        return "mountains"
    # Stored mountains with no name hit and no Alpine code are a false
    # berg/andes match, or a sticky leftover (Hameln-Pyrmont has neither token).
    if stored == "mountains":
        return geographic_fallback(p, lat)
    fallback = geographic_fallback(p, lat)
    if fallback != stored:
        return stored
    return stored


def _lat_of(p: dict, geo: Dict[int, dict]) -> float:
    pid = int(p["id"])
    g = geo.get(pid) or {}
    cx, cy = _centroid(g.get("points") or [])
    lat, _lon = canvas_to_latlon(cx, cy)
    return lat


def assign_all(base_list: List[dict], geo: Dict[int, dict], alpine: Dict[str, str]) -> Dict[int, str]:
    out: Dict[int, str] = {}
    for p in base_list:
        if _is_water(p):
            continue
        out[int(p["id"])] = classify_land(p, _lat_of(p, geo), alpine)
    return out


def terrain_updates(base_list: List[dict], geo: Dict[int, dict], alpine: Dict[str, str]) -> List[dict]:
    desired = assign_all(base_list, geo, alpine)
    by_id = {int(p["id"]): p for p in base_list}
    rows: List[dict] = []
    for pid, terr in desired.items():
        old = str(by_id[pid].get("terrain") or "")
        if terr != old:
            p = by_id[pid]
            rows.append({
                "pid": pid,
                "nuts": nuts_of(p),
                "name": str(p.get("name") or ""),
                "old": old,
                "new": terr,
            })
    rows.sort(key=lambda r: int(r["pid"]))
    return rows


def patch_base_text(text: str, updates: Dict[int, str]) -> str:
    if not updates:
        return text
    pid = -1
    out: List[str] = []
    for line in text.splitlines(keepends=True):
        mid = _ID_RE.search(line)
        if mid:
            pid = int(mid.group(1))
        if pid in updates and '"terrain"' in line:
            new = updates[pid]
            line = _TERR_RE.sub(lambda mm, _new=new: mm.group(1) + _new + mm.group(3), line, count=1)
        out.append(line)
    return "".join(out)


def patch_layer_text(text: str, updates: Dict[int, str]) -> str:
    if not updates:
        return text
    pid = -1
    out: List[str] = []
    for line in text.splitlines(keepends=True):
        mk = _LAYER_KEY_RE.match(line)
        if mk:
            pid = int(mk.group(2))
        elif pid in updates and '"terrain"' in line:
            new = updates[pid]
            line = _TERR_RE.sub(lambda mm, _new=new: mm.group(1) + _new + mm.group(3), line, count=1)
        out.append(line)
    return "".join(out)


def render_terrain_texts(
    base_text: str,
    layer_text: str,
    base_list: List[dict],
    geo: Dict[int, dict],
    alpine: Dict[str, str],
) -> Tuple[str, str]:
    rows = terrain_updates(base_list, geo, alpine)
    updates = {int(r["pid"]): str(r["new"]) for r in rows}
    return patch_base_text(base_text, updates), patch_layer_text(layer_text, updates)


def load_board() -> Tuple[dict, List[dict], Dict[int, dict], str, str]:
    base_path = D / "provinces_base.json"
    layer_path = D / "province_terrain_layer.json"
    base_text = base_path.read_text(encoding="utf-8")
    layer_text = layer_path.read_text(encoding="utf-8")
    base_doc = json.loads(base_text)
    base_list: List[dict] = list(base_doc.get("provinces") or [])
    geo = {int(g["id"]): g for g in _load(D / "provinces_geometry.json").get("provinces") or []}
    return base_doc, base_list, geo, base_text, layer_text


def sync_terrain_files(write: bool = False, alpine_path: Path = ALPINE_PATH) -> dict:
    """Patch terrain values only. Does not rewrite resources or add keys."""
    _base_doc, base_list, geo, base_text, layer_text = load_board()
    alpine = load_alpine(alpine_path)
    rows = terrain_updates(base_list, geo, alpine)
    new_base, new_layer = render_terrain_texts(base_text, layer_text, base_list, geo, alpine)
    if write:
        (D / "provinces_base.json").write_text(new_base, encoding="utf-8")
        (D / "province_terrain_layer.json").write_text(new_layer, encoding="utf-8")
    missing = sorted(set(alpine) - {nuts_of(p).upper() for p in base_list if nuts_of(p)})
    return {
        "changed": rows,
        "n": len(rows),
        "alpine_missing": missing,
        "base_same": new_base == base_text,
        "layer_same": new_layer == layer_text,
    }


def polish(write: bool = False) -> dict:
    base_doc, base_list, geo, _base_text, _layer_text = load_board()
    terr_doc = _load(D / "province_terrain_layer.json") if (D / "province_terrain_layer.json").is_file() else {"provinces": {}}
    res_doc = _load(D / "province_resources_layer.json") if (D / "province_resources_layer.json").is_file() else {"provinces": {}}
    terrain: Dict[str, dict] = dict(terr_doc.get("provinces") or {})
    resources: Dict[str, dict] = dict(res_doc.get("provinces") or {})
    alpine = load_alpine()
    desired = assign_all(base_list, geo, alpine)

    changed = 0
    oil_n = 0
    for p in base_list:
        pid = int(p["id"])
        if _is_water(p):
            terrain[str(pid)] = {
                "terrain": str(p.get("terrain") or "sea"),
                "domain": str(p.get("domain") or "sea"),
            }
            resources[str(pid)] = {}
            continue
        meta = _meta(p)
        adm0 = _adm0(p)
        new_terr = desired[pid]
        if new_terr != str(p.get("terrain") or "plains"):
            changed += 1
        p["terrain"] = new_terr
        p["domain"] = "land"
        terrain[str(pid)] = {"terrain": new_terr, "domain": "land"}

        res = dict(resources.get(str(pid)) or {})
        if new_terr == "desert" and adm0 in (
            "SAU", "IRQ", "IRN", "KWT", "ARE", "LBY", "VEN", "KAZ",
        ):
            res["oil"] = max(int(res.get("oil") or 0), 3)
        if new_terr == "mountains":
            res["steel"] = max(int(res.get("steel") or 0), 1)
            res["coal"] = max(int(res.get("coal") or 0), 1)
        if 710000 <= pid < 800000 and str(p.get("cntr_code") or "") == "DE":
            res["coal"] = max(int(res.get("coal") or 0), 2)
            res["steel"] = max(int(res.get("steel") or 0), 2)
        if 800000 <= pid < 900000:
            st = str(meta.get("statefp") or "")
            if st in ("48", "40", "22", "05"):
                res["oil"] = max(int(res.get("oil") or 0), 2)
            if st in ("42", "54", "21", "39", "18"):
                res["coal"] = max(int(res.get("coal") or 0), 2)
        if adm0 in ("RUS", "UKR", "CHN"):
            res["coal"] = max(int(res.get("coal") or 0), 1)
            res["steel"] = max(int(res.get("steel") or 0), 1)
        if adm0 == "ZAF":
            res["steel"] = max(int(res.get("steel") or 0), 2)
        if int(res.get("oil") or 0) > 0:
            oil_n += 1
        resources[str(pid)] = res

    dist = Counter(
        p.get("terrain")
        for p in base_list
        if not _is_water(p)
    )
    report = {
        "terrain_changed": changed,
        "oil_provinces": oil_n,
        "terrain_dist": dist.most_common(),
    }
    if write:
        base_doc["provinces"] = base_list
        _write(D / "provinces_base.json", base_doc)
        _write(
            D / "province_terrain_layer.json",
            {"provinces": terrain, "meta": {"source": "polish_world_accurate_terrain"}},
        )
        _write(
            D / "province_resources_layer.json",
            {"provinces": resources, "meta": {"source": "polish_world_accurate_terrain"}},
        )
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", help="rewrite base, terrain, and resources")
    ap.add_argument("--terrain-only", action="store_true", help="patch terrain values on the affected rows")
    ap.add_argument("--dry-run", action="store_true", help="print the terrain diff and do not write")
    args = ap.parse_args()
    if args.write and args.terrain_only:
        raise SystemExit("pass only one of --write or --terrain-only")
    if args.terrain_only and not args.dry_run:
        rep = sync_terrain_files(write=True)
    elif args.write and not args.dry_run:
        rep = polish(write=True)
    else:
        rep = sync_terrain_files(write=False)
    print(json.dumps(rep, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
