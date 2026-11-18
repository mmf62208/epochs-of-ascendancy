#!/usr/bin/env python3
"""SIM-1110-A-R FIX r3: product .gd must not read EOA_CAMPAIGN_LOOP via OS env.

Fails on r2 head 81b30cfa (BattleManager + TimeManager string-literal reads).
Passes when those product forks are gone. Harness tests (Headless*/Windowed*)
and tools/ may still set the env. WarStateDomain.loop_enabled keeps the
official loop killswitch via KILL_ENV (not a string-literal get_environment).
"""
from __future__ import annotations

import os
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
R2_HEAD = "81b30cfa0359742dec4c5efdf2468b0a824ea97e"
ENV_CALL_RE = re.compile(
    r"""OS\.(get_environment|has_environment)\s*\(\s*['\"]EOA_CAMPAIGN_LOOP['\"]"""
)
SKIP_DIR_PARTS = {"Headless", "Windowed"}
SKIP_NAMES = {"TestRunner.gd"}
SKIP_TOP = {"debug"}


def _is_product_gd_rel(rel: str) -> bool:
    if not rel.startswith("scripts/") or not rel.endswith(".gd"):
        return False
    name = Path(rel).name
    if name.startswith("Headless") or name.startswith("Windowed"):
        return False
    if name in SKIP_NAMES:
        return False
    parts = Path(rel).parts[1:]  # drop scripts/
    if parts and parts[0] in SKIP_TOP:
        return False
    for part in parts:
        if part in SKIP_DIR_PARTS:
            return False
    return True


def _is_product_gd(path: Path) -> bool:
    return _is_product_gd_rel(path.relative_to(ROOT).as_posix())


def env_fork_hits_in_text(rel: str, src: str) -> list[str]:
    hits: list[str] = []
    for i, line in enumerate(src.splitlines(), 1):
        if ENV_CALL_RE.search(line):
            hits.append("%s:%d:%s" % (rel, i, line.strip()))
    if rel == "scripts/combat/BattleManager.gd" and "EOA_CAMPAIGN_LOOP" in src:
        hits.append("%s:token:EOA_CAMPAIGN_LOOP" % rel)
    return hits


def product_env_fork_hits(root: Path) -> list[str]:
    hits: list[str] = []
    scripts = root / "scripts"
    if not scripts.is_dir():
        return ["missing scripts/"]
    for path in sorted(scripts.rglob("*.gd")):
        if not _is_product_gd(path):
            continue
        rel = path.relative_to(root).as_posix()
        hits.extend(env_fork_hits_in_text(rel, path.read_text(encoding="utf-8", errors="replace")))
    return hits


def product_env_fork_hits_at_rev(rev: str) -> list[str]:
    names = subprocess.check_output(
        ["git", "ls-tree", "-r", "--name-only", rev, "scripts"],
        cwd=str(ROOT),
        text=True,
    )
    hits: list[str] = []
    for rel in names.splitlines():
        rel = rel.strip()
        if not rel or not _is_product_gd_rel(rel):
            continue
        src = _git_show(rev, rel)
        hits.extend(env_fork_hits_in_text(rel, src))
    return hits


def _git_show(rev: str, rel: str) -> str:
    out = subprocess.check_output(
        ["git", "show", "%s:%s" % (rev, rel)],
        cwd=str(ROOT),
        text=True,
    )
    return out


class TestSim1110arNoCampaignLoopEnvFork(unittest.TestCase):
    def test_working_tree_has_no_eoa_campaign_loop_env_read(self) -> None:
        rev = os.environ.get("SIM1110AR_ENV_FORK_REV", "").strip()
        hits = product_env_fork_hits_at_rev(rev) if rev else product_env_fork_hits(ROOT)
        self.assertEqual(
            hits,
            [],
            msg="product .gd reads EOA_CAMPAIGN_LOOP via OS.get/has_environment:\n"
            + "\n".join(hits),
        )

    def test_r2_head_81b30cfa_still_reads_env(self) -> None:
        if not (ROOT / ".git").exists():
            self.skipTest(
                "no .git directory (codeload/tarball checkout); cannot git-show 81b30cfa"
            )
        try:
            probe = subprocess.run(
                ["git", "cat-file", "-e", R2_HEAD],
                cwd=str(ROOT),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        except OSError:
            self.skipTest("git is unavailable; cannot git-show 81b30cfa")
        if probe.returncode != 0:
            self.skipTest("81b30cfa is not reachable; skip r2 env-read regression")
        hits: list[str] = []
        try:
            for rel in (
                "scripts/combat/BattleManager.gd",
                "scripts/autoload/TimeManager.gd",
            ):
                src = _git_show(R2_HEAD, rel)
                hits.extend(env_fork_hits_in_text(rel, src))
        except (OSError, subprocess.SubprocessError):
            self.skipTest("git show 81b30cfa failed; skip r2 env-read regression")
        self.assertTrue(
            hits,
            msg="expected 81b30cfa product to still read EOA_CAMPAIGN_LOOP",
        )


if __name__ == "__main__":
    unittest.main()
