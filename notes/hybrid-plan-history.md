# Hybrid plan: history

Superseded "Start here" handoffs and session narrative moved out of
hybrid-plan.md (which keeps the current state).

## Handoff before the menu engine port (written 2026-09-28)

**State.** Phases 0-3 done. Banks: 0 = power-on (EPROM1 socket / multiboard),
1 = EPROM0 chip 0xC000 (the menu; in the asm build also APRS/MPRS, GPS,
FSK packets and repeater/CW; `C=1`: **8180 bytes free**, asm build 834),
2 = EPROM0 chip 0x8000 (`C=1`: `c/fsk.c`, `rptr.c`, `gps.c`, `aprs.c`,
12054 bytes; **~4.3 KB free**). Phase 4 in `make C=1`: `c/squelch_crc.c`,
`timers.c`, `keys.c`, `display.c`, `freq.c` in fixed ROM, the four bank-2
modules (see "Done: ... bank 2" under Phase 4); fixed ROM ends at ~0x493D
(~13.7 KB free, `_HOME` included). 186 tests pass on both builds; `make
-C firmware verify` still byte-identical for the release reference.

**Next task: the setup menu engine to C, in bank 1** (`#pragma bank 1`).
In `make C=1` bank 1 holds only the menu (`bank1_start` … the GPS section
marker, ~1890 lines: engine + 288 `REC` records, `TAB`/`STR` tables,
SAnE/band defaults, CFGSnd/CFGGEt `all_config_send/get`, wipe/reboot).
Bank 2 has only ~4.3 KB left, bank 1 ~8 KB, so the engine goes to C in
bank 1 next to the tables, which stay asm data (`REC` layout: offset_tag 0,
title 2, ptr 8, arg 10, def 12, type 14; types CFG_BYTE 1 … CFG_EXE 10).
What to know before starting:
- Entry points (fixed-ROM `far_*` stubs, `bank1_call`): `init_menu`,
  `update_gpio12_foo`, `toggle_or_position_menu`, `menu_enter_or_walk`,
  `menu_defval_or_exec`, `menu_up_value`, `menu_dn_value`,
  `menu_next_group`, `menu_prev`, `decoder_hist_rewind`,
  `remote_config_execute` (DE ptr, HL data), `leaved_setup`,
  `load_menu_ptr` (IX record → HL value ptr), `draw_menu_title`,
  `draw_menu_lower_row` (DE display cursor). Callers: keys.c, display.c
  (`DPY_SHIM`s), fsk.c (`fsk_menu_ptr`, `fsk_remote_config_execute`),
  asm. Check each for register interfaces.
- `menu_ptr` holds a record address; fixed code only compares it or hands
  it back. The records are data in bank 1, so C in bank 1 can read them;
  nothing outside bank 1 may dereference them (link.py's cross-bank check
  covers C).
- `_CODE_1` placement (after `bank1_end`, link.py) and `#pragma bank 1`
  are wired but **never exercised**: first build a tiny bank-1 C function
  and check the map, the image offset (window 0x8000 → file 0xC000) and a
  `BankedC` breakpoint, as was done for bank 2.
- Tests to widen first: `test_menu_power.py` (27), `test_mbus_config.py`
  (7), `test_remote_config.py` (7). Needed: every record type's up/down/
  enter/default and value display, every group walked (the whole menu
  drawn on both handsets, differential against the asm build), SAnE and
  band defaults (NV compared), CFGSnd/CFGGEt, remote config per type. The
  known menu bugs (cSEC last digit, SAnE and CFG_DYN) are in
  notes/open-bugs.md: keep them unless decided.
- Tools: `tools/mutate.py` for the mutation run (a `MUTANTS` list of
  replacements; tests read the mutant through the env variables),
  `tools/bankxref.py`, `tools/isrreach.py`; difftest steps `probe`,
  `trace`, `tones`.
Other open items: the scanner to C (coroutine → state machine); the
real-board bench test (EPROM programmer); `notes/hardware.md` open
questions (IC27, EPROM0 pin 1 = CPU A15 assumed, modem CLK frequency);
the bugs left in place: **notes/open-bugs.md**.

## Handoff before the scanner port (written 2026-09-28)

**State.** Phases 0-3 done; Phase 4 has the setup menu engine in C now
(`c/menu.c`, bank 1). Banks: 0 = power-on (EPROM1 socket / multiboard),
1 = EPROM0 chip 0xC000 (the menu; in the asm build also APRS/MPRS, GPS,
FSK packets and repeater/CW, 834 bytes free; `C=1`: REC records, TAB/STR
tables and band defaults as asm data 0x8000-0x97E7, then `c/menu.c`,
3074 bytes; **7191 bytes free**), 2 = EPROM0 chip 0x8000 (`C=1`:
`c/fsk.c`, `rptr.c`, `gps.c`, `aprs.c`, 11832 bytes; **~4.4 KB free**).
Fixed ROM (`C=1`: squelch/CRC, timers, keys, display, freq in C, the
shims and stubs, `_HOME`) ends at 0x4A0A (**~13.5 KB free**). 222 tests
pass on both builds; `make -C firmware verify` still byte-identical, and
the asm build is unchanged by the menu port.

**Next task: the scanner to C** (1.2 KB of fixed-ROM asm, a coroutine
through `scanner_state`: needs an explicit state machine). Simplest in
fixed ROM (room enough, no bank-duty question); in a bank it would need
the `far_repeater_run` kind of guard, since it runs on every mainloop pass
while scanning. `load_num_tmp_rejects`/`unreject_timer` stay fixed
(interrupts). Tests first: the scanner cases in `test_scan_rptr.py` pass
on the release; a differential scenario set (asm build vs `C=1`) for
scan rates, listen/tail times, rejects and auto-reject, memory scan
masks, FSK-carrier skip, stop by key/PTT is still to write. After that:
memories/VIP list, the PTT/TX flow (`pttcheck`), MBUS relay, idle
functions (see "What is left" under Phase 4).
Other open items: the real-board bench test (EPROM programmer);
`notes/hardware.md` open questions (IC27, EPROM0 pin 1 = CPU A15 assumed,
modem CLK frequency); the bugs left in place: **notes/open-bugs.md** (the
menu ones found in the port are there; CtCSSt on memories is fixed).
Earlier handoffs: notes/hybrid-plan-history.md.
