#!/usr/bin/env python3
"""
intgen: random integer C programs for the H8/500 lcc back end, with the
expected results worked out here under the target's rules (16-bit int,
32-bit long, two's complement wrap-around, arithmetic >> of negative
values) and embedded in the program, which reports every mismatch.

    intgen.py [--seed N] [--funcs N] [--stmts N] > prog.c
    h8cc.py -o prog.bin prog.c && h8run prog.bin    # last line: "N mismatches"

Each function has parameters, locals of all integer types (more than
the two register variables), statements that assign random expressions
(all operators, mixed types, casts, ?:, && ||, calls) to locals and
globals, compound assignments, increments, if/else and counted loops;
then it checks every variable and returns an expression.
"""
import argparse
import random


class T:
    def __init__(self, name, bits, signed):
        self.name, self.bits, self.signed = name, bits, signed

    def wrap(self, v):
        v &= (1 << self.bits) - 1
        if self.signed and v >> (self.bits - 1):
            v -= 1 << self.bits
        return v


SC = T("signed char", 8, True)
UC = T("unsigned char", 8, False)
S = T("short", 16, True)
US = T("unsigned short", 16, False)
I = T("int", 16, True)
U = T("unsigned", 16, False)
L = T("long", 32, True)
UL = T("unsigned long", 32, False)
TYPES = [SC, UC, S, US, I, U, L, UL]
ARRAYS = [("ga", I), ("gb", L), ("gc", SC), ("gd", US)]
ARITH = [I, U, L, UL]           # types after promotion


def promote(t):
    if t.bits < 16 or t is S:
        return I
    if t is US:
        return U
    return t


def common(a, b):
    a, b = promote(a), promote(b)
    if UL in (a, b):
        return UL
    if L in (a, b):
        return L                # long holds every unsigned int
    if U in (a, b):
        return U
    return I


def cdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


class E:
    """an expression: C text, type, value (the program state is fixed
    while an expression is evaluated: no side effects inside one)"""

    def __init__(self, text, t, ev):
        self.text, self.t, self.ev = text, t, ev


class Var:
    """name: the C lvalue; key: the storage it names (an array element
    reached through a pointer has the element's key)"""

    def __init__(self, name, t, scope, key=None):
        self.name, self.t, self.scope, self.key = name, t, scope, key or name


def const(t, v):
    """a constant of type t (after promotion) and value v"""
    v = t.wrap(v)
    if v < 0:                   # -(c): the same type for these ranges
        mag = -v
        if t is I and mag == 32768 or t is L and mag == 2147483648:
            # no positive constant of the type holds the magnitude
            text = "(%s - 1)" % const(t, v + 1).text
            return E(text, t, lambda env: v)
        inner = const(t, mag)
        return E("(-%s)" % inner.text, t, lambda env: v)
    suffix = {I: "", U: "U", L: "L", UL: "UL"}[t]
    return E("%d%s" % (v, suffix), t, lambda env: v)


class Gen:
    def __init__(self, rnd):
        self.r = rnd
        self.out = []
        self.globals = []
        self.nchecks = 0
        self.expect = {}

    # ---- expressions ----
    def rconst(self):
        t = self.r.choice(ARITH)
        k = self.r.random()
        if k < 0.3:
            v = self.r.randint(-4, 9)
        elif k < 0.5:
            v = self.r.choice([0x7F, 0x80, 0xFF, 0x100, 0x7FFF, 0x8000, 0xFFFF,
                               0x10000, 0x7FFFFFFF, -0x80000000, -1, -2])
        else:
            v = self.r.randint(-(1 << t.bits), 1 << t.bits)
        return const(t, v)

    def leaf(self, vars_):
        k = self.r.random()
        if k < 0.25 or not vars_:
            return self.rconst()
        v = self.r.choice(vars_)
        return E(v.name, v.t, lambda env: env[v.key])

    def expr(self, vars_, depth):
        r = self.r
        if depth <= 0 or r.random() < 0.15:
            return self.leaf(vars_)
        k = r.random()
        d = depth - 1
        if k < 0.45:
            return self.binary(r.choice(["+", "-", "*", "&", "|", "^", "+", "-",
                                         "/", "%", "<<", ">>"]), vars_, d)
        if k < 0.58:
            return self.compare(vars_, d)
        if k < 0.65:
            a = self.expr(vars_, d)
            op = r.choice(["-", "~", "!"])
            if op == "!":
                return E("(!%s)" % a.text, I, lambda env: int(a.ev(env) == 0))
            t = promote(a.t)
            if op == "-":
                return E("(-%s)" % a.text, t, lambda env: t.wrap(-a.ev(env)))
            return E("(~%s)" % a.text, t, lambda env: t.wrap(~a.ev(env)))
        if k < 0.7:
            arr, t = r.choice(ARRAYS)
            i = self.expr(vars_, d)
            return E("%s[%s & 3]" % (arr, i.text), t,
                     lambda env: env["%s[%d]" % (arr, i.ev(env) & 3)])
        if k < 0.75:
            t = r.choice(TYPES)
            a = self.expr(vars_, d)
            return E("((%s)%s)" % (t.name, a.text), t, lambda env: t.wrap(a.ev(env)))
        if k < 0.82:
            c, a, b = self.expr(vars_, d), self.expr(vars_, d), self.expr(vars_, d)
            t = common(a.t, b.t)
            return E("(%s ? %s : %s)" % (c.text, a.text, b.text), t,
                     lambda env: t.wrap(a.ev(env) if c.ev(env) else b.ev(env)))
        if k < 0.88:
            a, b = self.expr(vars_, d), self.expr(vars_, d)
            op = r.choice(["&&", "||"])
            if op == "&&":
                return E("(%s && %s)" % (a.text, b.text), I,
                         lambda env: int(bool(a.ev(env)) and bool(b.ev(env))))
            return E("(%s || %s)" % (a.text, b.text), I,
                     lambda env: int(bool(a.ev(env)) or bool(b.ev(env))))
        # a call: the identity function of a type
        t = r.choice(ARITH)
        a = self.expr(vars_, d)
        return E("id_%s(%s)" % (self.tname(t), a.text), t, lambda env: t.wrap(a.ev(env)))

    @staticmethod
    def tname(t):
        return {I: "i", U: "u", L: "l", UL: "ul"}[t]

    def binary(self, op, vars_, d):
        a, b = self.expr(vars_, d), self.expr(vars_, d)
        if op in ("<<", ">>"):
            t = promote(a.t)
            m = t.bits - 1
            if op == "<<":
                return E("(%s << (%s & %d))" % (a.text, b.text, m), t,
                         lambda env: t.wrap(a.ev(env) << (b.ev(env) & m)))
            return E("(%s >> (%s & %d))" % (a.text, b.text, m), t,
                     lambda env: t.wrap(t.wrap(a.ev(env)) >> (b.ev(env) & m)))
        t = common(a.t, b.t)
        if op in ("/", "%"):
            # b evaluated twice: no side effects, so only its code twice
            def ev(env, a=a, b=b, t=t, op=op):
                x, y = t.wrap(a.ev(env)), t.wrap(b.ev(env))
                if y == 0:
                    return 0
                q = t.wrap(cdiv(x, y))
                return q if op == "/" else t.wrap(x - cdiv(x, y) * y)
            return E("(%s ? %s %s %s : 0)" % (b.text, a.text, op, b.text), t, ev)
        f = {"+": lambda x, y: x + y, "-": lambda x, y: x - y, "*": lambda x, y: x * y,
             "&": lambda x, y: x & y, "|": lambda x, y: x | y, "^": lambda x, y: x ^ y}[op]
        return E("(%s %s %s)" % (a.text, op, b.text), t,
                 lambda env: t.wrap(f(t.wrap(a.ev(env)), t.wrap(b.ev(env)))))

    def compare(self, vars_, d):
        a, b = self.expr(vars_, d), self.expr(vars_, d)
        op = self.r.choice(["<", "<=", ">", ">=", "==", "!="])
        t = common(a.t, b.t)
        f = {"<": lambda x, y: x < y, "<=": lambda x, y: x <= y, ">": lambda x, y: x > y,
             ">=": lambda x, y: x >= y, "==": lambda x, y: x == y, "!=": lambda x, y: x != y}[op]
        return E("(%s %s %s)" % (a.text, op, b.text), I,
                 lambda env: int(f(t.wrap(a.ev(env)), t.wrap(b.ev(env)))))

    # ---- statements: each is (C lines, run(env)) ----
    def stmt(self, vars_, targets, depth, indent, loops):
        r = self.r
        k = r.random()
        ind = "\t" * indent
        if k < 0.1 and depth > 0:
            c = self.expr(vars_, 2)
            a = self.block(vars_, targets, depth - 1, indent + 1, loops, r.randint(1, 3))
            b = self.block(vars_, targets, depth - 1, indent + 1, loops, r.randint(0, 2))
            lines = ["%sif (%s) {" % (ind, c.text)] + a[0]
            lines += ["%s} else {" % ind] + b[0] + ["%s}" % ind] if b[0] else ["%s}" % ind]

            def run(env):
                (a[1] if c.ev(env) else b[1])(env)
            return lines, run
        if k < 0.18 and depth > 0 and loops:
            i = loops[0]
            n = r.randint(0, 5)
            inner = [v for v in vars_ if v.name != i]
            body = self.block(inner + [Var(i, I, "loop")], [t for t in targets if t.name != i],
                              depth - 1, indent + 1, loops[1:], r.randint(1, 3))
            lines = ["%sfor (%s = 0; %s < %d; %s++) {" % (ind, i, i, n, i)] + body[0] + ["%s}" % ind]

            def run(env):
                env[i] = 0
                while env[i] < n:
                    body[1](env)
                    env[i] += 1
            return lines, run
        if k < 0.24 and depth > 0:
            return self.switch(vars_, targets, depth, indent, loops)
        v = r.choice(targets)
        if k < 0.3:
            op = r.choice(["++", "--"])
            lines = ["%s%s%s;" % (ind, v.name, op)]

            def run(env):
                env[v.key] = v.t.wrap(env[v.key] + (1 if op == "++" else -1))
            return lines, run
        if k < 0.44:
            op = r.choice(["+", "-", "&", "|", "^"])
            e = self.expr(vars_, r.randint(1, 3))
            t = common(v.t, e.t)
            f = {"+": lambda x, y: x + y, "-": lambda x, y: x - y, "&": lambda x, y: x & y,
                 "|": lambda x, y: x | y, "^": lambda x, y: x ^ y}[op]
            lines = ["%s%s %s= %s;" % (ind, v.name, op, e.text)]

            def run(env):
                env[v.key] = v.t.wrap(f(t.wrap(env[v.key]), t.wrap(e.ev(env))))
            return lines, run
        e = self.expr(vars_, r.randint(1, 4))
        lines = ["%s%s = %s;" % (ind, v.name, e.text)]

        def run(env):
            env[v.key] = v.t.wrap(e.ev(env))
        return lines, run

    def switch(self, vars_, targets, depth, indent, loops):
        r = self.r
        ind = "\t" * indent
        e = self.expr(vars_, 2)
        if r.random() < 0.5:            # dense: a jump table
            t = common(e.t, I)
            sel = E("(%s & 7)" % e.text, t, lambda env: t.wrap(e.ev(env)) & 7)
            values = sorted(r.sample(range(8), r.randint(3, 7)))
        else:                           # sparse
            t = promote(e.t)
            sel = E(e.text, t, lambda env: t.wrap(e.ev(env)))
            values = sorted(set(t.wrap(r.choice([r.randint(-5, 5), r.randint(-40000, 70000),
                                                 r.randint(-(1 << 31), 1 << 31)]))
                                for _ in range(r.randint(2, 6))))
        cases = []                      # (label, block, break after)
        for v in values + ["default"] * (r.random() < 0.7):
            cases.append((v, self.block(vars_, targets, depth - 1, indent + 1, loops,
                                        r.randint(0, 2)), r.random() < 0.8))
        r.shuffle(cases)
        lines = ["%sswitch (%s) {" % (ind, sel.text)]
        for v, b, brk in cases:
            label = "default" if v == "default" else "case %s" % const(t, v).text
            lines.append("%s%s: ;" % (ind, label))
            lines += b[0]
            if brk:
                lines.append("%s\tbreak;" % ind)
        lines.append("%s}" % ind)

        def run(env):
            x = sel.ev(env)
            start = [n for n, c in enumerate(cases) if c[0] == x] or \
                    [n for n, c in enumerate(cases) if c[0] == "default"]
            if not start:
                return
            for v, b, brk in cases[start[0]:]:
                b[1](env)
                if brk:
                    break
        return lines, run

    def block(self, vars_, targets, depth, indent, loops, n):
        parts = [self.stmt(vars_, targets, depth, indent, loops) for _ in range(n)]
        lines = [l for p in parts for l in p[0]]

        def run(env):
            for p in parts:
                p[1](env)
        return lines, run

    def check(self, ind, text, value):
        self.nchecks += 1
        return "%sck(%d, (unsigned long)(%s), 0x%XUL);" % (ind, self.nchecks, text,
                                                          value & 0xFFFFFFFF)

    # ---- the program ----
    def program(self, nfuncs, nstmts):
        r = self.r
        self.globals = [Var("g%d" % k, t, "global") for k, t in enumerate(TYPES * 2)]
        env = {}
        init = []
        for v in self.globals:
            x = v.t.wrap(r.randint(-(1 << 31), 1 << 31))
            env[v.key] = x
            init.append("%s %s = %s;" % (v.t.name, v.name, const(promote(v.t), x).text))
        for arr, t in ARRAYS:
            vals = [t.wrap(r.randint(-(1 << 31), 1 << 31)) for _ in range(4)]
            for n, x in enumerate(vals):
                env["%s[%d]" % (arr, n)] = x
            init.append("%s %s[4] = { %s };" % (t.name, arr, ", ".join(const(promote(t), x).text for x in vals)))
            self.globals += [Var("%s[%d]" % (arr, n), t, "global") for n in range(4)]

        funcs, calls = [], []
        for fn in range(nfuncs):
            params = [Var("p%d" % k, r.choice(TYPES), "param") for k in range(r.randint(0, 4))]
            locs = [Var("v%d" % k, r.choice(TYPES), "local") for k in range(r.randint(2, 8))]
            rt = r.choice(ARITH)
            # pointers into the arrays: *p and p[1] alias elements
            ptrs = []
            for n, (arr, t) in enumerate(r.sample(ARRAYS, 2)):
                k = r.randrange(3)
                ptrs.append(("q%d" % n, arr, t, k))
            pvars = []
            for q, arr, t, k in ptrs:
                pvars += [Var("(*%s)" % q, t, "ptr", "%s[%d]" % (arr, k)),
                          Var("%s[1]" % q, t, "ptr", "%s[%d]" % (arr, k + 1))]
            vars_ = self.globals + params + locs + pvars
            targets = params + locs + r.sample(self.globals, 4) + r.sample(pvars, 2)
            lines = ["%s f%d(%s)" % (rt.name, fn, ", ".join("%s %s" % (p.t.name, p.name)
                                                             for p in params) or "void"), "{"]
            lines += ["\tint i0, i1;"]
            lines += ["\t%s *%s = &%s[%d];" % (t.name, q, arr, k) for q, arr, t, k in ptrs]
            linit = []
            for v in locs:
                e = self.expr(self.globals + params, 2)
                linit.append((v, e))
                lines.append("\t%s %s = %s;" % (v.t.name, v.name, e.text))
            body = self.block(vars_, targets, 2, 1, ["i0", "i1"], nstmts)
            lines += body[0]
            ret = self.expr(vars_, 3)
            args = [const(promote(p.t), p.t.wrap(r.randint(-(1 << 31), 1 << 31))) for p in params]

            # run it: parameters take the converted arguments
            fenv = dict(env)
            for p, a in zip(params, args):
                fenv[p.name] = p.t.wrap(a.ev(fenv))
            for v, e in linit:
                fenv[v.key] = v.t.wrap(e.ev(fenv))
            body[1](fenv)
            for v in params + locs:
                lines.append(self.check("\t", v.name, fenv[v.key]))
            want = rt.wrap(ret.ev(fenv))
            lines.append("\treturn %s;" % ret.text)
            lines.append("}")
            for v in self.globals:
                env[v.key] = fenv[v.key]
            funcs += lines
            calls.append(self.check("\t", "f%d(%s)" % (fn, ", ".join(a.text for a in args)), want))
        main = ["int main(void)", "{"] + calls
        main += [self.check("\t", v.name, env[v.key]) for v in self.globals]
        main += ['\tprintf("%d mismatches\\n", bad);', "\treturn 0;", "}"]
        head = ["/* generated by intgen.py */", "#include <stdio.h>", "static int bad;",
                "static void ck(int n, unsigned long got, unsigned long want)",
                "{", "\tif (got != want) {",
                '\t\tprintf("check %d: %lx want %lx\\n", n, got, want);',
                "\t\tbad++;", "\t}", "}"]
        for t in ARITH:
            head.append("%s id_%s(%s x) { return x; }" % (t.name, self.tname(t), t.name))
        return "\n".join(head + init + funcs + main) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--funcs", type=int, default=6)
    ap.add_argument("--stmts", type=int, default=12)
    a = ap.parse_args()
    print(Gen(random.Random(a.seed)).program(a.funcs, a.stmts), end="")


if __name__ == "__main__":
    main()
