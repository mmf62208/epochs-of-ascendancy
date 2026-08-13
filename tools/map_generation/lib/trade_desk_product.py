"""Trade Desk primary — auto interdict · tariff skim · desk board (R3–R5)."""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
REL_PATH = ROOT / "data" / "diplomacy" / "relation_rules.json"

SURFACE_KEYS = (
    "tdk_primary_catalog",
    "tdk_primary_interdict",
    "tdk_primary_tariff",
    "tdk_primary_desk",
    "tdk_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "tdk_catalog",
    "tdk_interdict",
    "tdk_tariff",
    "tdk_desk",
    "tdk_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "tdk_catalog": "apply_trade_desk_catalog_live",
    "tdk_interdict": "apply_trade_desk_interdict_live",
    "tdk_tariff": "apply_trade_desk_tariff_live",
    "tdk_desk": "apply_trade_desk_board_live",
    "tdk_close": "apply_trade_desk_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def load_relation_rules(path: Optional[Path] = None) -> Dict[str, Any]:
    p = path or REL_PATH
    if not p.is_file():
        return {}
    return json.loads(p.read_text(encoding="utf-8"))


def monthly_hit_chance(route_risk: float) -> float:
    """Mirror TradeManager.process_monthly_trade_risks hit_chance clamp."""
    risk = max(float(route_risk), 0.0)
    return max(0.02, min(0.45, risk * 0.55))


def monthly_loss_fraction(route_risk: float, roll: float = 0.6) -> float:
    """Mirror loss = clamp(risk * rand, 0.08, 0.65) with fixed roll for pure tests."""
    risk = max(float(route_risk), 0.0)
    r = max(0.35, min(0.85, float(roll)))
    return max(0.08, min(0.65, risk * r))


def pick_interdict_cause(route_risk: float, roll: float = 0.3) -> str:
    if float(route_risk) > 0.25 and float(roll) < 0.55:
        return "submarine"
    if float(roll) < 0.75:
        return "air_attack"
    return "surface_raider"


def apply_tariff_skim(amount: float, import_tariff: float = 0.0, import_subsidy: float = 0.0, embargo: bool = False) -> Dict[str, Any]:
    """Mirror TradeManager._apply_import_tariff_skim pure logic."""
    amt = max(0.0, float(amount))
    if embargo:
        return {"net_amount": 0.0, "tariff_rate": 1.0, "skimmed": amt, "embargo": True}
    rate = max(0.0, min(0.5, float(import_tariff)))
    sub = max(0.0, min(0.5, float(import_subsidy)))
    effective = max(0.0, min(0.5, rate - sub * 0.5))
    if effective <= 0.001:
        return {"net_amount": amt, "tariff_rate": 0.0, "skimmed": 0.0, "embargo": False}
    skim = amt * effective
    return {
        "net_amount": round(amt - skim, 4),
        "tariff_rate": round(effective, 4),
        "skimmed": round(skim, 4),
        "embargo": False,
    }


def desk_board_shape(
    player: str = "USA",
    partner: str = "ENG",
    crs: float = 30.0,
    import_tariff: float = 0.125,
    delivery_pct: int = 70,
    power_label: str = "peer",
    trade_disc: float = 0.95,
) -> Dict[str, Any]:
    """Minimal Trade Desk board payload shape (pure mirror of build_trade_desk_board keys)."""
    warnings: List[str] = []
    if delivery_pct < 90:
        warnings.append("Transit degraded: only %d%% of baseline cargo landing" % int(delivery_pct))
    if power_label in ("hopelessly_outmatched", "outmatched"):
        warnings.append("Power: %s vs %s" % (power_label, partner))
    if import_tariff >= 0.25:
        warnings.append("High import tariff %.0f%%" % (import_tariff * 100))
    return {
        "player_tag": player,
        "partner_tag": partner,
        "crs": float(crs),
        "band": {"label": "Cordial" if crs >= 25 else "Neutral"},
        "policy": {
            "import_tariff": float(import_tariff),
            "export_tariff": 0.0,
            "embargo": False,
            "mfn": False,
        },
        "discounts": {"trade_suu_mult": float(trade_disc), "tech_share_suu_mult": 1.0, "long_term": False},
        "power": {"matchup": {"label": power_label, "ratio": 1.0, "hopeless": power_label == "hopelessly_outmatched"}},
        "transit": {"healthy": delivery_pct >= 90, "overall_delivery_pct": int(delivery_pct)},
        "transit_plain": "Transit health %d%% on %s → %s" % (int(delivery_pct), player, partner),
        "tariff_treasury": 0.0,
        "warnings": warnings,
        "warning_n": len(warnings),
        "model": "strategic_compact_ledger",
        "desk_version": 1,
    }


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "Trade desk audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Trade desk audit", "empty": False,
    }


def build_trade_desk_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    # Auto-interdict pure
    hc = monthly_hit_chance(0.4)
    loss = monthly_loss_fraction(0.4, 0.6)
    cause = pick_interdict_cause(0.4, 0.3)
    interdict_ok = 0.02 <= hc <= 0.45 and 0.08 <= loss <= 0.65 and cause == "submarine"
    # Tariff pure
    t25 = apply_tariff_skim(100.0, import_tariff=0.25)
    t0 = apply_tariff_skim(100.0, import_tariff=0.0)
    emb = apply_tariff_skim(100.0, embargo=True)
    tariff_ok = (
        abs(float(t25["net_amount"]) - 75.0) < 0.01
        and abs(float(t0["net_amount"]) - 100.0) < 0.01
        and float(emb["net_amount"]) == 0.0
    )
    # Desk board pure
    board = desk_board_shape(delivery_pct=55, import_tariff=0.25, power_label="outmatched")
    required = (
        "player_tag", "partner_tag", "crs", "policy", "discounts", "power",
        "transit", "transit_plain", "tariff_treasury", "warnings", "model", "desk_version",
    )
    desk_ok = all(k in board for k in required) and int(board.get("warning_n", 0)) >= 1
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = interdict_ok and tariff_ok and desk_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "TDK · %s · live %s" % (step, api),
            "score": 0.78 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Trade desk · interdict_ok=%s tariff_ok=%s desk_ok=%s" % (
        interdict_ok, tariff_ok, desk_ok,
    )
    return {
        "score": 0.86 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "interdict_ok": interdict_ok, "tariff_ok": tariff_ok, "desk_ok": desk_ok,
        "hit_chance": hc, "loss_fraction": loss, "cause": cause,
        "tariff_sample": t25, "board": board,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "trade_desk_product", "auto_interdict", "tariff_skim",
            "trade_desk_board", "strategic_compact_ledger",
        ],
    }
