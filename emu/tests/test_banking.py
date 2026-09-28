"""
ROM window decode at 0x8000-0xBFFF, the basis of the banked-EPROM plan
(notes/hybrid-plan.md).  Uses synthetic ROM images, not the firmware.

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
from r58emu import Radio, P8E, P8N  # noqa: E402

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


if __name__ == "__main__":
    unittest.main()
