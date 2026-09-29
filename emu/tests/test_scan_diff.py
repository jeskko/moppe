"""
Scanner: differential scenarios for the C port (c/scan.c), asm build vs
C build.

The C build already steps a little slower than the asm build (about
1-10 % per channel: changed_frequency and go_mem_a go through the C
frequency code, c/freq.c), so over a scan the two drift apart and a
signal switched on at a fixed time would land on different channels.
So here:
  - what the scanner does is compared as the sequence of channels it
    visits (breakpoints on changed_frequency and go_mem_a; difftest
    "visits"), each
    stay (the time to the next visit) within STEP_TOL: settling, pauses,
    patience and tails;
  - signals belong to channels: World raises AD_SQL while the radio sits
    on a busy frequency (optionally only for so long after it first got
    there), checked every 5 ms;
  - full checkpoints (display, NV, events) only once the scanner has
    stopped; the synth load counters and SYNTH events are not compared
    (the builds load it at a different rate);
  - probes compare the scanner's RAM: slice table, mask, reject list,
    VIP list.
Covers band slices (unsorted, overlapping, empty, one channel, end below
start), S8B stepping, memory blocks and their mask digits, no channels at
all, permanent and temporary rejects (slot reuse, the reject key,
clearing, the VFO), auto-reject after the band's patience, pause/tail
lengths incl. 0 and 255, busy channels (double settling), forced
squelch, the FSK-carrier skip, mask toggles while scanning, the keys and
PTT that stop it, the idle-function start, P8N.

    R58_SCAN_REF_ROM / R58_SCAN_REF_LST    reference (default build/)
    R58_SCAN_CAND_ROM / R58_SCAN_CAND_LST  candidate (default build/)
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from difftest import run_diff  # noqa: E402
from test_radio import make_sane_nv  # noqa: E402
from r58emu import P8E, P8N, CU53AN, AD_SQL, load_symbols  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FW = os.path.join(ROOT, "firmware")
REF = (os.environ.get("R58_SCAN_REF_ROM", os.path.join(FW, "build-ref", "r58.bin")),
       os.environ.get("R58_SCAN_REF_LST", os.path.join(FW, "build-ref", "r58.map")))
CAND = (os.environ.get("R58_SCAN_CAND_ROM", os.path.join(FW, "build", "r58.bin")),
        os.environ.get("R58_SCAN_CAND_LST", os.path.join(FW, "build", "r58.map")))

MEM_SIZE = 12
# per stay: 15 ms + 10 %.  A mainloop pass of the C build can take up to
# ~14 ms longer on a P8N (a redraw falls in it), and a step may cross one
# more 10 ms systick; longer stays (settling, patience, tails) scale.  A
# one-pass stay (a rejected channel, a band wrap) is therefore not told
# apart from none: the mutation run's two yield mutants are timing-only.
STEP_TOL = (0.015, 0.1)
# a channel visit: a band frequency, or a memory recalled
CHANGED = [("changed_frequency", "_changed_frequency"), ("go_mem_a", "_go_mem_a")]


def f24(v):
    return (v & 0xFFFFFF).to_bytes(3, "little")


def visit(r):
    c = r.cpu()
    if c["pc"] == r.sym.get("go_mem_a", r.sym.get("_go_mem_a")):
        return ("memory", c["af"] >> 8)             # go_mem_a(A)
    on_mem = r.peek("mem_flags") & 1
    return (r.peek24("rx_freq"), r.peek("mem_idx") if on_mem else None)


class World:
    """busy: {freq: None (always) or seconds after the radio first sat
    there}; per side, so each build meets the signal on the same channel"""

    def __init__(self, busy):
        self.busy = busy
        self.first = {}

    def __call__(self, r, side):
        f = r.peek24("rx_freq")
        on = False
        if f in self.busy:
            t0 = self.first.setdefault((side, f), r.time)
            d = self.busy[f]
            on = d is None or r.time - t0 < d
        r.adc(AD_SQL, 0xC0 if on else 0)


def state(r):
    n = r.peek("scan_slicecnt")
    return (r.peek16("scan_mask"), n, r.peek("scan_slices", 6 * n) if n else b"",
            r.peek("tmp_rejects", 80), r.peek("reject_idx"), r.peek("scan_on"))


def stopped_state(r):
    return state(r) + (r.peek("vip_list", 30), r.peek("vip_idx"), r.peek("scan_paused"),
                       r.peek("squelch_muted") & 1, r.peek24("rx_freq"), r.peek("mem_idx"),
                       r.peek("scan_patience"))


def paused(label):
    """both builds sit on the same signal: the audio and pause state"""
    return [("probe", label + " paused",
             lambda r: (r.peek("scan_paused"), r.peek("squelch_muted") & 1, r.peek24("rx_freq"),
                        r.peek("vip_freq", 3)))]


def at(label):
    """a full comparison: only where the scanner has stopped"""
    return [("check", label), ("probe", label, stopped_state)]


def visits(label, seconds, world=None):
    return [("visits", label, seconds, CHANGED, visit, world, STEP_TOL), ("probe", label, state)]


def band(i, start, end, step=0, sctail=2, listen=15, autorej=0):
    """band i (1..6): start, end, duplex 0, step index, tail, listen,
    auto-reject"""
    b = "cfg_band%d_" % i
    return [("poke", b + "start", f24(start)), ("poke", b + "end", f24(end)),
            ("poke", b + "duplex", f24(0)), ("poke", b + "step", step),
            ("poke", b + "sctail", sctail), ("poke", b + "sclisten", listen),
            ("poke", b + "autoreject", autorej)]


_SYM = {}


def memory(n, freq, flags=0x05):
    """memory record n: freq, flags (VALID|SCANNABLE by default)"""
    if not _SYM:
        _SYM.update(load_symbols(REF[1]))
    rec = bytearray(MEM_SIZE)
    rec[0:3] = f24(freq)
    rec[_SYM["mem_FLAGS"]] = flags
    return [("poke", _SYM["memories"] + n * MEM_SIZE, bytes(rec))]


def start(digits=""):
    return ([("keys", digits)] if digits else []) + [("press", "S", 0.3), ("run", 0.05)]


def stop():
    return [("press", "#"), ("run", 0.3)]


SQL = [("poke", "cfg_squelch_level", 127)]


class ScanDiff(unittest.TestCase):
    def diff(self, scenario, card=P8E, synth_card=None):
        nv = make_sane_nv(card, CU53AN, synth_card)
        diffs = run_diff(scenario, REF, CAND, card=card, cu=CU53AN, nv=nv, tolerance_s=0.05,
                         ignore=("SYNTH", "rx_loads", "tx_loads", "ctrl_loads"))
        self.assertEqual(diffs, [], "\n".join(d[:3000] for d in diffs[:10]))

    def test_default_start(self):
        self.diff([("boot", 2.5)] + start() + visits("default bands", 3.0) + stop() + at("stopped"))

    def test_band_slices(self):
        """six bands: unsorted, overlapping, touching, one empty (start 0),
        one with its end below its start"""
        steps = [("boot", 2.5)]
        steps += band(1, 434600, 434700) + band(2, 433400, 433500)
        steps += band(3, 433475, 433550) + band(4, 433550, 433575)
        steps += band(5, 0, 435000) + band(6, 432100, 432000)
        steps += start("123456") + visits("six bands", 4.0) + stop() + at("stopped")
        steps += start("24") + visits("bands 2 4", 2.0) + stop() + at("stopped 24")
        steps += start("6") + visits("band 6", 1.0) + stop() + at("stopped 6")
        self.diff(steps)

    def test_band_slices_2(self):
        """slices whose frequencies differ only in the top byte (145 and
        433 MHz, 0x02.... / 0x06....), a start with low bytes 0 (65536), a
        band nested in another (sorted by start, not end)"""
        steps = [("boot", 2.5)]
        steps += band(1, 433400, 433500) + band(2, 145000, 145100) + band(3, 65536, 65600)
        steps += band(4, 434000, 434700) + band(5, 434100, 434200) + band(6, 0, 0)
        steps += start("12345") + visits("five bands", 5.0) + stop() + at("stopped")
        self.diff(steps)

    def test_band_steps_s8b(self):
        steps = [("boot", 2.5)] + band(1, 51490, 51610, step=1) + band(2, 50000, 50100, step=4)
        steps += start("12") + visits("s8b", 3.0) + stop() + at("stopped")
        self.diff(steps, synth_card=2)

    def test_memory_blocks(self):
        steps = [("boot", 2.5)]
        for n, f, fl in ((5, 433100, 5), (17, 433200, 5), (30, 440000, 5), (42, 433300, 1),
                         (44, 433325, 5), (71, 433400, 5), (88, 433425, 7), (95, 433450, 5),
                         (99, 433475, 5), (110, 433500, 5)):
            steps += memory(n, f, fl)
        for digits in ("0", "7", "89", "9", "01", "3", "1"):
            steps += start(digits) + visits("mask %s" % digits, 2.5) + stop() + at("stop %s" % digits)
        self.diff(steps)

    def test_memory_edges(self):
        """block 0x alone (mask bit 6), consecutive memories, a scan from
        mem_idx 130 and up (point_ix_memory_a clamps it to 99)"""
        steps = [("boot", 2.5)] + band(1, 0, 0) + band(2, 0, 0)
        for n, f in ((4, 433100), (5, 433125), (6, 433150), (90, 433200), (99, 433225)):
            steps += memory(n, f)
        steps += start("7") + [("press", "7", 0.2), ("press", "0", 0.2), ("run", 0.05)]
        steps += visits("block 0x only", 2.0) + stop() + at("stopped 0x")
        steps += [("poke", "mem_idx", 140), ("poke", "mem_flags", 5)]
        steps += start("9") + visits("from 140", 2.0) + stop() + at("stopped 9x")
        self.diff(steps)

    def test_no_channels(self):
        """memory block 7x with no memories and no bands: first_memory and
        first_frequency hand over to each other every pass"""
        steps = [("boot", 2.5)] + band(1, 0, 0) + band(2, 0, 0)
        steps += start("7") + visits("nothing to scan", 1.0)
        steps += [("probe", "on", lambda r: r.peek("scan_on"))] + stop() + at("stopped")
        self.diff(steps)

    def test_toggle_mask_while_scanning(self):
        steps = [("boot", 2.5)] + memory(21, 433150) + memory(3, 433175)
        steps += start("1") + visits("band 1", 1.0)
        for d in ("2", "0", "1", "9", "2"):
            steps += [("press", d, 0.2), ("run", 0.05)] + visits("toggle %s" % d, 1.5)
        steps += stop() + at("stopped")
        self.diff(steps)

    def test_signal_pause_patience_tail(self):
        w = World({433450: 5.0, 433525: 0.5, 433575: None})
        steps = [("boot", 2.5)] + SQL + band(1, 433400, 433600, sctail=1, listen=3)
        steps += start("1") + visits("signals", 14.0, w) + stop() + at("stopped")
        self.diff(steps)

    def test_tail_and_listen_extremes(self):
        for tail, listen in ((0, 1), (255, 2), (1, 255), (3, 0), (0, 0)):
            w = World({433450: 1.5, 433500: None})
            steps = [("boot", 2.5)] + SQL + band(1, 433400, 433600, sctail=tail, listen=listen)
            steps += start("1") + visits("tail %d listen %d" % (tail, listen), 8.0, w)
            steps += stop() + at("stopped %d %d" % (tail, listen))
            self.diff(steps)

    def test_busy_channels_settle_longer(self):
        """a signal on every channel, patience 0: it moves on at once.  The
        settling time is meant to double while the squelch is open, but
        every frequency change closes it first (close_squelch), so it
        never does (notes/open-bugs.md)"""
        w = World({433400 + 25 * i: None for i in range(8)})
        for rate in (2, 10):
            steps = [("boot", 2.5)] + SQL + [("poke", "cfg_scan_rate_kvik", rate)]
            steps += band(1, 433400, 433600, listen=0)
            steps += start("1") + visits("busy %d" % rate, 3.0, w) + stop() + at("stopped")
            self.diff(steps)

    def test_auto_reject(self):
        w = World({433425: None, 433475: None, 433525: None, 433550: None})
        steps = [("boot", 2.5)] + SQL + [("poke", "cfg_num_tmp_rejects", 3),
                                         ("poke", "cfg_unreject_mins", 0)]
        steps += band(1, 433400, 433600, listen=1, autorej=1)
        steps += start("1") + visits("auto rejects", 10.0, w) + stop() + at("stopped")
        self.diff(steps)

    def test_reject_key(self):
        """long S: reject the channel (the VIP one while scanning); longer:
        clear; slots reused round robin when full, the same frequency
        twice"""
        busy = {433425: None, 433475: None, 433525: None, 433575: None}
        w = World(busy)
        steps = [("boot", 2.5)] + SQL + [("poke", "cfg_num_tmp_rejects", 2),
                                         ("poke", "cfg_unreject_mins", 7)]
        steps += band(1, 433400, 433600, listen=255)
        steps += start("1")
        for i in range(4):
            steps += visits("to a signal %d" % i, 1.5, w) + paused("signal %d" % i)
            steps += [("press", "S", 1.5), ("run", 0.1)] + visits("rejected %d" % i, 0.3, w)
        steps += [("press", "S", 2.6), ("run", 0.1)] + visits("cleared", 1.5, w)
        steps += stop() + at("stopped")
        # not scanning: the VFO frequency, twice
        steps += [("keys", "433425"), ("press", "#"), ("run", 0.3),
                  ("press", "S", 1.5), ("run", 0.1)] + at("reject vfo")
        steps += [("press", "S", 1.5), ("run", 0.1)] + at("reject vfo again")
        steps += start("1") + visits("skips 433425", 2.0) + stop() + at("stopped again")
        self.diff(steps)

    def test_stale_temp_reject(self):
        """a temporary reject whose minutes ran out (0) no longer rejects"""
        steps = [("boot", 2.5)] + band(1, 433400, 433600)
        steps += [("poke", "tmp_rejects", f24(433450) + b"\x00" + f24(433500) + b"\x03")]
        steps += start("1") + visits("stale and live", 2.0) + stop() + at("stopped")
        self.diff(steps)

    def test_reject_key_rejects_the_vip(self):
        """long S while scanning on: the reject is the last channel that had
        a signal (vip_freq), not the one the scanner is on"""
        w = World({433450: 1.0})
        steps = [("boot", 2.5)] + SQL + [("poke", "cfg_unreject_mins", 5)]
        steps += band(1, 433400, 433600, sctail=0, listen=255)
        steps += start("1") + visits("signal, then on", 3.0, w)
        steps += [("press", "S", 1.5), ("run", 0.1)] + visits("rejected the vip", 2.0, w)
        steps += stop() + at("stopped")
        self.diff(steps)

    def test_permanent_rejects(self):
        steps = [("boot", 2.5)] + band(1, 433400, 433600)
        steps += [("poke", "cfg_reject_0", f24(433400)), ("poke", "cfg_reject_9", f24(433450)),
                  ("poke", "cfg_reject_10", f24(433500)), ("poke", "cfg_reject_19", f24(433575)),
                  ("poke", "cfg_reject_5", f24(433425))]
        steps += start("1") + visits("perm rejects", 2.0) + stop() + at("stopped")
        steps += [("poke", "cfg_reject_%d" % i, f24(433400 + 25 * i)) for i in range(8)]
        steps += start("1") + visits("all rejected", 1.0) + stop() + at("stopped all")
        self.diff(steps)

    def test_forced_squelch(self):
        w = World({433475: 1.0})
        steps = [("boot", 2.5)] + SQL + band(1, 433400, 433600, listen=2, sctail=1)
        steps += start("1") + visits("to the signal", 1.0, w)
        steps += [("poke", "squelch_forced", 1)] + visits("forced", 3.0, w)
        steps += [("poke", "squelch_forced", 0)] + visits("unforced", 3.0, w)
        steps += stop() + at("stopped")
        # forced while scanning past quiet channels: it stays on the next
        steps += start("1") + visits("quiet", 0.5)
        steps += [("poke", "squelch_forced", 1)] + visits("forced while scanning", 2.0)
        steps += stop() + at("stopped again")
        self.diff(steps)

    def test_fsk_carrier_skip(self):
        from test_fsk import with_crc
        pkt = with_crc(b"\xDD" + b"HELLO 42" + b"\xFF" * 4)
        for skip in (0, 1):
            w = World({433475: 4.0})
            steps = [("boot", 2.5)] + SQL + [("poke", "cfg_scan_skip_fsk_channels", skip)]
            steps += band(1, 433400, 433600, listen=5)
            steps += start("1") + visits("to the signal", 1.0, w)
            for i in range(4):
                steps += [("modem_rx", pkt)] + visits("fsk %d %d" % (skip, i), 0.3, w)
            steps += visits("after", 4.0, w) + stop() + at("stopped %d" % skip)
            self.diff(steps)

    def test_stop_keys_and_ptt(self):
        w = World({433450: None})
        steps = [("boot", 2.5)] + SQL + band(1, 433400, 433600, listen=255)
        for how in (("press", "#"), ("press", "B"), ("press", "3", 0.7), ("press", "6", 0.7),
                    ("press", "C"), ("ptt", True)):
            steps += start("1") + visits("to the signal %r" % (how,), 1.0, w)
            steps += [how, ("run", 0.3)] + at("after %r" % (how,))
            if how[0] == "ptt":
                steps += [("ptt", False), ("run", 0.3)] + at("ptt off")
        steps += [("press", "C"), ("press", "C"), ("run", 0.3)] + at("vip")
        steps += memory(12, 433125) + [("keys", "12"), ("press", "#"), ("run", 0.5)]
        steps += start("01") + visits("from a memory", 1.5) + stop() + at("stopped")
        self.diff(steps)

    def test_idle_function_starts_scan(self):
        steps = [("boot", 2.5), ("poke", "cfg_idlefn", 1), ("poke", "cfg_idlefn_delay", 1)]
        steps += [("keys", "1"), ("press", "#"), ("run", 0.3)]
        steps += [("run", 58.0)] + visits("idle scan", 5.0)
        steps += [("probe", "on", lambda r: r.peek("scan_on"))] + stop() + at("stopped")
        self.diff(steps)

    def test_p8n(self):
        w = World({433450: 2.5})
        steps = [("boot", 2.5)] + SQL
        steps += band(1, 434600, 434700) + band(2, 433400, 433500, listen=2) + memory(33, 433250)
        steps += start("123") + visits("p8n", 8.0, w) + stop() + at("stopped")
        self.diff(steps, card=P8N)


if __name__ == "__main__":
    unittest.main()
