"""Unit tests for ``runner.count_results`` (the ledger's ``tests``/``failures``).

A ``--testcase`` / ``TESTCASE`` filter does not remove the unselected tests
from cocotb's results XML: it writes them as ``<testcase>`` elements carrying a
``<skipped>`` child (cocotb 2.0.1, ``cocotb/_xunit_reporter.py``). Counting
those as tests that ran overstates a recorded result, so ``count_results``
excludes them. These tests pin that down against fixture XML; no simulator and
no DUT are involved.

Plain ``unittest`` (no extra dependency), but ``runner.py`` imports cocotb at
module top, so run it from an environment that has cocotb installed:
``.venv/bin/python -m unittest discover -s verification/tests -p 'test_runner_count.py'``.
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from verification.runner import count_results  # noqa: E402


def write_xml(body):
    """A results XML file holding ``body``; returns its path."""
    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".xml", delete=False, encoding="utf-8")
    tmp.write(f'<?xml version="1.0" encoding="UTF-8"?>\n'
              f'<testsuites name="results">\n'
              f'  <testsuite name="all" package="all">\n{body}\n'
              f'  </testsuite>\n'
              f'</testsuites>\n')
    tmp.close()
    return tmp.name


def case(name, child=None):
    """One ``<testcase>``, optionally carrying a single child element."""
    if child is None:
        return f'    <testcase name="{name}" classname="test_mod"/>'
    return (f'    <testcase name="{name}" classname="test_mod">\n'
            f'      <{child} message="m"/>\n'
            f'    </testcase>')


class CountResults(unittest.TestCase):
    def count(self, body):
        path = write_xml(body)
        self.addCleanup(Path(path).unlink, True)
        return count_results(path)

    def test_mixed_passed_failed_errored_and_skipped(self):
        """Skipped cases count as neither tests nor failures."""
        body = "\n".join([
            case("test_a"),
            case("test_b", "failure"),
            case("test_c", "error"),
            case("test_d", "skipped"),
            case("test_e", "skipped"),
            case("test_f"),
        ])
        self.assertEqual(self.count(body), (4, 2))

    def test_all_skipped_is_zero_tests(self):
        """A filter that matches nothing records no tests, not a full suite."""
        body = "\n".join(case(f"test_{i}", "skipped") for i in range(5))
        tests, failures = self.count(body)
        self.assertEqual((tests, failures), (0, 0))
        # The ledger's `passed` rule (runner.main); a vacuous run is not a pass.
        self.assertFalse(tests > 0 and failures == 0)

    def test_filtered_run_counts_only_the_selected_case(self):
        """The #128 shape: 1 of 11 selected records tests == 1, not 11."""
        body = "\n".join(
            [case("test_workload_mm_smoke")]
            + [case(f"test_other_{i}", "skipped") for i in range(10)])
        self.assertEqual(self.count(body), (1, 0))

    def test_unfiltered_run_counts_the_whole_suite(self):
        """No skips: the pre-existing counting behaviour is unchanged."""
        body = "\n".join(case(f"test_{i}") for i in range(11))
        self.assertEqual(self.count(body), (11, 0))

    def test_empty_suite_is_zero_tests(self):
        self.assertEqual(self.count("    <!-- no cases -->"), (0, 0))


if __name__ == "__main__":
    unittest.main()
