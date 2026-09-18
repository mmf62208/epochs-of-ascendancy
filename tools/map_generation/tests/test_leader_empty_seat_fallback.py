#!/usr/bin/env python3
"""Empty/missing/non-res:// leader portraits show empty-seat art; TextureRect stays visible."""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DETAIL = ROOT / "scripts" / "ui" / "LeaderDetailScreen.gd"
ASSIGN = ROOT / "scripts" / "ui" / "LeaderAssignmentScreen.gd"
EMPTY_SEAT = "res://assets/graphics/ui/leader_empty_seat.png"
EMPTY_SEAT_64 = "res://assets/graphics/ui/leader_empty_seat_64.png"
SEAT_CHECK = 'is_empty() or not {var}.begins_with("res://") or not ResourceLoader.exists({var})'


def portrait_or_seat(path: str, seat: str, exists=None) -> str:
    p = path.strip()
    if not p or not p.startswith("res://") or (exists is not None and not exists(p)):
        return seat
    return p


class TestLeaderEmptySeatFallback(unittest.TestCase):
    def test_pngs_exist(self) -> None:
        for rel in (
            "assets/graphics/ui/leader_empty_seat.png",
            "assets/graphics/ui/leader_empty_seat_64.png",
        ):
            self.assertTrue((ROOT / rel).is_file(), msg=rel)

    def test_empty_and_evil_paths_load_empty_seat(self) -> None:
        self.assertEqual(portrait_or_seat("", EMPTY_SEAT), EMPTY_SEAT)
        self.assertEqual(portrait_or_seat("   ", EMPTY_SEAT), EMPTY_SEAT)
        self.assertEqual(portrait_or_seat("http://evil", EMPTY_SEAT), EMPTY_SEAT)
        self.assertEqual(portrait_or_seat("http://evil", EMPTY_SEAT_64), EMPTY_SEAT_64)
        self.assertEqual(
            portrait_or_seat("res://missing.png", EMPTY_SEAT, exists=lambda _p: False),
            EMPTY_SEAT,
        )

    def test_existing_res_path_kept(self) -> None:
        kept = "res://assets/graphics/portraits/leaders/guderian.png"
        self.assertEqual(portrait_or_seat(kept, EMPTY_SEAT, exists=lambda _p: True), kept)

    def test_one_const_per_screen_and_inline_check(self) -> None:
        detail = DETAIL.read_text(encoding="utf-8")
        assign = ASSIGN.read_text(encoding="utf-8")
        self.assertIn(f'const EMPTY_SEAT := "{EMPTY_SEAT}"', detail)
        self.assertNotIn("EMPTY_SEAT_64", detail)
        self.assertIn(f'const EMPTY_SEAT_64 := "{EMPTY_SEAT_64}"', assign)
        self.assertNotIn("const EMPTY_SEAT :=", assign)
        self.assertNotIn("func _portrait_or_seat", detail)
        self.assertNotIn("func _portrait_or_seat", assign)
        self.assertIn(SEAT_CHECK.format(var="path"), detail)
        self.assertIn(SEAT_CHECK.format(var="ppath"), assign)
        self.assertIn("if tex == null and path != EMPTY_SEAT:", detail)
        self.assertIn("tex = load(EMPTY_SEAT) as Texture2D", detail)
        self.assertIn("if tex == null and ppath != EMPTY_SEAT_64:", assign)
        self.assertIn("tex = load(EMPTY_SEAT_64) as Texture2D", assign)

    def test_texture_rect_never_hidden(self) -> None:
        detail = DETAIL.read_text(encoding="utf-8")
        assign = ASSIGN.read_text(encoding="utf-8")
        self.assertNotIn("portrait_rect.visible = false", detail)
        self.assertIn("portrait_rect.visible = true", detail)
        self.assertNotIn("p_rect.visible = p_rect.texture != null", assign)
        self.assertIn("p_rect.visible = true", assign)

    def test_json_wiring_not_invented_in_ui(self) -> None:
        gen = (ROOT / "scripts" / "leaders" / "LeaderGenerator.gd").read_text(encoding="utf-8")
        self.assertIn(
            'leader.portrait_path = str(leader_data.get("portrait", leader_data.get("portrait_path", "")))',
            gen,
        )
        self.assertNotIn("EMPTY_SEAT", gen)


if __name__ == "__main__":
    unittest.main(verbosity=2)
