"""
MPRS receive and APRS sending (bank 1 asm: handle_mprs_packets ...
stuffed_8bits): differential fuzz scenarios for the C port, asm build vs
C build, with a fixed seed.

Receive: random MPRS packets (callsigns, SSIDs, positions in and out of
range, the reserved bit, symbol bits) against random own positions, in
every MBUS output format (cfg_mbus_mprs 0..4) and GPS waypoint upload
(cfg_gps_upload 0..2).  Compared: the remote display, locator and
distance/bearing strings, the packed packet, the MBUS and GPS bytes
(difftest events) and the display.
Own locator: random GPRMC positions (gps_own_locator).
Send: random report settings (position and hemisphere letters, speed,
course, symbol, SSID, callsign, digipeaters, MIC-E message and SSID, pad
bits) in the normal and the MIC-E format; compared: the AX.25 frame
(aprs_packet_out) and the bit-stuffed stream (aprs_bits_out).

    R58_APRS_REF_ROM / R58_APRS_REF_LST    reference (default build/)
    R58_APRS_CAND_ROM / R58_APRS_CAND_LST  candidate (default build/)
"""
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from difftest import builds, DiffCase  # noqa: E402
from helpers import with_crc, nmea  # noqa: E402
from r58emu import P8N  # noqa: E402

REF, CAND = builds("APRS")

EOS = 0xFF
CALL_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "


def rx_state(r):
    return (r.peek("remote_display_buffer", 16), r.peek("locator_display_buffer", 8),
            r.peek("distance_bearing", 8), r.peek("mprs_packed_packet", 12),
            r.peek("mprs_qrb_dir_bits"), r.peek("my_coord_tmp_6bytes", 6), r.peek("display_buffer_time") > 0,
            r.peek("locator_dpyed") > 0, r.peek("cfg_gps_locator", 8))


def tx_state(r):
    return r.peek("aprs_packet_out", 124), r.peek("aprs_bits_out", 189)


def pack_callsign(text):
    """8 characters as 6-bit values (' ' = 0) into 6 bytes, as
    packet_callsign_pack does."""
    v = [(ord(ch) - 0x20) & 0x3F for ch in text.ljust(8)[:8]]
    out = []
    for g in (v[0:4], v[4:8]):
        a, b, c, d = g
        out += [(b & 3) << 6 | a, (c << 4 | b >> 2) & 0xFF, (d << 2 | c >> 4) & 0xFF]
    return out


def near(rnd, own_lat, own_lon):
    """lat/lon bytes a few metres to ~600 km from the own position (QRB
    gives up from 1000 km), with the own hemispheres"""
    def centimin(d):
        return ((d[0] * 100 + d[1] * 10 + d[2]) * 60 + d[3] * 10 + d[4]) * 100 + d[5] * 10 + d[6]
    out = []
    for own, limit in ((own_lat, 90), (own_lon, 180)):
        scale = rnd.choice((0.001, 0.01, 0.1, 1, 3, 5))
        v = centimin(own) + int(rnd.uniform(-1, 1) * scale * 6000)
        v = max(0, min(v, limit * 6000 - 1))
        deg, rest = divmod(v, 6000)
        out.append([deg, rest // 100, rest % 100 | (0x80 if own[7] in b"SW" else 0)])
    return out


def mprs_packet(rnd, own=None):
    call = "".join(rnd.choice(CALL_CHARS) for _ in range(rnd.choice((3, 5, 6, 6, 6))))
    p = pack_callsign(call)
    p[4] = (p[4] & 0x0F) | rnd.randrange(16) << 4          # SSID
    p[5] = rnd.choice((0, 0, rnd.randrange(256)))           # reserved
    if own and rnd.random() < 0.7:
        lat, lon = near(rnd, *own)
    elif rnd.random() < 0.8:
        lat = [rnd.randrange(91), rnd.randrange(60), rnd.randrange(100)]
        lon = [rnd.randrange(181), rnd.randrange(60), rnd.randrange(100)]
    else:                                                   # out of range
        lat = [rnd.randrange(128), rnd.randrange(64), rnd.randrange(128)]
        lon = [rnd.randrange(256), rnd.randrange(64), rnd.randrange(128)]
    lat[1] |= rnd.randrange(4) << 6                         # symbol bits
    lon[1] |= rnd.randrange(4) << 6
    if not own and rnd.random() < 0.3:
        lat[2] |= 0x80                                      # south
    if not own and rnd.random() < 0.3:
        lon[2] |= 0x80                                      # west
    lat, lon = ref_packed(lat), ref_packed(lon)
    if rnd.random() < 0.1:
        lat[0] |= 0x80                                      # reserved: no position
    return with_crc(bytes([0x40 | rnd.randrange(16)] + p + lat + lon))


def degmin_digits(rnd, maxdeg, hemis):
    deg = rnd.randrange(maxdeg + 1)
    return bytes([deg // 100, deg // 10 % 10, deg % 10, rnd.randrange(6), rnd.randrange(10),
                  rnd.randrange(10), rnd.randrange(10), ord(rnd.choice(hemis))])


def ref_degmin(d):
    """An own position the reference computes right: north/east, not at
    exactly .50 minute (v3_Z's southern, western and .50 locators and own
    positions were wrong, fixed 2026-09-30; test_signalling.OwnLocator and
    test_fsk.ReceivedLocator check those against a model)"""
    d = bytearray(d)
    d[7] = {ord("S"): ord("N"), ord("W"): ord("E")}.get(d[7], d[7])
    if d[5:7] == b"\x05\x00":
        d[6] = 1
    return bytes(d)


def ref_packed(v):
    """the same for a packed [deg, min, centimin | sign] of a packet"""
    v[2] &= 0x7F
    if v[2] == 50:
        v[2] = 51
    return v


def own_position(rnd):
    lat, lon = degmin_digits(rnd, 88, "NNNS"), degmin_digits(rnd, 179, "EEEW")
    lat, lon = ref_degmin(lat), ref_degmin(lon)
    return (lat, lon), [("poke", "cfg_gps_latitude", lat), ("poke", "cfg_gps_longitude", lon)]


def rx_scenario(seed, n):
    rnd = random.Random(seed)
    # a GPS time as after any fix: the logger format prints gps_utc up to
    # EOS, and before the first fix there is none (it runs on through the
    # RAM after it, v3_Z)
    steps = [("boot", 2.5), ("poke", "cfg_remote_dpy_secs", 5),
             ("poke", "gps_utc", bytes([1, 2, 3, 4, 5, 6, EOS, EOS])),
             ("keys", "433500"), ("press", "#"), ("run", 0.3)]
    for i in range(n):
        own, pokes = own_position(rnd)
        steps += pokes + [
            ("poke", "cfg_mbus_mprs", rnd.randrange(5)),
            ("poke", "cfg_gps_upload", rnd.randrange(3)),
            ("modem_rx", mprs_packet(rnd, own if rnd.random() < 0.8 else None)), ("run", 0.8),
            ("probe", "rx %d" % i, rx_state), ("check", "rx %d" % i)]
    return steps


def locator_scenario(seed, n):
    rnd = random.Random(seed)
    steps = [("boot", 2.5)]
    for i in range(n):
        lat = "%02d%02d.%02d" % (rnd.randrange(90), rnd.randrange(60), rnd.randrange(100))
        lon = "%03d%02d.%02d" % (rnd.randrange(180), rnd.randrange(60), rnd.randrange(100))
        rnd.choice("NS"), rnd.choice("EW")      # drawn as before: the seeded sequence stays
        lat, lon = (x[:-2] + "51" if x.endswith("50") else x for x in (lat, lon))
        body = "GPRMC,120000,A,%s,%s,%s,%s,0.0,0.0,280926,," % (lat, "N", lon, "E")   # see ref_degmin
        steps += [("serial_rx", 0, nmea(body)), ("run", 0.25),
                  ("probe", "locator %d" % i, lambda r: r.peek("cfg_gps_locator", 8))]
    return steps + [("check", "end")]


def callsign(rnd):
    kind = rnd.random()
    if kind < 0.6:
        s = "".join(rnd.choice(CALL_CHARS[:-1]) for _ in range(rnd.randrange(3, 7)))
        return s.encode().ljust(8, b"\xff")
    if kind < 0.8:                                  # lowercase and -SSID
        s = "".join(rnd.choice("abcxyz019") for _ in range(4)) + "-%d" % rnd.randrange(16)
        return s.encode()[:8].ljust(8, b"\xff")
    return bytes(rnd.choice(list(range(16)) + [EOS]) for _ in range(8))   # raw digits


def tx_case(rnd):
    pokes = {
        "cfg_report_type": rnd.choice((1, 2)),
        "cfg_gps_latitude": degmin_digits(rnd, 89, "NNSX"),
        "cfg_gps_longitude": degmin_digits(rnd, 179, "EEWX"),
        "gps_knots": rnd.choice((0, 1, 2, 3, 99, 100, 199, 200, 299, 300, 450, 999, 1000,
                                 rnd.randrange(500))).to_bytes(2, "little"),
        "gps_course": rnd.choice((0, 1, 99, 100, 359, 360, rnd.randrange(400))).to_bytes(2, "little"),
        "cfg_mprs_symbol": rnd.randrange(16),
        "cfg_mprs_ssid": rnd.randrange(16),
        "cfg_mprs_callsign": callsign(rnd),
        "cfg_ax25_digi_other": rnd.choice((b"OH3RPT-5", b"WIDE2-2\xff", b"relay\xff\xff\xff")),
        "cfg_mic_e_message": rnd.randrange(16),
        "cfg_mic_e_dest_ssid": rnd.randrange(16),
        "cfg_ax25_padbits": rnd.choice((0, 8, 36, rnd.randrange(64))),
    }
    for k in range(4):
        pokes["cfg_ax25_digi%d" % k] = rnd.choice((0, 0, rnd.randrange(8)))
    return pokes


def tx_scenario(seed, n):
    rnd = random.Random(seed)
    steps = [("boot", 2.5), ("poke", "cfg_keyup_mprs", 1), ("keys", "433500"),
             ("press", "#"), ("run", 0.3)]
    for i in range(n):
        steps += [("poke", k, v) for k, v in tx_case(rnd).items()]
        steps += [("poke", "aprs_packet_out", bytes(124)), ("poke", "aprs_bits_out", bytes(189)),
                  ("ptt", True), ("run", 0.3), ("ptt", False), ("run", 2.5),
                  # the C build transmits ~10 ms longer per report (bit
                  # stuffing before the audio): the TX-hours seconds counter
                  # drifts over many reports
                  ("poke", "transmitter_hours_second_counter", 0),
                  ("probe", "tx %d" % i, tx_state), ("check", "tx %d" % i)]
    return steps


def tx_boundaries():
    """every speed and course boundary in both report formats"""
    steps = [("boot", 2.5), ("poke", "cfg_keyup_mprs", 1), ("keys", "433500"),
             ("press", "#"), ("run", 0.3)]
    k = 0
    for rtype in (1, 2):
        for knots, course in ((0, 5), (1, 5), (2, 0), (3, 1), (99, 99), (100, 100),
                              (150, 359), (199, 360), (200, 999), (299, 1000),
                              (300, 1001), (999, 7), (1000, 7), (1001, 7)):
            steps += [("poke", "cfg_report_type", rtype),
                      ("poke", "gps_knots", knots.to_bytes(2, "little")),
                      ("poke", "gps_course", course.to_bytes(2, "little")),
                      ("poke", "aprs_packet_out", bytes(124)),
                      ("ptt", True), ("run", 0.3), ("ptt", False), ("run", 2.0),
                      ("poke", "transmitter_hours_second_counter", 0),
                      ("probe", "boundary %d" % k, tx_state), ("check", "boundary %d" % k)]
            k += 1
    return steps


def rx_boundaries():
    """a longitude difference of exactly +-180 degrees (and just inside),
    east against west: degrees from 128 on are masked (7 bits)"""
    steps = [("boot", 2.5), ("poke", "cfg_remote_dpy_secs", 5), ("keys", "433500"),
             ("press", "#"), ("run", 0.3)]
    cases = ((b"\x01\x00\x00E", [80, 0, 0x80]), (b"\x00\x08\x00W", [100, 0, 0]),
             (b"\x01\x00\x00E", [79, 59, 0x80 | 99]), (b"\x00\x08\x00W", [99, 59, 99]))
    for i, (own, his_lon) in enumerate(cases):
        steps += [("poke", "cfg_gps_latitude", bytes([0, 6, 1, 0, 0, 0, 0, ord("N")])),
                  ("poke", "cfg_gps_longitude", own[:3] + bytes(4) + own[3:]),
                  ("modem_rx", with_crc(bytes([0x40] + pack_callsign("OH3AB") + [61, 0, 0] + his_lon))),
                  ("run", 0.8), ("probe", "lon 180 %d" % i, rx_state), ("check", "lon 180 %d" % i)]
    return steps


# The C APRS path transmits ~10 ms longer (bit stuffing before the audio,
# notes/open-bugs.md), and TX_OFF falls on a 10 ms systick: up to 20 ms
# late, which sat right at the default tolerance.
TX_TOLERANCE_S = 0.030


class AprsDiff(DiffCase):
    REF = REF
    CAND = CAND
    default_tolerance_s = TX_TOLERANCE_S
    msg_max_items = 20

    def test_mprs_receive(self):
        self.diff(rx_scenario(1, 60))

    def test_mprs_receive_p8n(self):
        self.diff(rx_scenario(2, 15), card=P8N)

    def test_own_locator(self):
        self.diff(locator_scenario(3, 40))

    def test_aprs_send(self):
        self.diff(tx_scenario(4, 30))

    def test_aprs_send_boundaries(self):
        self.diff(tx_boundaries())

    def test_mprs_receive_lon_180(self):
        self.diff(rx_boundaries())


if __name__ == "__main__":
    unittest.main()
