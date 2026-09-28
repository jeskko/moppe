#!/usr/bin/env python3
"""
Mutation check for a C port (notes/hybrid-plan.md, "Safety net"): apply
each mutant (a source replacement) to a C module in turn, build `make C=1`
into firmware/build-mut, run the given tests against that build, and
report which mutants no test caught.  The module is restored afterwards,
also on errors or ^C.  Run from the repository root:

    python3 tools/mutate.py firmware/c/aprs.c mutants.py test_aprs_diff test_fsk.FskRx
    python3 tools/mutate.py firmware/c/aprs.c mutants.py test_aprs_diff --only 3 7

mutants.py defines MUTANTS = [(old, new), ...]; each `old` must occur
exactly once in the module.  The mutated build is passed to the tests as
the candidate/default ROM through every env variable the tests read
(R58_ROM/LST, R58_CAND_*, R58_RPTR_CAND_*, R58_GPS_CAND_*, R58_APRS_CAND_*),
so differential tests compare the asm build (reference) with the mutant.
A test that fails without any mutant makes every result meaningless:
run the tests on the unmutated build first.
"""
import argparse
import os
import runpy
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BUILD = "build-mut"
ENV_PREFIXES = ("R58", "R58_CAND", "R58_RPTR_CAND", "R58_GPS_CAND", "R58_APRS_CAND")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("module", help="C source, e.g. firmware/c/aprs.c")
    ap.add_argument("mutants", help="python file defining MUTANTS")
    ap.add_argument("tests", nargs="+", help="unittest names (run in emu/tests)")
    ap.add_argument("--only", type=int, nargs="*", help="mutant indexes to run")
    a = ap.parse_args()

    path = os.path.join(ROOT, a.module)
    orig = open(path).read()
    mutants = runpy.run_path(a.mutants)["MUTANTS"]
    rom = os.path.join(ROOT, "firmware", BUILD, "r58.bin")
    lst = os.path.join(ROOT, "firmware", BUILD, "r58.map")
    env = dict(os.environ)
    for p in ENV_PREFIXES:
        env[p + "_ROM"] = rom
        env[p + "_LST"] = lst
    survived = []
    try:
        for i, (old, new) in enumerate(mutants):
            if a.only and i not in a.only:
                continue
            if orig.count(old) != 1:
                print("%d: `%s` occurs %d times, skipped" % (i, old[:40], orig.count(old)))
                continue
            open(path, "w").write(orig.replace(old, new))
            r = subprocess.run(["make", "-s", "-C", os.path.join(ROOT, "firmware"), "C=1",
                                "BUILD=" + BUILD], capture_output=True, text=True)
            label = (new.strip() or "(deleted) " + old.strip()).replace("\n", " ")[:50]
            if r.returncode:
                print("%d BUILD FAILED %s" % (i, r.stderr[-200:]))
                continue
            t = subprocess.run([sys.executable, "-m", "unittest"] + a.tests,
                               cwd=os.path.join(ROOT, "emu", "tests"), env=env,
                               capture_output=True, text=True)
            fails = sorted({l.split("(")[0].split(":")[1].strip()
                            for l in t.stderr.splitlines() if l.startswith(("FAIL:", "ERROR:"))})
            print("%d %s %s | %s" % (i, "caught" if t.returncode else "SURVIVED", label,
                                     ", ".join(fails)[:100]), flush=True)
            if not t.returncode:
                survived.append(i)
    finally:
        open(path, "w").write(orig)
        shutil.rmtree(os.path.join(ROOT, "firmware", BUILD), ignore_errors=True)
    print("survived:", survived)


if __name__ == "__main__":
    main()
