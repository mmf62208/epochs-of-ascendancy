#!/usr/bin/env python3
"""Pure save-slot list helpers for player-facing Save Manager UI.

Mirrors the contract of SaveLoadManager.list_saves / list_slots_for_ui:
fixed browser slots + discovered files, empty vs occupied distinguishable.
"""

from __future__ import annotations

from typing import Any, Dict, Iterable, List, Optional, Sequence

# Default browser slots shown even when empty (player can save into them).
DEFAULT_BROWSER_SLOTS: List[str] = [
    "quicksave",
    "autosave",
    "slot1",
    "slot2",
    "slot3",
    "slot4",
    "slot5",
]


def format_slot_row(
    slot: str,
    occupied: bool,
    metadata: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """One UI row: label + empty/occupied status + optional metadata summary."""
    name = (slot or "").strip() or "unnamed"
    meta = metadata or {}
    ts = str(meta.get("timestamp", meta.get("last_played", "")) or "")
    scenario = str(meta.get("scenario_id", "") or "").strip()
    player = str(meta.get("player_tag", "") or "").strip().upper()
    if occupied:
        bits: List[str] = [name]
        if scenario:
            bits.append(scenario)
        if player:
            bits.append(player)
        if ts:
            bits.append(ts[:16])
        label = " · ".join(bits)
        status = "occupied"
    else:
        label = "%s · empty" % name
        status = "empty"
    return {
        "slot": name,
        "occupied": bool(occupied),
        "status": status,
        "label": label,
        "metadata": dict(meta),
        "can_load": bool(occupied),
        "can_save": True,
        "api_save": "save_game_detailed",
        "api_load": "load_game_detailed",
    }


def build_save_slot_list(
    occupied_entries: Sequence[Dict[str, Any]],
    fixed_slots: Optional[Sequence[str]] = None,
) -> List[Dict[str, Any]]:
    """Merge fixed browser slots with list_saves()-shaped entries.

    occupied_entries: [{slot, metadata?, path?}, ...] from disk.
    Empty fixed slots appear as occupied=False so UI can distinguish.
    """
    fixed = list(fixed_slots) if fixed_slots is not None else list(DEFAULT_BROWSER_SLOTS)
    by_slot: Dict[str, Dict[str, Any]] = {}
    for e in occupied_entries or []:
        if not isinstance(e, dict):
            continue
        slot = str(e.get("slot", "")).strip()
        if not slot:
            continue
        meta = e.get("metadata") if isinstance(e.get("metadata"), dict) else {}
        by_slot[slot] = {
            "slot": slot,
            "path": str(e.get("path", "")),
            "metadata": meta,
            "occupied": True,
        }

    rows: List[Dict[str, Any]] = []
    seen: set = set()
    for slot in fixed:
        s = str(slot).strip()
        if not s or s in seen:
            continue
        seen.add(s)
        if s in by_slot:
            ent = by_slot[s]
            rows.append(format_slot_row(s, True, ent.get("metadata") or {}))
        else:
            rows.append(format_slot_row(s, False, {}))

    # Extra discovered slots not in fixed list (newest first if timestamps present)
    extras = [by_slot[k] for k in by_slot if k not in seen]

    def _ts(ent: Dict[str, Any]) -> str:
        m = ent.get("metadata") or {}
        return str(m.get("timestamp", m.get("last_played", "")))

    extras.sort(key=_ts, reverse=True)
    for ent in extras:
        rows.append(format_slot_row(str(ent["slot"]), True, ent.get("metadata") or {}))
    return rows


def slot_list_has_empty_and_occupied(rows: Sequence[Dict[str, Any]]) -> Dict[str, bool]:
    return {
        "has_empty": any(not bool(r.get("occupied")) for r in rows),
        "has_occupied": any(bool(r.get("occupied")) for r in rows),
        "count": len(rows),
    }
