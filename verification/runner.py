#!/usr/bin/env python3
"""cocotb + Icarus runner. Parameter-driven; nothing here names a DUT.

Defaults run the placeholder DUT. Every default can be overridden by an
argument or an environment variable, so a stamped copy needs no edits:

  python verification/runner.py
  python verification/runner.py --toplevel mydut --sources rtl/a.v rtl/b.v \
      --param WIDTH=16 --test-module test_smoke

Each run adds one record under ``verification/records/`` (append-only, see the
README there) and exits non-zero if any test failed.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

import cocotb
from cocotb_tools.runner import get_runner

HERE = Path(__file__).resolve().parent


def env(name, default):
    return os.environ.get(name, default)


def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument(
        "--toplevel",
        default=env("HDL_TOPLEVEL", "passthru"),
        help="top-level HDL module (env HDL_TOPLEVEL)",
    )
    p.add_argument(
        "--sources",
        nargs="+",
        default=env("HDL_SOURCES", str(HERE / "placeholder" / "passthru.v")).split(),
        help="HDL source files (env HDL_SOURCES, space-separated)",
    )
    p.add_argument(
        "--param",
        action="append",
        default=[],
        metavar="NAME=VALUE",
        help="top-level parameter, repeatable; also exported to the test env "
        "(env HDL_PARAMS, space-separated NAME=VALUE)",
    )
    p.add_argument(
        "--test-module",
        default=env("TEST_MODULE", "test_smoke"),
        help="Python test module under --test-dir (env TEST_MODULE)",
    )
    p.add_argument("--test-dir", default=env("TEST_DIR", str(HERE / "tests")))
    p.add_argument("--records-dir", default=env("RECORDS_DIR", str(HERE / "records")))
    p.add_argument("--build-dir", default=env("BUILD_DIR", str(HERE / "sim_build")))
    p.add_argument(
        "--expect-icarus",
        default=env("EXPECT_ICARUS", ""),
        help="fail unless `iverilog -V` mentions this version (env EXPECT_ICARUS)",
    )
    args = p.parse_args(argv)
    raw = args.param or env("HDL_PARAMS", "WIDTH=8").split()
    args.params = dict(kv.split("=", 1) for kv in raw)
    return args


def icarus_version():
    out = subprocess.run(
        ["iverilog", "-V"], capture_output=True, text=True, check=True
    ).stdout
    m = re.search(r"Icarus Verilog version [^\n]*", out)
    return m.group(0) if m else out.splitlines()[0] if out else "unknown"


def count_results(xml_path):
    tests = failures = 0
    for case in ET.parse(xml_path).getroot().iter("testcase"):
        tests += 1
        if case.find("failure") is not None or case.find("error") is not None:
            failures += 1
    return tests, failures


def write_record(records_dir, record):
    now = datetime.now(timezone.utc)
    rid = uuid.uuid4().hex[:8]
    rec_dir = Path(records_dir) / f"{now.strftime('%Y%m%dT%H%M%SZ')}-{rid}"
    rec_dir.mkdir(parents=True, exist_ok=False)
    record = {"id": rid, "utc": now.isoformat(), **record}
    with open(rec_dir / "record.json", "x") as f:  # "x": never overwrite
        json.dump(record, f, indent=2, sort_keys=True)
        f.write("\n")
    return rec_dir


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    version = icarus_version()
    if args.expect_icarus and args.expect_icarus not in version:
        sys.exit(f"Icarus mismatch: want {args.expect_icarus!r}, have {version!r}")

    runner = get_runner("icarus")
    runner.build(
        sources=[Path(s) for s in args.sources],
        hdl_toplevel=args.toplevel,
        parameters=args.params,
        build_dir=args.build_dir,
        always=True,
    )
    results_xml = runner.test(
        hdl_toplevel=args.toplevel,
        test_module=args.test_module,
        test_dir=args.test_dir,
        build_dir=args.build_dir,
        extra_env=dict(args.params),
    )
    tests, failures = count_results(results_xml)
    passed = tests > 0 and failures == 0
    rec_dir = write_record(
        args.records_dir,
        {
            "toplevel": args.toplevel,
            "sources": [os.path.relpath(s, HERE.parent) for s in args.sources],
            "parameters": args.params,
            "test_module": args.test_module,
            "cocotb": cocotb.__version__,
            "simulator": version,
            "passed": passed,
            "tests": tests,
            "failures": failures,
        },
    )
    print(f"record: {rec_dir}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
