"""Inspector Settle button title lock-in — named province, never generic create text.

Create path stays hidden with empty text. `_update_settle_button` writes
`🏠 Settle %s (+0.35, now %.2f)` from province.name (fallback `#id` only if
name empty) and hides for null/sea.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"

NAMED_TITLE_MARK = "Settle %s (+0.35"
GENERIC_CREATE_TITLE = "Settle This Province Now"


def _gd_func_slice(src: str, func_name: str) -> str:
    needle = "func %s" % func_name
    i = src.find(needle)
    if i < 0:
        return ""
    lines = src[i:].splitlines()
    out = [lines[0]]
    for line in lines[1:]:
        if line.startswith("func ") or line.startswith("static func "):
            break
        out.append(line)
    return "\n".join(out)


def format_settle_button_title(name: str, settlement_level: float, province_id: int) -> str:
    nm = str(name or "").strip()
    if not nm:
        nm = "#%d" % int(province_id)
    return "🏠 Settle %s (+0.35, now %.2f)" % (nm, float(settlement_level))


def build_settle_title_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    if format_settle_button_title("London", 1.0, 711414).startswith("🏠 Settle London (+0.35"):
        passes.append("format_named")
    else:
        fails.append("format_named")
    if format_settle_button_title("", 0.5, 12) == "🏠 Settle #12 (+0.35, now 0.50)":
        passes.append("format_id_fallback")
    else:
        fails.append("format_id_fallback")

    src = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    if not src:
        fails.append("missing_map_renderer")
    else:
        wiring["named_title"] = NAMED_TITLE_MARK in src
        wiring["no_generic_create"] = GENERIC_CREATE_TITLE not in src
        update_fn = _gd_func_slice(src, "_update_settle_button")
        wiring["hide_on_sea"] = (
            bool(update_fn)
            and "province.is_sea" in update_fn
            and "_btn_settle.visible = false" in update_fn
        )
        wiring["hide_on_null"] = bool(update_fn) and "province == null" in update_fn
        ensure_fn = _gd_func_slice(src, "_ensure_settle_button")
        wiring["create_hidden"] = (
            bool(ensure_fn)
            and GENERIC_CREATE_TITLE not in ensure_fn
            and "_btn_settle.visible = false" in ensure_fn
        )
        wiring["name_fallback_id"] = (
            'settle_nm = "#%d"' in update_fn or 'settle_nm = "#%d" % province.id' in update_fn
        )
        for k, v in wiring.items():
            if v:
                passes.append("wire_%s" % k)
            else:
                fails.append("wire_%s" % k)

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "Settle title lock-in · %s · fail=%s"
        % ("PASS" if ok else "FAIL", ",".join(fails) or "none"),
        "integration": [
            "settle_title_product",
            "MapRenderer._ensure_settle_button",
            "MapRenderer._update_settle_button",
        ],
    }


def settle_title_integrity() -> Dict[str, Any]:
    p = build_settle_title_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
