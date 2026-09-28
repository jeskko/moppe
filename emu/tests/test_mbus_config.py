"""
MBUS configuration dump and load: setup menu dF:CFGSnd (`all_config_send`)
and dF:CFGGEt (`all_config_get`), both CFG_RST records confirmed with 666
and both in bank 1 with the rest of the menu.

Wire format: a banner line ending in LF, the NV length as a little-endian
word (0x1000), the NV image (0xC000-0xCFFF), then a checksum byte meant to
make the 8-bit sum of data + checksum zero.

v3_Z bug, kept (pinned by test_cfgsnd_checksum_byte_is_last_nv_byte):
CFGSnd computes the checksum in A but `putchar` sends C, so the byte after
the data is the last NV byte again. CFGGEt checks the sum properly, so it
refuses a CFGSnd dump unless the sum happens to work out; a host tool has
to recompute the checksum.

MBUS is serial channel 1 (Radio.serial_rx(1, ...), MBUS_TX events). The
emulator's event ring holds 1024 events, so long transfers are run in
short steps and the events collected as they come.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_radio import RadioTest  # noqa: E402
from test_menu_power import enter_menu  # noqa: E402
from r58emu import P8E, P8N  # noqa: E402

NV_BASE, NV_SIZE = 0xC000, 0x1000


class MbusConfig(RadioTest):
    def run_steps(self, seconds, step=0.5):
        out = []
        for _ in range(int(round(seconds / step))):
            self.r.run(step)
            out += self.r.take_events("MBUS_TX")
        return bytes(e[2] for e in out)

    def cfgsnd(self):
        r = self.r
        enter_menu(r, "825")                  # group 8, record 25: dF:CFGSnd
        self.assertUpper("CFGSnd")
        r.take_events()
        r.type("666")
        r.press("#")
        tx = bytes(e[2] for e in r.take_events("MBUS_TX"))
        return tx + self.run_steps(6.0)       # 4157 bytes, ~4.4 s

    def image(self, body, checksum=None):
        if checksum is None:
            checksum = -sum(body) & 0xFF
        return (b"R58 test image\n" + bytes([NV_SIZE & 0xFF, NV_SIZE >> 8]) +
                bytes(body) + bytes([checksum]))

    def cfgget(self, img, loading=True):
        r = self.r
        enter_menu(r, "824")                  # dF:CFGGEt
        self.assertUpper("CFGGEt")
        r.type("666")
        r.press("#")
        r.run(0.3)
        self.assertLower(" rEAdY    ")
        r.serial_rx(1, img[:3000])            # host queue: 4 KB
        r.run(0.5)
        if loading:
            self.assertLower(" LoAdinG  ")
        self.run_steps(3.5)
        r.serial_rx(1, img[3000:])
        self.run_steps(2.0)

    def test_cfgsnd_dumps_nv(self):
        for card in (P8E, P8N):
            with self.subTest(card=card):
                self.card = card
                r = self.boot()
                r.poke("cfg_remote_dpy_secs", 42)
                tx = self.cfgsnd()
                i = tx.index(b"\n") + 1
                self.assertTrue(tx.startswith(b"R58 v3_Z"), tx[:i])
                self.assertEqual(tx[i:i + 2], bytes([0x00, 0x10]))
                body = tx[i + 2:i + 2 + NV_SIZE]
                self.assertEqual(len(tx), i + 2 + NV_SIZE + 1)
                self.assertEqual(body, r.peek(NV_BASE, NV_SIZE))
                self.assertEqual(body[r.addr("cfg_remote_dpy_secs") - NV_BASE], 42)
                self.assertLower("dF   666 ?")   # back in the menu

    def test_cfgsnd_checksum_byte_is_last_nv_byte(self):
        """The v3_Z bug described in the module docstring."""
        r = self.boot()
        tx = self.cfgsnd()
        body = tx[-1 - NV_SIZE:-1]
        self.assertEqual(tx[-1], body[-1])
        self.assertNotEqual((sum(body) + tx[-1]) & 0xFF, 0,
                            "this dump would fail CFGGEt's check")

    def test_cfgsnd_needs_666(self):
        r = self.boot()
        enter_menu(r, "825")
        r.take_events()
        r.type("123")
        r.press("#")
        self.assertEqual(self.run_steps(1.0), b"")

    def test_cfgget_loads_image(self):
        r = self.boot()
        body = bytearray(r.peek(NV_BASE, NV_SIZE))
        body[r.addr("cfg_remote_dpy_secs") - NV_BASE] = 42
        self.cfgget(self.image(body))
        self.assertEqual(r.peek("cfg_remote_dpy_secs"), 42)
        self.assertLower("dF   666 ?")

    def test_cfgget_refuses_bad_checksum(self):
        r = self.boot()
        body = bytearray(r.peek(NV_BASE, NV_SIZE))
        body[r.addr("cfg_remote_dpy_secs") - NV_BASE] = 42
        self.cfgget(self.image(body, checksum=(-sum(body) + 1) & 0xFF))
        self.assertEqual(r.peek("cfg_remote_dpy_secs"), 0)

    def test_cfgget_refuses_wrong_length(self):
        r = self.boot()
        body = bytearray(r.peek(NV_BASE, NV_SIZE))
        body[r.addr("cfg_remote_dpy_secs") - NV_BASE] = 42
        img = bytearray(self.image(body))
        img[img.index(b"\n") + 2] = 0x0F      # length 0x0F00
        self.cfgget(bytes(img), loading=False)   # refused at the length word
        self.assertEqual(r.peek("cfg_remote_dpy_secs"), 0)


if __name__ == "__main__":
    unittest.main()
