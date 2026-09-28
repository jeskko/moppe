"""
Remote configuration over RF, end to end: two emulated radios on one
simulated channel (rflink.Link). The operator's radio A, in the setup
menu, asks for or sets a record on the target radio B with PTT; B answers
with a DC packet that A's menu shows in place of its own value for
display_buffer_time (5 s). Packet formats and the single-radio cases:
test_fsk.py.

Both radios need the same cfg_remote_id (A addresses B with its own id);
setting a value also needs the same cfg_remote_passwd (it seeds the Enter
packet's CRC). Asking does not.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_radio import RadioTest, make_sane_nv, ROM, LST  # noqa: E402
from r58emu import Radio, P8E, P8N  # noqa: E402
from rflink import Link  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RELEASE = (os.path.join(ROOT, "firmware", "build-release", "r58.bin"),
           os.path.join(ROOT, "firmware", "build-release", "r58.map"))
ID = bytes([0x34, 0x12])
PASSWD = b"12345678"


class RemoteConfig(RadioTest):
    def radio(self, card=P8E, freq="433500", rid=ID, passwd=PASSWD, rom=(ROM, LST)):
        r = Radio(rom[0], rom[1], card=card, nv=make_sane_nv(card))
        r.run(2.5)
        r.poke("cfg_remote_id", rid)
        r.poke("cfg_remote_passwd", passwd)
        r.type(freq)
        r.press("#")
        r.run(0.3)
        return r

    def pair(self, b_card=P8E, a_rom=(ROM, LST), **b_kw):
        a = self.radio(rom=a_rom)
        b = self.radio(card=b_card, **b_kw)
        b.poke("cfg_txpwr", 3)
        self.r = a
        self.b = b
        self.link = Link(a, b)
        a.press("E")                  # first record: tPc GE (cfg_txpwr)
        self.link.run(0.3)
        self.assertLower("GE       0")
        return a, b

    def ptt(self, a):
        a.ptt(True)
        self.link.run(0.3)
        a.ptt(False)
        self.link.run(1.5)

    def senders(self):
        return [i for _, i, _ in self.link.log]

    def tearDown(self):
        super().tearDown()
        b = getattr(self, "b", None)
        if b is not None:
            self.assertEqual([e for e in b.events if e[1] == "WDRESET"], [])

    def test_ask_shows_remote_value(self):
        a, b = self.pair()
        self.ptt(a)
        self.assertEqual(self.senders(), [0, 1, 1])   # AC, then DC twice
        self.assertLower("GE       3")                # B's value
        self.link.run(5.0)
        self.assertLower("GE       0")                # back to A's own

    def test_enter_sets_remote_value(self):
        a, b = self.pair()
        a.type("5")
        self.link.run(0.2)
        self.ptt(a)
        self.assertEqual(self.senders(), [0, 1, 1])   # EC, then DC twice
        self.assertEqual(b.peek("cfg_txpwr"), 5)
        self.assertEqual(a.peek("cfg_txpwr"), 0, "A's own value untouched")
        self.assertLower("GE       5")

    def test_wrong_password_can_ask_but_not_set(self):
        a, b = self.pair(passwd=b"87654321")
        self.ptt(a)
        self.assertLower("GE       3")
        self.link.run(5.0)
        self.link.log.clear()
        a.type("5")
        self.link.run(0.2)
        self.ptt(a)
        self.assertEqual(self.senders(), [0], "B ignores the Enter packet")
        self.assertEqual(b.peek("cfg_txpwr"), 3)

    def test_other_remote_id_ignored(self):
        a, b = self.pair(rid=bytes([0x35, 0x12]))
        self.ptt(a)
        self.assertEqual(self.senders(), [0])
        self.assertLower("GE       0")

    def test_other_frequency_not_heard(self):
        a, b = self.pair(freq="433525")
        self.ptt(a)
        self.assertEqual(self.senders(), [0])
        self.assertLower("GE       0")

    def test_p8n_target(self):
        a, b = self.pair(b_card=P8N)
        a.type("5")
        self.link.run(0.2)
        self.ptt(a)
        self.assertEqual(b.peek("cfg_txpwr"), 5)
        self.assertLower("GE       5")

    def test_release_operator_configures_this_build(self):
        """Interop: an operator radio on the released v3_Z firmware sets a
        value on a radio running this build."""
        if not os.path.exists(RELEASE[0]):
            self.skipTest("run `make -C firmware verify` for build-release")
        a, b = self.pair(a_rom=RELEASE)
        a.type("5")
        self.link.run(0.2)
        self.ptt(a)
        self.assertEqual(b.peek("cfg_txpwr"), 5)
        self.assertLower("GE       5")


if __name__ == "__main__":
    unittest.main()
