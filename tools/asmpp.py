#!/usr/bin/env python3
"""
Post-cpp filter for the sdasz80 firmware build (notes/toolchain.md):

    cpp -traditional ... r58.s | python3 asmpp.py > r58.pp.s

 - '@' separates statements (cpp macros cannot produce newlines).
 - Numeric local labels as in as80: '1:' ... '1b' (nearest before),
   '1f' (nearest after), digits 1-9; renamed to __L<d>_<n>.
 - Absolute addressing.  sdas treats every label, even in an ABS area, as
   relocatable, and then refuses (or silently mis-assembles!) arithmetic
   such as 'lbl & 0xFF', 'lbl >> 8' or 'HI(.) == HI(lbl)'.  So in an area
   that starts with
        .area NAME (ABS)
        .org  N
   every label 'x:' becomes the absolute symbol 'x = N + . - __base_NAME',
   every '.' used in an expression becomes the same absolute value, and a
   later '.org E' becomes '.ds E - .' (the gap is 0xFF in the binary, as
   with as80).  The whole area stays one piece, so the location counter
   and the absolute value never disagree.
 - cpp line markers are dropped; duplicate labels are an error.
"""
import re
import sys

SCAN = re.compile(r"""
    (?P<str>"[^"]*")
  | (?P<chr>'.'?)
  | (?P<com>;.*)
  | (?P<sep>@)
  | (?P<word>[A-Za-z_.$0-9][\w.$]*)
  | (?P<ws>\s+)
  | (?P<other>.)
""", re.X)

LOCLAB = re.compile(r"[1-9]")
LOCREF = re.compile(r"[1-9][fb]")
SYM = re.compile(r"[A-Za-z_.$][\w.$]*")


class PP:
    def __init__(self):
        self.count = [0] * 10
        self.area = None        # current area name
        self.base = {}          # area -> base expression (text)
        self.want_org = None    # area waiting for its first .org
        self.labels = set()
        self.out = []
        self.lineno = 0

    def err(self, msg):
        sys.exit("asmpp: line %d: %s" % (self.lineno, msg))

    def here(self):
        return "%s + . - __base_%s" % (self.base[self.area], self.area)

    def absolute(self):
        return self.area in self.base

    def statement(self, toks, indent):
        """toks: list of (kind, text) of one statement (no separators)."""
        # strip leading whitespace
        while toks and toks[0][0] == "ws":
            toks = toks[1:]
        pre = []            # lines emitted before the statement
        # labels
        while len(toks) >= 2 and toks[0][0] == "word" and toks[1] == ("other", ":"):
            name = toks[0][1]
            if LOCLAB.fullmatch(name):
                d = int(name)
                self.count[d] += 1
                name = "__L%d_%d" % (d, self.count[d])
            elif not SYM.fullmatch(name):
                self.err("bad label %r" % name)
            if name in self.labels:
                self.err("label %s defined twice" % name)
            self.labels.add(name)
            if self.absolute():
                pre.append("%s = %s" % (name, self.here()))
            else:
                pre.append(name + ":")
            toks = toks[2:]
            while toks and toks[0][0] == "ws":
                toks = toks[1:]
        words = [t for k, t in toks if k == "word"]
        head = words[0].lower() if words and toks and toks[0][0] == "word" else ""
        # area bookkeeping
        if head == ".area":
            m = re.match(r"\.area\s+(\w+)\s*(\(.*\))?", "".join(t for _, t in toks), re.I)
            self.area = m.group(1)
            if m.group(2) and "ABS" in m.group(2).upper() and self.area not in self.base:
                self.want_org = self.area
        elif head == ".org":
            expr = "".join(t for _, t in toks)[4:].strip()
            if self.want_org == self.area:
                self.want_org = None
                self.base[self.area] = "(%s)" % expr
                return pre + ["".join(t for _, t in toks), "__base_%s:" % self.area]
            if self.absolute():
                toks = [("word", ".ds"), ("ws", " "), ("other", "(" + expr + ") - "),
                        ("word", ".")]
        res, uses_dot = [], False
        for i, (k, t) in enumerate(toks):
            if k == "word":
                if LOCREF.fullmatch(t):
                    d = int(t[0])
                    n = self.count[d] + (t[1] == "f")
                    if n == 0:
                        self.err("%s without a preceding %d:" % (t, d))
                    t = "__L%d_%d" % (d, n)
                elif t == "." and self.absolute() and i > 0:
                    uses_dot = True
                    t = "__here"
            res.append(t)
        if uses_dot:
            pre.append("__here = " + self.here())
        body = "".join(res).rstrip()
        lines = [indent + p if not p.endswith(":") or p.startswith("__base") else p
                 for p in pre]
        if body.strip():
            lines.append(indent + body.strip() if pre else body)
        return lines

    def line(self, line):
        if re.match(r"#\s*\d+\s", line) or line.startswith("# "):
            return                  # cpp line marker
        indent = re.match(r"[ \t]*", line).group() or "\t"
        stmts, cur, comment = [], [], ""
        for m in SCAN.finditer(line):
            k, t = m.lastgroup, m.group()
            if k == "chr" and m.start() > 0 and re.match(r"\w", line[m.start() - 1]):
                cur.append(("other", "'"))          # ex af, af'
                if len(t) > 1:
                    cur.append(("other", t[1:]))
                continue
            if k == "com":
                comment = t
            elif k == "sep":
                stmts.append(cur)
                cur = []
            else:
                cur.append((k, t))
        stmts.append(cur)
        out = []
        for st in stmts:
            out.extend(self.statement(st, indent))
        if comment:
            if out:
                out[-1] += "\t" + comment
            else:
                out.append(indent + comment)
        if not out:
            out.append("")
        self.out.extend(out)

    def run(self, text):
        for self.lineno, line in enumerate(text.split("\n"), 1):
            self.line(line)
        return "\n".join(self.out) + "\n"


def main():
    """asmpp.py [--labels FILE] < in > out; FILE gets the label names (the
    emulator harness uses them to tell code labels from equates)."""
    src = sys.stdin.buffer.read().decode("latin-1")
    pp = PP()
    sys.stdout.buffer.write(pp.run(src).encode("latin-1"))
    if len(sys.argv) == 3 and sys.argv[1] == "--labels":
        with open(sys.argv[2], "w") as f:
            f.write("".join(n + "\n" for n in sorted(pp.labels)
                            if not n.startswith("__L")))


if __name__ == "__main__":
    main()
