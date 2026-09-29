"""
The mainloop and its per-pass checks: differential scenarios for the C
port, asm build vs C build.

gps_check (the NMEA gatherer: sentences split over several receptions,
across the ring's end, too long, restarted by '$', junk shorter than 10
characters, several in one reception; the Aisin Seiki block gatherer),
script_check (on-hook/off-hook scripts: full, short, digits and
functions), idlefn_check (scanner start, default memory), bus_rf_relay
(MBUS bytes relayed as FFSK packets 12 at a time), dim_lights_if_idle,
redrawcheck, ccircheck (the ding for our CCIR call).

    R58_MAIN_REF_ROM / R58_MAIN_REF_LST    reference (default build/)
    R58_MAIN_CAND_ROM / R58_MAIN_CAND_LST  candidate (default build-c/)
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from difftest import run_diff  # noqa: E402
from test_radio import make_sane_nv  # noqa: E402
from test_gps_diff import gps_state, nmea_raw, aisin  # noqa: E402
from r58emu import P8E, P8N, CU53AN, CU58AF  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FW = os.path.join(ROOT, "firmware")
REF = (os.environ.get("R58_MAIN_REF_ROM", os.path.join(FW, "build", "r58.bin")),
       os.environ.get("R58_MAIN_REF_LST", os.path.join(FW, "build", "r58.map")))
CAND = (os.environ.get("R58_MAIN_CAND_ROM", os.path.join(FW, "build-c", "r58.bin")),
        os.environ.get("R58_MAIN_CAND_LST", os.path.join(FW, "build-c", "r58.map")))

EOS = 0xFF


def setUpModule():
    for rom, lst in (REF, CAND):
        if not (os.path.exists(rom) and os.path.exists(lst)):
            raise unittest.SkipTest("build not found (%s); run make -C firmware [C=1]" % rom)


def state(r):
    return (r.peek("gps_hist_rp"), r.peek("gps_hist_idx"), r.peek("gps_sentence_len"),
            r.peek("gps_sentence", 12), r.peek("digidx"), r.peek("scan_on"), r.peek("mem_idx"),
            r.peek("mem_flags"), r.peek("idlefn_flag"), r.peek("script_req"), r.peek("ding_req"),
            r.peek("indicators"), r.peek("call_dpyed"), r.peek("mbusrx_cnt"), r.peek("volume"),
            r.peek("audio_dst"), r.peek("squelch_muted"))


def at(label, gps=False):
    out = [("check", label), ("probe", label, state)]
    if gps:
        out.append(("probe", label + " gps", gps_state))
    return out


def rmc(t="123519", ck=None):
    return nmea_raw("GPRMC,%s,A,6130.12,N,02345.67,E,012.3,084.4,280926,," % t, ck)


def gps(data, label, wait=0.3):
    return [("serial_rx", 0, data), ("run", wait)] + at(label, gps=True)


def script(which, keys):
    """cfg_onhook/offhook_script = keys (bytes, EOS padded)"""
    return [("poke", "cfg_%s_script" % which, bytes(keys) + bytes([EOS]) * (8 - len(keys)))]


def enter(digits):
    return [("keys", digits), ("press", "#"), ("run", 0.3)]


BOOT = [("boot", 2.5)]


class MainloopDiff(unittest.TestCase):
    def diff(self, scenario, card=P8E, cu=CU53AN, **kw):
        nv = make_sane_nv(card, cu, None)
        diffs = run_diff(scenario, REF, CAND, card=card, cu=cu, nv=nv, **kw)
        self.assertEqual(diffs, [], "\n".join(d[:3000] for d in diffs[:10]))

    # ---- the NMEA gatherer

    def test_gps_gatherer(self):
        a = rmc("101010")
        s = list(BOOT) + gps(a, "one sentence")
        s += gps(a[:20], "first part") + gps(a[20:40], "second part") + gps(a[40:], "rest")
        s += gps(rmc("111111") + rmc("121212"), "two in one")
        s += gps(b"$GP" + b"X" * 120 + b"\r\n", "too long") + gps(rmc("131313"), "after too long")
        s += gps(a[:30] + b"$" + rmc("141414")[1:], "restarted by $")
        s += gps(b"$GPR\r\n", "junk under 10") + gps(b"12345678\n", "junk 8 + LF")
        s += gps(b"$GPRMC,1\n", "9 + LF") + gps(b"GPRMC,151515\r\n", "no $, 14 chars")
        s += gps(rmc("161616").replace(b"\r\n", b"\n"), "LF only")
        # push the ring past its end several times, a sentence across it
        for i in range(6):
            s += gps(rmc("17%04d" % i), "wrap %d" % i, wait=0.2)
        s += gps(b"x" * 99 + b"\n", "exactly 99 + LF") + gps(b"y" * 100 + b"\n", "exactly 100 + LF")
        s += gps(rmc("181818"), "after the long ones")
        self.diff(s)

    def test_gps_gatherer_aisin_seiki(self):
        s = list(BOOT) + [("poke", "cfg_gps_config", 3), ("run", 0.2)]
        s += gps(aisin(), "one block")
        blk = aisin(speed=50)
        s += gps(blk[:17], "block part 1") + gps(blk[17:], "block part 2")
        s += gps(b"\x0d\x0d\x0d" + aisin(heading=0x200), "leading CRs")
        for i in range(8):
            s += gps(aisin(speed=i * 10) * 2, "wrap %d" % i, wait=0.2)
        s += [("poke", "cfg_gps_config", 0), ("run", 0.2)] + gps(rmc("191919"), "nmea again")
        self.diff(s)

    # ---- hook scripts

    def test_scripts(self):
        s = list(BOOT) + enter("433500")
        s += script("offhook", b"12") + [("hook", True), ("run", 0.5)] + at("off hook: 12")
        s += script("onhook", [ord("#")]) + [("hook", False), ("run", 0.5)] + at("on hook: #")
        s += script("offhook", b"++") + [("hook", True), ("run", 0.5)] + at("off hook: ++")
        s += script("onhook", b"--K") + [("hook", False), ("run", 0.5)] + at("on hook: --K")
        s += script("offhook", b"43360") + script("onhook", b"0#") + [("hook", True), ("run", 0.5)]
        s += at("off hook: digits") + [("hook", False), ("run", 0.5)] + at("on hook: 0#")
        s += script("offhook", b"4335751#") + [("hook", True), ("run", 0.5)] + at("8 chars, no EOS")
        s += script("onhook", b"") + [("hook", False), ("run", 0.5)] + at("empty")
        s += script("offhook", b"T") + [("hook", True), ("run", 0.5)] + at("T mutes")
        s += script("onhook", b"B") + [("hook", False), ("run", 0.5)] + at("B")
        # an unknown request and a key typed meanwhile
        s += [("poke", "script_req", 3), ("run", 0.3)] + at("script_req 3")
        s += [("press", "7"), ("run", 0.3)] + at("key after")
        self.diff(s)

    # ---- idle function

    def test_idle_function(self):
        s = list(BOOT) + enter("433500")
        s += [("poke", "cfg_idlefn", 0), ("poke", "idlefn_flag", 1), ("run", 0.5)] + at("idlefn 0")
        s += [("poke", "cfg_idlefn", 3), ("poke", "idlefn_flag", 1), ("run", 0.5)] + at("idlefn 3")
        s += [("poke", "cfg_def_memory", 5), ("poke", "cfg_idlefn", 2), ("poke", "idlefn_flag", 1),
              ("run", 1.0)] + at("idlefn 2: default memory")
        s += enter("433500") + [("poke", "cfg_idlefn", 1), ("poke", "idlefn_flag", 1), ("run", 0.05)]
        s += [("probe", "idlefn 1: scanning", lambda r: (r.peek("scan_on"), r.peek("idlefn_flag")))]
        s += [("press", "#"), ("run", 0.3)] + at("stopped")
        # from the minute timer
        s += [("poke", "cfg_idlefn", 2), ("poke", "cfg_idlefn_delay", 1), ("run", 65)] + at("a minute idle")
        self.diff(s, ignore=("SYNTH", "rx_loads", "tx_loads", "ctrl_loads"))

    # ---- MBUS -> RF relay

    def test_bus_rf_relay(self):
        s = list(BOOT) + enter("433500") + [("poke", "cfg_bus_rf_relay", 1)]
        s += [("serial_rx", 1, bytes(range(11))), ("run", 0.5)] + at("11 bytes: waits")
        s += [("serial_rx", 1, b"\x0b"), ("run", 1.0)] + at("12: sent")
        s += [("serial_rx", 1, bytes(range(100, 130))), ("run", 2.0)] + at("30: two sent, 6 left")
        s += [("serial_rx", 1, bytes(range(200, 206))), ("run", 1.0)] + at("6 more: third")
        s += [("poke", "cfg_bus_rf_relay", 0), ("serial_rx", 1, bytes(12)), ("run", 1.0)]
        s += at("relay off")
        self.diff(s)

    # ---- lights, redraw requests, the ding

    def test_lights(self):
        s = list(BOOT) + [("poke", "cfg_light_seconds", 3), ("press", "5"), ("run", 1.0)] + at("lit")
        s += [("run", 3.5)] + at("dimmed") + [("press", "C"), ("run", 0.5)] + at("lit again")
        s += [("run", 4.0)] + at("dimmed again")
        s += [("poke", "cfg_light_seconds", 0), ("press", "5"), ("run", 1.0)] + at("light seconds 0")
        s += [("poke", "cfg_light_seconds", 255), ("press", "C"), ("run", 5.0)] + at("255")
        s += [("poke", "redraw_req", 1), ("run", 0.2)] + at("redraw request")
        self.diff(s)

    def test_lights_cu58af(self):
        s = list(BOOT) + [("poke", "cfg_light_seconds", 3), ("press", "5"), ("run", 1.0)] + at("lit")
        s += [("run", 3.5)] + at("dimmed") + [("press", "C"), ("run", 0.5)] + at("lit again")
        self.diff(s, cu=CU58AF, tolerance_s=0.03)

    def test_ding(self):
        s = list(BOOT) + enter("433500")
        s += [("poke", "cfg_ccir_1", bytes([1, 2, 3, 4, 5]) + bytes([EOS]) * 3),
              ("poke", "cfg_ccir_minlen", 20)]
        call = []
        for d in (1, 2, 3, 4, 5):
            call += [("ccir", d), ("run", 0.1)]
        s += call + [("ccir", 0x0F), ("tones", "ding", 1.5)] + at("our call: ding")
        other = []
        for d in (5, 4, 3, 2, 1):
            other += [("ccir", d), ("run", 0.1)]
        s += other + [("ccir", 0x0F), ("tones", "no ding", 1.0)] + at("other call")
        s += [("poke", "ding_req", 1), ("tones", "ding on request", 1.0)] + at("ding_req")
        self.diff(s)

    def test_p8n(self):
        s = list(BOOT) + gps(rmc("202020"), "gps") + script("offhook", b"12") + [("hook", True), ("run", 0.5)]
        s += at("script") + [("poke", "cfg_bus_rf_relay", 1), ("serial_rx", 1, bytes(range(12))), ("run", 1.5)]
        s += at("relay")
        self.diff(s, card=P8N)


if __name__ == "__main__":
    unittest.main()
