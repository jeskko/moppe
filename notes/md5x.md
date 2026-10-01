# Talkman MD50 / MD59 / ME59 (next emulator target)

Mobira/Nokia NMT-450 (MD50, MD59) and NMT-900 (ME59) car/portable phones,
converted to 70 cm (MD5x) and 23/33 cm (ME59) ham use. Facts below are
from the firmware sources unless marked otherwise; nothing is checked on
hardware or against the service manual yet.

## Sources (all under `reference/md5x/`, gitignored)

| Path | What |
|---|---|
| `md50/`, `md59/`, `me59/` | Mirror of https://oh3tr.fi/~ftp/modifications/mobira/{md50,md59,me59}/ (2026-10-01): OH3NWQ ham firmware v3.03 (2004) zips, every older release in `archive/` back to OH5NXO's 1997 v0.x, mod notes, pinouts, MD59 user manual, PE1DTN notes |
| `Sorsat/` | Mirror of .../mobira/Sorsat/: OH5NXO 1997 devkits (`md5x_h40_tevkit3.tar.gz`: CDP1802/1806 and HD6303 assemblers, MD5x `tst.asm`; `mc_rd_tevkit2.tar.gz`: MC25/RD58 sources, 1802/Z80 assemblers), `md5x09.asm` |
| `huolto-ohjeet/ME59NR_Huolto-ohje.pdf` | ME59NR service manual, 181 pages, scanned (text layer is only the TTRK/Nokia permission watermark). `*.ocr.txt` next to it is a tesseract (fin) OCR |
| `titanix/` | Mirror of https://titanix.net/DMR/md50/ (OH1E): `MD50p1/p2`, `MD50_H1/H2` = OH3NWQ **v3.182 (2014-12)** split images (newest OH3NWQ build seen); `md50bis/` = OH1E's own rewrite **#42 (2013, txt to 2017)**: `md50.asm` source, md50/md59/me59 binaries, Finnish user guide `md50.txt`, synth-board scan PDF, mod photos (`kuvei/`: CTCSS DAC, RSSI ADC) |
| `oh3nwq-moppe/` | Clone of https://github.com/oh3nwq/moppe (Vesa Tervo OH3NWQ, 2016-2021): `mx5x.asm` **v3.183** (2016, newest), v3.18 zips (source + `as06` binary + `1806.tar.gz` assembler source, Norway variants), and `tmx1.asm` v5.0 + `tmx1_v50.zip` for **Talkman 520/620 (TMF-1/TMN-1)**, see below |
| `talkman.shtml` | Moppeakatemia Talkman page |

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
- **MAS7205 NMT modem hybrid** at N=2 (`INP 2`/`OUT 2`, register select by address bit 5: `mdm_data` 0x801F, `mdm_ctrl`/`mdm_stat`): 100 Hz timer interrupt (CINTE/CCF), FFSK TX/RX, GPIN1 = clipped RX audio zero crossings, GPIN2 = squelch (MD5x) or 8253 OUT2 (ME59). The only interrupt source, plus the 1806 counter on MD59/ME59 (OH1E's tone generator: `ldc/stm/cie`, TPA/32).
- **Handset:** CU53 (same family as the R58 CU53AN: chip select KEYPAD=0, LATCH=2, LCD1=4, LCD2=6; DP/CLK/DA/DCU, PCF2111 LCDs; MD has a third CS line) or CU59 (different LCD segment map). `emu/cu53an.c` is a likely starting point.
- Tones (1750 Hz, CW, CCIR) by toggling PHI/MIC latch bits in software timing loops; OH1E's CTCSS uses a DAC fitted in the number-PROM socket (MD50) or the ME59 AFC DAC.

## Related: Talkman 520/620 (TMF-1 / TMN-1)

uPD7810-based, MBUS handsets; see [tmx1.md](tmx1.md).

## Emulator implications

- New CPU core: CDP1802 plus the 1804/1805/1806 extensions (counter/timer, `RLDI`, `SCAL`, `DBNZ`…). OH3NWQ code uses only 1802 instructions; OH1E uses the counter on 1806 models.
- Chips: MAS7205 (no datasheet in hand; register bits are from the sources' comments, partly guessed by OH5NXO), 4021 input chain, output latches, 93C06, i8253 (reuse `pit.c`), ADC/DAC, CU53/CU59.
- Test fixtures: `mx5x.asm` builds with `as06` (in the zips, as a Linux binary, and its source in the `Sorsat` devkit); OH1E's binaries come with source. Both are fine as boot targets.

## Open questions

- Service manual: memory map decode, exact MAS7205 part docs, clocking of the 4021 chain, synth part per model (check the OCR).
- MD50 PE1 vs PE2 processor boards: differences ("PE2 blocks RAM until first write", MD50 PE1 /EF4 caveat in OH1E).
- Licence of OH1E's `md50.asm` before anything derived is published.
