# OH5NXO's R58bis (C rewrite) compared with this firmware

> Written by a subagent from reading the code (2026-10-01), nothing built or run. Spot-checked in the main session: `zzz/IC` chip list (exists as quoted; it does not name the board, the parts match the P8E; "4.032 MHz clocks the FX429" is inference), the RA14=1 voice sample (`P8x_52.bin` 0xC000 = `onions_.raw`, byte-identical; `silly.s:26` OUT2 = ROM0|ROMA14), PA1 hook comment (`iomap_P8x.h:91`), README2 wait-state line. The NMI/NV claim and the rest are unverified.

Written 2026-10-01 from a read-only pass over `reference/oh5nxo/mods/R58bis/`
(gitignored). Paths below: `bis/` = `reference/oh5nxo/mods/R58bis/`,
`bis/R58/` = its main source tree. "Seen" = read in code or notes; "inferred"
= my deduction. Nothing here was built or run. All files were readable; the
JPG photos in `bis/kuvat/` were not examined; the three `rfc_dac_ctcss_*.gif`
were.

## Summary (ranked by usefulness)

1. **P8E IC list with pin notes** (`bis/zzz/IC`, same as `bis/old.P8x/IC`)
   answers several open hardware questions: IC3 is a 74HC4040, so the FX429
   CLK (IC3 pin 9) is **4.032 MHz**; IC27 is a **74HC21**; the SIO clock comes
   from a **74HC4059 dividing 4.032 MHz by 26 = 155.08 kHz** (9692 / 4846 baud,
   +0.96 %), not 153.6 kHz; the watchdog 4040 on the P8E is wired like the
   P8N's (Q11 = WD, Q12 = OFF); the EPROM1 socket pinout with the multiboard
   bits; an 82S129 PROM socket at I/O 0xC0/0xD0.
2. **ROM window, RA14 = 1 page: used by OH5NXO, not just schematic reading.**
   `P8x_52.bin` (v52, 2009-08) is a 64 KB image whose chip 0xC000-0xFFFF holds
   a voice sample (`bis/onions_.raw`, byte-identical), and `silly.s` plays it
   through OUT2 = ROM0|ROMA14 at 0x8000, called from the STO key in that
   version. This is the same mapping as our bank 1. Strong evidence, still not
   our bench test.
3. **P8E wait states also on I/O**: README2:56-58 "P8E waitstate from M1 _or_
   adc or dac1/2 or modem chipselect". The emulator adds waits only on M1.
   This fits IC27 = 74HC21 (4-input AND of active-low selects, inferred).
4. **Hook polarity**: R58bis says PA1 = 1 means off hook (`iomap_P8x.h:91`
   "0 onhook"). That contradicts our assumption (hardware.md:68, "1 = on
   cradle"), agrees with the service manual inference and with our firmware's
   hook-script path, and means the "repeater sitter's special" test
   (`c/timers.c:54`) runs while the handset is **off** the cradle. Needs a
   one-minute check on a real radio.
5. **CU58AF keypad row 6 is PCF8574 P6** (`cu58af.c:144,235`, ROW_MASK 0x7F,
   "+SR" on row 6). Corroborates our firmware over the manual
   (hardware.md:71). Also: two PCF8574s answer at 0x40 (DM58 and HS58), and
   COLBTN bit 3 is labelled "POWER".
6. **New feature candidates with working-looking code**: DCS encoder
   (`dcspat.c` + Golay `dcs_frame` in `util.s:1930`, 337-sample wave played by
   the PIO-A interrupt, same slot as the CTCSS DDS; disabled by `#if 0`), CTCSS
   phase reversal at TX end (`boot.s:1710-1730`, a stub), config versioning
   (magic + size; only fields added since the stored size get defaults,
   `setup.c:331-355`), a mainline liveness watchdog (`fido`, `boot.s:621-626`),
   a crash dump to the serial port (`crash.s`).
7. **RFC-DAC CTCSS needs a wire**: `bis/rfc_dac_ctcss_schema.gif` shows the
   mod: from the RFC DAC filter node (R72/C59/R73, P8N) through a series C and
   R to A8N IC6 pin 13 (-OP1, the TX summing node where FFSK, CCIR/MT and R55
   meet). Our notes describe the "rFcdAc" method without its hardware path.
   The gif also confirms our A8N trace (FFSKOUT, R57 56k, C30 "100", R55).
8. **R58bis is an unfinished experiment, abandoned around 2013-14**, not a
   replacement: last version string `130509#61` (2013-05-09), last build
   2014-02-11, ~25 KB of code and data for far fewer features than ours. It
   confirms the rewrite-evaluation conclusion: a C base fits, today's feature
   set would not without banking.
9. **No licence text anywhere** in R58bis or R58 (grep for
   copyright/licence/GPL/public domain/redistribute: no hits). Facts and ideas
   are free to use; copying code needs OH5NXO's permission. Add R58bis to the
   pending question to him.
10. SDCC gotchas in README2 are SDCC 2.7-2.9 bugs; none is known to affect 4.6,
    but two lessons carry over (division by a config value, alternate
    registers), both already handled here (checked below).

## 1. What R58bis is

| Item | Finding | Evidence |
|---|---|---|
| Scope | Full firmware in C + asm for R58-family logic boards, written from scratch (not a port of the asm firmware) | `bis/R58/*.c`, `*.s` |
| Boards | **P8x** (P8E/P8N, probed at boot), **L8M** (old board, RB58VY 6 m defaults), **L8TM** (Computec RB660 2 m defaults); one build per board (`./mak P8x`, `L8M`, `L8TM`) | `mak:3-5`, `maka`, `setup.c:12-40`, `README:83-85` |
| Handsets | CU53 (asm driver, model bits probed) and CU58AF (C driver, PCF8576/8574/PCD3312), autodetected, function pointers | `boot.s:2129-2475`, `cu58af.c` |
| Synths | S8D, S8C, Computec "16/58/S", S8M (MC145156, 12.5 or modified 10 kHz) | `cfg.h:127-133`, `r58bis.c:227-617` |
| Toolchain | SDCC 2.7.0 → 2.9.0 (`sdcc -mz80 --funsigned-char --opt-code-size`), as-z80, `--no-std-crt0 --nostdlib`, own runtime `cclib.s`, own libc-ish `util.s` (2627 lines), FreeBSD | `mak:7-39`, `README2:141-148` |
| Layout | Code from 0x0100, linear up to 0xBFFF (OUT2 = SMEM\|ROM0 at boot: RS=1, RA14=0, "contiguous 48 kB"); RAM 0xC000-0xFFFF; NV 0xC010-0xCFFF (cfg 0xC100, memories 0xCA00, RFC table 0xCF00); page-aligned buffers 0xD000-0xDFFF; task stacks; `_DATA` at 0xE200. `mkbin.c` appends the initialised-data image after `_etext` and patches a ROM checksum; boot copies it | `boot.s:31-136,376-383,415-421`, `mkbin.c` |
| Size | Last build: `_CODE` 0x600F (24.6 KB) + 2.7 KB data image; `P8x.bin` content ends at 0x6437. Fits 32 KB; the 48 KB window was never needed except for the voice sample | `boot.map`, `P8x.bin` |
| Features | Frequency entry (3/4-digit implied prefix), 100 memories (40 on L8M), scanner with linger/stay/hog and timed rejects, setup menu, squelch (noise/RSSI/IN7, bilevel, hysteresis), CTCSS TX by DDS on the RFC DAC, DCS TX (disabled), CCIR RX, DTMF RX (8870 multiboard; MT8888 experiment), FX429 FFSK RX/TX of 8/15-byte packets (shown as hex on a debug port), AX.25 AFSK TX (test UI frame), CW / CCIR / DTMF-burst TX from setup strings, satellite mode with Doppler steps and AFC from IN7, COS output on EXIN1 with polarity, multi-band legal-TX table, voice sample playback (v52 only), NMEA parser (fields only, no use) | `r58bis.inf`, `r58bis.c`, `setup.c:183-280` |
| Not there (vs ours) | Repeater, MPRS/APRS from GPS, remote config, MBUS protocol, VIP, DTMF/CCIR commands, CTCSS decode, per-band steps | absence in sources |
| State | Many `XXX` notes; DCS `#if 0` (`r58bis.c:756-760`), AFSK RX not called (`afsk_rx.s:1` "hopeless"), MT8888 "seems not work" (`r58bis.c:1646-1648`), CU58AF volume "does not work right" (`cu58af.c:319`). Version `130509#61`, files to 2014-02-11, dir to 2015-12-21. Later community work (ALs 2018) stayed on the asm line. **Abandoned experiment** (inferred) | `r58bis.c:10`, `README:47-49`, timestamps |
| Other subdirs | `old.P8x/` (2008 snapshot, C CU53 driver), `zzz/NN` (version snapshots 15..54), `r58bis.tar.gz` (2011 snapshot, older than `R58/`), `AD1200F/` and `orig.aplicom/` (Aplicom 80C188 terminal, RB660 top board: unrelated), `xxx/R58` | listings |

## 2. Architecture comparison

| Area | R58bis | Ours |
|---|---|---|
| Tasking | **Preemptive, 3 tasks** with 1 KB stacks: TASK_0 mainline (`hare` every tick, `tortoise` 256 Hz, `slug` 1 Hz), TASK_1 SIO A input (NMEA), TASK_2 hook. `sleep/wake/yield/hog`, switch on the 256 Hz tick, flags in one byte (`boot.s:479-1070`, `README:6-10`) | One C `mainloop` polling checks, plus soft-interrupt (SIR) work after systick (`c/mainloop.c`, firmware-timers-audio.md §6.3) |
| Timer tick | PIO A0 1968.75 Hz interrupt; 24-bit fraction accumulator (`+0x214A` per interrupt) gives an exact 256 Hz tick and a 32.24 s clock; wrap-safe `timef_mark/passed` (`boot.s:821-870`, `util.s:1723-1798`) | Same interrupt; systick every 20th = 98.44 Hz via E' counter |
| Interrupts | IM2, vectors in RAM (`_iv` at 0xE200, PIO-A vector swapped to switch CTCSS/DCS/plain); alternate set = PIO-A scratch only; SIO handlers nest (EI early, `pusha_int`); tick deferred if nested (`dotick`); nested `disable()/restore()` via `rst 0x30` + counter (`boot.s:169-215`) | IM2 table in ROM at 0x0140; alternate set owned by PIO-A; DI/EI pairs |
| ADC | Coroutine in the PIO-A ISR: one conversion per 2 interrupts, RSSI/SQL at double rate (`boot.s:1235-1330`) | One read every 4 interrupts, list-driven (firmware-timers-audio.md §3) |
| CTCSS TX | DDS on DA_RFC from the PIO-A ISR, 16-bit phase, sine centred on RFC only in full duplex, else 0x80 (`boot.s:1660-1700, 802-819`); TX end inverts phase (stub) | DDS on DA_RFC, always centred on RFC; stop = skip |
| DCS TX | 23-bit frame (Golay parity in asm), rendered once to a 337-sample slope-shaped wave, played at 1968.75 Hz on DA_RFC (`dcspat.c`, `util.s:1930-2090`, `boot.s:785-800`); disabled | none |
| CTCSS RX | none (only external decoders) | DSP decoder on multiboard bit 0 |
| DTMF | RX: 8870 from the EPROM1 window (`read_8870`, 2-3 reads, `boot.s:1356-1394`) or MT8888 at I/O 0xC0; TX: PWM sine pair at 15.75 kHz (`dtmf.s`), CU58AF PCD3312 | RX from the window; TX PWM; PCD3312 |
| FSK | FX429 interrupt-driven RX and TX (TX from a buffer queue), CRC in software (`r58bis.c:1691-1763`); L8x: FX419 + SIO A sync | FX429 RX interrupt, TX polled |
| AFSK/APRS | TX only: PWM DDS at 14.4 kHz (`afsk.s`); RX attempt by zero-crossing timing on PB4 with an external comparator, unused | TX PWM; RX none (the tests decode our TX) |
| GPS/NMEA | Sentence splitter into field pointers (`util.s:1799`), struct overlays for RMC/GGA/…; only echoed to the debug port | Parser + APRS/MPRS positions |
| Setup/config | Table of 16-byte records (type, address, default, value table, 8-char name), types TABLE/BYTE/WORD/DWORD/LONG/STRING/SPECIAL/SUBMENU/MEMORY, generic show/assign/bump (`setup.c`). README2:60-71 lists planned units (kHz, Hz, dHz, s, ms, mV, ranges, OFF/ON, list) that the code does not implement | REC tables in asm data, C engine (`c/menu.c`); more types |
| NV | `struct cfg` with **magic + size**; `new_defaults` zeroes and defaults only the part beyond the stored size (`setup.c:331-355`); P8N copy loops protected against NMI (`bombstack`, `retry_save`, `boot.s:1423-1610`); L8M EEPROM page writes with toggle polling | No magic or checksum (firmware-system.md:95); SAnE defaults |
| ROM banking | Linear 48 KB (RS=1, RA14=0) permanently; RS=0 only for the 8870 read; RA14=1 only for the voice sample; NMI forces OUT2 back (`boot.s:254-271`) | Fixed 32 KB + bank 1 (RA14=1) + bank 2 (RA14=0) through trampolines |
| Watchdogs | Hardware WD written only from the tick ISR; **software `fido`** counts ticks, cleared by the mainline, crash after 10 s (`boot.s:618-627, 507-508`) | WD written in systick and loops; no mainline liveness check |
| Debug | VT100 output to SIO A (P8x) / B (L8x): display mirror every 16 s, packets, NMEA; crash handler dumps SP and stack in hex, then reboots (`crash.s`) | Emulator, tests |

## 3. Hardware knowledge

Tags: **C** = corroborates our notes, **N** = new to us, **X** = contradicts
our notes or assumptions.

| # | Tag | Item | R58bis evidence | Ours |
|---|---|---|---|---|
| 1 | N, resolves | FX429 CLK = IC3 pin 9 = 74HC4040 Q1 = **4.032 MHz** (P8E) | `bis/zzz/IC:4-7` | hardware.md:94 (IC3 type unknown) |
| 2 | N, resolves | IC27 = **74HC21**; IC17/18 = 74HC107, IC28 74HC109, IC29 74HC74, IC14 74HC4059, IC8 82S129, IC9 SRM20256, IC16 HN27C101; IC10 '08, IC11 '32, IC12 '00, IC5 '139, IC6 '154 match our trace | `bis/zzz/IC:34-58` | hardware.md:75-94 |
| 3 | X (small) | SIO clock = 4.032 MHz / 26 = **155 077 Hz** (74HC4059 mode 8); MBUS 9692 baud, GPS 4846 baud (+0.96 %). "4.032 MHz / 26.25 would be exact" | `bis/zzz/IC:101-124` | hardware.md:17 "153.6 kHz" |
| 4 | N | **P8E wait states on M1 and on ADC, DAC1/2 and modem chip selects** | `README2:56-58` | hardware.md:13, emu/notes/r58.md (timing paragraph; M1 only) |
| 5 | C | P8E watchdog: second 74HC4040 on 1968.75 Hz, reset by /CSWD or /LOCAL, Q11 = WD out, Q12 = OFF | `bis/zzz/IC:19-33` | hardware.md:69 (P8E assumed same), :145 |
| 6 | C/X | Watchdog causes **NMI** with PA_WDR set ("RESET pulse from watchdog (doesn't create /RESET)"); NMI handler checks WDR first | `r58bis.c:1580-1590`, `boot.s:336-351` | service-manual-p8n.md:139 (p85 NMI vs p86 RESET conflict); firmware-system.md:184 assumes /RESET |
| 7 | N | NMI sources: watchdog, supply loss (CPU /RESET about 1 ms later), ON/OFF to off, which **bounces sometimes**; he saves on supply loss only after 3 s uptime | `r58bis.c:1578-1603` | firmware-system.md:126-139 |
| 8 | C+N | SIO A DCD combined interrupt is a **74HC107 toggled** by falling FX429 /INT, falling 8254 OUT2, either hook edge; reading 0x23 resets the hook edge latch and the OUT2 latch; **8254 OUT2 must idle high or these interrupts are blocked** | `r58bis.c:1099,1851-1853`, `boot.s:1157-1161` | service-manual-p8n.md:195-205, :223 (74HC107 role unknown); firmware-timers-audio.md §1.4-1.5 |
| 9 | C | PB5 = 8254 OUT2 state ("old CTCSS in") | `iomap_P8x.h:101` | service-manual-p8n.md:178 |
| 10 | X/C | **PA1 = 1 when off hook** ("0 onhook"); hook also reaches SA.DCD | `iomap_P8x.h:91`, `r58bis.c:207-218`, `README2:135` | hardware.md:68 assumes 1 = on cradle; firmware inconsistent (firmware-system.md:210) |
| 11 | C | MON (SIO B DTR) pulses override the power switch: toggled every tick only when "no OFF" is set | `boot.s:630-633,1996-2013`, `iomap_P8x.h:87` | hardware.md:70 open; service-manual-p8n.md:148 |
| 12 | C+N | P8E RAM: `out (0xB0),1` and "16 kB battery backed RAM 0xC000-0xFFFF", PB0 no effect. P8N: PB0 = RAMA12 kept 0 | `README2:29-45` | hardware.md:25 (only 0xC000-0xCFFF inferred NV on P8E) |
| 13 | C | OUT2 bits ROMA14 01, ROMA15 02, ROM0 04 (RS), SMEM 08 = ROMA16 on P8E; RS=0 reads EPROM1 | `iomap_P8x.h:71-78`, `README2:35-43`, `boot.s:1356-1394` | hardware.md:24,33,72 |
| 14 | N, strong | RS=1, RA14=1 maps **EPROM0 chip 0xC000-0xFFFF** at 0x8000: v52 image + `silly.s` voice playback | `silly.s:13-30`, `bis/R58/P8x_52.bin` 0xC000- = `bis/onions_.raw`, `bis/zzz/52/r58bis.c:725-731` | hardware.md:72 "not a bench test of the RA14=1 page" |
| 15 | C+N | EPROM1 socket (IC16) pinout: pin 2 = OUT2 ROMA16, pin 3 = ROMA15, pin 29 = ROMA14; multiboard data D7 = StD, D6..D3 = d3..d0, D0 = "afsqw" (CTCSS slicer) | `bis/zzz/IC:60-76` | hardware.md:24, firmware-timers-audio.md §5.3 |
| 16 | N | **Open bus**: with no EPROM1, a read of 0x80xx returns the last opcode byte | `boot.s:1354` | Our `dtmf_decoder` reads with `ld a,(hl)` (0x7E, StD = 0), so an empty socket is harmless (inferred) |
| 17 | N | P8E extra I/O selects: **0xC0 /CSPROM** (82S129 PROM socket IC8: A0-A3, D0-D3, /RD), **0xD0 /CSKEY** (switches the PROM supply); 74HC154 decode, "last 3 only on P8E" | `iomap_P8x.h:39-46`, `bis/zzz/IC:78-86` (82S129 at :79), `r58bis.c:1209-1249` | hardware.md:42 lists 0xB0 only |
| 18 | N | MT8888 DTMF transceiver tried in the 82S129 socket at 0xC0-0xC3: "MT8889 timing incompatible", "8888 timing looks unsuitable too" | `README2:150`, `r58bis.c:1213-1230,1640-1648` | relevant to the "next-generation multiboard" idea, hardware.md:97 |
| 19 | C | CU58AF keypad row 6 on P6, P7 unconnected | `cu58af.c:143-144,235` | hardware.md:71 |
| 20 | N | CU58AF: two PCF8574 at 0x40 (DM58 + HS58); COLBTN bit 3 labelled "POWER"; bits LDR 0x10, SPEAKER 0x20, TANGENT 0x40, OFFHOOK 0x80; CTRL 0x7C bits SPK_OFF 01, DTMF_ON 02, CONNECT_AF 04, MIC_ON 08, EAR_ON 10, volume E0; PCD3312 'B' = 0x3F (1768.5 Hz); HS58 may be absent (probe by I2C ack) | `cu58af.c:137-161,343-456` | firmware-handsets.md §3.3-3.9 (our bit 3 quirk; firmware needs a 0 there) |
| 21 | C+N | CU53 "display type" bits after the keycode = model: 0 = no handset (DCU pulldown), 3 = CU53AN; DP loops back to DCU after 8 clocks | `boot.s:2194-2210,2398-2420` | handset-manuals.md §1.4 (pull-ups read 1,1) |
| 22 | N | Handset connector with radio port bits: 5 /PTT 4k7 pull-up SB.CTS; 6 EXIN1 (/SERV out, 100k pull-up, 2k2 series) PB1; **7 LOCAL SB.SYNC**; 11 ON# PA3; 12/13 CS1/CS2 O2.4/O2.5; 14 DA/INT# SA.CTS; 15 EXAL 100R PB6; 16 DP O2.7; 17 DCU/SDA PB3; 18 CLK/SCL O2.6; 19 DM (MBUS) SB.DCD; 22 HK SA.DCD or PA1; 24 EXIN2 (100k pull-up, 2k2) PB2; 25 +VB switched; MIC/ERP ~100 mV RMS | `README2:112-138` | handset-manuals.md §1.3, §2.3; service-manual-p8n.md:214-218 |
| 23 | N | Stuck battery ADC: "wiggling d/c power cable, ad_batt sticks at FF"; resetting the mux to IN7 did not help | `boot.s:1236-1240`, `r58bis.c:1237-1240` | none (FF reads as a full battery, so low battery would go unseen) |
| 24 | C | S8D control register: his code sends deviation LSB first; with a 74HC4094 that puts the LSB in Q8, i.e. **reversed** against the service manual (B5 = LSB). Our firmware sends it MSB first, which matches the manual. Keep ours | `r58bis.c:403`; `bis/../R58.rf-boards.pins.a8n.txt` | service-manual-p8n.md:282-291, firmware-rf-ui.md §1.2 |
| 25 | N | MB87006 load: N/A before R, whole load under DI, "15 bits between strobes, not 18", so the VCO does not wander with a mixed R/NA | `r58bis.c:279-303` | firmware-rf-ui.md §1.4 (ours: R then N/A) |
| 26 | N | **RFC-DAC CTCSS mod**: tap after R72 (2k2) at C59/R73 (RFC filter) → series C + R → A8N IC6 pin 13 (-OP1). C59 1 µF with 2k2 is a ~72 Hz pole, so the tone is attenuated there (inferred) | `bis/rfc_dac_ctcss_schema.gif` (crop of `reference/Rx58_processor_and_audio_module_schema_and_placement-OH3TR-secure.pdf` p9 plus his red wire) | firmware-timers-audio.md §4.1 (method only) |
| 27 | C | A8N: FFSKOUT → R57 56k → IC6 -OP1 (pin 13); C30 "100" and R55 100k from pin 13 to O1 (pin 4); R55 sets FFSK + CCIR + mic level, R25 mic after the clipper, R7 mic before it | same gif, `README2:106-110` | hardware.md:116-139 |
| 28 | N | On P8x/A8N the FFSK input does **not** pass the MF6 LPF (on L8TM it does), so the LPF clock may stop in RX | `util.s:2193-2216` | hardware.md:120-121 |
| 29 | N | Measured on P8E: tick 0.4 ms every 4 ms; CU58AF full update 24-26 ms; CU53 update 12 ms; L8TM idle tick 160 µs, HALT 350 µs | `README2:73-99` | reference points for emulator timing |
| 30 | C | P8E/P8N probe with 8254 counter 1 and 20 NOPs (P8E reads 18, P8N −18) | `boot.s:752-783` | firmware-timers-audio.md §1.6 |
| 31 | N | L8M and L8TM boards (we know neither): full I/O maps, L8TM BANK port 0x70 (ROM1 A14/A15, ROM0 A15, SIO A RxC source), ADC at 0x80 (L8TM) or 0x40 (L8M), OUT1 = OUT2 at 0x50, watchdog 0x90/0x70; L8M config in a 2 KB NMC9817A EEPROM (two 1 KB blocks, 32-byte pages), PA1 reads /SLOCK (PLL lock) on L8M; L8TM uses FX419 on SIO A in sync mode and a DS1210 | `iomap_L8M.h`, `iomap_L8TM.h`, `README2:18-27,47-48`, `boot.s:1417-1610` | none |

## 4. Techniques worth borrowing

| Technique | What it gives us | Notes |
|---|---|---|
| Config versioning: magic + stored size; default only the fields past the old size (`setup.c:331-355`) | NV layout can grow with new features without SAnE, and garbage NV is detected | Our NV has no header (firmware-system.md:95). Needs a few free NV bytes and a rule "append only" |
| Mainline liveness counter (`fido`, `boot.s:621-627`) | A hung mainline (C loop) reboots instead of sitting forever; today systick kicks the WD whatever the mainline does | Legit long waits (MBUS `getchar`, `waitkey`) must clear it |
| Crash dump to a serial port (`crash.s`) on RST 38 or bad vectors | Field diagnosis on real hardware | SIO B (MBUS) is always wired; keep it in fixed ROM |
| DCS encoder (`dcspat.c`, `util.s:1930-2090`) | DCS TX for repeaters that use it | Precompute the 337-sample wave (RAM), play it in the PIO-A slot where the CTCSS DDS already is; ~250 B code. Same audio path as RFC-DAC CTCSS (item 26) |
| CTCSS phase reversal at TX end (`boot.s:1710-1730`) | Squelch-tail elimination on CTCSS receivers | His version is a stub (power is cut at once). Needs ~150 ms of reversed tone before TXOFF |
| Handset presence via CU53 type bits (`boot.s:2194-2210`) | Detect "no handset" | Optional |
| CCIR/CW level by placing the MF6 cutoff near the tone (`LPF_ccir`, `util.s:2218-2226`) | Cleaner, level-adjustable square-wave tones | Experimental |
| Open-bus model "last opcode" (item 16) | Emulator fidelity for an empty EPROM1 socket | Small emu change |
| P8E I/O waits (item 4) | Emulator fidelity | Our PWM loops write the 8254 and WD only, so the DTMF/AX.25 tests should not move (inferred); the DDS ISR gains a constant cycle |
| Size tricks seen | `--nostdlib` with own small runtime; `rst` vectors for `jp (hl)`/`(ix)`/`(iy)`, RETI and nested disable (1-byte calls); page-aligned tables with `ld h,#>tab`; formatting right to left into guard-padded buffers; divide-by-byte with remainder (`ulmoddiv`) instead of 32-bit division | We are not short of ROM (12.5 KB fixed free). Our RST slots hold boot code, so the rst trick would need the boot code moved |
| Cycle-count checker (`bis/count_t`), stack-usage and symbol-size scripts (`bis/stackusage`, `R58/zf`) | Static checks | Our emulator tests already pin the PWM timing |
| Not worth it | Preemptive tasking (complexity, RAM for stacks); AFSK RX on a PIO pin (`afsk_rx.s`, needs a comparator mod, "hopeless"); MT8888 in the PROM socket (timing failed); generic synth R-search, satellite/Doppler/AFC (niche) | |

## 5. Pitfalls he documented and our SDCC 4.6 build

| His note | Applies to us? |
|---|---|
| `ad_batt * 5000UL * 47 / (147 * 256)` always 0 (README2:50) | SDCC 2.x constant handling. Not known in 4.6; our C has no such expression (grep of `c/*.c`) |
| `if (!s) s = "foo";` later uses "foo" for `s` (README2:52) | SDCC 2.x bug; nothing to do |
| `n % 0` loops forever (README2:54) | Our runtime divisions by config values are guarded: `c/ptt.c:125-128` (`cfg_txtune_hz` 0 checked), `c/rptr.c:404-406` (`delta > 0`). Below 62 Hz the tune-tone count overflows 16 bits (truncated, harmless) |
| SDCC interrupt code did not save the alternate set (README:93,129) | Our rule already: alternate set belongs to PIO-A (hybrid-plan.md:229). Checked: no `exx`/`ex af,af'` in `/usr/share/sdcc/lib/src/z80/*.s` (4.6 library sources) |
| `p->rx_freq & 0xFFFFFF` "SDCC-3.0 has fixed a bug (?)" (`r58bis.c:805`) | Old 24-bit masking issue; nothing to do |
| `--funsigned-char` | Our code uses `uint8_t`; SDCC 4.x defaults to unsigned char anyway (from memory, not checked) |
| NMI during a P8N NV copy (he restarts the save from a ROM-safe stack) | **Ours has a one-byte hole**: `save_nvmisc_and_restart` (`r58/r58.s:7821`) does its first `ld a,(hl)` with whatever OUT2 the interrupted `save_nvdata` left; if the NMI lands between `out (c),d` and `out (c),e` (`r58.s:7872-7874`), the first byte (`nvstart` = `audio_dst`, 0xC000) is copied battery→battery and its work-RAM value is lost. A window of a few µs per byte, so rare and minor. Fix: `out (c),e` before the loop. DI does not mask NMI |
| ON/OFF bounces (`r58bis.c:1584`) | Our NMI always saves and restarts; a bounce reboots the radio (start re-checks PA3). Acceptable |
| "poks poks from speaker was caused by forgotten MTC (or CCIRC)" (`bis/XXX`) | General audio-path hint |

## 6. Licence and attribution

- No licence, copyright or permission text in `R58bis/` or `R58/` (grep, all
  text files). The archive README (`reference/oh5nxo/README.txt`, Finnish)
  says the collection may contain material once marked "not to be passed on",
  which he believes has expired; it grants nothing.
- R58bis is OH5NXO's own code (version string `@(#)R58bis`, `r58bis.c:10`;
  tar owner `junki`, the archive's owner).
- Default: all rights reserved. Hardware facts and ideas can be used with
  attribution; copying code (e.g. `dcspat.c`, `dcs_frame`) should wait for his
  permission. Ask about R58bis together with the pending ALs question
  (hybrid-plan.md:14-18).

## Recommended follow-ups (ranked)

1. **Update notes/hardware.md with the settled items** (IC3 = 4040 so modem
   CLK 4.032 MHz; IC27 = 74HC21; 74HC107 = DCDA toggle; SIO clock 155.08 kHz;
   P8E watchdog wiring; P8E I/O selects 0xC0/0xD0; CU58AF row 6; MON as
   switch-off override; RA14=1 page used by v52). Effort: 30 min. Evidence:
   §3 items 1-3, 5, 8, 11, 14, 17, 19.
2. **Check hook polarity on a real radio** (lift the handset, read PA1 in the
   status display or a test ROM), then fix whichever of the hook script /
   sitter's special path is wrong and the emulator default. Effort: 15 min on
   the bench + a small fix with a test. Evidence: §3 item 10, `c/timers.c:54`,
   firmware-system.md:210.
3. **Emulator fidelity**: P8E +1 wait on I/O to 0x30, 0x40, 0x50-0x57,
   0xA0-0xAF; open bus = last opcode for an empty EPROM1 socket; SIO clock
   155.08 kHz. Run the timing tests to confirm nothing moves. Effort: 2 h in
   moppe-emu. Evidence: §3 items 3, 4, 16. Check the I/O-wait claim on the
   P8E schematic (IC27/IC28/IC29) first.
4. **NV header with magic + size, append-only growth** before the first new
   feature that needs NV fields. Effort: half a day incl. tests (old images
   without the header must still boot). Evidence: `setup.c:331-355`.
5. **Mainline liveness watchdog** (counter in systick, cleared by the
   mainloop and by the known long waits; reboot after ~10 s). Effort: 2-3 h
   incl. a test with a deliberately hung loop. Evidence: `boot.s:618-627`.
6. **Close the NMI one-byte hole** in `save_nvmisc_and_restart` (`out (c),e`
   before the copy loop), with an emulator test that fires NMI between the two
   OUTs on P8N. Effort: 1 h. Evidence: §5, `r58/r58.s:7821-7874`.
7. **DCS encoder** as a new feature in bank 2, after the licence answer or as
   an own implementation from the DCS spec (his Golay parity equations,
   `util.s:1958-2060`, are the standard ones). Effort: 1-2 days incl. an
   emulator decoder test. Evidence: `dcspat.c`, `bis/XXX` "check dcs +023 …
   ok".
8. **Document the RFC-DAC CTCSS hardware path** (the mod wire) in
   notes/reference/firmware-timers-audio.md §4.1 or hardware.md; the series
   C/R values are not on the gif (the photos `bis/kuvat/L8TM_ctcss*.JPG` are
   L8TM and were not checked). Effort: 30 min. Evidence: §3 item 26.
9. **CTCSS reverse burst** option at TX end. Effort: half a day. Evidence:
   `boot.s:1710-1730` (idea only).
10. **Crash dump over MBUS** on unexpected RST 38 / bad vector. Effort: 2 h.
    Evidence: `crash.s`.
11. **Add R58bis to the question to OH5NXO** (permission to reuse code, e.g.
    DCS). Effort: one line in the mail. Evidence: §6.
