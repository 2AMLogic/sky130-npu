"""CI parity: ``verification/check-all.sh`` mirrors ``verification.yml``.

``check-all.sh`` exists so the canonical gate runs locally in one command; its
header documents the workflow as canonical and says the step list is kept in
step by hand. This test turns the step list itself into something checked
instead of hand-synced: it parses the ``run:`` blocks of
``.github/workflows/verification.yml`` and the ``step`` invocations of
``verification/check-all.sh`` and asserts the two sets are equal, so a step
added to one side and not the other fails naming that step -- the #163 defect
class (a gate named for the full set, running a subset) becomes detectable
instead of silent.

What counts as a mirrored step: a ``run:`` command is a step iff it is

- a ``python``/``python3``/``.venv/bin/python``/``${PY}`` invocation of
  ``-m unittest discover -s verification/tests -p '<pattern>'``,
- an ``EXPECT_ICARUS=<ver> <python> verification/runner.py --param
  ARRAY_N=<n>`` invocation,
- a ``check_mutation.sh <n>`` invocation,
- an ``rtl/check.sh`` invocation, or
- a ``uv run [--with <spec>]... python verification/check_workflows.py``
  invocation -- the workflow-parse guard, run through uv with PyYAML as CI
  runs it.

Everything else in the workflow (apt-get, the Icarus build, venv and pip
setup, PATH exports, and verification.yml's uv-wrapped run of the checker's
own test suite, which the local gate does not run -- each of its tests
spawns a uv subprocess, so check-all.sh runs the checker itself and leaves
its test suite to CI) is plumbing and is ignored. Every ``step`` in
check-all.sh must classify, since that script has no plumbing; an
unclassifiable step fails the test.

Equality is set equality (a ``collections.Counter`` comparison), not order:
the sides run the same steps in the same order today, but a reordered-yet-
equal set is not the drift this test pins. Two differences are deliberate and
documented in check-all.sh's header rather than treated as drift, and the
test fails if either disappears from that rationale: ``check_mutation_gl.sh``
is absent from the gate (PDK-specific), and the script runs every step after
an earlier failure (where CI's shell aborts the job) -- the latter pinned
structurally by requiring no ``errexit`` and the final ``exit "${FAIL}"``.

Step attributes are compared too, so both sides must agree on the details:
the ``runner.py`` steps pin ``EXPECT_ICARUS=13.0`` on both sides, and the
``test_relocated_layout.py`` seam test runs under ``python3 -I`` on both.

Standard library only, no cocotb and no YAML parser: the ``golden`` job that
runs this test installs nothing (checkout + setup-python), and
``rtl-elaborate`` runs its tests under ``python3 -I``, which ignores user
site-packages. PyYAML is importable on a developer host but absent from
``verification/requirements.txt``, so ``import yaml`` would pass locally and
fail in CI; the workflow is parsed as text with ``re`` and ``shlex`` instead
-- its ``run:`` lines are literal shell one-liners, which is why that is
tractable. The test only reads two files off disk and resolves them from
``__file__``, so it runs from any cwd and under ``python3 -I``.

Text parsing cannot establish that the file it walks is a workflow GitHub
will accept, but ``check-all.sh`` now runs the real YAML parse
(``verification/check_workflows.py`` through uv, step 7 in its header) as
CI does, so that gap is closed by the gate itself rather than by a regex
here. The errexit guard is sign-aware: a ``-`` flag cluster containing
``e`` enables errexit wherever the letter sits (``-euo`` as much as
``-e``), while a ``+`` cluster disables it and is fine.
"""

import re
import shlex
import unittest
from collections import Counter
from dataclasses import dataclass

from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WORKFLOW = REPO / ".github" / "workflows" / "verification.yml"
GATE = REPO / "verification" / "check-all.sh"

RUN_KEY_RE = re.compile(r"^(?P<indent>[ \t]*)run:(?P<rest>.*)$")
BLOCK_INDICATORS = ("|", "|-", "|+", ">", ">-", ">+")
ENV_PAIR_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=.*")
STEP_CALL_RE = re.compile(r'^\s*step\s+"(?P<name>[^"]*)"\s*(?P<rest>.*)$')
ARRAY_N_RE = re.compile(r"ARRAY_N=\d+$")


@dataclass(frozen=True)
class Step:
    """One mirrored gate step; equality covers the pins that must match."""

    kind: str  # unittest | runner | mutation | rtl-check | check-workflows
    detail: str  # -p pattern / ARRAY_N=n / mutation size / ""
    isolated: bool = False  # interpreter runs with -I
    expect_icarus: str | None = None  # EXPECT_ICARUS= prefix on the command

    def label(self) -> str:
        parts = [self.kind, self.detail]
        extras = []
        if self.isolated:
            extras.append("python -I")
        if self.expect_icarus is not None:
            extras.append(f"EXPECT_ICARUS={self.expect_icarus}")
        if extras:
            parts.append("(" + ", ".join(extras) + ")")
        return " ".join(parts)


def is_python_interpreter(token: str) -> bool:
    if token in ("${PY}", "${PYTHON}"):
        return True
    return token.split("/")[-1] in ("python", "python3")


def parse_step(command: str):
    """Classify one shell command line; None = workflow plumbing, not a step."""
    tokens = shlex.split(command)
    env = {}
    i = 0
    if tokens and tokens[0] == "env":
        i = 1
    while i < len(tokens) and ENV_PAIR_RE.fullmatch(tokens[i]):
        key, _, value = tokens[i].partition("=")
        env[key] = value
        i += 1
    rest = tokens[i:]
    if not rest:
        return None
    if rest[:2] == ["uv", "run"]:
        # The uv wrapper is environment plumbing, not a step boundary, but
        # only the checker invocation behind it is a mirrored step: any
        # other uv payload stays unmirrored plumbing (see the module
        # docstring). Only ``--with`` is unwrapped -- the one uv option the
        # workflows use -- so an unknown uv invocation keeps today's
        # plumbing classification instead of guessing.
        rest = rest[2:]
        while len(rest) >= 2 and rest[0] == "--with":
            rest = rest[2:]
        if (
            len(rest) == 2
            and is_python_interpreter(rest[0])
            and rest[1] == "verification/check_workflows.py"
        ):
            return Step("check-workflows", "")
        return None
    exe, args = rest[0], rest[1:]
    if exe.endswith("/check_mutation.sh"):
        if len(args) == 1 and args[0].isdigit():
            return Step("mutation", args[0])
        return Step("unrecognized", command)
    if exe.endswith("/rtl/check.sh"):
        if not args:
            return Step("rtl-check", "")
        return Step("unrecognized", command)
    if is_python_interpreter(exe):
        isolated = False
        if args and args[0] == "-I":
            isolated = True
            args = args[1:]
        if (
            len(args) == 7
            and args[:6]
            == ["-m", "unittest", "discover", "-s", "verification/tests", "-p"]
        ):
            return Step(
                "unittest", args[6], isolated=isolated,
                expect_icarus=env.get("EXPECT_ICARUS"),
            )
        if (
            len(args) == 3
            and args[0] == "verification/runner.py"
            and args[1] == "--param"
            and ARRAY_N_RE.fullmatch(args[2])
        ):
            return Step("runner", args[2], expect_icarus=env.get("EXPECT_ICARUS"))
    return None


def workflow_commands(text):
    """Each shell command line found in the workflow's ``run:`` keys."""
    commands = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        match = RUN_KEY_RE.match(lines[i])
        if not match:
            i += 1
            continue
        rest = match.group("rest").strip()
        if rest in BLOCK_INDICATORS:
            run_indent = len(match.group("indent"))
            i += 1
            while i < len(lines):
                line = lines[i]
                if line.strip() and (len(line) - len(line.lstrip())) <= run_indent:
                    break
                if line.strip():
                    commands.append(line.strip())
                i += 1
        elif rest:
            commands.append(rest)
            i += 1
        else:
            i += 1
    return commands


def gate_steps(text):
    """Each ``step "<name>"`` invocation as (name, classified command).

    A None classification means the step's command is not a recognized shape;
    the gate has no plumbing, so the caller treats that as a failure.
    """
    steps = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        match = STEP_CALL_RE.match(lines[i])
        if not match:
            i += 1
            continue
        name = match.group("name")
        command = match.group("rest").strip()
        while command.endswith("\\"):
            command = command[:-1].rstrip()
            i += 1
            if i >= len(lines):
                raise AssertionError(
                    f'step "{name}": continuation runs off the end of check-all.sh'
                )
            command = (command + " " + lines[i].strip()).strip()
        steps.append((name, parse_step(command) if command else None))
        i += 1
    return steps


def errexit_findings(text):
    """Every ``set`` line in the text that would enable errexit.

    Sign-aware: a ``-`` flag cluster enables errexit if it contains ``e``
    anywhere (bash parses cluster flags letter by letter, so ``-euo``
    enables exactly what ``-e`` does), while a ``+`` cluster disables it
    and is fine, and ``-o errexit`` goes through the option branch.
    """
    problems = []
    for number, line in enumerate(text.splitlines(), start=1):
        match = re.match(r"\s*set\s+(.*?)(?:\s*#.*)?$", line)
        if not match:
            continue
        previous_option = False
        for token in match.group(1).split():
            if token == "-o":
                previous_option = True
                continue
            if previous_option and token == "errexit":
                problems.append(
                    f"line {number}: {line.strip()!r} -- the gate must "
                    "run every step after an earlier failure"
                )
            previous_option = False
            if re.fullmatch(r"-[A-Za-z]*e[A-Za-z]*", token):
                problems.append(
                    f"line {number}: sets errexit ({token}): "
                    f"{line.strip()!r} -- the gate must run every step "
                    "after an earlier failure"
                )
    return problems


class CheckAllParity(unittest.TestCase):
    """check-all.sh's step set must equal verification.yml's."""

    @classmethod
    def setUpClass(cls):
        cls.workflow_text = WORKFLOW.read_text(encoding="utf-8")
        cls.gate_text = GATE.read_text(encoding="utf-8")
        cls.workflow_steps = [
            step
            for command in workflow_commands(cls.workflow_text)
            if (step := parse_step(command)) is not None
        ]
        # The gate has no plumbing, so an unclassifiable step is a defect
        # surfaced under its own name rather than silently dropped.
        cls.gate_steps = [
            step or Step("unrecognized", f'step "{name}" command did not classify')
            for name, step in gate_steps(cls.gate_text)
        ]

    def test_step_sets_match(self):
        """Every workflow step is mirrored by the gate, and vice versa."""
        workflow_counts = Counter(self.workflow_steps)
        gate_counts = Counter(self.gate_steps)
        missing = workflow_counts - gate_counts
        extra = gate_counts - workflow_counts
        problems = []
        if missing:
            names = ", ".join(sorted(step.label() for step in missing.elements()))
            problems.append(f"in verification.yml but missing from check-all.sh: {names}")
        if extra:
            names = ", ".join(sorted(step.label() for step in extra.elements()))
            problems.append(f"in check-all.sh but not in verification.yml: {names}")
        self.assertEqual(
            (dict(missing), dict(extra)),
            ({}, {}),
            "check-all.sh and verification.yml disagree on the gate's steps:\n"
            + "\n".join(problems),
        )

    def test_runner_steps_pin_expect_icarus(self):
        """Both runner.py steps pin EXPECT_ICARUS=13.0 (the Icarus pin)."""
        for side, steps in (("verification.yml", self.workflow_steps),
                            ("check-all.sh", self.gate_steps)):
            runners = [step for step in steps if step.kind == "runner"]
            self.assertTrue(
                runners, f"{side}: no runner.py step found"
            )
            for step in runners:
                self.assertEqual(
                    step.expect_icarus, "13.0",
                    f"{side}: {step.label()} must pin EXPECT_ICARUS=13.0",
                )

    def test_seam_test_runs_isolated(self):
        """The relocated-layout seam test runs under python3 -I on both sides."""
        for side, steps in (("verification.yml", self.workflow_steps),
                            ("check-all.sh", self.gate_steps)):
            seams = [
                step
                for step in steps
                if step.kind == "unittest" and step.detail == "test_relocated_layout.py"
            ]
            self.assertTrue(seams, f"{side}: no test_relocated_layout.py step found")
            for step in seams:
                self.assertTrue(
                    step.isolated,
                    f"{side}: {step.label()} must run the seam test under python3 -I",
                )

    def test_gate_documents_the_two_tolerated_differences(self):
        """The header must keep explaining what is deliberately not mirrored."""
        self.assertIn(
            "check_mutation_gl",
            self.gate_text,
            "check-all.sh must keep documenting that check_mutation_gl.sh is "
            "deliberately absent (PDK-specific, not in the workflow)",
        )
        self.assertIn(
            "Every step runs even after an earlier failure",
            self.gate_text,
            "check-all.sh must keep documenting that it runs every step after "
            "an earlier failure, where CI's shell aborts the job",
        )

    def test_gate_runs_every_step_after_a_failure(self):
        """No errexit anywhere, and the exit status carries the FAIL flag."""
        self.assertEqual(
            errexit_findings(self.gate_text),
            [],
            "check-all.sh must not set errexit: it must run every step "
            "after an earlier failure\n"
            + "\n".join(errexit_findings(self.gate_text)),
        )
        self.assertRegex(
            self.gate_text,
            r'(?m)^exit "\$\{FAIL\}"\s*$',
            "check-all.sh must exit with the accumulated FAIL flag",
        )

    def test_errexit_guard_catches_e_anywhere_in_a_minus_cluster(self):
        """``-euo``, ``-eo``, ``-euox`` enable errexit exactly like ``-e``.

        ``set -euo pipefail`` is the most likely way anyone would tighten
        the gate; the finding names the offending token and line.
        """
        for set_line in (
            "set -e",
            "set -eu",
            "set -eo pipefail",
            "set -euox",
            "set -euo pipefail",
        ):
            findings = errexit_findings(set_line + "\n")
            self.assertEqual(
                len(findings),
                1,
                f"{set_line!r} enables errexit and must produce exactly "
                f"one finding, got {findings}",
            )
            self.assertIn(set_line.split()[1], findings[0])

    def test_errexit_guard_ignores_plus_clusters_and_e_free_flags(self):
        """``+`` clusters disable errexit; ``-`` clusters without ``e`` are fine.

        ``set +e`` is the opposite of the defect, so flagging it would be a
        false positive; this pins the sign-awareness.
        """
        for set_line in (
            "set +e",
            "set +eu",
            "set +euo pipefail",
            "set -uo pipefail",
        ):
            self.assertEqual(
                errexit_findings(set_line + "\n"),
                [],
                f"{set_line!r} does not enable errexit",
            )

    def test_errexit_guard_keeps_the_o_option_branch(self):
        """``-o errexit`` still fails and ``+o errexit`` still passes."""
        findings = errexit_findings("set -o errexit\n")
        self.assertEqual(
            len(findings),
            1,
            f"set -o errexit enables errexit, got {findings}",
        )
        self.assertEqual(errexit_findings("set +o errexit\n"), [])


if __name__ == "__main__":
    unittest.main()
