"""
PTT and TX flow: differential scenarios for the C port, asm build vs C
build.

pttcheck (key up, the refusals and their 300 Hz tone, CTCSS, CCIR digits
on PTT, the tune tone in the menu, the watch loop: keys during TX, the
battery redraw, the menu redraw; at release: remote config packets from
the menu, MPRS on key-up, TX off, the VIP), beep1750, aprs_ptt_check
(/LOCAL keys the radio on the APRS frequency) and spontaneous_mprs_check
(an MPRS report on the APRS frequency when idle).

Checkpoints compare display, latches, events (TX_ON/TX_OFF, SYNTH,
MODEM_TX, within the timing tolerance) and NV; traces follow the TX
keying (OUT1's TXOFF bit, the TX power DAC) over time; tone steps
compare the 8254 pitch runs (the refusal tone, CCIR, DTMF, 1750 Hz, the
tune tone).  OUT1's other bits are the synth's serial lines, so only
TXOFF is traced.

    R58_PTT_REF_ROM / R58_PTT_REF_LST    reference (default build/)
    R58_PTT_CAND_ROM / R58_PTT_CAND_LST  candidate (default build-c/)
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from difftest import run_diff  # noqa: E402
from test_radio import make_sane_nv  # noqa: E402
from test_fsk import nmea  # noqa: E402
from test_menu_diff import rec, pos  # noqa: E402
from r58emu import P8E, P8N, CU53AN, CU58AF  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FW = os.path.join(ROOT, "firmware")
REF = (os.environ.get("R58_PTT_REF_ROM", os.path.join(FW, "build", "r58.bin")),
       os.environ.get("R58_PTT_REF_LST", os.path.join(FW, "build", "r58.map")))
CAND = (os.environ.get("R58_PTT_CAND_ROM", os.path.join(FW, "build-c", "r58.bin")),
        os.environ.get("R58_PTT_CAND_LST", os.path.join(FW, "build-c", "r58.map")))


def setUpModule():
    for rom, lst in (REF, CAND):
        if not (os.path.exists(rom) and os.path.exists(lst)):
            raise unittest.SkipTest("build not found (%s); run make -C firmware [C=1]" % rom)


def f24(v):
    return (v & 0xFFFFFF).to_bytes(3, "little")


def keying(r):
    lt = r.latches()
    return (lt["out1"] >> 7, lt["da_txpwr"])


def state(r):
    return (r.peek("txon"), r.peek("digidx"), r.peek24("rx_freq"), r.peek24("tx_freq"),
            r.peek("cfg_txpwr"), r.peek("txpwr_increment"), r.peek("dtmf_code"),
            r.peek("repeater_ptt_seen"), r.peek("vip_list", 6), r.peek("menu_active"),
            r.peek16("mprs_report_timer"))


def at(label):
    return [("check", label), ("probe", label, state)]


def ptt(seconds, label, trace=True, tones=False):
    """PTT down for `seconds` (traced), up, settle, compare"""
    if tones:
        down = [("ptt", True), ("tones", label + " tx", seconds)]
    elif trace:
        down = [("ptt", True), ("trace", label + " keying", keying, seconds)]
    else:
        down = [("ptt", True), ("run", seconds)]
    # settle 3 (15 ms): a build a few ms later to key down shows the state
    # before for a sample or two
    return down + at(label + " tx") + [("ptt", False), ("trace", label + " off", keying, 0.6, 3)] + \
        at(label + " released")


def enter(digits):
    return [("keys", digits), ("press", "#"), ("run", 0.3)]


def key(k, hold=0.15, label=None):
    return [("press", k, hold), ("run", 0.3)] + at(label or "key %r" % k)


BOOT = [("boot", 2.5)]


class PttDiff(unittest.TestCase):
    def diff(self, scenario, card=P8E, cu=CU53AN, synth_card=None, **kw):
        nv = make_sane_nv(card, cu, synth_card)
        diffs = run_diff(scenario, REF, CAND, card=card, cu=cu, nv=nv, **kw)
        self.assertEqual(diffs, [], "\n".join(d[:3000] for d in diffs[:10]))

    # ---- keying

    def test_keying(self):
        s = BOOT + enter("433500") + ptt(0.5, "simplex")
        s += enter("434700") + ptt(0.5, "duplex")
        s += [("poke", "cfg_pll_delay", 0)] + ptt(0.3, "no pll delay")
        s += [("poke", "cfg_pll_delay", 200)] + ptt(0.5, "long pll delay")
        s += [("poke", "cfg_txpwr", 3)] + ptt(0.4, "power 3")
        s += [("press", "R"), ("run", 0.3)] + ptt(0.4, "reverse")
        s += [("ptt", True), ("run", 0.05), ("ptt", False), ("run", 0.5)] + at("short blip")
        self.diff(s)

    def test_refused(self):
        s = BOOT + enter("440000") + ptt(0.8, "out of band", tones=True)
        s += [("ptt", True), ("run", 0.3), ("press", "5"), ("run", 0.3)] + at("key while refused")
        s += [("ptt", False), ("run", 0.5)] + at("released")
        s += enter("433500") + [("poke", "cfg_tx_tot_minutes", 0)] + ptt(0.8, "tot 0", tones=True)
        s += [("poke", "cfg_tx_tot_minutes", 5), ("poke", "cfg_function", 1)]
        s += ptt(0.5, "repeater mode ignores ptt") + [("poke", "cfg_function", 0)]
        s += ptt(0.3, "normal again")
        self.diff(s)

    def test_ctcss(self):
        s = BOOT + enter("433500")
        for when in (0, 1, 2, 3):
            s += [("poke", "cfg_ctcss_tx_hz", 5), ("poke", "cfg_ctcss_output_when", when)]
            s += ptt(0.5, "ctcss when %d" % when)
        self.diff(s)

    # ---- digits on PTT

    def test_ccir_digits(self):
        s = BOOT + enter("433500")
        s += [("keys", "12345")] + ptt(1.5, "ccir 5 digits", tones=True)
        s += [("keys", "7")] + ptt(1.5, "ccir 1 digit, no shortcut", tones=True)
        s += [("poke", "cfg_shortcut_3", b"98\xff\xff\xff\xff\xff\xff"), ("keys", "3")]
        s += ptt(1.5, "ccir shortcut", tones=True)
        s += [("keys", "C"), ("press", "E"), ("run", 0.3), ("keys", "12")]
        s += ptt(0.6, "digits in the menu: no ccir") + [("press", "E"), ("run", 0.3)] + at("menu left")
        self.diff(s)

    # ---- the watch loop

    def test_keys_during_tx(self):
        s = BOOT + enter("433500") + [("ptt", True), ("run", 0.4)]
        s += key("+", label="power up") + key("+") + key("-", label="power down")
        for k in "5#*0":
            s += [("key_down", k), ("tones", "dtmf %s" % k, 0.3), ("key_up",), ("run", 0.2)]
            s += at("dtmf %s released" % k)
        s += [("ptt", False), ("run", 0.5)] + at("released")
        self.diff(s)

    def test_keys_during_tx_cu58af(self):
        s = BOOT + enter("433500") + [("ptt", True), ("run", 0.4)]
        s += key("+", label="power up") + key("-", label="power down")
        for k in "5#*C":
            s += [("key_down", k), ("run", 0.25)] + at("dtmf %s held" % k)
            s += [("key_up",), ("run", 0.3)] + at("dtmf %s released" % k)
        s += [("ptt", False), ("run", 0.5)] + at("released")
        self.diff(s, cu=CU58AF, tolerance_s=0.03)

    def test_battery_during_tx(self):
        s = BOOT + enter("433500") + [("ptt", True), ("run", 0.4)]
        for v in (150, 151, 149, 160, 140, 141, 100, 60):
            s += [("adc", "AD_BATT", v), ("run", 0.4)] + at("batt %d" % v)
        s += [("ptt", False), ("run", 0.5)] + at("released")
        self.diff(s)

    # ---- the menu

    def test_menu(self):
        s = BOOT + enter("433500") + [("keys", "1"), ("press", "E"), ("run", 0.3)]
        s += ptt(0.6, "in the menu")
        s += [("keys", pos(rec("PH", "t tunE"))), ("press", "E"), ("run", 0.3)]
        s += at("tune record") + ptt(0.8, "tune tone 0 Hz")
        s += [("poke", "cfg_txtune_hz", (1000).to_bytes(2, "little"))] + ptt(0.8, "tune 1000 Hz", tones=True)
        s += [("poke", "cfg_txtune_hz", (2345).to_bytes(2, "little"))] + ptt(0.8, "tune 2345 Hz", tones=True)
        s += [("press", "#"), ("run", 0.3)] + ptt(0.6, "next record, no tune")
        s += [("press", "E"), ("run", 0.3)] + at("menu left")
        self.diff(s)

    # ---- MPRS at key-up

    def test_keyup_mprs(self):
        s = BOOT + [("poke", "cfg_report_type", 0), ("poke", "cfg_mprs_callsign", b"OH3XYZ\xff\xff"),
                    ("serial_rx", 0, nmea("GPRMC,123519,A,6130.12,N,02345.67,E,000.0,000.0,280926,,")),
                    ("run", 0.5)] + enter("433500")
        for mode in (1, 2):
            s += [("poke", "cfg_keyup_mprs", mode), ("poke", "cfg_mprs_seconds", (30).to_bytes(2, "little"))]
            s += [("poke", "mprs_report_timer", (40).to_bytes(2, "little"))]
            s += ptt(0.4, "mprs %d due" % mode) + [("run", 1.0)] + at("mprs %d sent" % mode)
            s += [("poke", "mprs_report_timer", (10).to_bytes(2, "little"))]
            s += ptt(0.4, "mprs %d not due" % mode) + [("run", 1.0)] + at("mprs %d after" % mode)
        self.diff(s)

    # ---- '*' without digits: 1750 Hz

    def test_beep1750(self):
        s = BOOT + enter("433500")
        s += [("key_down", "*"), ("tones", "1750", 0.8), ("key_up",), ("run", 0.5)] + at("beep over")
        s += enter("440000") + [("key_down", "*"), ("tones", "refused", 0.8), ("key_up",), ("run", 0.5)]
        s += at("refused over")
        self.diff(s)

    # ---- APRS on /LOCAL, spontaneous MPRS

    def test_aprs_local(self):
        s = BOOT + enter("433500") + [("poke", "cfg_aprs_tx", 1), ("poke", "cfg_idlefn_delay", 0)]
        s += [("local", True), ("trace", "aprs freq not set", keying, 0.5), ("local", False), ("run", 0.3)]
        s += at("not configured")
        s += [("poke", "cfg_aprs_tx_freq", f24(432500))]
        s += [("local", True), ("trace", "aprs keying", keying, 0.8)] + at("aprs tx")
        s += [("local", False), ("trace", "aprs off", keying, 0.5)] + at("aprs released")
        s += [("poke", "cfg_idlefn_delay", 5), ("local", True), ("run", 0.5)] + at("not idle")
        s += [("local", False), ("run", 0.3), ("poke", "cfg_aprs_tx", 0), ("poke", "cfg_idlefn_delay", 0),
              ("local", True), ("run", 0.5)] + at("aprs off") + [("local", False), ("run", 0.3)]
        self.diff(s)

    def test_spontaneous_mprs(self):
        s = BOOT + [("poke", "cfg_report_type", 0), ("poke", "cfg_mprs_callsign", b"OH3XYZ\xff\xff"),
                    ("serial_rx", 0, nmea("GPRMC,123519,A,6130.12,N,02345.67,E,000.0,000.0,280926,,")),
                    ("run", 0.5)] + enter("434700")
        s += [("poke", "cfg_idlefn_delay", 0), ("poke", "cfg_mprs_seconds", (20).to_bytes(2, "little")),
              ("poke", "mprs_report_timer", (25).to_bytes(2, "little")), ("poke", "cfg_spontaneous_mprs", 1),
              ("run", 1.5)] + at("no aprs freq")
        s += [("poke", "cfg_aprs_tx_freq", f24(432500)),
              ("trace", "spontaneous", keying, 2.0)] + at("sent, back on 434700")
        s += [("poke", "mprs_report_timer", (25).to_bytes(2, "little")), ("poke", "cfg_squelch_level", 0),
              ("run", 1.5)] + at("squelch open: waits")
        s += [("poke", "cfg_squelch_level", 127), ("trace", "closed: sends", keying, 4.0)]
        s += at("closed: sent")
        s += [("poke", "mprs_report_timer", (25).to_bytes(2, "little")), ("poke", "cfg_idlefn_delay", 3),
              ("run", 1.5)] + at("not idle")
        s += [("poke", "cfg_idlefn_delay", 0), ("poke", "cfg_mprs_seconds", b"\x00\x00"),
              ("run", 1.5)] + at("interval 0: never")
        self.diff(s)

    # ---- other card and handset

    def test_p8n(self):
        s = BOOT + enter("434700") + ptt(0.6, "duplex") + [("keys", "12")]
        s += ptt(1.5, "ccir", tones=True) + enter("440000") + ptt(0.6, "refused", tones=True)
        s += enter("433500") + [("ptt", True), ("run", 0.4)] + key("+") + [("ptt", False), ("run", 0.5)]
        s += at("released")
        self.diff(s, card=P8N)

    def test_cu58af(self):
        s = BOOT + enter("434700") + ptt(0.6, "duplex") + [("keys", "12")]
        s += ptt(1.5, "ccir", tones=True) + enter("440000") + ptt(0.6, "refused", tones=True)
        self.diff(s, cu=CU58AF, tolerance_s=0.03)


if __name__ == "__main__":
    unittest.main()
