#!/usr/bin/env python3
"""
Round-trip check of the binutils 2.16.1 H8/500 assembler (gas, h8500-hms;
tools/h8500/binutils/build.sh) like check_asl.py: every instruction the
emulator executed in the Nokia R40 ROM is disassembled (dis2), written
in gas syntax with the disassembler's explicit formats (mov:g.w, @aa:8,
#xx:16 ...), assembled alone at its own address with a label at its
branch target, and its bytes compared with the ROM's.  Different bytes
are decoded again and compared by meaning (check_asl.canon); those that
mean the same are counted as other encodings, the rest are listed.

    tools/h8500/check_gas.py [AS]
"""
import os
import re
import subprocess
import sys
import tempfile
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_asl as ca  # noqa: E402

AS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    ca.TOP, "reference/toolchain/binutils-h8500/bin/h8500-hms-as")

BRANCH = re.compile(r"(b(?!clr|set|not|tst)[a-z]{1,3}|bsr|scb/[a-z]+)(\.[bw])?$")


def to_gas(mnem, ops, a):
    """(line, branch target or None)"""
    ops = re.sub(r" \(-?\d+\)", "", ops).replace(", ", ",")
    if mnem.startswith(("ldm", "stm")):
        rl = "(" + ",".join(ca.regs(ops.split("@")[0] if mnem.startswith("stm")
                                    else ops.split(",", 1)[1])) + ")"
        return "%s\t%s" % (mnem, "@sp+," + rl if mnem.startswith("ldm") else rl + ",@-sp"), None
    m = BRANCH.match(mnem)
    if m:
        parts = ca.split_ops(ops)
        tgt = re.fullmatch(r"#?(0x[0-9a-f]+)(?::(?:8|16))?", parts[-1].strip())
        t = (a >> 16) << 16 | int(tgt.group(1), 16)
        mn = mnem[:-2] if mnem.endswith(".w") else mnem      # gas: no bra.w
        return "%s\t%s" % (mn, ",".join(parts[:-1] + ["T"])), t
    ops = re.sub(r"#(-?\w+):(?:q|4)\b", r"#\1", ops)          # add:q #2:q, bit #3:4
    if mnem.endswith(".w"):     # word op, #xx:8: sign-extended
        ops = re.sub(r"#0x([0-9a-f]+):8", lambda x: "#%d:8" % (int(x.group(1), 16) - 256)
                     if int(x.group(1), 16) >= 0x80 else x.group(0), ops)
    return "%s\t%s" % (mnem, ops), None


def assemble(job):
    a, line, t = job
    base = min(a, t) if t is not None else a
    src = ["\t.text"]
    if t is not None and t < a:
        src += ["\t.org\t%d" % (t - base), "T:"]
    src += ["\t.org\t%d" % (a - base), "L:\t" + line]
    if t is not None and t > a:
        src += ["\t.org\t%d" % (t - base), "T:"]
    elif t == a:
        src[-1] = "T:\n" + src[-1]
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, "x.s"), "w").write("\n".join(src) + "\n")
        p = subprocess.run([AS, "-ahl=x.lst", "-o", "x.o", "x.s"], cwd=d,
                           capture_output=True, text=True)
        if p.returncode:
            err = (p.stdout + p.stderr).strip().splitlines()
            return a, None, (err[-1] if err else "exit %d" % p.returncode)
        lst = open(os.path.join(d, "x.lst"), errors="replace").read()
    # "   2 0000 1DC35805 \tL:\tcmp:g.w ..." then "   2      00FA": more
    # bytes of the same source line (same number, no address)
    code, num = b"", None
    for ln in lst.splitlines():
        m = re.match(r"\s*(\d+) ([0-9a-f]{4}) ([0-9A-F]+)\s+(.*)$", ln)
        if m and re.search(r"\bL:", m.group(4)):
            code, num = bytes.fromhex(m.group(3)), m.group(1)
            continue
        m = re.match(r"\s*(\d+)\s{6}([0-9A-F]+)\s*$", ln)
        if m and m.group(1) == num:
            code += bytes.fromhex(m.group(2))
        else:
            num = None if not m else num
    return a, code, None


def main():
    rom = open(ca.ROM, "rb").read()
    cov = open(ca.COV, "rb").read()
    addrs = [a for a in range(len(cov)) if cov[a] & 1]
    ref = ca.dis2(rom, addrs)
    # dis2's table: RTD 0x14 read as #xx:16 (the manual and the emulator:
    # 0x14 #xx:8, 0x1C #xx:16), RTE (0x0A) unknown
    for a in addrs:
        if rom[a] == 0x14 and ref[a][1] == "rtd":
            ref[a] = (2, "rtd", "#0x%x:8" % rom[a + 1])
        elif rom[a] == 0x1C and ref[a][1] == "*unknown*":
            ref[a] = (3, "rtd", "#0x%x:16" % (rom[a + 1] << 8 | rom[a + 2]))
        elif rom[a] == 0x0A:
            ref[a] = (1, "rte", "")
    jobs, gas_of = [], {}
    for a in addrs:
        n, mnem, ops = ref[a]
        if "unknown" in mnem:
            continue
        line, t = to_gas(mnem, ops, a)
        gas_of[a] = line
        jobs.append((a, line, t))
    with Pool() as pool:
        res = pool.map(assemble, jobs, chunksize=64)
    errs = [(a, e) for a, c, e in res if e]
    code = {a: c for a, c, e in res if not e}
    exact = [a for a in code if code[a] == rom[a:a + ref[a][0]]]
    new = {}
    for phase in range(8):                # gas pads the section: decode the length
        img = bytearray(0x40000)
        sel = sorted(code)[phase::8]
        for a in sel:
            img[a:a + len(code[a])] = code[a]
        new.update(ca.dis2(bytes(img), sel))
    for a in code:
        n2 = new[a][0]
        if n2 < len(code[a]) and not any(code[a][n2:]):
            code[a] = code[a][:n2]
    exact = [a for a in code if code[a] == rom[a:a + ref[a][0]]]
    rest = sorted(set(code) - set(exact))
    for phase in range(8):                # decode, never two neighbours at once
        img = bytearray(0x40000)
        sel = rest[phase::8]
        for a in sel:
            img[a:a + len(code[a])] = code[a]
        new.update(ca.dis2(bytes(img), sel))
    def canon(mnem, ops):
        m, o = ca.canon(mnem, ops)
        if m.endswith(".w"):    # -1 and 65535 are the same word
            o = re.sub(r"(?<![\w(])-?\d+(?![\w)])", lambda x: str(int(x.group(0)) & 0xFFFF), o)
        return m, o

    bad, other, longer = [], 0, 0
    for a in rest:
        n, mnem, ops = ref[a]
        n2, mnem2, ops2 = new[a]
        if canon(mnem, ops) == canon(mnem2, ops2) and n2 == len(code[a]):
            other += 1
            longer += len(code[a]) > n
        else:
            bad.append((a, mnem + " " + ops, gas_of[a], code[a].hex(), mnem2 + " " + ops2))
    print("%d instructions: %d identical bytes, %d other encoding of the same "
          "(%d longer), %d differ, %d gas errors"
          % (len(gas_of), len(exact), other, longer, len(bad), len(errs)))
    kinds = {}
    for a, e in errs:
        k = gas_of[a].split("\t")[0]
        kinds.setdefault(k, []).append((a, e))
    for k, v in sorted(kinds.items(), key=lambda x: -len(x[1])):
        print("  error x%-4d %-10s e.g. %05x %s | %s" % (len(v), k, v[0][0], gas_of[v[0][0]], v[0][1]))
    kinds = {}
    for b in bad:
        kinds.setdefault(b[1].split()[0], []).append(b)
    for k, v in sorted(kinds.items(), key=lambda x: -len(x[1])):
        print("  differ x%-4d %05x  %-30s | %-28s | %-12s | %s" % ((len(v),) + v[0]))
    return 1 if bad or errs else 0


if __name__ == "__main__":
    sys.exit(main())
