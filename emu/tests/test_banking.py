"""
ROM window decode at 0x8000-0xBFFF, the basis of the banked-EPROM plan
(notes/hybrid-plan.md): synthetic ROM images (Window), and the firmware's
bank switching with code running from bank 1 (BankedFirmware).

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

    def test_p8n_extra_page(self):
        r = self.radio(P8N)
        self.assertEqual(self.window(r, RS | BIT3), (0x12, 0x12))

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

# Bank 1 test routine, put in the unused top of bank 1 (window 0xBF00 =
# EPROM0 file offset 0xFF00): spin ~0.3 s kicking the watchdog, store a
# mark in junk, return 0x5A in A.
TEST_AT = 0xBF00


def bank1_code(junk, loops=60000):
    code = bytes([0x01, loops & 0xFF, loops >> 8,       # ld bc, #loops
                  0xD3, 0x90,                           # 1: out (WD), a
                  0x0B,                                 # dec bc
                  0x78, 0xB1,                           # ld a, b / or c
                  0x20, 0xF9,                           # jr nz, 1b
                  0x3E, 0xA5,                           # ld a, #0xA5
                  0x32, junk & 0xFF, junk >> 8,         # ld (junk), a
                  0x3E, 0x5A,                           # ld a, #0x5A
                  0xC9])                                # ret
    return code + b"\xff" * (0x100 - len(code))


class BankedFirmware(unittest.TestCase):
    """Phase 2: set_bank / SDCC's ___sdcc_bcall_ehl run code in bank 1
    while the interrupts keep redrawing the display and scanning keys."""

    def radio(self, card):
        sys.path.insert(0, os.path.dirname(__file__))
        from test_radio import make_sane_nv
        fw = open(os.path.join(FW, "r58.bin"), "rb").read()
        lst = os.path.join(FW, "r58.map")
        sym = Radio(os.path.join(FW, "r58.bin"), lst).sym
        img = fw.ljust(0x10000, b"\xff")
        assert img[0xFF00:] == b"\xff" * 0x100, "bank 1 top is not free"
        img = img[:0xFF00] + bank1_code(sym["junk"])
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

    def check_bank_call(self, card):
        r = self.radio(card)
        up0, lo0 = r.display()
        hist0 = r.peek("dtmf_hist_idx")
        r.breakpoint("mainloop")
        self.assertEqual(r.run(1.0), "break")
        r.breakpoint("mainloop", False)
        ret = r.call("___sdcc_bcall_ehl", de=0x0001, hl=TEST_AT)

        r.run(0.1)                      # inside the banked loop
        self.assertEqual(r.peek("cur_bank"), 1)
        self.assertEqual(r.latches()["out2"] & 0x0F, 0x0D)    # RS|RA14|bit3
        self.assertEqual(r.peek16("ctcss_dec_src"), r.sym["ctcss_idle_sample"])
        # the soft interrupt redraws the display (here on request, as the
        # hook/light code in systick does) and scans the keypad meanwhile
        r.poke("segments", bytes(64))
        r.poke("sir", r.peek("sir") | 1 << r.sym["DPYSIR"])
        r.key_down("5")
        r.run(0.1)
        self.assertEqual(r.display_raw()[:16], bytes(16))
        self.assertEqual(r.latches()["out2"] & 0x0F, 0x0D)
        self.assertNotEqual(r.peek("junk"), 0xA5)  # still looping
        r.key_up()

        r.breakpoint(ret)
        self.assertEqual(r.run(1.0), "break")      # returned to the caller
        c = r.cpu()
        self.assertEqual(c["af"] >> 8, 0x5A)        # A comes back
        self.assertEqual(r.peek("junk"), 0xA5)
        self.assertEqual(r.peek("cur_bank"), 0)
        self.assertEqual(r.latches()["out2"] & 0x0F, 0x08)
        self.assertEqual(r.peek16("ctcss_dec_src"), 0x8000)
        # ROM bytes in the window were not taken for DTMF input
        self.assertEqual(r.peek("dtmf_hist_idx"), hist0)
        r.breakpoint(ret, False)
        r.run(0.5)                                  # and the radio goes on:
        self.assertEqual(r.display()[1], "5_        ")   # the key typed meanwhile
        self.assertEqual([e for e in r.events if e[1] == "WDRESET"], [])

    def test_bank_call_p8e(self):
        self.check_bank_call(P8E)

    def test_bank_call_p8n(self):
        self.check_bank_call(P8N)


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
                self.assertIn(r.display()[1].strip().upper(), ("B1  PASS", "B1  PA55"), (card, cu))

    def test_wrong_page_shows_its_sum(self):
        # as if RS|RA14 picked the P8N-only page (zeros) instead of 0xC000
        img = self.image()
        img = img[:0xC000] + img[0x8000:0xC000]
        r = self.boot(P8E, image=img)
        self.assertEqual(r.display()[1], "b1 0000 00")

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


if __name__ == "__main__":
    unittest.main()
