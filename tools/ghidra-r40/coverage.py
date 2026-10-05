#!/usr/bin/env python3
"""
Run the R40 emulator through boot, the service mode (PE1BVU's band
set-up, tests with PTT, UP/DOWN/RCL, parameter programming) and the
normal mode with an own number, and save the OR of the ROM coverage maps
(r40emu.Radio.coverage(): 1 executed, 2 entered non-sequentially, 4 call
target, 8 exception entry; the instruction length in the high nibble) for
SeedCoverage.java.

    tools/ghidra-r40/coverage.py [OUT]     (default reference/ghidra-r40/coverage.bin)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(TOP, "emu", "python"))
sys.path.insert(0, os.path.join(TOP, "emu", "tests", "r40"))
from r40emu import Radio   # noqa: E402
import roms                # noqa: E402

ROM = roms.rom()
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(TOP, "reference/ghidra-r40/coverage.bin")
total = bytearray(0x40000)


def radio(**kw):
    r = Radio(ROM, **kw)
    r.coverage()
    return r


def collect(r):
    for i, b in enumerate(r.coverage()):
        total[i] |= b


def ok(r, keys, wait=1.5):
    r.type(keys)
    r.press("OK", hold=0.3, gap=wait)


def fnc_sto(r):
    r.press("FNC")
    r.press("STO", hold=0.3, gap=1.0)


# cold boot to Error 6
r = radio()
r.run(10)
collect(r)

# service mode: band set-up, tests, PTT, keys, parameters
r = radio(service_head=True, power=False)
r.service_mode()
for t in ["18164000", "18271200", "16200000", "151", "155",
          "1043000000", "1143500000", "1244000000", "10", "11", "12"]:
    ok(r, t)
r.ptt(True)
r.run(1.0)
r.ptt(False)
r.run(0.5)
for t in ["31", "32", "33", "34"]:
    ok(r, t, wait=1.0)
    r.press("UP", hold=0.3, gap=0.5)
    r.press("DOWN", hold=0.3, gap=0.5)
    r.press("*", hold=0.3, gap=1.0)
ok(r, "36", wait=1.0)
r.press("UP", hold=0.3, gap=0.5)
r.press("RCL", hold=0.3, gap=1.0)
r.press("*", hold=0.3, gap=1.0)
for t in ["41", "42", "47", "61", "62", "63", "64", "65", "200", "201", "202"]:
    ok(r, t, wait=1.0)
    r.press("*", hold=0.3, gap=1.0)
ok(r, "70", wait=1.0)
r.type("1234")
fnc_sto(r)
ok(r, "030", wait=1.0)
for v in ("4886", "4886", "000"):
    r.type(v)
    fnc_sto(r)
ok(r, "800", wait=1.0)
r.type("325555")
fnc_sto(r)
for _ in range(5):
    r.press("UP", hold=0.3, gap=0.5)
r.press("*", hold=0.3, gap=2.0)
r.press("*", hold=0.3, gap=2.0)
nv = r.nv()
collect(r)

# normal mode with an own number: hunting, dialling, keys
r = radio(nv=nv)
r.run(20)
r.type("*55*001#")
r.press("OK", hold=0.3, gap=2.0)
for k in [(4, 4), (1, 0), (0, 4), (4, 0), (4, 1), (4, 2), (4, 3), "UP", "DOWN", "FNC", "RCL"]:
    r.press(k, hold=0.3, gap=1.0)
r.ptt(True)
r.run(1.0)
r.ptt(False)
r.run(2.0)
collect(r)

# the high nibble of an executed address: its instruction length
for a in range(len(total)):
    if total[a] & 1:
        total[a] |= r.L.r40api_oplen(r.m, a) << 4

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "wb") as f:
    f.write(total)
ex = sum(1 for b in total if b & 1)
ct = sum(1 for b in total if b & 4)
xe = sum(1 for b in total if b & 8)
print("%s: %d instructions executed, %d call targets, %d exception entries"
      % (OUT, ex, ct, xe))
