#!/usr/bin/env python3
"""Print the lburg %term lines for the H8/500 back end: lcc's ops.h
crossed with this target's type sizes (char 1, short/int/pointer 2,
long/long long 4, float/double/long double 4)."""
import re
import sys

OPS = sys.argv[1] if len(sys.argv) > 1 else "../../../reference/toolchain/lcc/src/ops.h"
TYPES = {"F": 1, "I": 5, "U": 6, "P": 7, "V": 8, "B": 9}
SIZE = {"c": 1, "s": 2, "i": 2, "l": 4, "h": 4, "f": 4, "d": 4, "x": 4, "p": 2}
gops, out = {}, []
for line in open(OPS):
    m = re.match(r"\s*gop\((\w+),(\d+)\)", line)
    if m:
        gops[m.group(1)] = int(m.group(2))
        continue
    m = re.match(r"\s*op\((\w+),(\w),([-\w]+)\)", line)
    if m:
        name, ty, sizes = m.groups()
        code = gops[name] << 4 | TYPES[ty]
        if sizes == "-":
            out.append("%s%s=%d" % (name, ty, code))
            continue
        for sz in sorted({SIZE[c] for c in sizes}):
            out.append("%s%s%d=%d" % (name, ty, sz, sz << 10 | code))
seen = set()
for t in out:
    if t not in seen:
        seen.add(t)
        print("%%term %s" % t)
