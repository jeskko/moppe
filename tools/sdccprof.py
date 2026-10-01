#!/usr/bin/env python3
"""
Where SDCC spends its compile time, per C function: compile each module
whole and once per function with that function's body stubbed out; the
difference is roughly what the function costs (register allocation is
per function).  A function far above the rest has control flow the
allocator searches hard (scanner_run, ~200 s with the pinned SDCC before
2026-10-01: notes/ci.md).  Run from the repository root:

    python3 tools/sdccprof.py                      # every module, sdcc on PATH
    python3 tools/sdccprof.py scan aprs -j 4 --sdcc ~/.cache/sdcc-4.6.0/bin/sdcc

Timings under parallel load are noisy (a few seconds); rerun the top
candidates with -j 1..4 before reading much into them.
"""
import argparse
import concurrent.futures
import os
import re
import shutil
import subprocess
import tempfile
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CDIR = os.path.join(ROOT, "firmware", "c")
CFLAGS = ["-mz80", "--sdcccall", "1", "--reserve-regs-iy", "--opt-code-size",
          "--max-allocs-per-node", "200000"]
DEF = re.compile(r"^((?:static |const )*[A-Za-z_][\w ]*?\**)\s*\b(\w+)\(([^)]*)\)\s*\n\{", re.M)


def body_end(t, i):
    """index of the '}' closing the '{' at i, skipping comments and quotes"""
    depth = 0
    while i < len(t):
        if t.startswith("/*", i):
            i = t.index("*/", i) + 2
            continue
        if t[i] in "'\"":
            q = t[i]
            i += 1
            while t[i] != q:
                i += 2 if t[i] == "\\" else 1
        elif t[i] == "{":
            depth += 1
        elif t[i] == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced braces")


def variants(src):
    yield "(whole)", src
    for m in DEF.finditer(src):
        rtype, name = m.group(1), m.group(2)
        start = m.end() - 1
        end = body_end(src, start)
        ret = "" if rtype.split()[-1] == "void" else "return 0;"
        yield name, src[:start] + "{" + ret + "}" + src[end + 1:]


def compile_time(sdcc, tmp, text):
    d = tempfile.mkdtemp(dir=tmp)
    shutil.copy(os.path.join(CDIR, "r58.h"), d)
    with open(os.path.join(d, "x.c"), "w") as f:
        f.write(text)
    t = time.time()
    r = subprocess.run([sdcc] + CFLAGS + ["-c", "x.c", "-o", "x.rel"], cwd=d,
                       capture_output=True)
    return time.time() - t, r.returncode


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("modules", nargs="*")
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count())
    ap.add_argument("--sdcc", default="sdcc")
    ap.add_argument("--top", type=int, default=15)
    a = ap.parse_args()
    mods = a.modules or sorted(f[:-2] for f in os.listdir(CDIR) if f.endswith(".c"))
    jobs = []
    for mod in mods:
        src = open(os.path.join(CDIR, mod + ".c")).read()
        jobs += [(mod, name, text) for name, text in variants(src)]
    tmp = tempfile.mkdtemp(prefix="sdccprof-")
    try:
        with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
            res = list(ex.map(lambda j: (j[0], j[1]) + compile_time(a.sdcc, tmp, j[2]), jobs))
    finally:
        shutil.rmtree(tmp)
    whole = {mod: t for mod, name, t, rc in res if name == "(whole)"}
    print("module          whole")
    for mod in mods:
        print("%-12s %7.1f s" % (mod, whole[mod]))
    rows = sorted(((whole[mod] - t, mod, name) for mod, name, t, rc in res
                   if name != "(whole)" and rc == 0), reverse=True)
    print("\nfunctions by compile time saved when stubbed:")
    for save, mod, name in rows[:a.top]:
        print("%7.1f s  %-12s %s" % (save, mod, name))
    bad = [(mod, name) for mod, name, t, rc in res if rc]
    if bad:
        print("\nstubs that did not compile (ignored):", bad)


if __name__ == "__main__":
    main()
