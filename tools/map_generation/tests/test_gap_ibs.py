#!/usr/bin/env python3
"""GAP-IBS: Iwo Jima, the Bonins, and Saipan, plus two carved seas.

Mutants edit the generator source, reload it, and write only a temp copy of
the board. The live board is audited as committed. The sea-overlap check
clips the parent rings itself; it does not trust the generator's clip.
"""
from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools" / "map_generation" / "scripts" / "generate_gap_ibs.py"
D = ROOT / "data" / "provinces_world_accurate"
FIXTURE = ROOT / "tools" / "map_generation" / "fixtures" / "gap_ibs_parent_seas.json"
ORIGINAL = SCRIPT.read_text(encoding="utf-8")

IWO = 905852
BONIN = 905853
SAIPAN = 905854
VOLCANO = 950341
MARIANAS = 950342
GUAM = 902485
POHNPEI = 902474
PARENTS = (950046, 950048)
NEW = (IWO, BONIN, SAIPAN, VOLCANO, MARIANAS)
LAND = (IWO, BONIN, SAIPAN)
YEARS = (1910, 1918, 1936, 1945, 2026)
OWNERS = {
    1910: {IWO: "JAP", BONIN: "JAP", SAIPAN: "GER", VOLCANO: "JAP", MARIANAS: "GER"},
    1918: {IWO: "JAP", BONIN: "JAP", SAIPAN: "JAP", VOLCANO: "JAP", MARIANAS: "JAP"},
    1936: {IWO: "JAP", BONIN: "JAP", SAIPAN: "JAP", VOLCANO: "JAP", MARIANAS: "JAP"},
    1945: {IWO: "USA", BONIN: "USA", SAIPAN: "USA", VOLCANO: "USA", MARIANAS: "USA"},
    2026: {IWO: "JAP", BONIN: "JAP", SAIPAN: "USA", VOLCANO: "JAP", MARIANAS: "USA"},
}
NAMES = {
    IWO: "Iwo Jima",
    BONIN: "Bonin Islands",
    SAIPAN: "Saipan",
    VOLCANO: "Volcano-Bonin Waters",
    MARIANAS: "Marianas Waters",
}
VOLCANO_RECT = (140.70, 147.60, 24.00, 29.50)
W_PX = 8192.0
H_PX = 4096.0
RESERVED = set(range(905855, 905889))
LAYER_NAMES = (
    "province_ownership_1910.json",
    "province_ownership_1918.json",
    "province_ownership_1936.json",
    "province_ownership_1945.json",
    "province_ownership_2026.json",
    "hierarchy_membership_1910.json",
    "hierarchy_membership_1918.json",
    "hierarchy_membership_1936.json",
    "hierarchy_membership_1945.json",
    "hierarchy_membership_2026.json",
    "province_terrain_layer.json",
    "province_economy_layer.json",
    "province_resources_layer.json",
    "strategic_regions.json",
    "hierarchy_scaffold.json",
    "provinces_base.json",
    "provinces_geometry.json",
    "province_city_layer.json",
    "province_states.json",
    "province_adjacency.json",
)


def _load_mod(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load gap ibs generator")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@contextmanager
def _mutated(old: str, new: str, name: str):
    text = SCRIPT.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise AssertionError("mutant needle missing or not unique: %r" % old)
    SCRIPT.write_text(text.replace(old, new, 1), encoding="utf-8")
    try:
        yield _load_mod(name)
    finally:
        SCRIPT.write_text(text, encoding="utf-8")


def _read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _canvas_to_lonlat(x: float, y: float):
    lon = -180.0 + (x / W_PX) * 360.0
    lat = 83.0 + (y / H_PX) * (-139.0)
    return (lon, lat)


def _ring_area(ring):
    area = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        area += x1 * y2 - x2 * y1
    return area / 2.0


def _dedupe(ring):
    cleaned = []
    for p in ring:
        if not cleaned or abs(p[0] - cleaned[-1][0]) > 1e-9 or abs(p[1] - cleaned[-1][1]) > 1e-9:
            cleaned.append((float(p[0]), float(p[1])))
    if len(cleaned) > 1 and abs(cleaned[0][0] - cleaned[-1][0]) < 1e-9 and abs(cleaned[0][1] - cleaned[-1][1]) < 1e-9:
        cleaned.pop()
    return cleaned


def _clip_plane(poly, inside, inter):
    if not poly:
        return []
    out = []
    prev = poly[-1]
    prev_in = inside(prev)
    for cur in poly:
        cur_in = inside(cur)
        if cur_in:
            if not prev_in:
                out.append(inter(prev, cur))
            out.append(cur)
        elif prev_in:
            out.append(inter(prev, cur))
        prev, prev_in = cur, cur_in
    return _dedupe(out)


def _inter_x(a, b, x):
    den = b[0] - a[0]
    t = 0.0 if abs(den) < 1e-15 else (x - a[0]) / den
    return (x, a[1] + t * (b[1] - a[1]))


def _inter_y(a, b, y):
    den = b[1] - a[1]
    t = 0.0 if abs(den) < 1e-15 else (y - a[1]) / den
    return (a[0] + t * (b[0] - a[0]), y)


def _clip_rect(poly, rect):
    west, east, south, north = rect
    p = _clip_plane(list(poly), lambda q: q[0] >= west, lambda a, b: _inter_x(a, b, west))
    p = _clip_plane(p, lambda q: q[0] <= east, lambda a, b: _inter_x(a, b, east))
    p = _clip_plane(p, lambda q: q[1] >= south, lambda a, b: _inter_y(a, b, south))
    p = _clip_plane(p, lambda q: q[1] <= north, lambda a, b: _inter_y(a, b, north))
    return p


def _ll_ring(points):
    return [_canvas_to_lonlat(float(p[0]), float(p[1])) for p in points]


def _pip(x, y, ring) -> bool:
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-30) + xi):
            inside = not inside
        j = i
    return inside


def _shrink_fail(board: Path) -> bool:
    """True when a parent still covers the volcano rectangle or did not lose area."""
    geo = {int(g["id"]): g for g in _read(board / "provinces_geometry.json")["provinces"]}
    fix = _read(FIXTURE)["rings"]
    west, east, south, north = VOLCANO_RECT
    for pid in PARENTS:
        cur = _ll_ring(geo[pid]["points"])
        old = _ll_ring(fix[str(pid)])
        if abs(_ring_area(cur)) > abs(_ring_area(old)) - 0.15:
            return True
        inter = _clip_rect(cur, VOLCANO_RECT)
        if len(inter) >= 3 and abs(_ring_area(inter)) > 1e-3:
            return True
        hits = 0
        y = south + 0.08
        while y < north - 0.08:
            x = west + 0.08
            while x < east - 0.08:
                if _pip(x, y, cur):
                    hits += 1
                    if hits > 0:
                        return True
                x += 0.25
            y += 0.25
    return False


def _audit(board: Path) -> set:
    """Empty means the board matches the GAP-IBS bars."""
    fails = set()
    base_doc = _read(board / "provinces_base.json")
    by_id = {int(p["id"]): p for p in base_doc["provinces"]}
    ids = set(by_id)
    if ids & RESERVED:
        fails.add("reserved")
    for pid in NEW:
        row = by_id.get(pid) or {}
        if row.get("name") != NAMES[pid]:
            fails.add("new_ids")
    for pid in LAND:
        if by_id.get(pid, {}).get("terrain") != "plains" or by_id.get(pid, {}).get("domain") != "land":
            fails.add("island_terrain")
    for pid in (VOLCANO, MARIANAS):
        if str(by_id.get(pid, {}).get("domain") or "") != "sea":
            fails.add("sea_domain")
    for pid in PARENTS:
        row = by_id.get(pid) or {}
        if row.get("name") != "WestPac" or row.get("domain") != "sea" or row.get("retired_into"):
            fails.add("parents_kept")
    guam = by_id.get(GUAM) or {}
    if guam.get("name") != "Guam":
        fails.add("guam")

    for year in YEARS:
        own = _read(board / ("province_ownership_%d.json" % year)).get("owners") or {}
        mem = _read(board / ("hierarchy_membership_%d.json" % year))
        reg = mem.get("province_to_region") or {}
        st = mem.get("province_to_state") or {}
        sup = mem.get("province_to_super_region") or {}
        for pid, tag in OWNERS[year].items():
            if own.get(str(pid)) != tag:
                fails.add("era_owner")
        for pid in LAND:
            if int(reg.get(str(pid)) or 0) != 7 or int(st.get(str(pid)) or 0) != 339:
                fails.add("era_membership")
            if int(sup.get(str(pid)) or 0) != 3:
                fails.add("era_membership")
        for pid in (VOLCANO, MARIANAS):
            if int(reg.get(str(pid)) or 0) != 10 or int(sup.get(str(pid)) or 0) != 4:
                fails.add("era_sea")
            if str(pid) in st:
                fails.add("era_sea")

    adj = _read(board / "province_adjacency.json").get("adjacency") or {}
    if GUAM not in {int(k) for k in adj}:
        fails.add("renumber")
    else:
        guam_nb = sorted(int(x) for x in adj.get(str(GUAM), []))
        if guam_nb != [POHNPEI, MARIANAS]:
            fails.add("guam_link")
    for pid in NEW:
        if not adj.get(str(pid)):
            fails.add("orphan")
    expect = {
        IWO: [VOLCANO],
        BONIN: [VOLCANO],
        SAIPAN: [MARIANAS],
    }
    for pid, nbs in expect.items():
        if sorted(int(x) for x in adj.get(str(pid), [])) != nbs:
            fails.add("island_link")
    for pid in PARENTS:
        if VOLCANO not in [int(x) for x in adj.get(str(pid), [])]:
            fails.add("parent_link")
    for a_s, nbs in adj.items():
        if not nbs:
            fails.add("orphan")
            break
    for a_s, nbs in adj.items():
        a = int(a_s)
        broken = False
        for b in nbs:
            if a not in [int(x) for x in adj.get(str(int(b)), [])]:
                fails.add("asymmetry")
                broken = True
                break
        if broken:
            break

    if _shrink_fail(board):
        fails.add("shrink")

    eco = _read(board / "province_economy_layer.json").get("provinces") or {}
    for pid in NEW:
        row = eco.get(str(pid)) or {}
        if int(row.get("population") or 0) != 0 or int(row.get("factories") or 0) != 0:
            fails.add("economy")
        if int(row.get("infrastructure") or 0) != 1:
            fails.add("economy")

    city = _read(board / "province_city_layer.json").get("provinces") or {}
    if (city.get(str(BONIN)) or {}).get("city_name") != "Chichi-jima":
        fails.add("city")
    if (city.get(str(SAIPAN)) or {}).get("city_name") != "Garapan":
        fails.add("city")
    if str(IWO) in city:
        fails.add("city")

    states = _read(board / "province_states.json").get("states") or []
    jpn = next((s for s in states if int(s.get("id") or 0) == 339), {})
    state_ids = [int(x) for x in (jpn.get("province_ids") or [])]
    for pid in LAND:
        if pid not in state_ids:
            fails.add("state")
    if len(states) < 400:
        fails.add("state")

    geo = {int(g["id"]): g for g in _read(board / "provinces_geometry.json")["provinces"]}
    for pid in NEW:
        if not (geo.get(pid) or {}).get("label_anchor"):
            fails.add("anchor")
        if len((geo.get(pid) or {}).get("points") or []) < 3:
            fails.add("geometry")
    return fails


def _scratch() -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="gap-ibs-"))
    for name in LAYER_NAMES:
        shutil.copy(D / name, tmp / name)
    for year in YEARS:
        own_path = tmp / ("province_ownership_%d.json" % year)
        own = _read(own_path)
        mem_path = tmp / ("hierarchy_membership_%d.json" % year)
        mem = _read(mem_path)
        for pid in NEW:
            (own.get("owners") or {}).pop(str(pid), None)
            for key in ("province_to_region", "province_to_state", "province_to_super_region"):
                (mem.get(key) or {}).pop(str(pid), None)
        own_path.write_text(json.dumps(own), encoding="utf-8")
        mem_path.write_text(json.dumps(mem), encoding="utf-8")
    return tmp


def _apply(mod) -> Path:
    tmp = _scratch()
    mod.D = tmp
    mod.apply_layers(mod.load_island_groups())
    return tmp


class TestGapIbs(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = _load_mod("gap_ibs_product")

    def test_board_matches_spec(self) -> None:
        fails = _audit(D)
        self.assertEqual(fails, set(), msg=sorted(fails))
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_generator_twice_byte_identical(self) -> None:
        before = {name: (D / name).read_bytes() for name in LAYER_NAMES}
        self.assertEqual(self.mod.main(), 0)
        mid = {name: (D / name).read_bytes() for name in LAYER_NAMES}
        self.assertEqual(mid, before)
        self.assertEqual(self.mod.main(), 0)
        after = {name: (D / name).read_bytes() for name in LAYER_NAMES}
        self.assertEqual(after, before)

    def test_mutant_drop_one_era(self) -> None:
        old = "ERA_YEARS = (1910, 1918, 1936, 1945, 2026)"
        new = "ERA_YEARS = (1910, 1918, 1945, 2026)"
        with _mutated(old, new, "gap_ibs_mut_era") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("era_owner", fails)
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_renumber_guam(self) -> None:
        old = "return int(pid)  # GAP_IBS_PID identity"
        new = "return 999001 if int(pid) == 902485 else int(pid)  # GAP_IBS_PID identity"
        with _mutated(old, new, "gap_ibs_mut_pid") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("renumber", fails)
                base = _read(board / "provinces_base.json")
                guam = [p for p in base["provinces"] if int(p["id"]) == GUAM]
                self.assertEqual(len(guam), 1)
                self.assertEqual(guam[0]["name"], "Guam")
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_one_way_link(self) -> None:
        old = "    _mirror_pairs(adj)  # GAP_IBS_MIRROR_CALL"
        new = "    pass  # GAP_IBS_MIRROR_CALL"
        with _mutated(old, new, "gap_ibs_mut_mirror") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("asymmetry", fails)
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_skip_parent_shrink(self) -> None:
        old = "    return True  # GAP_IBS_SHRINK"
        new = "    return False  # GAP_IBS_SHRINK"
        with _mutated(old, new, "gap_ibs_mut_shrink") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("shrink", fails)
                base = _read(board / "provinces_base.json")
                for pid in PARENTS:
                    row = next(p for p in base["provinces"] if int(p["id"]) == pid)
                    self.assertEqual(row["name"], "WestPac")
                    self.assertNotIn("retired_into", row)
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)


if __name__ == "__main__":
    unittest.main()
