"""
The setup map (firmware/build/r58.setup, tools/setupmap.py): every number
in it, typed in the menu and ENT, reaches the record it names.
"""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "emu", "python"))
sys.path.insert(0, os.path.dirname(__file__))
from test_radio import RadioTest, ROM  # noqa: E402

SETUP = os.path.join(os.path.dirname(ROM), "r58.setup")
SIZE_REC = 16
LINE = re.compile(r"^ (\d+) +(..):(.{6}) ")


@unittest.skipUnless(os.path.exists(SETUP), "run `make -C firmware`")
class SetupMap(RadioTest):
    def test_every_number_reaches_its_record(self):
        lines = open(SETUP, encoding="utf-8").read().split("\n")
        recs = [m.groups() for m in map(LINE.match, lines) if m]
        self.assertGreater(len(recs), 250)
        r = self.boot()
        start = r.sym["start_menu"]
        r.press("E")
        r.run(0.3)
        for n, (num, tag, title) in enumerate(recs):
            with self.subTest(num=num, rec="%s:%s" % (tag, title)):
                r.type(num)
                r.press("E")
                r.run(0.2)
                self.assertEqual(r.peek16("menu_ptr"), start + n * SIZE_REC)


if __name__ == "__main__":
    unittest.main()
