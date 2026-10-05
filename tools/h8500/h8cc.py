#!/usr/bin/env python3
"""
h8cc: C for the Hitachi H8/500 (H8/532, small model) with lcc and GNU
binutils.

    h8cc.py [-o out.bin] [-I dir] [-D name[=v]] [--lib sim|none] [-S] files...

Files: .c (lcc's cpp, then rcc -target=h8500/gas) and .s (gas syntax:
`!` comments, `.text/.data/.bss`).  Each file becomes an object; ld links
them after the start-up (lib/crt0.s unless --crt is given), against
lib/build/librt.a (run-time helpers, soft float) and, with --lib sim,
lib/build/libsim.a (libc and the h8run console).  The archives are
rebuilt when a library source or the tools are newer.  -S keeps the
generated .s files, the linker script and the map next to the output.

Memory (the linker script): code from address 0 in page 0, then the ROM
copy of the initialized data; both must end below 0xFF80 (the register
field).  Data and bss from --data (0x88000), copied and cleared by crt0;
SP from --stack (0x8FF00).  The image written is the ROM from address 0
(objcopy -O binary).
Tools: tools/h8500/lcc/build.sh builds rcc, cpp and binutils.
"""
import argparse
import glob
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.realpath(os.path.join(HERE, "..", ".."))
LCC = os.path.join(TOP, "reference/toolchain/lcc/build")
BIN = os.path.join(TOP, "reference/toolchain/binutils-h8500/bin")
LIB = os.path.join(HERE, "lib")
AS, LD, AR, OBJCOPY = (os.path.join(BIN, "h8500-hms-" + t) for t in ("as", "ld", "ar", "objcopy"))

SCRIPT = """\
OUTPUT_FORMAT("coff-h8500")
OUTPUT_ARCH(h8500)
SECTIONS
{
  .text 0 : { *(.text) __code_end = .; }
  .data %(data)s : AT (__code_end) { __data_start = .; *(.data) __data_end = .; }
  __data_rom = LOADADDR(.data);
  .bss : { __bss_start = .; *(.bss) *(COMMON) __bss_end = .; }
  __stack = %(stack)s;
}
ASSERT(__data_rom + SIZEOF(.data) <= 0xff80,
       "code and initialized data reach the register field (0xff80)")
"""


def run(cmd, **kw):
    p = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if p.returncode:
        sys.stderr.write(p.stdout + p.stderr)
        sys.exit("h8cc: %s failed" % os.path.basename(cmd[0]))
    return p


def compile_c(path, out_s, args):
    cpp = [os.path.join(LCC, "cpp"), "-D__H8500__", "-I" + os.path.join(LIB, "include")]
    cpp += ["-I" + d for d in args.include] + ["-D" + d for d in args.define] + [path]
    pre = run(cpp).stdout
    p = subprocess.run([os.path.join(LCC, "rcc"), "-target=h8500/gas"],
                       input=pre, capture_output=True, text=True)
    if p.returncode or p.stderr.strip():
        sys.stderr.write(p.stderr)
        if p.returncode:
            sys.exit("h8cc: rcc failed on %s" % path)
    open(out_s, "w").write(p.stdout)


def assemble(path, out_o):
    # -J: a .word above 0x7fff (a code address in a switch table) is not
    # an overflow here
    run([AS, "-J", "-o", out_o, path])


def build_object(path, d, args, keep=None):
    """path (.c or .s) to an object in d; keep: a directory for the .s"""
    base = os.path.splitext(os.path.basename(path))[0]
    obj = os.path.join(d, base + ".o")
    if path.endswith(".c"):
        s = os.path.join(keep or d, base + ".s")
        compile_c(path, s, args)
        assemble(s, obj)
    else:
        assemble(path, obj)
    return obj


def library(name, dirs, args):
    """lib/build/lib<name>.a from the .c and .s files of dirs, rebuilt
    when a source, an include file or a tool is newer"""
    srcs = sorted(f for d in dirs for f in glob.glob(os.path.join(LIB, d, "*.[cs]")))
    deps = srcs + glob.glob(os.path.join(LIB, "include", "*.h")) + \
        [os.path.join(LCC, "rcc"), AS]
    out = os.path.join(LIB, "build", "lib%s.a" % name)
    if os.path.exists(out) and os.path.getmtime(out) >= max(map(os.path.getmtime, deps)):
        return out
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with tempfile.TemporaryDirectory() as d:
        objs = [build_object(f, d, args) for f in srcs]
        if os.path.exists(out):
            os.remove(out)
        run([AR, "rcs", out] + objs)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="+")
    ap.add_argument("-o", "--out", default="a.bin")
    ap.add_argument("-I", dest="include", action="append", default=[])
    ap.add_argument("-D", dest="define", action="append", default=[])
    ap.add_argument("--lib", default="sim", choices=["sim", "none"])
    ap.add_argument("--crt", help="start-up file instead of lib/crt0.s")
    ap.add_argument("--data", default="0x88000")
    ap.add_argument("--stack", default="0x8FF00")
    ap.add_argument("-S", dest="keep", action="store_true")
    args = ap.parse_args()

    base = os.path.splitext(args.out)[0]
    keep = os.path.dirname(os.path.abspath(args.out)) if args.keep else None
    libs = [library("rt", ["rt"], args)]
    if args.lib == "sim":
        libs.insert(0, library("sim", ["libc", "sim"], args))
    with tempfile.TemporaryDirectory() as d:
        objs = [build_object(f, d, args, keep)
                for f in [args.crt or os.path.join(LIB, "crt0.s")] + args.files]
        script = os.path.join(keep and os.path.dirname(base) or d, os.path.basename(base) + ".ld")
        open(script, "w").write(SCRIPT % {"data": args.data, "stack": args.stack})
        elf = os.path.join(d, "prog")
        cmd = [LD, "-T", script, "-o", elf] + objs + ["--start-group"] + libs + ["--end-group"]
        if args.keep:
            cmd[1:1] = ["-Map", base + ".map"]
        run(cmd)
        run([OBJCOPY, "-O", "binary", elf, args.out])


if __name__ == "__main__":
    main()
