# Nokia R40: history

## 2026-10-05: feasibility research

Material surveyed with subagents (OCR of the scanned manuals, ROM
cross-reference with a rebuilt binutils h8500 disassembler, a web search
for the H8/500 and chip documentation, the cq3meter.nl bundle). The
verdict before any emulator code existed:

Enough material for an emulator that boots the RC40 Cr 13.04 ROM into
normal and service ("LOCAL") mode with an emulated CU43 / CU43PROG
control head. The memory map and device addresses agree in three
independent sources (manual, OH5NXO's PINS, firmware cross-reference).
The work is mostly new code: an **H8/500 CPU core** (nothing in moppe-emu
fits; MAME's BSD-3 core is a reference) and the H8/532 on-chip
peripherals. Gaps, in order of weight:

1. **Only one clean ROM.** `Cr1506.bin` (Cr 15.06-1, 23.08.1996, the
   MPT build) is damaged: 34 byte values never occur in it (0f 14 15
   b0-b4 b9-bc bf c0-c5 c8-ce d5 d9-dc df f2 fe; ABSBIN uses all 256,
   checked), apparently a many-to-one byte substitution. Its strings
   are intact, its code is not. The ZIP copy is identical. Usable ROM:
   RC40 **Cr 13.04-0** (06.08.1993, AC-2), `rc40_rom/ABSBIN`.
2. **NVRAM layout unknown.** No source gives byte addresses (the AMAN
   R40 parameter files have no address column). The firmware cold
   starts by itself when the RAM signature at 0x8bc95 is not 0x55/0x5a
   (F), so an empty NVRAM works; the layout can be learned by running
   service tests in the emulator and watching NVRAM writes.
3. **Trunking.** Normal mode wants an AC-2/MPT1327 control channel over
   the FX429 FFSK modem. Without one it will hunt; service mode and the
   simplex channels need no network. A control-channel simulator is
   optional later work.
4. **Datasheets:** all chips covered since 2026-10-05 (PCF8578,
   PCF8579, FX429 added by the user). PCF8574 is trivial and has none.
5. **Unknown pins:** the external watchdog IC57 kick line (MR, 4 s) and
   the synthesizer lock input "TX OFF" (SP pin 8) are not mapped to MCU
   pins in the text; find them by running the firmware.
6. **Licence:** the Nokia ROM is proprietary and stays out of both
   repos. Decided 2026-10-05: tests fetch it from the public archive,
   like the other test firmware (see "Test ROM").


## 2026-10-05: emulator built

Same day, on the user's go-ahead: H8/500 core, H8/532 modules and the
L100 + CU43 board in moppe-emu (commit 50ead02). Steps that mattered:

- The core's instruction lengths were checked against the patched
  disassembler over the whole ROM before running anything; the only
  disagreement left was binutils' RTD (0x14 is #xx:8, 0x1C #xx:16, by
  the Programming Manual).
- First runs: a PRTS decode bug (11 19 grouped under 0x18), then a crash
  at 2.26 s traced to the stack moving between the two NV RAM halves:
  P9.2 floats at reset, the firmware's first PJSR pushes its return
  address before P9DDR makes the pin an output 0. Modelled as pulled low.
- The firmware probed I2C 0x4A and wrote an 8-character segment display
  at 0x74, and the RAM held "6_rrE" / "ERR_6": it was showing Error 6
  ("own subscriber number lost", the manual's code for empty NV) on
  another head type. IC200 P6 = 0 made it a CU43: LCD init as in
  OH5NXO's cu42.s, then "Self test / Service necessary / Error 6".
- The top LCD row decoded as "Se lf tes t": the firmware writes 24
  five-column cells and the glass shows 20 characters (cells 2, 9, 16,
  23 are gaps).
- With the 24C02 service key and PWR held: every lost-NV error in turn
  (9, 11, 5, 2, 3, 1, 6, 10, 4), then the LOCAL display
  "0 000 00000  00000 0 / rsl / 075". Keypad positions found by pressing
  each in LOCAL mode.

### Plan at the end of the research

1. H8/500 core in C (moppe-emu style), tested against the programming
   manual; then H8/532 peripherals (ports, FRT x3, 8-bit timer, SCI,
   A/D, WDT, interrupt controller, WCR).
2. Board: memory map, latches, PCF8584 + CU43 I2C devices + 24C02,
   serial-bus devices (DS1202, MC144111, 4094), PLL decode to Hz,
   FX429 stub.
3. Boot Cr 13.04 to "Self test" and the service display; a test
   scripting the PE1BVU procedure.
4. Look for a clean Cr 15.x dump.
