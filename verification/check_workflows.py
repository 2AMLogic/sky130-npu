#!/usr/bin/env python3
"""Parse every GitHub Actions workflow file with a real YAML parser.

A workflow that cannot parse produces no check-runs at all, so every
presence-based CI gate reports green while its checks are simply absent.
This checker makes that failure loud: it loads each ``*.yml`` and
``*.yaml`` file in ``.github/workflows/`` with a real YAML parser (PyYAML,
never a regex or a hand-rolled reader) and exits non-zero on the first
file that fails, naming it with the parser's line and column.

A workflow file must contain a mapping, and one that GitHub will actually
start, so three shape failures are rejected with their own messages: an
empty document (``empty document (no YAML content)``); a document that
parses to a non-mapping such as a bare string or list (``top-level YAML is
<type>, not a mapping``); and any mapping that repeats a key. PyYAML
resolves a repeated key last-wins without complaint, which silently drops
every real job from a duplicated ``jobs:`` block, while GitHub refuses to
start such a workflow at all (measured: run 43733724749 on #185's probe PR
produced zero jobs) -- so the loader raises ``DuplicateKeyError`` naming
the repeated key and its line. The check applies at every nesting level,
including keys inside a job.

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


class DuplicateKeyError(yaml.YAMLError):
    """A mapping repeats a key; carries the mark for the checker's reporter."""

    def __init__(self, key, mark):
        super().__init__(f"duplicate mapping key {key!r}")
        self.problem_mark = mark


class StrictLoader(yaml.SafeLoader):
    """SafeLoader that refuses a mapping which repeats a key.

    ``yaml.safe_load`` resolves a repeated key last-wins, so a duplicated
    ``jobs:`` block parses to a document whose ``jobs`` holds only the
    impostor while the checker stays green; GitHub instead startup-fails the
    workflow with zero jobs. Refuse at every nesting level so the checker
    matches the real-world stricter side.
    """

    def construct_mapping(self, node, deep=False):
        seen = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            try:
                duplicate = key in seen
                seen.add(key)
            except TypeError:
                continue  # unhashable key; SafeLoader reports it as it does today
            if duplicate:
                raise DuplicateKeyError(key, key_node.start_mark)
        return super().construct_mapping(node, deep=deep)


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
                data = yaml.load(stream, Loader=StrictLoader)
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
        if not isinstance(data, dict):
            print(
                f"FAIL {path}: top-level YAML is {type(data).__name__}, not a mapping",
                file=sys.stderr,
            )
            return 1
        print(f"ok {path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
