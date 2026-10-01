"""
The systick timers once_per_second / once_per_minute / once_per_hour
(r58.s, called from systick in interrupt context). Tests before porting
them to C (notes/hybrid-plan.md Phase 4). TOT and low battery are covered
in test_menu_power.py, the remote display timeout in test_fsk.py.

Instead of waiting emulated minutes, a test pokes the clock just before a
boundary (`sec100` = 99, `seconds` = 59, `minutes` = 59) and lets systick
cross it.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_radio import RadioTest, make_sane_nv, LST  # noqa: E402
from r58emu import load_symbols, AD_SQL  # noqa: E402


def nv_with(**fields):
    """SAnE NV image with some byte fields changed (applied at boot)."""
    nv = bytearray(make_sane_nv())
    sym = load_symbols(LST)
    for name, v in fields.items():
        nv[sym[name] - 0xC000] = v
    return bytes(nv)


class Timers(RadioTest):
    def cross(self, what="second", n=1):
        """Let n second (minute, hour) boundaries pass."""
        r = self.r
        for _ in range(n):
            if what in ("minute", "hour"):
                r.poke("seconds", 59)
            if what == "hour":
                r.poke("minutes", 59)
            r.poke("sec100", 99)
            r.run(0.015)

    # ---- once_per_second

    def test_gps_valid_seconds_counts_down(self):
        r = self.boot()
        r.poke("gps_valid_seconds", 2)
        self.cross()
        self.assertEqual(r.peek("gps_valid_seconds"), 1)
        self.cross(n=2)
        self.assertEqual(r.peek("gps_valid_seconds"), 0)

    def test_mprs_report_timer_speed_weighted_saturating(self):
        """+ (speed_kmh / 4 & 63) + 1 per second, stops at 0xFFFF."""
        r = self.boot()
        r.poke("gps_speed", 128)
        r.poke("mprs_report_timer", bytes([0, 0]))
        self.cross()
        self.assertEqual(r.peek16("mprs_report_timer"), 33)
        r.poke("gps_speed", 0)
        self.cross()
        self.assertEqual(r.peek16("mprs_report_timer"), 34)
        r.poke("mprs_report_timer", bytes([0xF0, 0xFF]))
        r.poke("gps_speed", 255)
        self.cross()
        self.assertEqual(r.peek16("mprs_report_timer"), 0xFFFF)

    def test_transmitter_hours(self):
        """While TX is on, a second counter rolls over at 3600 into the
        3-byte St:USEhrS count."""
        r = self.boot()
        self.enter("433500")
        r.poke("transmitter_hours", bytes([0xFF, 0x00, 0x00]))
        r.poke("transmitter_hours_second_counter", bytes([0x0F, 0x0E]))  # 3599
        self.cross()
        self.assertEqual(r.peek16("transmitter_hours_second_counter"), 3599,
                         "no counting in RX")
        r.ptt(True)
        r.run(0.2)
        self.assertTrue(r.transmitting())
        self.cross()
        r.ptt(False)
        self.assertEqual(r.peek16("transmitter_hours_second_counter"), 0)
        self.assertEqual(r.peek("transmitter_hours", 3), bytes([0x00, 0x01, 0x00]))

    def test_alert_timer_counts_down(self):
        r = self.boot()
        r.poke("alert_timer", 5)
        self.cross()
        self.assertEqual(r.peek("alert_timer"), 4)

    def test_lights_timer_counts_up_to_255(self):
        r = self.boot()
        r.poke("lights_timer", 10)
        self.cross()
        self.assertEqual(r.peek("lights_timer"), 11)
        r.poke("lights_timer", 255)
        self.cross()
        self.assertEqual(r.peek("lights_timer"), 255)

    def test_call_timer_rollover_and_cap(self):
        """Runs while a call is shown; hours stop at 99."""
        r = self.boot()

        def hms(h, m, s):
            r.poke("call_timer_hour", h)
            r.poke("call_timer_min", m)
            r.poke("call_timer_sec", s)

        def get():
            return (r.peek("call_timer_hour"), r.peek("call_timer_min"),
                    r.peek("call_timer_sec"))

        hms(1, 2, 3)
        self.cross()
        self.assertEqual(get(), (1, 2, 3), "not counting without a call")
        r.poke("call_dpyed", 1)
        self.cross()
        self.assertEqual(get(), (1, 2, 4))
        hms(97, 59, 59)
        self.cross()
        self.assertEqual(get(), (98, 0, 0))
        hms(98, 59, 59)
        self.cross()
        self.assertEqual(get(), (99, 0, 0))
        hms(99, 59, 59)
        self.cross()
        self.assertEqual(get(), (99, 0, 0))

    def test_dtmf_hold_time(self):
        """dtmf_idletime counts up once pending and resets at
        cfg_dtmf_holdtime (dtmf_decoder_timeout)."""
        r = self.boot()
        r.poke("cfg_dtmf_holdtime", 3)
        r.poke("dtmf_idletime", 1)
        self.cross()
        self.assertEqual(r.peek("dtmf_idletime"), 2)
        self.cross()
        self.assertEqual(r.peek("dtmf_idletime"), 0)
        self.cross()
        self.assertEqual(r.peek("dtmf_idletime"), 0, "0 = nothing pending")

    def test_scan_patience_counts_down_while_scanning(self):
        r = self.boot()
        r.poke("scan_patience", 5)
        self.cross()
        self.assertEqual(r.peek("scan_patience"), 5, "only while scanning")
        r.press("S", hold=0.3)
        r.run(0.05)
        self.assertEqual(r.peek("scan_on"), 1)
        r.poke("scan_patience", 5)
        self.cross()
        self.assertEqual(r.peek("scan_patience"), 4)

    def test_repeater_sitters_count_on_cradle(self):
        """GE:rEPSit: while the squelch is open (squelch_is_closed zeroes
        it every tick) and the handset is on the cradle, the counter
        starts at -cfg_repeater_sitters_special and counts up; its
        overflow cuts the audio (audioc_off)."""
        r = self.boot()
        r.poke("cfg_repeater_sitters_special", 5)
        r.poke("cfg_squelch_level", 127)
        r.hook(True)                           # off cradle: no count
        r.adc(AD_SQL, 0xC0)
        r.run(0.5)
        self.assertEqual(r.peek("squelch_open"), 1)
        self.assertEqual(r.peek("repeater_sitters_special"), 251, "starts at -N")
        self.cross()
        self.assertEqual(r.peek("repeater_sitters_special"), 251)
        r.hook(False)
        r.run(0.1)
        self.cross()
        self.assertEqual(r.peek("repeater_sitters_special"), 252)
        r.poke("repeater_sitters_special", 255)
        self.cross()
        self.assertEqual(r.peek("repeater_sitters_special"), 0,
                         "overflow after N s: audio cut, counting stops")
        self.cross()
        self.assertEqual(r.peek("repeater_sitters_special"), 0)

    # ---- once_per_minute

    def test_idle_function_starts_scanner(self):
        """GE:IdLE t minutes of idleness run GE:IdLEFn (1 = scan)."""
        r = self.boot()
        r.poke("cfg_idlefn_delay", 2)
        r.poke("cfg_idlefn", 1)
        r.poke("idle_timer", 0)
        self.cross("minute")
        self.assertEqual(r.peek("idle_timer"), 1)
        self.assertEqual(r.peek("scan_on"), 0)
        self.cross("minute")
        r.run(0.05)
        self.assertEqual(r.peek("idle_timer"), 2)
        self.assertEqual(r.peek("scan_on"), 1)

    def test_idle_timer_held_by_pending_digits(self):
        r = self.boot()
        r.poke("idle_timer", 0)
        r.type("4")
        self.cross("minute")
        self.assertEqual(r.peek("idle_timer"), 0)

    def test_idle_timer_stops_at_255(self):
        r = self.boot()
        r.poke("cfg_idlefn_delay", 0)
        r.poke("idle_timer", 255)
        self.cross("minute")
        self.assertEqual(r.peek("idle_timer"), 255)

    # ---- once_per_hour

    def test_ignition_auto_power_off(self):
        """/IGN open: to:IGnAPO = N powers down at the (N+2)th hour
        boundary (compare before count, like v3_Z's TOT was). Needs
        GE:GPio 2 bit 1, which releases PB2 as an input."""
        r = self.boot(nv=nv_with(cfg_gpio2_state=2, cfg_ign_apo_hours=1))
        r.poke("ign_apo_timer", 0)
        self.cross("hour")
        self.assertEqual(r.peek("ign_apo_timer"), 0, "ignition on: no count")
        r.ign(False)
        self.cross("hour", 2)
        self.assertTrue(r.powered)
        self.assertEqual(r.peek("ign_apo_timer"), 2)
        self.cross("hour")
        r.run(0.5)
        self.assertFalse(r.powered)

    def test_ignition_apo_off_when_pb2_driven(self):
        """SAnE default GPio 2 = 0 drives PB2 low: /IGN reads as on, so
        no auto power-off whatever the pin does."""
        r = self.boot(nv=nv_with(cfg_ign_apo_hours=0))
        r.ign(False)
        self.cross("hour", 3)
        r.run(0.3)
        self.assertTrue(r.powered)
        self.assertEqual(r.peek("ign_apo_timer"), 0)

    def test_ignition_apo_255_never(self):
        r = self.boot(nv=nv_with(cfg_gpio2_state=2, cfg_ign_apo_hours=255))
        r.poke("ign_apo_timer", 250)
        r.ign(False)
        self.cross("hour", 3)
        r.run(0.3)
        self.assertTrue(r.powered)


if __name__ == "__main__":
    unittest.main()
