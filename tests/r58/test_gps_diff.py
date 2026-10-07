"""
GPS sentence processing (NMEA GPRMC; the Aisin Seiki binary path was
dropped 2026-10-01): differential scenarios for the C port (c/gps.c, bank 2), asm
build vs C build.  The parsed fields are compared by probes (gps_utc,
gps_date, speed, course, status, the NV position), including the partial
updates a sentence leaves when a field fails to parse.

    R58_GPS_REF_ROM / R58_GPS_REF_LST    reference (default build/)
    R58_GPS_CAND_ROM / R58_GPS_CAND_LST  candidate (default build/)
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from difftest import builds, DiffCase  # noqa: E402
from helpers import gps_state, nmea as nmea_raw  # noqa: E402
from r58emu import P8N  # noqa: E402

REF, CAND = builds("GPS")


def reset():
    """Distinct values in every field, so a partial update shows."""
    return [("poke", "gps_utc", b"\x09" * 8), ("poke", "gps_date", b"\x08" * 8),
            ("poke", "gps_knots", b"\x77\x07"), ("poke", "gps_speed", 0x55),
            ("poke", "gps_course", b"\x66\x06"), ("poke", "gps_valid_seconds", 0),
            ("poke", "cfg_gps_latitude", b"\x07" * 8), ("poke", "cfg_gps_longitude", b"\x06" * 8)]


def sentence(label, data, probe=gps_state):
    return reset() + [("serial_rx", 0, data), ("run", 0.25), ("probe", label, probe),
                      ("check", label)]



RMC = "GPRMC,123519,A,6130.12,N,02345.67,E,012.5,054.7,280926,020.3,E"
# Characters above '9' in a number field (letters, ':') make the sentence
# bad since 2026-10-01 (v3_Z stored them as digits):
# test_signalling.GpsNumbers.
GPRMC_CASES = [
    ("plain", nmea_raw(RMC)),
    ("lowercase checksum", nmea_raw(RMC, "%02x" % int(nmea_raw(RMC)[-4:-2], 16))),
    ("bad checksum", nmea_raw(RMC, "00")),
    ("bad checksum char", nmea_raw(RMC, "G1")),
    ("no checksum", ("$%s\r\n" % RMC).encode()),
    ("one checksum digit", ("$%s*4\r\n" % RMC).encode()),
    ("plain again", nmea_raw(RMC)),
    # '*' last: nothing after it is stored, the buffer still holds the
    # previous sentence's (valid) checksum digits there
    ("stale checksum", ("$%s*\n" % RMC).encode()),
    ("decimal seconds", nmea_raw("GPRMC,123519.25,A,6130.12,N,02345.67,E,012.5,054.7,280926,,")),
    ("status V", nmea_raw("GPRMC,123519,V,6130.12,N,02345.67,E,012.5,054.7,280926,,")),
    ("short utc", nmea_raw("GPRMC,1235,A,6130.12,N,02345.67,E,012.5,054.7,280926,,")),
    ("3 decimals, N/E", nmea_raw("GPRMC,000001,A,3352.083,N,15112.345,E,000.0,359.9,010100,,")),   # S/W: test_signalling.OwnLocator
    ("1 decimal", nmea_raw("GPRMC,000001,A,6130.1,N,02345.6,E,0.0,0.0,010100,,")),
    ("no decimals", nmea_raw("GPRMC,000001,A,6130.,N,02345.,E,5,7,010100,,")),
    ("long degrees", nmea_raw("GPRMC,000001,A,0006130.12,N,1002345.67,E,1,2,010100,,")),
    ("short degrees", nmea_raw("GPRMC,000001,A,130.12,N,5.67,E,1,2,010100,,")),
    ("below-0 in latitude", nmea_raw("GPRMC,000001,A,61/0.12,N,02345.67,E,1,2,010100,,")),
    ("speed round up", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,12.5,10.49,010100,,")),
    ("speed round down", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,12.4,10.51,010100,,")),
    ("fast", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,150.0,0,010100,,")),
    ("138 knots", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,138,0,010100,,")),
    ("137 knots", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,137,0,010100,,")),
    ("huge speed wraps", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,70000,0,010100,,")),
    ("slash in speed", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,1/2,3,010100,,")),
    ("empty speed/course", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,,,010100,,")),
    ("no comma after date", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,1,2,010100")),
    ("missing comma after N", nmea_raw("GPRMC,000001,A,6130.12,N;02345.67,E,1,2,010100,,")),
    ("GPGGA ignored", nmea_raw("GPGGA,123519,6130.12,N,02345.67,E,1,08,0.9,545.4,M,46.9,M,,")),
    ("GPRMB ignored", nmea_raw("GPRMB,A,0.66,L,003,004,4917.24,N,12309.57,W,001.3,052.5,000.5,V")),
    ("junk", b"$\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a"),
]




def scenario(cases, gps_config=0, probe=gps_state):
    steps = [("boot", 2.5), ("poke", "cfg_gps_config", gps_config), ("run", 0.2)]
    for label, data in cases:
        steps += sentence(label, data, probe)
    return steps


class GpsDiff(DiffCase):
    REF = REF
    CAND = CAND

    def test_gprmc(self):
        self.diff(scenario(GPRMC_CASES))

    def test_gprmc_p8n(self):
        self.diff(scenario(GPRMC_CASES[:8]), card=P8N)

    def test_updates_in_menu_redraw(self):
        self.diff([("boot", 2.5), ("press", "E"), ("run", 0.3)] +
                  sentence("in menu", nmea_raw(RMC)) + [("run", 1.0), ("check", "later")])


if __name__ == "__main__":
    unittest.main()
