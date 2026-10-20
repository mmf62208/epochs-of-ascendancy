#!/usr/bin/env python3
"""ADJ-V3: Rhineland pilot borders come from NUTS shared segments, not the hex preview.

The frozen add/drop lists are the brief. The generator is reloaded from source
for each mutant, then the same audit runs. A mutant that leaves the audit
green is a failed mutant.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import unittest
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools" / "map_generation" / "scripts" / "generate_adj_v3_rhineland.py"
D = ROOT / "data" / "provinces_world_accurate"
ADJ = D / "province_adjacency.json"
V2_INTERNAL = (
    ROOT / "tools" / "map_generation" / "fixtures" / "adj_v3_v2_pilot_internal.json"
)
ORIGINAL = SCRIPT.read_text(encoding="utf-8")

# Edges outside the pilot, minus the 16 bogus links. Repair 950244-950245 is
# excluded by the audit. Re-pinned on GAP-HAWAII (8186), GAP-IBS (8192),
# GAP-CHINA (8297), GAP-USSR-WEST (8357), GAP-BELARUS (8379), then
# GAP-WEST-UKR (8406). The +27 net pairs all touch 905900-905908. Pairs
# outside that set are unchanged.
_LOCKED_HASH = "c5d3cb35148bc3a71af76b8c49284ec83bcd9962f5421d3247f0705cd09b9e4a"
_REPAIR = (950244, 950245)
_HAWAII = 800094
_GUAM = 902485
_HAWAII_KEEP = (905849, 905850, 950340)
_GUAM_KEEP = (902474, 950342)

_ADD = """
710048-711027
710051-710081
710055-710060
710064-710072
710402-710412
710421-710467
710471-710484
710472-710489
710475-710487
710484-710494
710486-710487
710082-711034
""".split()

_DROP = """
710047-710049
710047-710061
710047-710070
710047-710075
710048-710053
710048-710060
710048-710061
710048-710070
710048-711025
710048-711026
710049-710070
710051-710061
710052-710078
710053-710080
710053-711008
710053-711030
710054-711026
710055-710074
710055-711026
710057-710074
710058-710060
710060-710075
710060-710076
710061-710078
710061-710089
710062-710065
710062-710072
710064-710066
710066-710067
710066-710068
710067-710072
710068-710072
710070-710090
710071-710077
710074-711026
710076-710077
710080-710081
710080-710085
710080-710088
710081-710421
710081-710422
710081-711033
710082-710468
710084-710087
710085-710087
710085-710090
710087-710977
710401-710404
710401-710406
710401-710410
710401-710423
710401-710447
710402-710403
710404-710406
710405-711033
710406-710415
710406-710427
710406-710447
710408-710447
710409-710418
710410-710413
710410-710424
710411-711030
710411-711033
710412-710420
710412-710423
710412-710442
710413-710415
710413-710421
710413-710423
710413-710447
710413-711033
710415-711009
710416-710417
710416-710421
710416-710455
710416-710460
710421-710460
710423-710460
710424-710447
710425-710447
710429-710453
710431-710443
710431-710444
710431-710447
710432-710444
710432-710447
710434-710441
710434-710448
710437-710441
710440-710441
710443-710446
710443-710449
710446-710447
710447-710450
710447-710460
710450-710462
710454-710460
710457-710484
710458-710463
710458-710491
710460-710464
710464-710468
710464-710485
710465-710466
710465-710467
710465-710468
710468-710469
710468-710977
710469-710485
710469-710493
710470-710478
710470-710481
710471-710481
710472-710475
710472-710483
710474-710480
710475-710477
710475-710483
710476-710479
710476-710484
710476-710486
710476-710494
710477-710481
710477-710483
710477-710486
710480-710487
710481-710483
710482-710488
710484-710486
710484-710495
710485-710489
710485-710491
710494-710495
711000-711007
711000-711011
711002-711006
711004-711009
711006-711007
711008-711017
711008-711025
711008-711031
711015-711017
711016-711024
711017-711024
711019-711025
711022-711025
711025-711026
711025-711029
711026-711027
711030-711033
""".split()

# Within 50 m in the HEXP3 probe, but they share no NUTS segment. Dropped.
_NEAR_MISS = """
710047-710070
710058-710060
710060-710076
710401-710404
710410-710424
710411-711030
710472-710483
710481-710483
711026-711027
""".split()


def _pairs(lines) -> set:
    out = set()
    for line in lines:
        a, b = line.split("-")
        ai, bi = int(a), int(b)
        out.add((ai, bi) if ai < bi else (bi, ai))
    return out


def _load_mod(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load ADJ-V3 generator")
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


def _audit(doc: dict, pilot: set, base_ids: set, spec_gis: set, bogus: set, seas: set) -> set:
    """Names of broken invariants. Empty means the graph is the ADJ-V3 graph."""
    adj = doc["adjacency"]
    fails = set()
    ids = {int(k) for k in adj}
    if ids - base_ids or base_ids - ids:
        fails.add("ids")
    for a_s, nbs in adj.items():
        a = int(a_s)
        if not nbs:
            fails.add("orphan")
        for b in nbs:
            if a not in [int(x) for x in adj.get(str(int(b)), [])]:
                fails.add("asymmetry")
                break
    internal = set()
    for a_s, nbs in adj.items():
        a = int(a_s)
        if a not in pilot:
            continue
        for b in nbs:
            bi = int(b)
            if bi in pilot and a < bi:
                internal.add((a, bi))
    if internal != spec_gis:
        fails.add("pilot_internal")
    for a, b in bogus:
        nbs = [int(x) for x in adj.get(str(a), [])]
        back = [int(x) for x in adj.get(str(b), [])]
        if b in nbs or a in back:
            fails.add("bogus_present")
            break
    if _REPAIR[1] not in [int(x) for x in adj.get(str(_REPAIR[0]), [])]:
        fails.add("repair_missing")
    if [int(x) for x in adj.get(str(_HAWAII), [])] != list(_HAWAII_KEEP):
        fails.add("hawaii")
    if [int(x) for x in adj.get(str(_GUAM), [])] != list(_GUAM_KEEP):
        fails.add("guam")
    if len(adj.get("710409") or []) != 4:
        fails.add("solingen")
    if len(adj.get("710446") or []) != 3:
        fails.add("herne")
    for pid in pilot:
        n_in = sum(1 for b in adj.get(str(pid), []) if int(b) in pilot)
        if n_in < 1:
            fails.add("pilot_orphan")
            break
    locked = []
    seen = set()
    for a_s, nbs in adj.items():
        a = int(a_s)
        for b in nbs:
            bi = int(b)
            if bi <= a:
                continue
            pair = (a, bi)
            if pair in seen:
                continue
            seen.add(pair)
            if a in pilot and bi in pilot:
                continue
            if pair in bogus or pair == _REPAIR:
                continue
            locked.append("%d-%d" % pair)
    locked.sort()
    digest = hashlib.sha256("\n".join(locked).encode()).hexdigest()
    if digest != _LOCKED_HASH:
        fails.add("locked_scope")
    if str(doc.get("version")) != "3":
        fails.add("version")
    method = str(doc.get("method") or "")
    if "gis_shared_segment_rhineland_pilot + v2_elsewhere" not in method:
        fails.add("method")
    if "shared_edge" not in method:
        fails.add("method")
    # Ocean route: a sea zone reachable without the removed links.
    for start, label in ((_HAWAII, "hawaii_ocean"), (_GUAM, "guam_ocean")):
        stack = [start]
        seen_n = {start}
        hit = False
        while stack:
            cur = stack.pop()
            for b in adj.get(str(cur), []):
                bi = int(b)
                if bi in seen_n:
                    continue
                if (min(cur, bi), max(cur, bi)) in bogus:
                    continue
                if bi in seas:
                    hit = True
                    stack.clear()
                    break
                seen_n.add(bi)
                stack.append(bi)
        if not hit:
            fails.add(label)
    return fails


class TestAdjV3Rhineland(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = _load_mod("adjv3_product")
        cls.cfg = cls.mod.load_config()
        cls.base = json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))
        cls.base_ids = {int(p["id"]) for p in cls.base["provinces"]}
        cls.pilot = {int(p["id"]) for p in cls.mod.pilot_provinces(cls.base, cls.cfg)}
        cls.seas = {
            int(p["id"])
            for p in cls.base["provinces"]
            if str(p.get("domain") or "") != "land"
        }
        cls.add = _pairs(_ADD)
        cls.drop = _pairs(_DROP)
        cls.near = _pairs(_NEAR_MISS)
        cls.bogus = cls.mod.norm_pairs(cls.mod.bogus_far_links())
        v2_doc = json.loads(V2_INTERNAL.read_text(encoding="utf-8"))
        cls.v2_internal = cls.mod.norm_pairs(tuple(p) for p in v2_doc["pairs"])
        cls.spec_gis = (cls.v2_internal - cls.drop) | cls.add
        nuts = {str(p["nuts_id"]): int(p["id"]) for p in cls.mod.pilot_provinces(cls.base, cls.cfg)}
        cls.rings = cls.mod.load_pilot_rings(cls.cfg, nuts)
        cls.geom = json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))
        cls.built = json.loads(cls.mod.build_text())

    def test_spec_lists_and_gis_source(self) -> None:
        self.assertEqual(len(self.add), 12)
        self.assertEqual(len(self.drop), 151)
        self.assertEqual(len(self.near), 9)
        self.assertTrue(self.near <= self.drop)
        self.assertEqual(len(self.v2_internal), 602)
        self.assertEqual(len(self.pilot), 180)
        gis = self.mod.gis_border_pairs(self.rings, int(self.cfg["quant_decimals"]))
        self.assertEqual(gis, self.spec_gis)
        self.assertTrue(self.near.isdisjoint(gis))
        touches = self.mod.point_touch_pairs(self.rings, 6)
        self.assertEqual(touches, {(710082, 711034)})
        self.assertEqual(len(self.mod.segment_pairs_only(self.rings, 6)), 462)
        preview = self.mod.load_forbidden_hex_preview(self.cfg)
        self.assertNotEqual(preview, gis)
        self.assertEqual(len(self.bogus), 16)

    def test_built_graph_matches_spec(self) -> None:
        fails = _audit(
            self.built, self.pilot, self.base_ids, self.spec_gis, self.bogus, self.seas
        )
        self.assertEqual(fails, set(), msg=sorted(fails))
        # 710173 Baden-Baden ↔ 710739 Bas-Rhin stays (outside the pilot).
        self.assertIn(710739, [int(x) for x in self.built["adjacency"]["710173"]])
        # Re-applying the generator to a reconstructed v2 board yields the same graph.
        again = self.mod.build_document(
            self._v2_doc(), self.base, self.rings, self.geom, self.cfg
        )
        self.assertEqual(again["adjacency"], self.built["adjacency"])

    def test_generator_twice_is_byte_identical(self) -> None:
        first = self.mod.render(self.built)
        second = self.mod.build_text()
        third = self.mod.build_text()
        self.assertEqual(first, second)
        self.assertEqual(second, third)

    def test_committed_file_matches_generator(self) -> None:
        self.assertEqual(ADJ.read_text(encoding="utf-8"), self.mod.build_text())
        self.assertEqual(self.mod.main(["--check"]), 0)
        dest = self.mod._repo(self.cfg, "adjacency")
        self.assertEqual(dest.parent.name, "provinces_world_accurate")

    def _v2_doc(self) -> dict:
        """v2 adjacency recovered from the built v3 graph and the frozen edge lists."""
        adj = {k: [int(x) for x in v] for k, v in self.built["adjacency"].items()}
        for a in self.pilot:
            adj[str(a)] = [b for b in adj[str(a)] if b not in self.pilot]
        for a, b in self.v2_internal:
            for src, dst in ((a, b), (b, a)):
                nbs = adj[str(src)]
                if dst not in nbs:
                    nbs.append(dst)
                adj[str(src)] = sorted(set(nbs))
        for src, dst in ((_REPAIR[0], _REPAIR[1]), (_REPAIR[1], _REPAIR[0])):
            adj[str(src)] = [b for b in adj[str(src)] if b != dst]
        for a, b in self.bogus:
            for src, dst in ((a, b), (b, a)):
                nbs = adj[str(src)]
                if dst not in nbs:
                    nbs.append(dst)
                adj[str(src)] = sorted(set(nbs))
        return {"version": 2, "stats": {}, "adjacency": adj}

    def _mutant_fails(self, mod) -> set:
        doc = mod.build_document(self._v2_doc(), self.base, self.rings, self.geom, self.cfg)
        return _audit(doc, self.pilot, self.base_ids, self.spec_gis, self.bogus, self.seas)

    def test_mutant_readd_dropped_link(self) -> None:
        old = "    extra_add: Set[Pair] = set()  # ADJ_V3_EXTRA_ADD"
        new = "    extra_add: Set[Pair] = {(710401, 710404)}  # ADJ_V3_EXTRA_ADD"
        with _mutated(old, new, "adjv3_mut_readd") as mod:
            self.assertIn("pilot_internal", self._mutant_fails(mod))
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_drop_one_added_link(self) -> None:
        old = "    extra_drop: Set[Pair] = set()  # ADJ_V3_EXTRA_DROP"
        new = "    extra_drop: Set[Pair] = {(710402, 710412)}  # ADJ_V3_EXTRA_DROP"
        with _mutated(old, new, "adjv3_mut_drop") as mod:
            self.assertIn("pilot_internal", self._mutant_fails(mod))
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_hex_preview_instead_of_gis(self) -> None:
        old = "    return segment_pairs | point_touch_pairs"
        new = "    return load_forbidden_hex_preview()"
        with _mutated(old, new, "adjv3_mut_hex") as mod:
            self.assertIn("pilot_internal", self._mutant_fails(mod))
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_skip_hawaii_guam_removal(self) -> None:
        old = "    return _BOGUS_FAR_LINKS"
        new = "    return ()"
        with _mutated(old, new, "adjv3_mut_bogus") as mod:
            doc = mod.build_document(
                self._v2_doc(), self.base, self.rings, self.geom, self.cfg
            )
            fails = _audit(doc, self.pilot, self.base_ids, self.spec_gis, self.bogus, self.seas)
            self.assertIn("bogus_present", fails)
            self.assertIn(800023, [int(x) for x in doc["adjacency"]["800094"]])
            self.assertIn(_HAWAII_KEEP[0], [int(x) for x in doc["adjacency"]["800094"]])
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_renumber_pilot_pid(self) -> None:
        old = "    return int(pid)  # ADJ_V3_PID identity"
        new = "    return 905849 if int(pid) == 710048 else int(pid)  # ADJ_V3_PID identity"
        with _mutated(old, new, "adjv3_mut_renumber") as mod:
            doc = mod.build_document(
                self._v2_doc(), self.base, self.rings, self.geom, self.cfg
            )
            ids = {int(k) for k in doc["adjacency"]}
            self.assertNotIn(710048, ids)
            self.assertIn(905849, ids)
            fails = _audit(doc, self.pilot, self.base_ids, self.spec_gis, self.bogus, self.seas)
            self.assertIn("ids", fails)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_orphan_solingen(self) -> None:
        old = "    _orphan_pid = 0  # ADJ_V3_ORPHAN"
        new = "    _orphan_pid = 710409  # ADJ_V3_ORPHAN"
        with _mutated(old, new, "adjv3_mut_orphan") as mod:
            doc = mod.build_document(
                self._v2_doc(), self.base, self.rings, self.geom, self.cfg
            )
            self.assertEqual(doc["adjacency"]["710409"], [])
            fails = _audit(doc, self.pilot, self.base_ids, self.spec_gis, self.bogus, self.seas)
            self.assertIn("orphan", fails)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_skip_symmetry_pass(self) -> None:
        old = "    _mirror_forward_links(adj)"
        new = "    return"
        with _mutated(old, new, "adjv3_mut_sym") as mod:
            self.assertIn("asymmetry", self._mutant_fails(mod))
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)


if __name__ == "__main__":
    unittest.main()
