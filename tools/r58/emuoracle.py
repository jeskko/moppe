#!/usr/bin/env python3
"""
Emulator oracle: run fixed scenarios on both cards and print one line per
phase with a digest of everything observable (CPU registers, all 64 KB of
memory, events, audio edges, polled tones).  For checking that an
emulator change (emu/*.c) keeps behaviour bit for bit: run it with the
old and the new library and compare.

    cp emu/libr58.so /tmp/libr58-old.so          # before the change
    R58_LIB=/tmp/libr58-old.so python3 tools/r58/emuoracle.py > old.txt
    make -C emu && python3 tools/r58/emuoracle.py > new.txt
    diff old.txt new.txt

Scenarios: boot, frequency entry, TX with CTCSS and DTMF (audio
captured), an APRS report (audio), a 60 s idle, a repeater CW ID with
tone polling, the scanner with and without a signal, a power cycle (the
clock jump of an unpowered run).  It caught a missing 8254 sync in the
lazy-clocking change of 2026-10-01 (emu/notes/r58.md).
"""
import hashlib
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tests", "r58"))
from test_radio import make_sane_nv, ROM, LST  # noqa: E402
from r58emu import Radio, P8E, P8N, AD_SQL  # noqa: E402


def digest(r, label):
    h = hashlib.sha256()
    h.update(repr(r.cpu()).encode())
    h.update(bytes(r.peek(0, 0x10000)))
    h.update(repr(r.take_events()).encode())
    h.update(repr(r.time).encode())
    print(label, h.hexdigest()[:16], "%.6f" % r.time)


def audio(r, label):
    e = r.audio_edges()
    print(label, "audio", len(e), hashlib.sha256(repr(e).encode()).hexdigest()[:16])


def scenarios(card):
    r = Radio(ROM, LST, card=card, nv=make_sane_nv(card))
    r.run(2.5)
    digest(r, "boot")
    r.type("433500")
    r.press("#")
    r.run(0.3)
    digest(r, "freq")
    r.poke("cfg_ctcss_tx_hz", 5)
    r.audio_start()
    r.ptt(True)
    r.run(1.0)
    audio(r, "ctcss")
    digest(r, "ctcss tx")
    r.type("123#")
    r.run(0.5)
    audio(r, "dtmf")
    digest(r, "dtmf tx")
    r.ptt(False)
    r.run(0.5)
    audio(r, "after")
    digest(r, "rx")
    r.poke("cfg_report_type", 1)
    r.poke("cfg_keyup_mprs", 1)
    r.poke("cfg_mprs_callsign", b"OH3XYZ\xff\xff")
    r.ptt(True)
    r.run(0.5)
    r.ptt(False)
    r.run(1.5)
    audio(r, "aprs")
    digest(r, "aprs")
    r.audio_start(0)
    r.run(60.0)
    digest(r, "idle 60")
    r.poke("cfg_function", 1)
    r.poke("repeater_cfg_access_method", 1)
    r.run(0.2)
    r.poke("repeater_timer_other", bytes([1, 0]))
    r.run(1.2)
    digest(r, "rptr idle")
    r.poke("cfg_squelch_level", 127)
    r.adc(AD_SQL, 0xC0)
    r.run(0.35)
    r.adc(AD_SQL, 0)
    tones = []
    for _ in range(300):
        r.run(0.01)
        tones.append(r.tone_hz())
    print("tones", hashlib.sha256(repr(tones).encode()).hexdigest()[:16])
    digest(r, "rptr cw")
    r.poke("cfg_function", 0)
    r.run(0.5)
    r.press("S", hold=0.3)
    r.run(3.0)
    digest(r, "scan")
    r.adc(AD_SQL, 0xC0)
    r.run(1.0)
    r.adc(AD_SQL, 0)
    r.run(3.0)
    digest(r, "scan sig")
    r.press("#")
    r.run(0.3)
    r.power(False)
    r.run(1.2345)
    r.power(True)
    r.run(2.5)
    digest(r, "power cycle")
    r.type("145500")
    r.press("#")
    r.run(0.3)
    digest(r, "after power")


if __name__ == "__main__":
    for card in (P8E, P8N):
        print("== card", card)
        scenarios(card)
