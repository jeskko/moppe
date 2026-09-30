# Hybrid plan: history

Superseded "Start here" handoffs and session narrative moved out of
hybrid-plan.md (which keeps the current state).

## Handoff after the asm was dropped, before the review clean-up (written 2026-09-29)

**State (2026-09-29).** Phase 4 is done as far as the plan's rule goes
("assembler only for what is timing critical or awkward in C"), and the
**C modules are the only build**: `make` links r58.s with `c/*.c`; the
assembler alternatives are gone from r58.s (21 356 → 11 019 lines; the
binary stayed byte-identical to the former `make C=1`). The last commit
with them is git tag **`asm-final`**; `make ref` builds it into
`firmware/build-ref/`, the reference of the module differential tests
(`test_*_diff.py`, `test_diff.DiffTest`), and it differs from the release
only by the bug fixes. `make verify` still rebuilds the release from
`r58.asm`. Sizes: fixed ROM ends at 0x4F10 incl. the C code (~12.2 KB
free), bank 1 7191 bytes free, bank 2 ~4.4 KB free; C statics 220 of the
256-byte `c_bss`. **301 tests** pass. Removed with the asm: 50 unused
`#define x _x` renames, six stubs without callers, the second copy of the
300 Hz marker shim (`marker_300hz_1s`).

Differential tests against `build-ref` only make sense for behaviour the
reference has: a bug fix or a new feature differs from it on purpose (then
the test pins the new behaviour on its own, as the bug-fix tests do).

## Handoff at the end of Phase 4, before the asm was dropped (written 2026-09-29)

**State. Phase 4 is done as far as the plan's rule goes** ("assembler
only for what is timing critical or awkward in C"). In `make C=1` the
C modules are: timers, squelch/CRC, keys (dispatch, handlers, memories,
VIP list, TX split/shift), display (rows and indicators), frequency logic
(+ the RFC fill), scanner, PTT/TX flow, mainloop and its checks (fixed
ROM); FSK, repeater/CW, GPS parsing, MPRS/APRS (bank 2); the setup menu
engine (bank 1). Sizes: fixed ROM ends at 0x4F21 incl. the C code
(**~12.3 KB free**), bank 1 **7191 bytes free**, bank 2 **~4.4 KB free**;
C statics 220 of the 256-byte `c_bss`. **301 tests** pass on both builds;
`make -C firmware verify` byte-identical; the asm build differs from the
release only by the bug fixes (latest: the CTCSS TX tone with the RFC
DAC/FX465 methods, 2026-09-29).

**Next task: to be decided (user).** Options: make `C=1` the default
build and drop the `#ifndef C_MODULES` asm (keep a pinned release
reference for `make verify` and the differential tests); the real-board
bench test (EPROM programmer); the open bugs (**notes/open-bugs.md**);
new features in the free space (bank 1/2, EPROM1 later).
Other open items: `notes/hardware.md` open questions (IC27, EPROM0 pin 1 =
CPU A15 assumed, modem CLK frequency).
Earlier handoffs: notes/hybrid-plan-history.md.

## Handoff during the small-cluster ports (written 2026-09-29)

**State.** Phases 0-3 done; Phase 4 has ported the timers, the key
dispatch and handlers with the memories and VIP list, the PTT/TX flow,
the mainloop and its per-pass checks, display composition, frequency logic
and the scanner (fixed ROM), the FSK layer,
repeater/CW, GPS parsing and MPRS/APRS (bank 2) and the setup menu engine
(bank 1). `C=1` sizes: fixed ROM ends at 0x4F21 (**~12.3 KB free**),
bank 1 **7191 bytes free**, bank 2 **~4.4 KB free**; the C statics use
**220 of the 256-byte `c_bss`**. 298 tests pass on both builds;
`make -C firmware verify` byte-identical; the asm build changes only by
the bug fixes.

**What is left** (measured 2026-09-29 with `python3 tools/asmleft.py`
after `make C=1`): fixed-ROM asm 0x0100-0x2F58, **~11.9 KB**: data 2030,
reachable from interrupts 3463, mainline touching hardware (out/in, DI,
halt, exx) 2321, mainline plain code 4049. The earlier estimates were too
high: CCIR/DTMF and CTCSS are nearly all interrupt context or hardware.
| Part | ~bytes | Status |
|---|---|---|
| CCIR/DTMF: decoders, series matching, `dtmf_commands`, `ccir_repeater_cmd`, GPIO commands | ~900 | systick: stays asm |
| CCIR/DTMF sending (`ptt_ccir_xmit`, `ccir_from_digbuf(_or_setup)`, `dtmf_bang_tone`, `dtmf_cu58af`/`i2c_dtmf`), `ccircheck` | ~400 | **decided 2026-09-29: stays asm** (OUT0/8254 writes with DI, cycle-counted DTMF, the handset bus; a C version would be shims around shims) |
| CTCSS: `ctcss_off`/`ctcss_maybe`/FX465/8254/DAC set-up | ~400 | hardware: stays asm |
| CTCSS maths: `calculate_sintab`, `ctcss_hz_to_phase_inc`, `ctcss_dec_start(stop)` | 110 | portable |
| Mainloop and its checks | 290 | **done 2026-09-29** (`c/mainloop.c`); left asm: `aisin_seiki_parse_latlon` (IX/IY interface for `c/gps.c`), `cu_lights_off` (bit writes interrupts share) |
| Indicators: `draw_dpx_ind`, `draw_ctcss_and_mute_and_gps_ind`, `draw_squelch_ind`, `set_dpx_ind_from_rx_tx_freq` | 240 | **done 2026-09-29** (`c/display.c`); the single-bit icon setters stay asm (asm callers) |
| RFC table fill `rfc_fill_blanks`/`rfc_fill_one_hole` | 106 | **done 2026-09-29** (`c/freq.c`) |
| RFC lookup `get_rfc_hl`/`lookup_rfc`/`save_rfc` | 60 | **kept asm on purpose** (every frequency change: in C 1.2 ms more per scanner step) |
| `set_tx_freq`, `set_duplex_shift_*` (and the now callerless `compare_tx_rx_freq`, `point_ix_memory`) | 133 | **done 2026-09-29** (`c/keys.c`) |
| Frequency kernel (`determine_rx_div`, `freq2div`, `channel_step_parms`, `locate_tx_band`, `div248`, ...) | ~500 | kept asm on purpose (carry semantics, register results); optional |
| TX keying `tx_on`/`tx_off` | 150 | kept asm on purpose |
| Display primitives (`draw_word`, `dpydig`, `draw_long`, `dpyval*`, strings), maths helpers (`bin_bcd`, `a2i`, `mul248`), boot (`main`, `cu58af_init`), bank trampolines | ~1500 | stays by design |

**Next task: the rest of the portable clusters** (user, 2026-09-29: port
them): CTCSS maths (`calculate_sintab`, `ctcss_hz_to_phase_inc`,
`ctcss_dec_start(stop)`; with them `ctcss_generator_on`/`ctcss_dec_start`,
whose asm callers pass registers, and one-instruction shims for the
`ctcss_enc_jump`/`ctcss_dec_jump` stores the PIO interrupt jumps
through; `calculate_sintab` multiplies by repeated addition, ~100 ms per
PTT with the RFC DAC method on a P8E, so C will be faster: a deliberate
difference). Tests first as before; `tools/asmleft.py` lists what is
left.
Other open items: the real-board bench test (EPROM programmer);
`notes/hardware.md` open questions (IC27, EPROM0 pin 1 = CPU A15 assumed,
modem CLK frequency); the bugs left in place: **notes/open-bugs.md**.
Earlier handoffs: notes/hybrid-plan-history.md.

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
