#!/usr/bin/env python3
"""
Intel HEX (sdldz80 output) -> ROM image.

    ihx2bin.py r58.ihx r58.bin [--map r58.map --cksum rom_cksum] [--size N]

Gaps are 0xFF (unprogrammed EPROM, and what as80 left in .org gaps).  The
image runs from address 0 to the last byte written, or is padded to --size.

Bank 1 (notes/hybrid-plan.md): code linked at the CPU window 0x8000-0xBFFF
is EPROM0 0xC000-0xFFFF, so it goes to file offset +0x4000, and the image
becomes 64 KB.  Bank 2 is EPROM0 0x8000-0xBFFF; it is linked at the
virtual address 0x28000-0x2BFFF (extended linear address records), which
goes to file 0x8000.  Any other address above 0xFFFF is an error.

--bank1-sum SYM / --bank2-sum SYM store the 16-bit sum of the bank 1 / 2
page at SYM (a word; the bench test compares it with what the window
reads).
--cksum SYM sets the byte at SYM to 256 - sum(image[0 .. SYM - 1]) (as80's
.cksum(0, .)); applied last.
"""
import argparse
import re
import sys


def read_ihx(path):
    mem, upper = {}, 0
    for n, line in enumerate(open(path), 1):
        line = line.strip()
        if not line:
            continue
        if line[0] != ":":
            sys.exit("%s:%d: not Intel HEX" % (path, n))
        b = bytes.fromhex(line[1:])
        if sum(b) & 0xFF:
            sys.exit("%s:%d: checksum error" % (path, n))
        cnt, addr, typ, data = b[0], b[1] << 8 | b[2], b[3], b[4:4 + b[0]]
        if typ == 0:
            for i, v in enumerate(data):
                a = upper + addr + i
                if a in mem and mem[a] != v:
                    sys.exit("%s:%d: address 0x%X written twice" % (path, n, a))
                mem[a] = v
        elif typ == 1:
            break
        elif typ == 4:
            upper = (data[0] << 8 | data[1]) << 16
        else:
            sys.exit("%s:%d: record type %d not supported" % (path, n, typ))
    return mem


def map_symbol(path, name):
    rx = re.compile(r"^\s+([0-9A-F]{8})\s+(\S+)")
    for line in open(path):
        m = rx.match(line)
        if m and m.group(2) == name:
            return int(m.group(1), 16)
    sys.exit("%s: symbol %s not found" % (path, name))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ihx")
    ap.add_argument("bin")
    ap.add_argument("--map")
    ap.add_argument("--cksum")
    ap.add_argument("--bank1-sum")
    ap.add_argument("--bank2-sum")
    ap.add_argument("--size", type=lambda s: int(s, 0))
    a = ap.parse_args()
    mem = read_ihx(a.ihx)
    if any(0xC000 <= k < 0x10000 for k in mem):
        sys.exit("ihx2bin: data linked into RAM (0xC000-0xFFFF)")
    if any(0x8000 <= k < 0xC000 or k >= 0x10000 for k in mem):
        out = {}
        for k, v in mem.items():
            if 0x8000 <= k < 0xC000:
                k += 0x4000                     # bank 1
            elif 0x28000 <= k < 0x2C000:
                k -= 0x20000                    # bank 2
            elif k >= 0x10000:
                sys.exit("ihx2bin: address 0x%X is in no bank" % k)
            out[k] = v
        mem = out
        a.size = a.size or 0x10000
    end = max(mem) + 1 if mem else 0
    if a.size is not None:
        if end > a.size:
            sys.exit("image is 0x%X bytes, larger than --size 0x%X" % (end, a.size))
        end = a.size
    img = bytearray(b"\xff" * end)
    for k, v in mem.items():
        img[k] = v
    for sym, page in ((a.bank1_sum, 0xC000), (a.bank2_sum, 0x8000)):
        if sym:
            at = map_symbol(a.map, sym)
            v = sum(img[page:page + 0x4000]) & 0xFFFF
            img[at], img[at + 1] = v & 0xFF, v >> 8
    if a.cksum:
        at = map_symbol(a.map, a.cksum)
        img[at] = -sum(img[:at]) & 0xFF
    open(a.bin, "wb").write(img)


if __name__ == "__main__":
    main()
