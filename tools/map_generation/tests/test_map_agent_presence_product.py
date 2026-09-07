#!/usr/bin/env python3
"""Gate: on-mission player agents get hang-safe map tokens."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_agent_presence_product import (  # noqa: E402
    MAX_TOKENS,
    agent_presence_marker,
    build_map_agent_presence_product,
    cap_agent_tokens,
)

LAYER = ROOT / "scripts" / "map" / "AgentPresenceLayer.gd"


class TestMapAgentPresenceProduct(unittest.TestCase):
    def test_on_mission_only(self) -> None:
        live = agent_presence_marker(pid=710739, on_mission=True, player=True)
        self.assertTrue(live.get("ok"), msg=live)
        idle = agent_presence_marker(pid=710739, on_mission=False, player=True)
        self.assertFalse(idle.get("ok"))
        foe = agent_presence_marker(pid=710739, on_mission=True, player=False)
        self.assertFalse(foe.get("ok"))

    def test_cap_eight(self) -> None:
        rows = [{"pid": 710000 + i, "on_mission": True} for i in range(20)]
        self.assertEqual(len(cap_agent_tokens(rows)), MAX_TOKENS)

    def test_product_integrity(self) -> None:
        p = build_map_agent_presence_product()
        self.assertTrue(p.get("ok"), msg=p)
        lyr = LAYER.read_text(encoding="utf-8")
        self.assertIn("func _draw", lyr)
        self.assertNotIn("ColorRect", lyr)
        self.assertNotIn("Control", lyr)
        self.assertNotIn("set_process(true)", lyr)


if __name__ == "__main__":
    unittest.main()
