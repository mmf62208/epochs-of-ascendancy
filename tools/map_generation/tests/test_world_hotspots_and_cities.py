#!/usr/bin/env python3
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from densify_world_hotspots import apply_hotspots, run_on_dir as hotspot_run  # noqa: E402
from seed_world_city_layer import match_hub, seed_cities, run_on_dir as city_run  # noqa: E402


class TestHotspots(unittest.TestCase):
    def test_apply_adds_named_hotspots(self) -> None:
        base = [{"id": 1, "name": "Seed", "domain": "land"}]
        geom = [{"id": 1, "points": [[100.0, 100.0], [110.0, 100.0], [110.0, 110.0], [100.0, 110.0]]}]
        nb, ng, n = apply_hotspots(base, geom, start_id=90000)
        self.assertGreaterEqual(n, 200)
        self.assertEqual(len(nb), len(ng))
        self.assertTrue(any("China" in p["name"] or "India" in p["name"] or "USA" in p["name"] for p in nb))
        self.assertTrue(
            any("Africa" in p["name"] or "Pacific" in p["name"] or "SE Asia" in p["name"] for p in nb),
            msg="wave-2 under-served theater hubs must be present",
        )
        self.assertTrue(all(p.get("hotspot_densify") for p in nb))

    def test_shipped_world_has_hotspots(self) -> None:
        path = ROOT / "data" / "provinces_world_full" / "provinces_base.json"
        data = json.loads(path.read_text())
        hot = [p for p in data["provinces"] if p.get("hotspot_densify")]
        self.assertGreaterEqual(len(hot), 800)
        self.assertGreaterEqual(len(data["provinces"]), 2200)
        theaters = {p.get("theater") for p in hot}
        # At least two non-Europe under-served theaters represented in hotspot set
        underserved = theaters & {"africa", "south_america", "pacific", "oceania", "central_asia"}
        self.assertGreaterEqual(len(underserved), 2, msg=str(theaters))


class TestCities(unittest.TestCase):
    def test_match_hub(self) -> None:
        self.assertIsNotNone(match_hub("New York Metro"))
        self.assertEqual(match_hub("Totally Random Nowhere"), None)

    def test_seed_cities_pure(self) -> None:
        base = [
            {"id": 1, "name": "London Core"},
            {"id": 2, "name": "Empty Fields"},
        ]
        geom = [
            {"id": 1, "points": [[10, 10], [20, 10], [20, 20]], "label_anchor": [15, 15]},
            {"id": 2, "points": [[30, 30], [40, 30], [40, 40]]},
        ]
        out = seed_cities(base, geom, {})
        self.assertGreaterEqual(out["seeded"], 1)
        self.assertTrue(out["provinces"]["1"]["cities"])
        c0 = out["provinces"]["1"]["cities"][0]
        self.assertAlmostEqual(float(c0["x"]), 15.0, places=3)
        self.assertAlmostEqual(float(c0["y"]), 15.0, places=3)

    def test_repairs_legacy_far_cities(self) -> None:
        """Europe-local leftovers (0,0 or wrong hub name) must snap to province anchor."""
        base = [{"id": 6, "name": "Reykjavik"}]
        geom = [
            {
                "id": 6,
                "points": [[3900, 1370], [3910, 1370], [3910, 1380], [3900, 1380]],
                "label_anchor": [3905, 1375],
            }
        ]
        existing = {
            "6": {
                "cities": [
                    {"name": "Washington DC", "x": 0.0, "y": 0.0, "level": 3}
                ]
            }
        }
        out = seed_cities(base, geom, existing)
        cities = out["provinces"]["6"]["cities"]
        self.assertEqual(len(cities), 1)
        self.assertAlmostEqual(float(cities[0]["x"]), 3905.0, places=3)
        self.assertAlmostEqual(float(cities[0]["y"]), 1375.0, places=3)
        # Name must relate to province (Reykjavik), not stuck Washington DC
        self.assertIn("reykjavik", str(cities[0]["name"]).lower())

    def test_shipped_city_layer(self) -> None:
        stats = city_run(ROOT / "data" / "provinces_world_full", write=False)
        self.assertGreaterEqual(stats["nonempty_cities"], 40)
        self.assertEqual(stats.get("cities_far_from_anchor", 0), 0)

    def test_shipped_cities_near_anchors(self) -> None:
        import math

        base = json.loads(
            (ROOT / "data" / "provinces_world_full" / "provinces_base.json").read_text()
        )["provinces"]
        geom = {
            int(g["id"]): g
            for g in json.loads(
                (ROOT / "data" / "provinces_world_full" / "provinces_geometry.json").read_text()
            )["provinces"]
        }
        city = json.loads(
            (ROOT / "data" / "provinces_world_full" / "province_city_layer.json").read_text()
        )["provinces"]
        far = []
        for p in base:
            sid = str(p["id"])
            cities = (city.get(sid) or {}).get("cities") or []
            if not cities:
                continue
            g = geom[int(sid)]
            if g.get("label_anchor") and len(g["label_anchor"]) >= 2:
                ax, ay = float(g["label_anchor"][0]), float(g["label_anchor"][1])
            else:
                pts = g["points"]
                ax = sum(float(x[0]) for x in pts) / len(pts)
                ay = sum(float(x[1]) for x in pts) / len(pts)
            for ci in cities:
                d = math.hypot(float(ci["x"]) - ax, float(ci["y"]) - ay)
                if d > 500:
                    far.append((sid, p["name"], ci.get("name"), d))
        self.assertEqual(far, [], msg=f"cities far from anchors: {far[:5]}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
