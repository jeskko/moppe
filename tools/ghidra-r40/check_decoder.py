#!/usr/bin/env python3
"""
Check the Ghidra H8/500 decoder against the patched binutils decoder
(reference/r40work/bin/dis, whose lengths agree with moppe-emu's h8500.c)
on every instruction of a linear sweep of the ROM, code and data alike:
lists opcodes Ghidra cannot decode and length disagreements, grouped by
the binutils mnemonic.

    tools/ghidra-r40/check_decoder.py [ROM]
"""
import collections
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.realpath(os.path.join(HERE, "..", ".."))
ROM = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    TOP, "reference/oh5nxo/mods/R40-manuals/rc40_rom/ABSBIN")
WORK = os.path.join(TOP, "reference/ghidra-r40")
GHIDRA = os.environ.get("GHIDRA_INSTALL_DIR", "/opt/ghidra")

sweep = subprocess.run([os.path.join(TOP, "reference/r40work/bin/dis"), ROM, "0", "40000"],
                       capture_output=True, text=True, check=True).stdout
ref = {}
for line in sweep.splitlines():
    f = line.split("\t")
    if len(f) < 2 or not f[0].endswith(":"):
        continue
    if "unknown" in line:
        continue
    a = int(f[0][:-1], 16)
    m = re.match(r"((?:[0-9a-f]{2} )+)\s*(.*)", f[1] + " ")
    if not m:
        continue
    text = (m.group(2).strip() + " " + "\t".join(f[2:])).strip()
    ref[a] = (len(m.group(1).split()), m.group(1).strip(), text)
with open(os.path.join(WORK, "sweep.txt"), "w") as fh:
    fh.write("".join("%x\n" % a for a in sorted(ref)))
p = subprocess.run([os.path.join(GHIDRA, "support/analyzeHeadless"), WORK, "R40",
                "-process", "ABSBIN", "-noanalysis", "-readOnly",
                "-scriptPath", HERE, "-postScript", "DecodeAll.java",
                os.path.join(WORK, "sweep.txt"), os.path.join(WORK, "decoded.txt")],
               capture_output=True, text=True)
if p.returncode:
    sys.exit(p.stdout[-3000:] + p.stderr[-3000:])
none = collections.defaultdict(list)
diff = collections.defaultdict(list)
for line in open(os.path.join(WORK, "decoded.txt")):
    a, n, text = line.rstrip("\n").split(" ", 2)
    a, n = int(a, 16), int(n)
    rn, rbytes, rtext = ref[a]
    key = rtext.split()[0] if rtext else "?"
    if n == 0:
        none[key].append((a, rbytes, rtext))
    elif n != rn:
        diff[key].append((a, n, text, rbytes, rtext))
print("%d instructions; no constructor: %d; length differs: %d"
      % (len(ref), sum(map(len, none.values())), sum(map(len, diff.values()))))
for k, v in sorted(none.items(), key=lambda kv: -len(kv[1])):
    a, rb, rt = v[0]
    print("  none %5d %-10s e.g. %05x %-15s %s" % (len(v), k, a, rb, rt))
for k, v in sorted(diff.items(), key=lambda kv: -len(kv[1])):
    a, n, t, rb, rt = v[0]
    print("  len  %5d %-10s e.g. %05x %-15s %s  | ghidra %d '%s'" % (len(v), k, a, rb, rt, n, t))
