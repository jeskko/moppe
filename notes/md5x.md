# Talkman MD50 / MD59 / ME59

Mobira/Nokia NMT-450 (MD50, MD59) and NMT-900 (ME59) car/portable phones,
converted to 70 cm (MD5x) and 23/33 cm (ME59) ham use. Facts below are
from the firmware sources unless marked otherwise; nothing is checked on
hardware.

**Emulated since 2026-10-02** (moppe-emu `cdp1802.c`, `md5x.c`; design,
model table and limits in `emu/notes/md5x.md`): both firmware lineages
boot and run on all three models. Narrative: [md5x-history.md](md5x-history.md).

## Sources (all under `reference/md5x/`, gitignored)

| Path | What |
|---|---|
| `md50/`, `md59/`, `me59/` | Mirror of https://oh3tr.fi/~ftp/modifications/mobira/{md50,md59,me59}/ (2026-10-01): OH3NWQ ham firmware v3.03 (2004) zips, every older release in `archive/` back to OH5NXO's 1997 v0.x, mod notes, pinouts, MD59 user manual, PE1DTN notes |
| `Sorsat/` | Mirror of .../mobira/Sorsat/: OH5NXO 1997 devkits (`md5x_h40_tevkit3.tar.gz`: CDP1802/1806 and HD6303 assemblers, MD5x `tst.asm`; `mc_rd_tevkit2.tar.gz`: MC25/RD58 sources, 1802/Z80 assemblers), `md5x09.asm` |
| `huolto-ohjeet/ME59NR_Huolto-ohje.pdf` | ME59NR service manual, 181 pages, scanned (text layer is only the TTRK/Nokia permission watermark). `*.ocr.txt` next to it is a tesseract (fin) OCR |
| `titanix/` | Mirror of https://titanix.net/DMR/md50/ (OH1E): `MD50p1/p2`, `MD50_H1/H2` = OH3NWQ **v3.182 (2014-12)** split images (newest OH3NWQ build seen); `md50bis/` = OH1E's own rewrite **#42 (2013, txt to 2017)**: `md50.asm` source, md50/md59/me59 binaries, Finnish user guide `md50.txt`, synth-board scan PDF, mod photos (`kuvei/`: CTCSS DAC, RSSI ADC) |
| `oh3nwq-moppe/` | Clone of https://github.com/oh3nwq/moppe (Vesa Tervo OH3NWQ, 2016-2021): `mx5x.asm` **v3.183** (2016, newest), v3.18 zips (source + `as06` binary + `1806.tar.gz` assembler source, Norway variants), and `tmx1.asm` v5.0 + `tmx1_v50.zip` for **Talkman 520/620 (TMF-1/TMN-1)**, see below |
| `talkman.shtml` | Moppeakatemia Talkman page |
| `../oh5nxo/mods/MD50bis/sch/` | Nokia service texts: `Prosessorimod_PE2_ja_PE2A.pdf` (18 pp., MD50 processor module text + schematics), `Prosessorimod_PE1A.pdf` (schematic, layout), `AudioProcessor_AP1.pdf` (8 pp.), ME59 NR schematics; `*.ocr.txt` (2026-10-02). `md59schemas/` GIFs of the MD59 boards |
| `reference/datasheets/` | CDP1802A/AC/BC (Intersil, 27 pp., instruction cycles and timing waveforms), CDP1805AC/1806AC (Harris 1991 databook extract, 15 pp., extended instructions and counter/timer), RCA MPM-201A CDP1802 user manual (1976, 117 pp.), MC145152-2 (4-page excerpt). Not found: MAS7205/7825, MC145156/MC145146, 93C06 |

No original Nokia NMT firmware dumps were found, only ham firmware.

Firmware lineages: OH5NXO (1997-2000) → OH3NWQ `mx5x.asm` (1999-2014,
one source, `-DMD50/-DMD59/-DME59`, handset `-DCU53/-DCU59`, region and
crystal options; built with `as06`, shell scripts `mak`, `makme59`), and
OH1E's separate rewrite `md50.asm` (2012-2013: CTCSS via DDS tone
generator in RAM, 20 memories, ME59 23/33 cm, RSSI ADC mods). Licences:
`mx5x.asm` is **CC BY-NC-SA 3.0** since 2011 (stated in the source; v3.03
and older carry the earlier "HamWare" text); `tmx1.asm` has OH3NWQ's own
"Binary And Source Code License Agreement" at the end of the source
(licensed hams, free of charge); OH1E's `md50.asm` states none.

## Hardware (from the sources)

| | MD50 | MD59 | ME59 |
|---|---|---|---|
| CPU | CDP1802 (OH1E: `#undef CDP1806`); boards PE1, PE2 | CDP1806 | CDP1806 |
| Clock | 3.6864 MHz | 3.6864 MHz | 4.800 MHz |
| ROM | 2 x 27128 (OH1E: "2 roms actually, total 32kB"; how they are split, by address or odd/even as in the v3.01 `.EVN`/`.ODD` files, is open) | 27256 | 27256 |
| Battery RAM | 1 KB at 0x8000 | 2 or 8 KB at 0x8000 | 2 or 8 KB |
| Extra | 74287 "number PROM" at 0xC000 (removable, free socket) | 93C06 serial EEPROM (`EECS`, data on /EF2) | i8253 at N=1, ADC 0xE000-0xE007 (pot, RSSI, batt, AFC, FSK level), AFC DAC 0xA000, 93C06 EEPROM, offset VCO PLL |
| Synth | serial load from OUT data bits while SWE is set; prescaler 80 (MD5x), 128/129 (ME59); ME59 also has an offset-oscillator PLL (MC145156, 32/33) | | |

Common to all three:
- **I/O:** `OUT 4` writes eight 4-bit output latches; the latch number comes from the address bits 3..1 of the RAM byte X points at (`output_0..7` at 0x8000, every other byte). Latch map is in both sources (TXB, EAR, PHI/NPHI, mic, TXA, CS1-3 handset select, HF, AT1/2 attenuator, DP/CLK/EXA handset, WDR watchdog (level, toggled), KV, ALO, CRM, SWE, PSC, XM TX on).
- **Inputs:** a 4021 shift register read bit-serially through /EF3 with Q as clock (`seq; req; b3`): /PW, TOFF, /HK, low battery, PTT, /LOCAL, POR, POT; order differs per model. /EF4 = /PTT, /EF1 = DCU (handset data), /EF2 per model.
- **MAS7205 NMT modem hybrid** (per the sources; MAS 7825 per the ME59 manual) at N=2 (`INP 2`/`OUT 2`, register select by address bit 5: `mdm_data` 0x801F, `mdm_ctrl`/`mdm_stat`): 100 Hz timer interrupt (CINTE/CCF), FFSK TX/RX, GPIN1 = clipped RX audio zero crossings, GPIN2 = squelch (MD5x) or 8253 OUT2 (ME59). The only interrupt source, plus the 1806 counter on MD59/ME59 (OH1E's tone generator: `ldc/stm/cie`, TPA/32).
- **Handset:** CU53 (same family as the R58 CU53AN: chip select KEYPAD=0, LATCH=2, LCD1=4, LCD2=6; DP/CLK/DA/DCU, PCF2111 LCDs; MD has a third CS line) or CU59 (different LCD segment map). `emu/cu53an.c` is a likely starting point.
- Tones (1750 Hz, CW, CCIR) by toggling PHI/MIC latch bits in software timing loops; OH1E's CTCSS uses a DAC fitted in the number-PROM socket (MD50) or the ME59 AFC DAC.

## ME59 processor module PSA (service manual)

From `ME59NR_Huolto-ohje.pdf` pp. 72-95 (OCR; PSA section 8-1, ASA 7-1).
Confirms the sources and adds the decode:

- **CPU CDP1806ACE, 4.800 MHz** (crystal X2). TPA/TPB = clock/8; they clock the ADC, I/O ports, address latch and the timer.
- **Address decode:** the high address byte goes into an 8-bit latch (IC6). Its low 6 bits are A8-A13 for EPROM/RAM; the top 3 bits drive two 1-of-4 decoders (IC7) that select the block.
- **Memory map:** 0000-7FFF EPROM (32 KB CMOS, IC8); 8000-87FF RAM (2 KB CMOS, 8 KB option, IC10, battery-backed with write protection while CLR* is low); A000 D/A (8-bit latch IC4 + R/2R, AFC 1-3 V); E000-E008 A/D (IC5, 8-bit: RSSI, VC battery, AFC, POT, FFSK level DL; write starts a conversion, read gets it). The ID EEPROM (IC9, "256 bytes"; the sources say 93C06, which is 256 *bits*) and the timer/counter (IC17) are in I/O space.
- **Timer/counter IC17** (the sources' i8253 at N=1): chip select from inverted N0; register by A0/A1. OUT gives the 30 ms interrupt (Nokia firmware) and counts the 455 kHz IF in 50 ms windows gated by GATE1. Its clock and the watchdog's are 19.2 kHz from the modem.
- **FFSK modem: MAS 7825** (IC16), 1200 baud, own 3.6864 MHz crystal X1. (The sources call it MAS7205 for all three radios; the ME59 manual says 7825. Check the MD5x manuals.) C/D* selects control/status vs data. Interrupt (INT* = 0) after each received byte; frame sync pattern 11100010010. Status bit 7 TIMINT = the 30 ms timer caused the interrupt, bit 6 FFSKC = comparator output of the band-passed FFSK RX.
- **Outputs:** 32 lines from four addressable 8-bit latches (IC3 on PSA, IC11-13 on ASA). Each latch takes one data line D0-D3; address A1-A3 selects the output; clocked by TPB and N2 together. So one `OUT 4` writes the same output number in all four latches (the sources' "4-bit output_n"). PSA's latch: TSE, RSE (TX/RX PLL enables), SCLK, SD, SWE, TXA, TXB (0.1/1/6 W), WDR.
- **Synth load:** while SWE is high, MWR* pulses clock SCLK and SD carries the data; TSE/RSE select the TX or RX PLL.
- **Inputs:** 9 signals through shift register IC14 on ASA; PSC=1 parallel load, PSC=0 shift; data on DIR into /EF3, clock CLKI driven by the CPU. /EF1 = DCU (handset serial data), /EF2 = EEPROM data.
- **Watchdog** IC2 (binary counter, 19.2 kHz): CLEAR* pulse if no WDR for 213 ms, power off (OFF3) at 427 ms; the firmware toggles WDR every 50 ms. Link LK1 disables it.
- **Reset:** RESET when +VB < 7.5 V or +5 V fails; CLR* resets CPU, modem, watchdog and output latches, delayed until a RAM access in progress ends.
- **Power:** latching relay; OFF1 (CPU, rising edge), OFF2 (ASA, ~3 s after PW* off if the CPU did nothing), OFF3 (watchdog).

## MD50 processor module PE2/PE2A and AP1 (service text)

From the OCR of `Prosessorimod_PE2_ja_PE2A.pdf` (prose pp. 1-8,
schematics pp. 15-18) and `AudioProcessor_AP1.pdf`; the schematic pages
were read from the images, so pin-level details are a best reading.

- **Clock** 3.6864 MHz; TPA/TPB = clock/8.
- **Decode:** a 74C374 latches A8-A15 at TPA; A14/A15 select EPROM IC10 (0000-3FFF), EPROM IC11 (4000-7FFF), RAM (8000-83FF, 2 x 1Kx4, IC12 = D0-D3, IC13 = D4-D7), ID PROM (C000-C0FF, 74S287 256x4 on AP1). The parts list says the EPROMs are 8 KB 27C64s in 16 KB windows (would mirror; the ham firmware images are 2 x 16 KB, so 27128s in practice).
- **PROM:** A0-A3 from the bus, A4-A7 from output latches beforehand; powered by PPC* = 0. OH1E puts a CTCSS DAC in this socket.
- **N lines** one each: N0 = WAIT trigger (cleared by the next /INT or reset; "only used on the call channel"), N1 = modem CS, N2 & TPB = output latch enable.
- **Outputs:** four 4099 addressable latches, one data bit each (IC7 on PE2A: D0; AP1 IC11-13: D1-D3); address A1-A3. IC7 holds SE, TXA, TXB (10/01 = 15 W, 00 = 150 mW), VCS, XM, OFF1, WDR, SWE. **SWE = 1 gates D7 and MWR onto SD and SCLK** (synth data and clock).
- **Flags:** /EF1 DCU, /EF2 1 = normal / 0 = production test (LK1), /EF3 = 4021 Q8, /EF4 production test only (the ham mods use it as /PTT); /INT from the modem.
- **4021** (AP1 IC15): PSC 1 = parallel load, 0 = shift; clock = CPU Q; nine inputs: DA, PW*, RF OFF, HK*, VC, PC, LOCAL*, POR, POT (serial in). Polarities: PW 1 = power cut, RF OFF 0 = output above 100 mW, HK 1 = lifted, VC 0 = above threshold, PC 0 = 15 W / 1 = 1.5 W, LOCAL* 1 = normal, POR 1 = portable, DA 1 = key, POT 1 = off over 2 s. The firmware reads them in the order DA, PW, RF OFF, HK, VC, PC, LOCAL, POR, POT, which the emulator uses (the pin-number reading of the drawing suggested another order).
- **Modem MAS 7205** (H5): 1200 baud FFSK, C/D* = A5, /INT 100 Hz while idle, every 8 bits during a frame; SQ (level detector, 1 = above the limit) and FFSKC in the status register.
- **Watchdog** 4020 at 19.2 kHz from the modem: restart 106 ms after the last WDR, OFF3 at 213 ms (the stage names Q12/Q13 suggest twice those); LK2 disables it. Normal Nokia firmware pulses WDR every 10 ms.
- **Power:** OFF1 rising edge cuts the supply; RAM has lithium backup.
- **PE1A vs PE2 vs PE2A:** PE1A has one 28-pin RAM with an 8k/2k jumper (LK4); PE2 and PE2A have 2 x 1Kx4. PE2 and PE2A differ only in the reset / RAM-protect circuit (PE2: 6.2 V zener, 4013; PE2A: 7.5 V zener, BCW32s, 4093).

## Related: Talkman 520/620 (TMF-1 / TMN-1)

uPD7810-based, MBUS handsets; see [tmx1.md](tmx1.md).

## Emulator

- CPU core `cdp1802.c`: CDP1802 and the 1804/5/6 extensions. OH3NWQ code uses only 1802 instructions (and no interrupts: its `int` handler just disables them); OH1E runs on the modem's 100 Hz interrupt and uses STPC/LDC/STM/CIE/CID on 1806 models.
- Tests: `make -C emu test-md5x` (`emu/tests/md5x/test_md5x.py`, 13 scenarios, six firmware builds). The sources are fetched from their authors' sites by `make -C emu refs` or read from this repo's `reference/md5x/`; nothing third-party is committed.
- Board `md5x.c`: see `emu/notes/md5x.md` for the model table, evidence and limits (modem at byte level, no 93C06, 8253 gates high).
- **Firmware builds** (`emu/tests/md5x/roms.py`): the shipped i386 `as06` (from the v3.18 zips) runs here and rebuilds the v3.18 release binaries byte-identically; it also builds OH1E's `md50.asm` identical to his published binaries except the `__DATE__` string. The `1806.tar.gz` assembler source builds with `gcc -m32` after one fix (`(intext ? textdot : datadot) = ...` is not valid C any more); a 64-bit build crashes (pointers kept in `unsigned` YYSTYPE and casts).
- Using the firmware: mx5x frequency entry is 5 digits with the 100 MHz (1 GHz on ME59) digit implied ("33500" = 433.500). OH1E: digits then `#`; on a CU59 the first key after a cold start goes to handset-type detection; zeroed RAM has `tx_start = tx_end = 0`, which refuses all TX until set up.

## Open questions

- MD59 manual (only MD50 PE2A/AP1 and ME59 are in hand): its RAM decode (2/8 KB mirroring assumed), modem part, watchdog time.
- MAS7205/7825 datasheet: none found yet; register bits come from source comments and OH5NXO's `MAS.registers` (reference/oh5nxo/mods/), which says the map is valid for both parts, so one model covers both.
- Watchdog times: PE2A text 106/213 ms vs its Q12/Q13 stage names (213/427 ms, as in the ME59 manual).
- CDP1805/1806 68xx cycle counts: the Harris extract has no instruction table; the core uses the CDP1805 user manual's counts as known, unverified against a document here.
- Licence of OH1E's `md50.asm` before anything derived is published.
