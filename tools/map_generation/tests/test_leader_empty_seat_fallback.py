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
HELPER = (
    'func _portrait_or_seat(path: String, seat: String) -> String:\n'
    '\tvar p := path.strip_edges()\n'
    '\tif p.is_empty() or not p.begins_with("res://") or not ResourceLoader.exists(p):\n'
    '\t\treturn seat\n'
    '\treturn p'
)


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

    def test_helper_and_constants_in_screens(self) -> None:
        for path in (DETAIL, ASSIGN):
            src = path.read_text(encoding="utf-8")
            self.assertIn(f'const EMPTY_SEAT := "{EMPTY_SEAT}"', src, msg=path.name)
            self.assertIn(f'const EMPTY_SEAT_64 := "{EMPTY_SEAT_64}"', src, msg=path.name)
            self.assertIn(HELPER, src, msg=path.name)
            self.assertIn("_portrait_or_seat(", src, msg=path.name)

    def test_texture_rect_never_hidden(self) -> None:
        detail = DETAIL.read_text(encoding="utf-8")
        assign = ASSIGN.read_text(encoding="utf-8")
        self.assertNotIn("portrait_rect.visible = false", detail)
        self.assertIn("portrait_rect.visible = true", detail)
        self.assertNotIn("p_rect.visible = p_rect.texture != null", assign)
        self.assertIn("p_rect.visible = true", assign)
        self.assertIn("_portrait_or_seat(str(current_leader.portrait_path), EMPTY_SEAT)", detail)
        self.assertIn("_portrait_or_seat(str(summary.get(\"portrait_path\", \"\")), EMPTY_SEAT_64)", assign)

    def test_json_wiring_not_invented_in_ui(self) -> None:
        gen = (ROOT / "scripts" / "leaders" / "LeaderGenerator.gd").read_text(encoding="utf-8")
        self.assertIn(
            'leader.portrait_path = str(leader_data.get("portrait", leader_data.get("portrait_path", "")))',
            gen,
        )
        self.assertNotIn("EMPTY_SEAT", gen)


if __name__ == "__main__":
    unittest.main(verbosity=2)
