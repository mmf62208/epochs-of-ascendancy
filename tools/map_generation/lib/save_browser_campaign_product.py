"""Save-browser campaign product surface (major #4) — not day-package stubs.

Player path: occupied/empty browser → recommend resume → checkpoint/autosave → integrity.
Leaf actions use real SaveLoad APIs: save_slot:X / load_slot:X (save_game_detailed / load_game_detailed).
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from priority_systems import save_slot_browser_package  # type: ignore
from week2_core_polish import save_slot_browser_flair  # type: ignore
from save_slot_ui import build_save_slot_list, slot_list_has_empty_and_occupied  # type: ignore
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


FIXED_SLOTS = ("quicksave", "autosave", "slot1", "slot2", "slot3", "slot4", "slot5")


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def _demo_occupied() -> List[Dict[str, Any]]:
    return [
        {
            "slot": "quicksave",
            "occupied": True,
            "label": "quicksave · world_full · GER",
            "metadata": {"scenario_id": "world_full", "player_tag": "GER", "timestamp": "1939-09-01"},
            "can_load": True,
            "can_save": True,
        },
        {
            "slot": "slot1",
            "occupied": True,
            "label": "slot1 · campaign · GER",
            "metadata": {"scenario_id": "world_full", "player_tag": "GER", "timestamp": "1939-09-15"},
            "can_load": True,
            "can_save": True,
        },
    ]


def recommend_resume_slot(rows: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    """Pick best occupied slot for resume (newest timestamp preferred)."""
    occupied = [r for r in rows if isinstance(r, Mapping) and bool(r.get("occupied"))]
    if not occupied:
        return {
            "slot": "",
            "action_id": "",
            "empty": True,
            "summary": "No occupied slot to resume",
            "can_load": False,
        }
    def _ts(r: Mapping[str, Any]) -> str:
        meta = r.get("metadata") if isinstance(r.get("metadata"), Mapping) else {}
        return str(meta.get("timestamp", meta.get("last_played", r.get("label", ""))))

    occupied_sorted = sorted(occupied, key=_ts, reverse=True)
    best = occupied_sorted[0]
    slot = str(best.get("slot", best.get("slot_id", ""))).strip()
    return {
        "slot": slot,
        "action_id": "load_slot:%s" % slot if slot else "",
        "label": str(best.get("flair_label", best.get("label", slot))),
        "can_load": bool(best.get("can_load", True)),
        "empty": False,
        "summary": "Resume · %s" % (best.get("label", slot)),
        "row": dict(best),
    }


def recommend_checkpoint_slot(rows: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    """Prefer autosave for checkpoint, else first empty, else quicksave."""
    by_slot = {str(r.get("slot", r.get("slot_id", ""))): r for r in rows if isinstance(r, Mapping)}
    if "autosave" in by_slot:
        slot = "autosave"
    else:
        empty = next(
            (str(r.get("slot", "")) for r in rows if isinstance(r, Mapping) and not bool(r.get("occupied"))),
            "quicksave",
        )
        slot = empty or "quicksave"
    row = by_slot.get(slot, {"slot": slot, "occupied": False, "can_save": True})
    return {
        "slot": slot,
        "action_id": "save_slot:%s" % slot,
        "label": str(row.get("flair_label", row.get("label", slot))),
        "can_save": bool(row.get("can_save", True)),
        "empty": False,
        "summary": "Checkpoint · save %s" % slot,
        "row": dict(row) if isinstance(row, Mapping) else {"slot": slot},
    }


def build_save_browser_campaign_product(
    occupied_slots: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    fixed_slots: Optional[Sequence[str]] = None,
    max_rows: int = 8,
) -> Dict[str, Any]:
    """Full save-browser campaign product: rows + flair + resume + checkpoint + apply queue."""
    fixed = list(fixed_slots or FIXED_SLOTS)
    occ = list(occupied_slots) if occupied_slots is not None else _demo_occupied()

    # Normalize occupied entries for build_save_slot_list (expects slot keys)
    norm_occ: List[Dict[str, Any]] = []
    for e in occ:
        if not isinstance(e, Mapping):
            continue
        d = dict(e)
        if "slot" not in d and "slot_id" in d:
            d["slot"] = d["slot_id"]
        if "occupied" not in d:
            d["occupied"] = True
        norm_occ.append(d)

    rows = build_save_slot_list(norm_occ, fixed_slots=fixed)
    flags = slot_list_has_empty_and_occupied(rows)
    pkg = save_slot_browser_package(occupied_slots=norm_occ, fixed_slots=fixed)
    flair = save_slot_browser_flair(rows, max_rows=max_rows)

    # Prefer flair rows for display
    display_rows = list(flair.get("rows") or rows)
    resume = recommend_resume_slot(display_rows if display_rows else rows)
    checkpoint = recommend_checkpoint_slot(display_rows if display_rows else rows)

    occupied_count = int(pkg.get("occupied_count", flair.get("occupied_count", 0)) or 0)
    empty_count = int(flair.get("empty_count", max(0, len(rows) - occupied_count)) or 0)
    count = int(pkg.get("count", len(rows)) or len(rows))

    score = _norm(
        0.35 * float(pkg.get("score", 0.7))
        + 0.25 * float(flair.get("score", 0.55))
        + 0.2 * (0.8 if not resume.get("empty") else 0.3)
        + 0.2 * (0.75 if checkpoint.get("slot") else 0.3)
    )

    apply_queue: List[Dict[str, Any]] = []
    actions: List[Dict[str, Any]] = [
        {
            "action_id": "save_browser_campaign_product",
            "label": "Run save browser campaign product",
            "enabled": True,
        }
    ]
    if not resume.get("empty") and resume.get("action_id"):
        actions.append(
            {
                "action_id": str(resume["action_id"]),
                "label": "Resume campaign · %s" % resume.get("slot"),
                "enabled": bool(resume.get("can_load", True)),
            }
        )
        apply_queue.append(
            {
                "action_id": str(resume["action_id"]),
                "province_id": 1,
                "score": 0.75,
                "enabled": bool(resume.get("can_load", True)),
                "label": "Resume %s" % resume.get("slot"),
                "product_action": "resume",
            }
        )
    if checkpoint.get("action_id"):
        actions.append(
            {
                "action_id": str(checkpoint["action_id"]),
                "label": "Checkpoint · %s" % checkpoint.get("slot"),
                "enabled": bool(checkpoint.get("can_save", True)),
            }
        )
        apply_queue.append(
            {
                "action_id": str(checkpoint["action_id"]),
                "province_id": 1,
                "score": 0.7,
                "enabled": bool(checkpoint.get("can_save", True)),
                "label": "Checkpoint %s" % checkpoint.get("slot"),
                "product_action": "checkpoint",
            }
        )
    # Quicksave always available
    actions.append({"action_id": "save_slot:quicksave", "label": "Quicksave", "enabled": True})
    apply_queue.append(
        {
            "action_id": "save_slot:quicksave",
            "province_id": 1,
            "score": 0.6,
            "enabled": True,
            "label": "Quicksave",
            "product_action": "quicksave",
        }
    )
    # Per-row save/load for top slots
    shown = 0
    for r in display_rows:
        if not isinstance(r, Mapping):
            continue
        slot = str(r.get("slot", "")).strip()
        if not slot:
            continue
        apply_queue.append(
            {
                "action_id": "save_slot:%s" % slot,
                "province_id": 1,
                "score": 0.55,
                "enabled": bool(r.get("can_save", True)),
                "label": "Save %s" % slot,
                "product_action": "save_row",
            }
        )
        if bool(r.get("occupied")) and bool(r.get("can_load", True)):
            apply_queue.append(
                {
                    "action_id": "load_slot:%s" % slot,
                    "province_id": 1,
                    "score": 0.65,
                    "enabled": True,
                    "label": "Load %s" % slot,
                    "product_action": "load_row",
                }
            )
        shown += 1
        if shown >= max_rows:
            break

    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok_flags = bool(flags.get("has_empty") or flags.get("has_occupied") or count > 0)

    label = (
        "Save browser campaign · %d slots · occupied %d · empty %d · resume %s · checkpoint %s · score %.2f"
        % (
            count,
            occupied_count,
            empty_count,
            resume.get("slot") or "—",
            checkpoint.get("slot") or "—",
            score,
        )
    )
    plain_lines = [label, str(resume.get("summary", "")), str(checkpoint.get("summary", ""))]
    for r in display_rows[:max_rows]:
        if isinstance(r, Mapping):
            plain_lines.append(str(r.get("flair_label", r.get("label", r.get("slot", "")))))

    return {
        "rows": display_rows,
        "browser_rows": rows,
        "package": pkg,
        "flair": flair,
        "flags": flags,
        "resume": resume,
        "checkpoint": checkpoint,
        "occupied_count": occupied_count,
        "empty_count": empty_count,
        "count": count,
        "score": score,
        "save_score": score,
        "apply_queue": apply_queue,
        "actions": actions,
        "gate": gate,
        "sole": sole,
        "slot_ok": ok_flags,
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#e8c547]💾 Save browser campaign[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": count <= 0,
        "integration": [
            "save_browser_campaign_product",
            "resume",
            "checkpoint",
            "major_4",
            "save_game_detailed",
            "load_game_detailed",
        ],
    }


def execute_save_browser_action(
    action_id: str,
    *,
    occupied_slots: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Validate a browser leaf action (save_slot:X / load_slot:X) against product rows."""
    aid = str(action_id or "").strip()
    product = build_save_browser_campaign_product(occupied_slots)
    rows = product.get("rows") or []
    kind = ""
    slot = ""
    if aid.startswith("save_slot:"):
        kind = "save"
        slot = aid[len("save_slot:") :].strip()
    elif aid.startswith("load_slot:"):
        kind = "load"
        slot = aid[len("load_slot:") :].strip()
    elif aid in ("resume", "save_browser_resume"):
        kind = "load"
        slot = str((product.get("resume") or {}).get("slot", ""))
        aid = "load_slot:%s" % slot if slot else aid
    elif aid in ("checkpoint", "save_browser_checkpoint"):
        kind = "save"
        slot = str((product.get("checkpoint") or {}).get("slot", "autosave"))
        aid = "save_slot:%s" % slot
    else:
        return {
            "ok": False,
            "reason": "unknown action",
            "action_id": aid,
            "empty": True,
            "summary": "Unknown save browser action",
        }

    row = next(
        (r for r in rows if isinstance(r, Mapping) and str(r.get("slot", "")) == slot),
        {"slot": slot, "occupied": False, "can_save": True, "can_load": False},
    )
    if kind == "load" and not bool(row.get("can_load", row.get("occupied", False))):
        return {
            "ok": False,
            "reason": "slot empty — cannot load",
            "action_id": aid,
            "slot": slot,
            "summary": "Load blocked · %s empty" % slot,
            "empty": False,
            "api": "load_game_detailed",
        }
    label = "%s · %s · api %s" % (
        kind.upper(),
        slot,
        "save_game_detailed" if kind == "save" else "load_game_detailed",
    )
    return {
        "ok": True,
        "action_id": aid,
        "slot": slot,
        "kind": kind,
        "row": dict(row) if isinstance(row, Mapping) else {},
        "api": "save_game_detailed" if kind == "save" else "load_game_detailed",
        "apply_queue": [
            {
                "action_id": aid,
                "province_id": 1,
                "score": 0.7 if kind == "load" else 0.65,
                "enabled": True,
                "label": label,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8c547]💾 %s[/color] [color=#8899aa]%s[/color]" % (kind.upper(), label),
        "empty": False,
        "score": 0.7 if kind == "load" else 0.65,
    }


def save_browser_campaign_product_integrity() -> Dict[str, Any]:
    product = build_save_browser_campaign_product()
    empty_only = build_save_browser_campaign_product([])
    resume_ok = not bool((product.get("resume") or {}).get("empty", True))
    cp = execute_save_browser_action("checkpoint")
    rs = execute_save_browser_action("resume")
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = (
        not bool(product.get("empty"))
        and int(product.get("count", 0)) >= 5
        and resume_ok
        and bool(cp.get("ok"))
        and bool(rs.get("ok"))
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and int(empty_only.get("count", 0)) >= 5  # fixed slots always present
    )
    return {
        "ok": ok,
        "count": int(product.get("count", 0)),
        "occupied_count": int(product.get("occupied_count", 0)),
        "resume_slot": str((product.get("resume") or {}).get("slot", "")),
        "checkpoint_slot": str((product.get("checkpoint") or {}).get("slot", "")),
        "gate": gate,
        "summary": "Save browser campaign product integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_save_browser_campaign_product_loop() -> Dict[str, Any]:
    product = build_save_browser_campaign_product()
    gate = save_browser_campaign_product_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = (
        "Close save browser campaign product · slots %d · occupied %d · queue %d · %s"
        % (
            int(product.get("count", 0)),
            int(product.get("occupied_count", 0)),
            len(product.get("apply_queue") or []),
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8c547]✓ Save browser campaign product[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
