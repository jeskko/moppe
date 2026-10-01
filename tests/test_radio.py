"""
Firmware-level scenario tests for the R58 emulator.

Run from the repository root:
    make -C firmware && make -C emu && python3 -m unittest discover -s tests -v

Expected values (synth R/N/A, display strings) were derived independently
from the firmware source (notes/reference/firmware-rf-ui.md), not from emulator runs.
Each test starts from an NV image produced by running the firmware's own
SAnE defaults procedure, cached in tests/.cache/.
"""
import os
import sys
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "emu", "python"))

from r58emu import Radio, P8E, P8N, CU53AN, CU58AF, AD_SQL  # noqa: E402

ROM = os.environ.get("R58_ROM", os.path.join(ROOT, "firmware", "build", "r58.bin"))
LST = os.environ.get("R58_LST", os.path.join(ROOT, "firmware", "build", "r58.map"))
CACHE = os.environ.get("R58_NV_CACHE", os.path.join(os.path.dirname(__file__), ".cache"))


def make_sane_nv(card=P8E, cu=CU53AN, synth_card=None):
    """Zeroed NV -> dF:SAnE (828 E, 666 #) -> power cycle, as a user would."""
    tag = "sane-%d-%d-%s" % (card, cu, synth_card)
    path = os.path.join(CACHE, tag + ".nv")
    if os.path.exists(path) and os.path.getmtime(path) > os.path.getmtime(ROM):
        with open(path, "rb") as f:
            return f.read()
    r = Radio(ROM, LST, card=card, cu=cu)
    if synth_card is not None:
        r.poke("cfg_synth_card", synth_card)
    # zeroed hook scripts would "type" eight 0 digits after the boot-time
    # hook edge; blank them (EOS) as the setup checklist advises
    r.poke("cfg_onhook_script", b"\xff" * 8)
    r.poke("cfg_offhook_script", b"\xff" * 8)
    r.run(2.5)
    r.type("828")
    r.press("E")
    r.run(0.3)
    r.type("666")
    r.press("#")
    r.run(1.0)
    assert not r.powered, "SAnE should power the radio down"
    r.power(False)
    r.run(0.1)
    os.makedirs(CACHE, exist_ok=True)
    nv = r.nv()
    with open(path + ".%d" % os.getpid(), "wb") as f:
        f.write(nv)
    os.replace(path + ".%d" % os.getpid(), path)    # atomic for parallel runs
    return nv


class RadioTest(unittest.TestCase):
    card = P8E
    cu = CU53AN
    synth_card = None
    prescaler = 128
    if_hz = 86.5125e6

    def boot(self, nv=None, seconds=2.5, **kw):
        if nv is None:
            nv = make_sane_nv(self.card, self.cu, self.synth_card)
        r = Radio(ROM, LST, card=self.card, cu=self.cu, nv=nv,
                  prescaler=self.prescaler, if_hz=self.if_hz, **kw)
        r.run(seconds)
        self.r = r
        return r

    def tearDown(self):
        r = getattr(self, "r", None)
        if r is not None:
            wd = [e for e in r.events if e[1] == "WDRESET"]
            self.assertEqual(wd, [], "watchdog reset during test")

    # --- helpers
    def glyphs(self, s):
        """7-segment glyph bytes for string s, via the ROM's font."""
        font = self.r.peek("cu53an_font", 128)
        return [font[ord(c) & 0x7f] for c in s]

    def assertLower(self, expect):
        up, lo = self.r.display()
        if self.cu == CU53AN:
            self.assertEqual(self.r.glyphs()[1], self.glyphs(expect),
                             "lower row %r, expected %r" % (lo, expect))
        else:
            self.assertEqual(lo, expect)

    def assertUpper(self, expect):
        up, lo = self.r.display()
        if self.cu == CU53AN:
            self.assertEqual(self.r.glyphs()[0], self.glyphs(expect),
                             "upper row %r, expected %r" % (up, expect))
        else:
            self.assertEqual(up, expect)

    def assertRx(self, n, a, r=1024):
        s = self.r.synth()
        self.assertEqual((s["rx_r"], s["rx_n"], s["rx_a"]), (r, n, a))

    def assertTx(self, n, a, r=1024):
        s = self.r.synth()
        self.assertEqual((s["tx_r"], s["tx_n"], s["tx_a"]), (r, n, a))

    def enter(self, digits):
        self.r.type(digits)
        self.r.press("#")
        self.r.run(0.3)


class Boot(RadioTest):
    def test_detects_p8e_and_cu53(self):
        r = self.boot()
        self.assertEqual(r.peek("cpu_is_P8E"), 1)
        self.assertEqual(r.peek("cu_is_alfa"), 0)

    def test_boot_frames(self):
        nv = bytearray(make_sane_nv())
        r = Radio(ROM, LST, nv=bytes(nv))
        r.poke24("rx_freq", 433500)
        r.poke24("tx_freq", 433500)
        r.run(2.5)
        self.r = r
        s = r.synth()
        self.assertRx(325, 1)
        self.assertEqual(s["tx_loads"], 0)
        self.assertEqual(s["ctrl"], 0xF7)
        L = r.latches()
        self.assertEqual(L["out1"], 0x80)
        self.assertEqual(L["da_txpwr"], 0)
        self.assertAlmostEqual(r.rx_hz(), 433.5e6, places=0)
        self.assertLower("    433500")
        self.assertTrue({"COLON_UL", "COLON_UR"} <= r.icons())

    def test_no_watchdog_for_10s(self):
        r = self.boot(seconds=10)
        # the firmware clock starts after the ~2 s boot
        self.assertGreaterEqual(r.peek("seconds") + 60 * r.peek("minutes"), 7)


class Frequency(RadioTest):
    def test_absolute_entry(self):
        r = self.boot()
        r.type("433525")
        self.assertLower("433525_   ")
        r.press("#")
        r.run(0.3)
        self.assertRx(325, 3)
        self.assertLower("    433525")

    def test_implied_entry(self):
        r = self.boot()
        self.enter("500")
        self.assertRx(325, 1)
        self.assertLower("    433500")
        self.enter("4500")
        self.assertRx(325, 81)
        self.assertLower("    434500")
        self.assertFalse({"V_D", "V_U"} & r.icons())

    def test_step_up_down(self):
        r = self.boot()
        self.enter("433500")
        r.press("3", hold=0.65)          # one 0x83 at 0.5 s
        r.run(0.3)
        self.assertLower("    433525")
        self.enter("433500")
        r.press("6", hold=0.65)
        r.run(0.3)
        self.assertLower("    433475")
        self.assertRx(324, 127)

    def test_memory_store_recall(self):
        r = self.boot()
        self.enter("433525")
        r.type("12")
        r.press("#", hold=1.5)
        r.run(0.3)
        self.assertLower("12  433525")
        self.enter("433500")
        self.assertLower("    433500")
        self.enter("12")
        self.assertLower("12  433525")
        self.assertRx(325, 3)


class TxLowPass(RadioTest):
    """PH:LPFILt (cfg_lpf_hz): init_LPF loads 8254 counter 0 with
    2016 / (Hz / 20), the switched-capacitor filter clock divider. v3_Z
    divided with div248, wrong for divisors of 128 and more: from 2900 Hz
    on some settings loaded 8 (3600 Hz, the default, gave a ~5 kHz cutoff)
    and 5100 Hz loaded 0 (fixed 2026-09-30)."""

    def test_filter_divider(self):
        a = self.boot().addr("cfg_lpf_hz")
        for hz in list(range(2000, 5101, 100)) + [2560, 2580, 5080]:
            with self.subTest(hz=hz):
                nv = bytearray(make_sane_nv(self.card, self.cu, self.synth_card))
                nv[a - 0xC000:a - 0xC000 + 2] = hz.to_bytes(2, "little")
                r = self.boot(nv=bytes(nv))
                self.assertEqual(r.pit(0)["count"], 2016 // (hz // 20))

class Transmit(RadioTest):
    def test_simplex_tx(self):
        r = self.boot()
        self.enter("433500")
        r.ptt(True)
        r.run(0.3)
        self.assertTrue(r.transmitting())
        self.assertTx(270, 120)
        self.assertAlmostEqual(r.tx_hz(), 433.5e6, places=0)
        rx_loads = r.synth()["rx_loads"]
        r.ptt(False)
        r.run(0.3)
        self.assertFalse(r.transmitting())
        L = r.latches()
        self.assertEqual(L["da_txpwr"], 0)
        self.assertEqual(r.synth()["ctrl"], 0xF7)
        self.assertEqual(r.synth()["rx_loads"], rx_loads)

    def test_auto_duplex(self):
        r = self.boot()
        self.enter("434700")
        self.assertRx(325, 97)
        self.assertIn("V_D", r.icons())
        r.ptt(True)
        r.run(0.3)
        self.assertTx(270, 88)
        self.assertLower("    433100")
        r.ptt(False)
        r.run(0.3)

    def test_out_of_band_refused(self):
        r = self.boot()
        self.enter("440000")
        r.ptt(True)
        r.run(0.3)
        self.assertFalse(r.transmitting())
        self.assertEqual(r.synth()["tx_loads"], 0)
        self.assertTrue(r.latches()["out0"] & 0x40)       # MTC: local tone
        self.assertAlmostEqual(r.tone_hz(), 300.0, delta=1)
        r.ptt(False)
        r.run(0.3)
        self.assertFalse(r.transmitting())

    def test_band_edge_strict(self):
        r = self.boot()
        self.enter("432000")
        r.ptt(True)
        r.run(0.3)
        self.assertFalse(r.transmitting())
        r.ptt(False)
        r.run(0.2)

    def test_zeroed_nv_never_transmits(self):
        r = self.boot(nv=bytes(4096))
        r.ptt(True)
        r.run(0.5)
        self.assertFalse(r.transmitting())
        r.ptt(False)
        r.run(0.2)


class Setup(RadioTest):
    def test_setup_entry_and_txpwr(self):
        r = self.boot()
        self.enter("433500")
        r.press("E")
        r.run(0.3)
        self.assertEqual(r.peek("menu_active"), 1)
        self.assertUpper("tPc   ")
        self.assertLower("GE       0")
        self.assertIn("COLON_D", r.icons())
        self.enter("200")
        r.press("E")
        r.run(0.3)
        self.assertEqual(r.peek("menu_active"), 0)
        r.ptt(True)
        r.run(0.3)
        self.assertEqual(r.latches()["da_txpwr"], 200)
        r.press("+")
        self.assertEqual(r.latches()["da_txpwr"], 226)
        r.press("-")
        self.assertEqual(r.latches()["da_txpwr"], 200)
        r.ptt(False)
        r.run(0.3)

    def test_quick_positioning(self):
        r = self.boot()
        r.type("8")
        r.press("E")
        r.run(0.3)
        self.assertUpper("SynCrd")
        self.assertLower("PH     S8d")
        r.press("#")
        r.press("#")
        r.run(0.2)
        self.assertUpper("IFFrEq")
        self.assertLower("PH   86512")
        r.press("E")

    def test_volume(self):
        r = self.boot()
        self.assertEqual(r.peek("volume"), 0)
        self.assertTrue(r.latches()["out0"] & 0x08)        # INH at volume 0
        for _ in range(4):
            r.press("+")
        self.assertEqual(r.peek("volume"), 4)
        L = r.latches()
        self.assertEqual(L["out0"] & 0x07, 2)
        self.assertFalse(L["out0"] & 0x08)


class Squelch(RadioTest):
    def test_squelch_opens_on_signal(self):
        r = self.boot()
        # SAnE leaves squelch level 0, which can open but never close
        # (close limit clamps at 0); use a realistic level.
        r.poke("cfg_squelch_level", 127)
        r.run(0.3)
        self.assertFalse(r.latches()["out0"] & 0x10)
        r.adc(AD_SQL, 0xC0)
        r.run(0.5)
        self.assertTrue(r.latches()["out0"] & 0x10, "AUDIOC on")
        self.assertIn(4, [k for k in range(8) if r.peek("indicators") >> k & 1])
        r.adc(AD_SQL, 0)
        r.run(1.0)
        self.assertFalse(r.latches()["out0"] & 0x10)


class HookScripts(RadioTest):
    def test_lift_runs_offhook_script(self):
        """GE:oFFHoo runs when the handset is lifted, GE:onHoo when it is
        put back (PA1 = 1 lifted: assumed, see notes/hardware.md).
        Scripts hold key codes (digits as 0-9, not ASCII)."""
        r = self.boot()
        r.poke("cfg_offhook_script", b"++" + b"\xff" * 6)
        r.poke("cfg_onhook_script", b"-" + b"\xff" * 7)
        v = r.peek("volume")
        r.hook(True)
        r.run(1.0)
        self.assertEqual(r.peek("volume"), v + 2, "lifting ran oFFHoo")
        r.hook(False)
        r.run(1.0)
        self.assertEqual(r.peek("volume"), v + 1, "putting back ran onHoo")


class P8NBoot(RadioTest):
    card = P8N

    def test_detects_p8n(self):
        r = self.boot()
        self.assertEqual(r.peek("cpu_is_P8E"), 0)
        self.enter("433500")
        self.assertRx(325, 1)
        self.assertLower("    433500")

    def test_nv_survives_power_cycle(self):
        r = self.boot()
        self.enter("433525")
        r.type("7")
        r.press("#", hold=1.5)
        r.run(0.3)
        r.power(False)
        r.run(0.5)
        self.assertFalse(r.powered)
        nv = r.nv()
        r2 = Radio(ROM, LST, card=P8N, nv=nv)
        r2.run(2.5)
        self.r = r2
        self.enter("7")
        self.assertLower(" 7  433525")

    def test_nmi_inside_save_keeps_first_nv_byte(self):
        """Switch-off NMI while save_nvdata has the battery RAM mapped in
        (between its two OUT2 writes): the NMI's own copy must still save
        nvstart (audio_dst) from work RAM, not copy the old battery byte
        onto itself."""
        r = self.boot()
        a = r.addr("save_nvdata")
        code = r.peek(a, 64)
        k = code.find(bytes([0xED, 0x51, 0x77, 0xED, 0x59]))  # out (c),d; ld (hl),a; out (c),e
        self.assertGreater(k, 0, "save_nvdata copy loop not found")
        old = r.nv()[0]
        new = 2 if old != 2 else 1
        r.poke("audio_dst", new)
        r.type("433525")
        r.breakpoint(a + k + 2)
        r.key_down("#")             # by hand: press() would run past the stop
        stop = r.run(0.15)
        if stop != "break":
            r.key_up()
            stop = r.run(1.0)
        self.assertEqual(stop, "break")
        self.assertEqual(r.cpu()["hl"], r.addr("nvstart"))
        r.key_up()
        r.breakpoint(a + k + 2, False)
        r.power(False)
        r.run(0.5)
        self.assertFalse(r.powered)
        self.assertEqual(r.nv()[0], new)


class CU58AFBoot(RadioTest):
    cu = CU58AF

    def test_detects_alpha_handset(self):
        r = self.boot()
        self.assertEqual(r.peek("cu_is_alfa"), 1)

    def test_frequency_entry(self):
        r = self.boot()
        self.enter("433500")
        self.assertRx(325, 1)
        up, lo = r.display()
        self.assertIn("433500", lo)

    def test_menu_text(self):
        r = self.boot()
        r.press("E")
        r.run(0.3)
        up, lo = r.display()
        self.assertEqual(r.peek("menu_active"), 1)
        self.assertIn("TPC", up.upper())


if __name__ == "__main__":
    unittest.main()
