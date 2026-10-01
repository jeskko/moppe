# Plan: hybrid C/assembler firmware with banked EPROM

Decided 2026-09-28 (user). **Goal:** assembler only for what is timing
critical or awkward in C; everything else in C. ROM grows beyond 32 KB
by banking EPROM0 into the 0x8000 window. EPROM1 is not used now, but the
design must not exclude it for future features. The multiboard is uncommon,
so its socket is normally free.

Background: notes/rewrite-evaluation.md (measurements, constraints, proof of
concept), notes/hardware.md (memory decode), notes/emulator.md.

## Start here (next session, written 2026-10-01)

**State (2026-09-30).** Phase 4 is done as far as the plan's rule goes
("assembler only for what is timing critical or awkward in C"), and the
**C modules are the only build**: `make` links r58.s with `c/*.c`. The
last commit with the assembler alternatives is git tag **`asm-final`**;
`make ref` builds it into `firmware/build-ref/`, the reference of the
module differential tests (`test_*_diff.py`, `test_diff.DiffTest`); it
differs from the release by the bug fixes and the removed Aisin Seiki
GPS path. `make verify` still rebuilds the release from `r58.asm`.
Sizes (2026-10-01, after the simplifications and the tone tables):
fixed ROM ends at 0x4EFB incl. the C code (12.5 KB free), bank 1 7328
bytes free, bank 2 5794 bytes free; C statics 227 of the 256-byte
`c_bss` (getting tight: grow C_BSS_SIZE or share statics before the next
large C module). **322 tests** pass.

The 2026-09-29 code review is applied (details in the commits): one
shared header `c/r58.h` (163 symbols had been declared in several modules,
28 of them inconsistently) with the layout constants; duplicates merged
(`copy3`, `mprs_degmin_pack` ×3, `nibbles`, the locator mirror/count-down
blocks, `menu_next/prev`, repeater state tails); `FAR()` for the bank stubs
and shims named for what they do; `tools/fwlink.py` for .map/.rel parsing;
`emu/tests/helpers.py` and `difftest.DiffCase` for the test boilerplate.
Kept on purpose: the `#x` command switch's four roger tails (a goto for 12
bytes), `freq.c locate_band`'s write-then-overwrite (as the asm; the
rewrite came out larger), two casts that silence an SDCC warning.

Differential tests against `build-ref` only make sense for behaviour the
reference has: a bug fix or a new feature differs from it on purpose (then
the test pins the new behaviour on its own, as the bug-fix tests do).
Timing-sensitive scenarios: a trace or checkpoint that starts on an edge
flips when code size shifts timing by a few ms (`test_rptr_diff` CUSTOM
epilog: a leading transient, now `settle=2`). Scenario inputs poked in
the same instant can race the mainloop: `test_ptt_diff.test_aprs_local`
set `cfg_aprs_tx` 0 and grounded /LOCAL together, and a pass sitting
between `aprs_ptt_check`'s two reads saw the old setting with the new edge
and sent APRS (reproduced with a behaviour-identical display.c change; the
same race exists in the asm). Change a setting, run a little, then the
edge.

**What stays assembler** (`python3 tools/asmleft.py` after `make`:
fixed-ROM asm 0x0100-0x2BBA, ~10.7 KB: data 1826, reachable from
interrupts 3146, mainline hardware 2365, mainline plain 3600):
| Part | Why |
|---|---|
| Interrupt handlers, systick, keypad/SIO/modem capture, the CCIR/DTMF decoders, series matching and commands, the CTCSS DDS/DSP entries (`ctcss_enc/dec_entry`: reached through RAM jump addresses, which `isrreach` cannot follow, so asmleft lists them as mainline) | interrupt context |
| TX keying `tx_on`/`tx_off`, CCIR/DTMF sending, CTCSS set-up (8254, FX465, DAC), OUT0/8254 writers, NV copy loops, bit-banged buses | hardware sequencing with DI, cycle counts |
| CTCSS maths (`ctcss_hz_to_phase_inc`, `ctcss_dec_start(stop)`) | ~60 bytes, register interface (A in, HL out) for asm callers; the slow multiply is ~1.5 ms. `calculate_sintab` is a shim to C `make_sintab` since 2026-10-01 |
| RFC lookup (`get_rfc_hl`, `lookup_rfc`, `save_rfc`) | every frequency change; C cost 1.2 ms per scanner step |
| Frequency kernel (`determine_rx_div`, `freq2div`, `channel_step_parms`, `locate_tx_band`, `div248`) | carry semantics, register results |
| Display primitives (`draw_word`, `dpydig`, `draw_long`, `dpyval*`, strings), icon setters, `redraw` | register cursor, atomic DPYSIR, many asm callers |
| Maths helpers (`bin_bcd`, `a2i*`, `mul248`, the GPS unit conversions) | register interfaces for asm and C shims |
| Boot (`main`, `cu58af_init`, hardware init), bank trampolines, page-aligned tables | fixed addresses, raw CPU |

**Done 2026-10-01: the open-bug decisions** (notes/open-bugs.md is
empty now; the entries and the user's answers are in
open-bugs-history.md, what was done under "Firmware behaviour the tests
pinned down" below): south/west locator edges, Aisin Seiki removed
(PH:GPSCFG renumbered, old 9600Std migrated at boot), TBEEPMAX 0 = no
limit, `repeater_operator_ptt` removed, overlapping scan bands merged,
logger time 000000 before a fix; busy settling, SAnE DYN and the APRS
timing kept. Mutants of the new code (edge_step, the slice merge, TBEEPMAX,
the logger) are all caught but one equivalent (.99 vs .98 when a minute
borrows: the same 0.25' cell). How a fix goes (for the next ones): a test that fails on
the release (`R58_ROM=firmware/build-release/r58.bin R58_LST=...r58.map`
runs a standalone test against it), the fix in C (the asm is gone), the
entry moved to "Firmware behaviour the tests pinned down" below. A fix
makes the differential tests differ from `build-ref` where their
scenarios reach the fixed case: keep those scenarios on the unaffected
side (as `test_aprs_diff.ref_degmin` does for S/W/.50 positions) and cover
the fixed case with a standalone test against a model, not by loosening
the comparison.

**Done 2026-10-01: CI and releases, prepared locally** (notes/ci.md):
`.github/workflows/ci.yml`, `tools/ci/` (pinned SDCC tarball, pipeline,
parallel test runner, packaging, `docker.sh` for a clean Ubuntu run). Not
on GitHub yet: publishing waits for the original authors (OH1E asked
2026-10-01). Release images come from the CI SDCC: another SDCC build of
the same version allocates registers differently (notes/ci.md).

Next, options: the first GitHub run (private repository, or public
after the authors' reply; later maybe a Markdown or richer setup map);
the real-board bench test (EPROM programmer); new features in the
free space (bank 1/2, EPROM1 later). Other open items: `notes/hardware.md`
open questions (IC27, EPROM0 pin 1 = CPU A15 assumed, modem CLK
frequency). Earlier handoffs: notes/hybrid-plan-history.md.

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
  `ix`/`iy`/`exx`. From the 2026-09-29 review: variables an interrupt
  writes are `volatile` in mainline C and read once into a static
  (`keycheck` had tested one `key` and dispatched another);
  `get24(a) - get24(b)` and 32-bit sums spill into an IX frame, so go
  through a static one step at a time.
- Safety net per module: tests first (they must pass on the release);
  differential scenarios for what the handset/synth/NV show
  (`test_diff.py`), release-vs-build RAM comparison for state they cannot
  see (`test_freq.Pair`), a mutation check that the new tests catch an
  off-by-one. Differential tests only cover what their scenarios drive
  (the CU58AF I2C slowdown from Phase 2 hid for a whole phase).
- Obvious firmware bugs may be fixed (user, 2026-09-28): with a test that
  fails on the release, noted under "Firmware behaviour the tests pinned
  down".
- From the menu port: an assembler equate to a label defined further down
  (`dpy_menu_title = far_draw_menu_title`) came out 0 with no error; use a
  stub or label. SDCC `switch` jump tables and `*p = f()` keep a value in
  an IX frame across the call: dispatch with `if` chains on a static,
  store call results in a static first. Per-function check:
  `awk '/^_[a-zA-Z0-9_]+:/{fn=$1} /\(ix\)|enter_ix/{c[fn]++} END{for(f in c) print f, c[f]}' build-c/X.asm`.
  Byte loops over NV with static pointers are about twice as slow as the
  asm (ALLrSt powered off 59 ms late): use a leaf with register pointers.
- From the scanner port: the C build's mainline is slower per pass
  (~1-10 % per scan step, up to ~14 ms a pass on a P8N), so timed stimuli
  meet different states in the two builds. `test_scan_diff.py` compares
  what the scanner does instead: the channel visits (difftest `visits`,
  breakpoints on routines), aligned for a lag, each stay within a
  tolerance, with channel-bound signals (`World`) and full checkpoints
  only when stopped. Loops that run per channel or per memory slot must
  not call helpers per item (a library divide and multiply per memory
  slot cost ~0.3 ms each; the port skips unscanned memory blocks whole).
- `tools/mutate.py --jobs N` builds each mutant in its own temporary copy
  of the firmware tree (TMPDIR), so mutants run in parallel and the repo
  is never modified; `R58_NV_CACHE` gives each its own SAnE NV cache.
  **A new differential test file needs its `R58_X_CAND` prefix in
  `ENV_PREFIXES`** (mutate.py), or it silently tests the unmutated build
  and every mutant "survives".
- From the key handler port: key timing in scenarios. `key_time` steps
  about once a second: for '#'/'R'/'S' at ~1.2/2.2/3.2 s of hold, for a
  held digit at ~0.6/1.65/2.65/3.65 s (from the long press); pick holds
  mid-step. A repeating key starts a 30 ms blip (OUT0 bit 6) per repeat,
  so compare only RAM mid-hold there. **CU58AF:** the handset signals only
  changes (/INT) and the firmware reads a release 90-100 ms after it; a
  press before that read is lost (both builds), so scenario gaps after a
  release need >= 150 ms (`test_menu_diff` walk had 100 ms and flipped
  on a 2 ms systick phase shift). CU58AF scenarios take 30 ms of
  tolerance everywhere (`test_diff.test_every_key_cu58af` too).
- **Per-pass/per-step cost:** before porting code the scanner or the
  mainloop runs every step, measure the step (difftest `_visits` on the
  "all rejected" scan: asm 7.4 ms, `C=1` 9.2 ms before the RFC port).
  C's 32-bit arithmetic is slow: the RFC slot in C added 1.2 ms, so it
  stayed asm.
- `tools/link.py` now removes its .ihx/.map when a check fails (the
  `c_bss` overflow left an .ihx behind and the next make did nothing).
- From the PTT port: the digit buffer survives a CCIR call (clear it
  between scenario cases); set a report due only after the condition it
  waits for holds (squelch open *first*); TX seconds counters
  (`transmitter_hours_second_counter`, `mprs_report_timer`) flip on a
  few ms of keying offset, so difftest `ignore` takes NV field names and
  probes leave such counters out; the SAnE bands are all 70 cm with step
  0, so set-up save/restore code needs a poked band with another step to
  be visible.

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
decided otherwise; the bugs still in place are collected in
notes/open-bugs.md):
- TOT: v3_Z powered down at the (N+2)th minute boundary after TX on
  (N+1…N+2 minutes of TX; r58.asm L2451-2462/L13050). **Fixed 2026-09-28**
  (user decision): now N…N+1 minutes (the firmware clock ticks whole
  minutes, so this is the finest it gets), 255 = no limit, 0 = no TX.
- Every CW message costs at least 400 ms: `send_cw_prolog` jumps into
  `send_cw_epilog`, and both wait 200 ms (r58.asm L15996/L16009).
- SAnE does not reset CFG_DYN records (`reset_menurec` L17684), so the
  squelch level stays 0 after SAnE although its REC default is 127. Kept
  (user, 2026-10-01).
- cSEC records (scan rates, squelch open delay) hold 10 ms units and show
  a fake trailing 0: typing "150" stores 15 = 150 ms, as meant (listed as
  a dropped digit until 2026-09-30).
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
  counts only; `test_scan_rptr.test_fast_cw_and_high_pitch`. The other
  callers, audited 2026-09-30: `freq2div` divides by 10, 15 or 25 only
  (exact, carry included), the MPRS maths by 100; `init_LPF` was wrong,
  see the TX low-pass entry.
- MPRS distance/bearing (QRB) was wrong for nearly every received position:
  `centiminutes_to_meters` (east-west metres) kept the hundredths of a
  minute in A, adding hundredths × 655 m (a station 13.5 km east showed
  22.1 km, one 457 m north "20.0 km E"), and its `pop bc` overwrote the
  multiplier's upper byte, so from 256 minutes of longitude difference on
  the result was garbage (345' west showed nothing). **Fixed 2026-09-28**
  (obvious bug, asm and C); `test_fsk.Qrb` against a model of the flat
  formula.
- GE:CtCSSt on a memory channel changed the VFO's TX tone
  (`cfg_ctcss_tx_hz`), not the memory's (`mem_ctcss_tx_hz`, which TX uses
  there): `load_menu_ptr` swapped only BYTE records, and CtCSSt is a TAB
  record. **Fixed 2026-09-29** (user decision): TAB records swap too (asm
  and C); `test_menu_power.MenuMemoryCtcss`.
- Temporary rejects: `add_reject` compared a slot's middle byte with the
  new frequency's low byte (`cp (iy+0)`), so rejecting the same
  frequency again took a second slot, and a reject whose middle byte
  equalled the new low byte was overwritten. **Fixed 2026-09-29**
  (obvious bug); `test_scan_rptr.Rejects`.
- CTCSS TX with the RFC DAC or FX465 method (PH:CtCGEn 1/2) played the
  wrong tone: GE:CtCSSt is a TAB record (an index into the tone list,
  which the i8254 method uses as one), and `ctcss_generator_on` /
  `ctcss_fx465_on` passed that index as Hz (97.4 Hz, index 12, played as
  12 Hz on the DDS; the FX465 found no tone for most settings). The RX
  setting CtCSSr is a BYTE in Hz and was right. Probably left over from
  the OH5NXO/OH1E change that made CtCSSt a table. **Fixed 2026-09-29**
  (obvious bug): `get_ctcss_tx_tone_hz` maps the index to rounded Hz
  (`ctcss_tone_hz`, from the same `CTCSS_TONES` list); `test_ctcss.py`.
- Scan tail 255 (b1:SCtAIL, "listen for ever" in the comments) was the
  same as 0: 255 skipped setting `scan_timer_secs`, which the settling
  wait leaves at 0, so the tail ended at once. Worse than it looked: on
  arrival the squelch has not opened yet (hangtime), so the scanner goes
  to the tail first, and with 255 it stepped on before the signal could
  hold it: it never stopped on a signal. Patience 255 was right.
  **Fixed 2026-09-30** (obvious bug): 255 waits until the signal returns or
  a stop key; `test_scan_rptr.test_tail_255_listens_for_ever` (fails on
  the release). `test_scan_diff` no longer compares tail 255 with the
  reference.
- MBUS logger format (`cfg_mbus_mprs` 4) printed `gps_utc` up to EOS;
  before the first GPS fix there was none and it printed the RAM after
  it. **Fixed 2026-10-01** (user decision: zeros): six characters,
  000000 before a fix (bss); `test_fsk.FskRx.test_mprs_to_mbus_logger`.
- MPRS position (`mprs_degmin_pack`): only 'W' set the sign bit, so a
  southern latitude was sent as northern, and the own locator was the
  northern one. And the locator of any packed position
  (`packed_latlon_to_locator`: the own one and every received station's)
  counted the south/west sign bit as hundredths above .50 and took
  exactly .50 as below, so southern, western and x.50' positions came out
  half a minute (and a last digit) off. **Fixed 2026-09-30** (user
  decision): 'S' sets the bit, the fractions mask it and .50 is in the
  upper half; `test_signalling.OwnLocator`, `test_fsk.ReceivedLocator`
  (against a Maidenhead model; fail on the release). The reference
  comparisons in `test_aprs_diff`/`test_gps_diff` keep to north/east and
  avoid .50. Exactly on a cell edge a southern/western last character
  was still one low (the mirror of the northern locator lands in the
  lower cell): **fixed 2026-10-01**, `edge_step` takes 0.01' off a
  southern/western value before mirroring (0.00 S/W counts as N/E);
  `test_signalling.OwnLocator.test_edges`,
  `test_fsk.ReceivedLocator.test_edges` (an integer Maidenhead model).
  `test_aprs_diff.rx_boundaries` keeps its exactly-180° case off an edge.
- TX audio low-pass (PH:LPFILt, `init_LPF`): the switched-capacitor
  filter clock divider 2016 / (Hz / 20) used `div248`, wrong for divisors
  from 128 (settings from 2560 Hz): 10 of the 32 settings in 100 Hz steps
  loaded a wrong count, the default 3600 Hz loaded 8 instead of 11 (a
  ~5040 Hz cutoff instead of ~3665) and 5100 Hz loaded 0 (the 8254 takes
  it as 65536: no TX audio). **Fixed 2026-09-30** (obvious bug):
  `div248_full`; `test_radio.TxLowPass`.
- Remote config while a remote reply was displayed (`display_buffer_time`)
  wrote the value into the reply buffer the menu shows, not the variable
  (on a DYN or RST record it would have called into that RAM), and the DC
  reply and the menu's config query took the buffer's address too:
  `load_menu_ptr` swapped for every use. And the record search compared the
  slot after the last record (TAB data, a pointer field like 0x43FF), so a
  packet for that pointer set `menu_ptr = end_menu`. **Fixed 2026-09-30**
  (obvious bugs): only drawing shows the buffer (`shown_ptr`), the search
  stops at the last record; `test_fsk.test_config_enter_while_reply_shown`,
  `test_config_search_stops_at_the_last_record`.
- CFGSnd sent the last NV byte twice instead of the checksum
  (`all_config_send` computed it in A, `putchar` sends C), so CFGGEt
  refused a plain CFGSnd dump. **Fixed 2026-09-28** (user decision);
  `test_mbus_config.py` checks the sum and the CFGSnd → CFGGEt round trip.
- Aisin Seiki binary GPS (PH:GPSCFG AiSin): course, centiminutes and the
  hemisphere were wrong since v3_Z, and the unit is not known to have
  been used (user). **Removed 2026-10-01** (user decision): the C
  gatherer and processor, `aisin_seiki_parse_latlon`,
  `quarter_ms_to_kmh`, the SIO even-parity set-up and the table entry.
  PH:GPSCFG is Std, SirF, SirFt, 9600Std; `gps_configure` rewrites an old
  NV's 9600Std (4) to 3 at boot. `gps_status` (GP:StAtuS) was written by
  that path only and now stays empty. `test_signalling.GpsConfig`.
- Repeater rP:tonE t (TBEEPMAX) 0 sent opening straight to beep-too-long,
  and with PTT held (which counts as an access tone) went idle → opening →
  beep-too-long → idle in one poll for as long as PTT was down (the rest
  of the mainloop stalled). **Fixed 2026-10-01** (user decision): 0 = no
  limit; `test_scan_rptr.Repeater.test_tbeepmax_0_is_no_limit`.
- `repeater_operator_ptt` was dead code (`pttcheck` returns before it in
  repeater mode, and it returned unless in repeater mode). **Removed
  2026-10-01** (user decision).
- Overlapping scan bands: slices were sorted by start only, and stepping
  out of one slice's end to the next one's start, which lay inside it,
  looped between the two for ever (later slices never scanned).
  **Fixed 2026-10-01** (user decision): `build_scan_slicetab` merges
  overlapping (and nested) slices, so each frequency of the bands is
  scanned once a round; in an overlap the step is the lower-numbered
  band's (`locate_band`, as for manual tuning), so channels only on the
  other band's grid there are not visited (a true union would cost a
  24-bit division per band per step). `test_scan_rptr.Scanner.
  test_overlapping_bands_*`; `test_scan_diff` scenarios have no overlaps.
- **Simplified 2026-10-01** (user: the C need not match the assembler
  1:1; understandable code and the overall function matter more, and
  exact assembler timing only where it matters). MPRS positions
  (`c/aprs.c`) are signed hundredths of a minute: the locator is computed
  directly (no mirror and edge step; one 32-bit division per axis) and
  the distance/bearing in plain 32-bit arithmetic (no bit-exact `div248`,
  24-bit wrapping or scratch writes to `my_coord_tmp_6bytes`). A packet
  with an out-of-range position (latitude 90 or more, longitude 180 or
  more, minutes 60, hundredths 100) is taken as one without a position:
  call shown, no locator, distance, MBUS or GPS-upload position (v3_Z
  computed garbage from it); `test_fsk.PositionRange`. NMEA number fields
  reject every non-digit (v3_Z only those below '0', storing a letter as
  its value minus '0'), and a two-digit piece is written only when both
  are digits; `test_signalling.GpsNumbers`. `test_aprs_diff` keeps to
  in-range positions and compares the distance only below 2^24 m per axis
  and the direction bits only with a distance shown (the reference left
  them half set otherwise); `test_gps_diff` has no non-digit cases.
  Locators checked against the integer model on 600 random own and
  received positions. Bank 2 -266 bytes.
- Tone tables (`calculate_sintab`: the CTCSS DDS, DTMF and AX.25 sine
  tables, built before each CTCSS start, manual DTMF tone and APRS packet)
  multiplied by repeated addition: 31-220 ms of silence each time (58 ms
  before every APRS packet at the default gain on a P8E, 110 on a P8N).
  **In C since 2026-10-01** (user: assembler kept for timing only where
  the timing matters): `c/ptt.c make_sintab` with a quarter-wave
  symmetric loop, 11 ms (20 ms on a P8N) whatever the gain; the same
  tables byte for byte (checked over gains, centres and both cards)
  except for a centre of 0, where the old loop's gain 0 ran 256 times and
  wrapped (now flat; RFC 0 does not happen on a tuned radio).
  `test_signalling.ToneTables`; the TX differential scenarios pin the
  AX.25/DTMF gain at 12, where both builds take about as long.
- Scanner busy-channel settling time never doubles (`squelch_open` is
  always 0 right after a frequency change): kept, the timing users know
  (user, 2026-10-01).

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
  (`make banktest` prints both pages' sums, currently bank 1 24B0, bank 2
  ED48, from the C build since 2026-09-29; C000 = an erased page); `b1 CA11 vv` = sum fine but
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
- **Done: setup menu engine in C, bank 1** (2026-09-28), `c/menu.c`
  (`#pragma bank 1`, the first banked C in bank 1): drawing (title, every
  record type, the DYN drawers, histories), `load_menu_ptr` as
  `value_ptr`, ENT (toggle, positioning by digits, the safety delay),
  walking, typed values, +/-, `*` defaults, `remote_config_execute`,
  `leaved_setup`, the DYN change routines and every RST routine (SAnE and
  band defaults, ALLrSt, CFGSnd/CFGGEt, CH rSt, rFcrSt, rEboot).
  Stays asm data in bank 1: the 285 REC records, TAB/STR tables,
  `menu_quickspots`, `defaults_70cm/2m/6m`; `rfc_fill_blanks` stays fixed
  asm. The DYN/RST records point at the C routines through the renames at
  the top of r58.s (`#define menu_sql_change _menu_sql_change` ...), so the
  REC lines are the same in both builds. Stubs: the `far_*` ones call C
  directly, except `far_remote_config_execute` (asm callers pass DE =
  ptr, HL = data; C takes HL, DE: `ex de, hl` first); `fsk_menu_ptr` and
  `fsk_remote_config_execute` call `_menu_value_ptr`/
  `_remote_config_execute` (no more swap); `dpy_menu_title/lower_row`
  are plain stubs (C keeps the cursor in `dpy_cursor`). New shims:
  `dpy_val255`, `dpy_word`, `dpy_freq_signed`, `dpy_str_rj(_scores)`,
  `dpy_history`, `menu_a2i` (AHL → HLDE), `menu_a2i_word`;
  `cfg_image_buffer` = `_end` (CFGGEt's receive buffer; C cannot name
  `_end`). Record layout, CFG_* values and constants asserted in r58.s.
  3074 bytes of C for ~2.1 KB of asm (1.5×); no IX frame except in
  C-only leaves. As in the asm build, the ENT safety delay, `waitkey`
  and CFGGEt's `getchar` loop busy-wait with bank 1 selected (multiboard
  readers off meanwhile); could go through `bank0_call` if that matters.
  Kept bit for bit: the cSEC entry (not a bug, see above), SAnE not resetting
  DYN, the search reading the slot at `end_menu`, the remote display
  buffer taking the place of the variable (open-bugs.md).
  Safety net first: `test_menu_diff.py` (34 tests, asm build vs `C=1`):
  the whole menu walked with seeded values of every type on CU53AN,
  CU58AF and P8N (every record drawn, out-of-range TABs, full strings,
  wrap and group walking), each type's +/-/#/`*` with edge values, the
  remote display override, histories and rewind, memory CTCSS, GPIO and
  external serial side effects, the ENT safety delay (difftest gained
  `key_down`/`key_up` steps to check mid-hold), positioning, every RST
  record with and without 666, SAnE per synth card and after a reboot,
  CFGSnd as one byte stream, CFGGEt good/bad checksum/wrong length,
  remote config of every type and the special pointers.
  `test_banking.BankedC.test_menu_runs_in_bank1`: breakpoints in
  `_toggle_or_position_menu`/`_draw_menu_lower_row` with bank 1 selected
  (OUT2 0x0D) on P8E and P8N, bank 0 after. Mutation run (`--jobs 12`,
  ~15 min): 64 mutants, 62 caught, 2 equivalent (`da_rfc = rfc`, which
  `save_rfc` writes again; the null check of DYN routines, none is null).
  The first round had 11 survivors, each a scenario gap: ENT held too
  briefly (EntLen is in **seconds**, `key_time` counts ~1/s, so the long
  path needs EntLen + 1 s; the limit clamps at 10), no position landing
  exactly on `end_menu`, no DPX value with bit 22 set, ALLrSt only with
  synth card 0, `rfctab`'s last byte already 0, no 16-bit alias of 666
  (66202), the memory CTCSS scenario ending on its original value.
- **Done: the scanner in C, fixed ROM** (2026-09-29), `c/scan.c`: the
  temporary/permanent reject lists, `add_reject`/`clear_rejects`, scan
  masks (digits before S, toggles while scanning), the sorted slice table
  and the scan itself. The asm coroutine (`scanner_state` = the return
  address after each `call scanner_ret`) became a state number (low byte)
  per resume point, with the same straight-line code between them, so
  every mainloop pass does what the asm did in it. Stays asm:
  `load_num_tmp_rejects`/`unreject_timer` (the minute timer), the
  `scanner_key` UI, VIP list, `go_mem_a`. 1799 bytes of C for 1212 of
  asm (1.5×); no IX frame except in C-only leaves. Memory scanning skips
  unscanned 10-memory blocks whole (the asm tested each memory's block
  bit), so a memory step is now a little faster than the asm's.
  Two v3_Z findings: `add_reject` compared the wrong byte (**fixed**,
  separate commit), overlapping bands loop between two channels (kept,
  open-bugs), and the busy-channel double settling never happens (kept).
  Safety net: `test_scan_diff.py` (21 tests, asm build vs `C=1`; see the
  rule above): band slices (unsorted, overlapping, touching, empty, end
  below start, top-byte boundaries, nested), S8B steps, memory blocks and
  their digits, from `mem_idx` ≥ 130, no channels, stale/live/permanent
  rejects, the reject key on the VIP and the VFO, slot reuse, clearing,
  auto-reject, patience/tail incl. 0 and 255, forced squelch (paused and
  while scanning), the FSK-carrier skip, toggles, stop keys and PTT, the
  idle start, P8N. `test_scan_rptr.Rejects`. Mutation run: 49 mutants,
  44 caught; not caught: 2 equivalent (the 9x block start, the dead
  doubling), 3 timing-only (a step one or two mainloop passes early:
  dropped yields, the ≥ 130 clamp), which the per-stay tolerance cannot
  separate from the C build's pass-time spread. **2026-10-01:**
  `scanner_run` is a table of block functions (one per label stretch,
  returning the next block or a yield) driven by a loop instead of one
  function with gotos and a switch into it: the pinned SDCC took ~200 s
  on the old shape (register allocation). Same work per pass, +61 bytes
  fixed ROM; mutation run again: the same survivors plus the tail-255
  check, equivalent since the tail-255 fix (survives on the old code
  too).
  `test_aprs_diff`: tolerance 30 ms (TX_OFF of the C APRS path was 20.0 ms
  late, the known ~10 ms plus a systick, already at the 20 ms edge
  before the scanner port).
- **Done: key handlers, memories and VIP list in C, fixed ROM**
  (2026-09-29), in `c/keys.c` with the dispatch: `execute` ('#': entry,
  implied digits, VIP walk, memory store by hold length), `monitor_audio`,
  the long-digit functions (squelch/memory/frequency up, down, default;
  volume default), `up/dn_vola`, digit entry, backspace and the menu's
  letters/punctuation, `duplex_key`, `scanner_key`, `beep_or_fsk_send`;
  `save_memory`, memory up/down (`step_memory`), `go_mem(_a)`,
  `save_memory_ctcss` (bank-1 menu calls it directly), `leave_memories`,
  `remember_vip`, `next_vip`, `fill_implied` (also called by the asm
  `set_tx_freq`). The hold-length loops share `held_until(n)`. Stay asm
  (asm callers need their registers or they disable interrupts):
  `set_vola(_a)`, `force/unforce_squelch`, `clear_buffer`/`clear_key`,
  `compare_tx_rx_freq`, `point_ix_memory(_a)`, `is_key_down`/`waitkey`,
  the feedback stubs, `set_tx_freq`/`set_duplex_shift_*`, `beep1750`,
  `step_audio_dst`, `mute_squelch_selective`. New shim `keys_a2i` (digits
  → 24 bits at HL). `back_to_last_vip` had no callers and is gone in C.
  1537 bytes of C for 1171 of asm (1.3×); no IX frame except the C-only
  leaf `copy3`; `c_bss` 192 → 224 bytes (199 used). Memory layout,
  `VIP_COUNT` and `MEM_HIDDEN` asserted in r58.s.
  Safety net first: `test_keys_diff.py` (19 tests, asm build vs `C=1`):
  digit entry/backspace (incl. the clear-all repeat, from ~1.1 s), '#'
  entries of every length with two implied prefixes, the VIP walk (ring
  wrap, duplicates, a frequency differing only in its top byte, one below
  65536 kHz), PTT remembering the channel, memory store per hold length
  into slots with old contents and out-of-range indexes, up/down over
  hidden/invalid slots, wrap and none valid, default memory incl. 130 and
  the idle function, squelch/frequency/volume keys at their limits and
  unforcing, monitor short/long/forced/duplex, the duplex key's hold
  lengths, scanner key, star with 0/1/4 digits and refused, menu letters,
  keys that stop the scanner (incl. a menu digit), CU58AF (30 ms
  tolerance: key releases are seen once per 25 ms display refresh), P8N.
  Mutation run (`tools/mutants/keys.py`): 70 mutants, 69 caught, 1
  equivalent (`go_mem_a`'s `set_channel_step`, which `locate_band`
  already calls, in the asm too). The first round had 7 survivors, each
  a scenario gap (listed above as the "incl." cases), after a first run
  that tested nothing (mutate.py lacked the test's env prefix).
  Test fixes on the way: `test_menu_diff` CU58AF walk gaps (see the rule
  in "Start here"); a scenario list extended in place (`s = BOOT; s +=`)
  had leaked one test's steps into the next.
- **Done: the PTT/TX flow in C, fixed ROM** (2026-09-29), `c/ptt.c`:
  `pttcheck` (the watch loop: keys during TX, battery redraw, menu
  redraw; the release: CTCSS off, remote config from the menu, MPRS on
  key-up, TX off, VIP), `tx_error`, `beep1750`, `tx_tune_tone_maybe`,
  `aprs_ptt_check` and `spontaneous_mprs_check` (the save/switch/restore
  of the TX set-up is shared). Stay asm: `tx_on`/`tx_off`/
  `tx_on_legal_or_not` (see "What is left"), `ptt_ccir_xmit`, the marker
  and CCIR tone routines, `check_for_mprs_timer`. Shims: `ptt_error_tone`,
  `ptt_tone_count`/`ptt_1750_tone` (8254 counter 1 with DI),
  `ptt_tx_band_step` (`locate_tx_band` → IX → `channel_step_parms` → the
  synth set-up); `fsk_tx_on_failed`/`fsk_mprs_not_yet` reused;
  `tune_tone_position` (bank 1) is compared only (`link.py`
  ADDRESS_ONLY). 507 bytes of C for ~512 of asm (1.0×). **Deliberate
  difference:** the tune tone's count is a division in C; the asm
  subtracted Hz from 4032000 until it borrowed (4032 rounds at 1000 Hz,
  ~20 ms on a P8E, ~40 ms on a P8N; a 1 Hz setting would stall the
  mainloop for ~20 s), so in C the tone starts that much sooner.
  Safety net first: `test_ptt_diff.py` (15 tests, asm build vs `C=1`):
  keying traces (OUT1 TXOFF, TX power DAC) simplex/duplex/PLL delays/power/
  reverse/a short blip, handset-use side effects and the selective-call
  unmute, refusals (out of band, TOT 0) with their tone, repeater mode,
  CTCSS modes, CCIR digits (1, 2, 5, a shortcut, none in the menu), keys
  during TX on both handsets, the battery walked and wiggled by one around
  the TX thresholds (9 V warning while `txtail_timer` runs), the menu
  (remote config ask, live SqL display, tune tone), MPRS on key-up with
  CTCSS, the 1750 Hz beep, APRS on /LOCAL (a 2 m band with another step,
  the mic muted before, squelch open, a top-byte-only frequency, the
  set-up restored for the next PTT), spontaneous MPRS (squelch, idle,
  interval 0, not while the repeater transmits), P8N, CU58AF. difftest:
  a leading one-sample tone run folds into the next; trace `settle` drops
  a leading transient; `ignore` takes NV field names. Mutation run
  (`tools/mutants/ptt.py`): 49 mutants, 48 caught, 1 equivalent
  (`close_squelch` before `tx_on_legal_or_not`, whose
  `tx_cut_local_audio` closes the squelch anyway). The first round had
  22 survivors, all scenario gaps (the SAnE bands, stale digits, a
  report racing the squelch, the TX-time warning threshold, no remote id).
- **Done: the mainloop and its per-pass checks in C, fixed ROM**
  (2026-09-29), `c/mainloop.c`: `mainloop` (boot jumps to it), the NMEA
  and Aisin Seiki gatherers of `gps_check`, `script_check`,
  `idlefn_check`, `bus_rf_relay`, `dim_lights_if_idle`, `redrawcheck`,
  `ccircheck`. New stubs `gpsc_sentence`/`gpsc_aisin` (A through
  `bank2_call`). 454 bytes of C for ~285 of asm (1.6×); no frames.
  Safety net: `test_mainloop_diff.py` (9 tests): the gatherers (split
  receptions, ring wrap, too long, 99/100 stored characters, `$`
  restarts, junk, a batch piled up while PTT holds the mainloop), hook
  scripts (incl. a stale `key_time` after a long press), the idle
  function, the MBUS→RF relay, light dimming (traced), the CCIR ding,
  P8N. Mutation run (`tools/mutants/mainloop.py`): 41 mutants, 39 caught,
  2 equivalent (a 10-character sentence processed or not: junk either
  way; `key = 0xFF` before a script key: `keycheck` ran earlier in the
  pass). The first round's 5 real survivors were scenario gaps (the
  gatherer only ever saw a byte or two per pass, the 5 pressed after the
  long press reset `key_time`, the dimming second).
- **Done: the display indicators in C** (2026-09-29), `c/display.c`:
  `draw_dpx_ind`, `draw_ctcss_and_mute_and_gps_ind`, `draw_squelch_ind`
  (the `dpy_squelch_ind` shim is gone), `set_dpx_ind_from_rx_tx_freq`
  (compares the 24 bits itself). `redraw` stays asm (sets DPYSIR
  atomically). Segment writes are C read-modify-writes: only mainline
  writes `segments` (the display interrupt reads it). Segment numbers
  asserted in r58.s. 284 bytes of C for ~238 of asm. Safety net:
  `test_display_diff.py` (3 tests, both handsets and P8N; a TX differing
  from RX only in its top byte is poked: the TX grid never produces one).
  Mutation run (`tools/mutants/indicators.py`): 16 mutants, all caught.
- **Done: the RFC table fill in C** (2026-09-29), `c/freq.c`:
  `rfc_fill_blanks` (dF:rFcFIL; the REC points at C through the
  `#define`) and the line interpolation `rfc_fill_one_hole` (a C-only
  leaf with locals). 271 bytes of C for 106 of asm (2.6×: SDCC's code for
  the 16-bit sum). The lookup stayed asm (see the per-step rule). Safety
  net: `test_rfc_diff.py` (4 tests: the fill's slopes, 8-bit wrap, the
  barrier, random tables; the lookup per frequency into the DAC, P8N).
  Mutation run (`tools/mutants/rfc.py`): 13 fill mutants, 11 caught, 2
  equivalent (`dx <= dy`: both branches draw the same line when equal;
  an extra outer iteration). `c_bss` 224 → 256 bytes.
  Test fixes: `test_ptt_diff.test_aprs_local` waits 1.2 s after /LOCAL
  (the arrows stay stale until a periodic redraw), `test_diff` CU58AF
  every-key at 30 ms.
- **Done: the TX split and duplex shift in C** (2026-09-29), `c/keys.c`:
  `set_tx_freq`, `set_duplex_shift_neg`/`_pos` (static: only
  `duplex_key` calls them); `compare_tx_rx_freq` and
  `point_ix_memory(_a)` had no caller left in the C build and are
  compiled out there. 108 bytes of C for 133 of asm. `test_keys_diff`
  `test_duplex_key` gained a split from a memory with RX ≠ TX and
  negative shifts that carry (256, 65536); mutation run
  (`tools/mutants/split.py`) 9/9.
- **What is left, and what gates it:**
  - See "What is left" in "Start here".
  - The real-board bench test still has to confirm both window pages.

### Future: EPROM1
- P8E: 27C010, 8 × 16 KB pages, A14/A15/A16 = OUT2 bits 0/1/3. Bit 3 is
  also held at 1 today, so the "current" EPROM1 page is 4 when unused.
- P8N: 27C512, 4 pages, RA15:RA14; bit 3 is SMEM there (must stay 1).
- The page-bit tables in `bank_select` must allow EPROM1 banks, so keep the
  bank id abstract (bank → OUT2 bits per card), not raw OUT2 values in C.
- Using EPROM1 excludes the multiboard; that's acceptable since it is rare.
