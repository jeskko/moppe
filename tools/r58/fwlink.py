#!/usr/bin/env python3
"""
Shared sdldz80 .map / .rel parsing and the banked-ROM address table
(notes/toolchain.md), used by link.py, ihx2bin.py, cglue.py and
asmleft.py so the record formats and the bank windows are defined once.

    read_map(path) -> {name: address}            sdldz80 -m symbol table
    read_rel(path)  -> Rel(defs, refs, areas)     one sdcc/sdas .rel object

Rel.defs is {name: address} (S ... Def records), Rel.refs is the set of
names the object references (S ... Ref records), Rel.areas is
{area name: byte size} (A ... size records; areas never emitted are
absent, not zero).

BANKS: for each banked C area (#pragma bank N, area _CODE_N), the
assembler symbol marking the end of its window, the CPU window
[lo, hi), and (for ihx2bin.py) the delta from CPU window address to
64 KB file offset.
"""
import re

BANKS = {
    "_CODE_1": {"end_sym": "bank1_end", "lo": 0x8000, "hi": 0xC000, "delta": 0x4000},
    "_CODE_2": {"end_sym": "bank2_end", "lo": 0x28000, "hi": 0x2C000, "delta": -0x20000},
}

_MAP_SYMBOL = re.compile(r"^\s+([0-9A-F]{8})\s+(\S+)")
_REL_DEF = re.compile(r"S (\S+) Def([0-9A-Fa-f]+)")
_REL_REF = re.compile(r"S (\S+) Ref")
_REL_AREA = re.compile(r"A (\S+) size ([0-9A-Fa-f]+)")


def read_map(path):
    syms = {}
    for line in open(path):
        m = _MAP_SYMBOL.match(line)
        if m:
            syms[m.group(2)] = int(m.group(1), 16)
    return syms


class Rel:
    __slots__ = ("defs", "refs", "areas")

    def __init__(self, defs, refs, areas):
        self.defs = defs
        self.refs = refs
        self.areas = areas


def read_rel(path):
    defs, refs, areas = {}, set(), {}
    for line in open(path, errors="replace"):
        m = _REL_DEF.match(line)
        if m:
            defs[m.group(1)] = int(m.group(2), 16)
            continue
        m = _REL_REF.match(line)
        if m:
            refs.add(m.group(1))
            continue
        m = _REL_AREA.match(line)
        if m:
            areas[m.group(1)] = int(m.group(2), 16)
    return Rel(defs, refs, areas)
