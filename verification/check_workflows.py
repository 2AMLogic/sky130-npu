#!/usr/bin/env python3
"""Parse every GitHub Actions workflow file with a real YAML parser.

A workflow that cannot parse produces no check-runs at all, so every
presence-based CI gate reports green while its checks are simply absent.
This checker makes that failure loud: it loads each ``*.yml`` and
``*.yaml`` file in ``.github/workflows/`` with ``yaml.safe_load`` (PyYAML,
never a regex or a hand-rolled reader) and exits non-zero on the first
file that fails, naming it with the parser's line and column. An empty
document is a failure too: a workflow file must contain a mapping, never
nothing.

The workflows directory is resolved from this file's location, so the
checker runs from any cwd. PyYAML is not a repo dependency; invoke it
through uv in both workflows, so each workflow is validated by at least
one *other* workflow:

  uv run --with pyyaml==6.0.3 python verification/check_workflows.py
"""

import sys
from pathlib import Path

import yaml

WORKFLOWS_DIR = Path(__file__).resolve().parents[1] / ".github" / "workflows"


def main() -> int:
    files = sorted(
        set(WORKFLOWS_DIR.glob("*.yml")) | set(WORKFLOWS_DIR.glob("*.yaml"))
    )
    if not files:
        print(f"check_workflows: no *.yml/*.yaml files in {WORKFLOWS_DIR}", file=sys.stderr)
        return 1
    for path in files:
        try:
            with path.open(encoding="utf-8") as stream:
                data = yaml.safe_load(stream)
        except (OSError, UnicodeDecodeError) as e:
            print(f"FAIL {path}: cannot read: {e}", file=sys.stderr)
            return 1
        except yaml.YAMLError as e:
            mark = getattr(e, "problem_mark", None)
            if mark is not None:
                where = f"line {mark.line + 1}, column {mark.column + 1}"
            else:
                where = "no location given by the parser"
            print(f"FAIL {path}: {where}: {e}", file=sys.stderr)
            return 1
        if data is None:
            print(f"FAIL {path}: empty document (no YAML content)", file=sys.stderr)
            return 1
        print(f"ok {path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
