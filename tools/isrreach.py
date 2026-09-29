#!/usr/bin/env python3
"""
Which routines of r58.s can run in interrupt context?  Code reachable from
the interrupt entries must stay in fixed ROM (notes/hybrid-plan.md,
Phase 3).

    isrreach.py firmware/r58.s                 list every reachable label
    isrreach.py firmware/r58.s FIRST AFTER     only those in [FIRST, AFTER)

Textual call graph: a routine is a global label up to the next one; its
edges are call/jp/jr/djnz to global labels, `.dw label` in its body (vector
and jump tables), and falling through into the next label unless its last
instruction is an unconditional ret/reti/retn/jp/jr/doreti (cpp lines,
e.g. `#ifdef` or a multi-line #define, are not instructions;
both sides of an #ifdef count, which errs on the safe side).  Indirect jumps
through RAM (`jp (hl)`, scanner_state, repeater_state) are not followed;
they are all mainline today, check new ones by hand.  Roots: the IM2
handlers (`.dw sio*_ / pio*_`) and dosir.  RST 38 and NMI are left out:
both restart (`jp start`, `jp save_nvmisc_and_restart`) and never return
into interrupted code; the NV save path they take is fixed ROM.
"""
import re
import sys

ROOTS = ["dosir"]

LABEL = re.compile(r"^([A-Za-z_]\w*):")
BRANCH = re.compile(r"\b(?:call|jp|jr|djnz)\s+(?:(?:n?z|n?c|p|m|pe|po)\s*,\s*)?([A-Za-z_]\w*)")
DW = re.compile(r"\.dw\s+([A-Za-z_]\w*)")
END = re.compile(r"^\s*(ret|reti|retn|doreti|jp\s+[^,]+|jr\s+[^,]+|halt)\s*$")


def code(line):
    return line.split(";")[0].rstrip()


def parse(path):
    src = open(path, encoding="latin-1").read().split("\n")
    order, start = [], {}
    for i, l in enumerate(src):
        m = LABEL.match(l)
        if m:
            order.append(m.group(1))
            start[m.group(1)] = i
    labels = set(order)
    edges = {}
    for k, name in enumerate(order):
        a = start[name]
        b = start[order[k + 1]] if k + 1 < len(order) else len(src)
        out = set()
        last = ""
        cont = False                    # inside a multi-line #define
        for l in src[a:b]:
            raw = l.rstrip()
            if cont or raw.lstrip().startswith("#"):
                cont = raw.endswith("\\")   # preprocessor lines are not code
                continue
            c = LABEL.sub("", code(l)).strip()
            if not c:
                continue
            last = c
            for m in BRANCH.finditer(c):
                if m.group(1) in labels:
                    out.add(m.group(1))
            for m in DW.finditer(c):
                if m.group(1) in labels:
                    out.add(m.group(1))
        if k + 1 < len(order) and not END.match(last):
            out.add(order[k + 1])
        edges[name] = out
    return src, order, start, edges


def main():
    path = sys.argv[1]
    src, order, start, edges = parse(path)
    roots = [r for r in ROOTS if r in edges]
    for l in src:                              # the IM2 vector table
        m = DW.search(code(l))
        if m and re.match(r"(sio[ab]|pio[ab])_", m.group(1)):
            roots.append(m.group(1))
    seen, todo = set(), list(roots)
    while todo:
        n = todo.pop()
        if n in seen:
            continue
        seen.add(n)
        todo += edges.get(n, ())
    if len(sys.argv) > 3:
        a, b = start[sys.argv[2]], start[sys.argv[3]]
        hits = [n for n in order if a <= start[n] < b and n in seen]
        print("reachable from interrupts in [%s, %s): %s"
              % (sys.argv[2], sys.argv[3], " ".join(hits) or "none"))
        sys.exit(1 if hits else 0)
    for n in order:
        if n in seen:
            print("%6d %s" % (start[n] + 1, n))


if __name__ == "__main__":
    main()
