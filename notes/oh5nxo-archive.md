# OH5NXO's archive (reference/oh5nxo/)

`oh5nxo.mods.2018.tar.gz` (323 MB, 12 366 files) and `tevkit6.tgz` (1998)
from https://oh3tr.fi/~ftp/modifications/sorsat/, fetched 2026-10-01.
Unpacked into `reference/oh5nxo/mods/` (gitignored). The tar has
directories without write permission: extract with
`--delay-directory-restore`, then `chmod -R u+rwX mods`.

README (Finnish, Juha Nurmela OH5NXO): everything he collected over the
years, unsorted, built on FreeBSD; it may contain material once marked
"not for redistribution", which he believes has expired. No licence.

## Relevant to this project

| Path | What |
|---|---|
| `R58bis/` | **OH5NXO's own R58 firmware in C (SDCC 2.7-2.9, 2007-2014)** for P8x (P8E/P8N), L8M and L8TM boards: `R58/*.c` (~4000 lines: `r58bis.c`, `setup.c`, `nmea.c`, `cu58af.c`, `dcspat.c`), asm parts (`boot.s`, `afsk*.s`, `dtmf.s`, `morse.s`, `i2c.s`), `iomap_*.h` per board. `README2`: board part lists, banking (see notes/hardware.md), handset connector pinout with Z80 port bits, task timings measured on P8E and L8TM. Also Computec RB660 / AD1200F (DT1200F) notes |
| `R58/` | His asm R58 firmware history (versions 3F..3Z, `old/` back to r58p8x11), changes files, CTCSS/DDS includes |
| `R58vy/` | `rom.0` (32 KB) and a full disassembly: an RB58VY (L8M board) ROM, original Nokia firmware; see notes/emulation-candidates.md |
| `R58-manuals/`, `R58_sioa/` | R58 manuals (same as reference/), RB660 synth pictures, SIO A GPS wiring |
| `MAS.registers` | MAS modem register bits, "seems valid for MAS7205 and MAS7825" |
| `Mx5x/`, `MD50bis/` | MD5x/ME59 source history from 1997 (`old/`), OH1E-era `md50.asm` work tree with C helper tools (see notes/md5x.md) |
| `MD94/` | Talkman 510 (MD94) firmware + **original handset dump** (`orig.handset.raw`, `orig.hs.dump`) |
| `tmx1/`, `TMX1R/`, `tmn1/`, `7810/` | TMF-1/TMN-1 work (`tmx1v18.asm`, TMN-1 schematic `tmn-1.pdf` 3 pages, repeater and tracker variants `tmx1r.asm`, `tmx1trk.asm`), HSN-2/MBUS sources, `as7810` (see notes/tmx1.md) |
| `1802/`, `1806/` | as02/dis02, as1806 and **cc1806**, a small C compiler for the 1806; MC25 and Senator 1802 firmware |
| `CD60/`, `H40/`, `H45/`, `hc16/`, `R40/`, `MC25/`, `DT50/`, `ARP150/`, `MDR150/`, `BSR450/` | Other radios (Cityman, hand portables, base stations), several with firmware and dumps; other CPUs (6303, 8048, 8051, HC11, 6501) |
