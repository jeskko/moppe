"""
The R40 ham firmware (r40/, notes/r40-firmware.md) on moppe-emu's R40
emulator.  The module builds r40/build/r40.bin with `make -C r40` when
the H8/500 toolchain is built (tools/h8500/lcc/build.sh); without the
toolchain it uses an existing image, or skips.
"""
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, os.path.join(ROOT, "emu", "python"))

from r40emu import Radio  # noqa: E402

ROM = os.path.join(ROOT, "r40", "build", "r40.bin")
MAP = os.path.join(ROOT, "r40", "build", "r40.map")
RCC = os.path.join(ROOT, "reference", "toolchain", "lcc", "build", "rcc")


def setUpModule():
    if os.path.exists(RCC):
        p = subprocess.run(["make", "-s", "-C", os.path.join(ROOT, "r40")],
                           capture_output=True, text=True)
        if p.returncode:
            raise RuntimeError("make -C r40 failed:\n" + p.stdout + p.stderr)
    elif not os.path.exists(ROM):
        raise unittest.SkipTest("no H8/500 toolchain and no r40/build/r40.bin")


def faults(r):
    return [e for e in r.events if e[1] in ("ILLEGAL", "EXC")]


def symbol(name):
    """a C function's address from the map (COFF drops the underscore)"""
    m = re.search(r"^\s+0x([0-9a-f]+)\s+%s$" % name, open(MAP).read(), re.M)
    return int(m.group(1), 16)


def booted():
    r = Radio(ROM)
    r.run(1.0)
    return r


class Boot(unittest.TestCase):
    def test_hello(self):
        # the top row's gaps (cells 2, 9, ...) are skipped: "R40 ham"
        # reads back whole only if the firmware maps them as display() does
        r = Radio(ROM)
        r.run(1.5)
        self.assertEqual(r.display()[:2], ["R40 ham", "Hello, world"])
        self.assertEqual(faults(r), [])

    def test_tick_and_watchdog(self):
        # the seconds counter comes from the 100 Hz FRT1 tick; a watchdog
        # NMI would restart the firmware and the count
        r = Radio(ROM)
        r.run(10.5)
        self.assertEqual(r.display()[2], "10")
        self.assertEqual(r.peek(0xFFEC) & 0x60, 0x60)    # WDT: watchdog mode, on
        self.assertEqual(faults(r), [])

    def test_watchdog_bites_without_kicks(self):
        # the main loop's jsr @_wdog_kick removed: the WDT (130 ms) restarts
        # the firmware through NMI, again and again
        rom = bytearray(open(ROM, "rb").read())
        kick = symbol("wdog_kick").to_bytes(2, "big")
        i = rom.find(b"\x18" + kick, symbol("main"))
        rom[i:i + 3] = bytes(3)
        with tempfile.NamedTemporaryFile(suffix=".bin") as f:
            f.write(rom)
            f.flush()
            r = Radio(f.name)
        r.run(0.01)
        r.breakpoint(symbol("reset"))
        starts = []
        for _ in range(3):
            self.assertEqual(r.run(2.0), "break")
            starts.append(r.time())
            r.step()
        self.assertLess(starts[-1], 2.0)

    def test_latches_and_lcd_set_up(self):
        r = Radio(ROM)
        r.run(0.5)
        self.assertEqual(r.out(0), 0x05)
        self.assertEqual(r.out(1) & 1, 0)                 # TX off
        first = r.i2c_log()[0][1]
        self.assertEqual(first, bytes([0x78, 0xD7, 0x7C]))


class Keypad(unittest.TestCase):
    def test_every_known_key(self):
        r = booted()
        for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#",
                  "OK", "CLR", "FNC", "RCL", "UP", "DOWN"]:
            r.press(k)
            self.assertEqual(r.display()[2][8:], "Key " + k, k)
        self.assertEqual(faults(r), [])

    def test_long_then_quick_presses(self):
        r = booted()
        r.press("7", hold=1.0)
        r.press("8", hold=0.05, gap=0.05)
        r.press("9", hold=0.05, gap=0.3)
        self.assertEqual(r.display()[2][8:], "Key 9")

    def test_volume_keys(self):
        # UP / DOWN set the volume (IC40 bits 6-4) for now
        r = booted()
        self.assertEqual(r.sreg(1), 0x30)
        r.press("UP")
        r.press("UP")
        self.assertEqual((r.display()[1][14:], r.sreg(1)), ("Vol 5", 0x50))
        r.press("DOWN")
        self.assertEqual((r.display()[1][14:], r.sreg(1)), ("Vol 4", 0x40))


def pwr(r, hold=0.3, gap=0.5):
    r.power_key(True)
    r.run(hold)
    r.power_key(False)
    r.run(gap)


class Power(unittest.TestCase):
    def test_audio_switches_at_boot(self):
        # the Nokia firmware's receive state with the squelch closed: mic
        # and receiver audio muted, spacing gain; volume 3, amplifier off;
        # deviation bits 0111
        r = booted()
        self.assertEqual([r.sreg(i) for i in range(3)], [0x0B, 0x30, 0x07])

    def test_pwr_held_at_power_on_is_not_a_press(self):
        r = Radio(ROM, power=False)
        r.power_key(True)
        r.power(True)
        r.run(1.0)
        r.power_key(False)
        r.run(0.5)
        self.assertEqual(r.display()[0], "R40 ham")
        self.assertEqual(r.take_events("POWEROFF"), [])

    def test_pwr_switches_off_and_on(self):
        # IC39 bit 2 cuts the supply; if it stays on (ignition), PWR
        # starts the firmware again
        r = booted()
        pwr(r)
        self.assertEqual(len(r.take_events("POWEROFF")), 1)
        self.assertEqual(r.sreg(0) & 0x07, 0x07)     # off, mic and audio muted
        self.assertEqual(r.display(), ["", "", ""])
        r.press("5")
        self.assertEqual(r.display(), ["", "", ""])
        pwr(r, gap=1.5)
        self.assertEqual(r.display()[0], "R40 ham")
        self.assertEqual(r.sreg(0), 0x0B)
        self.assertEqual(faults(r), [])

if __name__ == "__main__":
    unittest.main()
