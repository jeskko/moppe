# R40 ham firmware

A new firmware for the Nokia R40 (RC40/RD40, H8/532) in C with
assembler where timing needs it, built with the lcc back end and the
patched GNU binutils ([h8500-compiler.md](h8500-compiler.md)), run and
tested in moppe-emu's R40 emulator. Hardware facts, the Nokia ROM and
the gaps are in [r40.md](r40.md) ("Ham firmware: what is known").

MVP wanted: VFO with duplex split, memory channels, VFO and memory
scan, settings (squelch etc.), CTCSS encode if the hardware allows.

## Start here (next session)

Nothing of the firmware is written yet. The toolchain is ready (all
tests pass, `tools/h8500/test/run.sh`). Steps, each checked in the
emulator before the next:

1. **Layout and build.** Proposed: sources in `r40/` (C, `.s`, linker
   script, Makefile), firmware scenario tests in `tests/r40/` (pytest
   with `emu/python/r40emu.py`'s `Radio`, as `emu/tests/r40/` does for
   the Nokia ROM). h8cc.py builds h8run programs with its own crt0 and
   script; for the firmware add a way to pass a start-up file and a
   linker script (`--crt` exists; add `--script` or let the Makefile
   call rcc/as/ld directly). Run with
   `python3 emu/python/r40tui.py --rom r40/build/r40.bin`.
2. **Start-up** (`r40/start.s`): vectors (4 bytes each in maximum mode:
   page word + PC word, r40.md "Hardware"), page registers (DP = TP = 8,
   BR = 0xFF, EP 0 except while used), stack, data copy and bss clear
   as `tools/h8500/lib/crt0.s`, ports, interrupt priorities, the
   watchdog kick (`watchdog_kick` 0x1CE91 in the Nokia ROM: P9.0 high
   for a few µs, then WDT reload A57F/5A00), then `main`. OH5NXO's
   `start.s` covers most of this (below) but differs in two places
   to settle against the Nokia ROM: WCR 0xF0 (no wait states; Nokia
   uses 0xF1, the FX429 needs a wait state) and the on-chip WDT used
   as a 123 Hz tick instead of a watchdog.
3. **Display hello**: PCF8584 I2C → CU43 LCD (own font), from C.
4. Keypad (CU43 via I2C; ALPHA/handset/HF/F1 still unmapped), then RX:
   PLL to a 6.25 kHz channel (RX = f + 45 MHz), audio/squelch (AN1),
   RSSI (AN0), power-off. Then the VFO UI, NV storage (battery SRAM at
   0x80000), TX (TX ON OUT1.0, PTT P7.3, TX synthesizer parked +62.5 kHz
   until PTT), scan, memories, settings.

Open questions to keep in view: the gaps list in r40.md (CTCSS path,
calibration tables, 4094 bit meanings, PLL lock timing, no hardware
checks yet).

## Decisions

- **Memory model: small** (2026-10-06). Code and the initialized-data
  image in page 0 below 0xFF80 (the link fails with a clear message
  otherwise); data, bss and stack in page 8 (SRAM 0x88000-0x8FFFF;
  NVRAM 0x80000-0x83FFF is page 8 too). No banking on the R40: the
  EPROM is 0x00000-0x3FFFF, pages 0-3. If constants crowd RAM or page
  0, first move big tables (font, frequency/channel tables) into pages
  1-3 and read them through an EP helper; only if code outgrows page 0
  go to the **medium model** (code in several pages, near data): PJSR
  @aa:24 / PRTS calls (+1 byte each, 4-byte return addresses, frame
  offsets +2), helpers called with PJSR, function pointers via page-0
  stubs (lcc has one pointer size), functions placed per page by the
  linker script (ld does not keep them from straddling). Large-data
  models (24-bit pointers, DP/EP loaded around every far access) are
  not needed: all RAM is in page 8.

## OH5NXO's R40 bring-up (reference/oh5nxo/mods/R40/, 2008)

GNU as (h8500-hms) sources: `vectors.s`, `start.s`, `util.s`, `sci.s`,
`serbus.s` (4094s, MC144111, DS1202 RTC, FX803), `fx429.s`, `cu42.s`
(control head), `i2c.s` (PCF8584), `pll.s`, `tonegen.s`, `cfg.s`,
`lcdfont.s`, `regs.inc`, `macros.inc`, `PINS` (pin and latch map),
`r40.ldscript`; `r40.s`'s `main` is an empty loop (the drivers are a
library, not an application). Conventions (`RULES`): DP = TP = 8,
BR = 0xFF, EP restored after use (0 by default), serbus at IPL 3. His
layout is the same as ours: code from 0 in page 0 (below 0xFB80, the
on-chip RAM), `.data` at 0x88000 with its image after the code.

**Builds with our binutils** (checked 2026-10-06 in a scratch copy:
all files assemble, ld links with his script): the result differs from
his `r40.bin` only by our gas's shorter `mov:g.w #-35:8,@0x2:8` (06 dd
instead of 07 ffdd), the branches after it and an alignment nop. It
runs in the emulator (blank display, as his `main` does nothing).

To use the drivers from C: check each routine's register usage against
lcc's ABI (r0-r3 caller-saved, r4-r5 preserved, arguments on the stack
right to left, result in r0 / r0:r1) and add small C-callable wrappers
where they differ. Publishing: OH5NXO's code is under the same pending
question as the rest of the project (authors asked 2026-10-01); keep
it private until he answers.
