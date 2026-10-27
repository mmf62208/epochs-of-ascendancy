"""NATION-TAGS-1 catalog: UKR, MDA, PRC, MAN, Poland 1945, and gap provinces.

The four tags are era owners only. None of them own a 1936 province, and none
are added to the 1936 multi-AI major list. Poland 1945 is an ownership fix on
existing cc=PL provinces (Oder–Neisse), not a new geometry pack.

Gap provinces are append-only ids 906000–906020. They moved off 905849–905869
so they miss the GAP clash window 905849–905888 and the land ids used through
905908 (GAP-USSR-WEST 905889–905899, GAP-WEST-UKR 905900–905908).
MAP-RECONCILE-1 adds the 11 unique names from those branches at 906100–906110.
GAP-CHINA-2 adds the 28 unique #124 China names at 906111–906138.
This module does not write the board.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
BOARD = ROOT / "data" / "provinces_world_accurate"
CATALOG_PATH = ROOT / "data" / "nations" / "nation_tags1.json"
FLAG_DIR = ROOT / "data" / "nations" / "flags"
LOADER_PATH = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
LABELS_PATH = ROOT / "scripts" / "map" / "MapPoliticalLabelsLayer.gd"
SCENARIO_PATH = ROOT / "data" / "scenarios" / "world_accurate.json"

ERA_YEARS: Tuple[int, ...] = (1910, 1918, 1936, 1945, 2026)
NEW_TAGS = ("UKR", "MDA", "PRC", "MAN")
FIRST_GAP_ID = 906000
LAST_GAP_ID = 906020
PRIOR_MAX_LAND_ID = 905848
BOARD_N_BEFORE = 3536
LAND_N_BEFORE = 3196
GAP_N = LAST_GAP_ID - FIRST_GAP_ID + 1
# Unique USSR-west / west-Ukraine names folded at 906100–906110.
RECONCILE_WEST_N = 11
# Unique GAP-CHINA names folded at 906111–906138. Six #124 cities stay on
# their #136 ids, so they are not in this count.
CHINA2_N = 28
BOARD_N_AFTER = BOARD_N_BEFORE + GAP_N + RECONCILE_WEST_N + CHINA2_N
LAND_N_AFTER = LAND_N_BEFORE + GAP_N + RECONCILE_WEST_N + CHINA2_N

# Witnesses that must not move. 711112 is Warsaw (POL in 1936). 711074 is a
# recovered Silesian province (GER in 1936, POL after the 1945 border).
WARSAW_ID = 711112
WROCLAW_ID = 711074
# Pins that later gap packs must not renumber or drop.
PIN_IDS = (902487, 902598, 710173, 710739, PRIOR_MAX_LAND_ID)

TAGS: Dict[str, Dict[str, str]] = {
    "UKR": {"name": "Ukraine", "color": "#005BBB", "flag": "ukr.png"},
    "MDA": {"name": "Moldova", "color": "#003DA5", "flag": "mda.png"},
    "PRC": {"name": "People's Republic of China", "color": "#DE2910", "flag": "prc.png"},
    "MAN": {"name": "Manchukuo", "color": "#FFDE00", "flag": "man.png"},
}


@dataclass(frozen=True)
class GapSpec:
    pid: int
    name: str
    lon: float
    lat: float
    # 1910, 1918, 1936, 1945, 2026. Index 2 (1936) is never a new tag.
    owners: Tuple[str, str, str, str, str]
    state_id: int
    region_id: int
    super_id: int
    adm0: str

    def owner(self, year: int) -> str:
        return self.owners[ERA_YEARS.index(int(year))]


# State 388 holds the Russian blob that already contains Donetsk (903492).
# State 357 is the existing MDA placeholder set. State 289 is the CHN blob
# set that contains Shenyang (902505). Do not park these holes in the
# scrambled historical state names (Kiev / Bessarabia / Ukraine West).
GAPS: Tuple[GapSpec, ...] = (
    GapSpec(906000, "Kiev", 30.5234, 50.4501, ("RUS", "UKR", "SOV", "SOV", "UKR"), 388, 5, 3, "UKR"),
    GapSpec(906001, "Odessa", 30.73, 46.48, ("RUS", "UKR", "SOV", "SOV", "UKR"), 388, 5, 3, "UKR"),
    GapSpec(906002, "Kharkiv", 36.23, 49.99, ("RUS", "UKR", "SOV", "SOV", "UKR"), 388, 5, 3, "UKR"),
    GapSpec(906003, "Dnipropetrovsk", 35.05, 48.46, ("RUS", "UKR", "SOV", "SOV", "UKR"), 388, 5, 3, "UKR"),
    GapSpec(906004, "Crimean ASSR", 34.10, 45.30, ("RUS", "UKR", "SOV", "SOV", "UKR"), 388, 5, 3, "UKR"),
    GapSpec(906005, "Lviv", 24.0316, 49.842, ("AUS", "POL", "POL", "SOV", "UKR"), 388, 5, 3, "UKR"),
    GapSpec(906006, "Lutsk", 25.34, 50.75, ("RUS", "POL", "POL", "SOV", "UKR"), 388, 5, 3, "UKR"),
    GapSpec(906007, "Chernivtsi", 25.94, 48.29, ("AUS", "ROM", "ROM", "SOV", "UKR"), 388, 5, 3, "UKR"),
    GapSpec(906008, "Chisinau", 28.8575, 47.0105, ("RUS", "ROM", "ROM", "SOV", "MDA"), 357, 8, 2, "MDA"),
    GapSpec(906009, "Harbin", 126.534, 45.803, ("CHI", "CHI", "CHI", "MAN", "PRC"), 289, 7, 3, "CHN"),
    GapSpec(906010, "Changchun", 125.324, 43.817, ("CHI", "CHI", "CHI", "MAN", "PRC"), 289, 7, 3, "CHN"),
    GapSpec(906011, "Qiqihar", 123.92, 47.35, ("CHI", "CHI", "CHI", "MAN", "PRC"), 289, 7, 3, "CHN"),
    GapSpec(906012, "Hailar", 119.74, 49.21, ("CHI", "CHI", "CHI", "MAN", "PRC"), 289, 7, 3, "CHN"),
    GapSpec(906013, "Chongqing", 106.55, 29.56, ("CHI", "CHI", "CHI", "CHI", "PRC"), 289, 7, 3, "CHN"),
    GapSpec(906014, "Guangzhou", 113.26, 23.13, ("CHI", "CHI", "CHI", "CHI", "PRC"), 289, 7, 3, "CHN"),
    GapSpec(906015, "Chengdu", 104.07, 30.67, ("CHI", "CHI", "CHI", "CHI", "PRC"), 289, 7, 3, "CHN"),
    GapSpec(906016, "Fuzhou", 119.30, 26.07, ("CHI", "CHI", "CHI", "CHI", "PRC"), 289, 7, 3, "CHN"),
    GapSpec(906017, "Zhengzhou", 113.63, 34.75, ("CHI", "CHI", "CHI", "CHI", "PRC"), 289, 7, 3, "CHN"),
    GapSpec(906018, "Taiyuan", 112.55, 37.87, ("CHI", "CHI", "CHI", "CHI", "PRC"), 289, 7, 3, "CHN"),
    GapSpec(906019, "Guiyang", 106.63, 26.65, ("CHI", "CHI", "CHI", "CHI", "PRC"), 289, 7, 3, "CHN"),
    GapSpec(906020, "Hohhot", 111.75, 40.84, ("CHI", "CHI", "CHI", "CHI", "PRC"), 289, 7, 3, "CHN"),
)

GAP_BY_ID: Dict[int, GapSpec] = {g.pid: g for g in GAPS}


def _check_catalog() -> None:
    if len(GAPS) != GAP_N:
        raise RuntimeError("gap table length %s != %s" % (len(GAPS), GAP_N))
    ids = [g.pid for g in GAPS]
    if ids != list(range(FIRST_GAP_ID, LAST_GAP_ID + 1)):
        raise RuntimeError("gap ids are not the contiguous append block")
    for g in GAPS:
        if g.owners[ERA_YEARS.index(1936)] in NEW_TAGS:
            raise RuntimeError("%s owns 1936 as a new tag" % g.pid)
        if len(g.owners) != len(ERA_YEARS):
            raise RuntimeError("owners arity %s" % g.pid)


_check_catalog()


def apply_gap_era_owners(year: int, owners: Dict[str, str]) -> None:
    """Override era owners for the append-only gap ids. Does not touch other ids."""
    for spec in GAPS:
        owners[str(spec.pid)] = spec.owner(year)


def catalog_document() -> dict:
    return {
        "version": 1,
        "source": "nation_tags1",
        "note": "Era tags only. None own a 1936 province on world_accurate.",
        "tags": [
            {"tag": tag, "name": info["name"], "color": info["color"], "flag": info["flag"]}
            for tag, info in TAGS.items()
        ],
    }


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _point_in_ring(x: float, y: float, pts: Sequence[Sequence[float]]) -> bool:
    n = len(pts)
    if n < 3:
        return False
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = float(pts[i][0]), float(pts[i][1])
        xj, yj = float(pts[j][0]), float(pts[j][1])
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-18) + xi):
            inside = not inside
        j = i
    return inside


def _ring_bbox(pts: Sequence[Sequence[float]]) -> Tuple[float, float, float, float]:
    xs = [float(p[0]) for p in pts]
    ys = [float(p[1]) for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def audit(board_dir: Optional[Path] = None) -> dict:
    """Read the shipped board. ``ok`` is false until tags, 1945 Poland, and gaps land."""
    d = Path(board_dir) if board_dir else BOARD
    fails: List[str] = []
    passes: List[str] = []

    if not CATALOG_PATH.is_file():
        fails.append("missing catalog %s" % CATALOG_PATH)
    else:
        doc = _load(CATALOG_PATH)
        got = {row["tag"]: row for row in doc.get("tags") or []}
        for tag, info in TAGS.items():
            row = got.get(tag) or {}
            if row.get("name") != info["name"] or row.get("color") != info["color"]:
                fails.append("catalog %s name/color" % tag)
            else:
                passes.append("catalog %s" % tag)
            flag = FLAG_DIR / info["flag"]
            if not flag.is_file() or flag.stat().st_size < 32:
                fails.append("missing flag %s" % flag.name)
            else:
                passes.append("flag %s" % flag.name)

    loader = LOADER_PATH.read_text(encoding="utf-8") if LOADER_PATH.is_file() else ""
    labels = LABELS_PATH.read_text(encoding="utf-8") if LABELS_PATH.is_file() else ""
    for tag, info in TAGS.items():
        needle = '"%s": "%s"' % (tag, info["name"])
        if needle not in loader:
            fails.append("ScenarioLoader missing %s" % needle)
        else:
            passes.append("loader %s" % tag)
        if info["color"] not in loader:
            fails.append("ScenarioLoader missing color %s" % info["color"])
        if needle not in labels:
            fails.append("labels missing %s" % needle)
        else:
            passes.append("label %s" % tag)

    scenario = SCENARIO_PATH.read_text(encoding="utf-8") if SCENARIO_PATH.is_file() else ""
    for tag in NEW_TAGS:
        if '"tag": "%s"' % tag in scenario or '"%s"' % tag in scenario:
            fails.append("world_accurate.json lists %s (1936 start must not add it)" % tag)

    base_doc = _load(d / "provinces_base.json")
    base_rows = base_doc["provinces"]
    base = {int(p["id"]): p for p in base_rows}
    for pid in PIN_IDS:
        if pid not in base:
            fails.append("pin id missing %s" % pid)
    if len(base) not in (BOARD_N_BEFORE, BOARD_N_AFTER):
        fails.append("board n %s" % len(base))

    owners = {year: _load(d / ("province_ownership_%s.json" % year))["owners"] for year in ERA_YEARS}
    counts_1936 = {tag: 0 for tag in NEW_TAGS}
    for tag in owners[1936].values():
        if tag in counts_1936:
            counts_1936[tag] += 1
    for tag, n in counts_1936.items():
        if n != 0:
            fails.append("1936 %s owns %s provinces" % (tag, n))
        else:
            passes.append("1936 %s owns 0" % tag)

    if owners[1936].get(str(WARSAW_ID)) != "POL" or owners[1945].get(str(WARSAW_ID)) != "POL":
        fails.append(
            "Warsaw 711112 owners 1936=%s 1945=%s"
            % (owners[1936].get(str(WARSAW_ID)), owners[1945].get(str(WARSAW_ID)))
        )
    else:
        passes.append("Warsaw POL in 1936 and 1945")
    if owners[1936].get(str(WROCLAW_ID)) != "GER" or owners[1945].get(str(WROCLAW_ID)) != "POL":
        fails.append(
            "Wroclaw 711074 owners 1936=%s 1945=%s"
            % (owners[1936].get(str(WROCLAW_ID)), owners[1945].get(str(WROCLAW_ID)))
        )
    else:
        passes.append("Wroclaw GER in 1936 and POL in 1945")

    pl_ids = [int(p["id"]) for p in base_rows if str(p.get("cntr_code") or "").upper() == "PL"]
    if len(pl_ids) != 73:
        fails.append("cc=PL count %s" % len(pl_ids))
    pol_1945 = sum(1 for pid in pl_ids if owners[1945].get(str(pid)) == "POL")
    if pol_1945 != len(pl_ids):
        fails.append("1945 POL on cc=PL %s/%s" % (pol_1945, len(pl_ids)))
    else:
        passes.append("1945 POL on all %s cc=PL provinces" % len(pl_ids))
    ee = next((int(p["id"]) for p in base_rows if str(p.get("cntr_code") or "").upper() == "EE"), None)
    if ee is None or owners[1945].get(str(ee)) != "SOV":
        fails.append("1945 Baltic EE sample %s owner %s" % (ee, owners[1945].get(str(ee)) if ee else None))
    else:
        passes.append("1945 EE %s stays SOV" % ee)

    present = [g.pid for g in GAPS if g.pid in base]
    if len(present) != len(GAPS):
        fails.append("gap provinces present %s/%s" % (len(present), len(GAPS)))
    else:
        passes.append("gap provinces %s-%s" % (FIRST_GAP_ID, LAST_GAP_ID))
        _audit_present_gaps(d, base, owners, fails, passes)

    return {"ok": not fails, "failures": fails, "passes": passes, "gap_ids": [g.pid for g in GAPS]}


def _audit_present_gaps(
    d: Path,
    base: Dict[int, dict],
    owners: Dict[int, Dict[str, str]],
    fails: List[str],
    passes: List[str],
) -> None:
    from ne_full_geometry_align import lonlat_to_canvas

    geo = {int(g["id"]): g for g in _load(d / "provinces_geometry.json")["provinces"]}
    adj_doc = _load(d / "province_adjacency.json")
    adj = adj_doc.get("adjacency") or {}
    method = str(adj_doc.get("method") or "")
    if "shared_edge" not in method:
        fails.append("adjacency method %s" % method)
    stats = adj_doc.get("stats") or {}
    if int(stats.get("province_n") or 0) != len(base):
        fails.append("adjacency province_n %s != %s" % (stats.get("province_n"), len(base)))
    if int(stats.get("land_n") or 0) != LAND_N_AFTER:
        fails.append("adjacency land_n %s" % stats.get("land_n"))
    if float(stats.get("land_shared_coverage") or 0) < 0.95:
        fails.append("land_shared_coverage %s" % stats.get("land_shared_coverage"))
    if int(stats.get("orphan_land_after") or 0) != 0:
        fails.append("orphan_land_after %s" % stats.get("orphan_land_after"))

    states = {int(s["id"]): s for s in _load(d / "province_states.json")["states"]}
    regions = {int(r["id"]): r for r in _load(d / "strategic_regions.json")["regions"]}
    scaffold = _load(d / "hierarchy_scaffold.json")
    memberships = {year: _load(d / ("hierarchy_membership_%s.json" % year)) for year in ERA_YEARS}
    if int(scaffold.get("province_n") or 0) != 3520 or int(scaffold.get("land_n") or 0) != 3180:
        fails.append("scaffold scalars were rewritten")
    else:
        passes.append("scaffold scalars 3520/3180 kept")

    rings = []
    for gid, g in geo.items():
        pts = g.get("points") or []
        if len(pts) < 3:
            continue
        rings.append((gid, _ring_bbox(pts), pts))

    for spec in GAPS:
        row = base[spec.pid]
        if str(row.get("name")) != spec.name:
            fails.append("%s name %s" % (spec.pid, row.get("name")))
        if str(row.get("domain") or "") != "land":
            fails.append("%s domain" % spec.pid)
        adm0 = str((row.get("meta") or {}).get("adm0_a3") or "")
        if adm0 != spec.adm0:
            fails.append("%s adm0 %s" % (spec.pid, adm0))
        cores = [str(t) for t in (row.get("core_for_tags") or [])]
        if any(t in NEW_TAGS for t in cores):
            fails.append("%s core is a new tag %s" % (spec.pid, cores))
        if int(row.get("population_base") or 0) != 0:
            fails.append("%s population_base" % spec.pid)
        for year in ERA_YEARS:
            got = owners[year].get(str(spec.pid))
            if got != spec.owner(year):
                fails.append("%s era %s owner %s != %s" % (spec.pid, year, got, spec.owner(year)))
        g = geo.get(spec.pid) or {}
        pts = g.get("points") or []
        if len(pts) < 3:
            fails.append("%s geometry" % spec.pid)
            continue
        x, y = lonlat_to_canvas(spec.lon, spec.lat)
        if not _point_in_ring(x, y, pts):
            fails.append("%s city not inside ring" % spec.pid)
        anchor = g.get("label_anchor") or []
        if len(anchor) < 2 or not _point_in_ring(float(anchor[0]), float(anchor[1]), pts):
            fails.append("%s label_anchor outside ring" % spec.pid)
        bb = _ring_bbox(pts)
        for oid, obb, opts in rings:
            if oid == spec.pid:
                continue
            if obb[2] < bb[0] or obb[0] > bb[2] or obb[3] < bb[1] or obb[1] > bb[3]:
                continue
            if _point_in_ring(x, y, opts):
                fails.append("%s city also inside %s" % (spec.pid, oid))
                break
        nbrs = [int(n) for n in (adj.get(str(spec.pid)) or [])]
        if not nbrs:
            fails.append("%s adjacency empty" % spec.pid)
        else:
            for n in nbrs:
                back = [int(x) for x in (adj.get(str(n)) or [])]
                if spec.pid not in back:
                    fails.append("%s adjacency not symmetric with %s" % (spec.pid, n))
                    break
        for year, mem in memberships.items():
            if int(mem["province_to_region"].get(str(spec.pid)) or 0) != spec.region_id:
                fails.append("%s membership %s region" % (spec.pid, year))
            if int(mem["province_to_state"].get(str(spec.pid)) or 0) != spec.state_id:
                fails.append("%s membership %s state" % (spec.pid, year))
            if int(mem["province_to_super_region"].get(str(spec.pid)) or 0) != spec.super_id:
                fails.append("%s membership %s super" % (spec.pid, year))
        if int(scaffold["province_to_region"].get(str(spec.pid)) or 0) != spec.region_id:
            fails.append("%s scaffold region" % spec.pid)
        if int(scaffold["province_to_state"].get(str(spec.pid)) or 0) != spec.state_id:
            fails.append("%s scaffold state" % spec.pid)
        if int(scaffold["province_to_super_region"].get(str(spec.pid)) or 0) != spec.super_id:
            fails.append("%s scaffold super" % spec.pid)
        if spec.pid not in [int(x) for x in (states.get(spec.state_id) or {}).get("province_ids") or []]:
            fails.append("%s missing from state %s" % (spec.pid, spec.state_id))
        if spec.pid not in [int(x) for x in (regions.get(spec.region_id) or {}).get("province_ids") or []]:
            fails.append("%s missing from region %s" % (spec.pid, spec.region_id))
    if not any(f.startswith("906") or "gap" in f or "adjacency" in f or "era" in f for f in fails):
        passes.append("gap owners, rings, and symmetric adjacency")


def gap_ids() -> Iterable[int]:
    return (g.pid for g in GAPS)
