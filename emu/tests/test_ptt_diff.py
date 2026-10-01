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
    R58_PTT_CAND_ROM / R58_PTT_CAND_LST  candidate (default build/)
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from difftest import builds, skip_unless_built, DiffCase  # noqa: E402
from helpers import nmea, rec, pos, f24, enter, at as _at  # noqa: E402
from r58emu import P8N, CU58AF  # noqa: E402

REF, CAND = builds("PTT")
setUpModule = skip_unless_built(REF, CAND)


def keying(r):
    lt = r.latches()
    return (lt["out1"] >> 7, lt["da_txpwr"])


def state(r):
    p = r.pit(1)
    return (r.peek("txon"), r.peek("digidx"), r.peek24("rx_freq"), r.peek24("tx_freq"),
            r.peek("cfg_txpwr"), r.peek("txpwr_increment"), r.peek("dtmf_code"),
            r.peek("repeater_ptt_seen"), r.peek("vip_list", 6), r.peek("menu_active"),
            r.peek("ctcss_is_on"), r.peek("tx_divisor", 3),
            r.peek("tx_refdiv", 2), r.peek("tx_bstep_cfg", 2), (p["mode"], p["count"]),
            r.peek("idle_timer"), r.peek("ign_apo_timer"), r.peek("call_dpyed"),
            r.peek("display_buffer_time"), r.peek("locator_dpyed"), r.peek("squelch_muted"),
            r.peek("squelch_open"))


def at(label):
    return _at(label, state)


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


def key(k, hold=0.15, label=None):
    return [("press", k, hold), ("run", 0.3)] + at(label or "key %r" % k)


BOOT = [("boot", 2.5)]


class PttDiff(DiffCase):
    REF = REF
    CAND = CAND
    msg_max_items = 10
    msg_max_chars = 3000

    def diff(self, scenario, **kw):
        # whole seconds of TX: a few ms of keying offset flip it at a boundary
        kw["ignore"] = tuple(kw.get("ignore", self.default_ignore)) + ("transmitter_hours_second_counter",)
        return super().diff(scenario, **kw)

    # ---- keying

    def test_keying(self):
        s = BOOT + enter("433500") + ptt(0.5, "simplex")
        s += enter("434700") + ptt(0.5, "duplex")
        s += [("poke", "cfg_pll_delay", 0)] + ptt(0.3, "no pll delay")
        s += [("poke", "cfg_pll_delay", 200)] + ptt(0.5, "long pll delay")
        s += [("poke", "cfg_txpwr", 3)] + ptt(0.4, "power 3")
        s += [("press", "R"), ("run", 0.3)] + ptt(0.4, "reverse")
        s += [("ptt", True), ("run", 0.05), ("ptt", False), ("run", 0.5)] + at("short blip")
        # PTT counts as handset use (cu_manipulated): call notice, remote
        # display, locator and the idle timers are cleared
        s += [("poke", "call_dpyed", 2), ("poke", "display_buffer_time", 5), ("poke", "locator_dpyed", 4),
              ("poke", "idle_timer", 3), ("poke", "ign_apo_timer", 7), ("poke", "redraw_req", 1),
              ("run", 0.3)] + at("notices up") + ptt(0.4, "ptt clears them")
        # and it opens a selective-call mute ('T', from a hook script)
        s += [("poke", "cfg_offhook_script", b"T" + b"\xff" * 7), ("hook", True), ("run", 0.5),
              ("hook", False), ("run", 0.5)] + at("muted selective") + ptt(0.4, "ptt opens it")
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
        # the digits stay after a CCIR call: clear them (C held repeats)
        clear = [("press", "C", 1.5), ("run", 0.3)]
        s += clear + [("keys", "7")] + ptt(1.5, "ccir 1 digit, no shortcut", tones=True)
        s += clear + [("poke", "cfg_shortcut_3", b"98\xff\xff\xff\xff\xff\xff"), ("keys", "3")]
        s += ptt(1.5, "ccir shortcut", tones=True)
        s += clear + [("keys", "12")] + ptt(1.5, "ccir 2 digits", tones=True)
        s += clear + [("press", "E"), ("run", 0.3), ("keys", "12")]
        s += ptt(1.0, "digits in the menu: no ccir", tones=True)
        s += [("press", "E"), ("run", 0.3)] + at("menu left")
        self.diff(s)

    # ---- the watch loop

    def test_keys_during_tx(self):
        # the DTMF tone table is built before each tone: at gain 12 the
        # reference's repeated addition takes about as long as the C build
        # (test_aprs_diff TX_GAIN)
        s = BOOT + [("poke", "cfg_dtmf_gain", 12)] + enter("433500") + [("ptt", True), ("run", 0.4)]
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
        """battcheck runs in the watch loop only when the reading moves by
        more than one step: a battery sinking one step at a time into the
        warning and low zones goes unnoticed until PTT is released"""
        s = BOOT + enter("433500") + [("adc", "AD_BATT", 175), ("run", 0.3), ("ptt", True), ("run", 0.4)]
        for v in (150, 151, 149, 160, 140, 141, 170):
            s += [("adc", "AD_BATT", v), ("run", 0.4)] + at("batt %d" % v)
        for v in range(169, 130, -1):
            s += [("adc", "AD_BATT", v), ("run", 0.3)]
        s += at("sunk one step at a time")
        for v in range(131, 175):
            s += [("adc", "AD_BATT", v), ("run", 0.2)]
        s += at("back one step at a time")
        # wiggling by one around the warning thresholds (10 V, 9 V after a
        # transmission): the watch loop does not look
        for lo in (163, 146):
            s += [("adc", "AD_BATT", lo + 5), ("run", 0.3)] + at("above %d" % lo)
            for v in (lo + 3, lo + 1):
                s += [("adc", "AD_BATT", v), ("run", 0.3)]
            for i in range(6):
                s += [("adc", "AD_BATT", lo + (i & 1)), ("run", 0.3)]
            s += at("wiggled down %d" % lo)
            # onto lo in a jump of two (the loop stores it), then up by one
            s += [("adc", "AD_BATT", lo - 2), ("run", 0.3), ("adc", "AD_BATT", lo), ("run", 0.3)]
            for i in range(6):
                s += [("adc", "AD_BATT", lo + 1 - (i & 1)), ("run", 0.3)]
            s += at("wiggled up %d" % lo)
        s += [("adc", "AD_BATT", 140), ("run", 0.5)] + at("low in one jump")
        s += [("adc", "AD_BATT", 175), ("run", 1.0), ("ptt", False), ("run", 0.5)] + at("released")
        self.diff(s)

    # ---- the menu

    def test_menu(self):
        s = BOOT + enter("433500") + [("keys", "1"), ("press", "E"), ("run", 0.3)]
        s += ptt(0.6, "in the menu, no remote id")
        s += [("poke", "cfg_remote_id", b"\x34\x12"), ("poke", "cfg_remote_passwd", b"12345678")]
        s += ptt(0.6, "in the menu: remote config ask") + [("run", 1.0)] + at("asked")
        # the menu's live displays are redrawn while transmitting
        s += [("keys", pos(rec("Sq", "SqL"))), ("press", "E"), ("run", 0.3), ("ptt", True), ("run", 0.4)]
        for v in (0x20, 0x80, 0xC0, 0x40):
            s += [("adc", "AD_SQL", v), ("run", 0.3)] + at("sql %02x during tx" % v)
        s += [("ptt", False), ("run", 1.0)] + at("sql released")
        s += [("keys", pos(rec("PH", "t tunE"))), ("press", "E"), ("run", 0.3)]
        s += at("tune record") + ptt(0.8, "tune tone 0 Hz")
        # the tone from 0.1 s on: the asm computed its count by repeated
        # subtraction (4032000 / Hz rounds, ~20 ms at 1000 Hz on a P8E),
        # the C port divides (a deliberate difference)
        for hz in (1000, 2345):
            s += [("poke", "cfg_txtune_hz", hz.to_bytes(2, "little")), ("ptt", True), ("run", 0.1),
                  ("tones", "tune %d Hz" % hz, 0.7)] + at("tune %d tx" % hz)
            s += [("ptt", False), ("trace", "tune %d off" % hz, keying, 0.6, 3)] + at("tune %d released" % hz)
        s += [("press", "#"), ("run", 0.3)] + ptt(0.6, "next record, no tune")
        s += [("press", "E"), ("run", 0.3)] + at("menu left")
        self.diff(s)

    # ---- MPRS at key-up

    def test_keyup_mprs(self):
        """also with CTCSS: pttcheck turns it off before the packet"""
        s = BOOT + [("poke", "cfg_ctcss_tx_hz", 10), ("poke", "cfg_ctcss_output_when", 1), ("poke", "cfg_report_type", 0), ("poke", "cfg_mprs_callsign", b"OH3XYZ\xff\xff"),
                    ("serial_rx", 0, nmea("GPRMC,123519,A,6130.12,N,02345.67,E,000.0,000.0,280926,,")),
                    ("run", 0.5)] + enter("433500")
        for mode in (1, 2):
            s += [("poke", "cfg_keyup_mprs", mode), ("poke", "cfg_mprs_seconds", (30).to_bytes(2, "little"))]
            s += [("poke", "mprs_report_timer", (40).to_bytes(2, "little"))]
            s += [("ptt", True), ("run", 0.4)] + at("mprs %d tx" % mode) + [("ptt", False)]
            s += [("trace", "mprs %d ctcss" % mode, lambda r: r.peek("ctcss_is_on"), 1.0)]
            s += [("run", 0.5)] + at("mprs %d sent" % mode)
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
        s = BOOT + enter("433500") + [("poke", "cfg_aprs_tx", 1), ("poke", "cfg_idlefn_delay", 0),
                                      ("poke", "cfg_aprs_tx_freq", f24(0))]
        s += [("local", True), ("trace", "aprs freq not set", keying, 0.5), ("local", False), ("run", 0.3)]
        s += at("not configured")
        # the mic muted before (the 1750 Hz beep leaves it so): APRS unmutes
        s += [("key_down", "*"), ("run", 0.5), ("key_up",), ("run", 0.5)] + at("after beep")
        s += [("poke", "cfg_band3_start", f24(144000)), ("poke", "cfg_band3_end", f24(146000)),
              ("poke", "cfg_band3_step", 2)]
        # another band and step (2 m, step 2), the squelch open by a
        # signal (TX closes it); then a normal PTT on the restored set-up;
        # a frequency with only its top byte set counts as configured
        for f in (144800, 0x070000):
            s += [("poke", "cfg_aprs_tx_freq", f24(f)), ("poke", "cfg_squelch_level", 127),
                  ("adc", "AD_SQL", 0xC0), ("run", 0.5)] + at("%d: squelch open" % f)
            s += [("local", True), ("trace", "aprs %d keying" % f, keying, 0.8)] + at("aprs %d tx" % f)
            # back_from_aprs_freq redraws before restoring tx_freq: the
            # arrows are stale until the next periodic redraw, so wait for it
            s += [("local", False), ("trace", "aprs %d off" % f, keying, 1.2)] + at("aprs %d released" % f)
            s += [("adc", "AD_SQL", 0), ("run", 0.5)] + ptt(0.4, "normal ptt after %d" % f)
        s += [("poke", "cfg_idlefn_delay", 5), ("local", True), ("run", 0.5)] + at("not idle")
        # the setting changes first, /LOCAL later: poked in the same instant,
        # a mainloop pass between its cfg_aprs_tx and /LOCAL reads saw both
        # (old setting, new edge) and sent, depending on code layout
        s += [("local", False), ("run", 0.3), ("poke", "cfg_aprs_tx", 0), ("poke", "cfg_idlefn_delay", 0),
              ("run", 0.1), ("local", True), ("run", 0.5)] + at("aprs off") + [("local", False), ("run", 0.3)]
        self.diff(s)

    def test_spontaneous_mprs(self):
        s = BOOT + [("poke", "cfg_report_type", 0), ("poke", "cfg_mprs_callsign", b"OH3XYZ\xff\xff"),
                    ("serial_rx", 0, nmea("GPRMC,123519,A,6130.12,N,02345.67,E,000.0,000.0,280926,,")),
                    ("run", 0.5)] + enter("434700")
        s += [("poke", "cfg_idlefn_delay", 0), ("poke", "cfg_mprs_seconds", (20).to_bytes(2, "little")),
              ("poke", "mprs_report_timer", (25).to_bytes(2, "little")), ("poke", "cfg_spontaneous_mprs", 1),
              ("run", 1.5)] + at("no aprs freq")
        s += [("poke", "cfg_aprs_tx_freq", f24(144800)),
              ("trace", "spontaneous", keying, 2.0)] + at("sent, back on 434700") + ptt(0.4, "ptt after")
        # the squelch open first, then the report due
        s += [("poke", "cfg_squelch_level", 127), ("adc", "AD_SQL", 0xC0), ("run", 1.0),
              ("poke", "mprs_report_timer", (25).to_bytes(2, "little")), ("run", 1.5)]
        s += at("squelch open: waits")
        s += [("adc", "AD_SQL", 0), ("trace", "closed: sends", keying, 4.0)]
        s += at("closed: sent")
        s += [("poke", "mprs_report_timer", (25).to_bytes(2, "little")), ("poke", "cfg_idlefn_delay", 3),
              ("run", 1.5)] + at("not idle")
        s += [("poke", "cfg_idlefn_delay", 0), ("poke", "cfg_mprs_seconds", b"\x00\x00"),
              ("run", 1.5)] + at("interval 0: never")
        self.diff(s)

    def test_spontaneous_not_while_transmitting(self):
        """the mainloop runs while the repeater transmits: a due report
        waits until the transmitter is off"""
        from test_rptr_diff import setup, TONE, CARRIER, NO_TONE, NO_CARRIER, w
        s = setup(cfg_spontaneous_mprs=1, cfg_idlefn_delay=0, cfg_mprs_seconds=w(20),
                  cfg_aprs_tx_freq=f24(432500), cfg_report_type=0)
        s += [TONE, CARRIER, ("run", 0.4), NO_TONE, NO_CARRIER, ("run", 0.3),
              ("poke", "mprs_report_timer", w(25))]
        s += [("trace", "repeater open, report due", lambda r: (r.peek("txon"), r.peek24("tx_freq")), 1.5)]
        s += at("still open")
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
