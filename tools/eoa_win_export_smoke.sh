#!/usr/bin/env bash
# Headless Windows release export smoke.
# Not a Windows boot test. Wine is a separate, weak proxy and is not run here.
#
#   tools/eoa_win_export_smoke.sh
#
# One Godot at a time, via tools/run_godot.sh, under flock ~/.eoa_godot.lock.
# Fresh non-empty XDG_DATA_HOME / XDG_CONFIG_HOME / XDG_CACHE_HOME per run.
# Export templates are a read-only symlink. rcedit is set only in that fresh
# editor settings file. Does not write ~/.local/share/godot or the real
# ~/.config/godot/editor_settings-4.7.tres.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RCEDIT="${EOA_RCEDIT:-${HOME}/Applications/rcedit/rcedit-x64.exe}"
REAL_EDITOR_SETTINGS="${HOME}/.config/godot/editor_settings-4.7.tres"
TEMPLATE_LINK_TARGET="${HOME}/.local/share/godot/export_templates/4.7.1.stable"
EXE_REL="build/windows/EpochsOfAscendancy.exe"
FLOOR_BYTES=$((300 * 1024 * 1024))
CEIL_BYTES=$((800 * 1024 * 1024))

fail() {
	echo "EOA_WIN_EXPORT_SMOKE FAIL: $*" >&2
	exit 1
}

wait_until_idle() {
	local n=0
	while pgrep -af run_godot >/dev/null 2>&1; do
		n=$((n + 1))
		if [[ "$n" -gt 30 ]]; then
			fail "Godot still busy after 30 minutes; not killing it"
		fi
		echo "EOA_WIN_EXPORT_SMOKE who=wait godot busy; sleep 60s (poll ${n})"
		sleep 60
	done
}

if [[ ! -f "$RCEDIT" ]]; then
	fail "rcedit missing at ${RCEDIT} (host-local official release; not committed)"
fi
if [[ ! -d "$TEMPLATE_LINK_TARGET" ]]; then
	fail "export templates directory missing: ${TEMPLATE_LINK_TARGET}"
fi

RUN_ROOT="$(mktemp -d /tmp/eoa-win-export-XXXXXX)"
export XDG_DATA_HOME="${RUN_ROOT}/data"
export XDG_CONFIG_HOME="${RUN_ROOT}/config"
export XDG_CACHE_HOME="${RUN_ROOT}/cache"
mkdir -p \
	"${XDG_DATA_HOME}/godot/export_templates" \
	"${XDG_CONFIG_HOME}/godot" \
	"${XDG_CACHE_HOME}/godot"
# Homes must be non-empty. The marker stays in the fresh cache only.
echo "eoa-win-export" >"${XDG_CACHE_HOME}/godot/keep.txt"
ln -s "$TEMPLATE_LINK_TARGET" "${XDG_DATA_HOME}/godot/export_templates/4.7.1.stable"
if [[ ! -L "${XDG_DATA_HOME}/godot/export_templates/4.7.1.stable" ]]; then
	fail "template path is not a symlink"
fi
if [[ ! -f "${XDG_DATA_HOME}/godot/export_templates/4.7.1.stable/windows_release_x86_64.exe" ]]; then
	fail "windows release template missing through the symlink"
fi

EDITOR_SETTINGS="${XDG_CONFIG_HOME}/godot/editor_settings-4.7.tres"
cat >"$EDITOR_SETTINGS" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/windows/rcedit = "${RCEDIT}"
EOF

REAL_MTIME_BEFORE="$(stat -c %Y "$REAL_EDITOR_SETTINGS" 2>/dev/null || echo missing)"
LOG="${RUN_ROOT}/export.log"
mkdir -p build/windows
# This worktree's export dir only. Do not touch leftover exes elsewhere.
find build/windows -mindepth 1 -maxdepth 1 -exec rm -rf {} +

echo "EOA_WIN_EXPORT_SMOKE who=start xdg=${RUN_ROOT} rcedit=${RCEDIT}"
wait_until_idle

set +e
flock "${HOME}/.eoa_godot.lock" \
	env \
		XDG_DATA_HOME="$XDG_DATA_HOME" \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		XDG_CACHE_HOME="$XDG_CACHE_HOME" \
	tools/run_godot.sh --headless --path . --export-release "Windows Desktop" "$EXE_REL" \
	>"$LOG" 2>&1
rc=$?
set -e
echo "EOA_WIN_EXPORT_SMOKE who=export_exit rc=${rc} log=${LOG}"

REAL_MTIME_AFTER="$(stat -c %Y "$REAL_EDITOR_SETTINGS" 2>/dev/null || echo missing)"
if [[ "$REAL_MTIME_BEFORE" != "$REAL_MTIME_AFTER" ]]; then
	fail "real editor settings changed (${REAL_EDITOR_SETTINGS})"
fi

python3 - "$LOG" "$EXE_REL" "$ROOT/build/windows" "$rc" "$FLOOR_BYTES" "$CEIL_BYTES" <<'PY'
import pathlib, re, sys

log_path, exe_rel, out_dir, rc_s, floor_s, ceil_s = sys.argv[1:]
rc = int(rc_s)
floor_b = int(floor_s)
ceil_b = int(ceil_s)
log = pathlib.Path(log_path).read_text(errors="replace")
ansi = re.compile(r"\x1b\[[0-9;]*m")
allow = re.compile(
    r"resources still in use|DummyTexture|invalid UID|ObjectDB|CanvasItem|leaked at exit",
    re.I,
)
hard = re.compile(
    r"SCRIPT ERROR|export template not found|No export template|Could not find template|"
    r"Failed to export|Cannot export|Pack failed|failed to save pack",
    re.I,
)
bad = []
for n, raw in enumerate(log.splitlines(), 1):
    line = ansi.sub("", raw).strip()
    if not line:
        continue
    if hard.search(line):
        if "SCRIPT ERROR" in line or not allow.search(line):
            bad.append(f"{n}:{line[:240]}")
        continue
    if line.startswith("ERROR:") and not allow.search(line):
        bad.append(f"{n}:{line[:240]}")

exe = pathlib.Path(exe_rel)
problems = []
if rc != 0:
    problems.append(f"export exit {rc}")
if not exe.is_file():
    problems.append("missing exe")
else:
    data = exe.read_bytes()
    size = len(data)
    print(f"EOA_WIN_EXPORT_SMOKE bytes={size}")
    if size < floor_b or size > ceil_b:
        problems.append(f"size {size} outside {floor_b}..{ceil_b}")
    if data[-4:] != b"GDPC":
        problems.append(f"GDPC trailer missing, last4={data[-4:]!r}")
    else:
        print("EOA_WIN_EXPORT_SMOKE gdpc=yes")
    need = {
        "Epochs of Ascendancy": "Epochs of Ascendancy".encode("utf-16le"),
        "Featherstone Ops": "Featherstone Ops".encode("utf-16le"),
        "0.1.0.0": "0.1.0.0".encode("utf-16le"),
    }
    for label, needle in need.items():
        if needle not in data:
            problems.append(f"missing utf-16 metadata {label}")
        else:
            print(f"EOA_WIN_EXPORT_SMOKE metadata={label}")

allowed_names = {"EpochsOfAscendancy.exe", "EpochsOfAscendancy.console.exe"}
out = pathlib.Path(out_dir)
for child in sorted(out.iterdir()):
    name = child.name
    if name not in allowed_names:
        problems.append(f"unexpected output {name}")
    if name.lower().endswith(".pck"):
        problems.append(f"sibling pck {name}")
    if name.lower().endswith(".dll"):
        problems.append(f"unexpected dll {name}")

if bad:
    problems.append("log hits: " + " | ".join(bad[:12]))
    if len(bad) > 12:
        problems.append(f"... and {len(bad) - 12} more log hits")

if problems:
    print("EOA_WIN_EXPORT_SMOKE FAIL", file=sys.stderr)
    for item in problems:
        print(item, file=sys.stderr)
    raise SystemExit(1)
print("EOA_WIN_EXPORT_SMOKE RESULT=PASS")
PY

file -b "$EXE_REL"
sha256sum "$EXE_REL"
echo "EOA_WIN_EXPORT_SMOKE who=done log=${LOG}"
