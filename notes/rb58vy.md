# RB58VY (L8M logic board)

Status (2026-10-08): **the emulator runs the L8M board** (`card=L8M`,
emu commit 8885af5; details and limits in `emu/notes/r58.md`, tests in
`emu/tests/l8m`). OH5NXO's R58bis built for L8M works in it: keypad,
display, setup menu, 6 m RX/TX synthesizer frames and TX keying. Our own
firmware does not build for L8M yet (`r58.s`: `#error Sorry, L8M missing
in action`); the port plan is below.

## The radio

Mobira RB58VY: a low-VHF mobile for the VY-85 trunked system, 25 W /
2.5 W, CU 53 VY handset (same serial protocol as the CU53AN). Logic board
L8M (Z80 84C00 at 4.032 MHz, PIO, SIO, 82C54, ADC0809, DAC0832, FX409/419
FFSK modem, NMC9817 2 KB EEPROM, 2 x HM6264 RAM), synthesizer S8M
(MC145156, 40/41 prescaler, R = 1024), 45 MHz first IF. Service manual:
`reference/huolto-ohjeet/RB58VY_Huolto-ohje.ocr.txt` (chapter 11 = L8M,
chapter 17 = CU 53 VY). The hardware differences from P8x are tabulated
in `emu/notes/r58.md` "L8M".

## Firmware material

| What | Where | State |
|---|---|---|
| Original Nokia firmware, EPROM0 | `reference/oh5nxo/mods/R58vy/rom.0` + OH5NXO's labelled `rom.0.asm` | **incomplete**: EPROM1 (0x8000..0xBFFF) was not dumped; 5 of the 16 scheduler tasks (table at 0x7B00) start there. Runs its EEPROM default copy, then crashes into the missing EPROM |
| OH5NXO R58bis (C) for L8M | `reference/oh5nxo/mods/R58bis/R58/L8M.bin`, source in the same directory (`-DL8M`) | runs in the emulator; 6 m defaults; config and 40 memories in the EEPROM; FFSK via the FX419 on SIO A (sync mode) |
| OH5NXO asm R58 v4.0 L8M port (2000-12) | `reference/oh5nxo/mods/R58/r58.asm.pre4.0`, `r58.asm.vy.rx.sorta.better`, `r58l8m40b.inf` | alpha: RX and TX worked, S8M synth, NV lost when the supply is cut, no FSK. Dropped again in 3G..3Z, which our firmware descends from |

## Porting our firmware (assessment)

The hardware layer of `r58.s` is compact: the port block (`r58.s:557-600`),
the chip init tables (`init_chips`), OUT1/OUT2 bit use (~94 places),
`set_bank` (16), the 8254 counters (19), ADC channels (14). The C modules
hardly touch ports. Work items, in order:

1. **Port map and latches**: `#ifdef L8M` port block (I/O 0x00..0x70,
   ADC order), one shadow for the 0x50 latch with the O1_/O2_ bits
   redefined to its layout (OH5NXO's way: `OUT_1 == OUT_2`), 0x60 as OUT0.
2. **Timers**: LPF counter 0 -> 1, tone (MT) counter 1 -> 2; counter 0 is
   free (MBUS clock on the board).
3. **Hook**: SIO A DCD (ext/status interrupt) instead of PIO A1.
4. **Synth**: an S8M type (MC145156 frames, 40/41 prescaler, fixed R:
   12.5 kHz raster unless the RA pins are rewired; OH5NXO's S8M_10 mod
   gives 10 kHz). PA1 is the TX VCO buffer enable / lock input.
5. **ROM banks**: EPROM0 holds 32 KB (27C256 socket); our two 16 KB banks
   go into EPROM1's halves, selected by PB4 (S/L) in `set_bank`. The build
   makes two images.
6. **NV storage**: see the decision below.
7. Watchdog port 0x70. No P8E/P8N detection, no CSMEM.

Lost or to be redone on L8M:
- **FFSK** (FX429 code: packets, remote config, MPRS): the FX419 is a
  bit-sync modem on SIO A. It needs SIO sync/hunt support in our firmware
  and in the emulator's SIO; first cut without it.
- **GPS input**: SIO A belongs to the modem. SIO B (MBUS) could take NMEA:
  its clock is 8254 counter 0, 4800 baud x16 = count 52 (0.8 % fast).
- **DTMF and CTCSS decoders**: no multiboard window, and PB5 (the P8x
  CTCSS input) is SMEM on L8M.
- AFSK APRS out (tone pin), CCIR, scanner, repeater, setup menu: unchanged
  apart from the hardware layer.

**Decision needed: where NV lives.** Ours keeps ~4 KB in battery RAM
(130 memories x 12 B + config). On L8M the RAM is powered from Vm, so it
survives power-off but not a supply cut (OH5NXO 4.0's complaint). The
EEPROM holds 2 KB (two 1 KB copies in Nokia's use), or 8 KB with an
8 KB chip and the TP4 jumper. Options: (a) RAM only, as 4.0; (b) RAM,
plus config and a reduced memory set copied to the EEPROM on change
(byte writes ~10 ms each, so not in the power-off NMI); (c) everything in
an 8 KB EEPROM.
