#!/usr/bin/env python3
"""
Run the emulator test suite one module per process, N at a time (default:
the CPU count), and print each module's result as it finishes; the output
of a failing module in full at the end.  Exit status 1 if any failed.

    python3 tools/ci/runtests.py            # every suite: tests/*/test_*.py
    python3 tools/ci/runtests.py r58        # one suite (a directory of tests/)
    python3 tools/ci/runtests.py -j 4 test_fsk test_scan_diff   # modules by name

Arguments are suite names (r58, r40) or test module names, which are looked
up in whichever suite holds them.  Each module runs with its own suite
directory as the working directory.  The SAnE NV cache (tests/r58/.cache)
is written atomically, so parallel modules may share it.
"""
import argparse
import concurrent.futures
import glob
import os
import re
import subprocess
import sys
import time

TESTS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      "..", "..", "tests"))


def suites():
    return sorted(d for d in os.listdir(TESTS) if os.path.isdir(os.path.join(TESTS, d))
                  and glob.glob(os.path.join(TESTS, d, "test_*.py")))


def modules_of(suite):
    return [(suite, os.path.basename(f)[:-3])
            for f in sorted(glob.glob(os.path.join(TESTS, suite, "test_*.py")))]


def resolve(arg):
    """A suite name -> all its modules; a module name -> [(suite, module)]."""
    if arg in suites():
        return modules_of(arg)
    arg = arg[:-3] if arg.endswith(".py") else arg
    found = [(s, arg) for s in suites()
             if os.path.exists(os.path.join(TESTS, s, arg + ".py"))]
    if not found:
        sys.exit("runtests: no suite or test module '%s' (suites: %s)" % (arg, " ".join(suites())))
    return found


def run(item):
    suite, module = item
    t0 = time.time()
    p = subprocess.run([sys.executable, "-m", "unittest", module],
                       cwd=os.path.join(TESTS, suite),
                       capture_output=True, text=True)
    ran = re.search(r"^Ran (\d+) test", p.stderr, re.M)
    return item, p.returncode, int(ran.group(1)) if ran else 0, time.time() - t0, p.stderr


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count())
    ap.add_argument("what", nargs="*", help="suite (r58, r40) or test module names")
    a = ap.parse_args()
    mods = [m for w in a.what for m in resolve(w)] if a.what else \
        [m for s in suites() for m in modules_of(s)]
    t0, total, failed = time.time(), 0, []
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
        for (suite, mod), rc, n, dt, err in ex.map(run, mods):
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
