# R40 ham firmware

A new firmware for the Nokia R40 (RC40/RD40, H8/532) in C with
assembler where timing needs it, built with the lcc back end and the
patched GNU binutils ([h8500-compiler.md](h8500-compiler.md)), run and
tested in moppe-emu's R40 emulator. Hardware facts, the Nokia ROM and
the gaps are in [r40.md](r40.md) ("Ham firmware: what is known").

MVP wanted: VFO with duplex split, memory channels, VFO and memory
scan, settings (squelch etc.), CTCSS encode if the hardware allows.

## Start here (next session)

State (2026-10-06): `make -C r40` builds `r40/build/r40.bin`;
`python3 -m unittest test_r40fw` (in `tests/`) runs 10 scenarios; `make
-C r40 run` opens it in the emulator's TUI. It boots, shows "R40 ham /
Hello, world" and a seconds counter and the last key; UP/DOWN set the
volume; PWR switches off (IC39 OFF), PWR held at power-on is ignored.
Session narrative: [r40-firmware-history.md](r40-firmware-history.md).

Next, each checked in the emulator before the next:

1. **RX**: PLL to a 6.25 kHz channel (RX VCO = f + 45 MHz, 128/129
   prescaler, R = 1024, OH5NXO's `pll.s`; the emulator's `pll()` reads
   it back), squelch from the noise input (AN1; high = noise) driving
   `audio_rx()`, RSSI (AN0). The RX tuning DAC (RFC, MC144111 channel
   2) wants Nokia's calibration from NV (r40.md gap 3); `dac_write()`
   exists but is unused.
2. The VFO UI (frequency entry, UP/DOWN steps; volume then moves to
   another key), then NV storage (battery SRAM at 0x80000: needs a
   NOLOAD section, so a linker script of our own or `h8cc.py
   --script`), TX (TX ON OUT1.0, PTT P7.3, TX synthesizer parked +62.5
   kHz until PTT; `audio_tx()`), duplex split, memories, scan,
   settings. Key beeps: TMO (8-bit timer) with IC41 SIGN LSP + IC40
   PWRAMP.

Open questions to keep in view: the gaps list in r40.md (CTCSS path,
calibration tables, PLL lock timing, no hardware checks yet); whether
the real CU43 needs the slower Nokia-like I2C pacing; what P1.5 does
when the PCF8574 /INT and the IRQ0 function share it on hardware (the
emulator reads the pin); whether the supply really drops on IC39 OFF
with the ignition line high (the firmware then waits for PWR and
restarts).

## Firmware layout

| File | What |
|---|---|
| `r40/start.s` | vectors (CP word + PC word), reset (page registers, RAMCR off, WCR 0xF0, data copy, bss clear, `main`), NMI/faults → reset, the FRT1 OCIA entry (saves r0-r3 and EP, EP = 8, calls `tick_isr`), `xin`/`xout` (a byte in another page via EP and r4), `ei`/`di` |
| `r40/regs.h` | H8/532 registers as C lvalues (`@aa:8`) |
| `r40/hw.c`, `hw.h` | ports, OUT0/OUT1 latches with shadows, 100 Hz tick (`ticks`), `wdog_kick` (P9.0 pulse + WDT A57F/5A00), `delay_ticks` |
| `r40/i2c.c` | PCF8584, polled: `i2c_write(addr, hdr, nh, data, nd)`, `i2c_read`; S2 = 0x11 (45 kHz, as Nokia); gives up after 2000 polls |
| `r40/lcd.c`, `font.c` | text buffer 3 x 24, dirty rows sent as `78 F0+row E0 18` + 120 columns; top row 20 characters around gap cells 2, 9, 14, 21 |
| `r40/keypad.c` | CU43 matrix, PWR, hook; `key_get()` queue of presses; a key held at power-on is not a press |
| `r40/serbus.c` | serial bus bit-banging: `sr_write(n, v)` (4094 + OUT1 strobe), `dac_write()` (MC144111, 4 x 6 bits) |
| `r40/audio.c` | the 4094 states: `audio_rx(open)`, `audio_tx(on)`, `audio_volume()`, `power_off()`; differs from Nokia in keeping RX audio muted in TX |
| `r40/main.c` | the main loop (hello + key display for now) |
| `tests/test_r40fw.py` | boot, tick, watchdog (bites without kicks), latches, LCD set-up, keys, volume, 4094 boot state, power off/on |

Conventions: C runs with DP = EP = TP = 8, BR = FF. Only `xin`/`xout`
change EP; the interrupt entry saves it and sets 8 for C. Main loop
code owns PORT9 and the latches (read-modify-write is not atomic
against interrupts).

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
