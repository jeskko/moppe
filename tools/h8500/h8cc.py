#!/usr/bin/env python3
"""
h8cc: C for the Hitachi H8/500 (H8/532, small model) with lcc and AS.

    h8cc.py [-o out.bin] [-I dir] [-D name[=v]] [--lib sim|none] [-S] files...

Files: .c (compiled with lcc's cpp and rcc -target=h8500/asl), .asm
(hand-written assembly with the same ;@code / ;@data / ;@bss segment
markers).  All are linked as one assembly unit: crt0 first (lib/crt0.asm
unless --crt is given), then the code of every file, then the initialized
data (assembled for RAM in page 8 with PHASE, stored in ROM after the
code, copied by crt0), then bss.  --lib sim adds lib/sim.asm (putchar,
exit for h8run) and libc; the run-time helpers (lib/rt.asm) are always
linked.  -S keeps the combined .asm and the listing next to the output.

Memory: code from 0x100 in page 0 (must end below 0xFF80, the register
field); data and bss from --data (0x88000); SP from --stack (0x8FF00).
Tools: tools/h8500/lcc/build.sh builds rcc, cpp and asl.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.realpath(os.path.join(HERE, "..", ".."))
LCC = os.path.join(TOP, "reference/toolchain/lcc/build")
ASL = os.path.join(TOP, "reference/toolchain/asl-current")
LIB = os.path.join(HERE, "lib")

HEADER = """\tcpu\tHD6475328
\tmaxmode\ton
\trelaxed\ton
\tpage\t0
\tassume\tdp:8, ep:8, tp:8, br:$FF
"""


def run(cmd, **kw):
    p = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if p.returncode:
        sys.stderr.write(p.stdout + p.stderr)
        sys.exit("h8cc: %s failed" % os.path.basename(cmd[0]))
    return p.stdout


def compile_c(path, tag, args):
    cpp = [os.path.join(LCC, "cpp"), "-D__H8500__", "-I" + os.path.join(LIB, "include")]
    cpp += ["-I" + d for d in args.include] + ["-D" + d for d in args.define] + [path]
    pre = run(cpp)
    p = subprocess.run([os.path.join(LCC, "rcc"), "-target=h8500/asl", "-tag=" + tag],
                       input=pre, capture_output=True, text=True)
    if p.returncode or p.stderr.strip():
        sys.stderr.write(p.stderr)
        if p.returncode:
            sys.exit("h8cc: rcc failed on %s" % path)
    return p.stdout


def load(path, k, args):
    """a unit's assembly text: .asm as it is, .c compiled"""
    if not path.endswith(".c"):
        return open(path).read()
    tag = "%s%d" % (re.sub(r"\W", "_", os.path.basename(path)[:-2]), k)
    text = compile_c(path, tag, args)
    # asl takes no leading minus in a displacement: @(0-18,r6)
    text = text.replace("@(-", "@(0-")
    # asl: labels in column 1, everything else indented
    return "\n".join(l if re.match(r"^[\w$.]+:$", l) or l.startswith(";") else "\t" + l
                     for l in text.splitlines())


def defs(text):
    """global names a unit defines (C names start with one underscore)"""
    return set(re.findall(r"^(_[A-Za-z]\w*):", text, re.M))


def refs(text):
    return set(re.findall(r"(?<![\w$])(_[A-Za-z]\w*)", text)) - defs(text)


def split(text):
    """the ;@code / ;@data / ;@bss parts of one file"""
    parts = {"code": [], "data": [], "bss": []}
    cur = "code"
    for line in text.splitlines():
        m = re.match(r";@(code|data|bss)\s*$", line.strip())
        if m:
            cur = m.group(1)
            continue
        parts[cur].append(line)
    return parts


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="+")
    ap.add_argument("-o", "--out", default="a.bin")
    ap.add_argument("-I", dest="include", action="append", default=[])
    ap.add_argument("-D", dest="define", action="append", default=[])
    ap.add_argument("--lib", default="sim", choices=["sim", "none"])
    ap.add_argument("--crt", help="start-up file instead of lib/crt0.asm")
    ap.add_argument("--data", default="0x88000")
    ap.add_argument("--stack", default="0x8FF00")
    ap.add_argument("-S", dest="keep", action="store_true")
    args = ap.parse_args()

    inputs = [args.crt or os.path.join(LIB, "crt0.asm")] + args.files
    inputs.append(os.path.join(LIB, "rt.asm"))
    library = []
    if args.lib == "sim":
        inputs.append(os.path.join(LIB, "sim.asm"))
        libc = os.path.join(LIB, "libc")
        library = sorted(os.path.join(libc, f) for f in os.listdir(libc) if f.endswith(".c"))
    units = [(path, load(path, k, args)) for k, path in enumerate(inputs)]
    # library units only when they define something still undefined
    libunits = [(path, load(path, 100 + k, args)) for k, path in enumerate(library)]
    while True:
        defined = set().union(*(defs(t) for _, t in units))
        wanted = set().union(*(refs(t) for _, t in units)) - defined
        add = [(p, t) for p, t in libunits if defs(t) & wanted and not defs(t) & defined]
        if not add:
            break
        units += add
        libunits = [u for u in libunits if u not in add]
    code, data, bss = [], [], []
    for path, text in units:
        parts = split(text)
        name = os.path.basename(path)
        code += ["; ---- %s" % name] + parts["code"]
        if parts["data"]:
            data += ["; ---- %s" % name, "\talign\t2"] + parts["data"]
        if parts["bss"]:
            bss += ["; ---- %s" % name, "\talign\t2"] + parts["bss"]
    out = [HEADER]
    out += code
    out += ["", "\talign\t2", "__data_rom:", "\tphase\t%s" % args.data.replace("0x", "$"),
            "__data_start:"] + data + ["\talign\t2", "__data_end:", "\tdephase",
            "__code_end:", "\torg\t__data_end", "__bss_start:"] + bss
    out += ["\talign\t2", "__bss_end:", "__stack\tequ\t%s" % args.stack.replace("0x", "$"),
            "\tif\t__code_end > $FF80",
            "\terror\t\"code and initialized data reach the register field\"",
            "\tendif", ""]
    base = os.path.splitext(args.out)[0]
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "prog.asm")
        open(src, "w").write("\n".join(out))
        p = subprocess.run([os.path.join(ASL, "asl"), "-q", "-U", "-L", "-x", "prog.asm"],
                           cwd=d, capture_output=True, text=True)
        if args.keep:
            for ext in ("asm", "lst"):
                f = os.path.join(d, "prog." + ext)
                if os.path.exists(f):
                    open(base + "." + ext, "w").write(open(f, errors="replace").read())
        if p.returncode or not os.path.exists(os.path.join(d, "prog.p")):
            sys.stderr.write(p.stdout + p.stderr)
            sys.exit("h8cc: asl failed")
        run([os.path.join(ASL, "p2bin"), "-q", "-r", "$0-$FFFF", "prog.p", "prog.bin"], cwd=d)
        open(args.out, "wb").write(open(os.path.join(d, "prog.bin"), "rb").read())


if __name__ == "__main__":
    main()
