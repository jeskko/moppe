"""
Repeater state machine, CW and note sequences: differential scenarios for
the C port (c/rptr.c, bank 2).  The reference is the assembler build
(firmware/build), not the v3_Z release: the CW messages' CTCSS handling
was fixed (hybrid-plan.md, "Firmware behaviour the tests pinned down").

Besides difftest's display/latch/event/NV comparison, each scenario
compares the tones (CW elements, gaps, notes, blips: "tones" steps) and
the repeater's own RAM ("probe" steps: the state resolved per build, the
timers, the command and CTCSS flags).

    R58_RPTR_REF_ROM / R58_RPTR_REF_LST    reference (default build/)
    R58_RPTR_CAND_ROM / R58_RPTR_CAND_LST  candidate (default build-c/)
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from difftest import run_diff  # noqa: E402
from test_radio import make_sane_nv  # noqa: E402
from test_scan_rptr import cw_str, repeater_state_name  # noqa: E402
from r58emu import P8E, P8N, CU53AN, AD_SQL, AD_TP4, AD_RPM  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FW = os.path.join(ROOT, "firmware")
REF = (os.environ.get("R58_RPTR_REF_ROM", os.path.join(FW, "build", "r58.bin")),
       os.environ.get("R58_RPTR_REF_LST", os.path.join(FW, "build", "r58.map")))
CAND = (os.environ.get("R58_RPTR_CAND_ROM", os.path.join(FW, "build-c", "r58.bin")),
        os.environ.get("R58_RPTR_CAND_LST", os.path.join(FW, "build-c", "r58.map")))

WORDS = ("repeater_timer_other", "repeater_timer_ID")
BYTES = ("repeater_timer_BLIP_state", "squelch_tightening", "txpwr_increment",
         "repeater_req", "repeater_is_suspended", "repeater_ptt_seen",
         "ctcss_is_on", "cw_slot_ticks", "repeater_cw_sendit_all", "nosir", "txon")


def probe(r):
    return ((repeater_state_name(r),) + tuple(r.peek16(n) for n in WORDS) +
            tuple(r.peek(n) for n in BYTES) + (r.peek16("cw_pitch_cnt"),))


def w(v):
    return bytes([v & 0xFF, v >> 8])


def at(label):
    return [("check", label), ("probe", label, probe)]


CARRIER, NO_CARRIER = ("adc", AD_SQL, 0xC0), ("adc", AD_SQL, 0)
TONE, NO_TONE = ("ccir", 8), ("ccir", 0x0F)


def setup(**cfg):
    """Repeater mode with short messages and timers, past the boot minute,
    idle.  Checks must land between CW messages (a checkpoint on an
    element edge compares OUT0's tone bits at an arbitrary instant), so
    the "during" ID (TID) is long unless a scenario tests it."""
    pokes = {
        "cfg_squelch_level": 127, "cfg_cw_speed": 200,
        "repeater_cfg_id_greet1": cw_str("E"), "repeater_cfg_id_greet2": cw_str(""),
        "repeater_cfg_id_greet3": cw_str("I"),
        "repeater_cfg_id_during1": cw_str("T"), "repeater_cfg_id_during2": cw_str(""),
        "repeater_cfg_id_during3": cw_str(""),
        "repeater_cfg_id_bye1": cw_str("EE"), "repeater_cfg_id_bye2": cw_str(""),
        "repeater_cfg_id_bye3": cw_str(""),
        "repeater_cfg_msg_hog": cw_str("TT"), "repeater_cfg_blip": cw_str("E"),
        "repeater_cfg_TOPEN": w(3), "repeater_cfg_TID": w(30), "repeater_cfg_THOG": w(4),
        "repeater_cfg_TCLS": w(2), "repeater_cfg_TDEAD": w(2), "repeater_cfg_TBEEPMAX": w(5),
        "repeater_cfg_TBLIP": 50,
    }
    pokes.update(cfg)
    steps = [("boot", 2.5)] + [("poke", k, v) for k, v in pokes.items()]
    steps += [("keys", "433500"), ("press", "#"), ("run", 0.3),
              ("poke", "cfg_function", 1), ("run", 0.2)]
    steps += at("boot")
    steps += [("poke", "repeater_timer_other", w(1)), ("run", 1.2)]
    steps += at("idle")
    return steps


def open_by_tone():
    return [TONE, CARRIER, ("run", 0.4)] + at("opening") + [
        NO_TONE, NO_CARRIER, ("tones", "greet", 1.2)] + at("open")


def over(label, seconds=0.3):
    """A carrier (an over) then its end: active, then open with a blip."""
    return [CARRIER, ("run", seconds)] + at(label + " active") + [
        NO_CARRIER, ("tones", label + " blip", 1.0)] + at(label + " open")


SCN_CYCLE = setup(repeater_cfg_TID=w(2)) + open_by_tone() + over("over 1") + [
    ("tones", "id during and topen", 3.0)] + at("closing") + [
    CARRIER, ("run", 0.3)] + at("closing -> active") + [
    NO_CARRIER, ("run", 1.0)] + at("-> open") + [
    ("run", 3.2)] + at("closing again") + [
    TONE, CARRIER, ("run", 0.2)] + at("reopening") + [
    NO_TONE, ("run", 0.2)] + at("reopening -> active") + [
    NO_CARRIER, ("run", 1.0), ("run", 2.3)] + at("closing 3") + [
    TONE, CARRIER, ("run", 0.3)] + at("reopening 2") + [
    NO_TONE, NO_CARRIER, ("run", 0.4)] + at("reopening -> open") + [
    ("run", 3.0)] + at("closing 4") + [("tones", "tcls -> bye", 2.5)] + at("idle after bye")

SCN_HOG = setup(repeater_cfg_access_method=1) + [
    CARRIER, ("run", 0.3)] + at("carrier access") + [
    NO_CARRIER, ("tones", "greet", 1.2)] + at("open") + [
    CARRIER, ("run", 3.5), ("tones", "hog", 2.0)] + at("lockout") + [
    NO_CARRIER, ("tones", "lockout -> bye", 3.0)] + at("idle")

SCN_BEEP_TOO_LONG = setup(repeater_cfg_TBEEPMAX=w(1)) + [
    TONE, CARRIER, ("run", 2.2)] + at("beep too long") + [
    NO_TONE, ("run", 0.3)] + at("still carrier") + [
    NO_CARRIER, ("run", 0.3)] + at("idle")


def command(label, req, before=(), seconds=1.0):
    return list(before) + [("poke", "repeater_req", req), ("tones", label, seconds)] + at(label)


def trace(label, fn, seconds):
    """fn(radio) traced (difftest "trace"): for what changes and changes
    back between checkpoints."""
    return [("trace", label, fn, seconds)]


def ctcss_now(r):
    return r.peek("ctcss_is_on")


def marker_tone(r):
    return r.peek("mt_timer") > 0, r.latches()["out0"] & 0x60, r.pit(1)["count"]   # MTC, CCIRC


SCN_COMMANDS = setup(cfg_rssi_S1=20, cfg_rssi_S9=200, repeater_cfg_TOPEN=w(60)) + open_by_tone() + (
    command("#1 tighten", 1) + command("#3 tx power", 3) + command("#5 bongos", 5) +
    command("#5 bongos off", 5) + command("#0 restore", 0xFF) + command("roger", 0xFE) +
    command("report S1", ord("#"), seconds=2.6, before=[("poke", "repeater_sig", 10), ("poke", "last_sqtail", 1)]) +
    command("report S9", ord("#"), seconds=2.6, before=[("poke", "repeater_sig", 250), ("poke", "last_sqtail", 0)]) +
    command("report S5", ord("#"), seconds=2.6, before=[("poke", "repeater_sig", 100)]) +
    command("report S2", ord("#"), seconds=2.6, before=[("poke", "repeater_sig", 21)]) +
    command("#9 hidden", 9, [("poke", "cfg_repeater_cmd_9_hidden", 1)]) +
    command("#9 close", 9, [("poke", "cfg_repeater_cmd_9_hidden", 0)]) +
    command("roger from idle", 0xFE))

SCN_EMPTY_BYE = setup(repeater_cfg_id_bye1=cw_str(""), repeater_cfg_id_bye2=cw_str(""),
                      repeater_cfg_id_bye3=cw_str(""), repeater_cfg_mprs_id=0) + open_by_tone() + [
    ("run", 3.3)] + at("closing") + [("run", 2.5)] + at("idle, nothing sent")

# CUSTOM (4): send_cw_prolog turns CTCSS on, and when the message ends with
# a carrier present (aon after the last element keeps it on) the epilog
# turns it off for its 200 ms wait, until the open state's poll goes active
SCN_CTCSS_CUSTOM_EPILOG = setup(cfg_ctcss_output_when=4, cfg_ctcss_tx_hz=10,
                                repeater_cfg_TOPEN=w(60)) + open_by_tone() + [
    CARRIER, ("poke", "repeater_req", 1)] + trace("roger with carrier", ctcss_now, 1.2) + [
    NO_CARRIER, ("run", 1.0)] + at("after")

SCN_LOCAL_SUSPEND = setup() + [
    ("local", True), ("tones", "local rising", 1.2)] + at("open by /LOCAL") + [
    ("local", False), ("run", 0.3),
    ("poke", "cfg_repeater_suspended", 1), ("tones", "suspend qrt", 1.5)] + at("suspended") + [
    ("run", 1.0)] + at("still suspended") + [
    ("poke", "cfg_repeater_suspended", 0), ("tones", "resume", 1.5)] + at("resumed")


def blip(label, *pokes):
    """An over, then the pokes (after the carrier drops, before the blip
    timer runs out), and the blip."""
    return [CARRIER, ("run", 0.3), NO_CARRIER, ("run", 0.02)] + [
        ("poke", k, v) for k, v in pokes] + [("tones", label, 1.2)] + at(label)


SCN_BLIPS = setup(
    repeater_cfg_blip_link=cw_str("T"), cfg_cw_pitch_blip=100, cfg_cw_pitch_blip_link=80,
    cfg_cw_pitch_blip_gpio=120,
    repeater_cfg_blip_gpio_001=cw_str("I"), repeater_cfg_blip_gpio_010=cw_str(""),
    repeater_cfg_blip_gpio_011=cw_str("S"),
    repeater_cfg_rssi_A=50, repeater_cfg_blip_rssi_A=cw_str("A"),
    repeater_cfg_rssi_B=100, repeater_cfg_blip_rssi_B=cw_str("B"),
    repeater_cfg_rssi_C=150, repeater_cfg_blip_rssi_C=cw_str(""), repeater_cfg_TOPEN=w(60),
) + open_by_tone() + (
    blip("plain blip") +
    blip("link blip", ("repeater_ptt_seen", 1)) +
    blip("gpio1 blip", ("cfg_gpio1_state", 1)) +
    blip("gpio 011 blip", ("cfg_gpio2_state", 1)) +
    blip("gpio 010 empty -> default", ("cfg_gpio1_state", 0)) +
    blip("bongo A", ("cfg_gpio2_state", 0), ("repeater_cfg_rssi_bongos", 1), ("repeater_sig", 70)) +
    blip("bongo B", ("repeater_sig", 120)) +
    blip("bongo C empty -> default", ("repeater_sig", 200)) +
    blip("bongo below A", ("repeater_sig", 20)) +
    blip("musical", ("repeater_cfg_rssi_bongos", 0), ("repeater_cfg_musical_blips", 1),
         ("repeater_cfg_blip", bytes([0, 5, 10, 24, 25, 30, 0xFF, 0xFF]))) +
    # pre-emption: at 60 CPM the squelch opens early in the first dash (the
    # dash runs out on its own, not as the rest of the message would), not
    # near a slot edge where the builds' few ms differ
    [("poke", "repeater_cfg_musical_blips", 0), ("poke", "repeater_cfg_blip", cw_str("TTTT")),
     ("poke", "cfg_cw_speed", 60),
     CARRIER, ("run", 0.3), NO_CARRIER, ("run", 0.62), CARRIER] +
    trace("pre-empted", marker_tone, 0.8) + [NO_CARRIER, ("run", 1.0)] + at("after pre-empt"))

def alerts_mprs(mprs_id):
    return setup(
    cfg_temperature_limit_hot=100, cfg_temperature_limit_cold=30, cfg_rpm_limit=10,
    repeater_cfg_msg_hot_alert=cw_str("H"), repeater_cfg_msg_cold_alert=cw_str("C"),
    repeater_cfg_msg_ant_bad=cw_str("A"),
    repeater_cfg_mprs_id=mprs_id, cfg_report_type=0, cfg_mprs_callsign=b"OH3RPT\xff\xff",
    repeater_cfg_TID=w(2), repeater_cfg_TOPEN=w(8),
) + [("adc", AD_TP4, 50), ("adc", AD_RPM, 200)] + [
    TONE, CARRIER, ("run", 0.4), NO_TONE, NO_CARRIER, ("tones", "greet with alerts", 2.5)] + at("open") + [
    ("tones", "id during with alerts", 2.5)] + at("during") + [
    ("adc", AD_TP4, 60), ("adc", AD_RPM, 0),
    ("poke", "repeater_req", ord("#")), ("tones", "report + mprs", 1.5)] + at("report") + [
    ("run", 3.5)] + at("closing") + [("tones", "bye with alerts", 4.0)] + at("closed")


def mic(afsrc):
    """An over with the handset PTT held in the middle: where /MIC routes
    the audio (OUT0 MICM, compared at the checks)."""
    return setup(repeater_cfg_afsrc=afsrc) + open_by_tone() + [
        CARRIER, ("run", 0.3)] + at("active") + [
        ("ptt", True), ("run", 0.2)] + at("active, ptt") + [
        ("ptt", False), ("run", 0.2), NO_CARRIER, ("run", 0.1)] + at("open") + [
        ("run", 1.0)] + at("after blip")


def ctcss(when):
    return setup(cfg_ctcss_output_when=when, cfg_ctcss_tx_hz=10) + open_by_tone() + \
        over("over") + [("run", 3.2), ("tones", "bye", 3.0)] + at("idle")


class RepeaterDiff(unittest.TestCase):
    def diff(self, scenario, card=P8E):
        nv = make_sane_nv(card, CU53AN)
        diffs = run_diff(scenario, REF, CAND, card=card, cu=CU53AN, nv=nv)
        self.assertEqual(diffs, [], "\n".join(diffs))

    def test_cycle(self):
        self.diff(SCN_CYCLE)

    def test_cycle_p8n(self):
        self.diff(SCN_CYCLE, card=P8N)

    def test_hog_lockout(self):
        self.diff(SCN_HOG)

    def test_beep_too_long(self):
        self.diff(SCN_BEEP_TOO_LONG)

    def test_commands(self):
        self.diff(SCN_COMMANDS)

    def test_local_and_suspend(self):
        self.diff(SCN_LOCAL_SUSPEND)

    def test_blips(self):
        self.diff(SCN_BLIPS)

    def test_alerts_and_mprs_id(self):
        for mprs_id in (0x05, 0x0A):        # greet+bye, during+report
            with self.subTest(mprs_id=mprs_id):
                self.diff(alerts_mprs(mprs_id))

    def test_empty_bye(self):
        self.diff(SCN_EMPTY_BYE)

    def test_ctcss_custom_epilog(self):
        self.diff(SCN_CTCSS_CUSTOM_EPILOG)

    def test_mic_routing(self):
        for afsrc in (0, 1, 2):
            with self.subTest(afsrc=afsrc):
                self.diff(mic(afsrc))

    def test_ctcss_output_when(self):
        for when in (1, 2, 4):
            with self.subTest(when=when):
                self.diff(ctcss(when))

    def test_access_none_and_ctcss(self):
        for method in (2, 3):
            with self.subTest(method=method):
                self.diff(setup(repeater_cfg_access_method=method) + [
                    TONE, CARRIER, ("run", 0.5)] + at("tone") + [
                    NO_TONE, NO_CARRIER, ("run", 1.0)] + at("after"))


if __name__ == "__main__":
    unittest.main()
