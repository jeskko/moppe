#!/usr/bin/env python3
"""
One-shot converter: as80 ("jas") Z80 source -> sdasz80 source for the
cpp + asmpp.py + sdasz80 pipeline (see notes/toolchain.md).

    python3 tools/r58/as80tosdas.py r58/r58.asm > r58/r58.s

What changes:
  [mem]            -> (mem)            memory operands
  ld a, 5          -> ld a, #5         immediates get '#'
  ! comment        -> ; comment        (# comments too)
  a; b             -> separate lines   (inside #define bodies: 'a @ b')
  ex af            -> ex af, af'
  ld iv, a         -> ld i, a;  im2 -> im 2;  hx/lx/hy/ly -> ixh/ixl/iyh/iyl
  add x, adc x, sbc x (8-bit, implicit A) -> add a, x ...
  .byte/.word/.rs  -> .db/.dw/.ds
  .align b[,v], .fill n,v -> ALIGN(b, v), FILL(n, v)       (r58/asm.h)
  ASSERT(a == b)   -> ASSERT_EQ(a, b)  (also LT, GT, LE, GE, NZ)
  .text/.data      -> .area ROM (ABS) / .area RAM (ABS)
  name BYTE        -> name: BYTE       (BUF/BYTE/WORD/FREQ/STRING macros)
  expressions      -> reparenthesised where sdas precedence differs from as80
  strings with escapes, 'x' escapes, two-char constants, octal -> plain bytes

Kept as is: cpp directives and macros (HI/LO become macros in asm.h),
numeric local labels 1: 1f 1b (resolved by tools/r58/asmpp.py after cpp).
"""
import re
import sys

# ---------------------------------------------------------------- lexer

TOK = re.compile(r"""
    (?P<ws>[ \t\r\f\v]+)
  | (?P<ccom>/\*.*?\*/)
  | (?P<com>[!#].*)
  | (?P<str>"(?:\\.|[^"\\])*")
  | (?P<chr>'(?:\\.|[^'\\])*')
  | (?P<num>[0-9][0-9A-Za-z_]*)
  | (?P<id>[._A-Za-z][_A-Za-z0-9]*)
  | (?P<op><<|>>|<=|>=|==|&&|\|\||[-+*/%&|^~()\[\],:;=<>])
  | (?P<bs>\\)
  | (?P<other>.)
""", re.X)


class Tok:
    __slots__ = ("k", "t")

    def __init__(self, k, t):
        self.k, self.t = k, t

    def __repr__(self):
        return "%s:%r" % (self.k, self.t)


def lex(s):
    """'!'/'#' inside parentheses are text (free-text macro arguments such
    as REC's help string), not comments."""
    out, i, depth = [], 0, 0
    while i < len(s):
        if depth > 0 and s[i] in "!#":
            out.append(Tok("other", s[i]))
            i += 1
            continue
        m = TOK.match(s, i)
        out.append(Tok(m.lastgroup, m.group()))
        if m.group() == "(":
            depth += 1
        elif m.group() == ")" and depth:
            depth -= 1
        i = m.end()
    return out


ESC = {"n": 10, "a": 7, "b": 8}


def unescape(body):
    """as80 getq(): string/char body -> list of byte values."""
    out, i = [], 0
    while i < len(body):
        c = body[i]
        i += 1
        if c != "\\":
            out.append(ord(c))
            continue
        c = body[i]
        i += 1
        if c in ESC:
            out.append(ESC[c])
        elif c in "01234567":
            v = int(c)
            for _ in range(2):
                if i < len(body) and body[i] in "01234567":
                    v = v * 8 + int(body[i])
                    i += 1
                else:
                    break
            out.append(v)
        elif c in "xX":
            v = int(body[i], 16)
            i += 1
            if i < len(body) and body[i] in "0123456789abcdefABCDEF":
                v = v * 16 + int(body[i], 16)
                i += 1
            out.append(v)
        else:
            out.append(ord(c))
    return out


def number_value(t):
    if re.fullmatch(r"0[bB][01]+", t):
        return int(t[2:], 2)
    if re.fullmatch(r"0[xX][0-9a-fA-F]+", t):
        return int(t, 16)
    if re.fullmatch(r"0[0-7]*", t):
        return int(t, 8)
    if re.fullmatch(r"[1-9][0-9]*", t):
        return int(t)
    raise SyntaxError("bad number %r" % t)


def is_loclab(t):
    return re.fullmatch(r"[1-9][fb]", t) is not None

# ---------------------------------------------------------- expressions

AS80_PREC = {"+": 1, "-": 1, "*": 2, "/": 2, "%": 2,
             "==": 3, "<": 3, ">": 3, "<=": 3, ">=": 3, "||": 3, "&&": 3,
             "<<": 4, ">>": 4, "|": 5, "&": 5, "^": 5}
SDAS_PREC = {"|": 1, "&": 3, "^": 4, "<<": 5, ">>": 5,
             "+": 7, "-": 7, "*": 10, "/": 10, "%": 10}
CMP = {"==", "<", ">", "<=", ">="}


class Node:
    def __init__(self, kind, *a):
        self.kind, self.a = kind, a


class ExprParser:
    def __init__(self, toks):
        self.t = [x for x in toks if x.k not in ("ws", "ccom")]
        self.i = 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def take(self):
        x = self.peek()
        if x is None:
            raise SyntaxError("unexpected end of expression")
        self.i += 1
        return x

    def expect(self, text):
        x = self.take()
        if x.t != text:
            raise SyntaxError("expected %r, got %r" % (text, x.t))

    def parse(self):
        e = self.binary(0)
        if self.peek() is not None:
            raise SyntaxError("junk after expression: %r" % self.peek().t)
        return e

    def binary(self, minp):
        left = self.unary()
        while True:
            x = self.peek()
            if x is None or x.k != "op" or x.t not in AS80_PREC:
                return left
            p = AS80_PREC[x.t]
            if p < minp:
                return left
            self.take()
            right = self.binary(p + 1)
            left = Node("bin", x.t, left, right)

    def unary(self):
        x = self.peek()
        if x is not None and x.k == "op" and x.t in "+-~":
            self.take()
            return Node("un", x.t, self.unary())
        return self.primary()

    def primary(self):
        x = self.take()
        if x.k == "num":
            if is_loclab(x.t):
                return Node("raw", x.t)
            v = number_value(x.t)
            if re.fullmatch(r"0[0-7]+", x.t) and v >= 8:
                return Node("raw", str(v))
            return Node("raw", x.t)
        if x.k == "str":
            return Node("raw", x.t)
        if x.k == "chr":
            b = unescape(x.t[1:-1])
            if len(b) == 1:
                c = chr(b[0])
                if b[0] < 0x20 or b[0] > 0x7e or c in "\\'\"":
                    return Node("raw", "0x%02X" % b[0])
                return Node("raw", "'%s'" % c)
            if len(b) == 2:
                return Node("raw", "0x%04X" % (b[0] << 8 | b[1]))
            raise SyntaxError("bad char constant %s" % x.t)
        if x.k == "id":
            if x.t == ".":
                return Node("raw", ".")
            nx = self.peek()
            if nx is not None and nx.t == "(":
                self.take()
                args = []
                if self.peek() is not None and self.peek().t == ")":
                    self.take()
                    return Node("call", x.t, args)
                while True:
                    args.append(self.binary(0))
                    y = self.take()
                    if y.t == ")":
                        break
                    if y.t != ",":
                        raise SyntaxError("bad call args")
                if x.t == "SIZE":
                    return Node("size", args[0])
                return Node("call", x.t, args)
            return Node("raw", x.t)
        if x.t == "(":
            e = self.binary(0)
            self.expect(")")
            return Node("paren", e)
        raise SyntaxError("unexpected %r" % x.t)


def emit(n, top=True):
    """Print for sdas; parens added only where sdas would group differently."""
    k = n.kind
    if k == "raw":
        return n.a[0]
    if k == "paren":
        return "(" + emit(n.a[0]) + ")"
    if k == "call":
        return "%s(%s)" % (n.a[0], ", ".join(emit(a) for a in n.a[1]))
    if k == "size":
        raise SyntaxError("SIZE() needs special handling")
    if k == "un":
        s = emit(n.a[1], False)
        if n.a[1].kind in ("bin", "un"):
            s = "(" + s + ")"
        return n.a[0] + s
    op, l, r = n.a
    if op not in SDAS_PREC:
        raise SyntaxError("operator %s not available in sdas" % op)
    p = SDAS_PREC[op]
    ls, rs = emit(l, False), emit(r, False)
    if l.kind == "bin" and SDAS_PREC.get(l.a[0], 99) < p:
        ls = "(" + ls + ")"
    if r.kind == "bin" and SDAS_PREC.get(r.a[0], 99) <= p:
        rs = "(" + rs + ")"
    return "%s %s %s" % (ls, op, rs)


def orig_ok(n):
    """True if the original text parses the same under sdas precedence
    and needs no token rewrites."""
    k = n.kind
    if k == "raw":
        return True
    if k == "paren":
        return orig_ok(n.a[0])
    if k == "call":
        return all(orig_ok(a) for a in n.a[1])
    if k == "size":
        return False
    if k == "un":
        return n.a[1].kind not in ("bin",) and orig_ok(n.a[1])
    op, l, r = n.a
    if op not in SDAS_PREC:
        return False
    p = SDAS_PREC[op]
    if l.kind == "bin" and SDAS_PREC.get(l.a[0], 99) < p:
        return False
    if r.kind == "bin" and SDAS_PREC.get(r.a[0], 99) <= p:
        return False
    return orig_ok(l) and orig_ok(r)


def text(toks):
    return "".join(t.t for t in toks).strip()


def conv_expr(toks, size_label=None):
    """as80 expression tokens -> sdas expression text."""
    toks = strip_ws(toks)
    n = ExprParser(toks).parse()
    n = subst_size(n, size_label)
    # original token text is kept when it already means the same to sdas
    # and contains no token that needs rewriting
    if orig_ok(n) and all(tok_plain(t) for t in toks) and \
            not any(t.t == "SIZE" for t in toks):
        return text(toks)
    return emit(n)


def subst_size(n, label):
    """as80 SIZE(sym): bytes emitted by the statement that defines sym.
    Becomes an equate sym_size, emitted after that statement."""
    if n.kind == "size":
        sym = n.a[0]
        if sym.kind != "raw":
            raise SyntaxError("SIZE() of an expression")
        return Node("raw", sym.a[0] + "_size")
    if n.kind in ("paren",):
        return Node("paren", subst_size(n.a[0], label))
    if n.kind == "un":
        return Node("un", n.a[0], subst_size(n.a[1], label))
    if n.kind == "bin":
        return Node("bin", n.a[0], subst_size(n.a[1], label), subst_size(n.a[2], label))
    if n.kind == "call":
        return Node("call", n.a[0], [subst_size(a, label) for a in n.a[1]])
    return n


def tok_plain(t):
    if t.k == "other":
        raise SyntaxError("unexpected %r" % t.t)
    if t.k == "chr":
        b = unescape(t.t[1:-1])
        return len(b) == 1 and 0x20 <= b[0] <= 0x7e and chr(b[0]) not in "\\'\""
    if t.k == "num" and not is_loclab(t.t):
        return not (re.fullmatch(r"0[0-7]+", t.t) and number_value(t.t) >= 8)
    return True


def strip_ws(toks):
    a, b = 0, len(toks)
    while a < b and toks[a].k in ("ws", "ccom"):
        a += 1
    while b > a and toks[b - 1].k in ("ws", "ccom"):
        b -= 1
    return toks[a:b]


def split_commas(toks):
    parts, cur, depth = [], [], 0
    for t in toks:
        if t.t in ("(", "["):
            depth += 1
        elif t.t in (")", "]"):
            depth -= 1
        if t.t == "," and depth == 0:
            parts.append(cur)
            cur = []
        else:
            cur.append(t)
    parts.append(cur)
    return parts

def join_args(body, conv):
    """Join converted operands with the original spacing after each comma."""
    parts = split_commas(body)
    res = conv[0]
    for i, c in enumerate(conv[1:], 1):
        ws = ""
        if i < len(parts) and parts[i] and parts[i][0].k == "ws":
            ws = parts[i][0].t
        elif i >= len(parts):
            ws = " "
        res += "," + ws + c
    return res


def split_semis(toks):
    """Statements are separated by ';' outside parentheses (cpp macro
    arguments may contain ';')."""
    stmts, cur, depth = [], [], 0
    for t in toks:
        if t.t == "(":
            depth += 1
        elif t.t == ")" and depth:
            depth -= 1
        if t.t == ";" and depth == 0:
            stmts.append(cur)
            cur = []
        else:
            cur.append(t)
    stmts.append(cur)
    return stmts

# --------------------------------------------------------- instructions

REG8 = {"a", "b", "c", "d", "e", "h", "l"}
REGS = REG8 | {"i", "r", "iv", "af", "bc", "de", "hl", "sp", "ix", "iy",
               "hx", "lx", "hy", "ly"}
CC = {"nz", "z", "nc", "c", "po", "pe", "p", "m"}
IMM_MN = {"ld", "add", "adc", "sub", "sbc", "and", "or", "xor", "cp"}
IMPLICIT_A = {"add", "adc", "sbc"}
REG_RENAME = {"iv": "i", "hx": "ixh", "lx": "ixl", "hy": "iyh", "ly": "iyl"}
MNEMONICS = set("""
ld push pop ex exx ldi ldir ldd lddr cpi cpir cpd cpdr add adc sub sbc and
or xor cp inc dec daa cpl neg ccf scf nop halt di ei im0 im1 im2 rlca rla
rrca rra rlc rl rrc rr sla sra srl rld rrd bit set res jp jr djnz call ret
reti retn rst in ini inir ind indr out outi otir outd otdr
""".split())


def conv_operand(mn, toks, is_cc_pos=False):
    toks = strip_ws(toks)
    if not toks:
        raise SyntaxError("empty operand")
    low = text(toks).lower()
    if len(toks) == 1 and toks[0].k == "id":
        w = toks[0].t.lower()
        if w in REGS or (is_cc_pos and w in CC):
            return REG_RENAME.get(w, toks[0].t), "reg"
    if toks[0].t == "[" and toks[-1].t == "]":
        inner = strip_ws(toks[1:-1])
        w = text(inner).lower()
        if len(inner) == 1 and inner[0].k == "id" and w in REGS:
            return "(" + inner[0].t + ")", "mem"
        if inner and inner[0].k == "id" and inner[0].t.lower() in ("ix", "iy") \
                and len(inner) > 1 and inner[1].t in "+-":
            # [ix + d]: keep spacing, convert d
            head = inner[0].t
            rest = inner[1:]
            sign = rest[0].t
            d = conv_expr(rest[1:])
            ws = " " if len(rest) > 1 and rest[1].k == "ws" else ""
            ws0 = " " if toks[2].k == "ws" or (len(toks) > 2 and toks[1].k == "ws") else ""
            # reproduce the original compactness
            orig = text(toks[1:-1])
            sp = " " if (" " + sign + " ") in orig else ""
            return "(%s%s%s%s%s)" % (head, sp, sign, sp, d), "mem"
        return "(" + conv_expr(inner) + ")", "mem"
    e = conv_expr(toks)
    if mn in IMM_MN:
        return "#" + e, "imm"
    if e.startswith("(") and mn in ("jp", "jr", "call", "djnz"):
        e = "0 + " + e
    return e, "expr"


def conv_instruction(mn_tok, rest):
    mn = mn_tok.t.lower()
    ops = split_commas(rest) if strip_ws(rest) else []
    if mn in ("im0", "im1", "im2"):
        return "im", [mn[2]]
    if mn == "ex" and len(ops) == 1 and text(ops[0]).lower() == "af":
        return mn_tok.t, [text(ops[0]), text(ops[0]) + "'"]
    if mn == "ex" and len(ops) == 2 and text(ops[0]).lower() in ("hl", "ix", "iy"):
        # sdas wants ex de, hl and ex (sp), hl
        a, b = conv_operand(mn, ops[0])[0], conv_operand(mn, ops[1])[0]
        return mn_tok.t, [b, a]
    out = []
    for i, o in enumerate(ops):
        cc_pos = (i == 0 and mn in ("jp", "jr", "call", "ret") and len(ops) >= 1
                  and (len(ops) == 2 or mn == "ret"))
        s, kind = conv_operand(mn, o, cc_pos)
        out.append(s)
    if mn in IMPLICIT_A and len(out) == 1:
        out = ["a"] + out
    return mn_tok.t, out

# ------------------------------------------------------------ statements


class Converter:
    def __init__(self):
        self.macros = {}          # name -> "stmt" | "expr" | "label"
        self.sized = set()        # symbols used in SIZE()
        self.notes = []
        self.errors = []
        self.lineno = 0

    # one statement (tokens between ';'), returns list of output strings
    def statement(self, toks, in_define=False):
        self.cur_labels = []
        res = self._statement(toks, in_define)
        for l in self.cur_labels:
            if l in self.sized:
                res.append("%s_size = . - %s" % (l, l))
        return res

    def _statement(self, toks, in_define=False):
        toks = list(toks)
        labels = []
        labtext = ""          # labels with their original spacing
        while toks and toks[0].k == "ws":
            toks = toks[1:]
        while True:
            if len(toks) >= 2 and toks[0].k in ("id", "num") and toks[1].t == ":":
                labels.append(toks[0].t + ":")
                labtext += toks[0].t + ":"
                toks = toks[2:]
                ws = ""
                while toks and toks[0].k == "ws":
                    ws += toks[0].t
                    toks = toks[1:]
                labtext += ws
                continue
            break
        self.cur_labels = [l[:-1] for l in labels]
        s = strip_ws(toks)
        if not s:
            return [labtext.rstrip()] if labels else []
        head = s[0]
        body = s[1:]
        lab = labtext.rstrip()
        lab_sep = labtext[len(lab):] if labels else ""
        if labels and not lab_sep:
            lab_sep = " "
        # gap between head and operands, preserved
        gap = ""
        if body and body[0].k == "ws":
            gap = body[0].t
        if not gap:
            gap = " "
        size_label = labels[-1][:-1] if labels else None

        def out(stmt):
            return [lab + lab_sep + stmt]

        # name BYTE / name BUF(n)
        if head.k == "id" and body and strip_ws(body) and \
                strip_ws(body)[0].k == "id" and \
                self.macros.get(strip_ws(body)[0].t) == "label":
            self.cur_labels.append(head.t)
            return out(head.t + ":" + gap + self.macro_call(strip_ws(body)))
        # equates
        b = strip_ws(body)
        if head.k == "id" and b and b[0].t in ("=",) or \
                (head.k == "id" and b and b[0].k == "id" and b[0].t.lower() == "equ"):
            eq = b[0]
            ws1 = body[0].t if body[0].k == "ws" else ""
            after = body[body.index(eq) + 1:]
            ws2 = after[0].t if after and after[0].k == "ws" else " "
            return out("%s%s=%s%s" % (head.t, ws1 or " ", ws2, conv_expr(after)))
        if head.k == "id":
            h = head.t
            hl = h.lower()
            if hl in MNEMONICS:
                mn, ops = conv_instruction(head, body)
                if not ops:
                    return out(mn)
                return out(mn + gap + join_args(body, ops))
            if h == "ASSERT":
                return out(self.assertion(b, size_label))
            if hl == ".byte" and b and b[0].t.lower() == ".cksum":
                # as80 .cksum(0, .): the ROM checksum byte; sdas cannot
                # read back emitted bytes, tools/r58/ihx2bin.py patches it
                if text(b).replace(" ", "") != ".cksum(0,.)":
                    raise SyntaxError("only .cksum(0, .) is supported")
                return [lab + lab_sep + "rom_cksum:",
                        ".db" + gap + "0\t; ROM checksum: 256 - sum(ROM[0 .. rom_cksum - 1]), set by ihx2bin.py",
                        "rom_end:\t\t; linked code (C modules, SDCC library) follows (tools/r58/link.py)"]
            if hl == ".byte" or hl == ".word":
                d = ".db" if hl == ".byte" else ".dw"
                args = [conv_expr(a, size_label) for a in split_commas(body)]
                return out(d + gap + join_args(body, args))
            if hl == ".rs":
                n = conv_expr(body) if b else "1"
                return out(".ds" + gap + n)
            if hl == ".org":
                return out(".org" + gap + conv_expr(body))
            if hl == ".text":
                return out(".area" + gap + "ROM (ABS)")
            if hl == ".data":
                return out(".area" + gap + "RAM (ABS)")
            if hl == ".align":
                a = split_commas(body)
                v = conv_expr(a[1]) if len(a) > 1 else "0"
                return out("ALIGN(%s, %s)" % (conv_expr(a[0]), v))
            if hl == ".fill":
                a = split_commas(body)
                return out("FILL(%s, %s)" % (conv_expr(a[0]), conv_expr(a[1])))
            if hl in (".ascii", ".asciz"):
                return self.ascii(lab, lab_sep, gap, body, hl == ".asciz")
            if h in self.macros:
                return out(self.macro_call(s))
        raise SyntaxError("unknown statement %r" % text(s))

    def macro_call(self, s):
        """A statement made of macro invocations; convert args that parse
        as expressions, keep the rest (free text) as is."""
        res, i = [], 0
        while i < len(s):
            t = s[i]
            if t.k == "ws":
                res.append(t.t)
                i += 1
                continue
            if t.k != "id" or t.t not in self.macros:
                # macro bodies end in a separator, so a plain statement
                # may follow the calls (X(..) X(..) .byte STEP_25)
                rest = self.statement(s[i:])
                if len(rest) != 1:
                    raise SyntaxError("statement after macro calls: %r" % text(s[i:]))
                res.append(rest[0])
                break
            j = i + 1
            while j < len(s) and s[j].k == "ws":
                j += 1
            if j < len(s) and s[j].t == "(":
                depth, k = 0, j
                while True:
                    if s[k].t == "(":
                        depth += 1
                    elif s[k].t == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    k += 1
                args = split_commas(s[j + 1:k])
                conv = []
                for a in args:
                    lead = a[0].t if a and a[0].k == "ws" else ""
                    try:
                        conv.append(lead + conv_expr(a))
                    except SyntaxError:
                        conv.append(text(a) if not lead else lead + text(a))
                res.append(t.t + "(" + ",".join(conv) + ")")
                i = k + 1
            else:
                res.append(t.t)
                i += 1
        return "".join(res).strip()

    def assertion(self, b, size_label):
        if not (b and b[0].t == "(" and b[-1].t == ")"):
            raise SyntaxError("ASSERT syntax")
        inner = strip_ws(b[1:-1])
        n = ExprParser(inner).parse()
        depth, cuts = 0, []
        for i, t in enumerate(inner):
            if t.t in ("(", "["):
                depth += 1
            elif t.t in (")", "]"):
                depth -= 1
            elif depth == 0 and t.k == "op" and t.t in CMP:
                cuts.append(i)
        if not cuts:
            return "ASSERT_NZ(%s)" % conv_expr(inner, size_label)
        if len(cuts) > 1:
            raise SyntaxError("several comparisons in ASSERT")
        cut = cuts[0]
        op = inner[cut].t
        if not (n.kind == "bin" and n.a[0] in CMP):
            # as80 binds comparisons tighter than + - * /, so this
            # assertion tested something else (always true); convert the
            # evident intent and report it
            self.notes.append("%d: as80 parsed this ASSERT differently (it "
                              "could never fail); converted as intended: %s"
                              % (self.lineno, text(inner)))
        name = {"==": "EQ", "<": "LT", ">": "GT", "<=": "LE", ">=": "GE"}[op]
        lhs, rhs = inner[:cut], inner[cut + 1:]
        return "ASSERT_%s(%s, %s)" % (name, conv_expr(lhs, size_label),
                                      conv_expr(rhs, size_label))

    def ascii(self, lab, lab_sep, gap, body, z):
        parts = split_commas(body)
        stmts = []
        d = ".asciz" if z else ".ascii"
        for p in parts:
            p = strip_ws(p)
            if len(p) == 1 and p[0].k == "str":
                raw = p[0].t[1:-1]
                if "\\" not in raw and '"' not in raw:
                    stmts.append(d + gap + p[0].t)
                    continue
                bs = unescape(raw) + ([0] if z else [])
                # printable runs as .ascii, the rest as .db
                run = ""
                for v in bs:
                    c = chr(v)
                    if 0x20 <= v <= 0x7e and c not in '\\"':
                        run += c
                        continue
                    if run:
                        stmts.append('.ascii%s"%s"' % (gap, run))
                        run = ""
                    stmts.append(".db%s0x%02X" % (gap, v))
                if run:
                    stmts.append('.ascii%s"%s"' % (gap, run))
            elif len(p) == 1 and p[0].k == "id":
                stmts.append(d + gap + p[0].t)      # macro string
            else:
                raise SyntaxError(".ascii operand %r" % text(p))
        stmts[0] = lab + lab_sep + stmts[0]
        return stmts

    # ---- lines
    def split_statements(self, toks):
        """-> (leading ws, [stmt tokens], comment token or None)"""
        comment = None
        if toks and toks[-1].k == "com":
            comment = toks[-1]
            toks = toks[:-1]
        lead = ""
        if toks and toks[0].k == "ws":
            lead = toks[0].t
            toks = toks[1:]
        return lead, split_semis(toks), comment

    @staticmethod
    def comment_text(tok):
        # '!' and '#' comments -> ';', keep the rest
        t = tok.t
        n = len(t) - len(t.lstrip("!#"))
        return ";" * n + t[n:]

    def line(self, s):
        toks = lex(s)
        lead, stmts, com = self.split_statements(toks)
        # trailing whitespace before the comment
        pre_com = ""
        if stmts and stmts[-1] and stmts[-1][-1].k == "ws":
            pre_com = stmts[-1][-1].t
        outs = []
        for st in stmts:
            outs.extend(self.statement(st))
        outs = self.merge_data(outs)
        if com is not None:
            c = self.comment_text(com)
            if outs:
                outs[-1] = outs[-1] + (pre_com or " ") + c
            else:
                outs = [c]
            if not stmts or all(not strip_ws(x) for x in stmts):
                return [lead + c]
        if not outs:
            return [lead.rstrip()] if not com else [lead + self.comment_text(com)]
        return [lead + o if o and not o.startswith(";") else lead + o for o in outs]

    @staticmethod
    def merge_data(outs):
        """'.db a' '.db b' ... on one source line -> '.db a, b'."""
        if len(outs) < 2:
            return outs
        m = [re.match(r"(\.db|\.dw)(\s+)(.*)$", o) for o in outs]
        if all(m) and len({x.group(1) for x in m}) == 1:
            return [m[0].group(1) + m[0].group(2) + ", ".join(x.group(3) for x in m)]
        return outs

    # ---- #define
    def define(self, logical):
        """logical = list of physical lines (continuations joined by '\\')."""
        first = logical[0]
        m = re.match(r"(#\s*define\s+)([A-Za-z_][A-Za-z_0-9]*)(\([^)]*\))?(.*)$", first, re.S)
        if not m:
            raise SyntaxError("bad #define")
        pre, name, params, body0 = m.groups()
        params = params or ""
        bodylines = [body0] + logical[1:]
        joined = " ".join(b.rstrip().rstrip("\\") for b in bodylines)
        jt = [t for t in lex(joined) if t.k not in ("ws", "ccom")]
        # classify
        kind = "stmt"
        if not jt:
            kind = "expr"
        elif jt[0].t == ":":
            kind = "label"
        else:
            try:
                ExprParser(jt).parse()
                kind = "expr"
            except SyntaxError:
                kind = "stmt"
        self.macros[name] = kind
        out = []
        for i, b in enumerate(bodylines):
            cont = b.rstrip().endswith("\\")
            core = b.rstrip()
            if cont:
                core = core[:-1]
            head = (pre + name + params) if i == 0 else ""
            conv = self.define_body(core, kind)
            s = head + conv
            if cont:
                s = s + "\\" if s.endswith((" ", "\t")) else s + " \\"
                # keep original alignment of the continuation backslash
                orig = b.rstrip()
                col = len(orig.expandtabs()) - 1
                cur = len((s[:-1]).rstrip().expandtabs())
                s = s[:-1].rstrip()
                pad = max(1, col - cur)
                s = s + (" " * pad if col > cur else " ") + "\\"
            out.append(s.rstrip() if not cont else s)
        return out

    def define_body(self, core, kind):
        toks = lex(core)
        # trailing C comment is kept verbatim
        tail = ""
        while toks and toks[-1].k in ("ws", "ccom"):
            tail = toks[-1].t + tail
            toks = toks[:-1]
        if toks and toks[-1].k == "com":
            raise SyntaxError("'!' comment inside #define")
        lead = ""
        if toks and toks[0].k == "ws":
            lead = toks[0].t
            toks = toks[1:]
        if not toks:
            return lead + tail
        if kind == "expr":
            return lead + conv_expr(toks) + tail
        if kind == "label":
            s = strip_ws(toks)
            assert s[0].t == ":"
            st = s[1:]
            return lead + self.statement(strip_ws(st))[0] + tail
        # statements separated by ';' -> ' @ '
        stmts = split_semis(toks)
        outs = []
        for st in stmts:
            if not strip_ws(st):
                outs.append(None)      # empty statement (trailing ';')
                continue
            outs.extend(self.statement(st, in_define=True))
        res = []
        for o in outs:
            res.append("" if o is None else o)
        # 'a; b;' -> 'a @ b @'  (trailing separator kept: macro bodies are
        # pasted next to each other, e.g. CTCSS_TONES)
        s = " @ ".join(x for x in res if x != "")
        if res and res[-1] == "" and len(res) > 1:
            s += " @"
        return lead + s + tail

    # ---- file
    def convert(self, src):
        lines = src.split("\n")
        for l in lines:
            m = re.match(r"\s*#\s*define\s+([A-Za-z_][A-Za-z_0-9]*)", l)
            if m:
                self.macros.setdefault(m.group(1), "stmt")
        self.sized = set(re.findall(r"\bSIZE\(\s*([A-Za-z_][A-Za-z_0-9]*)\s*\)", src))
        out = []
        i = 0
        while i < len(lines):
            self.lineno = i + 1
            s = lines[i]
            st = s.lstrip()
            try:
                if re.match(r"#\s*define\b", st):
                    logical = [s]
                    while logical[-1].rstrip().endswith("\\"):
                        i += 1
                        logical.append(lines[i])
                    out.extend(self.define(logical))
                elif re.match(r"#\s*[a-z]+", st) and not st.startswith("# "):
                    out.append(s)          # other cpp directives
                elif re.match(r"#\s*(if|ifdef|ifndef|else|endif|undef|include|error)\b", st):
                    out.append(s)
                else:
                    out.extend(self.line(s))
            except (SyntaxError, IndexError, ValueError, KeyError) as e:
                self.errors.append("%d: %s: %s" % (i + 1, e, s))
                out.append(s)
            i += 1
        return "\n".join(out)


def main():
    src = open(sys.argv[1], encoding="latin-1").read()
    c = Converter()
    res = c.convert(src)
    header = ('; HI/LO, ALIGN/FILL, ASSERT_*: see notes/toolchain.md\n'
              '#include "asm.h"\n')
    sys.stdout.buffer.write((header + res).encode("latin-1"))
    for e in c.errors:
        print(e, file=sys.stderr)
    for e in c.notes:
        print("note: " + e, file=sys.stderr)
    sys.exit(1 if c.errors else 0)


if __name__ == "__main__":
    main()
