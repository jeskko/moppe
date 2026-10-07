"""
CTCSS TX tone per output method (PH:CtCGEn).  GE:CtCSSt is a TAB record:
the setting is an index into the tone list (1 = 67.0 Hz ... 42 = 254.1
Hz), and the i8254 method loads ctcss_counter_counts[index].  v3_Z passed
the index as Hz to the other two methods (found 2026-09-29): with the RFC
DAC DDS the tone was index Hz (97.4 Hz played as 12 Hz), and the FX465
got no tone for most settings.  Fixed: they take the tone's rounded Hz
(ctcss_tone_hz[index]).

Run against r58/build (R58_ROM/R58_LST for another build); the tests
fail on the release.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_radio import RadioTest  # noqa: E402

# the tone list, in 0.1 Hz (r58.s CTCSS_TONES)
TONES_DHZ = [670, 693, 719, 744, 770, 797, 825, 854, 885, 915, 948, 974, 1000, 1035, 1072,
             1109, 1148, 1188, 1230, 1273, 1318, 1365, 1413, 1462, 1514, 1567, 1622, 1679,
             1738, 1799, 1862, 1928, 2035, 2066, 2107, 2181, 2257, 2291, 2336, 2418, 2503, 2541]


def hz(index):
    return (TONES_DHZ[index - 1] + 5) // 10


def phase_inc(h):
    """ctcss_hz_to_phase_inc: Hz * 8522 / 256, rounded"""
    v = h * 8522
    return ((v >> 8) + ((v >> 7) & 1)) & 0xFFFF


class CtcssTx(RadioTest):
    def key_up(self, method, index, when=1):
        r = self.boot()
        self.enter("433500")
        r.poke("cfg_ctcss_output_method", method)
        r.poke("cfg_ctcss_tx_hz", index)
        r.poke("cfg_ctcss_output_when", when)
        return r

    def test_i8254_counts(self):
        """the reference: the i8254 method plays the listed tone"""
        for index in (1, 12, 13, 42):
            r = self.key_up(0, index)
            r.ptt(True)
            r.run(0.4)
            p = r.pit(2)
            self.assertAlmostEqual(4032000 / p["count"], TONES_DHZ[index - 1] / 10, delta=0.2)
            r.ptt(False)
            r.run(0.2)

    def test_rfc_dac_plays_the_listed_tone(self):
        for index in (1, 12, 13, 30, 42):
            r = self.key_up(1, index)
            r.ptt(True)
            r.run(0.4)
            self.assertEqual(r.peek16("ctcss_enc_phinc"), phase_inc(hz(index)),
                             "index %d: %d Hz" % (index, hz(index)))
            r.ptt(False)
            r.run(0.2)

    def test_fx465_gets_hz(self):
        """load_fx465 takes Hz in A (TX: D = 0)"""
        for index in (1, 3, 12, 20):
            r = self.key_up(2, index)
            r.breakpoint("load_fx465")
            r.ptt(True)
            self.assertEqual(r.run(0.4), "break")
            c = r.cpu()
            self.assertEqual((c["af"] >> 8, (c["de"] >> 8) & 0xFF), (hz(index), 0))
            r.breakpoint("load_fx465", False)
            r.ptt(False)
            r.run(0.3)


if __name__ == "__main__":
    unittest.main()
