#!/usr/bin/env python3
"""
Compare Ghidra's instruction lengths (insns.txt from ExportInsns.java)
with the patched binutils h8500 decoder (reference/r40work/bin/dis2),
which agrees with moppe-emu's h8500.c on every instruction of the ROM.
Prints a summary by Ghidra mnemonic and the first examples.

    tools/r40/ghidra/check_lengths.py [insns.txt] [ROM]
"""
import collections
import os
import subprocess
import sys

TOP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
INSNS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(TOP, "reference/ghidra-r40/insns.txt")
ROM = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    TOP, "reference/oh5nxo/mods/R40-manuals/rc40_rom/ABSBIN")
DIS2 = os.path.join(TOP, "reference/r40work/bin/dis2")

g = []
for line in open(INSNS):
    addr, n, text = line.rstrip("\n").split(" ", 2)
    g.append((int(addr, 16), int(n), text))
p = subprocess.run([DIS2, ROM], input="".join("%x\n" % a for a, _, _ in g),
                   capture_output=True, text=True, check=True)
ref = {}
for line in p.stdout.splitlines():
    f = line.split("\t")
    ref[int(f[0], 16)] = (int(f[1]), f[3] if len(f) > 3 else "")
bad = collections.defaultdict(list)
for a, n, text in g:
    rn, rtext = ref[a]
    if rn != n:
        bad[text.split()[0]].append((a, n, text, rn, rtext))
total = sum(len(v) for v in bad.values())
print("%d instructions, %d length mismatches" % (len(g), total))
for m, v in sorted(bad.items(), key=lambda kv: -len(kv[1])):
    a, n, text, rn, rtext = v[0]
    print("%6d  %-10s e.g. %05x ghidra %d '%s'  ref %d '%s'" % (len(v), m, a, n, text, rn, rtext))
