"""
Signalling tests: these decode the audio the firmware synthesises on the
8254 tone pin, so they check the cycle-exact PWM loops (DTMF, AX.25) and
the P8E one-wait-per-M1 timing model end to end.
"""
import math
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_radio import RadioTest, make_sane_nv, ROM, LST  # noqa: E402
from r58emu import Radio, P8E, P8N  # noqa: E402
from helpers import nmea  # noqa: E402
import afsk  # noqa: E402

DTMF_ROWS = [697, 770, 852, 941]
DTMF_COLS = [1209, 1336, 1477, 1633]
DTMF_KEYS = {"1": (697, 1209), "5": (770, 1336), "9": (852, 1477),
             "0": (941, 1336), "#": (941, 1477), "*": (941, 1209)}


def goertzel(x, rate, f):
    w = 2 * math.pi * f / rate
    c = 2 * math.cos(w)
    s1 = s2 = 0.0
    for v in x:
        s1, s2 = v + c * s1 - s2, s1
    return math.sqrt(max(0.0, s1 * s1 + s2 * s2 - c * s1 * s2)) / len(x)


class Dtmf(RadioTest):
    def dtmf(self, card):
        self.card = card
        r = self.boot()
        self.enter("433500")
        r.ptt(True)
        r.run(0.3)
        for key, (lo, hi) in DTMF_KEYS.items():
            r.audio_start()
            r.key_down(key)
            r.run(0.3)
            r.key_up()
            r.run(0.05)
            x = r.audio_samples(rate=16000)
            x = x[len(x) // 4: 3 * len(x) // 4]
            # Hann window: with a plain cut the leakage alone put the purity
            # ratio at 10-11 even for the released firmware, and a 1 ms shift
            # of the tone start could tip it under the limit
            n = len(x)
            x = [v * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1))) for i, v in enumerate(x)]
            mag = {f: goertzel(x, 16000, f) for f in DTMF_ROWS + DTMF_COLS}
            row = max(DTMF_ROWS, key=mag.get)
            col = max(DTMF_COLS, key=mag.get)
            self.assertEqual((row, col), (lo, hi), "key %s" % key)
            others = [mag[f] for f in DTMF_ROWS + DTMF_COLS if f not in (lo, hi)]
            self.assertGreater(min(mag[lo], mag[hi]), 10 * max(others))
        r.ptt(False)
        r.run(0.2)

    def test_dtmf_p8e(self):
        self.dtmf(P8E)

    def test_dtmf_p8n(self):
        self.dtmf(P8N)


def maidenhead8(lat, lon):
    """8-character locator of degrees (south and west negative)."""
    lon, lat = lon + 180, lat + 90
    return "".join([chr(65 + int(lon // 20)), chr(65 + int(lat // 10)),
                    str(int(lon % 20 // 2)), str(int(lat % 10)),
                    chr(65 + int(lon % 2 * 12)), chr(65 + int(lat % 1 * 24)),
                    str(int(lon * 12 % 1 * 10)), str(int(lat * 24 % 1 * 10))]).encode()


class OwnLocator(RadioTest):
    """cfg_gps_locator from a GPRMC position (gps_own_locator)."""

    def locator(self, lat, ns, lon, ew):
        r = self.boot()
        r.serial_rx(0, nmea("GPRMC,123519,A,%s,%s,%s,%s,000.0,000.0,280926,," % (lat, ns, lon, ew)))
        r.run(0.5)
        return r.peek("cfg_gps_locator", 8)

    def test_north_east(self):
        self.assertEqual(self.locator("6130.12", "N", "02345.67", "E"),
                         maidenhead8(61 + 30.12 / 60, 23 + 45.67 / 60))

    def test_south(self):
        """a southern latitude is negative (v3_Z read it as northern: only
        'W' set the sign bit; fixed 2026-09-30)"""
        self.assertEqual(self.locator("3352.08", "S", "15112.34", "E"),
                         maidenhead8(-(33 + 52.08 / 60), 151 + 12.34 / 60))
        self.assertEqual(self.locator("2254.60", "S", "04312.20", "W"),   # (not on
                         maidenhead8(-(22 + 54.60 / 60), -(43 + 12.20 / 60)))  # an edge)


class Aprs(RadioTest):
    def aprs(self, card, m1_wait=None, gps=None):
        self.card = card
        r = Radio(ROM, LST, card=card, nv=make_sane_nv(card))
        self.r = r
        if m1_wait is not None:
            r.set_m1_wait(m1_wait)
        r.poke("cfg_report_type", 1)          # Pr:tProto = APrS
        r.poke("cfg_keyup_mprs", 1)           # Pr:PttSnd = ALL
        r.poke("cfg_mprs_callsign", b"OH3XYZ\xff\xff")
        r.run(2.5)
        if gps:
            r.serial_rx(0, gps)
            r.run(0.5)
        self.enter("433500")
        r.ptt(True)
        r.run(0.5)
        r.audio_start()
        r.ptt(False)
        r.run(1.5)
        return afsk.decode(r.audio_samples(48000))

    def test_aprs_p8e(self):
        self.assertEqual(self.aprs(P8E), ["OH3XYZ>APRS:!0000.00N//0000.00Ep"])

    def test_aprs_p8n(self):
        self.assertEqual(self.aprs(P8N), ["OH3XYZ>APRS:!0000.00N//0000.00Ep"])

    def test_wrong_wait_model_breaks_aprs(self):
        # negative control: the loops only work with the real timing
        self.assertEqual(self.aprs(P8E, m1_wait=0), [])
        self.assertEqual(self.aprs(P8N, m1_wait=1), [])

    def test_gps_position_in_report(self):
        fr = self.aprs(P8E, gps=nmea(
            "GPRMC,123519,A,6130.12,N,02345.67,E,000.0,000.0,280926,,"))
        self.assertEqual(len(fr), 1)
        self.assertIn("6130.12N", fr[0])
        self.assertIn("02345.67E", fr[0])


def fsk_crc_ok(pkt):
    """Firmware FSK CRC: reflected CCITT, init FFFF, complemented, high
    byte first after the data (r58.asm L9099-9160)."""
    data, hi, lo = pkt[:-2], pkt[-2], pkt[-1]
    v = afsk.crc16_x25(data)
    return (v >> 8, v & 0xff) == (hi, lo)


class Fsk(RadioTest):
    def test_mprs_packet_after_ptt(self):
        r = self.boot()
        r.poke("cfg_report_type", 0)          # Pr:tProto = ProPr (MPRS over FFSK)
        r.poke("cfg_keyup_mprs", 1)           # after every over
        r.poke("cfg_mprs_callsign", b"OH3XYZ\xff\xff")
        self.enter("433500")
        r.ptt(True)
        r.run(0.5)
        r.take_events()
        r.ptt(False)
        r.run(1.5)
        tx = bytes(e[2] for e in r.take_events("MODEM_TX"))
        self.assertEqual(tx[:5], bytes([0xAA, 0xAA, 0xAA, 0xC4, 0xD7]))
        pkt = tx[5:]
        self.assertEqual(len(pkt), 15)
        self.assertEqual(pkt[0], 0x40)        # MPRS tag
        self.assertTrue(fsk_crc_ok(pkt), pkt.hex())


class Tones(RadioTest):
    def test_1750_burst(self):
        r = self.boot()
        self.enter("433500")
        r.press("*", hold=0.3, gap=0)        # '*' with no digits: 1750 Hz
        self.assertTrue(r.transmitting())
        self.assertAlmostEqual(r.tone_hz(), 1750.0, delta=1)
        self.assertTrue(r.latches()["out0"] & 0x20)       # CCIRC: to TX
        r.run(1.0)


if __name__ == "__main__":
    unittest.main()
