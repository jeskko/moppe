#!/usr/bin/env python3
"""
Round-trip check of Alfred Arnold's AS (asl) for the H8/500 against the
patched binutils decoder (reference/r40work/bin/dis2, which agrees with
moppe-emu's h8500.c): every instruction the emulator executed in the
Nokia R40 ROM (reference/ghidra-r40/coverage.bin, tools/r40/ghidra/
coverage.py) is disassembled, rewritten in asl syntax, assembled at its
own address, and the bytes asl produced are disassembled again.  The
two disassemblies must say the same thing; asl may choose a shorter
encoding (mov:i for mov:g, @aa:8 for @aa:16 ...), so formats and
operand sizes are compared, not bytes.

    tools/h8500/check_asl.py [ASL]
"""
import os
import re
import subprocess
import sys
import tempfile

TOP = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ROM = os.path.join(TOP, "reference/oh5nxo/mods/R40-manuals/rc40_rom/ABSBIN")
COV = os.path.join(TOP, "reference/ghidra-r40/coverage.bin")
DIS2 = os.path.join(TOP, "reference/r40work/bin/dis2")
ASL = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    TOP, "reference/toolchain/asl-current/asl")
CP = 0
DP = 8                       # the Nokia firmware keeps DP = EP = TP = 8, BR = FF


def dis2(image, addrs):
    with tempfile.NamedTemporaryFile(suffix=".bin") as f:
        f.write(image)
        f.flush()
        out = subprocess.run([DIS2, f.name], input="".join("%x\n" % a for a in addrs),
                             capture_output=True, text=True, check=True).stdout
    res = {}
    for line in out.splitlines():
        a, n, text = line.split("\t", 2)
        if "unknown" in text:          # binutils' gaps: RTE, word STC/LDC SR
            res[int(a, 16)] = (int(n), "*unknown*", "")
            continue
        text = re.sub(r"^(?:[0-9a-f]{2} )+\s*", "", text)     # the instruction bytes
        mnem, _, ops = text.partition("\t")
        res[int(a, 16)] = (int(n), mnem.strip(), ops.strip())
    return res


REG = r"(r[0-7]|fp|sp)"


def regs(s):
    return sorted({{"fp": "r6", "sp": "r7"}.get(x, x) for x in re.findall(REG, s)})


def operand_to_asl(op, mnem):
    op = op.strip()
    m = re.fullmatch(r"#(-?0x[0-9a-f]+|-?\d+)(?::(?:8|16|q|4))?", op)
    if m:
        return "#" + str(int(m.group(1), 0))
    m = re.fullmatch(r"@\((-?0x[0-9a-f]+|-?\d+):(8|16)(?: \(-?\d+\))?, ?" + REG + r"\)", op)
    if m:
        return "@(%d,%s)" % (int(m.group(1), 0) & 0xFFFF if m.group(2) == "16" else int(m.group(1), 0), m.group(3))
    m = re.fullmatch(r"@(0x[0-9a-f]+):8", op)
    if m:                                  # short absolute: page FF via BR
        return "@$%x" % (0xFF00 | int(m.group(1), 16))
    m = re.fullmatch(r"@(0x[0-9a-f]+):16", op)
    if m:
        a = int(m.group(1), 16)
        if mnem.startswith(("jmp", "jsr")):
            return "@$%x" % (CP << 16 | a)  # code: CP's page
        return "@$%x" % (DP << 16 | a)
    m = re.fullmatch(r"@(0x[0-9a-f]+):24", op)
    if m:
        return "@$%x" % int(m.group(1), 16)
    m = re.fullmatch(r"#(0x[0-9a-f]+):(8|16)", op)   # branch targets
    if m:
        return "$%x" % int(m.group(1), 16)
    if re.fullmatch(r"0x[0-9a-f]+(:16|:8)?", op):
        return "$%x" % int(op.split(":")[0], 16)
    return op


def split_ops(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def to_asl(mnem, ops, addr):
    base = re.sub(r":[a-z]+", "", mnem)          # mov:g.w -> mov.w
    if mnem.startswith(("ldm", "stm")):
        rl = "(" + ",".join(regs(ops.split("@")[0] if mnem.startswith("stm") else ops.split(",", 1)[1])) + ")"
        return "%s\t%s" % (base, "@sp+," + rl if mnem.startswith("ldm") else rl + ",@-sp")
    if mnem.startswith(("b", "scb")) and re.match(r"(b[a-z]+\.?[bw]?|bsr\.?[bw]?)$", mnem) \
            and not mnem.startswith(("bclr", "bset", "bnot", "btst")):
        base = re.sub(r"\.[bw]$", "", base)       # bra.b -> bra, size from the target
    if re.match(r"(b(?!clr|set|not|tst)[a-z]+|scb/[a-z]+)$", base):
        # branch target: "#0x275f:8" is the address in CP's page
        def tgt(o):
            m = re.fullmatch(r"#?(0x[0-9a-f]+)(?::(?:8|16))?", o.strip())
            return "$%x" % (CP << 16 | int(m.group(1), 16)) if m else operand_to_asl(o, base)
        return "%s\t%s" % (base, ",".join(tgt(o) for o in split_ops(ops)))
    parts = [operand_to_asl(o, base) for o in split_ops(ops)]
    if base.endswith(".w"):
        # "#0xff:8" with a word operation is sign-extended: -1
        parts = [("#%d" % (int(p[1:]) - 256) if re.fullmatch(r"#\d+", p) and re.fullmatch(r"#0x[0-9a-f]+:8", o.strip())
                  and int(p[1:]) >= 128 else p) for p, o in zip(parts, split_ops(ops))]
    return "%s\t%s" % (base, ",".join(parts))


def canon(mnem, ops):
    """meaning only: no format, no operand-size suffixes, registers named"""
    m = re.sub(r":[a-z]+", "", mnem)
    if re.match(r"(b[a-z]{1,3}|bsr|bra|brn)(\.[bw])?$", m) and m not in ("bclr", "bset", "bnot", "btst"):
        m = re.sub(r"\.[bw]$", "", m)
    o = ops
    if m.endswith(".w"):          # word op, 8-bit immediate: sign-extended
        o = re.sub(r"#0x([0-9a-f]+):8", lambda x: "#%d" % (int(x.group(1), 16) - (256 if int(x.group(1), 16) >= 128 else 0)), o)
    if re.match(r"(b(?!clr|set|not|tst)[a-z]+|scb/[a-z]+)$", m):
        o = o.lstrip("#")
    o = re.sub(r"\(0x[0-9a-f]+:(8|16) \((-?\d+)\)", lambda x: "(%s" % x.group(2), o)
    o = re.sub(r"(-?0x[0-9a-f]+):(8|16|24|q|4)", lambda x: str(int(x.group(1), 16)), o)
    o = re.sub(r"(?<![\w$])(-?0x[0-9a-f]+)", lambda x: str(int(x.group(1), 16)), o)
    o = o.replace("fp", "r6").replace("sp", "r7").replace(" ", "")
    if m.startswith(("ldm", "stm")):
        o = ",".join(regs(o))
    return m, o


class _Keep:
    def __init__(self, d):
        os.makedirs(d, exist_ok=True)
        self.d = d

    def __enter__(self):
        return self.d

    def __exit__(self, *a):
        return False


def main():
    rom = open(ROM, "rb").read()
    cov = open(COV, "rb").read()
    addrs = [a for a in range(len(cov)) if cov[a] & 1]
    ref = dis2(rom, addrs)
    lines = ["\tcpu\tHD6475328", "\tmaxmode\ton", "\trelaxed\ton", "\tpage\t0",
             "\tassume\tdp:%d, ep:%d, tp:%d, br:$ff" % (DP, DP, DP)]
    asl_of = {}
    for a in addrs:
        n, mnem, ops = ref[a]
        if "unknown" in mnem:
            continue
        global CP
        CP = a >> 16
        asl_of[a] = to_asl(mnem, ops, a)
        lines += ["\torg\t$%x" % a, "L%x:\t%s" % (a, asl_of[a])]
    keep = os.environ.get("KEEP")          # KEEP=dir keeps rt.asm / rt.lst there
    with (tempfile.TemporaryDirectory() if not keep else _Keep(keep)) as d:
        src = os.path.join(d, "rt.asm")
        open(src, "w").write("\n".join(lines) + "\n")
        p = subprocess.run([ASL, "-q", "-L", "-x", "rt.asm"], cwd=d, capture_output=True, text=True)
        errs = [l for l in (p.stdout + p.stderr).splitlines() if "error" in l]
        if not os.path.exists(os.path.join(d, "rt.p")):
            print("\n".join((p.stdout + p.stderr).splitlines()[:40]))
            return 1
        img = os.path.join(d, "rt.bin")
        subprocess.run([os.path.join(os.path.dirname(ASL), "p2bin"), "-q", "-l", "0", "-r", "0-$3ffff",
                        "rt.p", "rt.bin"], cwd=d, check=True, capture_output=True)
        out = open(img, "rb").read().ljust(0x40000, b"\0")
        lst = open(os.path.join(d, "rt.lst"), errors="replace").read()
    # each instruction's own bytes, from the listing: assembled at its
    # address, a longer encoding would overlap the next one in one image
    code = {}
    for m in re.finditer(r"^\s*\d+/\s+([0-9A-F]+) : ((?:[0-9A-F]{2} )+)\s+L([0-9a-f]+):", lst, re.M):
        code[int(m.group(3), 16)] = bytes.fromhex(m.group(2))
    order = sorted(asl_of)
    new, outs = {}, {}
    for phase in range(4):
        img = bytearray(0x40000)
        sel = order[phase::4]
        for a in sel:
            img[a:a + len(code[a])] = code[a]
            outs[a] = bytes(img)
        new.update(dis2(bytes(img), sel))
    bad, shorter = [], 0
    for a in sorted(asl_of):
        n, mnem, ops = ref[a]
        n2, mnem2, ops2 = new[a]
        if mnem.startswith("rtd") and mnem2 == "*unknown*":
            # binutils decodes only RTD #xx:8 (0x14); 0x1C is #xx:16
            c = code[a]
            if c[0] == 0x1C and (c[1] << 8 | c[2]) == int(ops.split(":")[0][1:], 16):
                continue
        if mnem.startswith("cmp:g.w") and re.match(r"#0x[0-9a-f]+:8,", ops):
            # asl uses CMP:G.W #xx:16 (EA, 05, imm16) where the ROM has the
            # #xx:8 form (EA, 04, imm8); binutils misreads 05 after an EA.
            # Same comparison if the bytes are the sign-extended immediate.
            orig = rom[a:a + n]
            k = orig.rfind(0x04, 0, n - 1)
            imm = orig[k + 1]
            want = orig[:k] + bytes([0x05, 0xFF if imm & 0x80 else 0x00, imm])
            if code[a] == want:
                continue
        if canon(mnem, ops) != canon(mnem2, ops2):
            bad.append((a, mnem + " " + ops, asl_of[a], mnem2 + " " + ops2))
        elif n2 < n:
            shorter += 1
    print("%d instructions, %d asl errors, %d differ, %d assembled shorter"
          % (len(asl_of), len(errs), len(bad), shorter))
    for e in errs[:15]:
        print("  ", e)
    for b in bad[:40]:
        print("  %05x  %-34s | %-30s | %s" % b)
    return 1 if bad or errs else 0


if __name__ == "__main__":
    sys.exit(main())
