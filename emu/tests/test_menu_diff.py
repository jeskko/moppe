"""
Setup menu engine: differential scenarios for the C port (c/menu.c, bank
1), asm build vs C build.  The records, TAB/STR tables and band defaults
stay assembler data; what the engine does with them is compared here:
every record drawn (both handsets, seeded values of every type, out of
range TAB indexes, full-length strings), each type's up/down/enter/
default, positioning by digits, group walking and wrap, the remote
display override, decoder histories, memory CTCSS, GPIO and external
serial side effects, the ENT safety delay, the RST records (SAnE per
synth card, ALLrSt, CH rSt, rFcrSt, rFcFIL, rEboot), CFGSnd/CFGGEt and
remote config of every type.  The probe compares the menu position as a
record index (the record addresses differ between the builds).

    R58_MENU_REF_ROM / R58_MENU_REF_LST    reference (default build/)
    R58_MENU_CAND_ROM / R58_MENU_CAND_LST  candidate (default build-c/)
"""
import os
import random
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from difftest import run_diff  # noqa: E402
from test_radio import make_sane_nv  # noqa: E402
from r58emu import Radio, P8E, P8N, CU53AN, CU58AF, load_symbols  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FW = os.path.join(ROOT, "firmware")
REF = (os.environ.get("R58_MENU_REF_ROM", os.path.join(FW, "build", "r58.bin")),
       os.environ.get("R58_MENU_REF_LST", os.path.join(FW, "build", "r58.map")))
CAND = (os.environ.get("R58_MENU_CAND_ROM", os.path.join(FW, "build-c", "r58.bin")),
        os.environ.get("R58_MENU_CAND_LST", os.path.join(FW, "build-c", "r58.map")))

EOS = 0xFF
SIZE_REC = 16


def parse_records():
    """The REC() lines of r58.s in order: dicts with group (menu_N),
    idx (record in the group), tag, title, type, ptr, arg, default."""
    src = open(os.path.join(FW, "r58.s"), encoding="latin-1").read().split("\n")
    a = next(i for i, l in enumerate(src) if l.startswith("start_menu:"))
    b = next(i for i, l in enumerate(src) if l.startswith("end_menu:"))
    recs, skip, group, idx = [], False, -1, 0
    for line in src[a:b]:
        s = line.strip()
        if s.startswith("#if 0"):
            skip = True
        elif s.startswith("#endif"):
            skip = False
        elif skip:
            continue
        m = re.match(r"menu_(\d):", s)
        if m:
            group, idx = int(m.group(1)), 0
            continue
        m = re.match(r'REC\("(..)",\s*"(.{6})",\s*CFG_(\w+),\s*(\w+),\s*(\w+),\s*(-?\d+)', s)
        if m:
            recs.append(dict(group=group, idx=idx, tag=m.group(1), title=m.group(2),
                             type=m.group(3), ptr=m.group(4), arg=m.group(5),
                             default=int(m.group(6))))
            idx += 1
    return recs


RECS = parse_records()


def rec(tag, title):
    return next(r for r in RECS if r["tag"] == tag and r["title"].rstrip() == title)


def pos(r):
    """digits for toggle_or_position_menu: group * 100 + record"""
    return "%d%02d" % (r["group"], r["idx"])


def menu_index(r):
    d = r.peek16("menu_ptr") - r.addr("start_menu")
    return d // SIZE_REC if d % SIZE_REC == 0 else ("odd", d)


FINGERS = ("ccir_hist_finger", "dtmf_hist_finger", "fsk_hist_finger", "gps_hist_finger")


def probe(r):
    return (menu_index(r), r.peek("menu_active"), r.peek("digidx"), r.peek("rfc"),
            tuple(r.peek(f) for f in FINGERS), r.peek("mem_ctcss_tx_hz"),
            r.peek("mem_ctcss_rx_hz"), r.peek("remote_display_buffer", 10),
            r.peek("cfg_squelch_level"), r.peek("cfg_squelch_BIG"),
            r.latches()["pio_b"] & 0x50, r.powered)


def at(label):
    return [("check", label), ("probe", label, probe)]


def keys(k, label=None, hold=0.15):
    """type k (the last key pressed is the action), then compare"""
    return [("keys", k[:-1]), ("press", k[-1], hold), ("run", 0.2)] + at(label or k)


def goto(r, label=None):
    return [("keys", pos(r)), ("press", "E"), ("run", 0.2)] + at(label or "at %s:%s" % (r["tag"], r["title"]))


# Records whose variables change what the radio does outside the menu
# (scanning, idle functions, serial output, TX, squelch, lights): the walk
# shows them at their SAnE values instead of poking random ones.
NO_POKE_GROUPS = {"GE", "Sq", "Fn", "PH", "dF", "St", "rF", "dH", "to"}
NO_POKE = {"cfg_mbus_mprs", "cfg_gps_upload", "cfg_gps_dst_send", "cfg_bus_rf_relay",
           "cfg_spontaneous_mprs", "cfg_keyup_mprs", "cfg_fsk_silencer",
           "remote_display_buffer", "locator_display_buffer", "distance_bearing"}
STR_CHARS = b"0123456789AbCdEFHJLnoPrStUy-_ "


def seeded_pokes(seed):
    rnd = random.Random(seed)
    out = []
    for r in RECS:
        if r["tag"] in NO_POKE_GROUPS or r["ptr"] in NO_POKE:
            continue
        t = r["type"]
        if t in ("BYTE", "cSEC"):
            v = bytes([rnd.choice([0, 1, 9, 10, 99, 100, 255, rnd.randrange(256)])])
        elif t == "WORD":
            v = rnd.choice([0, 1, 9999, 10000, 65535, rnd.randrange(65536)]).to_bytes(2, "little")
        elif t in ("FREQ", "DPX"):
            v = rnd.choice([0, 1, 999999, 1000000, 0xFFFFFF, 0x800000, 0x7FFFFF,
                            rnd.randrange(1 << 24)]).to_bytes(3, "little")
        elif t == "TAB":
            v = bytes([rnd.randrange(18)])          # some past the table end: "???"
        elif t == "STR":
            n = rnd.choice([0, 1, 5, 7, 8])
            v = bytes(rnd.choice(STR_CHARS) for _ in range(n)) + bytes([EOS] * (8 - n))
        else:
            continue
        out.append(("poke", r["ptr"], v))
    # RAM-only records of the GP group, and the histories
    out += [("poke", "gps_utc", b"123456\xff\xff"), ("poke", "gps_date", b"280926\xff\xff"),
            ("poke", "gps_speed", 77), ("poke", "gps_knots", b"\x39\x30"),
            ("poke", "gps_course", b"\x67\x01"), ("poke", "gps_status", b"A\xff" + b"\xff" * 6)]
    for h in ("ccir_history", "dtmf_history", "fsk_history", "gps_history"):
        out.append(("poke", h, bytes(rnd.randrange(16) for _ in range(256))))
    return out


def walk(seed):
    n = len(RECS)
    steps = [("boot", 2.5)] + seeded_pokes(seed) + [("run", 0.2), ("press", "E"), ("run", 0.2)]
    steps += at("menu entered")
    for i in range(n + 1):
        steps += [("press", "#", 0.12, 0.1)] + at("walk %d" % (i + 1))
    for i in range(3):
        steps += [("press", "R", 0.12, 0.1)] + at("back %d" % (i + 1))
    for i in range(len({r["tag"] for r in RECS}) + 2):
        steps += [("press", "S", 0.12, 0.1)] + at("group %d" % (i + 1))
    steps += [("press", "E"), ("run", 0.3)] + at("menu left")
    return steps


class MenuDiff(unittest.TestCase):
    def diff(self, scenario, card=P8E, cu=CU53AN, synth_card=None, **kw):
        nv = make_sane_nv(card, cu, synth_card)
        diffs = run_diff(scenario, REF, CAND, card=card, cu=cu, nv=nv, **kw)
        self.assertEqual(diffs, [], "\n".join(diffs[:40]))

    def test_records_parsed(self):
        sym = load_symbols(REF[1])
        self.assertEqual(len(RECS), (sym["end_menu"] - sym["start_menu"]) // SIZE_REC)

    # ---- drawing

    def test_walk_cu53an(self):
        self.diff(walk(1))

    def test_walk_cu58af(self):
        self.diff(walk(2), cu=CU58AF)

    def test_walk_p8n(self):
        self.diff(walk(3), card=P8N)

    def test_remote_display_override(self):
        """display_buffer_time set: every type draws remote_display_buffer
        (DYN records their own remote pair); '+' then edits that buffer."""
        steps = [("boot", 2.5)]
        for t in ("BYTE", "WORD", "FREQ", "TAB", "DYN", "RST", "STR", "DPX", "cSEC"):
            r = next(x for x in RECS if x["type"] == t)
            steps += goto(r)
            steps += [("poke", "remote_display_buffer", bytes([3, 0x41, 0x42, 0x43, 0x44, 0x45, EOS, 0, 0, 0])),
                      ("poke", "display_buffer_time", 5), ("run", 0.3)] + at("remote %s" % t)
            steps += [("press", "+"), ("run", 0.2)] + at("remote %s +" % t)
            steps += [("poke", "display_buffer_time", 0), ("run", 0.3)] + at("remote %s off" % t)
        for cu in (CU53AN, CU58AF):
            self.diff(steps, cu=cu)

    # ---- editing, one record type at a time

    def edit(self, r, ops, **kw):
        steps = [("boot", 2.5)] + goto(r)
        for op in ops:
            steps += keys(op)
        steps += keys("E", "left")
        self.diff(steps, **kw)

    def test_byte(self):
        self.edit(rec("rJ", "n tEmP"), ["+", "+", "-", "-", "-", "300#", "256#", "7#", "*",
                                         "0#", "255#", "+", "*"])

    def test_csec(self):
        # cSEC drops the last digit typed (notes/open-bugs.md)
        self.edit(rec("SC", "rAtE"), ["150#", "5#", "12#", "2550#", "9999#", "+", "-", "-", "*"])

    def test_word(self):
        self.edit(rec("Pr", "SndInt"), ["+", "-", "-", "0#", "-", "+", "65535#", "65536#",
                                        "123456#", "12#", "*"])

    def test_external_serial_word(self):
        for title in ("SErCtA", "SErCtB"):
            self.edit(rec("PH", title), ["4660#", "+", "-", "0#", "-", "*"])

    def test_freq(self):
        self.edit(rec("b1", "StArt"), ["+", "+", "-", "433450#", "99999999#", "16777215#",
                                       "+", "0#", "-", "*"])

    def test_freq_step_s8b(self):
        self.edit(rec("b1", "End"), ["+", "-", "-", "*"], synth_card=2)

    def test_dpx(self):
        self.edit(rec("b1", "duPL"), ["600#", "+", "600#", "-", "-", "0#", "+", "1600#", "*",
                                      "8388608#", "+"])

    def test_tab(self):
        self.edit(rec("Pr", "ObJECt"), ["-", "-", "+", "+", "15#", "+", "20#", "3#", "-", "*"])

    def test_tab_blip_default(self):
        self.edit(rec("GE", "Loud"), ["5#", "*", "+", "-", "-"])

    def test_tab_gpio(self):
        for title in ("GPio 1", "GPio 2"):
            self.edit(rec("GE", title), ["1#", "+", "+", "-", "3#", "2#", "0#", "-", "*"])

    def test_str(self):
        # long digits are letters (insdig_alpha), long 0 punctuation
        r = rec("AL", "id   1")
        steps = [("boot", 2.5)] + goto(r)
        steps += keys("12345#") + keys("123456789#") + keys("1#")
        steps += [("press", "2", 0.7), ("press", "3", 0.7), ("press", "0", 0.7),
                  ("press", "#"), ("run", 0.2)] + at("alpha")
        steps += keys("*") + keys("+") + keys("-")
        steps += keys("12345678#") + keys("E", "left")
        self.diff(steps)
        self.diff(steps, cu=CU58AF)

    def test_dyn_squelch(self):
        steps = [("boot", 2.5), ("adc", "AD_SQL", 0x55), ("adc", "AD_RSSI", 0x66)]
        for title in ("SqL", "SqL bi"):
            steps += goto(rec("Sq", title))
            for op in ("+", "+", "-", "50#", "300#", "*", "-", "0#", "-"):
                steps += keys(op, "%s %s" % (title, op))
        steps += keys("E", "left")
        self.diff(steps)

    def test_dyn_rfc(self):
        steps = [("boot", 2.5), ("keys", "433500"), ("press", "#"), ("run", 0.3),
                 ("adc", "AD_RSSI", 0x44)]
        steps += goto(rec("rF", "rFc"))
        for op in ("+", "+", "-", "33#", "-", "0#", "-", "+", "300#", "*"):
            steps += keys(op)
        steps += keys("E", "left")
        self.diff(steps)

    def test_dyn_histories(self):
        rnd = random.Random(7)
        steps = [("boot", 2.5)]
        for h in ("ccir", "dtmf", "fsk", "gps"):
            steps += [("poke", h + "_history", bytes(rnd.randrange(16) for _ in range(256))),
                      ("poke", h + "_hist_idx", rnd.randrange(256))]
        steps += [("press", "C"), ("run", 0.2)]            # backspace: decoder_hist_rewind
        for title in ("ccir H", "dtmf H", "FSK  H", "GPS  H"):
            steps += goto(rec("dH", title))
            for op in ("+", "+", "-", "-", "-", "5#", "*"):
                steps += keys(op, "%s %s" % (title, op))
            steps += keys("C", "%s rewind" % title)
        steps += keys("E", "left")
        self.diff(steps)
        self.diff(steps, cu=CU58AF)

    def test_rst_without_666(self):
        steps = [("boot", 2.5)]
        for r in RECS:
            if r["type"] == "RST" and r["title"] != "rFcFIL":
                steps += goto(r) + keys("#", "%s no digits" % r["title"])
                steps += goto(r) + keys("665#", "%s 665" % r["title"])
                steps += goto(r) + keys("*", "%s *" % r["title"]) + keys("+") + keys("-")
        self.diff(steps)

    def test_other_defaults(self):
        """'*' on every record that has a default (BYTE, TAB, cSEC, WORD,
        STR reset; FREQ, DPX copy; DYN, RST nothing)"""
        steps = [("boot", 2.5)] + seeded_pokes(11) + [("keys", "433525"), ("press", "#"), ("run", 0.3)]
        steps += goto(RECS[0])
        for i, r in enumerate(RECS):
            if r["type"] in ("RST",) or r["tag"] in ("PH", "Fn", "dF"):
                continue
            steps += goto(r, "at %d" % i) + keys("*", "default %d %s:%s" % (i, r["tag"], r["title"]))
        steps += keys("E", "left")
        self.diff(steps)

    # ---- positioning and walking

    def test_positioning(self):
        steps = [("boot", 2.5)]
        for d in ("5", "57", "0", "00", "09", "90", "123", "824", "999", "9999", "99999", "4999",
                  "12345678", "10", "1"):
            steps += keys(d + "E", "pos %s" % d)
        steps += keys("E", "toggle off") + keys("E", "toggle on") + keys("E", "toggle off")
        steps += keys("3E", "pos from normal")
        # digits typed past the key buffer and letters (long digits)
        steps += [("press", "8", 0.7), ("press", "2", 0.7), ("press", "E"), ("run", 0.2)] + at("pos letters")
        self.diff(steps)

    def test_group_walk_and_wrap(self):
        steps = [("boot", 2.5), ("press", "E"), ("run", 0.2)]
        for op in ("R", "R", "#", "#", "S", "R", "R", "S", "S"):
            steps += keys(op)
        steps += keys("999E", "last") + keys("#", "wrap to first") + keys("R", "wrap to last")
        steps += keys("S", "next group from last")
        self.diff(steps)

    def test_enter_safety_delay(self):
        steps = [("boot", 2.5)]
        for t in (3, 15):
            steps += [("poke", "cfg_enter_time", t)]
            steps += keys("E", "short E %d" % t)
            steps += [("key_down", "E"), ("run", 0.3)] + at("holding %d" % t)
            steps += [("run", 1.5)] + at("held %d" % t)
            steps += [("key_up",), ("run", 0.3)] + at("released %d" % t)
            steps += keys("824E", "position in menu %d" % t)
            steps += keys("E", "leave %d" % t)
            steps += [("keys", "5"), ("key_down", "E"), ("run", 2.0), ("key_up",), ("run", 0.3)]
            steps += at("digits + long E %d" % t)
            steps += keys("E", "leave again %d" % t)
        self.diff(steps)

    def test_memory_ctcss(self):
        """On a memory channel the CTCSS records edit mem_ctcss_*, saved to
        the memory when the menu is left."""
        steps = [("boot", 2.5), ("keys", "433525"), ("press", "#"), ("run", 0.3),
                 ("keys", "12"), ("press", "#", 1.5), ("run", 0.3),
                 ("keys", "12"), ("run", 0.5)] + at("recalled")
        for title in ("CtCSSt", "CtCSSr"):
            steps += goto(rec("GE", title))
            for op in ("+", "+", "5#", "-", "*"):
                steps += keys(op, "%s %s" % (title, op))
        steps += keys("E", "left") + keys("433500#", "vfo") + keys("12", "recalled again")
        steps += goto(rec("GE", "CtCSSt")) + keys("E", "left again")
        self.diff(steps)

    # ---- RST records

    def rst(self, title, digits="666", after=1.0, **kw):
        steps = [("boot", 2.5)] + seeded_pokes(5)
        steps += [("keys", "433525"), ("press", "#"), ("run", 0.3), ("keys", "3"),
                  ("press", "#", 1.5), ("run", 0.3), ("keys", "433500"), ("press", "#"),
                  ("run", 0.3), ("poke", "rfctab", bytes([0, 40, 0, 0, 50] + [0] * 95))]
        steps += goto(rec("dF", title))
        steps += [("keys", digits), ("press", "#"), ("run", after)] + at("%s done" % title)
        return steps

    def test_sane_each_synth_card(self):
        for card in (0, 1, 2):
            steps = self.rst("SAnE")
            steps[1:1] = [("poke", "cfg_synth_card", card)]
            steps += [("reboot", 0.5, 2.5)] + at("after reboot")
            self.diff(steps)

    def test_allrst(self):
        self.diff(self.rst("ALLrSt") + [("reboot", 0.5, 2.5)] + at("after reboot"))

    def test_wipes(self):
        for title in ("CH rSt", "rFcrSt", "rFcFIL"):
            self.diff(self.rst(title) + keys("E", "left") + keys("3", "memory 3"))

    def test_reboot(self):
        """rEboot with 666 stops in a loop until the watchdog resets.  The
        WDRESET event carries the PC (different names in the builds), so
        this one is compared by hand."""
        results = []
        for rom, lst in (REF, CAND):
            r = Radio(rom, lst, card=P8E, cu=CU53AN, nv=make_sane_nv(P8E, CU53AN))
            r.run(2.5)
            r.type(pos(rec("dF", "rEboot")))
            r.press("E")
            r.run(0.2)
            r.type("666")
            r.take_events()
            r.press("#")
            r.run(3.0)
            ev = [e[1] for e in r.take_events()]
            results.append((ev.count("WDRESET"), r.display(), r.peek("menu_active")))
        self.assertEqual(results[0], results[1])
        self.assertEqual(results[0][0], 1)

    # ---- MBUS configuration dump and load

    def test_cfgsnd(self):
        """The dump is compared as one byte stream (a byte near a
        checkpoint would fall on either side of it), and its end time."""
        results = []
        for rom, lst in (REF, CAND):
            r = Radio(rom, lst, card=P8E, cu=CU53AN, nv=make_sane_nv(P8E, CU53AN))
            r.run(2.5)
            for _, name, v in seeded_pokes(9):
                r.poke(name, v)
            r.type(pos(rec("dF", "CFGSnd")))
            r.press("E")
            r.run(0.2)
            r.type("666")
            r.take_events()
            r.press("#")
            out = []
            for _ in range(12):
                r.run(0.4)
                out += r.take_events("MBUS_TX")
            results.append((bytes(e[2] for e in out), out[-1][0], r.display(), r.nv()))
        (a, ta, da, na), (b, tb, db, nb) = results
        self.assertEqual(len(a) - a.index(b"\n") - 1, 2 + 0x1000 + 1)
        self.assertEqual(a, b)
        self.assertLess(abs(ta - tb), 0.05)
        self.assertEqual((da, na), (db, nb))

    def cfgget(self, img):
        steps = [("boot", 2.5)] + goto(rec("dF", "CFGGEt"))
        steps += [("keys", "666"), ("press", "#"), ("run", 0.3)] + at("ready")
        steps += [("serial_rx", 1, img[:3000]), ("run", 0.5)] + at("loading")
        for i in range(7):
            steps += [("run", 0.5)] + at("receiving %d" % i)
        steps += [("serial_rx", 1, img[3000:])]
        for i in range(4):
            steps += [("run", 0.5)] + at("finishing %d" % i)
        steps += keys("E", "left")
        return steps

    def image(self, seed, bad_sum=False, length=0x1000):
        rnd = random.Random(seed)
        nv = bytearray(make_sane_nv(P8E, CU53AN))
        for i in range(0x100, 0x200):
            nv[i] = rnd.randrange(256)
        body = bytes(nv)
        ck = (-sum(body) + (1 if bad_sum else 0)) & 0xFF
        return b"R58 test image\n" + bytes([length & 0xFF, length >> 8]) + body + bytes([ck])

    def test_cfgget(self):
        self.diff(self.cfgget(self.image(1)))

    def test_cfgget_bad_checksum(self):
        self.diff(self.cfgget(self.image(2, bad_sum=True)))

    def test_cfgget_wrong_length(self):
        self.diff(self.cfgget(self.image(3, length=0x0FFF)))
        self.diff(self.cfgget(self.image(3, length=0x1100)))

    # ---- remote configuration (EC packets) of every record type

    def test_remote_config_every_type(self):
        from test_fsk import with_crc, REMOTE_ID, PASSWD
        sym = load_symbols(REF[1])

        def ec(ptr, digits):
            data = bytes(digits) + b"\xFF" * (8 - len(digits))
            return with_crc(bytes([0xEC]) + REMOTE_ID + bytes([ptr & 0xFF, ptr >> 8]) + data, PASSWD)

        steps = [("boot", 2.5), ("poke", "cfg_remote_id", REMOTE_ID),
                 ("poke", "cfg_remote_passwd", PASSWD), ("poke", "cfg_remote_dpy_secs", 5),
                 ("keys", "433500"), ("press", "#"), ("run", 0.3)]
        cases = [("cfg_remote_dpy_secs", [1, 2]), ("cfg_mprs_seconds", [6, 0, 0]),
                 ("cfg_mprs_seconds", [7, 0, 0, 0, 0]), ("cfg_band1_start", [4, 3, 3, 4, 5, 0]),
                 ("cfg_mprs_symbol", [3]), ("cfg_mprs_symbol", [9, 9]),
                 ("cfg_gpio1_state", [1]), ("cfg_mycall_1", [1, 2, 3]),
                 ("cfg_mycall_1", [1, 2, 3, 4, 5, 6, 7, 8]), ("cfg_band1_duplex", [6, 0, 0]),
                 ("cfg_scan_rate_kvik", [1, 5, 0]), ("cfg_external_serial_A", [9, 9]),
                 ("cfg_mprs_callsign", [])]
        for name, digits in cases:
            steps += [("modem_rx", ec(sym[name], digits)), ("run", 1.2)]
            steps += at("remote %s %r" % (name, digits))
        for special, digits in ((0, [1]), (1, [5, 0]), (2, [6, 6]), (3, [2, 0, 0]), (4, [1]),
                                (0xC000 + 0xFFF, [1])):
            steps += [("modem_rx", ec(special, digits)), ("run", 1.2)]
            steps += at("remote special 0x%x" % special)
        # in the menu: the remote config moves menu_ptr to the record
        steps += [("press", "E"), ("run", 0.2), ("modem_rx", ec(sym["cfg_band2_end"], [4, 3, 5])),
                  ("run", 1.2)] + at("remote in menu") + keys("#", "walk on") + keys("E", "left")
        self.diff(steps)


if __name__ == "__main__":
    unittest.main()
