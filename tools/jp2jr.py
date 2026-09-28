#!/usr/bin/env python3
"""
Shrink the firmware: turn 'jp [nz|z|nc|c,] target' into 'jr' where the
target is in range, outside the timing-critical code (notes/hybrid-plan.md,
"What stays in assembler").  Rewrites the source in place; rebuild and run
again until it reports 0 (each pass brings more targets into range).

    jp2jr.py firmware/r58.s firmware/build

Uses the build's listing, symbol file (sdas -s; written even when the
assembly fails, e.g. on a ROM overflow) and asmpp line map.  Only jps
written literally in r58.s are changed, not ones from macro bodies.

A jr is 1 byte shorter; taken it costs 12 T instead of 10, not taken 7
instead of 10.  Only mainline code is touched, where that does not matter.
"""
import collections
import os
import re
import sys

# [first label, first label after the region): code whose cycle counts or
# branch lengths matter (ISRs, constant-time paths, bit-banging, PWM loops)
EXCLUDE = [
    ("siob_tbe", "once_per_second"),        # SIO/PIO ISRs, CTCSS DSP, systick, dosir
    ("gps_configure_SiRF_generic", "gps_check"),   # SiRF BREAK bit-bang
    ("slight_delay", "typematic"),          # CU53AN keypad shifting
    ("display", "probe_cu58af"),            # CU53AN display shifting
    ("i2c_getbit", "changed_frequency"),    # CU58AF I2C
    ("send_NA_to_synth", "real_txpwr"),     # synth / external serial
    ("save_nvmisc_and_restart", "repeater_toggle_suspend"),  # NV copy, DTMF/AX.25 PWM, CPU probe
]

RX_LST = re.compile(r"^\s{4}([0-9A-F]{8}) (C3|C2|CA|D2|DA) .*?\[\s*\d+\]\s*(\d+)\s+(.*)$")
RX_JP = re.compile(r"\s*jp\s+(?:(nz|z|nc|c)\s*,\s*)?([A-Za-z_][\w$.]*)")
RX_SRC = re.compile(r"\bjp(\s+)((?:(?:nz|z|nc|c)\s*,\s*)?)([\w$.]+)")


def main():
    src_path, build = sys.argv[1:3]
    base = os.path.join(build, "r58")
    syms = {}
    for line in open(base + ".sym", errors="replace"):
        for name, val in re.findall(r"([\w$.]+)\s+=\s+([0-9A-F]{8})", line):
            syms[name] = int(val, 16)
    ranges = [(syms[a], syms[b]) for a, b in EXCLUDE]
    linemap = {}
    for line in open(base + ".linemap"):
        n, loc = line.split()
        fn, sl = loc.rsplit(":", 1)
        linemap[int(n)] = (fn, int(sl))

    # per source line: the ok/not-ok flags of its jps, in order
    per_line = collections.defaultdict(list)
    for line in open(base + ".lst", errors="replace"):
        m = RX_LST.match(line)
        if not m:
            continue
        mm = RX_JP.match(m.group(4))
        if not mm:
            continue
        fn, sl = linemap[int(m.group(3))]
        if os.path.basename(fn) != os.path.basename(src_path):
            continue
        a = int(m.group(1), 16)
        t = syms.get(mm.group(2))
        ok = (t is not None and -126 <= t - (a + 2) <= 127
              and not any(lo <= a < hi for lo, hi in ranges))
        per_line[sl].append(ok)

    src = open(src_path, encoding="latin-1").read().split("\n")
    changed = 0
    for sl, oks in per_line.items():
        line = src[sl - 1]
        code, sep, comment = line.partition(";")
        found = list(RX_SRC.finditer(code))
        if len(found) != len(oks):
            continue        # jp comes from a macro on this line: leave it
        for m, ok in reversed(list(zip(found, oks))):
            if ok:
                code = code[:m.start()] + "jr" + code[m.start() + 2:]
                changed += 1
        src[sl - 1] = code + sep + comment
    open(src_path, "w", encoding="latin-1").write("\n".join(src))
    print("jp2jr: %d jp -> jr" % changed)


if __name__ == "__main__":
    main()
