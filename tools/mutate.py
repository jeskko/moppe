#!/usr/bin/env python3
"""
Mutation check for a C port (notes/hybrid-plan.md, "Safety net"): apply
each mutant (a source replacement) to a C module, build `make` in a
temporary copy of the firmware tree, run the given tests against that
build, and report which mutants no test caught.  The module in the
repository is never modified.  Run from the repository root:

    python3 tools/mutate.py firmware/c/aprs.c mutants.py test_aprs_diff test_fsk.FskRx
    python3 tools/mutate.py firmware/c/aprs.c mutants.py test_aprs_diff --only 3 7
    python3 tools/mutate.py firmware/c/menu.c tools/mutants/menu.py test_menu_diff --jobs 12

tools/mutants/ keeps the lists of the runs quoted in notes/hybrid-plan.md
(menu: + test_menu_power test_mbus_config test_remote_config
test_diff.DiffTest.test_fsk_edges_receive; scan: test_scan_diff
test_scan_rptr.Scanner test_scan_rptr.Rejects).

mutants.py defines MUTANTS = [(old, new), ...]; each `old` must occur
exactly once in the module.  The mutated build is passed to the tests as
the candidate/default ROM through every env variable the tests read
(R58_ROM/LST, R58_CAND_*, R58_RPTR_CAND_*, R58_GPS_CAND_*, R58_APRS_CAND_*,
R58_MENU_CAND_*, R58_SCAN_CAND_*, R58_KEYS_CAND_*, R58_PTT_CAND_*, R58_MAIN_CAND_*, R58_DPY_CAND_*, R58_RFC_CAND_*), so differential tests compare the asm build (reference)
with the mutant.  --jobs N runs N mutants at once.  A test that fails
without any mutant makes every result meaningless: run the tests on the
unmutated build first.
"""
import argparse
import concurrent.futures
import os
import runpy
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BUILD = "build-mut"
ENV_PREFIXES = ("R58", "R58_CAND", "R58_RPTR_CAND", "R58_GPS_CAND", "R58_APRS_CAND",
                "R58_MENU_CAND", "R58_SCAN_CAND", "R58_KEYS_CAND", "R58_PTT_CAND", "R58_MAIN_CAND", "R58_DPY_CAND", "R58_RFC_CAND")
# what `make` needs, copied per mutant (tools/ is shared, read only)
FIRMWARE_FILES = ("Makefile", "asm.h", "r58.s", "c")


def run_mutant(i, old, new, rel, orig, tests):
    tmp = tempfile.mkdtemp(prefix="r58mut%d-" % i)
    try:
        fw = os.path.join(tmp, "firmware")
        os.mkdir(fw)
        for f in FIRMWARE_FILES:
            src = os.path.join(ROOT, "firmware", f)
            (shutil.copytree if os.path.isdir(src) else shutil.copy)(src, os.path.join(fw, f))
        os.symlink(os.path.join(ROOT, "tools"), os.path.join(tmp, "tools"))
        with open(os.path.join(tmp, rel), "w") as f:
            f.write(orig.replace(old, new))
        label = (new.strip() or "(deleted) " + old.strip()).replace("\n", " ")[:50]
        r = subprocess.run(["make", "-s", "-C", fw, "BUILD=" + BUILD],
                           capture_output=True, text=True)
        if r.returncode:
            return i, None, "%d BUILD FAILED %s" % (i, r.stderr[-200:])
        env = dict(os.environ, R58_NV_CACHE=os.path.join(tmp, "nv-cache"))
        for p in ENV_PREFIXES:
            env[p + "_ROM"] = os.path.join(fw, BUILD, "r58.bin")
            env[p + "_LST"] = os.path.join(fw, BUILD, "r58.map")
        t = subprocess.run([sys.executable, "-m", "unittest"] + tests,
                           cwd=os.path.join(ROOT, "emu", "tests"), env=env,
                           capture_output=True, text=True)
        fails = sorted({l.split("(")[0].split(":")[1].strip()
                        for l in t.stderr.splitlines() if l.startswith(("FAIL:", "ERROR:"))})
        caught = t.returncode != 0
        return i, caught, "%d %s %s | %s" % (i, "caught" if caught else "SURVIVED", label,
                                             ", ".join(fails)[:100])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("module", help="C source, e.g. firmware/c/aprs.c")
    ap.add_argument("mutants", help="python file defining MUTANTS")
    ap.add_argument("tests", nargs="+", help="unittest names (run in emu/tests)")
    ap.add_argument("--only", type=int, nargs="*", help="mutant indexes to run")
    ap.add_argument("--jobs", type=int, default=1, help="mutants run at once")
    a = ap.parse_args()

    rel = os.path.relpath(os.path.join(ROOT, a.module), ROOT)
    orig = open(os.path.join(ROOT, rel)).read()
    mutants = runpy.run_path(a.mutants)["MUTANTS"]
    todo = []
    for i, (old, new) in enumerate(mutants):
        if a.only and i not in a.only:
            continue
        if orig.count(old) != 1:
            print("%d: `%s` occurs %d times, skipped" % (i, old[:40], orig.count(old)))
            continue
        todo.append((i, old, new))
    survived = []
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
        futs = [ex.submit(run_mutant, i, old, new, rel, orig, a.tests) for i, old, new in todo]
        for fut in concurrent.futures.as_completed(futs):
            i, caught, line = fut.result()
            print(line, flush=True)
            if caught is False:
                survived.append(i)
    print("survived:", sorted(survived))


if __name__ == "__main__":
    main()
