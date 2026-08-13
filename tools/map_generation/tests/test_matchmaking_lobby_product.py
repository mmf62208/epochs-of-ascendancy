"""Pure hooks for matchmaking_lobby."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from matchmaking_lobby_product import build_matchmaking_lobby_primary_command_product, primary_command_dead_audit

class TestMatchmakingLobby(unittest.TestCase):
    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_matchmaking_lobby_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_matchmaking_lobby_primary_live", gd)
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("matchmaking_lobby_primary_live=1", sl)
        # Real shipped symbols
        if "matchmaking_lobby" == "space_discovery_ui":
            mgr = (ROOT / "scripts/space/SpaceLayerManager.gd").read_text(encoding="utf-8")
            self.assertIn("func list_unresolved_discoveries", mgr)
            ui = (ROOT / "scripts/ui/SpaceLayerBoardView.gd").read_text(encoding="utf-8")
            self.assertIn("func apply_discovery_choice_from_board", ui)
        if "matchmaking_lobby" == "matchmaking_lobby":
            ui = (ROOT / "scripts/ui/MatchmakingLobbyView.gd").read_text(encoding="utf-8")
            self.assertIn("func apply_lobby_match_path", ui)

if __name__ == "__main__":
    unittest.main()
