#!/usr/bin/env python3
"""
Convert SDCC (asxxxx) Z80 assembler output into the as80 dialect used by
the R58 firmware, so C modules can be #included into r58.asm.

    sdcc -mz80 --sdcccall 1 -S mod.c -o mod.s
    python3 tools/sdcc2as80.py mod.s > mod.inc

Code goes to stdout.  Zero-initialised C variables (_DATA area) are
written with -d FILE as `.rs` reservations, to be #included inside the
firmware's zeroed RAM (_bss.._end); initialised C data is not supported.
External C symbols `_name` are bound to firmware symbols `name` with as80
assignments.

    python3 tools/sdcc2as80.py mod.s [-d mod_data.inc] > mod.inc
"""
import re
import sys


def operand(op):
    op = op.strip()
    if not op:
        return op
    # indexed: "-2 (ix)" -> "[ix-2]"
    m = re.match(r"^([+-]?\w+)\s*\((ix|iy)\)$", op)
    if m:
        d = m.group(1)
        if not d.startswith(("-", "+")):
            d = "+" + d
        return "[%s%s]" % (m.group(2), d)
    # memory: "(expr)" -> "[expr]" (immediate marker inside is dropped)
    if op.startswith("(") and op.endswith(")"):
        return "[" + op[1:-1].replace("#", "").strip() + "]"
    # immediate: "#expr" -> "expr"
    if op.startswith("#"):
        op = op[1:]
    # asxxxx byte selectors <(x) / >(x) -> as80 LO(x) / HI(x)
    op = re.sub(r"<\(", "LO(", op)
    op = re.sub(r">\(", "HI(", op)
    return op


def split_ops(s):
    """Split on top-level commas."""
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
    out.append(cur)
    return out


ALU1 = {"sub", "and", "or", "xor", "cp", "add", "adc", "sbc"}  # as80: implicit A


def convert(lines, prefix):
    out = []
    area = None
    defined, referenced = set(), set()
    body = []
    data = []
    scope = "top"       # asxxxx n$ labels are local between normal labels
    for raw in lines:
        line = raw.rstrip("\n")
        code = line.split(";", 1)[0].rstrip()
        comment = line.split(";", 1)[1].strip() if ";" in line else ""
        if not code.strip():
            if comment:
                body.append("\t! " + comment)
            continue
        s = code.strip()
        if s.startswith(".area"):
            area = s.split()[1]
            continue
        if s.startswith((".module", ".optsdcc", ".globl")):
            continue
        # assignment: _OUT0 = 0x0060
        m = re.match(r"^(\w+)\s*=\s*(.+)$", s)
        if m:
            defined.add(m.group(1))
            body.append("%s = %s" % (m.group(1), m.group(2)))
            continue
        # labels
        m = re.match(r"^(\w+\$?)::?\s*(.*)$", s)
        label = None
        if m and not re.match(r"^\w+\s", s.split(":")[0] + " "):
            pass
        if m:
            label = m.group(1)
            s = m.group(2)
            if label.endswith("$"):
                label = "%s_%s_L%s" % (prefix, scope, label[:-1])
            else:
                defined.add(label)
                scope = label.lstrip("_")
            if area in ("_DATA", "_BSS"):
                data.append(label + ":")
                if s.startswith(".ds"):
                    data.append("\t.rs " + s.split(None, 1)[1])
                continue
            if area not in ("_CODE", None):
                raise SystemExit("%s: label in area %s (unsupported)" % (label, area))
            body.append(label + ":")
            if not s:
                continue
        if area in ("_DATA", "_BSS") and s.startswith(".ds"):
            data.append("\t.rs " + s.split(None, 1)[1])
            continue
        if area not in ("_CODE", "_DABS", None) and s:
            raise SystemExit("unsupported content in area %s: %s" % (area, s))
        parts = s.split(None, 1)
        mn = parts[0].lower()
        ops = [operand(o) for o in split_ops(parts[1])] if len(parts) > 1 else []
        ops = [re.sub(r"\b(\d+)\$",
                      lambda k: "%s_%s_L%s" % (prefix, scope, k.group(1)), o)
               for o in ops]
        if mn == ".db":
            mn = ".byte"
        elif mn == ".dw":
            mn = ".word"
        if mn in ALU1 and len(ops) == 2 and ops[0].lower() == "a":
            ops = ops[1:]
        if mn == "ex" and [o.lower() for o in ops] == ["de", "hl"]:
            ops = ["hl", "de"]
        if mn == "ex" and [o.lower() for o in ops] == ["af", "af'"]:
            ops = ["af"]
        if mn == "jp" and ops and ops[0] in ("[hl]", "[ix]", "[iy]"):
            pass
        for o in ops:
            for name in re.findall(r"\b_\w+", o):
                referenced.add(name)
        body.append("\t%s %s" % (mn, ", ".join(ops)) +
                    ("\t! " + comment if comment else ""))
    # bind externals to firmware symbols
    for name in sorted(referenced - defined):
        if name == "___sdcc_enter_ix":
            continue            # provided by firmware/c/crt.inc
        if name.startswith("_") and not name.startswith(prefix):
            out.append("%s = %s" % (name, name[1:]))
    return out + body, data


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("-d", "--data", help="write RAM reservations here")
    a = ap.parse_args()
    prefix = "_c_" + re.sub(r"\W", "_", a.src.rsplit("/", 1)[-1].split(".")[0])
    with open(a.src) as f:
        code, data = convert(f.readlines(), prefix)
    hdr = "! generated by tools/sdcc2as80.py from %s - do not edit" % a.src
    print(hdr)
    print("\n".join(code))
    if data and not a.data:
        raise SystemExit("module has RAM variables: use -d FILE")
    if a.data:
        with open(a.data, "w") as f:
            f.write(hdr + "\n" + "\n".join(data) + "\n")
