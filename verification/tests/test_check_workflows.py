"""Tests for ``verification/check_workflows.py``, the workflow shape checker.

Exercises the checker's document-shape contract: a workflow file must hold a
mapping that GitHub will actually start. Covered here are the three shape
failures the checker rejects -- an empty document, a document that parses to
a non-mapping (``str``, ``list``, and the falsy-but-not-``None`` ``0`` and
``False``, which must fail as a non-mapping and not be mistaken for the
empty case), and a repeated mapping key. The duplicate-key rejection exists
because PyYAML resolves a repeated key last-wins -- silently deleting every
real job from a duplicated ``jobs:`` block -- while GitHub refuses to start
such a workflow at all; that GitHub-side behaviour was measured live
(issue #185, run 43733724749: zero jobs, startup failure), and this suite
pins the checker to match it. The loader refuses duplicates at every nesting
level, so a duplicate key inside a job is covered too.

Test shape, and why it is odd: PyYAML is importable on a developer host but
absent from ``verification/requirements.txt``, so this file must not
``import yaml`` -- and neither may the code under test be imported, since
``check_workflows.py`` imports ``yaml`` itself. The checker resolves its
workflows directory from ``__file__``, not cwd, so pointing it at a fixture
by changing directory is impossible. Each test therefore copies the checker
into a ``tempfile`` tree mirroring ``<tmp>/verification/`` +
``<tmp>/.github/workflows/``, writes fixture workflow files there, and runs
the copy as a subprocess under ``uv run --with pyyaml==6.0.3``, asserting on
exit code, stdout and stderr. This is exactly how both defect cases were
measured during #185's review.

Standard library only: no cocotb and no YAML parser runs in this test
process; PyYAML exists only inside the uv-managed subprocess environment.
"""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CHECKER = REPO / "verification" / "check_workflows.py"

VALID_WORKFLOW = """\
name: probe

on: push

permissions:
  contents: read

jobs:
  probe:
    runs-on: ubuntu-24.04
    steps:
      - name: probe
        run: "true"

"""

# The second top-level `jobs:` key sits on line 15 (1-based), column 1.
DUPLICATE_JOBS_WORKFLOW = """\
name: probe

on: push

permissions:
  contents: read

jobs:
  probe:
    runs-on: ubuntu-24.04
    steps:
      - name: probe
        run: "true"

jobs:
  dup-probe:
    runs-on: ubuntu-24.04
    steps:
      - name: impostor
        run: "true"

"""

# A repeated key nested inside a job: `steps:` appears twice under `probe`.
DUPLICATE_NESTED_KEY_WORKFLOW = """\
name: probe

on: push

permissions:
  contents: read

jobs:
  probe:
    runs-on: ubuntu-24.04
    steps:
      - name: probe
        run: "true"
    steps:
      - name: impostor
        run: "true"

"""


class CheckWorkflowsTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / "verification").mkdir()
        (self.root / ".github" / "workflows").mkdir(parents=True)
        shutil.copy(CHECKER, self.root / "verification" / "check_workflows.py")

    def write_workflow(self, name, text):
        (self.root / ".github" / "workflows" / name).write_text(text)

    def run_checker(self):
        return subprocess.run(
            [
                "uv", "run", "--with", "pyyaml==6.0.3",
                "python", str(self.root / "verification" / "check_workflows.py"),
            ],
            capture_output=True,
            text=True,
            cwd=self.root,
            timeout=300,
        )

    def test_valid_workflow_passes_with_ok_per_file(self):
        self.write_workflow("probe.yml", VALID_WORKFLOW)
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("ok probe.yml", result.stdout)

    def test_yml_and_yaml_extensions_both_discovered(self):
        self.write_workflow("probe.yml", VALID_WORKFLOW)
        self.write_workflow("other.yaml", VALID_WORKFLOW)
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("ok probe.yml", result.stdout)
        self.assertIn("ok other.yaml", result.stdout)

    def test_empty_document_fails_with_its_own_message(self):
        self.write_workflow("probe.yml", "\n")
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("probe.yml", result.stderr)
        self.assertIn("empty document (no YAML content)", result.stderr)

    def test_scalar_document_fails_naming_the_type(self):
        self.write_workflow("probe.yml", "just a string\n")
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("probe.yml", result.stderr)
        self.assertIn("top-level YAML is str, not a mapping", result.stderr)

    def test_list_document_fails_naming_the_type(self):
        self.write_workflow("probe.yml", "- a\n- b\n")
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("probe.yml", result.stderr)
        self.assertIn("top-level YAML is list, not a mapping", result.stderr)

    def test_falsy_non_none_documents_fail_as_non_mapping_not_empty(self):
        for text, type_name in (("0\n", "int"), ("False\n", "bool")):
            with self.subTest(text=text):
                self.write_workflow("probe.yml", text)
                result = self.run_checker()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    f"top-level YAML is {type_name}, not a mapping",
                    result.stderr,
                )
                self.assertIn("probe.yml", result.stderr)
                self.assertNotIn("empty document", result.stderr)

    def test_duplicate_top_level_key_fails_naming_key_and_line(self):
        self.write_workflow("probe.yml", DUPLICATE_JOBS_WORKFLOW)
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate mapping key 'jobs'", result.stderr)
        self.assertIn("line 15, column 1", result.stderr)
        self.assertIn("probe.yml", result.stderr)

    def test_duplicate_nested_key_also_fails(self):
        self.write_workflow("probe.yml", DUPLICATE_NESTED_KEY_WORKFLOW)
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate mapping key 'steps'", result.stderr)


if __name__ == "__main__":
    unittest.main()
