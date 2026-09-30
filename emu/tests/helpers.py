"""
Non-test scenario/protocol helpers shared by several test modules (moved
out of whichever test module first defined them, so that importing them
elsewhere is not a test-to-test import). Nothing in this module is a
test itself; unittest discovery ignores it (it does not match test_*).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "python"))

import afsk  # noqa: E402

EOS = 0xFF

REMOTE_ID = bytes([0x34, 0x12])          # cfg_remote_id 0x1234, low byte first
PASSWD = b"12345678"


# --------------------------------------------------------------- scenario

def f24(v):
    """A 24-bit little-endian frequency/value field (rx_freq, tx_freq,
    band edges, ...)."""
    return (v & 0xFFFFFF).to_bytes(3, "little")


def at(label, probe):
    """The standard "compare here" step pair: ("check", label) collects
    display/latch/synth/NV/event differences since the previous checkpoint,
    ("probe", label, probe) additionally compares probe(radio) of both
    sides. A module whose checkpoints need something else (extra probes, a
    different order) defines its own `at` instead of using this directly."""
    return [("check", label), ("probe", label, probe)]


def enter(digits):
    """type digits, '#', settle: the plain frequency/memory entry step
    sequence used by several scenario builders."""
    return [("keys", digits), ("press", "#"), ("run", 0.3)]


# ------------------------------------------------------------------- nmea

def nmea(body, ck=None):
    """A NMEA sentence: "$<body>*<checksum>\\r\\n" with the standard XOR
    checksum, unless `ck` overrides it (a deliberately wrong or malformed
    one, for the parser's error paths)."""
    if ck is None:
        c = 0
        for ch in body:
            c ^= ord(ch)
        ck = "%02X" % c
    return ("$%s*%s\r\n" % (body, ck)).encode("latin-1")


def aisin(fix=3, lat=(61, 30, 7, 128), lon=(23, 45, 40, 0), heading=0x100, speed=100,
          datetime=b"\x26\x09\x28\x12\x34\x56", sats=b"\x00\x00\x00\x00\x12\x34\xAB\xCD", ck=None):
    """An Aisin Seiki binary CA CA position block."""
    p = bytearray(40)
    p[0] = fix
    for at_, (d, m, s, f) in ((1, lat), (5, lon)):
        p[at_:at_ + 4] = (((d * 3600 + m * 60 + s) * 256) + f).to_bytes(4, "big")
    p[13:15] = heading.to_bytes(2, "big")
    p[16:18] = speed.to_bytes(2, "big")
    p[22:28] = datetime
    p[31:39] = sats
    if ck is None:
        ck = (-(0xCA + 0xCA + sum(p))) & 0xFF
    return bytes([0xCA, 0xCA]) + bytes(p) + bytes([ck, 0x0D])


def gps_state(r):
    """The GPS fields the NMEA/Aisin Seiki parsers write, distinct in
    every field so a partial update shows."""
    return (r.peek("gps_utc", 8), r.peek("gps_date", 8), r.peek16("gps_knots"),
            r.peek("gps_speed"), r.peek16("gps_course"), r.peek("gps_status", 8),
            r.peek("gps_valid_seconds"), r.peek("cfg_gps_latitude", 8),
            r.peek("cfg_gps_longitude", 8), r.peek("cfg_gps_locator", 8))


def gps_state_no_locator(r):
    """gps_state without the locator, for the Aisin Seiki path: it writes a
    garbage centiminute byte (open bug), and the locator made from it
    differs from the reference since the locator fixes of 2026-09-30."""
    return gps_state(r)[:-1]


# the locator bytes as difftest `ignore` names them
LOCATOR_NV = ("cfg_gps_locator",) + tuple("cfg_gps_locator+%d" % i for i in range(1, 8))


# ---------------------------------------------------------------- packets

def with_crc(data, seed=b""):
    """Firmware FSK CRC (reflected CCITT, init FFFF, complemented, high
    byte first), appended after `data`; an Enter-config (EC) packet seeds
    it with the password first."""
    v = afsk.crc16_x25(bytes(seed) + bytes(data))
    return bytes(data) + bytes([v >> 8, v & 0xFF])


def mprs_packet():
    """An MPRS report as the firmware itself sends it: OH3XYZ-7 at
    61 30.12 N, 023 45.67 E (from a GPRMC sentence)."""
    return with_crc(bytes.fromhex("402f3ae1b97e003d1e0c172d43"))


# ----------------------------------------------------------- menu records

FW = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "firmware"))
SIZE_REC = 16


def parse_records():
    """The REC() lines of r58.s in order: dicts with group (menu_N),
    idx (record in the group), tag, title, type, ptr, arg, default."""
    src = open(os.path.join(FW, "r58.s"), encoding="latin-1").read().split("\n")
    a = next(i for i, l in enumerate(src) if l.startswith("start_menu:"))
    b = next(i for i, l in enumerate(src) if l.startswith("end_menu:"))
    recs, skip, group, idx = [], False, -1, 0
    for line in src[a:b]:
        s = line.strip()
        if s.startswith("#if 0"):
            skip = True
        elif s.startswith("#endif"):
            skip = False
        elif skip:
            continue
        m = re.match(r"menu_(\d):", s)
        if m:
            group, idx = int(m.group(1)), 0
            continue
        m = re.match(r'REC\("(..)",\s*"(.{6})",\s*CFG_(\w+),\s*(\w+),\s*(\w+),\s*(-?\d+)', s)
        if m:
            recs.append(dict(group=group, idx=idx, tag=m.group(1), title=m.group(2),
                             type=m.group(3), ptr=m.group(4), arg=m.group(5),
                             default=int(m.group(6))))
            idx += 1
    return recs


RECS = parse_records()


def rec(tag, title):
    return next(r for r in RECS if r["tag"] == tag and r["title"].rstrip() == title)


def pos(r):
    """digits for toggle_or_position_menu: group * 100 + record"""
    return "%d%02d" % (r["group"], r["idx"])


# ------------------------------------------------------------------ rptr

SIZE_STR = 8

# Repeater FSM state, derived from repeater_state (r58.asm L19456, a
# "jump pointer" WORD). repeater_setstate (L15065-15068) pops the return
# address pushed by `call repeater_setstate` and stores it as the resume
# point for the *next* repeater_run tick, so the stored value is not the
# state label itself but somewhere inside that state's own code. Since
# as80 lays out the file in order, bucket the address between consecutive
# state labels (r58.asm L15243-15538).
STATE_LABELS = [
    "repeater_boot", "repeater_idle", "repeater_opening",
    "repeater_beep_too_long", "repeater_open", "repeater_active",
    "repeater_closing", "repeater_reopening", "repeater_lockout",
]

# c/rptr.c: repeater_state is a state number instead, in the order of its
# enum (0 = boot not entered yet).
C_STATES = ["repeater_boot"] + STATE_LABELS


def cw_str(s):
    """Pack a short ASCII message into an 8-byte CFG_STR field (EOS-padded,
    r58.asm L447 `#define STRING : .rs SIZE_STR`)."""
    b = s.encode("ascii") + bytes([EOS] * SIZE_STR)
    return b[:SIZE_STR]


def repeater_state_name(r):
    if "_repeater_run" in r.sym:
        return C_STATES[r.peek("repeater_state")]
    marks = sorted((r.sym[n], n) for n in STATE_LABELS)
    name = marks[0][1]
    pc = r.peek16("repeater_state")
    for addr, n in marks:
        if pc >= addr:
            name = n
        else:
            break
    return name
