"""
Display indicators: differential scenarios for the C port (c/display.c),
asm build vs C build.  redraw's indicator drawers: the duplex arrows
(TX below/above RX, simplex) and the remote-display phone icon
(draw_dpx_ind, set_dpx_ind_from_rx_tx_freq), CTCSS TX/RX, selective mute
and GPS-fix icons (draw_ctcss_and_mute_and_gps_ind, CU53AN only), the
forced-squelch star (draw_squelch_ind: an icon on the CU53AN, a character
on the CU58AF).  Checkpoints compare the raw segments.

    R58_DPY_REF_ROM / R58_DPY_REF_LST    reference (default build/)
    R58_DPY_CAND_ROM / R58_DPY_CAND_LST  candidate (default build-c/)
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from difftest import run_diff  # noqa: E402
from test_radio import make_sane_nv  # noqa: E402
from r58emu import P8E, P8N, CU53AN, CU58AF  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FW = os.path.join(ROOT, "firmware")
REF = (os.environ.get("R58_DPY_REF_ROM", os.path.join(FW, "build", "r58.bin")),
       os.environ.get("R58_DPY_REF_LST", os.path.join(FW, "build", "r58.map")))
CAND = (os.environ.get("R58_DPY_CAND_ROM", os.path.join(FW, "build-c", "r58.bin")),
        os.environ.get("R58_DPY_CAND_LST", os.path.join(FW, "build-c", "r58.map")))


def setUpModule():
    for rom, lst in (REF, CAND):
        if not (os.path.exists(rom) and os.path.exists(lst)):
            raise unittest.SkipTest("build not found (%s); run make -C firmware [C=1]" % rom)


def at(label):
    return [("probe", label + " flags", lambda r: r.peek("dpx_ind_flags")), ("check", label)]


def show(label, *pokes):
    return [("poke", k, v) for k, v in pokes] + [("poke", "redraw_req", 1), ("run", 0.3)] + at(label)


def enter(digits):
    return [("keys", digits), ("press", "#"), ("run", 0.3)]


def scenario():
    s = [("boot", 2.5)] + enter("433500") + at("simplex")
    s += enter("434700") + at("tx below")
    s += [("press", "R"), ("run", 0.3)] + at("reverse: tx above")
    s += [("press", "R"), ("run", 0.3), ("press", "R"), ("run", 0.3)] + at("round")
    s += [("ptt", True), ("run", 0.3)] + at("transmitting") + [("ptt", False), ("run", 0.3)]
    # a TX that differs from RX only in the top byte (433500 - 65536; the
    # TX grid never gives one, so poked): the arrows compare all 24 bits
    s += enter("433500") + show("tx differs in the top byte", ("tx_freq", (433500 - 65536).to_bytes(3, "little")))
    s += show("and above", ("tx_freq", (433500 + 65536).to_bytes(3, "little")))
    s += enter("433500")
    s += show("remote display", ("display_buffer_time", 5), ("remote_display_buffer", b"HI\xff" + b"\xff" * 7))
    s += show("remote display off", ("display_buffer_time", 0))
    for tx, rx in ((0, 0), (5, 0), (0, 7), (5, 7)):
        s += show("vfo ctcss %d/%d" % (tx, rx), ("cfg_ctcss_tx_hz", tx), ("cfg_ctcss_rx_hz", rx))
    # on a memory (stored as 4) the memory's tones count
    s += enter("433300") + [("keys", "4"), ("press", "#", 1.5), ("run", 0.3)] + enter("4")
    s += show("memory, vfo tones set", ("cfg_ctcss_tx_hz", 5), ("cfg_ctcss_rx_hz", 7),
              ("mem_ctcss_tx_hz", 0), ("mem_ctcss_rx_hz", 0))
    s += show("memory tones", ("mem_ctcss_tx_hz", 2), ("mem_ctcss_rx_hz", 9))
    s += show("gps fix", ("gps_valid_seconds", 30)) + show("no fix", ("gps_valid_seconds", 0))
    s += show("selective mute", ("squelch_muted", 2)) + show("other mute bits", ("squelch_muted", 1))
    s += show("mute off", ("squelch_muted", 0))
    s += [("press", "B"), ("run", 0.3)] + at("squelch forced") + [("press", "B"), ("run", 0.3)]
    s += at("squelch released")
    return s


class DisplayDiff(unittest.TestCase):
    def diff(self, scenario, card=P8E, cu=CU53AN, **kw):
        nv = make_sane_nv(card, cu, None)
        diffs = run_diff(scenario, REF, CAND, card=card, cu=cu, nv=nv, **kw)
        self.assertEqual(diffs, [], "\n".join(d[:3000] for d in diffs[:10]))

    def test_indicators_cu53an(self):
        self.diff(scenario())

    def test_indicators_cu58af(self):
        self.diff(scenario(), cu=CU58AF, tolerance_s=0.03)

    def test_indicators_p8n(self):
        self.diff(scenario(), card=P8N)


if __name__ == "__main__":
    unittest.main()
