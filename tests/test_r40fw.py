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
    with open(MAP) as f:
        m = re.search(r"^\s+0x([0-9a-f]+)\s+%s$" % name, f.read(), re.M)
    return int(m.group(1), 16)


def booted():
    r = Radio(ROM)
    r.run(1.0)
    return r


class Boot(unittest.TestCase):
    def test_hello(self):
        # the top row's gaps (cells 2, 9, ...) are skipped: the frequency
        # reads back whole only if the firmware maps them as display() does
        r = Radio(ROM)
        r.run(1.5)
        self.assertEqual(r.display()[:2], ["433.50000", "Vol 3         12.50k"])
        self.assertEqual(faults(r), [])

    def test_watchdog_kept(self):
        # a watchdog NMI would restart the firmware (and reload the PLLs)
        r = Radio(ROM)
        r.run(10.5)
        self.assertEqual(r.pll(0)[4], 2)                 # reference + N/A, once
        self.assertEqual(r.peek(0xFFEC) & 0x60, 0x60)    # WDT: watchdog mode, on
        self.assertEqual(faults(r), [])

    def test_watchdog_bites_without_kicks(self):
        # the main loop's jsr @_wdog_kick removed: the WDT (130 ms) restarts
        # the firmware through NMI, again and again
        with open(ROM, "rb") as f:
            rom = bytearray(f.read())
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


# key codes (r40/keypad.h)
CODES = {"OK": 0x80, "CLR": 0x81, "FNC": 0x82, "RCL": 0x83, "UP": 0x84, "DOWN": 0x85}
CODES.update({c: ord(c) for c in "0123456789*#"})


class Keypad(unittest.TestCase):
    def test_every_known_key_while_held(self):
        r = booted()
        at = symbol("key_down")
        for k, code in CODES.items():
            r.key(k, True)
            r.run(0.15)
            self.assertEqual(r.peek(at), code, k)
            r.key(k, False)
            r.run(0.15)
            self.assertEqual(r.peek(at), 0, k)
        self.assertEqual(faults(r), [])

    def test_digits_long_and_quick_presses(self):
        r = booted()
        r.press("4", hold=1.0)
        for k in "3950625":
            r.press(k, hold=0.05, gap=0.05)
        r.run(0.3)
        self.assertEqual(r.display()[0], "439.50625")
        r.press("CLR")
        self.assertEqual(r.display()[0], "439.5062_")


class Vfo(unittest.TestCase):
    def test_boot_frequency_and_synthesizers(self):
        # the Nokia firmware's words for 433.500 MHz simplex: RX 598/16
        # (478.5 MHz, 45 MHz IF), TX parked 541/122 (+62.5 kHz)
        r = booted()
        self.assertEqual(r.pll(0)[:4], (1024, 0, 598, 16))
        self.assertEqual(r.pll(1)[:4], (1024, 0, 541, 122))

    def test_entry(self):
        r = booted()
        r.type("4381")
        self.assertEqual(r.display()[0], "438.1____")
        r.press("OK")
        self.assertEqual(r.display()[0], "438.10000")
        self.assertEqual((r.pll(0)[-1], r.pll(1)[-1]), (483.1e6, 438.1625e6))
        r.type("43350627")                      # down to the 6.25 kHz raster
        r.press("OK")
        self.assertEqual(r.display()[0], "433.50625")
        r.type("999")                           # out of range: ignored
        r.press("OK")
        self.assertEqual(r.display()[0], "433.50625")

    def test_steps(self):
        r = booted()
        r.press("UP")
        r.press("UP")
        self.assertEqual(r.display()[0], "433.52500")
        r.press("DOWN")
        self.assertEqual(r.display()[0], "433.51250")
        self.assertEqual(r.pll(0)[-1], 478.5125e6)
        self.assertEqual(r.display()[1][14:], "12.50k")

    def test_squelch(self):
        # noise (AN1) below the level opens: RX audio on, amplifier on
        r = booted()
        self.assertEqual((r.sreg(0), r.sreg(1) & 0x08), (0x0B, 0))
        r.set_adc(1, 100)
        r.set_adc(0, 800)
        r.run(0.2)
        self.assertEqual((r.sreg(0), r.sreg(1) & 0x08), (0x09, 0x08))
        self.assertEqual(r.display()[2], "BUSY                 200")
        r.set_adc(1, 490)                       # inside the hysteresis
        r.run(0.2)
        self.assertEqual(r.sreg(0), 0x09)
        r.set_adc(1, 900)
        r.run(0.2)
        self.assertEqual((r.sreg(0), r.sreg(1) & 0x08), (0x0B, 0))
        self.assertEqual(r.display()[2].strip(), "200")

    def test_volume_is_fnc_up_down(self):
        r = booted()
        self.assertEqual(r.sreg(1), 0x30)
        r.press("FNC")
        self.assertEqual(r.display()[0][-1], "F")
        r.press("UP")
        r.press("FNC")
        r.press("UP")
        self.assertEqual((r.display()[1][:5], r.sreg(1)), ("Vol 5", 0x50))
        r.press("FNC")
        r.press("DOWN")
        self.assertEqual((r.display()[1][:5], r.sreg(1)), ("Vol 4", 0x40))
        self.assertEqual(r.display()[0], "433.50000")


class Tx(unittest.TestCase):
    def test_ptt_sequence(self):
        # the Nokia firmware's order: deviation bits, DAC, TX synthesizer
        # to f, TX ON, microphone on; release: mic off, TX OFF, parked
        r = booted()
        r.take_events()
        r.ptt(True)
        r.run(0.3)
        ev = [(k, a) for _, k, a in r.take_events() if k in ("SR", "DAC", "SYNTH", "TX_ON")]
        order = [k for k, _ in ev]
        self.assertLess(order.index("DAC"), order.index("SYNTH"))
        self.assertLess(order.index("SYNTH"), order.index("TX_ON"))
        self.assertEqual(ev[0], ("SR", 2 << 8 | 0x00))               # IC41: deviation 0
        self.assertEqual(ev[-1], ("SR", 0 << 8 | 0x0A))              # IC39: mic on
        self.assertEqual((r.pll(1)[-1], r.out(1) & 1), (433.5e6, 1))
        self.assertEqual(r.display()[2][:4], "TX  ")
        r.ptt(False)
        r.run(0.3)
        self.assertEqual((r.pll(1)[-1], r.out(1) & 1), (433.5625e6, 0))
        self.assertEqual([r.sreg(i) for i in range(3)], [0x0B, 0x30, 0x07])
        self.assertEqual(r.display()[2][:4], "    ")
        self.assertEqual(faults(r), [])

    def test_tuning_during_tx(self):
        r = booted()
        r.ptt(True)
        r.run(0.2)
        r.press("UP")
        self.assertEqual((r.pll(0)[-1], r.pll(1)[-1]), (478.5e6, 433.5e6))
        r.ptt(False)
        r.run(0.2)
        self.assertEqual((r.pll(0)[-1], r.pll(1)[-1]), (478.5125e6, 433.575e6))

    def test_squelch_closed_after_tx(self):
        r = booted()
        r.set_adc(1, 100)
        r.run(0.2)
        r.ptt(True)
        r.run(0.2)
        self.assertEqual(r.sreg(0) & 0x02, 0x02)       # RX audio muted in TX
        r.ptt(False)
        r.run(0.2)
        self.assertEqual(r.sreg(0), 0x09)              # open again (signal)


def fnc(r, key):
    r.press("FNC")
    r.press(key)


class Duplex(unittest.TestCase):
    def test_minus_plus_simplex(self):
        r = booted()
        r.type("4387")
        r.press("OK")
        fnc(r, "#")
        self.assertEqual(r.display()[0], "438.70000 -")
        self.assertEqual((r.pll(0)[-1], r.pll(1)[-1]), (483.7e6, 431.1625e6))
        r.ptt(True)
        r.run(0.2)
        self.assertEqual(r.display()[0], "431.10000 -")       # TX frequency
        self.assertEqual(r.pll(1)[-1], 431.1e6)
        r.ptt(False)
        r.run(0.2)
        self.assertEqual(r.display()[0], "438.70000 -")
        fnc(r, "#")
        self.assertEqual(r.display()[0], "438.70000 +")
        self.assertEqual(r.pll(1)[-1], 446.3625e6)
        fnc(r, "#")
        self.assertEqual(r.display()[0], "438.70000")
        self.assertEqual(r.pll(1)[-1], 438.7625e6)

    def test_reverse_and_shift_entry(self):
        r = booted()
        r.type("4387")
        r.press("OK")
        fnc(r, "#")
        fnc(r, "*")
        r.type("5000")
        self.assertEqual(r.display()[0], "Shift 5000_ kHz")
        r.press("OK")
        fnc(r, "0")                             # listen on the input
        self.assertEqual(r.display()[0], "433.70000 -R")
        self.assertEqual((r.pll(0)[-1], r.pll(1)[-1]), (478.7e6, 438.7625e6))
        r2 = Radio(ROM, nv=r.nv())              # all of it kept
        r2.run(1.0)
        self.assertEqual(r2.display()[0], "433.70000 -R")

    def test_tx_locked_outside_the_band(self):
        r = booted()
        r.type("4450")
        r.press("OK")
        r.take_events()
        r.ptt(True)
        r.run(0.3)
        self.assertEqual(r.display()[2][:4], "LOCK")
        self.assertEqual((r.out(1) & 1, r.take_events("TX_ON")), (0, []))
        r.ptt(False)
        r.run(0.3)
        self.assertEqual(r.display()[2][:4], "    ")


class Memories(unittest.TestCase):
    def store(self, r, n):
        r.press("FNC")
        r.press("RCL")
        self.assertEqual(r.display()[0], "Store _")
        r.type(n)

    def test_store_recall_step(self):
        r = booted()
        r.press("RCL")                          # no memories: stays on VFO
        self.assertEqual(r.display()[0], "433.50000")
        for n, f in (("05", "4331"), ("12", "4387"), ("40", "4395")):
            r.type(f)
            r.press("OK")
            if n == "12":
                fnc(r, "#")
            self.store(r, n)
            self.assertEqual(r.display()[0][:9], f[:3] + "." + f[3:] + "0000")
        self.assertEqual(r.display()[0], "439.50000 -")       # still the VFO
        r.press("RCL")                          # the first stored one
        self.assertEqual(r.display()[0], "433.10000     M05")
        r.press("UP")
        self.assertEqual(r.display()[0], "438.70000 -   M12")
        self.assertEqual(r.pll(1)[-1], 431.1625e6)
        r.press("UP")
        self.assertEqual(r.display()[0], "439.50000 -   M40")
        r.press("UP")                           # wraps
        self.assertEqual(r.display()[0], "433.10000     M05")
        r.press("DOWN")
        self.assertEqual(r.display()[0], "439.50000 -   M40")
        r.type("1")
        self.assertEqual(r.display()[0], "M1_")
        r.type("2")
        self.assertEqual(r.display()[0], "438.70000 -   M12")
        r.type("33")                            # empty: no change
        self.assertEqual(r.display()[0], "438.70000 -   M12")
        r.press("RCL")                          # back to the VFO as it was
        self.assertEqual(r.display()[0], "439.50000 -")
        r.press("RCL")                          # and to the last memory
        self.assertEqual(r.display()[0], "438.70000 -   M12")

    def test_memory_changes_do_not_touch_the_vfo(self):
        r = booted()
        r.type("4387")
        r.press("OK")
        self.store(r, "07")
        r.press("RCL")
        fnc(r, "#")                             # duplex on the channel only
        self.assertEqual(r.display()[0], "438.70000 -   M07")
        r.press("RCL")
        self.assertEqual(r.display()[0], "438.70000")
        r.press("RCL")                          # recalled as stored
        self.assertEqual(r.display()[0], "438.70000     M07")
        fnc(r, "#")
        self.store(r, "08")                     # store in memory mode: to 08
        self.assertEqual(r.display()[0], "438.70000 -   M08")

    def test_memories_survive_power_off(self):
        r = booted()
        r.type("4387")
        r.press("OK")
        fnc(r, "#")
        fnc(r, "0")
        self.store(r, "99")
        r.press("RCL")
        r2 = Radio(ROM, nv=r.nv())
        r2.run(1.0)
        self.assertEqual(r2.display()[0], "431.10000 -R  M99")
        self.assertEqual((r2.pll(0)[-1], r2.pll(1)[-1]), (476.1e6, 438.7625e6))
        self.assertEqual(faults(r2), [])


def run_with_signals(r, seconds, busy_mhz):
    """run in 5 ms slices with the noise input low (a signal) while the
    receiver is on one of busy_mhz"""
    busy = {round((f + 45) * 1e6) for f in busy_mhz}
    t = 0.0
    while t < seconds:
        on = round(r.pll(0)[-1]) in busy
        r.set_adc(1, 100 if on else 900)
        r.run(0.005)
        t += 0.005


class Scan(unittest.TestCase):
    def test_vfo_scan_stops_and_resumes(self):
        r = booted()
        fnc(r, "9")
        run_with_signals(r, 1.5, [433.600])
        self.assertEqual(r.display()[0], "433.60000")
        self.assertEqual(r.display()[2][:4], "BUSY")
        run_with_signals(r, 1.5, [])            # gone: held 2 s, then on
        self.assertEqual(r.display()[0], "433.60000")
        self.assertEqual(r.display()[2][:4], "SCAN")
        run_with_signals(r, 1.0, [])
        self.assertNotEqual(r.display()[0], "433.60000")
        r.press("OK")                           # any key ends it
        f = r.display()[0]
        run_with_signals(r, 0.5, [])
        self.assertEqual((r.display()[0], r.display()[2][:4]), (f, "    "))

    def test_vfo_scan_wraps_in_the_band(self):
        r = booted()
        r.type("43995")
        r.press("OK")
        fnc(r, "9")
        run_with_signals(r, 1.0, [430.025])
        self.assertEqual(r.display()[0], "430.02500")

    def test_memory_scan_and_ptt(self):
        r = booted()
        for n, f in (("01", "4331"), ("02", "4387"), ("03", "4395")):
            r.type(f)
            r.press("OK")
            r.press("FNC")
            r.press("RCL")
            r.type(n)
        r.press("RCL")
        fnc(r, "9")
        run_with_signals(r, 1.0, [439.5])
        self.assertEqual(r.display()[0], "439.50000     M03")
        r.ptt(True)                             # PTT ends the scan
        r.run(0.2)
        r.ptt(False)
        run_with_signals(r, 3.0, [])
        self.assertEqual((r.display()[0], r.display()[2][:4]), ("439.50000     M03", "    "))


# the settings block: NV 0x83000 with P9.2 = 0, the emulator's image
# offset 0x4000 + 0x3000 (r40/nv.h)
NV_CFG = 0x7000


class Nv(unittest.TestCase):
    def test_empty_nv_gets_defaults(self):
        r = booted()
        nv = r.nv()
        self.assertEqual(nv[NV_CFG:NV_CFG + 2], b"R4")
        size = nv[NV_CFG + 3]
        words = sum(nv[NV_CFG:NV_CFG + size - 2]) + int.from_bytes(nv[NV_CFG + size - 2:NV_CFG + size], "big")
        self.assertEqual(words & 0xFFFF, 0)
        self.assertEqual(r.nv()[:0x4000], bytes(0x4000))  # Nokia's copies untouched

    def test_settings_survive_power_off(self):
        r = booted()
        r.type("4381")
        r.press("OK")
        r.press("FNC")
        r.press("UP")
        r.press("FNC")
        r.press("1")                            # step 25 kHz
        r.press("UP")
        self.assertEqual(r.display()[:2], ["438.12500", "Vol 4         25.00k"])
        r2 = Radio(ROM, nv=r.nv())
        r2.run(1.0)
        self.assertEqual(r2.display()[:2], ["438.12500", "Vol 4         25.00k"])
        self.assertEqual((r2.sreg(1), r2.pll(0)[-1]), (0x40, 483.125e6))

    def test_bad_checksum_gives_defaults(self):
        r = booted()
        r.type("4381")
        r.press("OK")
        nv = bytearray(r.nv())
        nv[NV_CFG + 6] ^= 1                     # a bit of the frequency
        r2 = Radio(ROM, nv=bytes(nv))
        r2.run(1.0)
        self.assertEqual(r2.display()[0], "433.50000")


def pwr(r, hold=0.3, gap=0.5):
    r.power_key(True)
    r.run(hold)
    r.power_key(False)
    r.run(gap)


class Power(unittest.TestCase):
    def test_key_beep(self):
        # Nokia's key beep: 8-bit timer phi/64 cleared on compare A = 89,
        # then 51; IC41 SIGN LSP and IC40 PWRAMP while it sounds
        r = booted()
        r.key("5", True)
        seen = []
        for _ in range(150):
            r.run(0.001)
            v = (r.peek(0xFFD0), r.peek(0xFFD2), r.sreg(2) >> 7, (r.sreg(1) >> 3) & 1)
            if not seen or seen[-1] != v:
                seen.append(v)
        r.key("5", False)
        tones = [(a, b) for a, b, sign, amp in seen if a and sign and amp]
        self.assertEqual(sorted(set(tones)), [(0x0A, 51), (0x0A, 89)])
        self.assertEqual(seen[-1][0], 0)                    # timer stopped
        self.assertEqual((r.sreg(2), r.sreg(1)), (0x07, 0x30))

    def test_lcd_sends_only_changes(self):
        r = booted()
        n = r.i2c_count()
        r.set_adc(0, 500)                       # RSSI 75 -> 125
        r.run(0.2)
        lcd = [b for _, b in r.i2c_log(n) if b[0] == 0x78]
        self.assertEqual([len(b) for b in lcd], [4 + 15])
        self.assertEqual(r.display()[2].strip(), "125")

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
        self.assertEqual(r.display()[0], "433.50000")
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
        self.assertEqual(r.display()[0], "433.50000")
        self.assertEqual(r.sreg(0), 0x0B)
        self.assertEqual(faults(r), [])

if __name__ == "__main__":
    unittest.main()
