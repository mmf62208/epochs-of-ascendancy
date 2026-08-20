"""Living unit story — appearance, counter stats, XP, replacements, history.

Counters must look different by type, show org/str/readiness, and fight
with experience that grows in battle and dilutes when greens replace losses.
Commanders and a short battle record sit on the unit card.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
POWER = ROOT / "scripts" / "combat" / "LandCombatPower.gd"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
STRIP = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"
TM = ROOT / "scripts" / "autoload" / "TimeManager.gd"
ATTR = ROOT / "scripts" / "combat" / "LandBattleAttrition.gd"
BM = ROOT / "scripts" / "combat" / "BattleManager.gd"
LM = ROOT / "scripts" / "leaders" / "LeaderManager.gd"
HARNESS = ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd"
GATES = ROOT / "tools" / "eoa_full_test_gates.sh"
POPUP = ROOT / "scripts" / "ui" / "DomainDesignPopup.gd"

RECRUIT_XP = 22.0
HEAVY_LOSS_STR = 0.08
HEAVY_LOSS_XP_SCALE = 0.20
CADRE_MENTOR = 0.30  # 2.0 * 0.15 from blend_combat_experience_manpower


def clamp(v: float, lo: float = 0.0, hi: float = 1.0) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return lo
    return max(lo, min(hi, x))


def nato_letter(archetype: str, kind: str = "") -> str:
    blob = ("%s %s" % (archetype or "", kind or "")).strip().lower()
    if "artillery" in blob or "gun" in blob:
        return "G"
    if "heavy" in blob and "tank" in blob:
        return "H"
    if "light" in blob and "tank" in blob:
        return "L"
    if "mountain" in blob or "gebirg" in blob:
        return "M"
    if "rocket" in blob:
        return "R"
    if "armor" in blob or "armour" in blob or "panzer" in blob or "tank" in blob:
        return "A"
    return "I"


def letter_color(letter: str) -> str:
    m = {
        "A": "gold",
        "H": "gold",
        "L": "gold",
        "G": "orange",
        "R": "orange",
        "M": "green",
        "I": "white",
    }
    return m.get(str(letter or "I"), "white")


def counter_bar_widths(org: float, strength: float, readiness: float, width: float = 40.0) -> Dict[str, float]:
    w = max(8.0, float(width))
    return {
        "org": max(2.0, w * clamp(org)),
        "str": max(2.0, w * clamp(strength)),
        "rdy": max(2.0, w * clamp(readiness)),
    }


def xp_power_mult(xp: float) -> float:
    """Green ~0.80, regular ~1.0, veteran ~1.18. Same curve as reinforcement logistics."""
    x = clamp(float(xp), 0.0, 100.0)
    if x <= 20.0:
        return 0.78 + (0.88 - 0.78) * (x / 20.0)
    if x <= 40.0:
        return 0.88 + (0.98 - 0.88) * ((x - 20.0) / 20.0)
    if x <= 60.0:
        return 0.98 + (1.0 - 0.98) * ((x - 40.0) / 20.0)
    if x <= 80.0:
        return 1.0 + (1.1 - 1.0) * ((x - 60.0) / 20.0)
    return 1.1 + (1.2 - 1.1) * ((x - 80.0) / 20.0)


def dilute_xp_replacements(old_xp: float, strength_gain: float, new_strength: float, recruit_xp: float = RECRUIT_XP) -> float:
    """Greens fill TOE holes. Surviving cadre keeps most knowledge."""
    old_v = clamp(old_xp, 0.0, 100.0)
    rec = clamp(recruit_xp, 0.0, 100.0)
    gain = max(0.0, float(strength_gain))
    new_s = max(0.05, float(new_strength))
    frac = clamp(gain / new_s, 0.0, 1.0)
    blended = (1.0 - frac) * old_v + frac * rec
    blended += CADRE_MENTOR * (1.0 - frac)
    return clamp(blended, 0.0, 100.0)


def dilute_xp_heavy_loss(old_xp: float, strength_lost: float) -> float:
    """Blooded troops among the dead. Mild — replacements are the bigger hit."""
    drop = max(0.0, float(strength_lost))
    if drop < HEAVY_LOSS_STR:
        return clamp(old_xp, 0.0, 100.0)
    return clamp(float(old_xp) * (1.0 - HEAVY_LOSS_XP_SCALE * drop), 0.0, 100.0)


def record_battle(
    *,
    date: str = "1936-01-01",
    province_id: int = 710173,
    result: str = "win",
    outcome: str = "",
    leader: str = "",
    key_factors: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    return {
        "date": str(date or ""),
        "province_id": int(province_id),
        "result": str(result or ""),
        "outcome": str(outcome or result or ""),
        "leader": str(leader or ""),
        "key_factors": [str(x) for x in (key_factors or [])][:6],
    }


def history_line(entry: Mapping[str, Any] | None) -> str:
    if not isinstance(entry, Mapping):
        return ""
    date = str(entry.get("date") or "").strip()
    outcome = str(entry.get("outcome") or entry.get("result") or "").strip()
    bits = [b for b in (date, outcome) if b]
    return " ".join(bits)


def history_lines(log: Sequence[Any], n: int = 3) -> List[str]:
    rows: List[str] = []
    items = list(log or [])
    for raw in items[-max(1, int(n)) :]:
        if isinstance(raw, Mapping):
            line = history_line(raw)
            if line:
                rows.append(line)
    return rows


def build_unit_living_story_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    if nato_letter("medium_tank") == "A" and nato_letter("infantry") == "I" and nato_letter("artillery") == "G":
        passes.append("nato_letters")
    else:
        fails.append("nato_letters")

    bars = counter_bar_widths(0.4, 0.5, 0.35)
    if bars["org"] < bars["str"] and bars["rdy"] >= 2.0:
        passes.append("counter_bars")
    else:
        fails.append("counter_bars")

    g = xp_power_mult(10.0)
    r = xp_power_mult(48.0)
    v = xp_power_mult(90.0)
    if g < 0.90 < r < v <= 1.21:
        passes.append("xp_mult_bands")
    else:
        fails.append("xp_mult_bands")

    vet = 90.0
    after_rep = dilute_xp_replacements(vet, 0.30, 1.0)
    if 40.0 < after_rep < vet - 5.0:
        passes.append("replacement_dilutes")
    else:
        fails.append("replacement_dilutes")

    tiny = dilute_xp_replacements(vet, 0.03, 0.63)
    if vet - 8.0 < tiny < vet:
        passes.append("trickle_mild")
    else:
        fails.append("trickle_mild")

    no_hit = dilute_xp_heavy_loss(vet, 0.04)
    hit = dilute_xp_heavy_loss(vet, 0.20)
    if abs(no_hit - vet) < 0.01 and hit < vet - 1.0:
        passes.append("heavy_loss")
    else:
        fails.append("heavy_loss")

    rec = record_battle(date="1936-02-03", result="win", outcome="victory", leader="Guderian")
    if "1936-02-03" in history_line(rec) and "victory" in history_line(rec):
        passes.append("history_line")
    else:
        fails.append("history_line")

    if check_wiring:
        power = POWER.read_text(encoding="utf-8") if POWER.is_file() else ""
        ren = RENDERER.read_text(encoding="utf-8") if RENDERER.is_file() else ""
        strip = STRIP.read_text(encoding="utf-8") if STRIP.is_file() else ""
        tm = TM.read_text(encoding="utf-8") if TM.is_file() else ""
        attr = ATTR.read_text(encoding="utf-8") if ATTR.is_file() else ""
        bm = BM.read_text(encoding="utf-8") if BM.is_file() else ""
        lm = LM.read_text(encoding="utf-8") if LM.is_file() else ""
        harness = HARNESS.read_text(encoding="utf-8") if HARNESS.is_file() else ""
        gates = GATES.read_text(encoding="utf-8") if GATES.is_file() else ""
        pop = POPUP.read_text(encoding="utf-8") if POPUP.is_file() else ""

        def _ok(name: str, cond: bool) -> None:
            wiring[name] = cond
            (passes if cond else fails).append(name)

        _ok("xp_in_power", "func xp_power_mult" in power and "xp_power_mult" in power)
        _ok("rdy_bar", "RdyBar" in ren)
        _ok("letter_from_arch", "visual_archetype" in ren and "func _unit_type_letter" in ren)
        _ok("popup_symbols", "DOMAIN_SYMBOLS" in pop and "artillery" in pop)
        _ok("replace_dilute", "dilute_xp_replacements" in tm)
        _ok("loss_dilute", "combat_experience" in attr)
        _ok("aar_log", "log_combat" in bm)
        _ok("card_history", "combat_log" in strip)
        _ok("save_log", "combat_log" in lm)
        _ok("auto_cmd", "auto_assign_land_leaders" in lm)
        _ok("on_official_quick", "test_unit_living_story_product" in gates)
        _ok("harness_story", "xp_power_mult" in harness or "RdyBar" in harness)

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "unit_living_story · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "look_stats_xp_replacements_history_commanders",
        "xp_green": round(xp_power_mult(10.0), 3),
        "xp_regular": round(xp_power_mult(48.0), 3),
        "xp_veteran": round(xp_power_mult(90.0), 3),
    }


def unit_living_story_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_living_story_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
