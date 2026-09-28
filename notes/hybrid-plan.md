# Plan: hybrid C/assembler firmware with banked EPROM

Decided 2026-09-28 (user). **Goal:** assembler only for what is timing
critical or awkward in C; everything else in C. ROM grows beyond 32 KB
by banking EPROM0 into the 0x8000 window. EPROM1 is not used now, but the
design must not exclude it for future features. The multiboard is uncommon,
so its socket is normally free.

Background: notes/rewrite-evaluation.md (measurements, constraints, proof of
concept), notes/hardware.md (memory decode), notes/emulator.md.

## Ground rules

- **The emulator test suite is the safety net.** Every phase ends with
  `python3 -m unittest discover -s emu/tests` passing on the new build. Add
  tests *before* porting a module whose behaviour is not yet covered.
- **Keep the stock build reproducible.** `make -C firmware verify` must keep
  passing, until Phase 1 replaces as80 and moves the byte-identical check
  to the new toolchain.
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
- Add **differential testing**: run the stock build and the candidate build
  side by side on the same scripted inputs and compare observable outputs
  (display glyphs, synth registers, OUT0/OUT1/DACs, events, NV image) at
  checkpoints. This catches regressions no hand-written expectation covers.
- Grow the emulator where tests need it: FX429 RX bit timing, MBUS
  host-side helpers (CFGSnd/CFGGEt), maybe CTCSS slicer input.

### Phase 1: one toolchain (SDCC's sdas + sdld)
- Write a converter from as80 syntax to sdasz80 (`[x]`→`(x)`, `#` for
  immediates, `!` comments, `iv`/`ex af`, `HI()/LO()`, `.rs/.byte/.word/
  .align/.fill/.cksum`, `1f/1b` local labels → unique names). Keep GNU
  `cpp -traditional` as the macro stage.
- **Acceptance: the converted source links byte-identical to
  r58p8x3Z.bin.als.** Then drop as80 and the `sdcc2as80.py` include hack;
  C modules become normal linked objects.
- Replace absolute `.org`/ASSERT layout checks with linker areas and
  explicit placement of page-aligned tables.
- Install SDCC system-wide (`pacman -S sdcc`). The session that did the
  proof of concept used a temporary download of 4.4.0.

### Phase 2: OUT2 shadow and bank infrastructure (still 32 KB)
- Add `out2_shadow` (RAM) and route **every** OUT2 write through it,
  preserving the bank bits (RS, RA14, RA15, bit 3). Today's writers use
  absolute constants: `start`, `keypad`, `display_cu53an`/`display_group`/
  `display_bit*`, `i2c_scl_low/high`, and the three NV copy loops. The
  handset bus code must OR the current bank bits into CS/CLK/DP values
  without adding jitter that matters (the CU53 and I²C timing is loose).
- **Important:** `keypad` and `display` run from the sir soft interrupt
  (`dosir`), which can interrupt banked mainline code. So OUT2 writes from
  them must keep the bank bits. That is why the shadow comes before any
  banked code.
- Bank-select API (asm): `bank_select(n)` writes the page bits from a
  per-card table (P8E/P8N) and `cpu_is_P8E`; `bank_call` trampolines in
  fixed ROM save and restore the previous bank.
- The CTCSS DSP decoder reads the multiboard at 0x80xx **from the ISR**.
  If code is banked in the window, that read returns ROM. Either
  (a) the ISR saves the shadow, selects RS=0, reads, and restores (a few
  cycles in a constant-time path; the slack must be checked), or (b) the
  DSP CTCSS decoder is unavailable while the window holds code, or (c) only
  in multiboard-less builds. Decide in this phase; (b) plus a build option
  is likely simplest, since multiboards are uncommon. The DTMF decoder read
  runs in systick (ISR), same issue.
- Tests: emulator banking tests (`emu/tests/test_banking.py`) plus a
  firmware test that runs code from the window while the soft interrupt
  redraws the display.

### Phase 3: banked EPROM0 (48 KB)
- **Portable page:** OUT2 = RS|RA14 (bit 3 kept at 1) maps EPROM0 chip
  0xC000-0xFFFF into 0x8000-0xBFFF on **both** P8E (schematic) and P8N
  (manual). Verified in the emulator model only; **confirm on a real board
  early** (a tiny test ROM that checksums the window and shows the result
  on the display).
- P8N has a second EPROM0 page (chip 0x8000, RS=1 RA14=0); P8E cannot reach
  it. Don't depend on it, or make it P8N-only.
- Image layout: 64 KB file; 0x0000-0x7FFF fixed; 0x8000-0xBFFF unused
  (unreachable on P8E); 0xC000-0xFFFF = bank 1. EPROM: 27C512 (or W27C512 /
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

### Future: EPROM1
- P8E: 27C010, 8 × 16 KB pages, A14/A15/A16 = OUT2 bits 0/1/3. Bit 3 is
  also held at 1 today, so the "current" EPROM1 page is 4 when unused.
- P8N: 27C512, 4 pages, RA15:RA14; bit 3 is SMEM there (must stay 1).
- The page-bit tables in `bank_select` must allow EPROM1 banks, so keep the
  bank id abstract (bank → OUT2 bits per card), not raw OUT2 values in C.
- Using EPROM1 excludes the multiboard; that's acceptable since it is rare.
