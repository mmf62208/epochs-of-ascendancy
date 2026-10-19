#!/usr/bin/env python3
"""BAVARIA-1: berg/andes are not enough to call a province mountains.

T1 and T2 read the committed JSON (they fail on the pre-fix board).
T3 re-runs the terrain-only generator and requires byte-identical JSON.
Mutants edit the generator source, then restore it.
"""
from __future__ import annotations

import importlib.util
import json
import re
import unittest
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools" / "map_generation" / "scripts" / "polish_world_accurate_terrain.py"
D = ROOT / "data" / "provinces_world_accurate"
ORIGINAL = SCRIPT.read_text(encoding="utf-8")

# Legitimate mountain evidence. "berg" is absent. "andes" is a whole word.
_REAL_WORD = re.compile(r"\b(?:alps|andes|atlas|tirol|tyrol|alpen)\b")
_ANDES_WORD = re.compile(r"\bandes\b")
_REAL_SUB = (
    "himal", "rocky", "tibet", "caucas", "pyrene", "carpath", "zagros",
    "hindu kush", "pamir", "altai", "urals", "appalach", "cascade",
    "montblanc", "savoie", "valais", "graub", "mountain",
)
_WATER = frozenset({"sea", "ocean", "water", "lake", "strait"})
_ID_HASH = "bf9b6be110fa8c33ea090e1a1d176511851a73b9ce58c8ec547317b007ddafe1"
_PROVINCE_COUNT = 3536

# Named bars from the brief.
_NOT_MOUNTAINS = {
    710224: "Starnberg",
    710217: "Landsberg am Lech",
    710290: "Aichach-Friedberg",
    710265: "Nürnberg",
    710177: "Heidelberg",
    710876: "Bergamo",
    710760: "Landes",
}
_MUST_MOUNTAINS = {
    710216: "Garmisch-Partenkirchen",
    710208: "Berchtesgadener Land",
    710299: "Oberallgäu",
}
_STAY_NUTS = ("AT333", "AT334", "AT335", "CH012", "CH056", "FRK27", "FRK28")
_STICKY_PLAINS = {
    710367: "Hameln-Pyrmont",
    711128: "Terras de Trás-os-Montes",
    711520: "Gibraltar",
    905844: "Hong Kong",
}

_NEEDLE_BERG = '    "himal",'
_NEEDLE_ALPINE = '    return alpine.get(str(nuts or "").strip().upper(), "")'
_NEEDLE_WORD = "    return _WORD_RE.search(low) is not None"
_MUTANT_WORD = '    return any(tok in low for tok in ("alps", "andes", "atlas", "tirol", "tyrol", "alpen"))'


def _load_mod(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load terrain generator")
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


def _real_evidence(name: str, nuts: str, alpine: set) -> bool:
    if nuts.upper() in alpine:
        return True
    low = name.lower()
    if _REAL_WORD.search(low):
        return True
    return any(tok in low for tok in _REAL_SUB)


def _t1_offenders(provinces: list, alpine: set) -> list:
    bad = []
    for p in provinces:
        terrain = str(p.get("terrain") or "")
        domain = str(p.get("domain") or "land").lower()
        if terrain != "mountains" or terrain in _WATER or domain in _WATER:
            continue
        low = str(p.get("name") or "").lower()
        berg = "berg" in low
        andes_false = "andes" in low and _ANDES_WORD.search(low) is None
        if not berg and not andes_false:
            continue
        nuts = str(p.get("nuts_id") or "")
        if _real_evidence(str(p.get("name") or ""), nuts, alpine):
            continue
        bad.append("%s (%s)" % (p.get("name"), p.get("id")))
    return bad


class TestBavaria1TerrainKeywords(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = _load_mod("bavaria1_product")
        cls.base = json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))
        cls.layer = json.loads((D / "province_terrain_layer.json").read_text(encoding="utf-8"))
        cls.provinces = list(cls.base["provinces"])
        cls.by_id = {int(p["id"]): p for p in cls.provinces}
        cls.alpine = set(cls.mod.load_alpine())

    def test_t1_no_berg_or_andes_only_mountains(self) -> None:
        bad = _t1_offenders(self.provinces, self.alpine)
        self.assertEqual(bad, [], msg=bad)
        for pid, name in _NOT_MOUNTAINS.items():
            terr = str(self.by_id[pid]["terrain"])
            self.assertNotEqual(terr, "mountains", msg="%s %s is %s" % (pid, name, terr))
            self.assertIn(name.split(",")[0], str(self.by_id[pid]["name"]))
        for pid, name in _STICKY_PLAINS.items():
            self.assertNotEqual(str(self.by_id[pid]["terrain"]), "mountains", msg=name)
        self.assertEqual(self.by_id[711220]["terrain"], "forest")

    def test_t2_alpine_rim_and_named_ranges(self) -> None:
        for pid, name in _MUST_MOUNTAINS.items():
            self.assertEqual(self.by_id[pid]["terrain"], "mountains", msg=name)
        by_nuts = {}
        for p in self.provinces:
            nuts = str(p.get("nuts_id") or "").upper()
            if nuts:
                by_nuts[nuts] = p
        for nuts in _STAY_NUTS:
            self.assertEqual(by_nuts[nuts]["terrain"], "mountains", msg=nuts)
        alpine = self.mod.load_alpine()
        for code, kind in alpine.items():
            self.assertIn(code, by_nuts, msg=code)
            self.assertEqual(by_nuts[code]["terrain"], kind, msg="%s %s" % (code, by_nuts[code]["name"]))
        # German annex has no foothill column for these two.
        self.assertEqual(alpine["DE21N"], "mountains")
        self.assertEqual(alpine["DE21M"], "mountains")
        self.assertNotIn("ITC46", alpine)

    def test_t3_generator_reproduces_json_bytes(self) -> None:
        base_raw = (D / "provinces_base.json").read_bytes()
        layer_raw = (D / "province_terrain_layer.json").read_bytes()
        base_list = list(self.base["provinces"])
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8")).get("provinces") or []
        }
        new_base, new_layer = self.mod.render_terrain_texts(
            base_raw.decode("utf-8"),
            layer_raw.decode("utf-8"),
            base_list,
            geo,
            self.mod.load_alpine(),
        )
        self.assertEqual(new_base.encode("utf-8"), base_raw)
        self.assertEqual(new_layer.encode("utf-8"), layer_raw)
        rep = self.mod.sync_terrain_files(write=False)
        self.assertEqual(rep["n"], 0)
        self.assertEqual(rep["alpine_missing"], [])
        self.assertTrue(rep["base_same"])
        self.assertTrue(rep["layer_same"])

    def test_t4_pid_set_and_keys_unchanged(self) -> None:
        import hashlib
        ids = [int(p["id"]) for p in self.provinces]
        self.assertEqual(len(ids), _PROVINCE_COUNT)
        self.assertEqual(len(set(ids)), _PROVINCE_COUNT)
        digest = hashlib.sha256(",".join(str(i) for i in ids).encode()).hexdigest()
        self.assertEqual(digest, _ID_HASH)
        layer = self.layer["provinces"]
        self.assertEqual(set(layer), {str(i) for i in ids})
        self.assertEqual(set(self.base.keys()), {"provinces"})
        self.assertEqual(set(self.layer.keys()), {"provinces"})
        for key, row in layer.items():
            self.assertEqual(set(row.keys()), {"terrain", "domain"}, msg=key)
            self.assertEqual(row["terrain"], self.by_id[int(key)]["terrain"])

    def test_mutant_readd_berg_fails_t1(self) -> None:
        with _mutated(_NEEDLE_BERG, '    "berg",\n    "himal",', "bavaria1_mut_berg") as mod:
            bad = _t1_offenders(self._classified(mod), set(mod.load_alpine()))
            self.assertTrue(bad, msg="re-adding berg must fail T1")
            self.assertTrue(any(x.startswith("Starnberg") for x in bad), msg=bad)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_drop_alpine_lookup_fails_t2(self) -> None:
        with _mutated(_NEEDLE_ALPINE, '    return ""', "bavaria1_mut_alpine") as mod:
            by_id = {int(p["id"]): p for p in self._classified(mod)}
            self.assertNotEqual(by_id[710216]["terrain"], "mountains")
            self.assertNotEqual(by_id[710208]["terrain"], "mountains")
            self.assertNotEqual(by_id[710299]["terrain"], "mountains")
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_substring_andes_fails_t1(self) -> None:
        with _mutated(_NEEDLE_WORD, _MUTANT_WORD, "bavaria1_mut_sub") as mod:
            bad = _t1_offenders(self._classified(mod), set(mod.load_alpine()))
            self.assertTrue(any(x.startswith("Landes") for x in bad), msg=bad)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def _classified(self, mod) -> list:
        _doc, base_list, geo, _bt, _lt = mod.load_board()
        desired = mod.assign_all(base_list, geo, mod.load_alpine())
        out = []
        for p in base_list:
            row = dict(p)
            pid = int(p["id"])
            if pid in desired:
                row["terrain"] = desired[pid]
            out.append(row)
        return out


if __name__ == "__main__":
    unittest.main()
