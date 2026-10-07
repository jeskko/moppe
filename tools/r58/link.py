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
not use initialised data, which would need a startup copy).  _HOME (SDCC library
helpers for banked code, e.g. __mullong) is placed after _CODE in a second
pass.  And no C
module may reference a symbol in a bank it does not run in (a bank-2
module cannot see bank 1, fixed code sees neither): calls go through the
fixed-ROM far_* stubs.  ADDRESS_ONLY lists the exceptions, symbols C only
compares as numbers.

Writes <out>.ihx and <out>.map (sdldz80 -m -w).
"""
import argparse
import os
import re
import subprocess
import sys

from fwlink import BANKS, read_map, read_rel

ROM_END = 0x8000


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


# C compares these with pointers and never reads or calls them
ADDRESS_ONLY = {"_menu_rfc_change", "_menu_sql_change", "_menu_sqB_change",
                "_tune_tone_position"}


def cross_bank_refs(cmods, mapsyms):
    bad = []
    for path in cmods:
        rel = read_rel(path)
        areas = {name for name, size in rel.areas.items()
                 if size and name.startswith("_CODE")}
        for name in sorted(rel.refs - ADDRESS_ONLY):
            v = mapsyms.get(name)
            for area, bank in BANKS.items():
                if v is not None and bank["lo"] <= v < bank["hi"] and area not in areas:
                    bad.append("%s uses %s (0x%X, %s)" % (os.path.basename(path), name, v, area))
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", required=True, help="output base name")
    ap.add_argument("asm")
    ap.add_argument("cmods", nargs="*")
    a = ap.parse_args()

    syms = read_rel(a.asm).defs
    if "rom_end" not in syms:
        sys.exit("link.py: %s does not define rom_end" % a.asm)
    # the SDCC library is always searched: assembler code uses its
    # banked-call trampolines too
    cmd = ["sdldz80", "-m", "-w", "-i", "-b", "_CODE=0x%04X" % syms["rom_end"],
           "-k", sdcc_libdir(), "-l", "z80"]
    used = set()
    for path in [a.asm] + a.cmods:
        used |= set(read_rel(path).areas)
    for area, bank in BANKS.items():
        if bank["end_sym"] in syms and area in used:
            cmd += ["-b", "%s=0x%X" % (area, syms[bank["end_sym"]])]
    if a.cmods:
        for s in ("c_bss", "c_bss_end"):
            if s not in syms:
                sys.exit("link.py: %s does not define %s" % (a.asm, s))
        cmd += ["-b", "_DATA=0x%04X" % syms["c_bss"]]
    files = [a.o + ".ihx", a.asm] + a.cmods

    def link(extra):
        r = subprocess.run(cmd + extra + files, capture_output=True, text=True)
        out = r.stdout + r.stderr
        if r.returncode or "?ASlink" in out or "Error" in out:
            sys.stderr.write(out)
            sys.exit("link.py: sdldz80 failed")
        return map_areas(a.o + ".map")

    # the SDCC library puts some helpers (__mullong, __divulong) in _HOME,
    # code for every bank: a second pass places it after _CODE (fixed ROM)
    areas = link([])
    if areas.get("_HOME", (0, 0, ""))[1]:
        code = areas.get("_CODE", (syms["rom_end"], 0, ""))
        areas = link(["-b", "_HOME=0x%04X" % (code[0] + code[1])])
    bad = []
    for name, (addr, size, flags) in areas.items():
        if size == 0 or "ABS" in flags:
            continue
        if name in ("_CODE", "_HOME"):
            if addr + size > ROM_END:
                bad.append("%s 0x%04X-0x%04X passes 0x%04X" % (name, addr, addr + size, ROM_END))
        elif name in BANKS:
            end = BANKS[name]["hi"]
            if BANKS[name]["end_sym"] not in syms:
                bad.append("%s: no %s" % (name, BANKS[name]["end_sym"]))
            elif addr + size > end:
                bad.append("%s 0x%X-0x%X passes 0x%X" % (name, addr, addr + size, end))
        elif name == "_DATA" and "c_bss_end" in syms:
            if addr + size > syms["c_bss_end"]:
                bad.append("_DATA needs %d bytes, c_bss has %d"
                           % (size, syms["c_bss_end"] - syms["c_bss"]))
        else:
            bad.append("area %s is not empty (%d bytes)" % (name, size))
    bad += cross_bank_refs(a.cmods, read_map(a.o + ".map"))
    if bad:
        # no output left behind, or make would take the build as done
        for ext in (".ihx", ".map"):
            if os.path.exists(a.o + ext):
                os.remove(a.o + ext)
        sys.exit("link.py: " + "; ".join(bad))


if __name__ == "__main__":
    main()
