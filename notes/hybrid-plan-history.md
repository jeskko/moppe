# Hybrid plan: history

Superseded "Start here" handoffs and session narrative moved out of
hybrid-plan.md (which keeps the current state).

## Handoff before the PTT/TX port (written 2026-09-29)

**State.** Phases 0-3 done; Phase 4 has ported the timers, the key
dispatch and handlers with the memories and VIP list, display
composition, frequency logic and the scanner (fixed ROM), the FSK layer,
repeater/CW, GPS parsing and MPRS/APRS (bank 2) and the setup menu engine
(bank 1). `C=1` sizes: fixed ROM ends at 0x4DC3 (**~12.6 KB free**),
bank 1 **7191 bytes free**, bank 2 **~4.4 KB free**; the C statics use
**199 of the 224-byte `c_bss`**. 267 tests pass on both builds;
`make -C firmware verify` byte-identical; the asm build changes only by
the bug fixes.

**What is left** (assembler still in the `C=1` build, rough sizes from the
map, 2026-09-29):
| Part | ~bytes | Notes |
|---|---|---|
| PTT/TX flow (`pttcheck`, `tx_on`/`tx_off`, legality, APRS/MPRS on PTT, CCIR on PTT, tune tone, `beep1750`) | 750 | timing: TX keying order, PLL delay |
| CCIR/DTMF decoding and commands | 1300 | partly systick/interrupt context: only the mainline parts can go |
| CTCSS set-up (decoder start/stop, encoder methods i8254/RFC DAC/FX465) | 700 | the DDS/DSP interrupt parts stay |
| GPS I/O (`gps_check` gatherer, `gps_configure`, Aisin Seiki lat/lon) | 500 | the SiRF BREAK bit-bang stays |
| Mainloop, idle functions, hook, lights, ignition | 300 | |
| RFC table (fill, lookup), MBUS relay, small NV helpers | 400 | |
| Small key-side asm kept for asm callers: `set_vola(_a)` (OUT0, DI), `set_tx_freq`, `set_duplex_shift_*`, `step_audio_dst`, `mute_squelch_selective`, `compare_tx_rx_freq`, `point_ix_memory`, `a2i*`, `is_key_down`/`waitkey`, the feedback stubs | 350 | port with their asm callers (frequency kernel, PTT) |
| Frequency arithmetic kernel (`freq2div`/`div2freq`, `div248`, `channel_step_parms`) | 600 | kept asm on purpose (carry semantics, register results); optional |
| **Stays assembler by design** | ~7000 | interrupts/systick/keypad/SIO/modem capture (~1.5 KB), handset drivers and display primitives (~2 KB), DTMF/AX.25 PWM, NV copy loops, boot and hardware init, bank trampolines, page-aligned tables (~3.7 KB) |

**Next task: the PTT/TX flow** (`pttcheck` … `tx_error`, `tx_on`/`tx_off`,
`beep1750`, `tx_tune_tone_maybe`; fixed ROM, mainline). Tests first:
differential scenarios for TX keying order and timing (OUT0/OUT1 latch
sequence, PLL settle, TX refused out of band and with TX limits, TOT),
digits on PTT (CCIR), APRS/MPRS on key-up, the 1750 Hz beep, the tune
tone in the menu, the repeater-mode PTT path. Then the mainline halves of
CCIR/DTMF and CTCSS, GPS I/O, the rest.
Other open items: the real-board bench test (EPROM programmer);
`notes/hardware.md` open questions (IC27, EPROM0 pin 1 = CPU A15 assumed,
modem CLK frequency); the bugs left in place: **notes/open-bugs.md**.
Earlier handoffs: notes/hybrid-plan-history.md.

## Handoff before the key handler port (written 2026-09-29)

**State.** Phases 0-3 done; Phase 4 has ported the timers, keys dispatch,
display composition, frequency logic and the scanner (fixed ROM), the
FSK layer, repeater/CW, GPS parsing and MPRS/APRS (bank 2) and the setup
menu engine (bank 1). `C=1` sizes: fixed ROM ends at 0x4C55 (**~13.2 KB
free**), bank 1 **7191 bytes free**, bank 2 **~4.4 KB free**; the C
statics use **179 of the 192-byte `c_bss`** (raise `C_BSS_SIZE` in r58.s
for the next module). 248 tests pass on both builds (`test_aprs_send`
now at 30 ms tolerance, see Phase 4); `make -C firmware verify`
byte-identical; the asm build changes only by the bug fixes.

**What is left** (assembler still in the `C=1` build, rough sizes from the
map, 2026-09-29):
| Part | ~bytes | Notes |
|---|---|---|
| Key handlers keys.c dispatches to (execute, monitor, duplex key, volume/squelch/memory up-down-default, digit entry and backspace, scanner key, call/beep) | 900 | mainline; `test_diff` every-key scenarios cover the dispatch |
| Memories and VIP list (store/recall, `go_mem_a`, `leave_memories`, `remember_vip`/`next_vip`) | 550 | mainline; with the key handlers |
| PTT/TX flow (`pttcheck`, `tx_on`/`tx_off`, legality, APRS/MPRS on PTT, CCIR on PTT, tune tone) | 700 | timing: TX keying order, PLL delay |
| CCIR/DTMF decoding and commands | 1300 | partly systick/interrupt context: only the mainline parts can go |
| CTCSS set-up (decoder start/stop, encoder methods i8254/RFC DAC/FX465) | 700 | the DDS/DSP interrupt parts stay |
| GPS I/O (`gps_check` gatherer, `gps_configure`, Aisin Seiki lat/lon) | 500 | the SiRF BREAK bit-bang stays |
| Mainloop, idle functions, hook, lights, ignition | 300 | |
| RFC table (fill, lookup), MBUS relay, small NV helpers | 400 | |
| Frequency arithmetic kernel (`freq2div`/`div2freq`, `div248`, `channel_step_parms`) | 600 | kept asm on purpose (carry semantics, register results); optional |
| **Stays assembler by design** | ~7000 | interrupts/systick/keypad/SIO/modem capture (~1.5 KB), handset drivers and display primitives (~2 KB), DTMF/AX.25 PWM, NV copy loops, boot and hardware init, bank trampolines, page-aligned tables (~3.7 KB) |

**Next task: the key handlers with the memories/VIP list** (they call
each other; ~1.4 KB, mainline, fixed ROM). Tests first: differential
scenarios for memory store/recall/hide/scan flags, VIP walking, every
long/short key outside the menu with digits typed and not, and the
feedback texts. Then the PTT/TX flow, then the mainline halves of
CCIR/DTMF and CTCSS, GPS I/O, the rest.
Other open items: the real-board bench test (EPROM programmer);
`notes/hardware.md` open questions (IC27, EPROM0 pin 1 = CPU A15 assumed,
modem CLK frequency); the bugs left in place: **notes/open-bugs.md**.
Earlier handoffs: notes/hybrid-plan-history.md.

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
