#!/usr/bin/env python3
"""
EPROM image for the ROM window bench test (firmware built with
-DBANK_TEST, see bank_test in r58.s; notes/hybrid-plan.md Phase 3):
the 64 KB firmware image with file 0x8000-0xBFFF, bank 2 (EPROM0 chip
0x8000, RS=1 RA14=0), filled with 0x5A: bank_test expects its byte sum to
be BANK2_SUM = 0x8000. A different sum shows which page the window really
showed: bank 1's sum (RA14 does not select), 0xC000 (an erased page).

    banktest.py build-banktest/r58.bin r58-banktest.bin
"""
import sys


def main():
    img = open(sys.argv[1], "rb").read()
    if len(img) != 0x10000:
        sys.exit("banktest.py: expected a 64 KB image")
    if img[0x8000:0xC000] != b"\xff" * 0x4000:
        sys.exit("banktest.py: file 0x8000-0xBFFF is not empty")
    img = img[:0x8000] + b"\x5a" * 0x4000 + img[0xC000:]
    s1, s2 = sum(img[0xC000:]) & 0xFFFF, sum(img[0x8000:0xC000]) & 0xFFFF
    assert s2 == 0x8000                      # BANK2_SUM in r58.s
    if s1 in (0x8000, 0xC000, 0x0000):
        sys.exit("banktest.py: bank 1 sum 0x%04X is ambiguous" % s1)
    open(sys.argv[2], "wb").write(img)
    print("bank 1 sum 0x%04X, bank 2 sum 0x%04X" % (s1, s2))


if __name__ == "__main__":
    main()
