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

Both subprocesses run from a directory that is not the repo root, so a relative
seam value that resolved against the cwd instead of the repo root would fail
here rather than pass by accident.

``runner.py`` imports cocotb at module top, so run this from an environment
that has cocotb installed:
``.venv/bin/python -m unittest discover -s verification/tests -p 'test_source_list.py'``.
"""

import json
import os
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


class SourceListAgrees(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
