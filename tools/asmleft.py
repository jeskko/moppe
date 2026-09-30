#!/usr/bin/env python3
"""
What assembler is left in the fixed ROM of a C build, and what kind
(notes/hybrid-plan.md, "What is left").  Run from the repository root
after `make -C firmware`:

    python3 tools/asmleft.py              # totals, then the portable list
    python3 tools/asmleft.py --all        # every routine with its class

Each global label of the preprocessed r58.s that the build map
places in fixed ROM below the C code is a routine up to the next label.
Classes:
    data       no instructions (tables, strings)
    isr        reachable from interrupts (tools/isrreach.py on r58.s)
    main-hw    mainline, touches hardware: out/in/outi, di, halt, exx,
               ex af (port with shims, or keep)
    main-pure  mainline, plain code: the candidates
Sizes are address differences in the map, so a routine includes any
padding or data up to the next label.
"""
import os
import re
import subprocess
import sys

from fwlink import read_map

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FW = os.path.join(ROOT, "firmware")
LABEL = re.compile(r"^([A-Za-z_]\w*):")
HW = re.compile(r"\bout\s*\(|\bin\s+a\s*,\s*\(|\bouti\b|\bdi\b|\bhalt\b|\bexx\b|\bex\s+af")
INSN = re.compile(r"\b(ld|call|jp|jr|ret|push|pop|inc|dec|add|sub|and|or|xor|cp)\b")


def cpp_command():
    """The cpp invocation `make -C firmware` uses to build r58.s (its CPP
    and DEFS variables), read from the Makefile so both places agree.
    Plain cpp output is used, not build/r58.pp.s: asmpp.py rewrites every
    label in the (ABS) fixed-ROM area from 'name:' to 'name = ...', which
    would break this script's label parsing below."""
    flags = subprocess.run(["make", "-s", "-C", FW, "print-cpp-flags"],
                           capture_output=True, text=True, check=True).stdout.split()
    return flags + ["-I" + FW, "-I" + os.path.join(FW, "build"), os.path.join(FW, "r58.s")]


def main():
    src = subprocess.run(cpp_command(), capture_output=True, text=True,
                         encoding="latin-1").stdout.split("\n")
    reach = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "isrreach.py"),
                            os.path.join(FW, "r58.s")], capture_output=True, text=True).stdout
    reach = {l.split()[1] for l in reach.splitlines() if l.strip()}
    bodies, cur = {}, None
    for l in src:
        m = LABEL.match(l)
        if m:
            cur = m.group(1)
            bodies[cur] = []
        elif cur:
            bodies[cur].append(l.split(";")[0])
    syms = read_map(os.path.join(FW, "build", "r58.map"))
    end = syms["s__CODE"]
    fixed = sorted((a, n) for n, a in syms.items() if n in bodies and 0x100 <= a < end)
    rows, tot = [], {}
    for i, (a, n) in enumerate(fixed):
        size = (fixed[i + 1][0] if i + 1 < len(fixed) else end) - a
        body = " ".join(bodies[n])
        if not INSN.search(body):
            k = "data"
        elif n in reach:
            k = "isr"
        elif HW.search(body):
            k = "main-hw"
        else:
            k = "main-pure"
        rows.append((a, size, k, n))
        tot[k] = tot.get(k, 0) + size
    print("fixed-ROM asm 0x0100-0x%04X: %s" % (end, ", ".join(
        "%s %d" % (k, tot[k]) for k in ("data", "isr", "main-hw", "main-pure") if k in tot)))
    for a, size, k, n in rows:
        if "--all" in sys.argv or k == "main-pure":
            print("%04X %5d %-9s %s" % (a, size, k, n))


if __name__ == "__main__":
    main()
