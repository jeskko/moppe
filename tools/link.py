#!/usr/bin/env python3
"""
Link the firmware (notes/toolchain.md):

    link.py -o build/r58 build/r58.rel [c modules .rel ...]

The assembler module is absolute: it defines rom_end (end of the assembler
ROM image) and, in C builds, c_bss / c_bss_end (a RAM block reserved for C
statics).  The C modules' _CODE area is placed at rom_end and _DATA at
c_bss; the SDCC library supplies runtime helpers.  Banked C code
(#pragma bank N, area _CODE_N) follows the assembler's bank N: _CODE_1 at
bank1_end (window addresses), _CODE_2 at bank2_end (virtual 0x28000 +
offset, see ihx2bin.py).  After linking, the map is checked: _CODE must
end by 0x8000 (the fixed ROM), _CODE_N by the end of its bank, _DATA must
fit its block, and every other relocatable area must be empty (C code must
not use initialised data, which would need a startup copy).

Writes <out>.ihx and <out>.map (sdldz80 -m -w).
"""
import argparse
import os
import re
import subprocess
import sys

ROM_END = 0x8000
# banked C areas: (assembler symbol it follows, end of the bank)
BANKS = {"_CODE_1": ("bank1_end", 0xC000), "_CODE_2": ("bank2_end", 0x2C000)}


def rel_symbols(path):
    syms = {}
    for line in open(path, errors="replace"):
        m = re.match(r"S (\S+) Def([0-9A-Fa-f]+)", line)
        if m:
            syms[m.group(1)] = int(m.group(2), 16)
    return syms


def sdcc_libdir():
    out = subprocess.run(["sdcc", "-mz80", "--print-search-dirs"],
                         capture_output=True, text=True).stdout
    sect = None
    for line in out.splitlines():
        if line.endswith(":"):
            sect = line[:-1]
        elif sect == "libdir":
            for d in (line.strip(), os.path.join(line.strip(), "z80")):
                if os.path.exists(os.path.join(d, "z80.lib")):
                    return d
    sys.exit("link.py: SDCC z80 library not found")


def map_areas(path):
    areas = {}
    rx = re.compile(r"^(\S+)\s+([0-9A-F]{8})\s+([0-9A-F]{8}) =\s+\d+\. bytes \(([^)]*)\)")
    for line in open(path):
        m = rx.match(line.replace(".  .ABS.", ".ABS."))
        if m:
            areas[m.group(1)] = (int(m.group(2), 16), int(m.group(3), 16), m.group(4))
    return areas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", required=True, help="output base name")
    ap.add_argument("asm")
    ap.add_argument("cmods", nargs="*")
    a = ap.parse_args()

    syms = rel_symbols(a.asm)
    if "rom_end" not in syms:
        sys.exit("link.py: %s does not define rom_end" % a.asm)
    # the SDCC library is always searched: assembler code uses its
    # banked-call trampolines too
    cmd = ["sdldz80", "-m", "-w", "-i", "-b", "_CODE=0x%04X" % syms["rom_end"],
           "-k", sdcc_libdir(), "-l", "z80"]
    used = set()
    for path in [a.asm] + a.cmods:
        used |= {l.split()[1] for l in open(path, errors="replace") if l.startswith("A ")}
    for area, (sym, _) in BANKS.items():
        if sym in syms and area in used:
            cmd += ["-b", "%s=0x%X" % (area, syms[sym])]
    if a.cmods:
        for s in ("c_bss", "c_bss_end"):
            if s not in syms:
                sys.exit("link.py: %s does not define %s (built without -DC_MODULES?)" % (a.asm, s))
        cmd += ["-b", "_DATA=0x%04X" % syms["c_bss"]]
    cmd += [a.o + ".ihx", a.asm] + a.cmods
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = r.stdout + r.stderr
    if r.returncode or "?ASlink" in out or "Error" in out:
        sys.stderr.write(out)
        sys.exit("link.py: sdldz80 failed")

    areas = map_areas(a.o + ".map")
    bad = []
    for name, (addr, size, flags) in areas.items():
        if size == 0 or "ABS" in flags:
            continue
        if name == "_CODE":
            if addr + size > ROM_END:
                bad.append("_CODE 0x%04X-0x%04X passes 0x%04X" % (addr, addr + size, ROM_END))
        elif name in BANKS:
            end = BANKS[name][1]
            if BANKS[name][0] not in syms:
                bad.append("%s: no %s" % (name, BANKS[name][0]))
            elif addr + size > end:
                bad.append("%s 0x%X-0x%X passes 0x%X" % (name, addr, addr + size, end))
        elif name == "_DATA" and "c_bss_end" in syms:
            if addr + size > syms["c_bss_end"]:
                bad.append("_DATA needs %d bytes, c_bss has %d"
                           % (size, syms["c_bss_end"] - syms["c_bss"]))
        else:
            bad.append("area %s is not empty (%d bytes)" % (name, size))
    if bad:
        sys.exit("link.py: " + "; ".join(bad))


if __name__ == "__main__":
    main()
