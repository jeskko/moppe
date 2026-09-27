# Rewriting the R58 firmware in a higher-level language: evaluation

Question: would rewriting the firmware in a more modern language than Z80
assembler be doable, and a reasonable effort?

**Short answer.** A *complete* rewrite in C is technically doable. It does
not fit the 32 KB ROM with today's feature set, though, and it is a large
project with a lot of regression risk. An **incremental hybrid** is doable
now and is the reasonable path: the timing-critical core stays in assembler
and C replaces logic module by module, all checked against the emulator
test suite. I demonstrated this on the real firmware (below). Rust, Zig
and the like are not options on this CPU.

## What the firmware is (measured)

| Fact | Value |
|---|---|
| Source | 19,568 lines; 10,763 instruction lines, 743 named routines/labels, 288 setup-menu records |
| ROM use | 32,721 of 32,768 bytes: **47 bytes free** (the changelog shows features being dropped to fit: "had to drop i8253 code to fit into 32kB", "FX614 stuff jettisoned, tight fit") |
| RAM | 16 KB: 4 KB battery-backed configuration block, variables, 9 KB stack/scratch |

Approximate split of the ROM by function (label address ranges; `experiments/c-density`):

| Share | What | Suited to a high-level language? |
|---|---|---|
| ~20% | Setup-menu record tables (data) | yes; tables stay tables |
| ~10% | APRS/MPRS formatting, locator and distance math | yes, the best candidate |
| ~5% each | FSK packets/remote config, synth/frequency/band math, repeater logic, UI key handling, display drivers, keypad/lights, number formatting, packet CRC/TX | yes, apart from the bit-banged driver primitives |
| ~4% | Scanner | yes |
| ~3% | GPS NMEA/SiRF/Aisin parsing | yes |
| **~6%** | Interrupt handlers (PIO systick, SIO, ADC reader, CTCSS DDS), **cycle-exact PWM loops** for DTMF/AX.25, SiRF BREAK bit-bang, P8E detection, I²C/shift-register bit primitives | **no**: must stay assembler |

So roughly 90% of the code is ordinary control logic, the kind of code a
high-level language makes much easier to write and change.

## Language options

| Option | Verdict |
|---|---|
| **C with SDCC 4.x** (or z88dk, which also uses the SDCC engine and adds banking support) | The realistic choice: mature Z80 back end, register calling convention (`--sdcccall 1`), inline and linked assembler. |
| Rust, Zig, Go, C++ | No usable Z80 back end. There are experimental LLVM Z80/eZ80 forks, not something to build a radio on. |
| Forth | Very compact threaded code and interactive on target, but slow, niche, and a different programming model. Not worth it for a rewrite. |
| Small Z80 languages (Millfork, Cowgol, Boriel BASIC, PL/M-style) | Interesting but immature or aimed at other targets; little tooling, few users. |
| A better assembler (sjasmplus: structured macros, modules, Lua; or SDCC's sdas with a linker) | Cheap productivity gain even with no language change. |

### Code density, measured

The same routines written as idiomatic C, compiled with SDCC 4.4.0
`--opt-code-size --sdcccall 1`, compared with the hand-written assembler
(`experiments/c-density/measure.py`):

| Routine kind | Assembler | C | Ratio |
|---|---|---|---|
| Control logic (squelch state machine + helpers) | 234 B | 390 B | 1.7× |
| 24-bit arithmetic (`a2i`) | 46 B | 95 B | 2.1× (+ shared 32-bit multiply routine) |
| Binary→BCD | 93 B | 217 B | 2.3× |
| Packet CRCs (the assembler is unrolled for speed) | 314 B | 192 B | 0.6× |

Expect C to be **about 1.7–2× the size** of this carefully squeezed
assembler for typical logic, worse for 24/32-bit arithmetic (the firmware
does its frequency math in 24-bit register triples), and better only where
the assembler traded size for speed.

## Constraints any C code must respect

These surfaced while getting C to run inside the firmware:

1. **Interrupt context must not touch IX or IY.** The PIO interrupt saves
   only AF and BC/DE/HL (via `ex af` / `exx`). Systick runs squelch, the
   decoders and the repeater step inside it, so C called from there must
   be compiled with `--reserve-regs-iy` and must have no stack frame (IX).
2. **The assembler routines do not preserve IX**, which SDCC uses as frame
   pointer. So C that calls assembler either keeps no frame (static
   locals) or needs wrapper thunks of about 8 bytes each.
3. **The alternate register set belongs to the PIO interrupt** (E'/D' are
   its tick counters). C must never use it; SDCC doesn't.
4. **The cycle-counted loops cannot be C.** The AX.25 loop must be exactly
   280 T per cell on P8E and 168 T on P8N, with separate versions per card.
5. **The RAM layout is owned by the assembler** (4 KB NV block at 0xC000
   with an assertion-checked layout, page-aligned tables). C variables have
   to be placed into that map (the converter emits them into `_bss`), and
   NV configuration fields shared between C and assembler must be declared
   in one place.
6. **ROM budget.** Nothing new fits unless something else shrinks.

## The ROM-size question and the hardware

Estimated size of a full C rewrite with today's features: about 26 KB of
code × 1.7–2.0, plus 6.5 KB of tables, plus 1–3 KB of runtime ≈ **52–62 KB**.
That does not fit the 32 KB the firmware uses.

The P8E schematic (3C 305838, parts list) suggests the board has room
(**read from the schematic, not tested on hardware**):

- EPROM0 (IC15) is a **27C512** (64 KB). The address logic (IC10-IC12) maps
  its top 16 KB into **0x8000-0xBFFF when OUT2 bit 2 ("RS") = 1**. That is
  48 KB reachable in total.
- A second socket, EPROM1 (IC16), is a **32-pin 27C010** (128 KB), mapped
  at 0x8000-0xBFFF when RS=0, with **A14/A15/A16 = OUT2 bits 0, 1, 3**:
  eight 16 KB banks. The community DTMF/CTCSS "multiboard" currently plugs
  into this socket; the firmware reads it at 0x80xx.
- The firmware never uses RS/RA14-16; on P8E OUT2 bit 3 is RA16, and the
  firmware's comment that SMEM moved to a separate flip-flop (port 0xB0) on
  P8E agrees with that.

So on P8E a larger firmware is plausible: 16 KB more in the RS window
without touching the multiboard, or far more with banked EPROM1 if the
multiboard's function is moved. Banked code in C is workable (z88dk
supports it), but it adds real complexity: interrupt code that reads the
multiboard must switch RS back, and cross-bank calls need trampolines.
The P8N's memory decoding is different (RA14/RA15 appear to bank RAM
there) and its schematic isn't available, so a large firmware may be
P8E-only. The service manual now in `reference/` should settle this;
see notes/hardware.md.

## Proof of concept: C inside the existing firmware

`make -C firmware C=1 SDCC=...`:

- `firmware/c/squelch_crc.c` replaces the **squelch state machine** (runs
  in interrupt context, calls a dozen assembler routines) and the three
  **FSK packet CRC** routines.
- SDCC compiles it to assembler; `tools/sdcc2as80.py` converts that to the
  as80 dialect. The result is `#include`d under `#ifdef C_MODULES`, with its
  RAM placed in `_bss`. The default build stays byte-identical to the release.
- **All 29 emulator tests pass on the C build**, including squelch
  open/close, FFSK MPRS packet CRCs, and the cycle-sensitive DTMF/APRS
  tests. The ROM has 95 bytes free instead of 47, because the C CRC loop is
  smaller than the unrolled assembler.
- The tests caught three real bugs on the way: IX clobbering (stack
  corruption and a watchdog reset), label scoping in the converter (a
  wrong branch), and IY use in interrupt context.

That is the development loop a hybrid approach needs, and it works today.

## Options compared

| | A. Stay in assembler, better tooling | B. Incremental hybrid (recommended) | C. Full rewrite in C |
|---|---|---|---|
| What | Emulator + tests (done), optionally move to a maintained assembler | Keep the assembler kernel (ISRs, PWM loops, drivers, tables); write new features in C and port logic modules when touched | New codebase: C for logic, assembler only for the kernel |
| Fits 32 KB? | yes | yes, module by module (C must replace more than it adds; the space-trading modules, such as unrolled code, go first) | no; needs the P8E 48 KB/banked map |
| Effort | low | moderate, spread over time; each module ~hours to days with the test suite | large: rough order of several hundred hours for feature parity, dominated by re-verifying 20+ years of accumulated behaviour |
| Risk | low | low to moderate, each step verified in the emulator | high: subtle behaviour (typematic timings, scanner, repeater, APRS formats) is easy to lose |
| Benefit | faster iteration | most new work in C; the codebase gets readable over time | cleanest result, if finished |

## Recommendation

1. **Use the emulator and tests as the development loop now.** Most of the
   "assembler is painful" cost is the edit-burn-test cycle, which the
   emulator removes. Add a test for each behaviour before changing it.
2. **Go hybrid (option B).** New features in C. Port a module to C when you
   need to change it anyway, preferring modules where C is compact (table
   lookups, parsers, formatting) or where the assembler is unrolled. Keep
   ISRs, PWM loops and bit-bang primitives in assembler.
3. **If more space is needed**, try the P8E RS window (16 KB, 27C512 already
   fitted per the parts list) in the emulator first, then on hardware.
   Treat banking as a separate project.
4. **Optionally, move to a maintained toolchain.** Converting the as80
   source to sdas/sjasmplus syntax is mechanical, and "the new build must
   be byte-identical to the release binary" is an exact acceptance test.
   That would let C modules link normally instead of being converted and
   #included.
5. **Hardware tip for when you do burn.** Electrically erasable,
   pin-compatible parts (Winbond W27C512, SST/Microchip 27SF512) or an
   EPROM emulator module avoid UV erasing entirely.

A full rewrite (option C) only becomes reasonable if the goal is a
different radio: new architecture, a reduced or re-designed feature set,
P8E-only. Even then, the emulator and this test suite are the way to
build it.
