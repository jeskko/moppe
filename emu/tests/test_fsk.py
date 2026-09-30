"""
FSK (FX429) packets: receive dispatch (`packet_for_whom`) and the packets
the radio sends (call, remote config ask/enter, display-config reply,
MPRS). Packets are injected at byte level with Radio.modem_rx() (SYNC,
then the bytes); sent packets are MODEM_TX events, each prefixed with the
5-byte `packet_header` (AA AA AA C4 D7).

Formats (r58.s `packet_for_whom` ... `send_packet_buffer`): short packets
are 6 bytes + CRC, long ones 13 + CRC. CRC: reflected CCITT, init FFFF,
complemented, high byte first; an Enter-config (EC) packet seeds it with
the 8-byte `cfg_remote_passwd` first. Fields after the tag are read
nibble by nibble from `fsk_history`.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_radio import RadioTest  # noqa: E402
from helpers import nmea, with_crc, mprs_packet, REMOTE_ID, PASSWD  # noqa: E402
from r58emu import P8E, P8N  # noqa: E402

HEADER = bytes([0xAA, 0xAA, 0xAA, 0xC4, 0xD7])


def split_tx(tx):
    """MODEM_TX bytes -> list of packets (header stripped)."""
    parts = tx.split(HEADER)
    assert parts[0] == b"", tx.hex()
    return parts[1:]


class FskRx(RadioTest):
    def rx(self, pkt, t=0.3):
        self.r.take_events()
        self.r.modem_rx(pkt)
        self.r.run(t)

    def modem_tx(self):
        return split_tx(bytes(e[2] for e in self.r.take_events("MODEM_TX")))

    def test_call_for_us(self):
        """Cx packet: caller in nibbles 1-5, callee in nibbles 6-10; a
        callee equal to cfg_mycall_1 shows CALL <caller>."""
        r = self.boot()
        r.poke("cfg_mycall_1", bytes([1, 2, 3, 4, 5, 0xFF, 0xFF, 0xFF]))
        self.rx(with_crc([0xC9, 0x87, 0x65, 0x12, 0x34, 0x5F]))
        self.assertLower("CALL 98765")

    def test_call_for_someone_else(self):
        r = self.boot()
        r.poke("cfg_mycall_1", bytes([1, 2, 3, 4, 5, 0xFF, 0xFF, 0xFF]))
        self.rx(with_crc([0xC9, 0x87, 0x65, 0x12, 0x34, 0x6F]))
        self.assertLower("          ")

    def test_bad_crc_ignored(self):
        r = self.boot()
        r.poke("cfg_mycall_1", bytes([1, 2, 3, 4, 5, 0xFF, 0xFF, 0xFF]))
        pkt = bytearray(with_crc([0xC9, 0x87, 0x65, 0x12, 0x34, 0x5F]))
        pkt[-1] ^= 1
        self.rx(bytes(pkt))
        self.assertLower("          ")

    def test_display_data(self):
        """DD packet: 8 characters to the lower row for 5 s."""
        r = self.boot()
        self.rx(with_crc(b"\xDD" + b"HELLO 42" + b"\xFF" * 4))
        self.assertLower("HELLO 42  ")
        self.assertIn("PHONE", r.icons())
        r.run(6)
        self.assertLower("          ")

    def test_display_config_needs_remote_id(self):
        """DC packet (a config reply) is shown only when cfg_remote_id is
        set."""
        pkt = with_crc(b"\xDC" + b"CONFIG01" + b"\xFF" * 4)
        r = self.boot()
        self.rx(pkt)
        self.assertLower("          ")
        r.poke("cfg_remote_id", REMOTE_ID)
        self.rx(pkt)
        self.assertLower("CONFIG01  ")

    def config_radio(self):
        r = self.boot()
        r.poke("cfg_remote_id", REMOTE_ID)
        r.poke("cfg_remote_passwd", PASSWD)
        r.poke("cfg_remote_dpy_secs", 7)
        return r

    def test_config_query_replies(self):
        """AC packet (short): id, pointer. The radio keys up and sends
        the 8 bytes at the pointer in a DC packet, twice."""
        r = self.config_radio()
        a = r.addr("cfg_remote_dpy_secs")
        self.rx(with_crc(bytes([0xAC]) + REMOTE_ID + bytes([a & 0xFF, a >> 8, 0xFF])), 1.0)
        kinds = [e[1] for e in r.events]
        self.assertIn("TX_ON", kinds)
        self.assertIn("TX_OFF", kinds)
        pkts = self.modem_tx()
        self.assertEqual(len(pkts), 2)
        self.assertEqual(pkts[0], pkts[1])
        p = pkts[0]
        self.assertEqual(len(p), 15)
        self.assertEqual(p[0], 0xDC)
        self.assertEqual(p[1:9], r.peek("cfg_remote_dpy_secs", 8))
        self.assertEqual(p, with_crc(p[:13]))

    def test_config_query_other_id_ignored(self):
        r = self.config_radio()
        a = r.addr("cfg_remote_dpy_secs")
        self.rx(with_crc(bytes([0xAC, 0x35, 0x12, a & 0xFF, a >> 8, 0xFF])), 1.0)
        self.assertEqual(self.modem_tx(), [])

    def test_config_query_refuses_password(self):
        r = self.config_radio()
        a = r.addr("cfg_remote_passwd")
        self.rx(with_crc(bytes([0xAC]) + REMOTE_ID + bytes([a & 0xFF, a >> 8, 0xFF])), 1.0)
        self.assertEqual(self.modem_tx(), [])

    def enter_packet(self, a, digits):
        data = bytes(digits) + b"\xFF" * (8 - len(digits))
        return bytes([0xEC]) + REMOTE_ID + bytes([a & 0xFF, a >> 8]) + data

    def test_config_enter_sets_and_replies(self):
        """EC packet (long, CRC seeded with the password): digits for the
        menu record whose variable is at the pointer; the value is stored
        and echoed in a DC reply."""
        r = self.config_radio()
        a = r.addr("cfg_remote_dpy_secs")
        self.rx(with_crc(self.enter_packet(a, [1, 2]), PASSWD), 1.0)
        self.assertEqual(r.peek("cfg_remote_dpy_secs"), 12)
        pkts = self.modem_tx()
        self.assertEqual(len(pkts), 2)
        self.assertEqual(pkts[0][:2], bytes([0xDC, 12]))

    def test_config_enter_wrong_password(self):
        r = self.config_radio()
        a = r.addr("cfg_remote_dpy_secs")
        self.rx(with_crc(self.enter_packet(a, [1, 2]), b"87654321"), 1.0)
        self.assertEqual(r.peek("cfg_remote_dpy_secs"), 7)
        self.assertEqual(self.modem_tx(), [])

    def test_relay_to_mbus(self):
        """5x packet: its 12 nibbles, tag included, go out on MBUS."""
        r = self.boot()
        self.rx(with_crc([0x51, 0x23, 0x45, 0x67, 0x89, 0xAB]), 0.5)
        mbus = bytes(e[2] for e in r.take_events("MBUS_TX"))
        self.assertEqual(mbus, bytes([5]) + bytes(range(1, 12)))

    def test_relay_across_ring_end(self):
        """A 5x packet stored across the end of the fsk_history ring is
        relayed from the ring too (v3_Z sent the gps_history bytes that
        follow the ring instead; fixed 2026-09-28)."""
        r = self.boot()
        r.poke("fsk_hist_idx", 0xF8)
        self.rx(with_crc([0x51, 0x23, 0x45, 0x67, 0x89, 0xAB]), 0.5)
        mbus = bytes(e[2] for e in r.take_events("MBUS_TX"))
        self.assertEqual(mbus, bytes([5]) + bytes(range(1, 12)))

    def mprs_rx(self, card=P8E, mbus=0):
        self.card = card
        r = self.boot()
        r.poke("cfg_remote_dpy_secs", 5)
        r.poke("cfg_mbus_mprs", mbus)
        self.rx(mprs_packet(), 0.6)        # QRB maths: ~0.2 s on a P8N
        return r

    def test_mprs_shows_call_and_locator(self):
        """4x packet: callsign-SSID below, Maidenhead locator above, for
        cfg_remote_dpy_secs seconds (handle_mprs_packets, bank 1)."""
        for card in (P8E, P8N):
            with self.subTest(card=card):
                r = self.mprs_rx(card)
                self.assertLower("OH3XYZ-7  ")
                self.assertUpper("KP11VM")
                self.assertEqual(r.take_events("MBUS_TX"), [])
                r.run(6)
                self.assertLower("          ")

    def test_mprs_to_mbus_as_aprs(self):
        r = self.mprs_rx(mbus=1)
        mbus = bytes(e[2] for e in r.take_events("MBUS_TX"))
        self.assertEqual(mbus, b"OH3XYZ-7>APRS,RELAY,WIDE:!6130.12N/02345.67Ep\r\n")


# metres per minute of longitude by latitude degree (r58.s
# minutes_to_meters_wrt_latitude_degree)
M_PER_MIN = [1852, 1852, 1851, 1849, 1847, 1845, 1842, 1838, 1834, 1829, 1824, 1818,
             1812, 1805, 1797, 1789, 1780, 1771, 1761, 1751, 1740, 1729, 1717, 1705,
             1692, 1678, 1665, 1650, 1635, 1620, 1604, 1587, 1571, 1553, 1535, 1517,
             1498, 1479, 1459, 1439, 1419, 1398, 1376, 1354, 1332, 1310, 1287, 1263,
             1239, 1215, 1190, 1166, 1140, 1115, 1089, 1062, 1036, 1009, 981, 954,
             926, 898, 869, 841, 812, 783, 753, 724, 694, 664, 633, 603, 572, 541,
             510, 479, 448, 417, 385, 353, 322, 290, 258, 226, 194, 161, 129, 97, 65, 32]


def qrb_model(own, his):
    """distance_bearing as mprs_qrb means it: flat model, north metres
    1852 per minute, east metres by the own latitude, distance = major +
    minor * 83 / 256, 3 digits (values 0..9) and a '.' or trailing 0.
    own, his: ((deg, min, hundredths), (deg, min, hundredths)), N/E."""
    def cm(d, m, h):
        return (d * 60 + m) * 100 + h
    dlat = cm(*own[0]) - cm(*his[0])
    dlon = cm(*own[1]) - cm(*his[1])
    q, r = divmod(abs(dlat), 100)
    north = q * 1852 + r * 1852 // 100
    w = M_PER_MIN[own[0][0]]
    q, r = divmod(abs(dlon), 100)
    east = q * w + r * w // 100
    ew = east >= north
    major, minor = (east, north) if ew else (north, east)
    dist = major + minor * 83 // 256
    for b, div in ((0, 1), (1, 10), (2, 100), (3, 1000)):
        if dist < 1000 * div:
            break
    v = dist // div
    out = []
    digits = [v // 100, v // 10 % 10, v % 10]
    for k in range(3):
        if b == k:
            out.append(ord("."))
        out.append(digits[k])
    out.append(ord(".") if b == 3 else 0)
    out.append(ord(" "))
    out.append(ord("E" if dlon < 0 else "W") if ew else ord("N" if dlat < 0 else "S"))
    return bytes(out + [0xFF])


def mprs_position(call, lat, lon):
    """an MPRS packet of call at lat/lon ((deg, min, hundredths), N/E)"""
    from test_aprs_diff import pack_callsign
    return with_crc(bytes([0x40] + pack_callsign(call) + list(lat) + list(lon)))


class Qrb(RadioTest):
    """Distance and bearing of a received MPRS position (mprs_qrb). v3_Z's
    east-west metres (centiminutes_to_meters) were wrong: hundredths of a
    minute added hundredths * 655 m, and from 256 minutes of longitude
    difference on each 256 minutes added garbage (fixed 2026-09-28)."""

    OWN = ((61, 30, 0), (23, 45, 0))

    def qrb(self, his):
        r = self.boot()
        r.poke("cfg_remote_dpy_secs", 5)
        r.poke("cfg_gps_latitude", bytes([0, 6, 1, 3, 0, 0, 0, ord("N")]))
        r.poke("cfg_gps_longitude", bytes([0, 2, 3, 4, 5, 0, 0, ord("E")]))
        r.modem_rx(mprs_position("OH3XYZ", *his))
        r.run(0.8)
        return r.peek("distance_bearing", 8)

    def test_distances(self):
        for his in (((61, 30, 0), (24, 0, 13)),      # 15.13' east, hundredths
                    ((61, 35, 47), (23, 45, 0)),     # 5.47' north
                    ((61, 30, 20), (23, 45, 30)),    # a few hundred metres
                    ((60, 10, 0), (20, 0, 50)),      # 224.5' west
                    ((61, 0, 0), (18, 0, 0)),        # 345' west (256 or more)
                    ((62, 0, 0), (30, 0, 0))):       # 375' east
            with self.subTest(his=his):
                want = qrb_model(self.OWN, his)
                self.assertEqual(self.qrb(his)[:len(want)], want)       # up to EOS


class FskTx(RadioTest):
    def modem_tx(self):
        return split_tx(bytes(e[2] for e in self.r.take_events("MODEM_TX")))

    def test_call_packet(self):
        """Digits then *: a Cx packet (our cfg_mycall_1, then the digits,
        F-padded), sent three times."""
        r = self.boot()
        r.poke("cfg_mycall_1", bytes([1, 2, 3, 4, 5, 0xFF, 0xFF, 0xFF]))
        self.enter("433500")
        r.take_events()
        r.type("98765")
        r.press("*")
        r.run(1.5)
        pkts = self.modem_tx()
        self.assertEqual(pkts, [with_crc([0xC1, 0x23, 0x45, 0x98, 0x76, 0x5F])] * 3)
        self.assertLower("    433500")

    def menu_ptt(self, digits):
        r = self.boot()
        r.poke("cfg_remote_id", REMOTE_ID)
        r.poke("cfg_remote_passwd", PASSWD)
        self.enter("433500")
        r.press("E")                       # first record: tPc GE (cfg_txpwr)
        r.run(0.3)
        if digits:
            r.type(digits)
            r.run(0.2)
        r.take_events()
        r.ptt(True)
        r.run(0.3)
        r.ptt(False)
        r.run(1.0)
        return r

    def test_config_query_on_ptt_in_menu(self):
        """PTT released in the menu with nothing typed: AC packet asking
        for the current record's variable."""
        r = self.menu_ptt("")
        a = r.addr("cfg_txpwr")
        self.assertEqual(self.modem_tx(),
                         [with_crc(bytes([0xAC]) + REMOTE_ID + bytes([a & 0xFF, a >> 8, 0xFF]))])

    def test_config_enter_on_ptt_in_menu(self):
        """With digits typed: EC packet carrying them, CRC seeded with the
        password; the local value is not changed."""
        r = self.menu_ptt("200")
        a = r.addr("cfg_txpwr")
        pkt = bytes([0xEC]) + REMOTE_ID + bytes([a & 0xFF, a >> 8, 2, 0, 0]) + b"\xFF" * 5
        self.assertEqual(self.modem_tx(), [with_crc(pkt, PASSWD)])

    def test_no_config_packets_without_remote_id(self):
        r = self.boot()
        self.enter("433500")
        r.press("E")
        r.run(0.3)
        r.take_events()
        r.ptt(True)
        r.run(0.3)
        r.ptt(False)
        r.run(1.0)
        self.assertEqual(self.modem_tx(), [])

    def test_mprs_packet_round_trip(self):
        """The MPRS report a radio sends (with a GPS fix) is the packet
        the receive tests use."""
        r = self.boot()
        r.poke("cfg_report_type", 0)
        r.poke("cfg_keyup_mprs", 1)
        r.poke("cfg_mprs_callsign", b"OH3XYZ\xff\xff")
        r.poke("cfg_mprs_ssid", 7)
        r.serial_rx(0, nmea("GPRMC,123519,A,6130.12,N,02345.67,E,000.0,000.0,280926,,"))
        r.run(0.5)
        self.enter("433500")
        r.ptt(True)
        r.run(0.5)
        r.take_events()
        r.ptt(False)
        r.run(1.5)
        self.assertEqual(self.modem_tx(), [mprs_packet()])


if __name__ == "__main__":
    unittest.main()
