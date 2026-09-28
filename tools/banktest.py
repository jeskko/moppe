#!/usr/bin/env python3
"""
EPROM image for the ROM window bench test (firmware built with
-DBANK_TEST, see bank_test in r58.s; notes/hybrid-plan.md Phase 3):
the 64 KB firmware image with file 0x8000-0xBFFF, the P8N-only second page
(RS=1, RA14=0), filled with zeros, so that a window showing that page
instead of bank 1 reads as sum 0000.

    banktest.py build-banktest/r58.bin r58-banktest.bin
"""
import sys


def main():
    img = open(sys.argv[1], "rb").read()
    if len(img) != 0x10000:
        sys.exit("banktest.py: expected a 64 KB image")
    if img[0x8000:0xC000] != b"\xff" * 0x4000:
        sys.exit("banktest.py: file 0x8000-0xBFFF is not empty")
    img = img[:0x8000] + bytes(0x4000) + img[0xC000:]
    open(sys.argv[2], "wb").write(img)
    print("bank 1 sum 0x%04X" % (sum(img[0xC000:]) & 0xFFFF))


if __name__ == "__main__":
    main()
