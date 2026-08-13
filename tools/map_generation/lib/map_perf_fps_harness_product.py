"""Map perf FPS / frame-time harness product (Master Plan M3 · Director D4).

Pure measurement product for:
  - global density pilot (~4650 land)
  - NUTS-3 Europe pilot (~1514 land)
  - world_full scaffold (~2665 provinces) — CI dual SCRIPT 0 smoke
  - world_accurate default (~8761 / land ~8421) — primary play board

Consumes frame_times_ms samples (from dual/headless EOA_MAP_PERF=1 later, or
synthetic lists for pure tests). Does **not** invent budget PASS without samples.

Later dual wiring: MapRendererPerf.mark_frame → samples → this product
(or GD mirror of measure_frame_budget). Env flag remains EOA_MAP_PERF=1.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Union

# Hard frame budgets (ms). 1000/fps.
BUDGET_MS_30: float = 1000.0 / 30.0  # ≈ 33.333
BUDGET_MS_60: float = 1000.0 / 60.0  # ≈ 16.667

# Pilot expected land / province counts (honest constants from shipped pilots).
# Soft budgets may be slightly looser than hard for denser boards (advisory only).
_PILOT_PLANS: Dict[str, Dict[str, Any]] = {
    "density": {
        "pilot_tag": "density",
        "pilot_name": "density",
        "land_n": 4650,
        "province_count": 4650,
        "id_base": 900000,
        "scenario_hint": "provinces_pilot_global_density",
        "soft_budget_ms_30": BUDGET_MS_30,
        "soft_budget_ms_60": 18.0,  # slightly soft vs 16.67 at ~4.6k land
        "soft_p95_ms_30": 42.0,
        "soft_p95_ms_60": 22.0,
        "target_fps_primary": 30,
        "target_fps_stretch": 60,
        "summary": "Density pilot · land~4650 · soft 30fps 33.3ms · soft 60fps 18ms",
    },
    "nuts3": {
        "pilot_tag": "nuts3",
        "pilot_name": "nuts3",
        "land_n": 1514,
        "province_count": 1514,
        "id_base": 710000,
        "scenario_hint": "provinces_pilot_europe_nuts3",
        "soft_budget_ms_30": BUDGET_MS_30,
        "soft_budget_ms_60": BUDGET_MS_60,
        "soft_p95_ms_30": 40.0,
        "soft_p95_ms_60": 20.0,
        "target_fps_primary": 30,
        "target_fps_stretch": 60,
        "summary": "NUTS-3 Europe pilot · land~1514 · soft 30/60fps hard-aligned",
    },
    "world_full": {
        "pilot_tag": "world_full",
        "pilot_name": "world_full",
        "land_n": 2325,
        "province_count": 2665,
        "id_base": 1,
        "scenario_hint": "world_full",
        "soft_budget_ms_30": BUDGET_MS_30,
        "soft_budget_ms_60": BUDGET_MS_60,
        "soft_p95_ms_30": 40.0,
        "soft_p95_ms_60": 20.0,
        "target_fps_primary": 30,
        "target_fps_stretch": 60,
        "summary": "world_full scaffold · provinces~2665 · CI dual SCRIPT 0 · soft 30/60fps",
    },
    "world_accurate": {
        "pilot_tag": "world_accurate",
        "pilot_name": "world_accurate",
        # Post US + full RoW sparse merge (2026-07-29); pre was 5670 / 8761.
        "land_n": 3180,
        "province_count": 3520,
        "land_n_pre_us_merge": 8421,
        "province_count_pre_us_merge": 8761,
        "land_n_pre_row_sparse": 5330,
        "province_count_pre_row_sparse": 5670,
        "id_base": 710000,
        "scenario_hint": "world_accurate",
        # Primary play board: soft 30fps target; 60fps is stretch-only at dense GIS scale.
        "soft_budget_ms_30": BUDGET_MS_30,
        "soft_budget_ms_60": 20.0,  # stretch advisory
        "soft_p95_ms_30": 48.0,
        "soft_p95_ms_60": 28.0,
        "target_fps_primary": 30,
        "target_fps_stretch": 60,
        "summary": (
            "world_accurate default · provinces~3520 land~3180 (post US+RoW sparse; was ~5670/~8761) · "
            "soft 30fps primary · 60fps stretch · EOA_MAP_PERF=1 (honest EMPTY until samples)"
        ),
    },
    "custom": {
        "pilot_tag": "custom",
        "pilot_name": "custom",
        "land_n": 0,
        "province_count": 0,
        "id_base": 0,
        "scenario_hint": "",
        "soft_budget_ms_30": BUDGET_MS_30,
        "soft_budget_ms_60": BUDGET_MS_60,
        "soft_p95_ms_30": 40.0,
        "soft_p95_ms_60": 20.0,
        "target_fps_primary": 30,
        "target_fps_stretch": 60,
        "summary": "Custom board · budgets default 30/60fps",
    },
}

_PILOT_ALIASES: Dict[str, str] = {
    "density": "density",
    "global_density": "density",
    "global": "density",
    "pilot_global_density": "density",
    "provinces_pilot_global_density": "density",
    "nuts3": "nuts3",
    "nuts": "nuts3",
    "nuts-3": "nuts3",
    "europe_nuts3": "nuts3",
    "provinces_pilot_europe_nuts3": "nuts3",
    "world_full": "world_full",
    "world": "world_full",
    "full": "world_full",
    "scaffold": "world_full",
    "world_accurate": "world_accurate",
    "accurate": "world_accurate",
    "gis": "world_accurate",
    "gis_hybrid": "world_accurate",
    "provinces_world_accurate": "world_accurate",
    "default": "world_accurate",
    "custom": "custom",
}


def _norm_score(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.0
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def _as_float_list(values: Optional[Sequence[Any]]) -> List[float]:
    out: List[float] = []
    if not values:
        return out
    for v in values:
        try:
            f = float(v)
        except (TypeError, ValueError):
            continue
        if f < 0:
            continue
        out.append(f)
    return out


def _percentile(sorted_vals: Sequence[float], pct: float) -> float:
    """Linear interpolation percentile; pct in [0, 100]."""
    n = len(sorted_vals)
    if n == 0:
        return 0.0
    if n == 1:
        return float(sorted_vals[0])
    p = max(0.0, min(100.0, float(pct)))
    if p <= 0:
        return float(sorted_vals[0])
    if p >= 100:
        return float(sorted_vals[-1])
    rank = (p / 100.0) * (n - 1)
    lo = int(rank)
    hi = min(lo + 1, n - 1)
    frac = rank - lo
    return float(sorted_vals[lo]) * (1.0 - frac) + float(sorted_vals[hi]) * frac


def resolve_pilot_tag(
    pilot_name: Optional[str] = None,
    province_count: Optional[int] = None,
    land_n: Optional[int] = None,
) -> str:
    """Map pilot_name / counts → density | nuts3 | world_full | world_accurate | custom."""
    if pilot_name:
        key = str(pilot_name).strip().lower().replace(" ", "_")
        if key in _PILOT_ALIASES:
            return _PILOT_ALIASES[key]
        if "accurate" in key or "gis" in key:
            return "world_accurate"
        if "density" in key:
            return "density"
        if "nuts" in key:
            return "nuts3"
        if "full" in key or "scaffold" in key:
            return "world_full"
        if key == "world" or key.startswith("world_"):
            # Prefer accurate when ambiguous "world" alone already alias→world_full;
            # bare "world_*" without full/accurate falls through to count match.
            if "full" in key:
                return "world_full"
    # Prefer province_count when both given (accurate: 8761 total vs 8421 land).
    n = int(province_count if province_count is not None else (land_n if land_n is not None else 0))
    if n <= 0 and land_n is not None:
        n = int(land_n)
    if n <= 0:
        return "custom"
    wa = _PILOT_PLANS["world_accurate"]
    candidates = {
        "density": abs(n - int(_PILOT_PLANS["density"]["land_n"])),
        "nuts3": abs(n - int(_PILOT_PLANS["nuts3"]["land_n"])),
        "world_full": abs(n - int(_PILOT_PLANS["world_full"]["province_count"])),
        "world_accurate": min(
            abs(n - int(wa["province_count"])),
            abs(n - int(wa["land_n"])),
            abs(n - int(wa.get("province_count_pre_us_merge") or wa["province_count"])),
            abs(n - int(wa.get("land_n_pre_us_merge") or wa["land_n"])),
            abs(n - int(wa.get("province_count_pre_row_sparse") or wa["province_count"])),
            abs(n - int(wa.get("land_n_pre_row_sparse") or wa["land_n"])),
        ),
    }
    best_tag = min(candidates, key=candidates.get)
    best = candidates[best_tag]
    # Only auto-tag when within ~15% of a known pilot count
    threshold = max(80, int(0.15 * n))
    if best > threshold:
        return "custom"
    return best_tag


def pilot_budget_plan(pilot_name: str = "density") -> Dict[str, Any]:
    """Expected province/land counts and soft budgets for known pilots.

    Always returns a dict (custom fallback). Keys include land_n, province_count,
    soft_budget_ms_30/60, soft_p95_ms_30/60, pilot_tag.
    """
    key = str(pilot_name or "custom").strip().lower().replace(" ", "_")
    tag = _PILOT_ALIASES.get(key, resolve_pilot_tag(pilot_name=key))
    plan = dict(_PILOT_PLANS.get(tag) or _PILOT_PLANS["custom"])
    plan["ok"] = tag in ("density", "nuts3", "world_full", "world_accurate", "custom")
    plan["empty"] = False
    plan["hard_budget_ms_30"] = BUDGET_MS_30
    plan["hard_budget_ms_60"] = BUDGET_MS_60
    return plan


def measure_frame_budget(
    frame_times_ms: Optional[Sequence[Any]] = None,
    target_fps: float = 30.0,
) -> Dict[str, Any]:
    """Measure mean/p95/min/max frame ms and whether samples meet target_fps budget.

    Empty samples → empty=True, budget_ok=False (no fake PASS).
    """
    times = _as_float_list(frame_times_ms)
    try:
        fps = float(target_fps)
    except (TypeError, ValueError):
        fps = 30.0
    if fps <= 0:
        fps = 30.0
    target_ms = 1000.0 / fps

    if not times:
        return {
            "ok": False,
            "budget_ok": False,
            "empty": True,
            "sample_n": 0,
            "frame_times_ms": [],
            "mean_ms": 0.0,
            "p95_ms": 0.0,
            "min_ms": 0.0,
            "max_ms": 0.0,
            "estimated_fps": 0.0,
            "target_fps": fps,
            "target_ms": target_ms,
            "budget_ms": target_ms,
            "summary": "Frame budget EMPTY · no samples · target %.0ffps (%.2fms) · FAIL"
            % (fps, target_ms),
        }

    ordered = sorted(times)
    mean_ms = sum(times) / float(len(times))
    p95_ms = _percentile(ordered, 95.0)
    min_ms = float(ordered[0])
    max_ms = float(ordered[-1])
    estimated_fps = (1000.0 / mean_ms) if mean_ms > 1e-9 else 0.0
    # Hard gate: mean under budget (matches MapRendererPerf.passes_budget spirit).
    budget_ok = mean_ms > 0.0 and mean_ms <= target_ms + 1e-9
    label = (
        "Frame budget · n=%d · mean %.2fms · p95 %.2fms · min %.2f · max %.2f · "
        "~%.1f fps · target %.0ffps (%.2fms) · %s"
        % (
            len(times),
            mean_ms,
            p95_ms,
            min_ms,
            max_ms,
            estimated_fps,
            fps,
            target_ms,
            "PASS" if budget_ok else "FAIL",
        )
    )
    return {
        "ok": budget_ok,
        "budget_ok": budget_ok,
        "empty": False,
        "sample_n": len(times),
        "frame_times_ms": list(times),
        "mean_ms": mean_ms,
        "p95_ms": p95_ms,
        "min_ms": min_ms,
        "max_ms": max_ms,
        "estimated_fps": estimated_fps,
        "target_fps": fps,
        "target_ms": target_ms,
        "budget_ms": target_ms,
        "summary": label,
    }


def _score_from_metrics(
    *,
    empty: bool,
    mean_ms: float,
    budget_ok_30: bool,
    budget_ok_60: bool,
) -> float:
    if empty:
        return 0.0
    # Base: how close mean is to 30fps budget (0 at 2× budget, 1 at 0ms)
    if mean_ms <= 0:
        return 0.0
    ratio_30 = mean_ms / BUDGET_MS_30
    base = max(0.0, min(1.0, 1.0 - (ratio_30 - 0.5) / 1.5))
    if budget_ok_60:
        return _norm_score(0.85 + 0.15 * base)
    if budget_ok_30:
        return _norm_score(0.55 + 0.30 * base)
    return _norm_score(0.15 + 0.25 * base)


def _expand_simulated_budgets(
    simulated_budgets: Optional[Union[float, Sequence[Any]]],
) -> List[float]:
    """Turn a single budget ms or list of budget samples into frame_times_ms.

    A bare float is expanded to a short constant series so stats are defined.
    """
    if simulated_budgets is None:
        return []
    if isinstance(simulated_budgets, (int, float)) and not isinstance(simulated_budgets, bool):
        try:
            v = float(simulated_budgets)
        except (TypeError, ValueError):
            return []
        if v < 0:
            return []
        # 30 constant samples — enough for mean/p95 without inventing variance
        return [v] * 30
    return _as_float_list(simulated_budgets)  # type: ignore[arg-type]


def build_map_perf_fps_harness_product(
    *,
    province_count: Optional[int] = None,
    land_n: Optional[int] = None,
    frame_times_ms: Optional[Sequence[Any]] = None,
    simulated_budgets: Optional[Union[float, Sequence[Any]]] = None,
    target_fps: float = 30.0,
    pilot_name: Optional[str] = None,
) -> Dict[str, Any]:
    """Main M3 harness entry: frame stats + 30/60 budget gates + pilot tag.

    Honesty: empty frame_times (and no simulated_budgets) → empty=True,
    budget_ok_30/60 False, score 0.0. No fake PASS.

    Dual/headless path (later): collect ms via EOA_MAP_PERF=1 MapRendererPerf,
    pass samples here (or GD mirror).
    """
    times = _as_float_list(frame_times_ms)
    simulated = False
    if not times and simulated_budgets is not None:
        times = _expand_simulated_budgets(simulated_budgets)
        simulated = bool(times)

    land = int(land_n) if land_n is not None else None
    prov = int(province_count) if province_count is not None else None
    if land is None and prov is not None:
        land = prov
    if prov is None and land is not None:
        prov = land

    tag = resolve_pilot_tag(pilot_name=pilot_name, province_count=prov, land_n=land)
    plan = pilot_budget_plan(tag)
    if land is None:
        land = int(plan.get("land_n") or 0)
    if prov is None:
        prov = int(plan.get("province_count") or land or 0)

    try:
        primary_fps = float(target_fps)
    except (TypeError, ValueError):
        primary_fps = 30.0
    if primary_fps <= 0:
        primary_fps = 30.0

    m_primary = measure_frame_budget(times, target_fps=primary_fps)
    m30 = measure_frame_budget(times, target_fps=30.0)
    m60 = measure_frame_budget(times, target_fps=60.0)

    empty = bool(m_primary.get("empty"))
    mean_ms = float(m_primary.get("mean_ms") or 0.0)
    p95_ms = float(m_primary.get("p95_ms") or 0.0)
    min_ms = float(m_primary.get("min_ms") or 0.0)
    max_ms = float(m_primary.get("max_ms") or 0.0)
    estimated_fps = float(m_primary.get("estimated_fps") or 0.0)
    budget_ok_30 = bool(m30.get("budget_ok")) and not empty
    budget_ok_60 = bool(m60.get("budget_ok")) and not empty
    score = _score_from_metrics(
        empty=empty,
        mean_ms=mean_ms,
        budget_ok_30=budget_ok_30,
        budget_ok_60=budget_ok_60,
    )

    if empty:
        status = "EMPTY"
        ok = False
    elif budget_ok_60:
        status = "PASS_60"
        ok = True
    elif budget_ok_30:
        status = "PASS_30"
        ok = True
    else:
        status = "FAIL"
        ok = False

    label = (
        "Map FPS harness · pilot=%s · land=%d · n=%d · mean %.2fms · p95 %.2fms · "
        "~%.1f fps · 30fps=%s · 60fps=%s · %s · score %.2f"
        % (
            tag,
            land,
            int(m_primary.get("sample_n") or 0),
            mean_ms,
            p95_ms,
            estimated_fps,
            "OK" if budget_ok_30 else "FAIL",
            "OK" if budget_ok_60 else "FAIL",
            status,
            score,
        )
    )
    if simulated:
        label += " · simulated"

    plain_lines = [
        label,
        plan.get("summary", ""),
        m30.get("summary", ""),
        m60.get("summary", ""),
        "Dual later: EOA_MAP_PERF=1 → MapRendererPerf samples → build_map_perf_fps_harness_product",
    ]

    return {
        "ok": ok,
        "empty": empty,
        "score": score,
        "status": status,
        "pilot_tag": tag,
        "pilot_name": tag,
        "province_count": int(prov),
        "land_n": int(land),
        "sample_n": int(m_primary.get("sample_n") or 0),
        "frame_times_ms": list(times),
        "mean_ms": mean_ms,
        "p95_ms": p95_ms,
        "min_ms": min_ms,
        "max_ms": max_ms,
        "estimated_fps": estimated_fps,
        "target_fps": primary_fps,
        "budget_ok_30": budget_ok_30,
        "budget_ok_60": budget_ok_60,
        "budget_ms_30": BUDGET_MS_30,
        "budget_ms_60": BUDGET_MS_60,
        "measure_primary": m_primary,
        "measure_30": m30,
        "measure_60": m60,
        "pilot_plan": plan,
        "simulated": simulated,
        "summary": label,
        "plain": "\n".join(str(x) for x in plain_lines if x),
        "bbcode": "[color=#70b0d0]⏱ Map FPS[/color] [color=#8899aa]%s[/color]" % label,
        "integration": [
            "map_perf_fps_harness_product",
            "m3_fps",
            "EOA_MAP_PERF",
            "MapRendererPerf",
            tag,
            "frame_budget",
        ],
        "dual_note": (
            "CI dual smoke (SCRIPT 0, lighter): EOA_SCENARIO=world_full EOA_MAP_PERF=1 "
            "tools/run_godot.sh --path . --headless res://scenes/TestScenario.tscn --quit-after 90; "
            "Accurate optional longer job: EOA_SCENARIO=world_accurate EOA_MAP_PERF=1 "
            "(default F5 board ~8761) — feed frame samples here; empty stays honest FAIL not fake PASS"
        ),
        "ci_path": "world_full" if tag in ("world_full", "density", "nuts3") else "world_accurate",
    }


def load_frame_samples_json(path: str = "") -> Dict[str, Any]:
    """Load M5 export JSON written by MapRendererPerf.export_session_json / headless harness.

    Returns {ok, empty, frame_times_ms, mean_ms, p50_ms, p95_ms, …} without inventing samples.
    If ``path`` is given, only that file is tried (no silent fallback to defaults).
    If ``path`` is empty, tries repo output then /tmp.
    """
    import json
    from pathlib import Path as _P

    root = _P(__file__).resolve().parents[3]
    explicit = bool(str(path or "").strip())
    if explicit:
        candidates = [_P(path)]
    else:
        candidates = [
            root / "tools" / "map_generation" / "output" / "map_perf_world_accurate_samples.json",
            _P("/tmp/eoa-map-perf-world-accurate.json"),
        ]
    for p in candidates:
        if not p.is_file():
            if explicit:
                return {
                    "ok": False,
                    "empty": True,
                    "path": str(p),
                    "frame_times_ms": [],
                    "summary": "Load samples missing · %s" % p,
                }
            continue
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            return {
                "ok": False,
                "empty": True,
                "path": str(p),
                "error": str(e),
                "frame_times_ms": [],
                "summary": "Load samples FAIL · %s" % e,
            }
        times = _as_float_list(data.get("frame_times_ms") or data.get("samples") or [])
        if not times:
            return {
                "ok": False,
                "empty": True,
                "path": str(p),
                "frame_times_ms": [],
                "measure_kind": str(data.get("measure_kind") or ""),
                "summary": "Load samples EMPTY · %s" % p,
            }
        # Prefer file stats when present; recompute p50 for honesty
        ordered = sorted(times)
        mean_ms = sum(times) / float(len(times))
        p50 = _percentile(ordered, 50.0)
        p95 = _percentile(ordered, 95.0)
        return {
            "ok": True,
            "empty": False,
            "path": str(p),
            "frame_times_ms": times,
            "sample_n": len(times),
            "mean_ms": mean_ms,
            "p50_ms": float(data.get("p50_ms") or p50),
            "p95_ms": float(data.get("p95_ms") or p95),
            "min_ms": float(ordered[0]),
            "max_ms": float(ordered[-1]),
            "estimated_fps": (1000.0 / mean_ms) if mean_ms > 1e-9 else 0.0,
            "pilot_tag": str(data.get("pilot_tag") or "world_accurate"),
            "measure_kind": str(data.get("measure_kind") or "unknown"),
            "province_count": int(data.get("province_count") or 8761),
            "land_n": int(data.get("land_n") or 8421),
            "summary": "Loaded %d samples from %s · mean %.2f · p50 %.2f · p95 %.2f"
            % (len(times), p.name, mean_ms, p50, p95),
        }
    return {
        "ok": False,
        "empty": True,
        "path": "",
        "frame_times_ms": [],
        "summary": "No map perf samples file found (run HeadlessWorldAccurateMapPerfTest or EOA_MAP_PERF dump)",
    }


def build_m5_measured_product(
    samples_path: str = "",
    *,
    pilot_name: str = "world_accurate",
) -> Dict[str, Any]:
    """M5 measured FPS product: ingest real samples → harness budget gates + p50/p95.

    Honesty: empty samples → empty=True, measured=False (not fake PASS).
    measure_kind is preserved so headless map-tick proxy is not claimed as GPU FPS.
    """
    loaded = load_frame_samples_json(samples_path)
    times = list(loaded.get("frame_times_ms") or [])
    harness = build_map_perf_fps_harness_product(
        pilot_name=pilot_name or str(loaded.get("pilot_tag") or "world_accurate"),
        province_count=int(loaded.get("province_count") or 8761),
        land_n=int(loaded.get("land_n") or 8421),
        frame_times_ms=times,
    )
    # Attach p50 (not always in harness root)
    ordered = sorted(_as_float_list(times))
    p50 = _percentile(ordered, 50.0) if ordered else 0.0
    harness["p50_ms"] = p50
    harness["measure_kind"] = str(loaded.get("measure_kind") or "")
    harness["samples_path"] = str(loaded.get("path") or "")
    harness["measured"] = not bool(harness.get("empty"))
    harness["m5"] = True
    # Soft 30fps primary; proxy samples still report budget_ok honestly from mean ms
    kind = str(harness.get("measure_kind") or "")
    if kind == "map_tick_proxy_headless":
        harness["note"] = (
            "measure_kind=map_tick_proxy_headless — CPU map path (pick/adj/path), "
            "not full MapRenderer GPU FPS. Soft 30fps gate is advisory for proxy."
        )
    elif kind == "renderer_frame":
        harness["note"] = "measure_kind=renderer_frame — MapRenderer process frame samples (EOA_MAP_PERF)."
    else:
        harness["note"] = "measure_kind unknown or empty; re-run M5 harness to capture samples."
    harness["summary"] = (
        "M5 measured · %s · p50 %.2fms · p95 %.2fms · ~%.1f fps · 30=%s · 60=%s · %s"
        % (
            kind or "empty",
            float(harness.get("p50_ms") or 0.0),
            float(harness.get("p95_ms") or 0.0),
            float(harness.get("estimated_fps") or 0.0),
            "OK" if harness.get("budget_ok_30") else "FAIL",
            "OK" if harness.get("budget_ok_60") else "FAIL",
            harness.get("status"),
        )
    )
    harness["integration"] = list(harness.get("integration") or []) + ["m5", "measured"]
    return harness


def map_perf_fps_harness_integrity() -> Dict[str, Any]:
    """Structural integrity: helpers + pilot plans + empty honesty."""
    known = ("density", "nuts3", "world_full", "world_accurate")
    plans_ok = all(pilot_budget_plan(k).get("pilot_tag") == k for k in known)
    dens = pilot_budget_plan("density")
    nuts = pilot_budget_plan("nuts3")
    accurate = pilot_budget_plan("world_accurate")
    empty = build_map_perf_fps_harness_product(frame_times_ms=[])
    # ~25ms mean → 40 fps: pass 30, fail 60
    mid = build_map_perf_fps_harness_product(
        land_n=4650,
        pilot_name="density",
        frame_times_ms=[24.0, 25.0, 26.0, 25.5, 24.5] * 6,
    )
    # Count resolve: 8761 / 8421 → world_accurate (not density)
    tag_8761 = resolve_pilot_tag(province_count=8761)
    tag_8421 = resolve_pilot_tag(land_n=8421)
    # M5 helpers present
    m5_empty = build_m5_measured_product(samples_path="/nonexistent/path.json")
    m5_helpers_ok = bool(m5_empty.get("empty")) and not bool(m5_empty.get("measured"))
    ok = (
        plans_ok
        and int(dens.get("land_n") or 0) >= 4000
        and int(nuts.get("land_n") or 0) >= 1000
        and int(accurate.get("province_count") or 0) >= 3000
        and tag_8761 == "world_accurate"
        and tag_8421 == "world_accurate"
        and resolve_pilot_tag(province_count=3520) == "world_accurate"
        and bool(empty.get("empty"))
        and not bool(empty.get("budget_ok_30"))
        and not bool(empty.get("budget_ok_60"))
        and bool(mid.get("budget_ok_30"))
        and not bool(mid.get("budget_ok_60"))
        and m5_helpers_ok
    )
    return {
        "ok": ok,
        "plans_ok": plans_ok,
        "density_land_n": dens.get("land_n"),
        "nuts3_land_n": nuts.get("land_n"),
        "world_accurate_province_count": accurate.get("province_count"),
        "resolve_8761": tag_8761,
        "resolve_8421": tag_8421,
        "empty_honest": bool(empty.get("empty")) and not bool(empty.get("budget_ok_30")),
        "mid_pass_30_fail_60": bool(mid.get("budget_ok_30")) and not bool(mid.get("budget_ok_60")),
        "m5_helpers_ok": m5_helpers_ok,
        "summary": "Map FPS harness integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
