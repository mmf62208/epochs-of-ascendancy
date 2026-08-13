"""Resolve which province data dir is the play board (operator clarity pilot).

world_full is the default F5 play theater; full_europe / grand_theater / legacy
840 are secondary. Pure helper for docs, CI, and ScenarioLoader operator notes.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

DEFAULT_PLAY_DIR = "provinces_world_full"
KNOWN_DIRS = (
    "provinces_world_full",
    "provinces_grand_theater",
    "provinces_full_europe",
    "provinces_phase1_test",
    "provinces",
)


def resolve_play_data_dir(
    scenario_id: str = "",
    *,
    explicit_dir: str = "",
    env_dir: str = "",
) -> Dict[str, Any]:
    """Return the authoritative play data directory name.

    Priority: explicit_dir → env_dir → scenario map → default world_full.
    Never invents unknown dirs without marking secondary.
    """
    scenario = str(scenario_id or "").strip().lower()
    explicit = str(explicit_dir or "").strip().replace("\\", "/").rstrip("/")
    envd = str(env_dir or "").strip().replace("\\", "/").rstrip("/")

    # Normalize paths to basenames
    if "/" in explicit:
        explicit = explicit.split("/")[-1]
    if "/" in envd:
        envd = envd.split("/")[-1]

    chosen = ""
    source = "default"
    if explicit:
        chosen = explicit
        source = "explicit"
    elif envd:
        chosen = envd
        source = "env"
    elif scenario in ("world_full", "world", "full_world"):
        chosen = "provinces_world_full"
        source = "scenario"
    elif scenario in ("grand_theater", "grand"):
        chosen = "provinces_grand_theater"
        source = "scenario"
    elif scenario in ("full_europe", "europe", "phase1_europe"):
        chosen = "provinces_full_europe"
        source = "scenario"
    elif scenario in ("phase1", "phase1_test"):
        chosen = "provinces_phase1_test"
        source = "scenario"
    else:
        chosen = DEFAULT_PLAY_DIR
        source = "default"

    is_default_play = chosen == DEFAULT_PLAY_DIR
    is_legacy = chosen in ("provinces", "provinces_phase1_test")
    known = chosen in KNOWN_DIRS
    warning = ""
    if is_legacy:
        warning = "legacy/test data dir — not default world_full play board"
    elif not is_default_play and known:
        warning = "secondary theater — default F5 play is provinces_world_full"
    elif not known:
        warning = "unknown data dir — verify ScenarioLoader path"

    return {
        "data_dir": chosen,
        "source": source,
        "is_default_play": is_default_play,
        "is_legacy": is_legacy,
        "known": known,
        "scenario_id": scenario,
        "warning": warning,
        "summary": (
            "play data_dir=%s (via %s)%s"
            % (chosen, source, (" · " + warning) if warning else "")
        ),
    }


def list_secondary_data_dirs() -> List[str]:
    return [d for d in KNOWN_DIRS if d != DEFAULT_PLAY_DIR]
