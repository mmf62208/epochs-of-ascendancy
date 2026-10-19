#!/usr/bin/env python3
"""Write the committed v1-format day-0 save used by SAVE-RELOAD-1 tests.

Reproducible: pinned timestamps, no host paths, no live gather. The file is a
valid v1 ``<slot>.json`` body (save_version 1) that SaveFormat.migrate /
validate accept. Tests load it from res://tests/fixtures/save_reload_1/.

Regenerate:

    python3 tools/generate_sr1_v1_fixture.py

Optional Godot path (same bytes; boots the campaign and then writes this slim
shape, not a host dump):

    EOA_CAMPAIGN_LOOP=1 EOA_SCENARIO_EARLY_WARS=0 EOA_CALENDAR_AUTOSAVE=0 \\
      tools/run_godot.sh --headless --path . -s res://scripts/core/SaveReload1V1FixtureExport.gd
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests" / "fixtures" / "save_reload_1" / "sr1test_v1_day0.json"


def v1_day0() -> dict:
    return {
        "save_version": 1,
        "metadata": {
            "timestamp": "1936-01-01T00:00:00",
            "scenario_id": "1936",
            "player_tag": "GER",
            "nation_name": "Germany",
            "game_date": "1936-01-01 00:00",
            "play_time_seconds": 0,
            "game_version": "0.2-dev",
            "last_played": "1936-01-01T00:00:00",
        },
        "time": {
            "current_date": {"year": 1936, "month": 1, "day": 1},
            "scenario_start_date": "1936-01-01",
            "paused": True,
            "time_scale": 1.0,
            "total_days_elapsed": 0,
            "current_hour": 0,
            "run_seed": 193601,
            "accumulated_days": 0.0,
            "accumulated_hours": 0.0,
        },
        "map": {
            "provinces": [
                {
                    "id": 710173,
                    "owner_tag": "GER",
                    "controller_tag": "GER",
                    "development_level": 3,
                    "infrastructure": 4,
                    "settlement_level": 0,
                    "built_road_neighbors": [],
                    "built_rail_neighbors": [],
                }
            ]
        },
        "land_war": {
            "version": 1,
            "open_battles": [],
            "marches": {},
            "next_seq": 1,
            "last_aar": {},
        },
        "infrastructure_projects": {"version": 1, "active_projects": {}},
        "game_data": {
            "campaign_wars": {
                "wars": {},
                "truces": {},
                "log": [],
                "justifies": {},
                "booted": True,
            },
            "campaign_capitulation": {},
            "campaign_end": {},
            "peace_settlements": [],
            "peace_settlement_count": 0,
            "peace_last_settlement": {},
            "war_goals": {},
            "war_goal_tick_count": 0,
        },
    }


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(v1_day0(), indent=2, sort_keys=True) + "\n"
    OUT.write_text(text, encoding="utf-8")
    print("wrote %s (%d bytes)" % (OUT, len(text.encode("utf-8"))))


if __name__ == "__main__":
    main()
