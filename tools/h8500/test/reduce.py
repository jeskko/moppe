#!/usr/bin/env python3
"""
reduce: shrink a C file that makes rcc fail, keeping the same message.

    reduce.py file.c 'assertion text' > small.c

Deletes lines, then replaces parenthesized subexpressions by 1, as long
as rcc -target=h8500/asl (after lcc's cpp) still prints the text.
"""
import os
import re
import subprocess
import sys

TOP = os.path.realpath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
LCC = os.path.join(TOP, "reference/toolchain/lcc/build")
INC = os.path.join(TOP, "tools/h8500/lib/include")


def fails(text, msg):
    pre = subprocess.run([os.path.join(LCC, "cpp"), "-D__H8500__", "-I" + INC],
                         input=text, capture_output=True, text=True).stdout
    p = subprocess.run([os.path.join(LCC, "rcc"), "-target=h8500/asl"],
                       input=pre, capture_output=True, text=True)
    return msg in p.stderr


def main():
    path, msg = sys.argv[1], sys.argv[2]
    lines = open(path).read().splitlines()
    assert fails("\n".join(lines), msg), "does not fail"
    # lines, in chunks halving down to one
    n = len(lines) // 2
    while n >= 1:
        i = 0
        while i < len(lines):
            trial = lines[:i] + lines[i + n:]
            if fails("\n".join(trial), msg):
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
                if trial[k] != line and fails("\n".join(trial), msg):
                    lines = trial
                    changed = True
                    break
    print("\n".join(lines))


if __name__ == "__main__":
    main()
