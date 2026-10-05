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

## 2026-10-05, second session: NV map, keys, PLL

- Service tests diffed against `nv()`: every test writes the same offset
  in three places, 0x0000 and 0x2000 in the half with P9.2 = 1 and the
  working copy (P9.2 = 0, the half that also holds the stack). Byte
  0x12B changed with every write: the first block's checksum. The block
  table (start, length, checksum byte) turned up at ROM 0x36966 by
  searching for 0x012B / 0x01CB; the routine at 0x36A47 writes each byte
  to both copies and stores NOT(sum).
- Test 10 before test 18 stored 0x1980: (430 MHz / 3.125 kHz) mod 2^16,
  the overflow of an unset 0-channel. In PE1BVU's order (18 first) the
  stored words are the physical channels, 4800 for 430.0 MHz.
- The top row showed "05 600" and "435000 00": the gap cells are 2, 9,
  ? and 21, not 16 and 23. "Self test" confirms 2 and 9; 13 or 14 can't
  be told apart from these texts, so 14 was chosen by symmetry.
- PLL: RX read 960 MHz for 435 MHz with A = 0, TX had A = 96, which
  rules out the 64/65 prescaler; OH5NXO's `pll.s` says the chip sees
  the VCO's second harmonic and puts SRE on P7.7. Halving gave RX 480
  MHz (435 + 45 IF). The TX R stayed 0: SYNTH events showed SRE with 16
  bits and then STE with 0, so the firmware strobes the two chips one
  after the other on the same shifted word. The model now keeps the
  shared shift register across strobes. TX then read 435.0625 MHz idle,
  435.000 on PTT (parked, like OH5NXO's `xor #16`).
- Keys: 70 OK 1234 followed by every ordered pair of unknown positions;
  only (2,0) (0,0) entered parameter programming: FNC, STO. In tests 31
  and 36, (2,4) raised and (3,4) lowered the value, and (0,0) stepped
  test 36 to the next frequency (+1.5 MHz, then +1 MHz, as PE1BVU says
  for RCL). The manual's key list has STO and RCL on one key.
- Parameter 030 in Cr 13.04 asks rx, tx and `st`; the entries live in
  6-byte records from 0x48E (parameter 001), and leaving with `*` wrote
  FFFF into the unused records. Parameter 800 (own number) cleared
  Error 6: normal mode shows the number and "Number unobtainable" /
  date, the cold-start company text "British Gas Northern", and the TX
  synthesizer steps 403-473 MHz (hunting?) while the RX never gets an
  N/A. `*55*001#` did not take: '#' is not echoed, OK adds a second
  '_'; (4,4) cleared the entry.

## 2026-10-05, third session: Ghidra project, TUI, Cr 15.06 damage

- Ghidra has no H8/500 support; the OZVR4 community module (H8/539F,
  same CPU core, maximum mode) imported the ROM with an H8/532 pspec.
  First pass: 45 199 instructions, 12 length disagreements with
  binutils, all binutils' fault. Reset's `jmp @0x27bc:16` was not
  followed: the constructor loaded a word from DP:aa. After the fix,
  sampling the emulator's PC showed 9 % of executed addresses still
  undecoded (computed calls; the idle loop at 0x215F8); a coverage map
  in the emulator seeded them, which exposed analyzer data placed over
  code and a missing SUBS <EA>,Rd. End state: nothing executed is
  undecoded.
- Ghidra xrefs to P7DR led to `pll_rx_load` / `pll_tx_load` /
  `pll_reference_load` behind a far-pointer table at 0x1B50, matching
  the emulator's PLL model. Breakpoints in normal mode: `tx_tune` 350
  times from `tx_park`, `rx_tune` never.
- `r40tui.py` written by a subagent (checked: headless script gives
  RX 480 / TX 435 MHz on PTT; curses screen shows the boot text).
- Cr1506.bin: bit statistics normal; aligning 28 000 bytes of code
  shared with Cr 13.04 showed each of the 34 missing values replaced
  by one or a few fixed values (BF→2B every time, 0F→CF, 14→F4, 15→F5),
  matching an OEM→ANSI→OEM best-fit conversion.
- `r40nv.py`: a set-up NV image built through the service mode. An
  image with the band set-up and own number still showed Error 11 in
  the service head's power-on list; 172 + 190002 cleared it (190002
  rewrites the 10-12 words, so they go after it). PE1BVU's squelch
  delay settings (31/32 00, FNC STO) never reached NV in the emulator;
  the manual calls 31/32 factory tests with no effect in system mode.
