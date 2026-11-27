# Windows export

Repeatable Windows release export of current main. This is export config, a headless smoke, and a weak wine proxy. It is not a real Windows boot test. D3D12 agility is out of scope.

Godot **4.7.1**. Launch only through `tools/run_godot.sh`.

## Recipe

`tools/eoa_win_export_smoke.sh` does the release export:

1. Wait until `pgrep -af run_godot` is empty. Poll every 60 seconds. Never kill a Godot process.
2. Take `flock ~/.eoa_godot.lock` for the export, so only one Godot runs.
3. Create a fresh non-empty `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` for that run.
4. `mkdir -p "$XDG_DATA_HOME/godot/export_templates"` and symlink `4.7.1.stable` to `$HOME/.local/share/godot/export_templates/4.7.1.stable`.
5. Write `export/windows/rcedit` into the fresh `$XDG_CONFIG_HOME/godot/editor_settings-4.7.tres`, pointing at the host-local `rcedit-x64.exe`.
6. `mkdir -p build/windows` and run:

```bash
tools/run_godot.sh --headless --path . --export-release "Windows Desktop" build/windows/EpochsOfAscendancy.exe
```

The smoke passes only when the process exits 0, `file` reports PE32+ x86-64, the last 4 bytes of the exe are `GDPC` (embedded PCK, same trailer check as #156), there is no sibling `.pck` and no `.dll`, and the exe is between 300 MiB and 800 MiB. A console wrapper named `EpochsOfAscendancy.console.exe` is allowed. The exe must contain the UTF-16 metadata strings `Epochs of Ascendancy`, `Featherstone Ops`, and `0.1.0.0`.

Known post-savepack editor-exit lines are allow-listed: resources still in use, DummyTexture RID leaks, invalid-UID warnings, and ObjectDB or CanvasItem leaks. The smoke fails on `SCRIPT ERROR`, a missing export template, a failed pack, or a missing exe.

## Symlink rule

The export-template directory is a symlink into the existing Godot templates. Do not copy it. Do not write or delete anything under `~/.local/share/godot`, including `app_userdata`. Do not edit the real `~/.config/godot/editor_settings-4.7.tres`. The rcedit path lives only in the fresh XDG editor settings for that run. Do not store it under `~/.local/share/godot`.

## rcedit

Host-local only. Not committed. Official GitHub release asset, not a mirror, the AUR, or `node-rcedit`.

| Field | Value |
|-------|--------|
| Tag | v2.0.0 (latest official `rcedit-x64.exe` as of this slice) |
| URL | https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe |
| Path | `~/Applications/rcedit/rcedit-x64.exe` |
| Bytes | 1360384 |
| sha256 | `3e7801db1a5edbec91b49a24a094aad776cb4515488ea5a4ca2289c400eade2a` |

Wine is already installed (`/usr/bin/wine`, package `wine 11.22`). Do not install packages to satisfy rcedit.

## Preset metadata

`export_presets.cfg`, preset `Windows Desktop`:

| Key | Value |
|-----|--------|
| `application/icon` | `res://icon.ico` |
| `application/product_name` | Epochs of Ascendancy |
| `application/company_name` | Featherstone Ops |
| `application/file_description` | Epochs of Ascendancy |
| `application/file_version` | `0.1.0.0` |
| `application/product_version` | `0.1.0.0` |
| `application/modify_resources` | true |
| `application/export_d3d12` | 0 |
| `codesign/enable` | false |
| `binary_format/embed_pck` | true |
| `binary_format/architecture` | x86_64 |

`icon.ico` is a 16, 32, 48, and 256 image generated from `icon.svg` with ImageMagick `magick`. `project.godot` keeps `config/icon="res://icon.svg"` and sets `config/version="0.1.0"`. That starting version is `0.1.0.0` in the preset. Do not commit `icon.ico.import` or other Godot import sidecars.

## Rendering fallbacks

`project.godot` `[rendering]` only:

```
rendering_device/driver.windows="d3d12"
rendering_device/fallback_to_vulkan=true
rendering_device/fallback_to_opengl3=true
```

`driver.windows` stays `d3d12`. Do not enable `application/export_d3d12`. Do not add D3D12 agility DLLs. Agility is out of scope.

## Exclude list

`exclude_filter` still drops tests, scratch, build, and `*.cs`. This slice adds:

| Pattern | Why |
|---------|-----|
| `godot_state_charts_examples/*` | Addon demos. Nothing on the game boot path references them. #156 packed them and logged invalid-UID warnings. Replaces the narrower `csharp/*` pattern. |
| `tools/*` | Map-generation fixtures and `tools/map_generation/data/cache/` (gitignored). Runtime opens of those JSON files are debug or `FileAccess.file_exists` sample loads, and proposed-split load runs only in a debug build. A release boot does not need the tree. Keeps a dirty worktree from packing the cache. |
| `data/hierarchy_samples/*` | No game script, scene, or JSON opens this directory. Python map-generation tests read it from the repo, not from the PCK. |

Left in the pack on purpose:

| Path | Why it stays |
|------|----------------|
| `data/provinces_world_accurate` | Default board. Never exclude. |
| `data/provinces_pilot_*`, `data/provinces_phase1_test`, `data/provinces_full_europe`, `data/provinces_grand_theater` | Scenario JSON `use_province_data_dir` and `ScenarioLoader` can open them when that scenario is selected. `MapManager` also falls back to `provinces_phase1_test` for sea-zone theaters before a scenario dir is set. In doubt, they stay. |
| `assets/maps` | Bulk of the exe. Do not trim map textures. |

Export from a clean worktree. This exclude list will not make the exe small.

## Do not commit `build/`

`build/`, the staged zip, and XDG editor-settings files stay uncommitted. `build/` is gitignored. Do not commit the exe.

## Staged zip

After a green smoke, zip the release exe plus a one-page README to:

`~/eoa_win_build_1/EpochsOfAscendancy_<sha8>_win64.zip`

Write `md5` and `sha256` of the zip and of the exe next to it. Drive folder name is **EOA Windows Builds**. OP uploads after KEEP. This slice does not upload.

Release exe from the smoke on this slice (filled after the run):

| Field | Value |
|-------|--------|
| Path | `build/windows/EpochsOfAscendancy.exe` (not committed) |
| Bytes | 505494040 |
| sha256 | `3df4ef564d7dfffe804698ae19e0536e27f2281b6f166ab4d5232a98f3dd64db` |
| file(1) | PE32+ executable for MS Windows 5.02 (GUI), x86-64, 12 sections |
| GDPC | last 4 bytes |
| Sibling .pck / .dll | none |

Godot also warned that icon sizes 64 and 128 are missing. The ico still has the required 16, 32, 48, and 256 images, and the exe carries the product metadata. Those two size warnings are not a pack failure.

## Wine boot is not a real Windows test

A wine launch of `build/windows/EpochsOfAscendancy.exe` for up to 30 seconds is only a weak proxy. PASS means wine ran for 30 seconds, or reached a title-screen / `LivingTitleBoot` log line, without a crash, `SCRIPT ERROR`, segfault, unhandled exception, or fatal error. It does not mean the game boots on Windows. A real Windows boot waits for Mike or his dad on their own time. Do not ping them. If wine cannot start the exe, the result is INCONCLUSIVE, not a product FAIL. Do not install packages to make wine happier.

A debug export is optional and is not required for the zip.
