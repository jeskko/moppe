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

## 2026-10-06/07: CTCSS

The tone source is TMO. OH5NXO's "final Hz = TMO / 8" does not fit the
Nokia firmware: its CCIR table (8:2051, used by 0x1D2AB: phi/64, toggle
on compare A) gives 1125 Hz for '1', 1000 for 'D' and so on directly on
TMO. Timer division alone is too coarse for CTCSS (phi/1024: 88.5 Hz
comes out 1.1 % off), so an 8 kHz compare interrupt runs a phase
accumulator and sets TMO's next level. Two slips found by measuring:
compare 124 gave 8064 Hz (the counter clears after compare + 1 counts),
and a truncated increment ran 0.1 Hz low. The emulator showed TMO only
to a bus callback the board did not hook: moppe-emu ee44234 counts its
rising edges (`Radio.tmo_rises()`). lcc drops a bare volatile read
(`(void)REG;`): the firmware stores such reads.

## 2026-10-06: transmit

Nokia's PTT in simplex (emulator events, ~3 ms after /PTT): IC41 00,
DAC load (all 0 on the r40nv image), TX synthesizer to f, TX ON 0.6 ms
later (no lock wait), IC39 0A, then 08 6 ms later. Release: IC39 09,
TX OFF, synthesizer parked, IC39 back to the squelch state 13 ms later.
Ours follows it except the last IC39 step in TX (RX audio stays muted)
and a 10-20 ms PTT debounce (two ticks).

## 2026-10-06: duplex, memories, scan

Key layout grew on FNC: # duplex, * shift, 0 reverse, 1 step, RCL
store, 9 scan, UP/DOWN volume. STO first switched to memory mode, which
made "store, then type the next frequency" impossible (in memory mode
digits pick channels); it now keeps the mode. TX is limited to 430-440
MHz. The scan's dwell (3 ticks for the PLL, 2 for the squelch) is a
guess until the lock timing is known (r40.md gap 5). Scan tests drive
the noise input from the RX synthesizer's frequency in 5 ms slices
(`run_with_signals`), as the emulator has no RF model.

## 2026-10-07: Nokia's calibration

Mapped in the emulator by diffing NV around the service tests (r40.md
NV RAM table). 172 + 190002 wrote D-band defaults only to the working
copy; FNC STO in 36 / 20x / 21 / 33 / 34 commits a test's whole table,
plain STO does not, and power-on copies the committed copy over the
working one. So the r40nv image had empty committed tables (the "DAC
all 0" of the transmit entry below) and Nokia ran on zeros: r40nv now
commits them with FNC STO in 36 and 201. Distinct values in the tables
and `*55*30#` / `*55*31#` showed how Nokia indexes them: floor of the
MHz above 400 (433.5 → 33, 434.9875 → 34), TX power level 2 in simplex
TX, level 3 loaded in RX, deviation bits set in RX and TX alike. With
the MC144111 datasheet (last word → Q1) Nokia's two-word loads put RFC
on Q2 and TPC on Q1, which our `dac_write(rfc, tpc, rfc, tpc)` already
matched. Sweeping AN1 in simplex: Nokia mutes above 0x6C and opens
below 0x6D; its defaults (136 / 133) are hysteresis that way round, a
real calibration (-114 / -118 dBm on a noise reading) would be the
other way, so `cal.c` takes the lower as open and the higher as close.

Firmware: `cal.c`; menu TX power low/mid/high and RX tune as a trim;
squelch "cal" the default. The emulator's idle AN1 was 512, below
Nokia's default open level (532), so a "no signal" radio was open with
Nokia's own levels too: moppe-emu now idles at 600.

## 2026-10-07: RX self-calibration

Assumption (user's call): with no signal the RSSI is highest where RFC
tunes the front end. The emulator got a front-end model (optimum RFC
per MHz, RSSI falling as 16 / (16 + d^2)); Nokia's automatic test 36
(OK twice) found the model's peak, so Nokia's search is the same
RSSI-peak idea (with a generator signal). `cal_self()` sweeps RFC at
six points in 430-440 MHz and recovered an optimum curve offset from
Nokia's table exactly, odd MHz by interpolation. A key stops it and
keeps the previous table.

## 2026-10-08: 2 m on the RC40; an lcc register-allocator bug

Nokia's PLL words on the C band (emulator, service test 154 at 145 MHz)
differ from D only in the prescaler (SW = 1, 64/65); IF, parking and
raster are the same. The band byte (0x63: C 0x40, D 0x80) and the
0-channels are written straight to the committed copies by tests 15x
and 18, so a first read of the working copy showed D values. 171 +
190002 loads the same tables as 172: no C-band defaults in Cr 13.04.
Nokia's cold-start working copy has deviation 7 everywhere: the earlier
"defaults 0" was the committed copy without test 21; our fallback now
uses 7.

`band.c` selects the band (Nokia's byte, or the menu for a lost NV).
The memory range check made rcc spin: lcc's `spillee` could not free a
pair whose halves held single-register values (assertion in one case,
endless spilling in another). Allowing temporaries in r4-r5 only hid
the small case (300 random programs found another); the fix is in
lcc's `spillee` (h8500-compiler.md). The 2 m self-cal test found an
edge effect in the RFC smoothing (a peak at 1 came out as 0) and needed
the emulator's front-end model to take a base frequency.
