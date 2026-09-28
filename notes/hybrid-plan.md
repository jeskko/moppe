# Plan: hybrid C/assembler firmware with banked EPROM

Decided 2026-09-28 (user). **Goal:** assembler only for what is timing
critical or awkward in C; everything else in C. ROM grows beyond 32 KB
by banking EPROM0 into the 0x8000 window. EPROM1 is not used now, but the
design must not exclude it for future features. The multiboard is uncommon,
so its socket is normally free.

Background: notes/rewrite-evaluation.md (measurements, constraints, proof of
concept), notes/hardware.md (memory decode), notes/emulator.md.

## Start here (next session, written 2026-09-28)

**State.** Phases 0-3 done. Banks: 0 = power-on (EPROM1 socket / multiboard),
1 = EPROM0 chip 0xC000 (the menu; in the asm build also APRS/MPRS, GPS,
FSK packets and repeater/CW; `C=1`: **8180 bytes free**, asm build 834),
2 = EPROM0 chip 0x8000 (`C=1`: `c/fsk.c`, `rptr.c`, `gps.c`, `aprs.c`,
12054 bytes; **~4.3 KB free**). Phase 4 in `make C=1`: `c/squelch_crc.c`,
`timers.c`, `keys.c`, `display.c`, `freq.c` in fixed ROM, the four bank-2
modules (see "Done: ... bank 2" under Phase 4); fixed ROM ends at ~0x493D
(~13.7 KB free, `_HOME` included). 186 tests pass on both builds; `make
-C firmware verify` still byte-identical for the release reference.

**Next task: the menu engine to C** (bank 1 holds only the menu now in
`C=1`: 8.2 KB of asm, mostly the REC/TAB/STR tables; the engine could be C
with `#pragma bank 1` next to the tables, which stay asm data, since bank
2 is nearly full). Then the scanner (coroutine → state machine) and the
other fixed-ROM modules. Per module: tests first (reference = the asm
build when a fixed bug makes the release differ), entry points as plain
`void f(void)` behind `far_X` stubs under `#ifdef C_MODULES`, register
interfaces through fixed-ROM shims, data it reads moved out of other
banks (link.py refuses cross-bank references), a mutation run.
Other open items: scanner to C (coroutine → state machine); the real-board
bench test (EPROM programmer); `notes/hardware.md` open questions (IC27,
EPROM0 pin 1 = CPU A15 assumed, modem CLK frequency).

**Rules learned this session (details in Phase 3/4 below):**
- Moving code to a bank: `tools/bankxref.py` (external users),
  `tools/isrreach.py` (must say "none"; it skips cpp lines), no stored bank
  addresses used by fixed code, block edges end in ret/jp.
- **Bank duty:** anything polled on every mainloop pass enters a bank only
  when it has work (see `far_repeater_run`: once per systick), and long
  busy-waits run in bank 0 (`bank0_call`); a bank hides the multiboard.
  `test_banking.BankDuty` measures it.
- 16-bit variables an interrupt changes (`repeater_timer_*`): SDCC splits
  volatile 16-bit loads/stores into bytes, so an interrupt between them
  can see or leave a half value (0x0100 read as 0). Access them through
  one-instruction shims (`ld hl, (nn)` / `ld (nn), hl`).
- C: no stack frames where asm callees may clobber IX (statics instead);
  interrupt-context C: no IX/IY at all; asm results in flags need a value in
  A (or a shim); keep the asm's evaluation order for volatile/hardware
  reads; copy constant expressions, not comments; `sir |= bit` in mainline
  is not atomic (keep such writes in asm); layout constants C hard-codes
  get an ASSERT in r58.s under C_MODULES. Check generated asm for
  `ix`/`iy`/`exx`.
- Safety net per module: tests first (they must pass on the release);
  differential scenarios for what the handset/synth/NV show
  (`test_diff.py`), release-vs-build RAM comparison for state they cannot
  see (`test_freq.Pair`), a mutation check that the new tests catch an
  off-by-one. Differential tests only cover what their scenarios drive
  (the CU58AF I2C slowdown from Phase 2 hid for a whole phase).
- Obvious firmware bugs may be fixed (user, 2026-09-28): with a test that
  fails on the release, noted under "Firmware behaviour the tests pinned
  down".

## Ground rules

- **The emulator test suite is the safety net.** Every phase ends with
  `python3 -m unittest discover -s emu/tests` passing on the new build. Add
  tests *before* porting a module whose behaviour is not yet covered.
- **Keep the stock build reproducible.** `make -C firmware verify` must keep
  passing (byte-identical to the release) until a change is meant to alter
  the binary; from then on the differential tests are the check.
- **NV layout stays v3_Z compatible** (0xC000-0xCFFF, asserted field offsets)
  so existing radios and CFGSnd images keep working. Reorganise it only
  deliberately, with a migration.
- One binary for P8E and P8N (runtime `cpu_is_P8E`), as today.
- Commit each validated step.

## What stays in assembler

| Part | Why | Current location (r58.asm) |
|---|---|---|
| Reset, RST 38, NMI, IM2 vector table (page 1) | fixed addresses, raw CPU | L819-1043 |
| PIO A interrupt: tick counters in E'/D', ADC reader, CTCSS DDS encoder/decoder dispatch | alternate register set, constant-time paths | L1884-2020 |
| SIO interrupt handlers, `modem_handler` byte capture | tiny, latency | L1614-1880 |
| systick dispatcher and the sir soft-interrupt trampoline (`call 8b` = ei;reti) | stack/RETI tricks | L2022-2252; the timer bookkeeping *inside* it may become C later |
| DTMF and AX.25 PWM loops (P8E 280 T / P8N 168 T per cell), SiRF BREAK bit-bang, `check_for_P8E_cpu` | cycle-exact | L14300-14830, L3458-3530 |
| Bit primitives: CU53AN shift (`display_bit*`, keypad strobe), I²C bit ops, synth/external serial shifting, FX465 load | bit-banging, OUT2/OUT1/PIO direction details | L10177-10260, L11502-11600, L11944-12110, L12808-12985 |
| NV copy loops (SMEM toggling, DI) | touch RAM while it is unmapped | L14207-14295 |
| Page-aligned tables used by asm: sinetab, crctbls, cu53an_font, res_set_stubs, dtmf_8870_tab, ad_list | alignment assumptions | L1223-1500 |
| Bank-switch trampolines, OUT2 shadow writer | see below | new |
| Optionally 24-bit helpers (mul248/div248/bin_bcd) as C-callable asm | C 32-bit maths is 2-4x larger | keep, give C prototypes |

Everything else moves to C: main loop, key handling and typematic, display
composition (not the bus driver), setup menu engine and record tables,
frequency/band/synth maths, scanner, repeater, CW sequencing, FSK packets
and remote config, APRS/MPRS/MIC-E, GPS parsing, MBUS, timers.

## C coding rules (from the proof of concept)

1. Code called from interrupt context (systick: squelch, decoders,
   `repeater_step_10msec`, timers) must not touch IX or IY: compile with
   `--reserve-regs-iy`, no stack frame (static locals), or move the work to
   mainline behind a flag. The PIO ISR saves only AF and BC/DE/HL.
2. Assembler routines called from C must preserve IX, or C must not have a
   frame around the call. Audit and document per routine; add thunks only
   where necessary.
3. Never use the alternate register set from C (SDCC doesn't).
4. C owns no NV data; NV variables are declared once (a header generated
   from, or checked against, the assembler NV map).
5. Banked code is never called from interrupt context (see banking).

## Phases

### Phase 0: widen the safety net (tests before porting)
Gaps today: scanner, repeater states, CW ID, menu editing of each record
type, CCIR/DTMF *receive* decode, FSK receive/remote config, MBUS CFGSnd/
CFGGEt, CU58AF keys and display in depth, low-battery/TOT power-down,
typematic timings.
- **Differential testing — done** (`emu/tests/difftest.py`, `test_diff.py`):
  stock and candidate builds run the same scripted inputs; display text and
  segments, icons, synth registers and load counts, OUT0/OUT1/DACs/CSMEM,
  power, event sequences (timestamps within 20 ms) and the NV image are
  compared at checkpoints. OUT2 and the PIO ports are not compared: they are
  bit-banged buses, so a checkpoint catches them at an arbitrary phase and
  they differ between two correct builds. Candidate: `R58_CAND_ROM`/`_LST`,
  default `firmware/build-c`. Stock vs `C=1`: no differences.
- **Added 2026-09-28:** `test_scan_rptr.py` (scanner: default mask, memory
  block, stop/resume on signal, mask toggle, perm reject; repeater: menu
  enable + 60 s boot lockout, access by 1750 Hz / DTMF * / carrier, greet,
  during and bye CW decoded from the tone pin) and `test_menu_power.py`
  (menu edit of every record type in use, "???", backspace, low battery
  warning/power-down, TOT, typematic groups, CU58AF menu/frequency/volume
  layout). Still open: CCIR/DTMF *receive* decode of digit strings, FSK
  receive/remote config and MBUS CFGSnd/CFGGEt (**covered 2026-09-28**,
  `test_fsk.py`, `test_mbus_config.py`).
- Grow the emulator where tests need it: FX429 RX bit timing, MBUS
  host-side helpers (CFGSnd/CFGGEt), maybe CTCSS slicer input.

**Firmware behaviour the tests pinned down** (keep it when porting unless
decided otherwise):
- TOT: v3_Z powered down at the (N+2)th minute boundary after TX on
  (N+1…N+2 minutes of TX; r58.asm L2451-2462/L13050). **Fixed 2026-09-28**
  (user decision): now N…N+1 minutes (the firmware clock ticks whole
  minutes, so this is the finest it gets), 255 = no limit, 0 = no TX.
- Every CW message costs at least 400 ms: `send_cw_prolog` jumps into
  `send_cw_epilog`, and both wait 200 ms (r58.asm L15996/L16009).
- SAnE does not reset CFG_DYN records (`reset_menurec` L17684), so the
  squelch level stays 0 after SAnE although its REC default is 127.
- cSEC entry drops the last typed digit ("150" stores 15, shown as 150 ms).
- Lower colon flickered off in ~10 % of frames while transmitting in the
  menu (clear-then-set in each redraw). **Fixed 2026-09-28.**
- CFG_EXE (type 10) is defined but no record uses it.
- FSK relay (5x packet → MBUS) walked `fsk_history` with `inc hl`, so a
  packet stored across the end of the ring was sent with the
  `gps_history` bytes that follow it. **Fixed 2026-09-28** (obvious bug:
  `inc l`, in asm and C); `test_fsk.test_relay_across_ring_end`.
- CW messages cut CTCSS: `send_cw_prolog` began with `xor h` (meant
  `ld h, #0`), so `ctcss_custom_flag` got the caller's H (0xD0 after
  `repeater_txon`) and `send_cw_epilog` called `ctcss_off` after every
  message: with CTCSS output WHEN = transmitter the repeater went on
  transmitting without its tone after the greeting ID. **Fixed
  2026-09-28** (obvious bug); `test_scan_rptr.test_ctcss_stays_on_after_id`.
- CW slot and pitch counts: `cw_calc_delays`/`cw_calc_blip` divided with
  `div248`, which is only right while 2 × remainder + 1 < 256 (divisors
  below ~128): CW speeds from 164 CPM gave 0-tick slots (no audible CW),
  and 100 of the pitch settings from 1280 Hz were off (1320 Hz played as
  ~1956 Hz). **Fixed 2026-09-28** (obvious bug): `div248_full` (any 8-bit
  divisor; the same results wherever `div248` was right, checked
  exhaustively for the CW inputs and on 200 000 random ones) for the CW
  counts only; `test_scan_rptr.test_fast_cw_and_high_pitch`. **Open:** the
  other `div248` callers (blip Hz, frequency, GPS, locator maths) have not
  been checked for divisors ≥ 128; the frequency code also uses the carry
  `div248` leaves, so do not swap it blindly.
- MPRS distance/bearing (QRB) was wrong for nearly every received position:
  `centiminutes_to_meters` (east-west metres) kept the hundredths of a
  minute in A, adding hundredths × 655 m (a station 13.5 km east showed
  22.1 km, one 457 m north "20.0 km E"), and its `pop bc` overwrote the
  multiplier's upper byte, so from 256 minutes of longitude difference on
  the result was garbage (345' west showed nothing). **Fixed 2026-09-28**
  (obvious bug, asm and C); `test_fsk.Qrb` against a model of the flat
  formula.
- MBUS logger format (`cfg_mbus_mprs` 4) prints `gps_utc` up to EOS; before
  the first GPS fix there is none and it prints the RAM after it. Kept.
- MPRS position (`mprs_degmin_pack`): only 'W' sets the sign bit, so a
  southern latitude is sent as northern. Kept as is (asm and C): the
  radios are used in Finland only, so the southern case never mattered
  and was likely never tested (user, 2026-09-28). Low priority.
- CFGSnd sent the last NV byte twice instead of the checksum
  (`all_config_send` computed it in A, `putchar` sends C), so CFGGEt
  refused a plain CFGSnd dump. **Fixed 2026-09-28** (user decision);
  `test_mbus_config.py` checks the sum and the CFGSnd → CFGGEt round trip.

### Phase 1: one toolchain (SDCC's sdas + sdld) — done 2026-09-28
- `firmware/r58.s` (sdasz80 syntax, converted by `tools/as80tosdas.py`)
  links **byte-identical** to r58p8x3Z.bin.als; `make verify` checks it.
  C modules are linked SDCC objects; `sdcc2as80.py` and `crt.inc` are gone.
  Details and the sdas pitfalls found: notes/toolchain.md.
- Deviation: the assembler stays **absolute** instead of moving to linker
  areas. sdas mis-assembles arithmetic on relocatable labels (sometimes
  silently), and this code relies on address arithmetic, so asmpp turns
  every label into an absolute symbol; ASSERTs are checked at assembly
  time. Linker areas are used for what is really relocatable: C code/data
  now, bank images in Phase 3.
- `r58.asm` (as80 source) stays as the reference for `make verify` and the
  differential tests (build-release). User: remove it when it gets in the
  way (then pin the release reference some other way, e.g. a committed
  converted copy).

### Phase 2: OUT2 shadow and bank infrastructure (still 32 KB) — done 2026-09-28
- **Space first.** The fixed ROM had 47 bytes free, too few for this
  phase: `tools/jp2jr.py` turned 318 `jp` into `jr` outside the timing-
  critical code (its exclusion list is the "stays in assembler" table),
  freeing 318 bytes. After Phase 2: 142 bytes free in the stock build
  (0x7F72), more in `C=1`. Watch page-aligned tables: 12 bytes added before
  `crctbls` once cost ~250 bytes of padding (`slack_at_this_xxx_hole`).
- `out2_bank` holds the bank bits (O2_BANK = SMEM/RA16, RS, RA15, RA14);
  every OUT2 writer ORs them in (`LD_A_OUT2(bus)`): keypad, display,
  I²C SCL, NV copy loops (P8N builds). Each bus routine records its final
  bus state in `out2_last`, which `set_bank` merges with the new bank bits.
  Only a routine's *last* OUT2 write matters for banked code (an interrupt
  returns into it only after the routine has finished); the test checks it.
- API (fixed ROM): `get_bank` (A = bank), `set_bank` (A → bank; destroys
  A, F), per-card bit tables. Bank 0 = power-on state (EPROM1 socket /
  multiboard), bank 1 = EPROM0 0xC000-0xFFFF (RS|RA14). Calls go through
  SDCC's library trampolines, which use exactly these two helpers:
  `ld e, #bank / ld hl, #fn / call ___sdcc_bcall_ehl` (A, DE, HL come back,
  BC is destroyed); C `__banked` functions use the same path.
- Multiboard readers decided: the DTMF decoder (systick) skips its sample
  while `cur_bank` ≠ 0; the CTCSS DSP decoder reads through
  `ctcss_dec_src`, which `set_bank` points at 0x8000 or at a RAM zero byte
  ("no signal"). Still constant-time, +20 T per PIO tick (1969 Hz, ~1 % of
  a P8N) while the DSP decoder runs. Order in `set_bank`: readers off
  before leaving bank 0, back on after returning to it.
- Tests: `test_banking.BankedFirmware` builds a 64 KB image with a routine
  in bank 1, enters it from `mainloop` through `___sdcc_bcall_ehl` (P8E and
  P8N), and checks: bank bits in OUT2 while it runs, display redrawn and
  keypad scanned by the soft interrupt meanwhile, A returned, bank 0 and
  the readers restored, no DTMF input taken from ROM, no watchdog reset.
  A mutated display routine that drops the bank bits fails it. The
  differential tests show no behaviour change against the release.

### Phase 3: banked EPROM0 (48 KB) — setup menu in bank 1, 2026-09-28
- **Done: the setup menu** (`init_menu` … band defaults, 1900 source lines:
  engine, 288 REC records, TAB/STR tables, SAnE resets) is in
  `.area BANK1 (ABS)` at 0x8000, 8.2 KB. Fixed ROM went from 32.6 KB to
  24.5 KB (~8 KB free); bank 1 has ~8 KB left. The image is 64 KB now
  (ihx2bin puts window 0x8000 at file 0xC000; file 0x8000-0xBFFF is 0xFF).
- Entry from fixed code: 15 stubs `far_X: call bank1_call / .dw X`
  (all registers and flags pass both ways, previous bank restored, nests).
  Only mainline code calls them (keys, redraw, FSK config packets, boot).
  `tab_ax25_digi` stays in fixed ROM because the APRS code reads it; the
  TAB/STR/REC macros moved ahead of it. `menu_ptr` holds bank addresses,
  which fixed code only compares or hands back to `far_load_menu_ptr`.
- All tests pass unchanged, including the differential tests against the
  release and the menu tests; a breakpoint in `draw_menu_title` stops at
  0x8009 with bank 1 selected.
- The bench test now sums the whole bank-1 window against `bank1_sum`
  (patched by ihx2bin) and calls `bank_test_ping` there, before anything
  else runs from bank 1; on failure it stays in a redraw loop.
- **Portable page:** OUT2 = RS|RA14 (bit 3 kept at 1) maps EPROM0 chip
  0xC000-0xFFFF into 0x8000-0xBFFF on **both** P8E (schematic) and P8N
  (manual). Verified in the emulator model only; **confirm on a real board
  early** (a tiny test ROM that checksums the window and shows the result
  on the display).
- **Bench test ROM — built 2026-09-28, waiting for a real board** (now
  also checks bank 2, see below):
  `make -C firmware banktest` → `build-banktest/r58-banktest.bin`, a 64 KB
  image for a 27C512 in the EPROM0 socket (EPROM1 socket as usual). It is
  the normal firmware plus `bank_test` early at boot. The lower row shows
  `b1b2 PASS` (on a CU53AN the S look like 5, B like b) when both window
  pages are right; `b1 ssss 00` = bank 1's 16-bit byte sum was ssss
  (`make banktest` prints both pages' sums, currently bank 1 FB75, bank 2
  BE64; C000 = an erased page); `b1 CA11 vv` = sum fine but
  `bank_test_ping` returned vv; `b2 ssss 00` = bank 1 fine but bank 2's
  sum was ssss (bank 1's sum = RA14 does not select the page); `b2 CA11
  vv` = bank 2's sum fine but `bank_test_ping2`, called through a far2
  stub (`bank2_call`), returned vv. The
  emulator shows PASS on P8E/P8N with both handsets
  (`test_banking.BenchTestRom`). The user will burn it when the EPROM
  programmer turns up and expects the service manual's decode to be right,
  so Phase 3 proceeds in the emulator meanwhile. Still to report: which
  card (P8E /H or P8N) and the display.
- **How to move the next block to bank 1** (what worked for the menu):
  1. Pick a contiguous block of r58.s, first label to the first label after
     it. `python3 tools/bankxref.py firmware/r58.s FIRST AFTER` lists every
     symbol of the block used outside it and local labels crossing its
     edges.
  2. `python3 tools/isrreach.py firmware/r58.s FIRST AFTER` must say
     "none". Classify each bankxref hit. A routine called from mainline gets a stub
     `far_X: call bank1_call / .dw X` in fixed ROM, and the outside
     `call`/`jp` sites are renamed to `far_X`. Keep in fixed ROM: data that
     fixed code reads (like `tab_ax25_digi`), anything reachable from an
     ISR or `dosir`, cycle-counted code. Address-only compares
     (`cp #HI(x)`) are fine. Also look for bank addresses stored in RAM
     and later used by fixed code (`adj_feedback`, pointers).
  3. Cut the block, paste it before `bank1_end:` in the BANK 1 section;
     `#define`s used by code left behind move with it to fixed ROM.
  4. Build (asserts catch range/size problems, the linker catches `jr`
     out of range), run all tests incl. `test_diff.py` against the release
     and `make C=1`; confirm with a breakpoint in the moved code that it
     runs with `cur_bank` = 1.
- **Done: APRS/MPRS/MIC-E, locator maths and GPS sentence processing**
  (2026-09-28), 4.0 KB: `handle_mprs_packets` … `stuffed_8bits` and
  `gps_process_aisin_seiki` … `gps_information_has_been_updated`. Four
  stubs: `far_handle_mprs_packets`, `far_send_aprs_report_packet`,
  `far_gps_process_sentence`, `far_gps_process_aisin_seiki`. The per-pass
  byte gatherer `gps_check` stays fixed on purpose: it runs on every
  mainloop pass, and time spent in bank 1 starves the multiboard DTMF/CTCSS
  readers; the processors run once per complete sentence. The AX.25 PWM
  loop (`emit_ax25_packet`) stays fixed and is tail-jumped from bank 1.
  Fixed ROM now ends at 0x4F89 (**~12 KB free**); bank 1 ends at 0xB04F
  (**~4 KB free**). All tests pass, including `test_diff.py` against the
  release for both `make` and `make C=1`; breakpoints in
  `gps_process_sentence`, `gps_own_locator`, `send_aprs_report_packet` and
  `encode_aprs_report_packet_normal` hit with `cur_bank` = 1 on P8E and
  P8N. `handle_mprs_packets` (MPRS receive) has been covered by
  `test_fsk.py` since the FSK move below. `tab_ax25_digi` is now read only
  from bank 1, so it could move there too.
- **Done: FSK packet layer** (2026-09-28), 1.3 KB: `packet_callsign_pack`
  … `send_mprs_report_packet_1` (receive dispatch `packet_for_whom`, call/
  display/config/relay handlers, config ask/enter and the DC reply, MPRS
  sending) and `map_special_ptrs` … `build_call_packet_buffer` (config
  packet filling, call packet). Six stubs: `far_packet_for_whom`,
  `far_send_remote_config_packets`, `far_send_mprs_report_packet{_maybe,,_1}`,
  `far_send_call_packet`. Fixed: the modem ISR path (`modem_handler`,
  `check_*_packet`, `check_packet`, `mute_fsk_at_sync/tag_maybe`), the
  CRC routines (C modules in `C=1`), `send_packet_buffer`, `init_modem`.
  Tests first: `test_fsk.py` (18 tests, pass on the release too) and FSK
  receive/send scenarios in `test_diff.py`; all 110 tests pass, FSK tests
  also on `C=1`; breakpoints in the moved code hit with `cur_bank` = 1.
  Fixed ROM ends at 0x4A61 (**~13.4 KB free**), bank 1 at 0xB591
  (**~2.6 KB free**). MBUS CFGSnd/CFGGEt (`all_config_send/get`) were
  already in bank 1 with the menu; `test_mbus_config.py` now covers them.
- **Done: repeater state machine, CW and note sequences** (2026-09-28),
  1.9 KB: `repeater_halt` … `repeater_operator_ptt`, `repeater_setstate` …
  timer helpers, `repeater_boot` … `cw_tab`. Stays fixed: everything
  interrupts reach (`repeater_toggle_suspend`, `dtmf_commands`,
  `ccir_repeater_cmd`, `repeater_step_1sec/10msec`) and `repeater_init`
  (runs on every pass when not a repeater). Stubs: `far_repeater_run`,
  `far_repeater_operator_ptt`. Fixed ROM ends at 0x4336 (**~15.2 KB
  free**), bank 1 at 0xBCEF (**785 bytes free**).
- **Multiboard readers vs. bank 1 (lesson from this move).** A plain stub
  for `repeater_run` kept bank 1 selected **46 %** of the time in repeater
  idle (the mainloop mostly spins), i.e. the multiboard DTMF decoder
  skipped about half its samples and the CTCSS DSP decoder read zeros.
  Two rules now:
  - Code polled on every mainloop pass enters bank 1 only when there is
    work: `far_repeater_run` checks `cfg_function`, then runs at most once
    per 10 ms systick (`sec100` vs `repeater_tick`). The state machine
    polls systick-driven inputs, so the pass after a tick sees the same
    inputs as before; only SIO-driven ones (LOCAL, PTT) can be up to 10 ms
    later. Repeater idle: 0.4 % in bank 1; while sending CW: 2.6 %.
  - Long busy-waits run with bank 0 selected: `bank0_call` (same body as
    `bank1_call`, target in `bank_to`) through fixed-ROM stubs
    (`b0_cw_wait_tone`, `b0_ccir_tx_timer_wait`). The pre-emption
    longjmp (`ld sp, (repeater_cw_jmpbuf)`) stays in bank 1 code, after
    the wait has restored the bank.
  `test_banking.BankDuty` checks < 5 % in normal mode and repeater idle
  (fails at 46 % without the guard) and runs `tools/isrreach.py` over all
  of bank 1 (nothing reachable from interrupts).
- **Not moved: the scanner** (1.2 KB, does not fit in the 785 bytes left).
  It is interrupt-free (`load_num_tmp_rejects`/`unreject_timer` stay
  fixed) and a coroutine through `scanner_state`; it would need the same
  kind of guard as the repeater (it runs on every pass while scanning).
- `tools/isrreach.py FILE [FIRST AFTER]`: routines reachable from the IM2
  handlers and dosir (textual call graph, `.dw` tables, fall-through);
  run it on a block before moving it (step 2 of the procedure above).
- Repeater tests are P8E-only: on a P8N the fixture pokes the 60 s boot
  timer before `repeater_boot` has set it (same on the release).
- **Next:** Phase 4 (port to C).
- Note: MPRS receive takes ~0.2 s on a P8N (QRB/locator maths), all of it
  in bank 1, i.e. with the multiboard DTMF/CTCSS readers off.
- **Bank 2 = EPROM0 chip 0x8000 (RS=1, RA14=0), on both cards** (2026-09-28):
  the user's P8E schematic trace shows the same RA14 page select as the
  P8N (hardware.md), so every radio has a second free 16 KB EPROM0 bank,
  no EPROM1 and no multiboard conflict. `set_bank` knows it (NUM_BANKS =
  3). (The first bench ROM filled it with 0x5A and checked sum 0x8000;
  replaced by the ping check below.) Still assumed: EPROM0 A15 = CPU A15.
- **Bank 2 wiring** (2026-09-28): asm `.area BANK2 (ABS)` / `.org 0x28000`
  after bank 1 (`bank2_start` … `bank2_end`), a virtual address so that
  it does not collide with bank 1's window addresses in the .ihx. asmpp
  absolutizes it like the other ABS areas; labels are 0x28000 + offset and
  every 16-bit use (`ld`, `jp`, `.dw`, `>> 8`, `& 0xFF`, relative `jr`)
  gets the window address (checked in a listing: sdld truncates silently).
  ihx2bin maps 0x28000-0x2BFFF to file 0x8000 and refuses other addresses
  above 0xFFFF. SDCC's `#pragma bank N` code is in area `_CODE_N` with
  `b_fn = N`; link.py places `_CODE_1` at `bank1_end` and `_CODE_2` at
  `bank2_end` (only when some module has the area; sdld refuses `-b` for
  an unknown one) and checks the bank ends. Verified with a throwaway
  `#pragma bank 2` module: `_ping` at 0x28000, `b_ping = 2`, the code at
  file 0x8000. `bank2_call` = `bank1_call` with bank 2 (stubs `far2_X:
  call bank2_call / .dw X`). The emulator (`r58emu._map_symbols`) masks
  bank-2 symbols to their window address. Tests: `test_banking`
  `test_bank2_call_p8e/p8n` (code in bank 2, OUT2 low nibble 0xC,
  display/keys go on, bank 0 back), `test_nested_bank1_to_bank2` (bank 1
  → far2 stub → bank 2, returns to bank 1 then 0), `BankDuty` runs
  isrreach over bank 2 too; a mutation (`bank2_call` selecting bank 1)
  fails the nesting and bench tests.
- Image layout: 64 KB file; 0x0000-0x7FFF fixed; 0x8000-0xBFFF = bank 2;
  0xC000-0xFFFF = bank 1. EPROM: 27C512 (or W27C512 /
  27SF512 for electrical erase).
- What goes in the bank: mainline-only, non-ISR code with its data. Good
  first candidates: setup menu engine + 288 records (~7.4 KB), APRS/MPRS/
  MIC-E + locator maths (~3 KB), GPS parsing (~1 KB), remote config/FSK
  packet building, CFGSnd/CFGGEt.
- Keep in fixed ROM: everything reachable from interrupts or dosir, the bus
  drivers, hot paths.

### Phase 4: port the rest to C, module by module
Order by test coverage and independence. Suggested: timers/battcheck →
key handling → display composition → frequency/band/synth maths →
scanner → FSK/remote config → APRS/GPS → repeater → CW. For each: tests
first, port, differential test against stock, size check, commit.

- **Done: timers and battery check** (2026-09-28), `c/timers.c`:
  `once_per_second`, `once_per_minute`, `once_per_hour` (systick,
  interrupt context) and `battcheck` (+ static `battcheck_lobatt`). Tests
  first: `test_timers.py` (15 tests, every branch; pass on the release).
  The alert tone goes through a 3-line asm shim `alert_tone_1s`
  (`start_marker_tone` takes HL and D, which `--sdcccall 1` cannot pass).
  All 134 tests pass on `C=1`, differential tests too. Size: the `C=1`
  image ends ~50 bytes after the stock one (all C modules, 0x3BE bytes,
  replacing their asm).
- Porting checklist (from this module):
  - Interrupt-context C: no parameters, no stack locals (static instead),
    so no IX frame; check the generated asm for `ix`/`iy`/`exx`.
  - Mainline C that calls asm routines: the same, since the asm may
    clobber IX (rule 2), unless the routine is audited.
  - Asm routines that return a flag: C needs the value in A; check every
    return path (`is_ptt_pressed` leaves A != 0 when pressed).
  - Keep the asm's evaluation order where hardware or volatile RAM is
    read (`battcheck_lobatt` tests the deadline before the voltage) and
    where it tail-jumps (`jp c, powerdown_now` skips the rest).
  - Assembler constants: copy the expression, not the comment
    (`#80 * 256 / 156` is 8 V in tenths; a VOLTS(8) that dropped the 10
    was caught by the low-battery tests).
- **Done: key dispatch** (2026-09-28), `c/keys.c`: `keycheck`, `dokey`,
  `dokey_not_menu`, `menu_input`, `handle_key_during_tx` (a `switch` per
  mode). The keypad scanners and `typematic` stay asm (interrupt
  context), as do `execute` (24-bit AHL helpers) and `is_key_down`
  (returns a flag, and clears the key as a side effect). Every handler
  takes the key in A, where `--sdcccall 1` passes a `uint8_t`; checked
  that none reads B/C before writing them. `script_check` now loads A
  before calling `dokey_not_menu`. 287 bytes of C for 302 of asm. Safety
  net: `test_diff.py` every-key scenarios (all keys short and long, normal,
  menu and TX, 'K'/'T' via a hook script; CU53AN and CU58AF).
- **Phase 2 regression found by those scenarios and fixed** (f2e982f): the
  bank bits made each SCL edge 26 T-states slower, so a CU58AF display
  refresh took 28.1 ms instead of 25.1 and keys were handled up to ~40 ms
  later than with the release. `out2_last` is now recorded once in
  `i2c_stop`, and `i2c_delay` has two watchdog writes instead of three:
  24.7 / 8.1 ms (release 25.1 / 8.3). Lesson: the differential tests only
  cover what their scenarios drive; the CU58AF variant had run only boot
  and frequency entry.
- **Done: display composition** (2026-09-28), `c/display.c`:
  `draw_upper_row`, `draw_lower_row` and what only they use (call timer,
  locator, call notice, feedback/remote text, scan mask, digit buffer,
  memory info). The assembler threads a display cursor through DE (CU53AN:
  a ROM table of segment-bit positions; CU58AF: a RAM character buffer);
  C keeps it in `dpy_cursor`, and `DPY_SHIM`s in r58.s load DE, call the
  primitive and store DE back (`dpy_freq` builds AHL for `draw_long` from
  a pointer). Stay asm: the primitives (`dpydig`, `dpyval*`, `draw_long`),
  the icon/LED setters (single `set`/`res`, some used by interrupts),
  `redraw` (sets DPYSIR atomically; C's `sir |= 2` need not be atomic),
  the feedback text stubs, `set_dpx_ind_from_rx_tx_freq` (flag result).
  731 bytes of C for ~570 of asm. New safety net: `SCN_DISPLAY_STATES`
  (memory marks, call notices, call timer, locator, remote display,
  repeater mode; both handsets).
- **Lower-colon flicker fixed** (63c77c5): v3_Z cleared the colon at the
  start of each redraw and the menu drawer set it again, so while
  transmitting in the menu ~10 % of frames lacked it; the C port's timing
  landed a differential checkpoint on one. Now cleared only when the menu
  row is not next (asm and C). `test_menu_power.MenuColon`.
- Size so far (`C=1`): fixed ROM ends at ~0x4437, about 15 KB free.
- **Done: frequency, band and duplex logic** (2026-09-28), `c/freq.c`:
  `changed_frequency` and its chain, `locate_band`, `set_duplex_from_tx_rx`,
  `determine_tx_div`, `step_duplex_state`, `set_legal_tx_flag`, channel
  stepping, `determine_qsy_kHz`, the VCO band bits. 24-bit values wrap at
  24 bits (`get24`/`put24` through a static union: SDCC's 32-bit shifts
  are large). Stay asm: the arithmetic kernel (`freq2div`/`div2freq`: the
  long division compares 2r+1, the last rounding takes a carry left by
  `div248`; via `determine_rx_div`/`determine_tx_div_split`), and helpers
  whose register results asm callers use (`locate_tx_band` → IX,
  `channel_step_parms` → HL/BC/DE; C calls the latter directly, A in and
  DE out being `--sdcccall 1`'s convention). The band record layout C
  hard-codes is asserted in r58.s. 1360 bytes of C for ~710 of asm (1.9×).
  Safety net: `test_freq.py` compares the RAM this logic writes, release
  vs build, through edge cases (mutation-checked).
- **Pattern for RAM the differential tests cannot see:** run the release
  and the build side by side and compare named RAM after each step
  (`test_freq.Pair`), each symbol resolved in its own build's map.
- Size (`C=1`): C modules 0xD08 bytes; fixed ROM ends at ~0x46C1, ~14.7 KB
  free.
- **Done: FSK packet layer in C, bank 2** (2026-09-28), `c/fsk.c`
  (`#pragma bank 2`): receive dispatch `packet_for_whom` and its call/
  display/config/relay handlers, config ask/enter/DC reply,
  `send_remote_config_packets`, MPRS sending, the call packet. The
  first banked C module. Entry points are plain `void f(void)` functions;
  the six `far_*` stubs call `bank2_call` under `C_MODULES` (all callers
  ignore returned registers). Bank-1 routines it uses go through their
  existing `far_*` stubs, which return to bank 2 (`far_handle_mprs_packets`,
  `far_send_aprs_report_packet`, `far_load_menu_ptr`,
  `far_remote_config_execute`, `far_leaved_setup`). Shims in fixed ROM
  (`fsk_*`) for register interfaces: `putchar` (C), `send_packet_buffer`
  (B), `tx_on`/`check_for_mprs_timer` (carry → A), `load_menu_ptr` (IX
  in, HL out), `handle_mprs_packets` (HL), `remote_config_execute` (DE/HL
  swapped). Stays asm in bank 1: `packet_callsign_unpack`,
  `mprs_degmin_pack` (the APRS code uses them; the C file has its own
  degmin and callsign packing). `onesies` (0xFF padding) moved into the C
  file: bank-1 data is invisible from bank 2. 1688 bytes of C for 1216 of
  asm (1.4×). No IX/IY in the generated code (two first drafts had frames:
  an argument kept across calls, a second argument on the stack).
  Safety net: `test_fsk.py`/`test_remote_config.py` as before, plus
  `test_diff` `test_fsk_edges_receive/send` (special config pointers,
  reply while transmitting, packets across the ring end, call packets of
  1/4/7/8 digits and the 0* resend, TX refused, 8/9-digit config entry,
  MPRS on demand, S/W position, symbol bits) and
  `test_banking.BankedC` (breakpoint in `_packet_for_whom`: bank 2
  selected, back to 0). Mutation run: 15 mutants, 14 caught, 1 equivalent
  (8 digits copied by either branch).
  link.py now refuses a C module referencing a symbol in a bank it does
  not run in (`ADDRESS_ONLY` lists the menu routine addresses `fsk.c`
  only compares); checked that it fires.
- **Done: repeater state machine, CW and note sequences in C, bank 2**
  (2026-09-28), `c/rptr.c`: `repeater_run` (suspend, /LOCAL, #x
  commands, state dispatch), the nine states, messages (IDs with alerts
  and MPRS bits, blips of every kind, UR 5x S-report, roger/QRT/hog),
  the CW and note engine. Stays fixed asm: what interrupts reach (command
  parsers, timer steps, suspend toggle), `repeater_init`, `cw_calc_delays`
  / `cw_calc_blip` (moved to fixed ROM in both builds: `div248_full`
  semantics for any input), the bank-0 waits. **States:** the asm stored
  the code address after `call repeater_setstate`; C keeps a state number
  in the low byte of `repeater_state` (0 = boot not entered; fixed
  `repeater_init` stores it), entry actions then the poll at once, and
  `go()` loops rather than nesting calls (the asm jumped). **CW
  pre-emption:** the asm's SP longjmp became a return flag passed up
  through `cw_slots` → `cw_chr` → `send_cw`/`send_cw_chr`/`send_notes`
  (which skip their closing `silence_timer1`, as the longjmp did).
  Shims: `rptr_tone` (start_marker_tone takes HL, D), `rptr_calc_blip`
  (C), the timer accessors (see the 16-bit rule). `c_bss` 64 → 128 bytes.
  2169 bytes of C for ~1.9 KB of asm. `test_scan_rptr.repeater_state_name`
  reads the state number in C builds.
  **Two v3_Z bugs fixed first** (in the asm, separate commits, see
  "Firmware behaviour the tests pinned down"): CTCSS cut after every CW
  message, and the CW slot/pitch overflow in `div248`.
  **Safety net:** `test_rptr_diff.py` (13 tests, asm build vs `C=1`):
  every state transition, the commands and S-reports, /LOCAL, suspend,
  all blip kinds, alerts, MPRS ID bits, CTCSS output modes incl. the
  CUSTOM epilog, MIC routing, access methods, empty bye, pre-emption.
  difftest gained `tones` (8254 pitch runs), `probe` (per-build RAM/state)
  and `trace` (value changes over time, change times within the timing
  tolerance) steps. Mutation run: 27 mutants, 26 caught, 1 equivalent
  (the pattern of a character no message sends); the first round had 7
  survivors, each a scenario gap (report windows shorter than a report,
  so the S digit was never compared; `TOPEN` running out mid-scenario;
  all MPRS bits set at once; no reversed/bypassed MIC; pre-emption and
  the CUSTOM epilog only visible between checkpoints). Scenario lessons:
  checkpoints must not land on CW element edges (OUT0's tone bits at an
  arbitrary instant), and pre-emption must happen mid-element, not near
  a slot edge where the builds' few ms differ.
  `test_banking.BankedC.test_repeater_runs_in_bank2`: breakpoint in
  `_repeater_run` with bank 2 selected.
- **Done: GPS sentence processing in C, bank 2** (2026-09-28), `c/gps.c`:
  NMEA GPRMC (checksum, time, status, lat/lon, speed, course, date) and
  the Aisin Seiki binary CA CA block. `gps_check` (the per-pass byte
  gatherer) stays fixed; `far_gps_process_sentence` passes the length
  (C → A) and `far_gps_process_aisin_seiki` the index (E → A) and keeps
  DE, which the caller's loop needs. `gps_own_locator` (bank 1, APRS
  block) through a new `far_gps_own_locator` until that block moves;
  `aisin_seiki_parse_latlon` (fixed) through a shim (IY, IX). The two
  APRS symbol tables stay in bank 1 asm. 1359 bytes of C. Kept on purpose
  (pinned by the tests): number fields reject only characters below '0'
  (a letter is stored as its value minus '0'), a field that fails leaves
  the fields before it updated, speed/course wrap at 16 bits, the digit
  shift register of lat/lon (only the last five digits before the point).
  Safety net: `test_gps_diff.py` (asm build vs `C=1`: 36 GPRMC cases incl.
  checksum edge cases and a stale checksum left in the buffer, 10 Aisin
  Seiki blocks, the menu redraw); mutation run 18/18 caught (after a
  second round: 4 survivors showed missing cases); `BankedC` breakpoint.
- **Open question (user): the Aisin Seiki binary GPS path is broken** in
  v3_Z (`cfg_gps_config` 3; found 2026-09-28, kept as is in the port):
  course = H + 256 × bit 7 of L of heading × 45 instead of / 128 (90° shows
  45, 270° shows 390); the centiminutes' ones byte is the low byte of a
  remainder, not a digit (30.11' shows 30.1 and 0x80); no N/S/E/W letter is
  written (the byte keeps its old value). Is that GPS still in use? If not,
  the path could be dropped; if yes, the first two are clear fixes, the
  hemisphere needs the unit's sign convention.
- **Done: MPRS receive and APRS sending in C, bank 2** (2026-09-28),
  `c/aprs.c`: `handle_mprs_packets` (display, locator, QRB), the five
  MBUS formats, GPS waypoint upload, `gps_own_locator`, APRS normal and
  MIC-E encoding, AX.25 CRC (fixed-ROM `calc_ax25_crc` via a shim) and bit
  stuffing; `emit_ax25_packet` (cycle-exact PWM) stays fixed. With it
  `packet_callsign_unpack`, `mprs_degmin_pack` and the symbol tables left
  bank 1: in `C=1` bank 1 holds only the menu. c/fsk.c and c/gps.c call it
  directly (same bank). 6474 bytes of C. Arithmetic kept bit for bit: a C
  copy of `div248` (its overflow for wrapped 24-bit values of out-of-range
  packets), 24-bit wrap, digits as values in `distance_bearing`, and two
  v3_Z bugs in `centiminutes_to_meters` (fixed in the next commit, see
  "Firmware behaviour": QRB). Deliberate difference: the metres-per-minute
  table for own latitudes of 90 and more (the asm read past it). Also
  found: the logger format prints `gps_utc` up to EOS, and before the first
  fix there is none, so it prints RAM after it (kept, noted).
  Toolchain: SDCC puts `__mullong`/`__divulong` in `_HOME`; link.py places
  it after `_CODE` in a second pass. `c_bss` 192 bytes. Frame rule refined:
  no frame in a function that calls assembler routines (a leaf using only C
  and the SDCC library may have one; SDCC spills some 32-bit conversions).
  Safety net: `test_aprs_diff.py` (seeded fuzz, asm build vs `C=1`: 60+15
  random MPRS packets near and far, every MBUS format and GPS upload, 40
  own locators, 30 random APRS reports, speed/course boundaries in both
  formats, ±180° longitude); difftest compares events per type now (MBUS
  and GPS output interleave by timing). Mutation run: 30 mutants, 28
  caught, 1 equivalent (SSID mask 0x1F vs 0x1E), 1 needing an exact
  9999 m distance. The C APRS path transmits ~10 ms longer (bit stuffing
  before the audio). `BankedC` breakpoint in `_handle_mprs_packets`.
  `test_rptr_diff`: the probe no longer compares raw second timers (edge
  flake as timing moved), `test_boot_minute` traces boot → idle instead.
- **What is left, and what gates it:**
  - Fixed-ROM modules that can go to C now: scanner (1.2 KB asm, a
    coroutine through `scanner_state`: needs an explicit state machine),
    memories/VIP list, the PTT/TX flow (`pttcheck`), MBUS relay, idle
    functions.
  - The menu (bank 1) goes to C
    in bank 2 like `fsk.c` (~14.7 KB free there). The real-board bench
    test still has to confirm both window pages.
  `--codeseg` + `__banked`), not done yet; the fixed ROM has room for now.

### Future: EPROM1
- P8E: 27C010, 8 × 16 KB pages, A14/A15/A16 = OUT2 bits 0/1/3. Bit 3 is
  also held at 1 today, so the "current" EPROM1 page is 4 when unused.
- P8N: 27C512, 4 pages, RA15:RA14; bit 3 is SMEM there (must stay 1).
- The page-bit tables in `bank_select` must allow EPROM1 banks, so keep the
  bank id abstract (bank → OUT2 bits per card), not raw OUT2 values in C.
- Using EPROM1 excludes the multiboard; that's acceptable since it is rare.
