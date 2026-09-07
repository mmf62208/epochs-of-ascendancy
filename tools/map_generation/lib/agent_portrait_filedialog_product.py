"""Agent FileDialog portrait slot — custom PNG lives under user:// only.

Player value: click the 36px Agnt face, pick a stock or Import a PNG.
Import copies bytes to user://agent_portraits/{safe_id}.png — never res://
or /assets/. Reset deletes that file and restores the remembered stock.
Esc / close Agnt does not wipe customs.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
AGENT_SCREEN = ROOT / "scripts" / "ui" / "AgentAssignmentScreen.gd"
FRAME_PNG = ROOT / "assets" / "graphics" / "ui" / "agent_portrait_slot_frame.png"
FRAME_PNG_64 = ROOT / "assets" / "graphics" / "ui" / "agent_portrait_slot_frame_64.png"

USER_DIR = "user://agent_portraits"
STOCK_PREFIX = "res://assets/graphics/portraits/agents/"
STOCK_FACES = (
    "agent_male.png",
    "agent_female.png",
    "agent_italian.png",
    "double_agent.png",
    "elite_spy.png",
    "visionary_scientist.png",
)


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


def safe_portrait_agent_id(agent_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "", str(agent_id or ""))


def custom_portrait_user_path(agent_id: str) -> str:
    sid = safe_portrait_agent_id(agent_id)
    if not sid:
        return ""
    return "%s/%s.png" % (USER_DIR, sid)


def stock_sidecar_path(agent_id: str) -> str:
    sid = safe_portrait_agent_id(agent_id)
    if not sid:
        return ""
    return "%s/%s.stock" % (USER_DIR, sid)


def dest_allowed_for_import(dest: str) -> bool:
    """Bytes may land under user://agent_portraits only — never res:// or /assets/."""
    path = str(dest or "").replace("\\", "/")
    if not path:
        return False
    if path.startswith("res://"):
        return False
    if "/assets/" in path:
        return False
    return path.startswith(USER_DIR + "/") and path.endswith(".png")


def build_agent_portrait_filedialog_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    if safe_portrait_agent_id("GER/agent 1!") == "GERagent1" and safe_portrait_agent_id("") == "":
        passes.append("safe_id")
    else:
        fails.append("safe_id")
    if custom_portrait_user_path("spy_01") == "user://agent_portraits/spy_01.png":
        passes.append("user_png_path")
    else:
        fails.append("user_png_path")
    if stock_sidecar_path("spy_01") == "user://agent_portraits/spy_01.stock":
        passes.append("stock_sidecar_path")
    else:
        fails.append("stock_sidecar_path")
    if dest_allowed_for_import("user://agent_portraits/spy_01.png") and not dest_allowed_for_import(
        "res://assets/graphics/portraits/agents/agent_male.png"
    ):
        passes.append("dest_user_only")
    else:
        fails.append("dest_user_only")
    if not dest_allowed_for_import("/tmp/assets/stolen.png"):
        passes.append("dest_rejects_assets")
    else:
        fails.append("dest_rejects_assets")

    if FRAME_PNG.is_file():
        passes.append("frame_png")
    else:
        fails.append("frame_png")
    if FRAME_PNG_64.is_file():
        passes.append("frame_png_64")
    else:
        fails.append("frame_png_64")

    if check_wiring:
        src = AGENT_SCREEN.read_text(encoding="utf-8") if AGENT_SCREEN.is_file() else ""
        if not src:
            fails.append("missing_agent_screen")
        else:
            wiring["slot_36px"] = (
                "Vector2(36, 36)" in _gd_func_slice(src, "_make_agent_portrait_slot")
                and "AGENT_PORTRAIT_SLOT_FRAME" in src
            )
            wiring["six_stock_faces"] = all(
                (STOCK_PREFIX + name) in src for name in STOCK_FACES
            )
            wiring["in_card_picker"] = (
                "Import" in _gd_func_slice(src, "_make_agent_portrait_picker")
                and "Reset" in _gd_func_slice(src, "_make_agent_portrait_picker")
                and "PortraitPicker" in src
            )
            import_fn = _gd_func_slice(src, "_on_import_portrait_pressed")
            wiring["filedialog_native"] = (
                "FileDialog.new()" in import_fn
                and "ACCESS_FILESYSTEM" in import_fn
                and "use_native_dialog = true" in import_fn
                and "*.png" in import_fn
            )
            copy_fn = _gd_func_slice(src, "_import_portrait_png")
            wiring["copy_user_only"] = (
                "user://agent_portraits" in src
                and "store_buffer" in copy_fn
                and 'dest.begins_with("res://")' in copy_fn
                and '"/assets/" in dest_abs' in copy_fn
            )
            reset_fn = _gd_func_slice(src, "_on_reset_portrait_pressed")
            wiring["reset_deletes_custom"] = (
                "_delete_custom_portrait" in reset_fn
                and ".stock" in src
                and "_remember_original_stock" in src
            )
            del_fn = _gd_func_slice(src, "_delete_custom_portrait")
            wiring["delete_never_res"] = (
                'path.begins_with("res://")' in del_fn
                and "remove_absolute" in del_fn
            )
            wiring["close_does_not_wipe"] = (
                "func _on_close_pressed" in src
                and "_delete_custom_portrait" not in _gd_func_slice(src, "_on_close_pressed")
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
        "user_dir": USER_DIR,
        "stock_n": len(STOCK_FACES),
        "summary": "Agent FileDialog portrait · %s · fail=%s"
        % ("PASS" if ok else "FAIL", ",".join(fails) or "none"),
        "integration": [
            "agent_portrait_filedialog_product",
            "AgentAssignmentScreen FileDialog",
            "user://agent_portraits",
        ],
    }


def agent_portrait_filedialog_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_agent_portrait_filedialog_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
