#!/usr/bin/env python3
"""Gates: densified hotspot names + terrain/resource/economy layer coverage on world_full."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from assign_world_hotspot_names import (  # noqa: E402
    assign_hotspot_names,
    is_numbered_hub_label,
    is_placeholder_name,
    quality_gates as name_gates,
    run_on_dir as names_run,
)
from backfill_world_province_layers import (  # noqa: E402
    backfill_layers,
    entry_nonempty_economy,
    entry_nonempty_resources,
    quality_gates as layer_gates,
    run_on_dir as layers_run,
)

WF = ROOT / "data" / "provinces_world_full"


class TestHotspotNamesPure(unittest.TestCase):
    def test_assign_replaces_numbered_hubs_uniquely(self) -> None:
        provinces = [
            {"id": 1, "name": "Berlin", "hotspot_densify": False},
            {"id": 2, "name": "China North China Plain 1", "hotspot_densify": True, "theater": "far_east"},
            {"id": 3, "name": "China North China Plain 2", "hotspot_densify": True, "theater": "far_east"},
            {"id": 4, "name": "Africa Congo Basin 1", "hotspot_densify": True, "theater": "africa"},
        ]
        stats = assign_hotspot_names(provinces)
        self.assertGreaterEqual(stats["renamed"], 3)
        self.assertEqual(stats["numbered_hub_remaining"], 0)
        self.assertTrue(stats["unique"])
        for p in provinces:
            if p.get("hotspot_densify"):
                self.assertFalse(is_numbered_hub_label(p["name"]))
                self.assertFalse(is_placeholder_name(p["name"]))
                self.assertNotEqual(p["name"], "Berlin")
        names = [p["name"] for p in provinces]
        self.assertEqual(len(names), len(set(n.lower() for n in names)))

    def test_shipped_world_hotspot_names(self) -> None:
        """Drive shipped provinces_base.json — densified names human-readable & unique."""
        base = json.loads((WF / "provinces_base.json").read_text())["provinces"]
        gates = name_gates(base)
        self.assertTrue(gates["all_unique"], msg=gates)
        self.assertTrue(gates["no_placeholders"], msg=gates)
        self.assertTrue(gates["hotspot_no_numbered_hub"], msg=gates)
        self.assertGreaterEqual(gates["hotspot_count"], 300)
        # Dry-run helper must report pass on shipped data
        stats = names_run(WF, write=False)
        self.assertTrue(stats["gates"]["hotspot_no_numbered_hub"])
        self.assertTrue(stats["gates"]["all_unique"])


class TestLayerBackfillPure(unittest.TestCase):
    def test_backfill_fills_gaps(self) -> None:
        provinces = [
            {
                "id": 10,
                "name": "Europe Core A",
                "terrain": "hills",
                "domain": "land",
                "theater": "europe_core",
                "facility_tier": "full",
                "island_class": "mainland",
            },
            {
                "id": 90001,
                "name": "Africa Congo Basin 1",
                "terrain": "plains",
                "domain": "land",
                "theater": "africa",
                "hotspot_densify": True,
                "population_base": 400000,
                "facility_tier": "full",
                "island_class": "mainland",
                "hotspot_hub": "Africa Congo Basin",
            },
            {
                "id": 50,
                "name": "Open Ocean",
                "terrain": "sea",
                "domain": "sea",
                "theater": "sea",
            },
        ]
        terrain: dict = {}
        resources: dict = {}
        economy: dict = {}
        stats = backfill_layers(provinces, terrain, resources, economy)
        self.assertEqual(stats["terrain_added"], 3)
        self.assertIn("10", terrain)
        self.assertIn("90001", terrain)
        self.assertTrue(entry_nonempty_resources(resources["90001"]))
        self.assertTrue(entry_nonempty_economy(economy["90001"]))
        # Sea densify not required for resources; hot land only
        g = layer_gates(provinces, terrain, resources, economy)
        self.assertTrue(g["terrain_full_coverage"])
        self.assertEqual(g["hot_missing_resources"], 0)
        self.assertEqual(g["hot_missing_economy"], 0)

    def test_shipped_world_layers(self) -> None:
        """Drive shipped layer JSON files against real province ids."""
        base = json.loads((WF / "provinces_base.json").read_text())["provinces"]
        terrain = json.loads((WF / "province_terrain_layer.json").read_text())["provinces"]
        resources = json.loads((WF / "province_resources_layer.json").read_text())["provinces"]
        economy = json.loads((WF / "province_economy_layer.json").read_text())["provinces"]
        g = layer_gates(base, terrain, resources, economy)
        self.assertTrue(g["terrain_full_coverage"], msg=g)
        self.assertEqual(g["terrain_count"], g["province_count"], msg=g)
        self.assertEqual(g["hot_missing_resources"], 0, msg=g)
        self.assertEqual(g["hot_missing_economy"], 0, msg=g)
        self.assertTrue(g["sea_share_ok"], msg=g)
        self.assertGreaterEqual(g["province_count"], 2200)
        # Also exercise real entrypoint dry-run
        stats = layers_run(WF, write=False)
        self.assertTrue(stats["gates"]["terrain_full_coverage"])
        self.assertEqual(stats["gates"]["hot_missing_resources"], 0)


class TestStartingTechWorldFull(unittest.TestCase):
    def _tree_tech_ids(self) -> set:
        """IDs actually loaded into TechnologyManager.technology_nodes (trees only)."""
        ids: set = set()
        for path in (ROOT / "data" / "technology" / "trees").glob("*.json"):
            data = json.loads(path.read_text())

            def walk(obj: object) -> None:
                if isinstance(obj, dict):
                    if "id" in obj:
                        ids.add(str(obj["id"]))
                    for v in obj.values():
                        walk(v)
                elif isinstance(obj, list):
                    for x in obj:
                        walk(x)

            walk(data)
        return ids

    def test_technology_manager_aliases_world_full_to_1936(self) -> None:
        lm = (ROOT / "scripts" / "technology" / "TechnologyManager.gd").read_text(encoding="utf-8")
        # Real resolution path must remap world_full → 1936 pack file
        self.assertIn("world_full", lm)
        self.assertIn('sn = "1936"', lm)
        # Pack file exists and has multi-tech substance for majors
        pack = json.loads((ROOT / "data" / "technology" / "starting" / "1936.json").read_text())
        self.assertEqual(pack.get("scenario"), "1936")
        defaults = pack.get("defaults") or {}
        completed = list(defaults.get("completed") or [])
        self.assertGreaterEqual(len(completed), 4)
        self.assertNotEqual(completed, ["basic_machine_tools"])
        tree_ids = self._tree_tech_ids()
        for tid in completed:
            self.assertIn(tid, tree_ids, msg=f"default tech {tid} not in technology trees")
        countries = pack.get("countries") or {}
        for major in ("GER", "USA"):
            self.assertIn(major, countries)
            maj_done = list((countries[major] or {}).get("completed") or [])
            merged = list(dict.fromkeys(completed + maj_done))
            self.assertGreaterEqual(len(merged), 6, msg=f"{major} merged starting techs too thin: {merged}")
            for tid in maj_done:
                self.assertIn(tid, tree_ids, msg=f"{major} tech {tid} not in technology trees")

    def test_resolve_starting_pack_path_mirrors_game(self) -> None:
        """Pure mirror of TechnologyManager._load_starting_pack alias rules + file load."""
        starting = ROOT / "data" / "technology" / "starting"

        def load_pack(scenario_name: str) -> dict:
            sn = scenario_name.strip()
            if sn in ("phase1_europe_test", "world_full", "grand_theater"):
                sn = "1936"
            path = starting / f"{sn}.json"
            if not path.exists():
                return {}
            return json.loads(path.read_text())

        empty_missing = load_pack("no_such_scenario_xyz")
        self.assertEqual(empty_missing, {})
        wf = load_pack("world_full")
        s1936 = load_pack("1936")
        self.assertEqual(wf.get("scenario"), "1936")
        self.assertEqual(wf.get("defaults"), s1936.get("defaults"))
        self.assertEqual(wf.get("countries"), s1936.get("countries"))
        defaults = list((wf.get("defaults") or {}).get("completed") or [])
        ger = list((wf.get("countries") or {}).get("GER", {}).get("completed") or [])
        merged_ger = list(dict.fromkeys(defaults + ger))
        self.assertGreaterEqual(len(merged_ger), 6)
        # Minimal-defaults path only when pack empty — world_full must not be empty
        self.assertTrue(wf)
        self.assertNotEqual(defaults, ["basic_machine_tools"])
        tree_ids = self._tree_tech_ids()
        for tid in merged_ger:
            self.assertIn(tid, tree_ids)


if __name__ == "__main__":
    unittest.main(verbosity=2)
