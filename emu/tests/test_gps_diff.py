"""
GPS sentence processing (NMEA GPRMC and the Aisin Seiki binary CA CA
block): differential scenarios for the C port (c/gps.c, bank 2), asm
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
from difftest import run_diff  # noqa: E402
from test_radio import make_sane_nv  # noqa: E402
from r58emu import P8E, P8N, CU53AN  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FW = os.path.join(ROOT, "firmware")
REF = (os.environ.get("R58_GPS_REF_ROM", os.path.join(FW, "build-ref", "r58.bin")),
       os.environ.get("R58_GPS_REF_LST", os.path.join(FW, "build-ref", "r58.map")))
CAND = (os.environ.get("R58_GPS_CAND_ROM", os.path.join(FW, "build", "r58.bin")),
        os.environ.get("R58_GPS_CAND_LST", os.path.join(FW, "build", "r58.map")))


def gps_state(r):
    return (r.peek("gps_utc", 8), r.peek("gps_date", 8), r.peek16("gps_knots"),
            r.peek("gps_speed"), r.peek16("gps_course"), r.peek("gps_status", 8),
            r.peek("gps_valid_seconds"), r.peek("cfg_gps_latitude", 8),
            r.peek("cfg_gps_longitude", 8), r.peek("cfg_gps_locator", 8))


def nmea_raw(body, ck=None):
    if ck is None:
        c = 0
        for ch in body:
            c ^= ord(ch)
        ck = "%02X" % c
    return ("$%s*%s\r\n" % (body, ck)).encode("latin-1")


def reset():
    """Distinct values in every field, so a partial update shows."""
    return [("poke", "gps_utc", b"\x09" * 8), ("poke", "gps_date", b"\x08" * 8),
            ("poke", "gps_knots", b"\x77\x07"), ("poke", "gps_speed", 0x55),
            ("poke", "gps_course", b"\x66\x06"), ("poke", "gps_valid_seconds", 0),
            ("poke", "cfg_gps_latitude", b"\x07" * 8), ("poke", "cfg_gps_longitude", b"\x06" * 8)]


def sentence(label, data):
    return reset() + [("serial_rx", 0, data), ("run", 0.25), ("probe", label, gps_state),
                      ("check", label)]


RMC = "GPRMC,123519,A,6130.12,N,02345.67,E,012.5,054.7,280926,020.3,E"
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
    ("letter in utc", nmea_raw("GPRMC,12351X,A,6130.12,N,02345.67,E,012.5,054.7,280926,,")),
    ("3 decimals, S/W", nmea_raw("GPRMC,000001,A,3352.083,S,15112.345,W,000.0,359.9,010100,,")),
    ("1 decimal", nmea_raw("GPRMC,000001,A,6130.1,N,02345.6,E,0.0,0.0,010100,,")),
    ("no decimals", nmea_raw("GPRMC,000001,A,6130.,N,02345.,E,5,7,010100,,")),
    ("long degrees", nmea_raw("GPRMC,000001,A,0006130.12,N,1002345.67,E,1,2,010100,,")),
    ("short degrees", nmea_raw("GPRMC,000001,A,130.12,N,5.67,E,1,2,010100,,")),
    ("letter in latitude", nmea_raw("GPRMC,000001,A,61:0.12,N,02345.67,E,1,2,010100,,")),
    ("below-0 in latitude", nmea_raw("GPRMC,000001,A,61/0.12,N,02345.67,E,1,2,010100,,")),
    ("speed round up", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,12.5,10.49,010100,,")),
    ("speed round down", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,12.4,10.51,010100,,")),
    ("fast", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,150.0,0,010100,,")),
    ("138 knots", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,138,0,010100,,")),
    ("137 knots", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,137,0,010100,,")),
    ("huge speed wraps", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,70000,0,010100,,")),
    ("slash in speed", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,1/2,3,010100,,")),
    ("letter in speed", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,1A.0,3,010100,,")),
    ("empty speed/course", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,,,010100,,")),
    ("bad date", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,1,2,01x100,,")),
    ("no comma after date", nmea_raw("GPRMC,000001,A,6130.12,N,02345.67,E,1,2,010100")),
    ("missing comma after N", nmea_raw("GPRMC,000001,A,6130.12,N;02345.67,E,1,2,010100,,")),
    ("GPGGA ignored", nmea_raw("GPGGA,123519,6130.12,N,02345.67,E,1,08,0.9,545.4,M,46.9,M,,")),
    ("GPRMB ignored", nmea_raw("GPRMB,A,0.66,L,003,004,4917.24,N,12309.57,W,001.3,052.5,000.5,V")),
    ("junk", b"$\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a"),
]


def aisin(fix=3, lat=(61, 30, 7, 128), lon=(23, 45, 40, 0), heading=0x100, speed=100,
          datetime=b"\x26\x09\x28\x12\x34\x56", sats=b"\x00\x00\x00\x00\x12\x34\xAB\xCD", ck=None):
    p = bytearray(40)
    p[0] = fix
    for at, (d, m, s, f) in ((1, lat), (5, lon)):
        p[at:at + 4] = (((d * 3600 + m * 60 + s) * 256) + f).to_bytes(4, "big")
    p[13:15] = heading.to_bytes(2, "big")
    p[16:18] = speed.to_bytes(2, "big")
    p[22:28] = datetime
    p[31:39] = sats
    if ck is None:
        ck = (-(0xCA + 0xCA + sum(p))) & 0xFF
    return bytes([0xCA, 0xCA]) + bytes(p) + bytes([ck, 0x0D])


AISIN_CASES = [
    ("2D fix", aisin()),
    ("3D fix, changed flag", aisin(fix=0x14)),
    ("no fix", aisin(fix=2)),
    ("fix 5", aisin(fix=5)),
    ("bad checksum", aisin(ck=0x12)),
    ("headings", aisin(heading=0x2FF)),
    ("heading 3FF", aisin(heading=0x3FF, speed=285)),
    ("speed 284", aisin(speed=284, heading=0x200)),
    ("slow", aisin(speed=1, lat=(0, 0, 0, 0), lon=(179, 59, 59, 255))),
    ("with junk before", b"\x0d\x01\x02" + aisin(heading=0x80)),
]


def scenario(cases, gps_config=0):
    steps = [("boot", 2.5), ("poke", "cfg_gps_config", gps_config), ("run", 0.2)]
    for label, data in cases:
        steps += sentence(label, data)
    return steps


class GpsDiff(unittest.TestCase):
    def diff(self, scenario, card=P8E):
        diffs = run_diff(scenario, REF, CAND, card=card, cu=CU53AN, nv=make_sane_nv(card, CU53AN))
        self.assertEqual(diffs, [], "\n".join(diffs))

    def test_gprmc(self):
        self.diff(scenario(GPRMC_CASES))

    def test_gprmc_p8n(self):
        self.diff(scenario(GPRMC_CASES[:8]), card=P8N)

    def test_aisin_seiki(self):
        self.diff(scenario(AISIN_CASES, gps_config=3))

    def test_updates_in_menu_redraw(self):
        self.diff([("boot", 2.5), ("press", "E"), ("run", 0.3)] +
                  sentence("in menu", nmea_raw(RMC)) + [("run", 1.0), ("check", "later")])


if __name__ == "__main__":
    unittest.main()
