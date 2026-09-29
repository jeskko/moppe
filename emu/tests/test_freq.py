"""
Frequency, band and duplex logic (c/freq.c): the release
and the build under test side by side through band edges, slice
boundaries, the duplex cycle, split, TX legality (band, out-of-band
spots, /LOCAL), memories with a shift, and QSY sizes, comparing the RAM
this logic writes after every step (each symbol resolved in its own
build's map). The differential tests only see display, synth registers,
events and NV; tx_is_legal, band, the shift or the scanner's settling
time would slip through them.

Candidate: R58_ROM/R58_LST (default firmware/build); reference: the
release build (firmware/build-release, `make -C firmware verify`).
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_radio import make_sane_nv, ROM, LST  # noqa: E402
from r58emu import Radio, P8E, P8N  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REF = (os.path.join(ROOT, "firmware", "build-release", "r58.bin"),
       os.path.join(ROOT, "firmware", "build-release", "r58.map"))

STATE = [("rx_freq", 3), ("tx_freq", 3), ("duplex_state", 1), ("duplex_shift", 3),
         ("band", 1), ("band_step", 1), ("band_step_hz", 2), ("band_sctail", 1),
         ("band_sclisten", 1), ("band_autoreject", 1), ("tx_is_legal", 1),
         ("synth_ctrl", 1), ("rx_divisor", 3), ("tx_divisor", 3),
         ("rx_bstep_cfg", 2), ("tx_bstep_cfg", 2), ("last_qsy_kHz", 3),
         ("rx_freq_previous", 3), ("scan_settling_time", 1)]


def f24(khz):
    return bytes([khz & 0xFF, (khz >> 8) & 0xFF, (khz >> 16) & 0xFF])


class Pair:
    """The same inputs to the reference and the candidate radio."""

    def __init__(self, card):
        nv = make_sane_nv(card)
        self.radios = [Radio(REF[0], REF[1], card=card, nv=nv),
                       Radio(ROM, LST, card=card, nv=nv)]

    def __getattr__(self, name):
        def call(*a, **kw):
            return [getattr(r, name)(*a, **kw) for r in self.radios]
        return call

    def enter(self, digits):
        self.type(digits)
        self.press("#")
        self.run(0.3)

    def state(self, r):
        out = {}
        for n, k in STATE:
            v = r.peek(n, k)
            out[n] = bytes([v]) if isinstance(v, int) else bytes(v)
        return out


class FreqLogic(unittest.TestCase):
    def setUp(self):
        if not os.path.exists(REF[0]):
            self.skipTest("run `make -C firmware verify` for build-release")

    def check(self, p, label):
        a, b = (p.state(r) for r in p.radios)
        diff = {n: (a[n].hex(), b[n].hex()) for n in a if a[n] != b[n]}
        self.assertEqual(diff, {}, "%s: release vs candidate %s" % (label, diff))
        self.steps += 1

    def scenario(self, card):
        self.steps = 0
        p = Pair(card)
        p.run(2.5)
        r0 = p.radios[0]
        b1s, b1e = r0.peek24("cfg_band1_start"), r0.peek24("cfg_band1_end")
        b2s = r0.peek24("cfg_band2_start")
        vco = r0.peek24("cfg_rx_vco_center")

        # band edges: start, end - 1 step, end, below start, between bands
        for khz in (b1s, b1e - 25, b1e, b1s - 25, b1e + 100, b2s):
            p.enter(str(khz))
            self.check(p, "enter %d" % khz)
        # the VCO band switch point
        for khz in (vco - 25, vco, vco + 25):
            p.enter(str(khz))
            self.check(p, "vco %d" % khz)
        # stepping across slice and band boundaries (long 3 up, long 6 down)
        p.enter(str(b1e - 50))
        for key in "3333666666":
            p.press(key, 0.65)
            p.run(0.3)
            self.check(p, "step %s" % key)
        # the duplex cycle, in a duplex band and outside the bands
        for khz in (b2s + 100, b1e + 100):
            p.enter(str(khz))
            for _ in range(4):
                p.press("R")
                p.run(0.3)
                self.check(p, "R at %d" % khz)
        # split: digits then a long R, and a temporary shift
        p.enter(str(b1s + 100))
        p.type("433700")
        p.press("R", 1.5)
        p.run(0.3)
        self.check(p, "split")
        # TX legality: in the TX band, outside, at an out-of-band spot,
        # and with /LOCAL grounded
        ts, te = r0.peek24("cfg_tx_band_start"), r0.peek24("cfg_tx_band_end")
        for khz in (ts, ts + 25, te - 25, te, te + 1000):
            p.enter(str(khz))
            self.check(p, "tx legal? %d" % khz)
        oob = r0.peek24("cfg_tx_band_end") + 2000
        p.poke("cfg_tx_oob_2", f24(oob))
        p.enter(str(oob))
        self.check(p, "oob spot")
        p.local(True)
        p.enter(str(oob + 25))
        self.check(p, "local")
        p.local(False)
        p.enter(str(oob + 50))
        self.check(p, "local released")
        # a memory with a shift, recalled (go_mem_a -> set_duplex_from_tx_rx)
        p.enter(str(b2s + 200))
        p.press("R")
        p.run(0.3)
        p.type("9")
        p.press("#", 1.5)
        p.run(0.3)
        p.enter(str(b1s + 200))
        p.type("9")
        p.run(0.3)
        self.check(p, "memory with shift")
        # small and large QSY (settling time)
        for khz in (b1s + 225, b1s + 250, b2s + 225):
            p.enter(str(khz))
            self.check(p, "qsy to %d" % khz)
        return self.steps

    def test_p8e(self):
        self.assertGreater(self.scenario(P8E), 30)

    def test_p8n(self):
        self.assertGreater(self.scenario(P8N), 30)


if __name__ == "__main__":
    unittest.main()
