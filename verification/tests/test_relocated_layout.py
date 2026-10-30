"""The harness finds the RTL through NPU_RTL_DIR / NPU_PDK_DIR, not fixed paths.

Copies the RTL into a layout that matches neither default (a ``common/``
directory and an unrelated, non-nested seam directory), then runs
``rtl/check.sh`` against it. A wrong variable must fail, so the pass is not the
defaults answering by accident.
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CHECK = REPO / "rtl" / "check.sh"


@unittest.skipUnless(shutil.which("iverilog") and shutil.which("yosys"),
                     "needs iverilog and yosys on PATH")
class RelocatedLayout(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.common = self.tmp / "common"
        self.seam = self.tmp / "elsewhere" / "seam"
        self.common.mkdir()
        self.seam.mkdir(parents=True)
        for f in (REPO / "rtl").glob("*.v"):
            shutil.copy(f, self.common)
        for f in (REPO / "rtl" / "pdk" / "sky130").glob("*.v"):
            shutil.copy(f, self.seam)

    def run_check(self, rtl, pdk):
        env = {k: v for k, v in os.environ.items()
               if k not in ("NPU_RTL_DIR", "NPU_PDK_DIR")}
        env.update(NPU_RTL_DIR=str(rtl), NPU_PDK_DIR=str(pdk))
        return subprocess.run([str(CHECK), "4"], env=env, cwd=self.tmp,
                              capture_output=True, text=True)

    def test_relocated_absolute(self):
        r = self.run_check(self.common, self.seam)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("synthesis view (npu_sram_bank_bb.v) elaborates", r.stdout)

    def test_relocated_relative_resolves_against_repo_root(self):
        rel = Path(os.path.relpath(self.common, REPO)), Path(os.path.relpath(self.seam, REPO))
        r = self.run_check(*rel)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_missing_seam_fails(self):
        r = self.run_check(self.common, self.tmp / "nope")
        self.assertNotEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
