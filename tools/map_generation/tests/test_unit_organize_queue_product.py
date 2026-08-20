#!/usr/bin/env python3
"""Gate: organize queue — existing vs new, train/refit, priority, core deploy."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_organize_queue_product import (  # noqa: E402
    EXISTING_TRAIN_DAYS,
    NEW_TRAIN_DAYS,
    REFIT_DAYS,
    apply_organize_save,
    build_unit_organize_queue_product,
    equip_share,
    pack_organize_save,
    plan_organize,
    split_equip_budget,
    tick_stats,
    training_label,
    unit_organize_queue_integrity,
)


class TestUnitOrganizeQueueProduct(unittest.TestCase):
    def test_math(self) -> None:
        n = plan_organize(mode="new", count=3, deploy_pid=710173, cores=[710173])
        self.assertTrue(n.get("ok"), msg=n)
        self.assertEqual(int(n["count"]), 3)
        self.assertEqual(int(n["train_days"]), NEW_TRAIN_DAYS)
        ex = plan_organize(
            mode="existing", existing_template=True, deploy_pid=710173, cores=[710173]
        )
        self.assertEqual(int(ex["train_days"]), EXISTING_TRAIN_DAYS)
        rf = plan_organize(mode="refit", deploy_pid=710173, cores=[710173])
        self.assertEqual(int(rf["train_days"]), REFIT_DAYS)
        bad = plan_organize(mode="new", deploy_pid=9, cores=[710173])
        self.assertFalse(bad.get("ok"))
        job = dict(n["jobs"][0])
        done = tick_stats(job, days=float(NEW_TRAIN_DAYS))
        self.assertTrue(done.get("combat_ready"))
        sp = split_equip_budget(10, 8, 8, "field")
        self.assertEqual(sp["field"], 8.0)
        self.assertEqual(sp["new"], 2.0)
        self.assertEqual(equip_share(is_training=True, priority="field"), 0.35)
        self.assertEqual(equip_share(is_training=True, priority="new"), 1.0)
        self.assertIn("Training 5/14d", training_label(mode="new", progress=5, train_days=14))
        packed = pack_organize_save(
            priority="new",
            formations=[{"formation_id": "x", "is_training": True, "training_progress": 2}],
        )
        forms = {"x": {"formation_id": "x"}}
        applied = apply_organize_save(packed, forms)
        self.assertEqual(int(applied["restored"]), 1)
        self.assertTrue(forms["x"]["is_training"])

    def test_product_wiring(self) -> None:
        p = build_unit_organize_queue_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        i = unit_organize_queue_integrity()
        self.assertTrue(i.get("ok"), msg=i)


if __name__ == "__main__":
    unittest.main()
