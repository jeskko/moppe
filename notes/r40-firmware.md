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
`python3 -m unittest test_r40fw` (in `tests/`) runs 38 scenarios; `make
-C r40 run` or plain `python3 emu/python/r40tui.py` opens it in the
emulator's TUI (`--factory`: the Nokia firmware). A simplex VFO: boots
on 433.500 MHz (the same PLL words as the Nokia firmware's simplex
channel), frequency entry (digits, OK; CLR deletes), UP/DOWN 12.5 kHz
steps, FNC + UP/DOWN volume, duplex (FNC # simplex/-/+, FNC * shift
in kHz, default 7.6 MHz; FNC 0 reverse; TX frequency shown while
transmitting), TX only in 430-440 MHz ("LOCK" otherwise), memories 00-99 (FNC RCL
+ two digits stores; RCL toggles VFO / memories; two digits or
UP/DOWN choose), scan (FNC 9: VFO through 430-440 MHz, or the stored
memories; stops while busy, resumes 2 s after; any key or PTT ends it;
~15 channels/s: 30 ms PLL settle guess + 20 ms squelch), key beep (as
Nokia's), settings menu (FNC OK: squelch 0-9, TX time-out, beep, TX
power and RX tune as raw DAC values), CTCSS encode per channel
(experimental: menu "Tone", 50 tones, a 'T' on row 0; 8 kHz phase
accumulator on TMO through the Fii switch, measured within 0.1 Hz in
the emulator; whether sub-audio reaches the carrier is unknown), noise squelch with hysteresis switching
the RX audio and amplifier, BUSY and the RSSI reading; PTT transmits
in the Nokia firmware's order (deviation bits, DAC, TX synthesizer,
TX ON, mic); settings (VFO, memory mode and channel, volume, step) and memories kept in NV RAM; PWR
off.
Session narrative: [r40-firmware-history.md](r40-firmware-history.md).

Next, each checked in the emulator before the next:

1. **Hardware**: the MVP is complete in the emulator. Before more
   features, the open questions below want a real R40: CTCSS deviation
   (does the tone get through?), RX tuning and TX power DAC values,
   squelch scale, PLL lock time (scan dwell), keys, power-off.
2. Calibration (r40.md gap 3): read Nokia's RX tuning (RFC per MHz),
   TX power and deviation tables from the other NV half instead of the
   raw menu values.
3. Hardware checks of everything in "Open questions" below.

Open questions to keep in view: the gaps list in r40.md (CTCSS path,
calibration tables, PLL lock timing, no hardware checks yet); whether
the real CU43 needs the slower Nokia-like I2C pacing; what P1.5 does
when the PCF8574 /INT and the IRQ0 function share it on hardware (the
emulator reads the pin); what OUT0.3 (RAM PAGE) does to the NV window on hardware (Nokia toggles
it, the emulator ignores it, we keep it 0); whether the supply really drops on IC39 OFF
with the ignition line high (the firmware then waits for PWR and
restarts).

## Firmware layout

| File | What |
|---|---|
| `r40/start.s` | vectors (CP word + PC word), reset (page registers, RAMCR off, WCR 0xF0, data copy, bss clear, `main`), NMI/faults → reset, the FRT1 OCIA entry (saves r0-r3 and EP, EP = 8, calls `tick_isr`), `xin`/`xout` (a byte in another page via EP and r4), `ei`/`di` |
| `r40/regs.h` | H8/532 registers as C lvalues (`@aa:8`) |
| `r40/hw.c`, `hw.h` | ports, OUT0/OUT1 latches with shadows, 100 Hz tick (`ticks`), `wdog_kick` (P9.0 pulse + WDT A57F/5A00), `delay_ticks` |
| `r40/i2c.c` | PCF8584, polled: `i2c_write(addr, hdr, nh, data, nd)`, `i2c_read`; S2 = 0x11 (45 kHz, as Nokia); gives up after 2000 polls |
| `r40/lcd.c`, `font.c` | text buffer 3 x 24 cells; `lcd_update()` sends the changed cells of one row per call (`78 F0+row E0+dev X` + 5 bytes a cell); top row 20 characters around gap cells 2, 9, 14, 21 |
| `r40/keypad.c` | CU43 matrix, PWR, hook; `key_get()` queue of presses; a key held at power-on is not a press |
| `r40/serbus.c` | serial bus bit-banging: `sr_write(n, v)` (4094 + OUT1 strobe), `dac_write()` (MC144111, 4 x 6 bits; channel 1 = RFC) |
| `r40/audio.c` | key beep (8-bit timer as Nokia: phi/64, compare 89 then 51, IC41 SIGN LSP + IC40 PWRAMP); the 4094 states: `audio_rx(open)`, `audio_tx_prepare()` / `audio_mic()` / `audio_tx_done()`, `audio_volume()`, `power_off()`; differs from Nokia in keeping RX audio muted in TX |
| `r40/pll.c` | both synthesizers: `pll_init()` (R = 1024, SW = 0, both chips), `pll_vco(which, hz)` (N/A from the VCO frequency, 6.25 kHz steps) |
| `r40/radio.c` | `radio_tune(rx, tx)` (a new RX frequency closes the squelch and waits `SETTLE` ticks; `radio_settled()`) (RX VCO rx + 45 MHz, TX parked tx + 62.5 kHz), `radio_poll()`: PTT (P7.3, two ticks) with the TX sequence, A/D scan AN0/AN1, squelch (opens below `sq_level` = 480, closes 16 above, two ticks) |
| `r40/ui.c` | VFO state (`vfo_hz`, duplex, shift, reverse → `radio_tune(rx, tx)`), screen (row 0 frequency or entry + `-`/`+`/`R`/`F`, row 1 volume and step, row 2 TX/LOCK/BUSY and RSSI / 4) and keys; the key layout is in its header comment |
| `r40/nv.c` | settings block (`struct nv_cfg`, version 5: the VFO as a `struct chan`, memory mode/channel, volume, step, squelch level, time-out, beep, RFC/TPC) at 0x83000 (P9.2 = 0 half, emulator `nv()[0x7000:]`): magic `R4`, version, size, 16-bit checksum; `nv_save()` on every change, defaults when invalid. Nokia's copies (the other half) are left alone |
| `r40/mem.c` | memories 00-99 at 0x83100: `struct chan` (frequency, shift, duplex, reverse, CTCSS tone) + used byte + checksum byte per slot; `mem_get/put/clear/next` |
| `r40/menu.c` | settings menu; `settings_apply()` (squelch level n → threshold 600 - 20 n, 0 = open; time-out; DAC write) |
| `r40/tone.c` | CTCSS: table (0.1 Hz), `ctcss_on(t)` (8-bit timer phi/8, compare 125 = 8 kHz, CMIA level 3), `ctcss_off()`; the interrupt is `ctcss` in start.s |
| `r40/main.c` | start-up order, main loop, power off |
| `tests/test_r40fw.py` | boot, tick, watchdog (bites without kicks), latches, LCD set-up, keys (`key_down` while held), entry, steps, squelch, volume, synthesizer words, 4094 boot state, power off/on |

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
