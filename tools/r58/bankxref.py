#!/usr/bin/env python3
"""
Before moving a block of r58.s into bank 1: which symbols defined in the
block are used outside it (each needs a far_ stub, must stay fixed, or is
only compared as an address), and do numeric local labels cross its edges.

    bankxref.py r58/r58.s first_label first_label_after_block

Textual (word match on code, comments ignored), so also read the hits:
a data table read by fixed code must stay fixed; a routine reachable from
interrupts or dosir must stay fixed.  See notes/hybrid-plan.md Phase 3.
"""
import collections
import re
import sys


def main():
    path, first, after = sys.argv[1:4]
    src = open(path, encoding="latin-1").read().split("\n")
    a = next(i for i, l in enumerate(src) if l.startswith(first + ":"))
    b = next(i for i, l in enumerate(src) if l.startswith(after + ":"))

    def code(l):
        return l.split(";")[0]

    inside = set()
    for l in src[a:b]:
        for m in re.finditer(r"^\s*([A-Za-z_]\w*):", code(l)):
            inside.add(m.group(1))
        m = re.match(r"^\s*([A-Za-z_]\w*)\s*=", code(l))
        if m:
            inside.add(m.group(1))
        for m in re.finditer(r"TAB\((\w+)\)", l):
            inside.add(m.group(1))
    refs = collections.defaultdict(list)
    for i, l in enumerate(src):
        if a <= i < b:
            continue
        for w in set(re.findall(r"\b[A-Za-z_]\w*\b", code(l))):
            if w in inside:
                refs[w].append(i + 1)
    print("used outside the block (symbol, source lines):")
    for w, ls in sorted(refs.items(), key=lambda x: x[1][0]):
        print("  %-28s %s" % (w, ls[:10]))

    # numeric local labels (1: .. 1b / 1f) must resolve inside the block
    seen, last = set(), {}
    for i in range(a, b):
        for m in re.finditer(r"(?<![\w.$])([1-9]):", code(src[i])):
            last[m.group(1)] = i
    for i in range(a, b):
        if src[i].lstrip().startswith("#"):
            continue
        c = code(src[i])
        for m in re.finditer(r"(?<![\w.$])([1-9])([fb]?)(?![\w$])(:?)", c):
            d, fb, colon = m.groups()
            if colon and not fb:
                seen.add(d)
            elif fb == "b" and d not in seen:
                print("  %d: %sb refers to a label before the block" % (i + 1, d))
            elif fb == "f" and last.get(d, -1) < i:
                print("  %d: %sf refers to a label after the block" % (i + 1, d))
    print("%d symbols, %d lines in the block" % (len(inside), b - a))


if __name__ == "__main__":
    main()
