# Emulation candidates in the reference mirrors

Status: #1 done, emulated since 2026-10-08 ([rb58vy.md](rb58vy.md)).

Survey of `reference/` (mainly `reference/oh5nxo/mods/`) on 2026-10-08:
which radios not yet emulated have enough material. Paths are under
`reference/oh5nxo/mods/` unless noted. "Checked" = verified in the files
this session; the rest is from file headers and comments.

## Ranking

| # | Target | CPU (core) | Firmware | Docs | Readiness |
|---|---|---|---|---|---|
| 1 | **Nokia RB58VY, L8M board** | Z80 (have), PIO/SIO/8254 (have), FX419, NMC9817 EEPROM | `R58vy/rom.0` 32 KB original (checked: `JP 00EF`, IM2) + labelled disassembly; OH5NXO's C firmware `R58bis/R58/L8M.bin` 48 KB (2014, CU53 handset) | `reference/huolto-ohjeet/RB58VY_Huolto-ohje.ocr.txt` (L8M logic, parts list); `R58bis/R58/iomap_L8M.h`; `R58bis/README2` | **High**: a board variant of the R58 emulator |
| 2 | **Computec RB660, L8TM board** | Z80 (have), same peripheral set | `rb660_0.bin` + `rb660_1.bin`, 64 KB each, original "rb660 7.05" (checked) + disassemblies; OH5NXO's `R58bis/R58/L8TM.bin` 48 KB (CU53) | `iomap_L8TM.h`, `rb660_ioinit`, README2 (banking, DS1210 NV RAM); no manual | **High** for OH5NXO's firmware, medium for the original (bank map inferred) |
| 3 | **Mobira DT50** data terminal (APRS tracker) | HD6303 (new) | `DT50/dt50.asm` ham source #162 + `dt50.bin` (checked: reset 0x834A); original `zzz/dt50.orig.bin` + disassembly | README (6303 pin use, mods), `doc/` glue-chip and LCD datasheets, `keymap`; TCM3105 modem | Medium-high; not a radio |
| 4 | **Nokia H45 / H40** (Kyodo KG109T) handhelds | HD6301Y0 / HD63A03Y (new, same core as DT50) | H45: `h45.asm` source, mask ROM dump, originals in `H45_secrets/`; H40: `h40.asm` v117 + `hd40.bin`, original `H40_old/orig/h40_11.bin` | H45 service manual (scanned, 5 chapters, no text layer); memory maps in asm comments; FX429/FX419, PCF2100 | Medium; three targets share one new core |
| 5 | Mobira CD60 NMT car phone | 1802 (have) | `CD60/orig/nn3.bin`, `nn4.bin` 32 KB original + patches | panel protocol logs; no schematic, no MAS7205 docs | Medium-low |
| 6 | TNC-2 clone (InfoMotion 1.18a) | Z80 (have), SIO (have) | `8080/ohtnc/oh6mf1.18a` 32 KB | none here; TNC-2 hardware is public (TAPR) | Medium-low; a TNC |

Low (no firmware, no docs, or a new core with little hardware info):
- Niros TRX-909 (MCS-48; original ROM and OH5NXO rewrite, hardware from photos).
- MD94 (uPD7810; only the handset ROM is original, main unit is OH5NXO's blind build).
- H17 (Z80; a disassembly, little hardware info).
- Ericsson Hotline 431/433 (6800 family; schematics as GIFs).
- Ascom SE550/Condor (8051; ham MK3 firmware only, scanned handbook).
- FORTE 2000, lajax (unidentified 6303 / 8051 ROMs).
- TSGB base-station module (80C557; banked flash not dumped).
- Nokia HD85 (H8/300; manual, no firmware).
- No CPU at all: ARP150, BSR450, tpradio (channel PROMs).

RD540 (`reference/cq3meter/`) is a PA4KW patch of the RD40: no image, only
patch offsets; it would need the base RD40 ROM in the existing R40
emulator.

## L8M / L8TM vs the emulated P8E/P8N

From `iomap_L8M.h`, `iomap_L8TM.h`, README2 and the RB58VY manual:
- 4.032 MHz, no M1 wait (like P8N).
- L8M ports: ADC 0x40-0x47 (P8x 0x50), OUT_1 = OUT_2 at 0x50,
  OUT_0 at 0x60, watchdog 0x70, DA 0x30 only; no FX429 at 0xA2/A3. The
  FX419 modem runs on SIO A in sync mode.
- L8M memory: RAM, or two 1 KB EEPROM blocks (PB0 selects block, PB5 SMEM
  selects EEPROM). L8TM: 16 KB NV RAM (DS1210) at C000, 32+16 KB ROM in two
  27512s with bank bits at port 0x70.
- The original RB58VY uses a separate control unit on MBUS (SIO B, 8254
  OUT0 155 kHz), not documented here; OH5NXO's firmware uses the CU53, so
  start with his `L8M.bin`/`L8TM.bin`.
- `R58vy/rom.0` is EPROM0 only, and EPROM1 is needed: five of the 16
  scheduler tasks start in it (checked in the emulator, rb58vy.md).
