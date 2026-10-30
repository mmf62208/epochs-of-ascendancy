#!/usr/bin/env python3
"""Original AUDIO-1 sound effects.

Synthesizes short mono 16-bit WAVs with the Python stdlib. No third-party
samples. Every file is peak-normalized to -8 dBFS so nothing exceeds -6 dBFS.
"""
from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "audio" / "sfx"
SR = 22050
PEAK_DB = -8.0
PEAK_AMP = 10 ** (PEAK_DB / 20.0)
DATE = "2026-10-30"
GENERATOR = "tools/audio/gen_audio1_sfx.py"


def _noise(n: int, seed: int) -> list[float]:
    x = seed & 0xFFFFFFFF
    out: list[float] = []
    for _ in range(n):
        x = (1664525 * x + 1013904223) & 0xFFFFFFFF
        out.append((x / 0xFFFFFFFF) * 2.0 - 1.0)
    return out


def _tone(freq: float, n: int, decay: float) -> list[float]:
    out: list[float] = []
    for i in range(n):
        e = math.exp(-decay * i / max(1, n))
        out.append(math.sin(2.0 * math.pi * freq * i / SR) * e)
    return out


def _fade(samples: list[float], ms: float = 2.0) -> list[float]:
    n = max(1, int(SR * ms / 1000.0))
    out = samples[:]
    span = min(n, len(out))
    for i in range(span):
        g = i / float(span)
        out[i] *= g
        out[-1 - i] *= g
    return out


def _join(parts: list[list[float]]) -> list[float]:
    acc: list[float] = []
    for part in parts:
        acc.extend(part)
    return acc


def _mix(a: list[float], b: list[float], gain_b: float = 1.0) -> list[float]:
    n = max(len(a), len(b))
    out = [0.0] * n
    for i, s in enumerate(a):
        out[i] += s
    for i, s in enumerate(b):
        out[i] += s * gain_b
    return out


def ui_click() -> list[float]:
    n = int(SR * 0.045)
    burst = _noise(n, 11)
    for i in range(n):
        burst[i] *= math.exp(-18.0 * i / n)
    return _fade(_mix(burst, _tone(1600.0, n, 10.0), 0.65), 1.5)


def ui_hover() -> list[float]:
    return _fade(_tone(2400.0, int(SR * 0.028), 12.0), 1.5)


def day_tick() -> list[float]:
    return _fade(_tone(520.0, int(SR * 0.032), 8.0), 1.5)


def select() -> list[float]:
    return _fade(_tone(880.0, int(SR * 0.05), 7.0), 2.0)


def confirm() -> list[float]:
    gap = [0.0] * int(SR * 0.018)
    return _fade(_join([_tone(660.0, int(SR * 0.04), 8.0), gap, _tone(990.0, int(SR * 0.05), 7.0)]), 2.0)


def achievement() -> list[float]:
    parts: list[list[float]] = []
    for freq in (523.25, 659.25, 783.99):
        parts.append(_tone(freq, int(SR * 0.07), 6.0))
        parts.append([0.0] * int(SR * 0.012))
    return _fade(_join(parts), 3.0)


def error() -> list[float]:
    n = int(SR * 0.11)
    out: list[float] = []
    for i in range(n):
        phase = (180.0 * i / SR) % 1.0
        sq = 1.0 if phase < 0.5 else -1.0
        out.append(sq * math.exp(-5.0 * i / n) * 0.45)
    return _fade(out, 2.0)


def map_ping() -> list[float]:
    return _fade(_tone(494.0, int(SR * 0.07), 6.0), 2.0)


def pin_focus() -> list[float]:
    return _fade(_tone(740.0, int(SR * 0.055), 7.0), 2.0)


def combat_clash() -> list[float]:
    n = int(SR * 0.22)
    nz = _noise(n, 99)
    out: list[float] = []
    for i in range(n):
        e = math.exp(-7.0 * i / n)
        low = math.sin(2.0 * math.pi * 80.0 * i / SR) * e
        mid = math.sin(2.0 * math.pi * 140.0 * i / SR) * math.exp(-12.0 * i / n)
        out.append(low * 0.85 + mid * 0.35 + nz[i] * e * 0.5)
    return _fade(out, 3.0)


def alert() -> list[float]:
    gap = [0.0] * int(SR * 0.02)
    return _fade(_join([_tone(784.0, int(SR * 0.07), 5.0), gap, _tone(622.0, int(SR * 0.09), 4.0)]), 2.0)


def end_victory_sting() -> list[float]:
    parts: list[list[float]] = []
    for freq in (523.25, 659.25, 783.99, 1046.5):
        parts.append(_tone(freq, int(SR * 0.11), 4.0))
    return _fade(_join(parts), 4.0)


def end_defeat_sting() -> list[float]:
    parts: list[list[float]] = []
    for freq in (440.0, 349.23, 293.66):
        parts.append(_tone(freq, int(SR * 0.15), 3.0))
    return _fade(_join(parts), 4.0)


SOUNDS: list[tuple[str, object]] = [
    ("ui/ui_click.wav", ui_click),
    ("ui/ui_hover.wav", ui_hover),
    ("ui/select.wav", select),
    ("ui/confirm.wav", confirm),
    ("ui/achievement.wav", achievement),
    ("ui/error.wav", error),
    ("ui/alert.wav", alert),
    ("map/map.wav", map_ping),
    ("map/pin_focus.wav", pin_focus),
    ("map/day_tick.wav", day_tick),
    ("combat/combat_clash.wav", combat_clash),
    ("end/end_victory_sting.wav", end_victory_sting),
    ("end/end_defeat_sting.wav", end_defeat_sting),
]


def _to_pcm(samples: list[float]) -> tuple[list[int], float]:
    peak = max(abs(s) for s in samples) or 1e-9
    gain = PEAK_AMP / peak
    pcm: list[int] = []
    for s in samples:
        v = int(round(max(-1.0, min(1.0, s * gain)) * 32767.0))
        pcm.append(v)
    mx = max(abs(v) for v in pcm) or 1
    db = 20.0 * math.log10(mx / 32767.0)
    if db > -6.0 + 1e-6:
        raise SystemExit("peak %.2f dBFS exceeds -6" % db)
    return pcm, db


def _write_wav(path: Path, pcm: list[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(struct.pack("<" + "h" * len(pcm), *pcm))


def _write_credits(rows: list[tuple[str, float, int]]) -> None:
    lines = [
        "# AUDIO-1 credits",
        "",
        "Original effects generated for Epochs of Ascendancy. No Starter Pack, Sonniss, music, or voice assets.",
        "",
        "| File | Source | Author | License | Source URL | Download date |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for rel, db, nbytes in rows:
        res = "res://audio/sfx/" + rel
        lines.append(
            "| `%s` | Original (generated by %s) | Epochs of Ascendancy | Original | `%s` | %s |"
            % (res, GENERATOR, GENERATOR, DATE)
        )
    lines.append("")
    lines.append("Peak target %.1f dBFS. Measured peaks are at or under -6 dBFS." % PEAK_DB)
    lines.append("")
    (ROOT / "audio" / "CREDITS.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    rows: list[tuple[str, float, int]] = []
    total = 0
    for rel, fn in SOUNDS:
        pcm, db = _to_pcm(fn())
        path = OUT / rel
        _write_wav(path, pcm)
        total += path.stat().st_size
        rows.append((rel, db, path.stat().st_size))
        print("%s  peak=%6.2f dBFS  bytes=%d" % (rel, db, path.stat().st_size))
    _write_credits(rows)
    print("total_bytes=%d" % total)
    if total > 3 * 1024 * 1024:
        raise SystemExit("sfx total exceeds 3 MB")


if __name__ == "__main__":
    main()
