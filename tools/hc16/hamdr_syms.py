#!/usr/bin/env python3
"""
Symbol table of a HaMDR build, local labels included: the linker map
gives the global symbols and where each object's sections landed; each
object's COFF symbol table (objdump -t) gives its local labels
(adc_buf, int_OC2_rx, rx_bits, ...) relative to those sections.

    tools/hc16/hamdr_syms.py BUILDDIR OBJDUMP > hamdr.sym

Output lines: 20-bit address in hex, name; sorted by address.  Load with
emu/python/mdr150emu.py load_syms() (or load_map() for the globals only).
"""
import re
import subprocess
import sys


def main(build, objdump):
    base, glob = {}, {}
    for line in open(build + "/hamdr.map", encoding="latin-1"):
        m = re.match(r"^ (\.\w+)\s+0x([0-9a-f]+)\s+0x[0-9a-f]+ (\S+\.o)$", line)
        if m:
            base[(m.group(3), m.group(1))] = int(m.group(2), 16)
            continue
        p = line.split()
        if len(p) == 2 and p[0].startswith("0x") and not p[1].startswith("."):
            glob[p[1]] = int(p[0], 16) & 0xFFFFF
    syms = dict(glob)
    for obj in sorted({o for o, s in base}):
        path = build + "/" + obj
        secs = {}
        for line in subprocess.run([objdump, "-h", path], capture_output=True,
                                   text=True).stdout.splitlines():
            p = line.split()
            if len(p) > 2 and p[0].isdigit():
                secs[int(p[0]) + 1] = p[1]
        for line in subprocess.run([objdump, "-t", path], capture_output=True,
                                   text=True).stdout.splitlines():
            m = re.match(r"\[\s*\d+\]\(sec\s+(-?\d+)\).*0x([0-9a-f]+) (\S+)$", line)
            if not m or int(m.group(1)) not in secs:
                continue
            b = base.get((obj, secs[int(m.group(1))]))
            name = m.group(3)
            if b is None or name.startswith(".") or name in syms:
                continue
            syms[name] = (b + int(m.group(2), 16)) & 0xFFFFF
    for name, a in sorted(syms.items(), key=lambda kv: (kv[1], kv[0])):
        print("%05X %s" % (a, name))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
