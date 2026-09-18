#!/usr/bin/env python3
"""Gates: 2026 roster wires portraits only for on-disk PNGs (24 leader_ids)."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ROSTER = ROOT / "data" / "leaders" / "historical_leaders_2026.json"
PORTRAIT_DIR = ROOT / "assets" / "graphics" / "portraits" / "leaders"

# On-disk 2026 PNGs that were unwired; JSON portrait must match <id>.png.
ON_DISK_2026_IDS = (
    "aus_air_2026",
    "aus_mitchell_2026",
    "aus_navy_2026",
    "bra_air_2026",
    "bra_navy_2026",
    "bra_silva_2026",
    "can_air_2026",
    "can_fraser_2026",
    "can_navy_2026",
    "ind_air_2026",
    "ind_navy_2026",
    "ind_sharma_2026",
    "isr_air_2026",
    "isr_cohen_2026",
    "isr_navy_2026",
    "kor_air_2026",
    "kor_navy_2026",
    "kor_park_2026",
    "mex_air_2026",
    "mex_herrera_2026",
    "mex_navy_2026",
    "pol_air_2026",
    "pol_kowalski_2026",
    "pol_navy_2026",
)


def _portrait_field(entry: dict) -> str:
    return str(entry.get("portrait_path") or entry.get("portrait") or "").strip()


def _res_to_disk(res_path: str) -> Path:
    if not res_path.startswith("res://"):
        return Path()
    return ROOT / res_path[len("res://") :]


class TestHistoricalLeaders2026OnDiskPortraits(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.roster = json.loads(ROSTER.read_text(encoding="utf-8"))
        cls.by_id = {
            str(e.get("leader_id")): e
            for e in (cls.roster.get("leaders") or [])
            if e.get("leader_id")
        }

    def test_twenty_four_ids_have_existing_portrait_png(self) -> None:
        self.assertEqual(len(ON_DISK_2026_IDS), 24)
        missing = []
        for lid in ON_DISK_2026_IDS:
            entry = self.by_id.get(lid)
            if not entry:
                missing.append(f"{lid}: not in 2026 roster")
                continue
            portrait = _portrait_field(entry)
            if not portrait:
                missing.append(f"{lid}: empty portrait")
                continue
            expected = f"res://assets/graphics/portraits/leaders/{lid}.png"
            if portrait != expected:
                missing.append(f"{lid}: portrait {portrait!r} != {expected!r}")
                continue
            disk = _res_to_disk(portrait)
            if not disk.is_file():
                missing.append(f"{lid}: missing file {disk}")
        self.assertFalse(missing, msg="\n".join(missing))

    def test_2026_roster_has_zero_refs_to_missing_portrait_files(self) -> None:
        bad = []
        for lid, entry in self.by_id.items():
            portrait = _portrait_field(entry)
            if not portrait:
                continue
            disk = _res_to_disk(portrait)
            if not disk.is_file():
                bad.append(f"{lid}: {portrait} -> {disk}")
        self.assertEqual(bad, [], msg="portrait refs missing on disk:\n" + "\n".join(bad))

    def test_on_disk_pngs_exist_for_fixture_ids(self) -> None:
        missing = [lid for lid in ON_DISK_2026_IDS if not (PORTRAIT_DIR / f"{lid}.png").is_file()]
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
