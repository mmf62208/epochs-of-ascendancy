#!/usr/bin/env python3
"""M0 gates: strategic_regions.json matches live hierarchy membership (31, multi=0)."""
from __future__ import annotations

import json
import unittest
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "data" / "provinces_world_accurate"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate missing")
class TestStrategicRegionsMembershipM0(unittest.TestCase):
    def test_file_matches_membership_31_zero_multi(self) -> None:
        mem = json.loads((D / "hierarchy_membership_1936.json").read_text(encoding="utf-8"))
        p2r = mem.get("province_to_region") or {}
        mem_ids = {int(v) for v in p2r.values() if int(v or 0) > 0}
        by_mem: dict = defaultdict(list)
        for pid_s, rid in p2r.items():
            by_mem[int(rid)].append(int(pid_s))

        sr = json.loads((D / "strategic_regions.json").read_text(encoding="utf-8"))
        rows = sr.get("regions") or []
        self.assertEqual(len(rows), 31)
        names = [str(r.get("name") or "") for r in rows]
        self.assertEqual(len(set(names)), 31)
        file_ids = {int(r["id"]) for r in rows}
        self.assertEqual(file_ids, mem_ids)

        seen = set()
        multi = 0
        for r in rows:
            pids = [int(x) for x in (r.get("province_ids") or [])]
            self.assertGreater(len(pids), 0, msg="empty region %s" % r.get("name"))
            for pid in pids:
                if pid in seen:
                    multi += 1
                seen.add(pid)
            # Agree with membership for this id
            rid = int(r["id"])
            self.assertEqual(set(pids), set(by_mem[rid]), msg="region %d list drift" % rid)
        self.assertEqual(multi, 0)
        # Matches live board size (post US merge ~5670; pre-merge was 8761)
        base_n = len(
            json.loads((D / "provinces_base.json").read_text(encoding="utf-8")).get("provinces")
            or []
        )
        self.assertEqual(len(seen), base_n)
        # Post US + full RoW sparse merge ~3520 (was ~5670 / ~8761)
        self.assertGreaterEqual(base_n, 3000)

        na = next(r for r in rows if int(r["id"]) == 2)
        self.assertEqual(str(na.get("name")), "North America")
        self.assertGreaterEqual(len(na.get("province_ids") or []), 70)
        self.assertEqual(len(na.get("province_ids") or []), len(by_mem[2]))

    def test_no_us_census_quadruple_names(self) -> None:
        rows = json.loads((D / "strategic_regions.json").read_text(encoding="utf-8")).get(
            "regions"
        ) or []
        from collections import Counter

        c = Counter(str(r.get("name") or "") for r in rows)
        for name, n in c.items():
            self.assertEqual(n, 1, msg="%s appears %d times" % (name, n))


if __name__ == "__main__":
    unittest.main()
