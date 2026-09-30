"""
Key handlers, memories and the VIP list: differential scenarios for the
C port (c/keys.c), asm build vs C build.

What keys.c dispatches to outside the menu: digit entry and backspace
(incl. the menu's letters and punctuation), '#' (frequency/memory entry,
the VIP walk, memory store with its hold lengths), the long digits
(squelch, memory and frequency up/down/default, volume default), '+'/'-'
volume, 'B' monitor (short/long, on a duplex channel), 'R' duplex key
(its hold lengths and feedback texts), 'S' scanner key (start, reject,
clear), '*' call packet or 1750 Hz beep, 'K' audio destination; and the
memories: store/recall, hidden and invalid slots, wrap-around, the VIP
list (duplicates, the 10-entry ring, PTT remembering the channel).

Checkpoints compare display, icons, latches, events and NV (memories and
the VIP list are NV); probes add the RAM they leave behind (digit buffer,
VIP index, feedback text, squelch forcing, ...).  Holds are chosen clear
of the key timers: `key_time` steps about once a second, for '#', 'R',
'S' from ~1.2 s of hold (1 at 1.2 s, 2 at 2.2 s, 3 at 3.2 s), for a held
digit from the long press on (1 at ~0.6 s, 2 at 1.65 s, 3 at 2.65 s, 4 at
3.65 s); `keydown` counts 10 ms ticks.

    R58_KEYS_REF_ROM / R58_KEYS_REF_LST    reference (default build/)
    R58_KEYS_CAND_ROM / R58_KEYS_CAND_LST  candidate (default build/)
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from difftest import builds, skip_unless_built, DiffCase  # noqa: E402
from helpers import f24, at as _at  # noqa: E402
from r58emu import P8N, CU58AF, load_symbols  # noqa: E402

REF, CAND = builds("KEYS")
setUpModule = skip_unless_built(REF, CAND)

MEM_SIZE = 12
_SYM = {}


def sym(name):
    if not _SYM:
        _SYM.update(load_symbols(REF[1]))
    return _SYM[name]


def memory(n, rx, tx=None, flags=0x05, ctcss_t=0, ctcss_r=0):
    """memory record n (0..129): rx, tx (default rx), flags
    (VALID|SCANNABLE by default), CTCSS indexes"""
    rec = bytearray(MEM_SIZE)
    rec[0:3] = f24(rx)
    rec[3:6] = f24(rx if tx is None else tx)
    rec[sym("mem_FLAGS")] = flags
    rec[sym("mem_CTCSSt")] = ctcss_t
    rec[sym("mem_CTCSSr")] = ctcss_r
    rec[sym("mem_BAND")] = 0x33
    rec[sym("mem_FOO2")] = 0x44
    rec[sym("mem_FOO3")] = 0x55
    return [("poke", sym("memories") + n * MEM_SIZE, bytes(rec))]


def feedback(r):
    p = r.peek16("adj_feedback")
    return r.peek(p, 10) if p else None


def state(r):
    """RAM the key handlers leave that the display/NV need not show"""
    n = r.peek("digidx")
    return (n, r.peek("digbuf", min(n, 16)) if n else b"", r.peek("vip_idx"),
            r.peek("mem_idx"), r.peek("mem_flags"), r.peek24("rx_freq"), r.peek24("tx_freq"),
            r.peek("volume"), r.peek("audio_dst"), r.peek("squelch_forced"),
            r.peek("cfg_squelch_level"), r.peek("duplex_state"), r.peek("scan_on"),
            r.peek("mem_ctcss_tx_hz"), r.peek("mem_ctcss_rx_hz"), feedback(r),
            r.peek("tmp_rejects", 20))


def at(label):
    return _at(label, state)


def key(k, hold=0.15, label=None, gap=0.3):
    """press k, then compare"""
    return [("press", k, hold), ("run", gap)] + at(label or "%r %.2f" % (k, hold))


def keys(ks, hold=0.15, label=None):
    out = []
    for k in ks:
        out += key(k, hold, label)
    return out


def held(k, seconds, label, mid=True):
    """hold k for `seconds`, compare mid-hold, release, compare.  With
    mid=False only the RAM is compared mid-hold: a repeating key starts a
    30 ms key blip (OUT0 bit 6) on every repeat, so a checkpoint there
    can land inside one in one build and not in the other."""
    return [("key_down", k), ("run", seconds)] + \
        (at(label + " held") if mid else [("probe", label + " held", state)]) + \
        [("key_up",), ("run", 0.4)] + at(label + " released")


def enter(digits, label=None):
    return [("keys", digits), ("press", "#"), ("run", 0.3)] + at(label or "enter " + digits)


def script(ks, label):
    """keys no handset has ('K', 'T'): through the off-hook script"""
    return [("poke", "cfg_offhook_script", ks.encode() + b"\xff" * (8 - len(ks))),
            ("hook", True), ("run", 0.5)] + at(label) + [("hook", False), ("run", 0.5)]


BOOT = [("boot", 2.5)]		# copy before +=


class KeysDiff(DiffCase):
    REF = REF
    CAND = CAND
    msg_max_items = 10
    msg_max_chars = 3000

    # ---- digit entry, backspace

    def test_digit_entry_and_backspace(self):
        s = BOOT + keys("1234", label="four digits")
        s += key("C", label="one erased") + key("C") + key("C") + key("C") + key("C", label="C on empty")
        s += [("keys", "1234567890123456")] + at("16 digits")
        s += key("7", label="17th ignored")
        s += held("C", 0.8, "C before its repeat", mid=False)
        s += [("keys", "123456")] + held("C", 1.5, "C repeating (from ~1.1 s)", mid=False)
        s += key("C", label="C on empty again")
        s += [("keys", "98")] + held("C", 0.25, "C held just past 200 ms")
        self.diff(s)

    def test_execute_entries(self):
        s = BOOT + [("poke", "cfg_implied", b"\x04\x03\x03")]
        for d in ("433525", "4500", "475", "7", "42", "50000", "4335250", "1234567890123456",
                  "145300", "123", "99"):
            s += enter(d)
        s += [("poke", "cfg_implied", b"\x01\x04\x05")] + enter("5250") + enter("525")
        self.diff(s)

    def test_vip_walk(self):
        s = BOOT + memory(3, 433300) + memory(17, 433425, 431825) + memory(88, 145500)
        for d in ("433500", "3", "433600", "17", "433500", "88", "145525", "3", "433700",
                  "433725", "367964", "51000", "433775", "433800"):
            s += enter(d)
        for i in range(12):
            s += key("#", label="vip %d" % i)
        s += key("C", label="C rewinds") + key("#", label="vip after C")
        s += [("keys", "5")] + key("C", label="digit erased, rewound") + key("#") + key("#")
        self.diff(s)

    def test_ptt_remembers_vip(self):
        s = BOOT + memory(9, 433450) + enter("433525") + enter("9")
        s += [("ptt", True), ("run", 0.3), ("ptt", False), ("run", 0.3)] + at("ptt on memory")
        s += enter("433575") + [("ptt", True), ("run", 0.3), ("ptt", False), ("run", 0.3)]
        s += at("ptt on vfo") + key("#") + key("#") + key("#")
        self.diff(s)

    # ---- memories

    def test_store_memory(self):
        s = BOOT + enter("433525")
        # slots with old contents: the store overwrites band byte and the
        # two spare bytes, keeps the CTCSS bytes
        for m in (0, 5, 99, 129):
            s += memory(m, 145000 + m, 145600, flags=0x07, ctcss_t=3, ctcss_r=4)
        for digits, secs in (("5", 1.7), ("", 2.7), ("0", 3.7), ("129", 1.7), ("130", 1.7),
                             ("250", 2.7), ("1234", 1.7), ("", 1.7)):
            s += [("keys", digits)] + held("#", secs, "store %r %.1f" % (digits, secs))
            s += enter("4336%02d" % len(digits))
        s += enter("5") + enter("99") + enter("129")
        # a stored duplex channel keeps its TX frequency; CTCSS is not stored
        s += enter("434700") + [("keys", "21")] + held("#", 1.7, "store duplex")
        s += enter("433000") + enter("21")
        self.diff(s)

    def test_memory_up_down(self):
        s = BOOT + memory(0, 433100) + memory(4, 433200, flags=0x03) + memory(7, 433300, flags=0x01)
        s += memory(8, 433325, 431725, flags=0x05, ctcss_t=5, ctcss_r=9)
        s += memory(128, 433400) + memory(129, 433425, flags=0x00) + memory(64, 145500, flags=0x07)
        s += enter("7") + enter("433500")
        s += key("2", 0.65, "up from vfo: last memory")
        for i in range(6):
            s += key("2", 0.65, "up %d" % i)
        s += enter("433500") + key("5", 0.65, "down from vfo: last memory")
        for i in range(6):
            s += key("5", 0.65, "down %d" % i)
        s += enter("4") + enter("433500") + key("2", 0.65, "up from vfo, last hidden")
        s += enter("64") + enter("433500") + key("5", 0.65, "down from vfo, last hidden")
        s += [("keys", "12")] + key("2", 0.65, "up with digits typed")
        s += held("2", 1.8, "up repeating", mid=False)
        self.diff(s)

    def test_memory_none_valid(self):
        s = BOOT + [("poke", sym("memories"), b"\x00" * (130 * MEM_SIZE))]
        s += enter("433500") + key("2", 0.65, "up, none valid") + key("5", 0.65, "down, none valid")
        s += enter("12") + key("2", 0.65, "up from an empty memory")
        self.diff(s)

    def test_default_memory(self):
        s = BOOT + memory(11, 433275) + memory(99, 433475) + memory(129, 433450, flags=0x03)
        for m in (11, 99, 129, 130, 135, 0):
            s += [("poke", "cfg_def_memory", m), ("keys", "3")]
            s += held("8", 1.0, "def memory %d" % m)
        s += [("poke", "cfg_def_memory", 11), ("poke", "cfg_idlefn", 2),
              ("poke", "cfg_idlefn_delay", 1), ("run", 75)] + at("idle function")
        self.diff(s)

    # ---- long digits: squelch, frequency, volume

    def test_squelch_keys(self):
        s = BOOT + [("poke", "cfg_squelch_level", 253), ("poke", "cfg_def_squelch", 90)]
        s += key("1", 0.65, "sq up") + key("1", 0.65, "sq up") + key("1", 0.65, "sq up at 255")
        s += [("poke", "cfg_squelch_level", 1)]
        s += key("4", 0.65, "sq down") + key("4", 0.65, "sq down at 0")
        s += key("B", label="forced") + key("4", 0.65, "sq down unforces")
        s += key("B", label="forced") + key("1", 0.65, "sq up unforces")
        s += [("keys", "44")] + key("7", 0.65, "sq default")
        s += [("poke", "cfg_squelch_level", 40)] + held("7", 1.3, "sq still default")
        s += [("poke", "cfg_squelch_level", 40)] + held("7", 2.1, "sq store default")
        s += key("B", label="forced") + key("7", 0.65, "sq default unforces")
        self.diff(s)

    def test_frequency_keys(self):
        s = BOOT + memory(6, 433200) + [("poke", "cfg_def_frequency", f24(145500))]
        s += enter("6") + key("3", 0.65, "freq up leaves memory")
        s += [("keys", "12")] + key("6", 0.65, "freq down clears digits")
        s += held("3", 1.8, "freq up repeating", mid=False)
        s += enter("6") + held("9", 1.0, "default frequency")
        self.diff(s)

    def test_keys_stop_scanner(self):
        """'#', 'B', long 3/6/9 and a digit while scanning.  The C scanner
        steps at another speed (test_scan_diff.py), so the scan covers one
        memory only (mask 0: memories 0-9, only 2 scannable) and the synth
        loads are not compared"""
        s = BOOT + memory(2, 433200) + memory(6, 433250, flags=0x01) + enter("433500")
        scan = [("keys", "0"), ("press", "S", 0.3), ("run", 1.0)]
        s += key("3", 0.65, "freq up stops scanner") + scan + key("6", 0.65, "freq down stops")
        s += scan + held("9", 1.0, "default freq stops") + scan + key("B", label="B stops")
        s += scan + key("#", label="# stops") + scan + key("C", label="C stops")
        s += scan + key("1", label="digit toggles mask") + key("#", label="stopped")
        s += scan + key("*", label="star while scanning") + key("#")
        s += scan + key("E", label="menu while scanning") + key("1", label="menu digit stops")
        s += key("E", label="menu left")
        # R does not stop the scanner: compare once '#' has
        s += scan + [("press", "R", 1.7), ("run", 0.3)] + key("#", label="R while scanning")
        self.diff(s, ignore=("SYNTH", "rx_loads", "tx_loads", "ctrl_loads"))

    def test_volume_keys(self):
        s = BOOT + [("poke", "cfg_def_volume", 5)]
        for i in range(10):
            s += key("+", label="vol up %d" % i)
        for i in range(10):
            s += key("-", label="vol down %d" % i)
        s += [("keys", "12")] + held("0", 1.0, "vol default")
        for v in (0, 1, 9, 12):
            s += [("poke", "cfg_def_volume", v)] + held("0", 1.0, "vol default %d" % v)
        s += key("+") + key("+") + key("+")
        s += script("K", "audio dst 1") + script("KK", "audio dst 0") + script("KKK", "audio dst 0 again")
        s += script("T", "mute selective")
        self.diff(s)

    # ---- monitor, duplex, scanner, star

    def test_monitor(self):
        s = BOOT + enter("433500")
        s += key("B", label="forced open") + key("B", label="toggled closed")
        s += held("B", 0.6, "long monitor")
        s += key("B", label="forced") + held("B", 0.6, "long while forced")
        s += enter("434700") + held("B", 0.6, "duplex: listens on input")
        s += key("B", label="duplex short") + key("B", label="duplex short again")
        self.diff(s)

    def test_duplex_key(self):
        s = BOOT + memory(12, 433300, 431700) + enter("434700")
        s += key("R", label="R no digits") + key("R") + key("R") + key("R")
        s += [("keys", "5")] + key("R", label="R one digit")
        # a split from memory 12 takes its RX (not TX); negative shifts
        # whose low byte(s) carry (256, 65536)
        for digits, secs in (("16", 0.5), ("16", 1.7), ("16", 2.7), ("433100", 3.7),
                             ("12", 3.7), ("4350", 3.7), ("600", 1.7), ("256", 1.7),
                             ("65536", 1.7)):
            s += [("keys", digits)] + held("R", secs, "R %s %.1f" % (digits, secs))
            s += key("#", label="after R")
        self.diff(s)

    def test_scanner_key(self):
        s = BOOT + enter("433500")
        s += held("S", 1.7, "reject") + enter("433525") + held("S", 1.7, "reject 2")
        s += enter("433500") + held("S", 2.7, "cleared")
        # while scanning only probes: the C scanner steps at another speed
        # (test_scan_diff.py); stopping returns to the last VIP
        scanning = [("probe", "scanning", lambda r: (r.peek16("scan_mask"), r.peek("scan_on")))]
        s += [("key_down", "S"), ("run", 0.5)] + at("start held") + [("key_up",), ("run", 0.4)]
        s += scanning + key("#", label="stopped")
        s += [("keys", "1"), ("key_down", "S"), ("run", 0.5)] + at("start with mask held")
        s += [("key_up",), ("run", 0.4)] + scanning + [("press", "3"), ("run", 0.3)] + scanning
        s += key("#", label="stopped")
        self.diff(s, ignore=("SYNTH", "rx_loads", "tx_loads", "ctrl_loads"))

    def test_star(self):
        s = BOOT + enter("433500") + held("*", 0.6, "beep 1750")
        s += [("keys", "1234")] + key("*", label="call packet") + [("run", 1.0)] + at("sent")
        s += [("keys", "5")] + key("*", label="call packet, one digit") + [("run", 1.0)] + at("sent 1")
        s += [("poke", "cfg_tx_band_start", f24(440000))] + held("*", 0.6, "beep refused")
        self.diff(s)

    # ---- menu letters

    def test_menu_letters(self):
        s = BOOT + key("E", label="menu")
        for d, secs in (("2", 0.8), ("2", 2.1), ("2", 3.1), ("2", 4.1), ("9", 5.1), ("0", 0.8),
                        ("0", 3.1), ("0", 6.1), ("0", 9.1), ("1", 0.8), ("5", 0.8)):
            s += held(d, secs, "letter %s %.1f" % (d, secs), mid=False)
        s += key("C", label="erased") + keys("1234567890", label="digits")
        s += held("7", 0.8, "letter at 15", mid=False) + held("8", 0.8, "letter at 16", mid=False)
        s += held("8", 0.8, "full", mid=False) + held("C", 0.8, "cleared", mid=False) + key("E", label="menu left")
        self.diff(s)

    # ---- other handsets and cards

    def test_cu58af(self):
        s = BOOT + memory(3, 433300) + enter("433525") + enter("3")
        s += [("keys", "16")] + held("R", 2.7, "shift pos")
        s += held("S", 2.7, "cleared") + key("2", 0.65, "up") + held("7", 2.1, "stored")
        s += [("keys", "8")] + held("#", 3.7, "store hidden") + key("#") + key("#")
        s += key("+") + key("-") + key("B") + key("B")
        # key releases are seen once per display refresh, 25 ms on this
        # handset: 30 ms as in test_aprs_diff
        self.diff(s, cu=CU58AF, tolerance_s=0.03)

    def test_p8n(self):
        s = BOOT + memory(3, 433300) + enter("433525") + enter("3")
        s += [("keys", "25")] + held("#", 1.7, "store") + key("5", 0.65, "down")
        s += key("#") + key("#") + [("keys", "16")] + held("R", 1.7, "shift neg")
        s += held("B", 0.6, "monitor") + key("+") + held("0", 1.0, "vol default")
        self.diff(s, card=P8N)


if __name__ == "__main__":
    unittest.main()
