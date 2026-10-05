#!/usr/bin/env python3
"""
Tests for moppe's patches to binutils 2.16.1 h8500 (h8500.patch): short
immediates of MOV:G.W / CMP:G.W, explicit sizes and their errors, RTD and
RTE, branches (relaxed, explicit 16-bit, .w, to numbers) within a file
and through ld (two objects linked at two addresses).

    tools/h8500/binutils/test_gas.py [BINDIR]
"""
import os
import re
import subprocess
import sys
import tempfile

TOP = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(TOP, "reference/toolchain/binutils-h8500/bin")
AS, LD, OBJDUMP = (os.path.join(BIN, "h8500-hms-" + p) for p in ("as", "ld", "objdump"))

# (source line, bytes); the line is assembled alone at address 0
BYTES = [
    ("mov.w #5,@r1", "d90605"),                 # #xx:8, sign-extended
    ("mov.w #127,@r1", "d9067f"),
    ("mov.w #-128,@r1", "d90680"),
    ("mov.w #0xffff,@r1", "d906ff"),            # -1
    ("mov.w #0xff80,@r1", "d90680"),
    ("mov.w #128,@r1", "d9070080"),             # does not fit: #xx:16
    ("mov.w #0xff7f,@r1", "d907ff7f"),
    ("mov.w #-129,@r1", "d907ff7f"),
    ("mov.w #5:16,@r1", "d9070005"),            # explicit size kept
    ("mov.w #5:8,@r1", "d90605"),
    ("mov:g.w #-1,@(4,r2)", "ea0406ff"),
    ("mov.w #3,@0x8010:16", "1d80100603"),
    ("cmp.w #3,@r1", "d90403"),
    ("cmp.w #300,@r1", "d905012c"),
    ("cmp:g.w #-2,@0x12:8", "0d1204fe"),
    ("mov.b #5,@r1", "d10605"),                 # byte ops unchanged
    ("add.w #5,r0", "0c000520"),                # source EA: 0x04 would be a byte op
    ("and.w #-1,r3", "0cffff53"),
    ("cmp.w #3,r1", "490003"),
    ("ldc.w #5,sr", "0c000588"),
    ("rtd #4", "1404"),
    ("rtd #0x212", "1c0212"),                   # was 14 02 12
    ("rte", "0a"),
    ("L: bra L", "20fe"),
    ("L: bra L:16", "30fffd"),                  # was 30 ff fb (2 off)
    ("L: bra.w L", "30fffd"),                   # was rejected
    ("L: beq.w L", "37fffd"),
    ("L: bsr.w L", "1efffd"),
    ("L: bra.b L", "20fe"),
]

ERRORS = [
    "mov.w #200:8,@r1",          # out of range for a sign-extended #xx:8
    "add.w #5:8,r0",             # no #xx:8 form for a word source EA
]

A = """	.text
	.global	tgt
	.word	0, start
	.org	0x100
start:	nop
tgt:	nop
l0:	bra.w	l0
	bra	l0:16
	beq.w	l0
	bra	tgt
	bsr.w	l0
"""
B = """	.text
	.global	tgt
f:	bra	tgt
	bra.w	tgt
	bra	0x100
	bra.w	0x101
	bsr	0x100
	beq	tgt:16
"""
# targets objdump shows, by address relative to the text start, with
# "t" a target in the text (moves with -Ttext) and "a" an absolute one
LINKED = {0x102: "t102", 0x105: "t102", 0x108: "t102", 0x10b: "t101", 0x10d: "t102",
          0x110: "t101", 0x113: "t101", 0x116: "a100", 0x119: "a101", 0x11c: "a100",
          0x11f: "t101"}


def run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def main():
    bad = 0
    with tempfile.TemporaryDirectory() as d:
        for line, want in BYTES:
            open(os.path.join(d, "t.s"), "w").write("\t.text\n" + line.replace("L: ", "L:\t") + "\n")
            p = run([AS, "-ahl=t.lst", "-o", "t.o", "t.s"], d)
            got = ""
            if p.returncode == 0:
                for ln in open(os.path.join(d, "t.lst")).read().splitlines():
                    m = re.match(r"\s*2 (?:[0-9a-f]{4} |\s{5})([0-9A-F]+)", ln)
                    if m:
                        got += m.group(1).lower()
                got = got[:len(want)] if got.startswith(want) and not got[len(want):].strip("0") else got
            if got != want:
                print("FAIL %-24s got %s want %s %s" % (line, got or "-", want, p.stderr.strip()[-60:]))
                bad += 1
        for line in ERRORS:
            open(os.path.join(d, "t.s"), "w").write("\t.text\n\t" + line + "\n")
            if run([AS, "-o", "t.o", "t.s"], d).returncode == 0:
                print("FAIL %-24s assembled, want an error" % line)
                bad += 1
        open(os.path.join(d, "a.s"), "w").write(A)
        open(os.path.join(d, "b.s"), "w").write(B)
        for f in ("a", "b"):
            p = run([AS, "-o", f + ".o", f + ".s"], d)
            if p.returncode:
                print("FAIL as %s.s: %s" % (f, p.stderr))
                return 1
        for base in (0, 0x2000):
            p = run([LD] + (["-Ttext", hex(base)] if base else []) + ["-o", "p", "a.o", "b.o"], d)
            if p.returncode:
                print("FAIL ld: %s" % p.stderr)
                return 1
            dis = run([OBJDUMP, "-d", "p"], d).stdout
            seen = {}
            for m in re.finditer(r"^\s*([0-9a-f]+):\s+(?:[0-9a-f]{2} )+\s*\S+\s+#?(0x[0-9a-f]+)", dis, re.M):
                seen[int(m.group(1), 16) - base] = int(m.group(2), 16)
            for off, t in LINKED.items():
                want = int(t[1:], 16) + (base if t[0] == "t" else 0)
                if seen.get(off) != want:
                    print("FAIL linked at %#x: %#x branches to %s, want %#x"
                          % (base, base + off, hex(seen[off]) if off in seen else "-", want))
                    bad += 1
    print("%d failures" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
