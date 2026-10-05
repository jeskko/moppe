# R40 ham firmware: history

Session narrative; current state in [r40-firmware.md](r40-firmware.md).

## 2026-10-06: plan before the first line (the "Start here" it replaced)

### Start here, as written before the firmware existed

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

## 2026-10-06: skeleton, display, keypad

Steps 1-3 of the plan and the keypad part of step 4, each checked in the
emulator. Changes against the plan:

- Tests are `tests/test_r40fw.py` (unittest, like the rest of `tests/`, so
  `tools/ci/runtests.py` and `unittest discover` pick them up), not a
  pytest directory `tests/r40/`.
- No own linker script yet: h8cc.py's generated one with `--crt
  r40/start.s` already puts the vectors at 0 and the data in page 8.
  An `--script` option waits for the first NV section.
- The on-chip registers (FF80-FFFF) exist only in page 0, so a C pointer
  0xFF82 (page 8 by DP) missed them. The back end now takes a constant
  pointer in FF80-FFFF as `@aa:8` (BR = FF) and any other constant
  pointer as `@aa:16`; toolchain tests pass after the change.
- The on-chip WDT stays a watchdog as in the Nokia firmware (not
  OH5NXO's 123 Hz tick: a ham firmware on real hardware needs the
  external watchdog kicked anyway), and the tick is FRT1 compare
  match A. Checked: with the main loop's kick removed the firmware
  restarts every ~0.4 s.
- The PCF8584 is polled, not interrupt driven: a 124-byte LCD row takes
  ~42 ms (the Nokia firmware ~30 ms, interrupt driven). Good enough for
  now; the watchdog is kicked between rows.
- LCD rows go out as the Nokia firmware sends them: `78 F0+bank E0 18`
  then 120 column bytes. The font is the classic 5 x 7 shape set, which
  has the same 'S' as Nokia's, so the emulator's `display()` (which finds
  the font by that glyph) decodes our ROM too.
- Keypad: scanned when P1.5 (IC190 /INT) is low, and every 100 ms while
  a key is down. All 18 known keys, PWR and the unknown row-4 positions
  decode in the emulator.

## 2026-10-06: serial bus, audio switches, power-off

The 4094 bit meanings (r40.md gap 4) settled by running the Nokia
firmware in the emulator: boot, volume UP/DOWN ("Volume level n" =
IC40 bits 6-4), beeps (IC40 bit 3 + IC41 bit 7), PWR (IC39 00001101,
bit 2), service-mode PTT, and normal-mode simplex (`*55*30#` after four
CLRs) with the noise input AN1 swept: IC39 bit 1 follows it (1 =
muted on noise). Service mode never squelches (bit 1 stays 1 whatever
the inputs). The board description's numbering matches the emulator's
`sreg()` bit numbers; OH5NXO's `PINS` does not for IC40/IC41. In TX
Nokia unmutes the RX audio (IC39 08); ours keeps it muted.

Firmware: `serbus.c` (shift MSB first, strobe pulse on OUT1), `audio.c`
(the states), PWR → `power_off()`, then wait for PWR and restart (for
an ignition-held supply). The keypad's first scan at start-up now only
records the keys held, so the PWR press that switched the radio on is
not taken as "off".

## 2026-10-06: receiver, VFO screen; the emulator's DAC

Nokia never seemed to load the MC144111 in the emulator. Stepping its
DAC routine (0x2F902) showed why: it shifts two 6-bit values (12 bits)
per chip select and relies on the chip keeping the other 12; the model
waited for 24. Fixed in moppe-emu (266673f): a separate 24-bit register
clocked only while selected. Test 36 then moves channel 1 (and 3):
channel 1 is RFC, the first value shifted, not TPC as in OH5NXO's
`serbus.s`. Nokia's values in the r40nv image are all 0 (no tuning
calibration stored), so there is no default to copy.

PLL as Nokia (128/129, R = 1024; OH5NXO used 64/65): our 433.500 MHz
words equal Nokia's simplex channel's (RX 598/16, TX parked 541/122).
The VFO keys are a first choice (digits + OK, UP/DOWN step, FNC +
UP/DOWN volume); the keypad tests now read `key_down` from RAM for
keys without a function.
