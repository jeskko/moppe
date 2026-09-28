#!/usr/bin/env python3
"""
64 KB EPROM image for the ROM window bench test (firmware built with
-DBANK_TEST, see bank_test in r58.s; notes/hybrid-plan.md Phase 3).

    banktest.py build-banktest/r58.bin r58-banktest.bin

  0x0000-0x7FFF  the firmware
  0x8000-0xBFFF  0x00: the P8N-only second page (RS=1, RA14=0); should not
                 appear, and a mapping that picks it shows as "b1 8010 00"
  0xC000-0xFFFF  bank 1 = window 0x8000-0xBFFF: at 0x8000 'ld a, #0xA5 /
                 ret', from 0x8010 LO(a) ^ HI(a) ^ 0x5A for window address a
"""
import sys


def bank1():
    page = bytearray(0x4000)
    page[0:3] = bytes([0x3E, 0xA5, 0xC9])          # ld a, #0xA5 / ret
    for i in range(0x10, 0x4000):
        a = 0x8000 + i
        page[i] = (a & 0xFF) ^ (a >> 8) ^ 0x5A
    return bytes(page)


def main():
    fw = open(sys.argv[1], "rb").read()
    if len(fw) > 0x8000:
        sys.exit("banktest.py: firmware is larger than 32 KB")
    img = fw.ljust(0x8000, b"\xff") + bytes(0x4000) + bank1()
    open(sys.argv[2], "wb").write(img)


if __name__ == "__main__":
    main()
