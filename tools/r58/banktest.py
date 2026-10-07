#!/usr/bin/env python3
"""
EPROM image for the ROM window bench test (firmware built with
-DBANK_TEST, see bank_test in r58.s; notes/hybrid-plan.md Phase 3): the
64 KB firmware image, with bank 1 (EPROM0 chip 0xC000) and bank 2 (chip
0x8000) each holding a test routine and their byte sums patched in by
ihx2bin.py.  The display shows the sum a wrong window read, so the two
pages and an erased one (0xC000) must sum differently; this checks that
and prints the sums.

    banktest.py build-banktest/r58.bin r58-banktest.bin
"""
import sys

ERASED = 0x4000 * 0xFF & 0xFFFF


def main():
    img = open(sys.argv[1], "rb").read()
    if len(img) != 0x10000:
        sys.exit("banktest.py: expected a 64 KB image")
    s1, s2 = sum(img[0xC000:]) & 0xFFFF, sum(img[0x8000:0xC000]) & 0xFFFF
    if len({s1, s2, ERASED}) != 3:
        sys.exit("banktest.py: page sums 0x%04X 0x%04X are ambiguous" % (s1, s2))
    open(sys.argv[2], "wb").write(img)
    print("bank 1 sum 0x%04X, bank 2 sum 0x%04X" % (s1, s2))


if __name__ == "__main__":
    main()
