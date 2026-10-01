# Talkman 520 / 620 (Nokia TMF-1 / TMN-1)

NMT-450 (TMF-1, Talkman 520) and NMT-900 (TMN-1, Talkman 620) portables,
converted to 70 cm and 23 cm. Ham firmware by OH5NXO (2000) and OH3NWQ
(to v5.0, 2006). Only TM*-1 units have the program in EPROM; TM*-3 and
TM*-4 have a mask-programmed CPU (a -1 logic board fits a -3; -4 needs
rework). Facts are from the source `tmx1.asm` unless marked; nothing
checked on hardware.

## Sources (gitignored)

| Path | What |
|---|---|
| `reference/tmx1/tmf1/` | Mirror of https://oh3tr.fi/~ftp/modifications/nokia/tmf1/ (2026-10-01). `.../tmn1/` was byte-identical and is not kept. Radio v3.9 (2000) `tmx1v39.zip` (source, `as7810` binary + `as7810.tar.Z` source, handset sources), `archive/` back to v0.7 with sources, HSN2 v1.4 / HSF2 v0.2 handset firmware, `license.txt`, `usage.txt`, MB1501 and MB87006A datasheets, mod photos and notes (`modification/`), board photos (`kuvat/`) |
| `reference/md5x/oh3nwq-moppe/` | github.com/oh3nwq/moppe: `tmx1.asm` and `tmx1_v50.zip` **v5.0 (2006)**, the newest |
| `reference/tmx1/f5soh/` | F5SOH (France, Radiocom 2000 version): logic replaced by a PIC16F84 driving the MB1501s; PA and PLL/TX board pinouts |
| `reference/datasheets/` | NEC uPD7810/7811/78C10/C11/C14 data sheets (1989 databook extract, 81 pp.), uPD78C10/C11/C14 preliminary (26 pp.), **uPD78C10A/11A/12A (1995, 66 pp.: instruction table with state counts, 1 state = 3 clocks)**, uPD7225 LCD controller application note (no uPD7228 sheet found). No separate 7810 user's manual found. Check the 7810 (NMOS) state counts against the 78C10A table |
| `reference/huolto-ohjeet/TMF1XS_Huolto-ohje.pdf` | TMF-1 service manual, 214 pages, scanned; OCR in `*.ocr.txt` next to it |
| `reference/tmx1/tmf1.shtml` | Moppeakatemia page. Links: OH4MS/OH8LRB TMN-1 page (mju.dy.fi, 404 in 2026-10), OK2UCX's PC-controlled packet firmware v0.93 (qsl.net/ok0ns, 404) |

Licence: OH3NWQ's "Binary And Source Code License Agreement"
(`license.txt`, also at the end of the source): internal use, licensed
amateur use only, redistribution only to a recipient who accepts the
agreement and pays at most 0.01 €. Not an open licence: binaries and
source may not be committed to a public repo without OH3NWQ's
permission.

## Hardware (from `tmx1.asm` v5.0)

- **CPU uPD7810** (NMOS, ROM-less; the uPD78C10 is the CMOS version). Interrupt vectors at 0x0000 reset, 0x0004 NMI (restart), 0x0008 INTT1 (112 Hz tick, INTT0 unused), 0x0010 INT1/INT2, 0x0018 INTE0 (timer/event counter, NETFREE), 0x0020 INTEIN/INTAD (on-chip A/D used), 0x0028 serial (MBUS), 0x0060 SOFTI.
- Clock: **11.0592 MHz** (TMF1XS service manual 8-1; 1 state = 3 clocks, so a 4-state NOP is 1.085 µs, matching the source's "1 nop about 1usec"). The manual names the CPU **uPD78C10** (CMOS); the source says uPD7810. Use the 78C10A state table.
- From the manual (processor module NPSA, 8-1..8-3): 64 KB EPROM, 8 KB SRAM with write protection, address latch, addressable output latch, watchdog and power logic; MODE0/MODE1 pulled up (external memory, 64 KB); ID EEPROM 128x8 on I²C (data PC2, clock PA0, powered via EEON); MBUS from the on-chip serial port through one bidirectional transistor stage, RX data also on PC5 (counter input) for net-free detection; on-chip A/D reads temperature (6 diodes), battery voltage/current/temperature, RSSI, FSKL; TX power by an MC144111 (four 6-bit DACs, two summed 1:64 for 12 bits); timer N450 (the i8253) does AFC timing and frame interrupts, MINT = modem INT or timer output to INT2.
- **Memory map:** 0xC000/0xC001 MAS7825 NMT modem (data, CSR); 0xC400-0xC403 i8253; 0xC800 SISE (unwired chip select to the audio card); 0xD400 74259 AMU/LE deviation latch; external RAM 8 KB at 0xE000 (2 KB used for config and memories).
- **i8253:** CLK0 "455 kHz", CLK1 921600 Hz; CLK2 originally 7200 Hz, 921600 Hz after a documented mod (from a 4040 divider); OUT2 used for tones/CTCSS.
- **PLLs:** MB1501 or MB87006 (dual-modulus 128/129 prescaler), serial-loaded.
- **Audio:** MAS7845 LFU; MC144111 6-bit DAC.
- **Handsets** HSN-2 / HSF-2 on **MBUS** (serial, packets such as `0 "ANY1" "HSN2" "M" "." \4` per key). The handsets are uPD7810 machines too (uPD7228 LCD controller, PCD3312 DTMF). HSN-2 runs from an ordinary EPROM; HSF-2 has an SMD PROM. Their ham firmware is `hsn2.asm` / `hsf2.asm`.

## Emulator implications

- uPD7810 core with its on-chip timers (INTT0/1), timer/event counter, serial port and A/D: much more on-chip peripheral work than the 1802 or Z80.
- A full TMx-1 run means two 7810s (radio + handset) linked by MBUS, or the handset modelled at MBUS packet level.
- `pit.c` (8254) covers the i8253 modes used here.
- The licence limits test fixtures: keep the binaries local (like `reference/`), or ask OH3NWQ.
