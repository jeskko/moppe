"""
Our firmware built for the RB58VY's L8M logic board (make -C r58 l8m,
notes/rb58vy.md) on the emulator's L8M card (emu/notes/r58.md "L8M").

The S8M synthesizer: MC145156, R = 1024 at 12.8 MHz (12.5 kHz), 40/41
prescaler; SAnE gives the 6 m defaults with the 45 MHz IF above.  The NV
data stays in RAM; its essentials go into the EEPROM (r58.s "L8M
EEPROM"): the setup block, VIP/RFC and the first memories in the
background, the state block at power-down, all of it back after a
supply cut.  Here r.nv() is the EEPROM, so a new Radio with nv= and an
empty RAM is a radio whose supply was cut.
"""
import os
import sys
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "emu", "python"))

from r58emu import Radio, L8M, CU53AN  # noqa: E402

ROM = os.path.join(ROOT, "r58", "build-l8m", "r58.bin")
LST = os.path.join(ROOT, "r58", "build-l8m", "r58.map")
CACHE = os.environ.get("R58_NV_CACHE", os.path.join(os.path.dirname(__file__), ".cache"))


def radio(nv=None):
    return Radio(ROM, LST, card=L8M, cu=CU53AN, nv=nv, prescaler=40)


def sane_eeprom():
    """blank EEPROM and RAM -> dF:SAnE (828 E, 666 #): the EEPROM after it"""
    path = os.path.join(CACHE, "sane-l8m.nv")
    if os.path.exists(path) and os.path.getmtime(path) > os.path.getmtime(ROM):
        with open(path, "rb") as f:
            return f.read()
    r = radio()
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
    nv = r.nv()
    os.makedirs(CACHE, exist_ok=True)
    with open(path + ".%d" % os.getpid(), "wb") as f:
        f.write(nv)
    os.replace(path + ".%d" % os.getpid(), path)
    return nv


@unittest.skipUnless(os.path.exists(ROM), "no L8M build (make -C r58 l8m)")
class L8MTest(unittest.TestCase):
    def setUp(self):
        self.sane = sane_eeprom()
        self.r = radio(nv=self.sane)        # empty RAM: restored from the EEPROM
        self.r.run(2.5)

    def tune(self, khz):
        self.r.type(str(khz))
        self.r.press("#")
        self.r.run(0.5)

    def test_boot_from_eeprom(self):
        r = self.r
        self.assertEqual(r.peek16("ram_magic"), 0x5A58)
        self.assertEqual(r.nv()[:4], b"R58\x01")
        self.assertEqual(r.peek("cfg_synth_card"), 2)      # S8B: 6 m defaults
        self.assertFalse(r.take_events("WDRESET"))

    def test_6m_synth_and_tx(self):
        r = self.r
        r.poke("cfg_txpwr", 200)
        self.tune(51000)
        self.assertEqual(r.display()[1].strip(), "51000")
        self.assertAlmostEqual(r.vco_hz(), 96.0e6)          # + 45 MHz IF
        r.take_events()
        r.ptt(1)
        r.run(0.5)
        self.assertTrue(r.take_events("TX_ON"))
        self.assertAlmostEqual(r.vco_hz(tx=True), 51.0e6)
        self.assertEqual(r.latches()["da_txpwr"], 200)
        self.assertFalse(r.latches()["out1"] & 0x88)        # TXOFF, /STE low
        r.ptt(0)
        r.run(0.5)
        self.assertTrue(r.take_events("TX_OFF"))
        self.assertEqual(r.latches()["out1"] & 0x88, 0x88)

    def test_raster_12k5(self):
        self.tune(51230)
        self.assertEqual(self.r.peek24("rx_freq"), 51225)
        self.assertAlmostEqual(self.r.vco_hz(), 96.225e6)

    def test_keys_keep_txoff(self):
        # keypad reads must not take TXOFF (or /STE) out of the latch: a
        # synth load after one used to key the transmitter
        r = self.r
        r.take_events()
        for k in "51100":
            r.press(k)
        r.press("#")
        r.run(1.0)
        self.assertFalse(r.take_events("TX_ON"))
        self.assertEqual(r.latches()["out1"] & 0x88, 0x88)

    def test_setup_menu(self):
        r = self.r
        r.type("828")
        r.press("E")
        r.run(0.3)
        self.assertEqual(r.display()[0], "5AnE  ")          # bank 1 menu

    def test_supply_cut_after_power_off(self):
        r = self.r
        self.tune(51100)
        r.power(False)                       # NMI: state block into the EEPROM
        r.run(2.0)
        self.assertFalse(r.powered)
        r2 = radio(nv=r.nv())
        r2.run(2.5)
        self.assertEqual(r2.peek24("rx_freq"), 51100)
        self.assertAlmostEqual(r2.vco_hz(), 96.1e6)

    def test_background_sync(self):
        r = self.r
        r.poke("cfg_squelch_level", 77)
        mem5 = r.sym["memories"] + 5 * 12
        r.poke(mem5, b"\x01\x02\x03")
        self.tune(51100)
        r.run(5)                             # no power-down
        ee = r.nv()
        r2 = radio(nv=ee)
        r2.run(2.5)
        self.assertEqual(r2.peek("cfg_squelch_level"), 77)
        self.assertEqual(r2.peek(mem5, 3), b"\x01\x02\x03")
        # the state block (frequency etc.) waits for the power-down
        self.assertEqual(ee[4:4 + 0x1E], self.sane[4:4 + 0x1E])
        self.assertNotEqual(r2.peek24("rx_freq"), 51100)

    def test_warm_start_keeps_ram(self):
        r = self.r
        self.tune(51100)
        r.power(False)
        r.run(2.0)
        r.power(True)                        # RAM kept (Vm): no restore
        r.run(2.5)
        self.assertEqual(r.peek24("rx_freq"), 51100)


if __name__ == "__main__":
    unittest.main()
