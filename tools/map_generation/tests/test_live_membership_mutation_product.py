#!/usr/bin/env python3
"""Gates: live hierarchy membership mutation (reassign/create/transfer) + agency."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from live_membership_mutation_product import (  # noqa
    agency_policy_ok,
    exercise_world_full_mutation,
    exercise_cross_region_transfer,
    find_cross_region_state_pair,
    live_membership_integrity,
    load_membership_snapshot,
    snapshot_to_runtime,
    reassign_province_membership,
    transfer_state_membership,
    get_hierarchy,
    peace_annex_membership,
    membership_save_roundtrip,
)


class TestLiveMembershipMutation(unittest.TestCase):
    def test_integrity(self):
        g = live_membership_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_reassign_changes_state_on_real_ids(self):
        snap = load_membership_snapshot(ROOT / "data" / "provinces_world_full", 1936)
        self.assertEqual(snap.get("mode"), "full")
        rt = snapshot_to_runtime(snap)
        ex = exercise_world_full_mutation(1936)
        self.assertTrue(ex.get("ok"), msg=ex)
        self.assertNotEqual(ex.get("from_state"), ex.get("to_state"))
        self.assertEqual(int(ex["after_reassign"]["state_id"]), int(ex["to_state"]))

    def test_agency_policy_no_year_tick_reapply(self):
        pol = agency_policy_ok()
        self.assertTrue(pol.get("ok"), msg=pol)
        self.assertTrue(pol.get("time_manager_no_reseed"))
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("membership_reapply_on_year_tick = false", sl)
        self.assertIn("reassign_province_membership", sl)
        self.assertIn("create_state_membership", sl)
        self.assertIn("transfer_state_membership", sl)
        self.assertIn("membership_live_mut=1", sl)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        self.assertIn("reassign_province_membership_live", gd)
        self.assertIn("create_state_membership_live", gd)
        self.assertIn("transfer_state_membership_live", gd)
        self.assertIn("apply_membership_mutation_live", gd)

    def test_create_and_transfer_chain(self):
        snap = load_membership_snapshot(ROOT / "data" / "provinces_world_full", 1936)
        rt = snapshot_to_runtime(snap)
        pid = next(iter(rt["province_state_by_id"].keys()))
        old = get_hierarchy(rt, pid)["state_id"]
        # reassign first to ensure path works
        other = old
        for _p, s in rt["province_state_by_id"].items():
            if int(s) != int(old):
                other = int(s)
                break
        reassign_province_membership(rt, pid, other)
        from live_membership_mutation_product import create_state_membership

        cr = create_state_membership(rt, [pid], "Test Split State")
        self.assertTrue(cr.get("ok"))
        new_sid = int(cr["state_id"])
        self.assertEqual(get_hierarchy(rt, pid)["state_id"], new_sid)
        tr = transfer_state_membership(rt, new_sid, other)
        self.assertTrue(tr.get("ok"))
        self.assertEqual(get_hierarchy(rt, pid)["state_id"], other)

    def test_cross_region_transfer_coherent_region_super(self):
        """Two real world_full states in different regions → after transfer, movers share dest region/super."""
        snap = load_membership_snapshot(ROOT / "data" / "provinces_world_full", 1936)
        rt = snapshot_to_runtime(snap)
        pair = find_cross_region_state_pair(rt)
        self.assertTrue(pair.get("ok"), msg=pair)
        self.assertNotEqual(pair["from_region"], pair["to_region"])
        fs, ts = int(pair["from_state"]), int(pair["to_state"])
        want_rid = int(pair["to_region"])
        want_srid = int(pair["to_super"])
        movers = [pid for pid, sid in rt["province_state_by_id"].items() if int(sid) == fs]
        self.assertGreaterEqual(len(movers), 1)
        # Source region differs from dest
        src_rid = int(rt["province_region_by_id"].get(movers[0], 0))
        self.assertNotEqual(src_rid, want_rid)
        tr = transfer_state_membership(rt, fs, ts)
        self.assertTrue(tr.get("ok"), msg=tr)
        self.assertEqual(int(tr.get("dest_region_id") or 0), want_rid)
        for pid in movers:
            h = get_hierarchy(rt, pid)
            self.assertEqual(int(h["state_id"]), ts, msg=(pid, h))
            self.assertEqual(int(h["region_id"]), want_rid, msg=(pid, h, want_rid))
            if want_srid > 0:
                self.assertEqual(int(h["super_region_id"]), want_srid, msg=(pid, h, want_srid))

    def test_reassign_uses_destination_region_not_source(self):
        snap = load_membership_snapshot(ROOT / "data" / "provinces_world_full", 1936)
        rt = snapshot_to_runtime(snap)
        pair = find_cross_region_state_pair(rt)
        self.assertTrue(pair.get("ok"), msg=pair)
        pid = int(pair["from_province"])
        dest_sid = int(pair["to_state"])
        want_rid = int(pair["to_region"])
        src_rid = int(get_hierarchy(rt, pid)["region_id"])
        self.assertNotEqual(src_rid, want_rid)
        re = reassign_province_membership(rt, pid, dest_sid)
        self.assertTrue(re.get("ok"))
        after = get_hierarchy(rt, pid)
        self.assertEqual(int(after["state_id"]), dest_sid)
        self.assertEqual(int(after["region_id"]), want_rid)
        self.assertEqual(int(re.get("dest_region_id") or 0), want_rid)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_live_membership_mutation_product.py", ci)

    def test_gdscript_infer_excludes_movers(self):
        """Static: transfer/reassign resolve dest region before move / with exclude list."""
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("_infer_region_for_state(to_state_id, moved_pids)", sl)
        self.assertIn("_infer_region_for_state(new_state_id, [province_id])", sl)
        self.assertIn("exclude_pids", sl)

    def test_peace_annex_creates_winner_state(self):
        snap = load_membership_snapshot(ROOT / "data" / "provinces_world_full", 1936)
        rt = snapshot_to_runtime(snap)
        pid = next(iter(rt["province_state_by_id"].keys()))
        pe = peace_annex_membership(rt, pid, "GER")
        self.assertTrue(pe.get("ok"), msg=pe)
        self.assertIn("Occupied Zone", str(pe.get("create", {}).get("state_name", "")))
        self.assertEqual(int(pe["after"]["state_id"]), int(pe["create"]["state_id"]))

    def test_membership_save_roundtrip_after_mutation(self):
        snap = load_membership_snapshot(ROOT / "data" / "provinces_world_full", 1936)
        rt = snapshot_to_runtime(snap)
        pair = find_cross_region_state_pair(rt)
        self.assertTrue(pair.get("ok"))
        pid = int(pair["from_province"])
        reassign_province_membership(rt, pid, int(pair["to_state"]))
        pe = peace_annex_membership(rt, pid, "USA")
        self.assertTrue(pe.get("ok"))
        sr = membership_save_roundtrip(rt)
        self.assertTrue(sr.get("ok"), msg=sr)
        self.assertGreater(int(sr.get("bound") or 0), 100)

    def test_saveload_and_peace_wired_in_game(self):
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        self.assertIn("get_membership_save_data", sl)
        self.assertIn("apply_membership_save_data", sl)
        self.assertIn("hierarchy_membership_live", gd)
        self.assertIn("Occupied Zone", gd)
        self.assertIn("membership_peace_saveload=1", sl)


if __name__ == "__main__":
    unittest.main(verbosity=2)
