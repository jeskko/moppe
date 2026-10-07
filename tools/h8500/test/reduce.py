#!/usr/bin/env python3
"""
reduce: shrink a C file that makes rcc fail, keeping the same message.

    reduce.py file.c 'assertion text' > small.c
    reduce.py --hang [SECONDS] file.c > small.c    # rcc does not finish

Deletes lines, then replaces parenthesized subexpressions by 1, as long
as rcc -target=h8500/gas (after lcc's cpp) still prints the text, or
with --hang still runs longer than SECONDS (default 2; the endless
spilling of 2026-10-08, h8500-compiler.md).  The result may be cut off
mid-function: rcc's error recovery still reaches the bad code.
"""
import os
import re
import subprocess
import sys

TOP = os.path.realpath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
LCC = os.path.join(TOP, "reference/toolchain/lcc/build")
INC = os.path.join(TOP, "tools/h8500/lib/include")


def fails(text, msg, hang=None):
    pre = subprocess.run([os.path.join(LCC, "cpp"), "-D__H8500__", "-I" + INC],
                         input=text, capture_output=True, text=True).stdout
    try:
        p = subprocess.run([os.path.join(LCC, "rcc"), "-target=h8500/gas"],
                           input=pre, capture_output=True, text=True, timeout=hang)
    except subprocess.TimeoutExpired:
        return True
    return hang is None and msg in p.stderr


def main():
    args, hang = sys.argv[1:], None
    if args and args[0] == "--hang":
        args = args[1:]
        hang = 2.0
        if len(args) > 1:
            hang = float(args.pop(0))
        path, msg = args[0], None
    else:
        path, msg = args
    lines = open(path).read().splitlines()

    def check(text, msg):
        return fails(text, msg, hang)

    assert check("\n".join(lines), msg), "does not fail"
    # lines, in chunks halving down to one
    n = len(lines) // 2
    while n >= 1:
        i = 0
        while i < len(lines):
            trial = lines[:i] + lines[i + n:]
            if check("\n".join(trial), msg):
                lines = trial
            else:
                i += n
        n //= 2
    # subexpressions: (...) without nested parentheses first, outwards
    changed = True
    while changed:
        changed = False
        for k, line in enumerate(lines):
            for m in reversed(list(re.finditer(r"\([^()]*\)", line))):
                trial = lines[:]
                trial[k] = line[:m.start()] + "1" + line[m.end():]
                if trial[k] != line and check("\n".join(trial), msg):
                    lines = trial
                    changed = True
                    break
    print("\n".join(lines))


if __name__ == "__main__":
    main()
