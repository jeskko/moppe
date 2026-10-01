#!/usr/bin/env python3
"""
Run the emulator test suite one module per process, N at a time (default:
the CPU count), and print each module's result as it finishes; the output
of a failing module in full at the end.  Exit status 1 if any failed.

    python3 tools/ci/runtests.py            # all of tests/test_*.py
    python3 tools/ci/runtests.py -j 4 test_fsk test_scan_diff

The same tests as `python3 -m unittest discover -s tests`; the SAnE NV
cache is written atomically, so parallel modules may share it.
"""
import argparse
import concurrent.futures
import glob
import os
import re
import subprocess
import sys
import time

TESTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests")


def run(module):
    t0 = time.time()
    p = subprocess.run([sys.executable, "-m", "unittest", module], cwd=TESTS,
                       capture_output=True, text=True)
    ran = re.search(r"^Ran (\d+) test", p.stderr, re.M)
    return module, p.returncode, int(ran.group(1)) if ran else 0, time.time() - t0, p.stderr


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count())
    ap.add_argument("modules", nargs="*")
    a = ap.parse_args()
    mods = a.modules or sorted(os.path.basename(f)[:-3]
                               for f in glob.glob(os.path.join(TESTS, "test_*.py")))
    t0, total, failed = time.time(), 0, []
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
        for mod, rc, n, dt, err in ex.map(run, mods):
            total += n
            print("%-4s %-22s %4d tests %6.1f s" % ("ok" if rc == 0 else "FAIL", mod, n, dt),
                  flush=True)
            if rc:
                failed.append((mod, err))
    for mod, err in failed:
        print("\n==== %s\n%s" % (mod, err))
    print("\n%d tests in %d modules, %.0f s: %s" % (
        total, len(mods), time.time() - t0,
        "FAILED: " + " ".join(m for m, _ in failed) if failed else "OK"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
