"""
RFC table (receiver tuning voltage per MHz): differential scenarios for
the C port, asm build vs C build.

rfc_fill_blanks / rfc_fill_one_hole (dF:rFcFIL, 666 #): the holes (0)
between set values are interpolated, a line drawn with integer steps,
shallow (dx >= dy) or steep, up or (wrapping, dy is 8 bits) down; index
99 becomes a 255 barrier when 0.  get_rfc_hl / lookup_rfc / save_rfc:
the slot is (RX kHz mod 100000) / 1000, the value goes to the RFC DAC.

    R58_RFC_REF_ROM / R58_RFC_REF_LST    reference (default build/)
    R58_RFC_CAND_ROM / R58_RFC_CAND_LST  candidate (default build-c/)
"""
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from difftest import run_diff  # noqa: E402
from test_radio import make_sane_nv  # noqa: E402
from test_menu_diff import rec, pos  # noqa: E402
from r58emu import P8E, P8N, CU53AN  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FW = os.path.join(ROOT, "firmware")
REF = (os.environ.get("R58_RFC_REF_ROM", os.path.join(FW, "build", "r58.bin")),
       os.environ.get("R58_RFC_REF_LST", os.path.join(FW, "build", "r58.map")))
CAND = (os.environ.get("R58_RFC_CAND_ROM", os.path.join(FW, "build-c", "r58.bin")),
        os.environ.get("R58_RFC_CAND_LST", os.path.join(FW, "build-c", "r58.map")))


def setUpModule():
    for rom, lst in (REF, CAND):
        if not (os.path.exists(rom) and os.path.exists(lst)):
            raise unittest.SkipTest("build not found (%s); run make -C firmware [C=1]" % rom)


def table(points, last=0):
    t = [0] * 100
    for i, v in points.items():
        t[i] = v
    if last:
        t[99] = last
    return bytes(t)


def state(r):
    return (r.peek("rfctab", 100), r.peek("rfc"))


def at(label):
    return [("check", label), ("probe", label, state)]


def fill(t, label):
    """poke the table, run dF:rFcFIL (666 #), leave the menu"""
    return [("poke", "rfctab", t), ("keys", pos(rec("dF", "rFcFIL"))), ("press", "E"), ("run", 0.3),
            ("keys", "666"), ("press", "#"), ("run", 1.0)] + at(label) + \
        [("press", "E"), ("run", 0.3)]


TABLES = [
    ("shallow up", table({0: 10, 50: 20})),
    ("steep up", table({10: 10, 12: 200, 98: 1})),
    ("down (wraps)", table({20: 200, 30: 100, 40: 90})),
    ("equal ends", table({5: 77, 60: 77})),
    ("dx == dy", table({0: 0, 20: 20, 21: 1})),
    ("hole of one", table({3: 9, 5: 12, 6: 13, 8: 250})),
    ("empty", table({})),
    ("barrier kept", table({1: 5}, last=66)),
    ("no holes", bytes(range(1, 101))),
    ("start zero", table({0: 0, 40: 120}, last=200)),
    ("steep near 255", table({50: 250, 52: 255}, last=255)),
]


class RfcDiff(unittest.TestCase):
    def diff(self, scenario, card=P8E, **kw):
        nv = make_sane_nv(card, CU53AN, None)
        diffs = run_diff(scenario, REF, CAND, card=card, cu=CU53AN, nv=nv, **kw)
        self.assertEqual(diffs, [], "\n".join(d[:3000] for d in diffs[:10]))

    def test_fill(self):
        s = [("boot", 2.5)]
        for label, t in TABLES:
            s += fill(t, label)
        self.diff(s)

    def test_fill_random(self):
        rnd = random.Random(58)
        s = [("boot", 2.5)]
        for i in range(12):
            pts = {rnd.randrange(100): rnd.randrange(1, 256) for _ in range(rnd.randrange(1, 12))}
            s += fill(table(pts, last=rnd.choice([0, 0, rnd.randrange(256)])), "random %d" % i)
        self.diff(s)

    def test_lookup(self):
        """the DAC follows the slot of each RX frequency"""
        s = [("boot", 2.5), ("poke", "rfctab", bytes((i * 7 + 3) & 0xFF or 1 for i in range(100)))]
        for f in ("433500", "432000", "432999", "438990", "145500", "144000", "51000", "50999",
                  "1296000", "100000", "99999", "10700000"):
            s += [("keys", f), ("press", "#"), ("run", 0.3)] + at("rx %s" % f)
        self.diff(s)

    def test_lookup_p8n(self):
        s = [("boot", 2.5), ("poke", "rfctab", bytes(range(100, 200)))]
        for f in ("433500", "145500", "51000"):
            s += [("keys", f), ("press", "#"), ("run", 0.3)] + at("rx %s" % f)
        self.diff(s, card=P8N)


if __name__ == "__main__":
    unittest.main()
