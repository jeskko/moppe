"""
ROM window decode at 0x8000-0xBFFF, the basis of the banked-EPROM plan
(notes/hybrid-plan.md): synthetic ROM images (Window), and the firmware's
bank switching with code running from banks 1 and 2 (BankedFirmware).

P8E (schematic): RS=1 -> EPROM0 chip 0xC000-0xFFFF; RS=0 -> EPROM1 page
  (A14,A15,A16 = OUT2 bits 0,1,3).
P8N (service manual): RS=1 -> EPROM0 chip 0x8000 (RA14=0) / 0xC000 (RA14=1);
  RS=0 -> EPROM1 page RA15:RA14.
Portable "high page": OUT2 = RS|RA14|bit3 selects EPROM0 chip 0xC000 on both.
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "python"))
from r58emu import Radio, P8E, P8N, CU53AN, CU58AF  # noqa: E402

RA14, RA15, RS, BIT3 = 0x01, 0x02, 0x04, 0x08
OUT2 = 0x80


def image(size, tag):
    """ROM image whose every 16 KB page is filled with tag+page."""
    return bytes((tag + a // 0x4000) & 0xff for a in range(size))


class Window(unittest.TestCase):
    def radio(self, card, rom1=None):
        d = tempfile.mkdtemp()
        p0 = os.path.join(d, "rom0.bin")
        with open(p0, "wb") as f:
            f.write(image(0x10000, 0x10))          # pages 0x10..0x13
        r = Radio(p0, card=card)
        if rom1:
            p1 = os.path.join(d, "rom1.bin")
            with open(p1, "wb") as f:
                f.write(image(rom1, 0x40))         # pages 0x40..
            r.load_rom1(p1)
        r.multiboard(0x5A)
        return r

    def window(self, r, out2):
        r.io_write(OUT2, out2)
        return r.peek(0x8123), r.peek(0xBFFF)

    def test_portable_high_page(self):
        for card in (P8E, P8N):
            r = self.radio(card)
            self.assertEqual(self.window(r, RS | RA14 | BIT3), (0x13, 0x13), card)

    def test_fixed_region_unaffected(self):
        for card in (P8E, P8N):
            r = self.radio(card)
            r.io_write(OUT2, RS | RA14 | BIT3)
            self.assertEqual((r.peek(0x0000), r.peek(0x4000), r.peek(0x7FFF)),
                             (0x10, 0x11, 0x11))

    def test_second_eprom0_page(self):
        """RS with RA14=0: EPROM0 chip 0x8000, on both cards (the P8E per
        the user's schematic trace, 2026-09-28)."""
        for card in (P8E, P8N):
            r = self.radio(card)
            self.assertEqual(self.window(r, RS | BIT3), (0x12, 0x12), card)

    def test_multiboard_when_socket_holds_it(self):
        for card in (P8E, P8N):
            r = self.radio(card)
            self.assertEqual(self.window(r, BIT3), (0x5A, 0x5A))

    def test_eprom1_pages(self):
        r = self.radio(P8E, rom1=0x20000)
        for page in range(8):
            out2 = ((page & 3) | ((page & 4) << 1)) | 0    # bit3 = A16
            self.assertEqual(self.window(r, out2)[0], 0x40 + page)
        r = self.radio(P8N, rom1=0x10000)
        for page in range(4):
            self.assertEqual(self.window(r, page | BIT3)[0], 0x40 + page)


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FW = os.path.join(ROOT, "firmware", "build")

# Test routines, put in the unused tops of bank 1 (window 0xBF00 = EPROM0
# file offset 0xFF00) and bank 2 (window 0xBF00 = file 0xBF00).
TEST_AT = 0xBF00
NEST_AT = 0xBF80
PAGE = {1: 0xC000, 2: 0x8000}           # file offset of each bank's page
OUT2_BANK = {0: 0x08, 1: 0x0D, 2: 0x0C}  # OUT2 bits 3..0: bit3, RS, RA14


def spin_code(junk, loops=60000):
    """Spin ~0.3 s kicking the watchdog, store a mark in junk, return 0x5A
    in A."""
    return bytes([0x01, loops & 0xFF, loops >> 8,       # ld bc, #loops
                  0xD3, 0x90,                           # 1: out (WD), a
                  0x0B,                                 # dec bc
                  0x78, 0xB1,                           # ld a, b / or c
                  0x20, 0xF9,                           # jr nz, 1b
                  0x3E, 0xA5,                           # ld a, #0xA5
                  0x32, junk & 0xFF, junk >> 8,         # ld (junk), a
                  0x3E, 0x5A,                           # ld a, #0x5A
                  0xC9])                                # ret


def nest_code(sym):
    """Bank 1: call the bank 2 spin routine through a far2_ stub (here in
    bank 1 too), then return A = 0x10 + the bank it came back to."""
    b2, cb, stub = sym["bank2_call"], sym["cur_bank"], NEST_AT + 9
    return bytes([0xCD, stub & 0xFF, stub >> 8,         # call stub
                  0x3A, cb & 0xFF, cb >> 8,             # ld a, (cur_bank)
                  0xC6, 0x10,                           # add a, #0x10
                  0xC9,                                 # ret
                  0xCD, b2 & 0xFF, b2 >> 8,             # stub: call bank2_call
                  TEST_AT & 0xFF, TEST_AT >> 8])        # .dw TEST_AT


class BankedFirmware(unittest.TestCase):
    """set_bank / SDCC's ___sdcc_bcall_ehl / bank2_call run code in banks 1
    and 2 while the interrupts keep redrawing the display and scanning
    keys; calls nest and return to the caller's bank."""

    def radio(self, card):
        sys.path.insert(0, os.path.dirname(__file__))
        from test_radio import make_sane_nv
        fw = open(os.path.join(FW, "r58.bin"), "rb").read()
        lst = os.path.join(FW, "r58.map")
        sym = Radio(os.path.join(FW, "r58.bin"), lst).sym
        img = bytearray(fw.ljust(0x10000, b"\xff"))
        for at, code in ((PAGE[1] + 0x3F00, spin_code(sym["junk"])),
                         (PAGE[1] + 0x3F80, nest_code(sym)),
                         (PAGE[2] + 0x3F00, spin_code(sym["junk"]))):
            assert img[at:at + 0x80] == b"\xff" * 0x80, "bank top 0x%X is not free" % at
            img[at:at + len(code)] = code
        d = tempfile.mkdtemp()
        rom = os.path.join(d, "rom64.bin")
        with open(rom, "wb") as f:
            f.write(img)
        r = Radio(rom, lst, card=card, nv=make_sane_nv(card))
        r.multiboard(0)                 # a multiboard with no DTMF tone
        r.run(2.5)
        r.type("433500")
        r.press("#")
        r.run(0.3)
        return r

    def check_bank_call(self, card, bank, at=TEST_AT, spin_bank=None, a_back=0x5A):
        """Call bank:at from mainloop; the spin routine runs in spin_bank."""
        spin_bank = spin_bank or bank
        r = self.radio(card)
        hist0 = r.peek("dtmf_hist_idx")
        r.breakpoint("mainloop")
        self.assertEqual(r.run(1.0), "break")
        r.breakpoint("mainloop", False)
        ret = r.call("___sdcc_bcall_ehl", de=bank, hl=at)

        r.run(0.1)                      # inside the banked loop
        self.assertEqual(r.peek("cur_bank"), spin_bank)
        self.assertEqual(r.latches()["out2"] & 0x0F, OUT2_BANK[spin_bank])
        self.assertEqual(r.peek16("ctcss_dec_src"), r.sym["ctcss_idle_sample"])
        # the soft interrupt redraws the display (here on request, as the
        # hook/light code in systick does) and scans the keypad meanwhile
        r.poke("segments", bytes(64))
        r.poke("sir", r.peek("sir") | 1 << r.sym["DPYSIR"])
        r.key_down("5")
        r.run(0.1)
        self.assertEqual(r.display_raw()[:16], bytes(16))
        self.assertEqual(r.latches()["out2"] & 0x0F, OUT2_BANK[spin_bank])
        self.assertNotEqual(r.peek("junk"), 0xA5)  # still looping
        r.key_up()

        r.breakpoint(ret)
        self.assertEqual(r.run(1.0), "break")      # returned to the caller
        c = r.cpu()
        self.assertEqual(c["af"] >> 8, a_back)      # A comes back
        self.assertEqual(r.peek("junk"), 0xA5)
        self.assertEqual(r.peek("cur_bank"), 0)
        self.assertEqual(r.latches()["out2"] & 0x0F, OUT2_BANK[0])
        self.assertEqual(r.peek16("ctcss_dec_src"), 0x8000)
        # ROM bytes in the window were not taken for DTMF input
        self.assertEqual(r.peek("dtmf_hist_idx"), hist0)
        r.breakpoint(ret, False)
        r.run(0.5)                                  # and the radio goes on:
        self.assertEqual(r.display()[1], "5_        ")   # the key typed meanwhile
        self.assertEqual([e for e in r.events if e[1] == "WDRESET"], [])

    def test_bank_call_p8e(self):
        self.check_bank_call(P8E, 1)

    def test_bank_call_p8n(self):
        self.check_bank_call(P8N, 1)

    def test_bank2_call_p8e(self):
        self.check_bank_call(P8E, 2)

    def test_bank2_call_p8n(self):
        self.check_bank_call(P8N, 2)

    def test_nested_bank1_to_bank2(self):
        # bank 1 calls bank 2 through bank2_call and gets bank 1 back
        for card in (P8E, P8N):
            self.check_bank_call(card, 1, at=NEST_AT, spin_bank=2, a_back=0x11)


FW_C = os.path.join(ROOT, "firmware", "build-c")


@unittest.skipUnless(os.path.exists(os.path.join(FW_C, "r58.bin")), "run `make -C firmware C=1`")
class BankedC(unittest.TestCase):
    """C code in bank 2 (c/fsk.c, #pragma bank 2) runs with bank 2
    selected, entered through a far_ stub, and returns to bank 0."""

    def test_fsk_dispatch_runs_in_bank2(self):
        sys.path.insert(0, os.path.dirname(__file__))
        from test_radio import make_sane_nv
        from test_fsk import with_crc
        for card in (P8E, P8N):
            r = Radio(os.path.join(FW_C, "r58.bin"), os.path.join(FW_C, "r58.map"),
                      card=card, nv=make_sane_nv(card))
            r.run(2.5)
            self.assertGreaterEqual(r.sym["_packet_for_whom"], 0x8000)
            self.assertLess(r.sym["_packet_for_whom"], 0xC000)
            r.breakpoint("_packet_for_whom")
            r.modem_rx(with_crc([0x51, 0x23, 0x45, 0x67, 0x89, 0xAB]))
            self.assertEqual(r.run(0.5), "break")
            self.assertEqual(r.peek("cur_bank"), 2)
            self.assertEqual(r.latches()["out2"] & 0x0F, OUT2_BANK[2])
            r.breakpoint("_packet_for_whom", False)
            r.run(0.5)
            self.assertEqual(r.peek("cur_bank"), 0)
            mbus = bytes(e[2] for e in r.take_events("MBUS_TX"))
            self.assertEqual(mbus, bytes([5]) + bytes(range(1, 12)))


    def test_repeater_runs_in_bank2(self):
        """c/rptr.c: far_repeater_run enters bank 2 once per systick in
        repeater mode; the CW waits in between run in bank 0."""
        sys.path.insert(0, os.path.dirname(__file__))
        from test_radio import make_sane_nv
        r = Radio(os.path.join(FW_C, "r58.bin"), os.path.join(FW_C, "r58.map"),
                  card=P8E, nv=make_sane_nv(P8E))
        r.run(2.5)
        self.assertGreaterEqual(r.sym["_repeater_run"], 0x8000)
        r.poke("cfg_function", 1)
        r.breakpoint("_repeater_run")
        self.assertEqual(r.run(0.5), "break")
        self.assertEqual(r.peek("cur_bank"), 2)
        self.assertEqual(r.latches()["out2"] & 0x0F, OUT2_BANK[2])
        r.breakpoint("_repeater_run", False)
        r.run(0.3)
        self.assertEqual(r.peek("repeater_state"), 1)     # ST_BOOT


    def test_gps_runs_in_bank2(self):
        """c/gps.c: a complete GPRMC sentence is parsed in bank 2."""
        sys.path.insert(0, os.path.dirname(__file__))
        from test_radio import make_sane_nv
        from test_signalling import nmea
        r = Radio(os.path.join(FW_C, "r58.bin"), os.path.join(FW_C, "r58.map"),
                  card=P8E, nv=make_sane_nv(P8E))
        r.run(2.5)
        r.breakpoint("_gps_process_sentence")
        r.serial_rx(0, nmea("GPRMC,123519,A,6130.12,N,02345.67,E,000.0,000.0,280926,,"))
        self.assertEqual(r.run(0.5), "break")
        self.assertEqual(r.peek("cur_bank"), 2)
        r.breakpoint("_gps_process_sentence", False)
        r.run(0.3)
        self.assertEqual(r.peek("cur_bank"), 0)
        self.assertEqual(r.peek("gps_valid_seconds"), 5)


    def test_mprs_receive_runs_in_bank2(self):
        """c/aprs.c: a received MPRS position is handled in bank 2 (called
        by c/fsk.c there, no bank switch between them)."""
        sys.path.insert(0, os.path.dirname(__file__))
        from test_radio import make_sane_nv
        from test_fsk import mprs_packet
        r = Radio(os.path.join(FW_C, "r58.bin"), os.path.join(FW_C, "r58.map"),
                  card=P8E, nv=make_sane_nv(P8E))
        r.run(2.5)
        r.breakpoint("_handle_mprs_packets")
        r.modem_rx(mprs_packet())
        self.assertEqual(r.run(0.5), "break")
        self.assertEqual(r.peek("cur_bank"), 2)
        r.breakpoint("_handle_mprs_packets", False)
        r.run(0.6)
        self.assertEqual(r.peek("cur_bank"), 0)


BANKTEST = os.path.join(ROOT, "firmware", "build-banktest")


@unittest.skipUnless(os.path.exists(os.path.join(BANKTEST, "r58-banktest.bin")),
                     "run `make -C firmware banktest`")
class BenchTestRom(unittest.TestCase):
    """The ROM window bench test for real boards (make banktest): what it
    shows when the window works, and when it maps the wrong thing."""

    def boot(self, card, cu=CU53AN, image=None):
        sys.path.insert(0, os.path.dirname(__file__))
        from test_radio import make_sane_nv
        rom = os.path.join(BANKTEST, "r58-banktest.bin")
        if image is not None:
            rom = os.path.join(tempfile.mkdtemp(), "rom.bin")
            with open(rom, "wb") as f:
                f.write(image)
        r = Radio(rom, os.path.join(BANKTEST, "r58.map"), card=card, cu=cu,
                  nv=make_sane_nv(card, cu))
        r.run(4.0)
        self.assertEqual([e for e in r.events if e[1] == "WDRESET"], [])
        return r

    def image(self):
        return open(os.path.join(BANKTEST, "r58-banktest.bin"), "rb").read()

    def test_pass(self):
        for card in (P8E, P8N):
            for cu in (CU53AN, CU58AF):
                r = self.boot(card, cu)
                # (on the CU53AN's 7-segment digits S and 5 look the same)
                self.assertIn(r.display()[1].strip().upper(), ("B1B2 PASS", "B1B2 PA55"), (card, cu))

    def test_wrong_page_shows_its_sum(self):
        # as if RS|RA14 picked the other page (bank 2) instead of 0xC000
        img = self.image()
        s2 = sum(img[0x8000:0xC000]) & 0xFFFF
        img = img[:0xC000] + img[0x8000:0xC000]
        r = self.boot(P8E, image=img)
        self.assertEqual(r.display()[1].upper(), "B1 %04X 00" % s2)

    def test_bank2_wrong_page_shows_its_sum(self):
        # as if RS alone showed chip 0xC000 again (RA14 ignored): bank 2
        # reads bank 1's sum
        img = self.image()
        s1 = sum(img[0xC000:]) & 0xFFFF
        img = img[:0x8000] + img[0xC000:] + img[0xC000:]
        r = self.boot(P8N, image=img)
        self.assertEqual(r.display()[1].upper(), "B2 %04X 00" % s1)

    def test_routine_result_shown(self):
        img = bytearray(self.image())
        sym = Radio(os.path.join(BANKTEST, "r58-banktest.bin"),
                    os.path.join(BANKTEST, "r58.map")).sym
        at = sym["bank_test_ping"] + 0x4000 + 1        # ld a, #0xA5
        self.assertEqual(img[at], 0xA5)
        img[at] = 0xC3
        img[0xFFFF] -= 0xC3 - 0xA5              # (0xFF there) keep the sum
        r = self.boot(P8N, image=bytes(img))
        self.assertEqual(r.display()[1], "b1 CA11 C3")

    def test_bank2_routine_result_shown(self):
        img = bytearray(self.image())
        sym = Radio(os.path.join(BANKTEST, "r58-banktest.bin"),
                    os.path.join(BANKTEST, "r58.map")).sym
        at = sym["bank_test_ping2"] + 1                # ld a, #0x5A (file = window)
        self.assertEqual(img[at], 0x5A)
        img[at] = 0xC3
        img[0xBFFF] -= 0xC3 - 0x5A              # (0xFF there) keep the sum
        r = self.boot(P8E, image=bytes(img))
        self.assertEqual(r.display()[1], "b2 CA11 C3")


class BankDuty(unittest.TestCase):
    """Bank 1 hides the multiboard (DTMF decoder, CTCSS DSP decoder skip
    or read zeros meanwhile), so code polled from mainloop must not sit in
    bank 1: guards like far_repeater_run's once-per-systick check keep the
    share small. And nothing in bank 1 may be reachable from interrupts."""

    def test_nothing_in_banks_reachable_from_interrupts(self):
        import subprocess
        root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        for first, after in (("bank1_start", "bank1_end"), ("bank2_start", "bank2_end")):
            res = subprocess.run([sys.executable, os.path.join(root, "tools", "isrreach.py"),
                                  os.path.join(root, "firmware", "r58.s"), first, after],
                                 capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, first + ": " + res.stdout + res.stderr)

    def share_in_bank1(self, r, seconds, step=0.0007):
        n = [0, 0]
        for _ in range(int(seconds / step)):
            r.run(step)
            n[1 if r.peek("cur_bank") else 0] += 1
        return n[1] / sum(n)

    def test_idle_and_repeater_idle_stay_in_bank0(self):
        from test_radio import make_sane_nv, ROM, LST
        r = Radio(ROM, LST, card=P8E, nv=make_sane_nv(P8E))
        r.run(2.5)
        self.assertLess(self.share_in_bank1(r, 0.3), 0.05, "normal mode")
        r.poke("cfg_function", 1)               # repeater
        r.run(0.2)
        r.poke("repeater_timer_other", bytes([1, 0]))   # skip the 60 s boot
        r.run(1.2)
        self.assertLess(self.share_in_bank1(r, 0.3), 0.05, "repeater idle")


if __name__ == "__main__":
    unittest.main()
