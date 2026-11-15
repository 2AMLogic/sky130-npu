"""``runner.py``'s source list is the file set ``rtl/sources.sh`` emits.

``rtl/sources.sh`` is the single source of truth for which files are the design
and for the ``NPU_RTL_DIR`` / ``NPU_PDK_DIR`` seam, and every shell entry point
reads it. ``runner.py`` builds the same list in Python instead -- it is a cocotb
entry point and must not need a shell -- so the repo carries exactly two
implementations of the same rule, on purpose.

This test is what holds the second one to the first. It asks the shell library
for the file set, asks ``runner.py`` for its ``DEFAULT_SOURCES``, and compares
them: under the default layout, under a relocated layout given as absolute
paths, and under one given as paths relative to the repo root. It replaces the
``# Same source list and directory variables as rtl/check.sh.`` comment that
used to assert this by asking to be trusted.

The list is also held to the disk, which the runner comparison cannot see:
under a relocated copy of the RTL tree and the seam directory, the set of
``*.v`` files present must be exactly the set ``npu_rtl_files`` /
``npu_seam_file`` name, and a planted file no list names fails by name
(#174) -- an unlisted module must be a loud failure, never a silent omission
from a negative control that stages and compiles from the list.

Both subprocesses run from a directory that is not the repo root, so a relative
seam value that resolved against the cwd instead of the repo root would fail
here rather than pass by accident.

``runner.py`` imports cocotb at module top, so run this from an environment
that has cocotb installed:
``.venv/bin/python -m unittest discover -s verification/tests -p 'test_source_list.py'``.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SEAM_VARS = ("NPU_RTL_DIR", "NPU_PDK_DIR")

# The same question runner.py answers in Python, asked of the shell library.
LIB_QUERY = """
set -uo pipefail
REPO_ROOT="$1"
. "${REPO_ROOT}/rtl/sources.sh"
npu_seam_dirs
npu_rtl_files "${RTL_DIR}"
npu_seam_file "${PDK_DIR}"
"""

RUNNER_QUERY = (
    "import json;"
    " from verification.runner import DEFAULT_SOURCES;"
    " print(json.dumps(DEFAULT_SOURCES))"
)


def _env(overrides):
    """The ambient environment with the seam variables replaced, not merged."""
    env = {k: v for k, v in os.environ.items() if k not in SEAM_VARS}
    env.update(overrides)
    return env


def _norm(paths):
    """Comparable absolute paths (the two sides normalise differently)."""
    return [str(Path(p).resolve()) for p in paths]


class _SeamQuery(unittest.TestCase):
    """Asks the shell library and runner.py for the file set, from elsewhere."""

    def setUp(self):
        # Neither side may answer from the cwd; run both from somewhere else.
        self.elsewhere = tempfile.gettempdir()

    def lib_sources(self, **overrides):
        r = subprocess.run(
            ["bash", "-c", LIB_QUERY, "sources.sh", str(REPO)],
            env=_env(overrides), cwd=self.elsewhere,
            capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r.stdout.split()

    def runner_sources(self, **overrides):
        env = _env(overrides)
        env["PYTHONPATH"] = os.pathsep.join(
            [str(REPO)] + ([env["PYTHONPATH"]] if env.get("PYTHONPATH") else []))
        r = subprocess.run(
            [sys.executable, "-c", RUNNER_QUERY],
            env=env, cwd=self.elsewhere, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return json.loads(r.stdout)

    def assert_agree(self, **overrides):
        lib = self.lib_sources(**overrides)
        runner = self.runner_sources(**overrides)
        # Order matters: it is the order the tools read the files in.
        self.assertEqual(_norm(lib), _norm(runner))
        self.assertEqual([Path(p).name for p in lib],
                         [Path(p).name for p in runner])
        return lib


class SourceListAgrees(_SeamQuery):
    """The two implementations of the file set answer identically."""

    def test_default_layout(self):
        """With no seam variables set, both build this repo's own layout."""
        lib = self.assert_agree()
        # Not vacuous: the files are real, and the one in PDK_DIR is last.
        self.assertGreater(len(lib), 1)
        for path in lib:
            self.assertTrue(Path(path).is_file(), path)
        self.assertEqual([p for p in lib if Path(p).parent == REPO / "rtl"],
                         lib[:-1])
        self.assertEqual(Path(lib[-1]).parent, REPO / "rtl" / "pdk" / "sky130")

    def test_relocated_absolute(self):
        """Absolute seam values are used as given, by both implementations."""
        with tempfile.TemporaryDirectory() as tmp:
            rtl, pdk = Path(tmp) / "common", Path(tmp) / "elsewhere" / "seam"
            lib = self.assert_agree(NPU_RTL_DIR=str(rtl), NPU_PDK_DIR=str(pdk))
            # Neither side fell back to the defaults.
            self.assertEqual({str(Path(p).parent) for p in lib},
                             {str(rtl), str(pdk)})

    def test_relative_resolves_against_repo_root(self):
        """A relative seam value resolves against the repo root, not the cwd."""
        lib = self.assert_agree(NPU_RTL_DIR="rtl",
                                NPU_PDK_DIR="rtl/pdk/sky130")
        for path in lib:
            self.assertTrue(Path(path).is_file(), path)
            self.assertTrue(Path(path).resolve().is_relative_to(REPO), path)


class DiskSetMatchesList(_SeamQuery):
    """Every ``*.v`` on disk is a file the list names -- an orphan is loud.

    ``SourceListAgrees`` pins the two implementations to each other; neither
    comparison pins them to the disk. A module added as a file without being
    added to ``NPU_MODULES`` agrees with ``runner.py`` all the same, and a
    consumer that stages and compiles from the list (the mutation control,
    ``rtl/check.sh``) would leave it silently unexercised (#174). This is the
    disk-side half of the rule, and it is repo-wide, not one script's job:
    the list names every design file, so a planted ``.v`` file no list names
    is a named failure here.
    """

    def relocated_copy(self, tmp):
        """The repo's own rtl/ tree and seam dir, copied somewhere else."""
        rtl, pdk = Path(tmp) / "relocated-rtl", Path(tmp) / "relocated-seam"
        rtl.mkdir()
        pdk.mkdir()
        for src in (REPO / "rtl").glob("*.v"):
            shutil.copy(src, rtl / src.name)
        for src in (REPO / "rtl" / "pdk" / "sky130").glob("*.v"):
            shutil.copy(src, pdk / src.name)
        return rtl, pdk

    def disk_vs_list(self, rtl, pdk):
        """The on-disk and listed basename sets, per directory."""
        disk_rtl = {p.name for p in rtl.glob("*.v")}
        disk_pdk = {p.name for p in pdk.glob("*.v")}
        lib = self.lib_sources(NPU_RTL_DIR=str(rtl), NPU_PDK_DIR=str(pdk))
        # The seam file is the one entry outside the relocated RTL dir; no
        # entry may escape the two directories the seam variables named.
        list_rtl = {Path(p).name for p in lib if Path(p).parent == rtl}
        list_pdk = {Path(p).name for p in lib if Path(p).parent == pdk}
        self.assertEqual(
            len(lib), len(list_rtl) + len(list_pdk),
            f"entries outside the two relocated directories: {lib}")
        return disk_rtl, disk_pdk, list_rtl, list_pdk

    def assert_no_orphans(self, disk, listed, where):
        orphans = sorted(disk - listed)
        self.assertEqual(
            [], orphans,
            f".v files on disk that no list names in {where}: {orphans}")

    def test_disk_set_equals_list_set(self):
        """In a relocated copy, the on-disk *.v set is exactly the listed set."""
        with tempfile.TemporaryDirectory() as tmp:
            rtl, pdk = self.relocated_copy(tmp)
            disk_rtl, disk_pdk, list_rtl, list_pdk = self.disk_vs_list(rtl, pdk)
            # Not vacuous: the copies hold the design files.
            self.assertGreater(len(disk_rtl), 1)
            self.assertIn("npu_requant.v", disk_rtl)
            self.assertIn("npu_sram_bank.v", disk_pdk)
            self.assert_no_orphans(disk_rtl, list_rtl, str(rtl))
            self.assert_no_orphans(disk_pdk, list_pdk, str(pdk))

    def test_orphan_in_rtl_dir_is_a_named_failure(self):
        """A planted unlisted .v in the RTL copy is detected, and named."""
        with tempfile.TemporaryDirectory() as tmp:
            rtl, pdk = self.relocated_copy(tmp)
            (rtl / "npu_rogue.v").write_text("module npu_rogue();\nendmodule\n")
            disk_rtl, _, list_rtl, _ = self.disk_vs_list(rtl, pdk)
            self.assertEqual(sorted(disk_rtl - list_rtl), ["npu_rogue.v"])

    def test_orphan_in_seam_dir_is_a_named_failure(self):
        """A planted unlisted .v in the seam copy is detected, and named."""
        with tempfile.TemporaryDirectory() as tmp:
            rtl, pdk = self.relocated_copy(tmp)
            (pdk / "npu_rogue_bank.v").write_text(
                "module npu_rogue_bank();\nendmodule\n")
            _, disk_pdk, _, list_pdk = self.disk_vs_list(rtl, pdk)
            self.assertEqual(sorted(disk_pdk - list_pdk), ["npu_rogue_bank.v"])


if __name__ == "__main__":
    unittest.main()
