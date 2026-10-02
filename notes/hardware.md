# R58 hardware as the emulator models it

Status tags: **confirmed** = the firmware in the emulator depends on it and
the tests pass; **source** = read from firmware source or a document, not
exercised; **inferred** = our deduction; **open** = unresolved.

Detailed per-area specs are in `notes/reference/`.

## CPU cards

| | P8E ("/H" units) | P8N |
|---|---|---|
| CPU | Z84C0008, 8.064 MHz, **+1 wait state per M1** incl. prefix bytes (confirmed: P8E detection, DTMF/AX.25 loops). OH5NXO (R58bis `README2` "P8E waitstate from M1 _or_ adc or dac1/2 or modem chipselect"): also a wait on ADC, DAC1/DAC2 and FX429 I/O cycles. Not modelled; check the schematic (IC27?) | Z80, 4.032 MHz, no waits (confirmed) |
| Crystal | 8.064 MHz (schematic) | same |
| 8254 | CLK0/CLK1 4.032 MHz, CLK2 1968.75 Hz (confirmed) | same |
| System tick | PIO A0 = 1968.75 Hz square, interrupt per falling edge; systick every 20th = 98.44 Hz (confirmed) | same |
| SIO clock | 153.6 kHz → 9600 (×16, MBUS on B), 4800 (×32, GPS on A) (source; GPS RX confirmed). OH5NXO's P8E chip list (`reference/oh5nxo/mods/R58bis/zzz/IC`): IC14 74HC4059 in mode 8 dividing 4.032 MHz by 26 = **155.08 kHz** → 9692 / 4846 baud, 1 % fast (the emulator uses 153.6 kHz) | 153.6 kHz assumed (not checked) |

## Memory

| Range | P8E | P8N |
|---|---|---|
| 0x0000-0x7FFF | EPROM0 (27C512 per parts list), firmware 32 KB (confirmed) | EPROM0 27C512 (manual p87-90, p105) |
| 0x8000-0xBFFF | OUT2.RS=1: EPROM0 chip 0x8000 (RA14=0) or 0xC000 (RA14=1) page; RS=0: EPROM1 socket (27C010, A14/A15/A16 = OUT2 bits 0/1/3), where the community DTMF/CTCSS "multiboard" sits and reads as a status byte at 0x80xx (source: schematic IC5/IC10-12/IC15/IC16, traced by the user 2026-09-28; see below) | banked window, 6 pages: RS=1 → EPROM0 0x8000 (RA14=0) or 0xC000 (RA14=1) page; RS=0 → EPROM1 (27C512) page RA15:RA14 (manual). The community multiboard, when fitted, goes in the EPROM1 socket |
| 0xC000-0xFFFF | 16 KB RAM; 0xC000-0xCFFF config battery-backed (inferred: SMEM copy loops are no-ops on P8E) | 16 KB of a 32K×8 RAM; OUT2.SMEM=0 swaps in the battery RAM at 0xC000-0xCFFF, PIO B0 picks one of two 4 KB copies (manual; firmware always uses copy 0) |

The DTMF/CTCSS "multiboard" in the EPROM1 socket is a community add-on and
**not common** in practice (user, 2026-09-28): on most radios the second
EPROM socket is free, so it can hold program EPROM when more ROM is needed.
The firmware only reads 0x80xx for the DTMF decoder and the DSP CTCSS
decoder, both optional features.

OUT2 (port 0x80) bits: RA14 01, RA15 02, RS 04, SMEM (P8N) / RA16 (P8E) 08,
CS1 10, CS2 20, CLK 40, DP 80. The firmware keeps RA14/RA15/RS at 0 and bit 3 at 1.

## I/O map (confirmed unless noted)

PIO 0x00 (A data, B data, A ctrl, B ctrl), SIO 0x10 (same order), 8254 0x20,
DA_RFC 0x30, DA_TXPWR 0x40, ADC 0x50-0x57 (OUT starts channel n; IN returns
the *last* result, whatever the address), OUT0 0x60 (audio), OUT1 0x70
(synth serial and TXOFF), OUT2 0x80 (handset bus, memory), watchdog 0x90
(any write), FX429 0xA2/0xA3, CSMEM 0xB0 (P8E).

Interrupts: IM2, I=0x01, table at 0x0140. SIO status-affects-vector 0x40-0x4E,
PIO A 0x50 (0x54 once CTCSS DSP/RFC starts), PIO B 0x52 (unused).

Inputs: PA1 hook, PA3 power switch (1 = off), PA7..4 CCIR decoder nibble
(F = idle), PB1 EXIN1, PB2 /IGN (1 = ignition off → auto power-off),
PB3 handset DCU / I²C SDA, PB5 external CTCSS detect; SIO B CTS = /PTT,
SYNC = /LOCAL; SIO A CTS = handset DA or /INT, DCD = FX429 IRQ (inferred).
Outputs: PB7 power relay off, PB6 EXAL, PB4 /RXON (GPIO).

## Handsets

- **CU53AN** (manual + firmware agree, confirmed): CS2:CS1 decode 00 keypad
  load, 01 LED latch, 10 LCD IC8, 11 LCD IC7; two PCF2111 (0, 32 data bits,
  half bit; loaded on deselect); 8-bit shift chain to DCU; MM74C923 keycode
  = 4·(row−1)+(col−1), which the firmware reads inverted as its key-table index.
- **CU58AF** (manual + firmware agree on addresses): I²C SCL = OUT2.6,
  SDA = PB3 (open drain by PIO direction), /INT on SIO A CTS; PCF8574 at
  0x40 (columns and buttons), 0x4C (rows), 0x44 (LEDs), PCF8574A 0x7C
  (audio control), PCD3312 0x48 (DTMF), PCF8576 0x70 (LCD, 40 bytes).

## Open questions

| Question | Current assumption | Where to look |
|---|---|---|
| Hook polarity on PA1 after buffering | **1 = lifted** (assumed 2026-10-01, user: reverse if a radio disagrees; emulator `hook_offhook_level = 1`; was 1 = on cradle) | manual: 0 = in holder *at the connector*; buffer polarity not shown. **OH5NXO's R58bis says the opposite** (`iomap_P8x.h:91` `PA_OFFHOOK 0x02 /* state of HOOK pin, 0 onhook */`). Check on a radio: the hook scripts and the repeater-sitter check (`c/timers.c`) depend on it |
| Watchdog on P8E | same as P8N (0.52 s) | P8N only in manual |
| MON (SIO B DTR): manual says the radio powers off ~1 s after power-on unless MON is pulsed; firmware sets DTR once | not modelled. R58bis (`boot.s:628-630`, `iomap_P8x.h:87` "Master ON pulse, a/c coupled") toggles MON on every tick only when its `stay_on` option ("#ON/OFF override") is set, i.e. MON pulses hold the power on against the switch; without them the switch decides | real radio |
| CU58AF keypad row 6: manual says PCF8574 P7 (P6 unused), firmware decodes '+ S R' from P6 | follow firmware | real handset |
| The RS window and EPROM1 banking on real hardware (P8E from schematic, P8N from manual) | modelled, unverified. **Corroborated (2026-10-01)** by OH5NXO's own SDCC firmware for the R58 (`reference/oh5nxo/mods/R58bis/R58/`, 2007-2014): `iomap_P8x.h` has OUT2 bit 0 ROMA14, bit 1 ROMA15, bit 2 ROM0 ("2 banks from ROM0, if '1'"), bit 3 SMEM ("ROMA16 on P8E"), the same bits as ours; `boot.s` sets OUT2 = SMEM\|ROM0 "for contiguous 48 kB ROM" on P8E and P8N (= our bank 2, chip 0x8000), and README2 has his P8E timing measurements. Not a bench test of the RA14=1 page | the bench test ROM: `make -C firmware banktest`, see notes/hybrid-plan.md Phase 3 |
| P8E: EPROM0 pin 1 (A15) = CPU A15? | assumed (then the window pages are chip 0x8000 and 0xC000, like the P8N) | P8E schematic; the bench ROM checks both pages (`b1b2 PASS`) |

**P8E memory decode as traced by the user (schematic, 2026-09-28).**
IC5/1 "MDEC" (half of a 2-to-4 decoder, presumably 74HC139): /E = "_WREQ"
(presumably /MREQ), A = A14, B = A15; outputs /0 (0x0000-3FFF) → IC10/1
pin 1, /1 (0x4000-7FFF) → IC10/1 pin 2, /2 (0x8000-BFFF) → IC11/1 pin 1
and IC11/2 pin 5, /3 → /CSRAM. IC10 is AND (presumably 74HC08), IC11 OR
(≥1), IC12/1 an inverter of RS. So /CSROM0 = IC10/2(IC10/1(/0, /1),
IC11/1(/2, NOT RS)): EPROM0 for 0x0000-7FFF and for the window with RS=1;
/CSROM1 = IC11/2(/2, RS): EPROM1 for the window with RS=0. EPROM0 A14
(pin 27) is marked "IC10/11", read as IC10 pin 11 (the fourth AND gate,
inputs 12/13), and the block diagram shows A14, A15 and RA14 (OUT2 D0)
combined into EPROM0 A14. The rest (user, same day): RA14 (OUT2 D0) → IC16 (EPROM1)
pin 27 and IC11/4 pin 13; A15 → IC11/3 pin 9 and IC12/2 pins 4+5 (NAND as
inverter) → pin 6 → IC11/4 pin 12; IC11/3 pin 8 → IC10/4 pin 12; IC11/4
pin 11 → IC10/4 pin 13; IC10/4 pin 11 → IC15 (EPROM0) pin 27. So EPROM0
A14 = (A15 OR x) AND (NOT A15 OR RA14), which is **RA14 in the window**
(A15 = 1) whatever IC11/3's other input x is (A14 for a mux; only matters
outside the window). **Settled: the P8E selects the EPROM0 window page by
RA14 like the P8N**; the earlier "A14 forced high" reading was wrong. The
emulator models both cards alike now.
| FX429 modem socket | socketed; RX/TX audio pins carry "raw" RX and TX audio; bus pins /CS, R/W, /IRQ, A0, A1, D0-D7 and a CLK input. R/W = /WR; /CS = /CSMOD = IC6 pin 11, output /10 (Y10 = 0xA0-0xAF), consistent with the I/O map (user, 2026-09-28). **Provenance:** signal and pin readings are from the schematic (P8E); the part number 74HC154 is from the P8N parts list. Both give 0xA0, so the decode is assumed the same on both cards. CLK is the modem IC's own clock, not a bus clock (user). Mic/speaker would need extra wires | IC6 enables (user, 2026-09-28): /E0 (pin 19) = /IORQ, /E1 (pin 18) = /M1 through a gate of IC12 (presumably an inverter), so /CSMOD is active only for I/O cycles without M1: an interrupt acknowledge cannot select the modem. /CSMODEM also goes to IC27, with /M1 on another gate of IC27: what IC27 is and where its outputs go (a bus buffer enable? IRQ gating?). IC27 is a **74HC21** (dual 4-input AND, chip list); with OH5NXO's wait-state note (CPU row) it is probably the wait-state OR of the active-low selects; outputs not traced. CPU pins as read: /IORQ 22, /M1 31 (not the 40-pin DIP numbering, /IORQ 20, /M1 27; which package?). CLK (P8E, user 2026-09-28): the 8.064 MHz crystal oscillator (a gate of IC2) clocks IC3's CP input; IC3 pin 9 goes to the modem's CLK. **IC3 is a 74HC4040** (OH5NXO's chip list `R58bis/zzz/IC`: pin 9 = Q1 = 4.032 MHz, his "phi0"), so with the user's trace (IC3 pin 9 → modem CLK) **the FX429 CLK is 4.032 MHz** (paper, not measured). The same 4040 gives Q12 = 1968.75 Hz, the PIO A0 / 8254 CLK2 tick. P8N: assumed the same frequency at the modem pin (inferred: identical modem chip, which needs its rated clock; the P8N has the same 8.064 MHz crystal and a 4.032 MHz CPU, so only the divider differs). A free-running clock from the CPU oscillator: a replacement board does not need it, but a CPLD can clock its synchronizers from it. Matters for an ESP32 board in the modem socket (see below) |
| Logic family on the CPU card bus | P8N: plenty of 74HC (user, 2026-09-28), so a board driving the data bus must give 5 V CMOS levels (74HC VIH = 3.5 V at 5 V) | schematic, per card |

**Idea (2026-09-28): a "next generation" multiboard in the FX429 socket.**
An ESP32 there would get I/O registers both ways (0xA2/0xA3), an interrupt
(SIO A DCD, shared with hook and 8254 OUT2) and the radio's audio. It is
visible in every bank, unlike a board in the EPROM1 socket (which bank 1
hides), and it would leave both EPROM sockets for code. It needs a CPLD or
latch mailbox between the bus and the ESP32 (the ESP32 cannot meet Z80 I/O
timing in software), 5 V/3.3 V level handling and more supply current.
With A0 and A1 the socket decodes four registers (0xA0-0xA3); the firmware
uses 0xA2 (data) and 0xA3 (control/status), so 0xA0/0xA1 are free for an
extended interface. R/W + /CS is a Motorola-style bus: latch writes on the
rising edge of /CS with R/W low, drive the data bus while /CS is low with
R/W high. With R/W = /WR, a /CS that is low with /WR high means a read;
in a Z80 I/O write /IORQ and /WR fall together, so the contention window
at the start of a write is only gate delays. /CS decodes A7-A4 only, so
the four registers repeat through 0xA0-0xAF. Because of the 74HC loads, a 5 V CPLD (ATF1504AS/ATF1508AS)
fits better than a 3.3 V one (XC9572XL would need a 74HCT245 driver). If
it keeps the FX429 register behaviour, the stock firmware works unchanged.
Still to check: the FX429 bus pins and timing on the datasheet.

**Module candidate and the radio around it (2026-10-02).** User facts: the
5 V bus comes from a **7805CP (TO-220) on the audio board**; there is plenty
of free board space next to the FX429 socket; the case is properly shielded,
so a wireless module needs an external antenna; +13.8 V should be on one of
the CPU-card/audio-card headers (not yet located). Candidate: XIAO
ESP32-S3 Plus (20 GPIO incl. 9 rear castellations, Wi-Fi + BLE, U.FL
antenna). Inferred: it cannot answer Z80 reads in software (~100 ns from
/CS on the P8E, no /WAIT on the socket) and is not 5 V tolerant, so it needs
a hardware mailbox in front: 74LVC574 at 3.3 V for writes (clock = /CS OR
R/W), preloaded 74HCT574s for the 0xA2/0xA3 reads, or one CPLD with SPI.
Alternative front end: an RP2350 (PIO answers the bus directly; its digital
GPIOs are 5 V tolerant). Open: the 7805's heatsinking and present load (an
ESP32-S3 adds ~30-100 mA average, ~350 mA Wi-Fi TX peaks); which header pin
carries 13.8 V; the antenna route out of the case. Voice-grade audio (mic,
speaker, Wi-Fi audio) would need an I²S codec (e.g. ES8311 mono, ES8388
stereo; I²S + I²C ≈ 6-7 pins, so with a codec the CPLD/SPI front end is the
one that fits the pin budget). The ESP32-S3 has BLE only, no Classic
Bluetooth, so no A2DP/HFP headsets. The XIAO size is not required (user,
2026-10-02: larger is fine if available and reasonably priced). Leading
idea (inferred, not prototyped): a carrier with a Pico 2 (RP2350: PIO bus
interface, DSP, I²S codec) plus an ESP32 module with U.FL (wireless only),
linked by SPI or UART; it replaces the CPLD. BT headsets are a bonus, not
required (user, 2026-10-02), so the plan is an **ESP32-S3-WROOM-1U** (newer
chip, PSRAM variants for web UI / OTA / audio buffers), optionally with a
second footprint for an ESP32-WROOM-32UE (the only common ESP32 with
Classic BT) wired to the same few link pins. Chip-down alternative for the
real-time side: RP2354B (RP2350B with 2 MB flash in the package, 48 GPIO,
8 ADC inputs; needs PCB assembly, QFN-80). The radio stays a certified
module: Raspberry Pi's RM2 (CYW43439, Classic BT, same SDK) has only a PCB
antenna, useless in the shielded case.

**Modem socket audio lines (user trace, 2026-09-28):**
- CPU board: FFSKIN has C30 (47 nF) in series; FFSKOUT has C81 (or C61)
  and C31, both 47 nF, in parallel (94 nF), in series.
- Audio board connector PP2: pin 15 = FFSKIN, pin 16 = FFSKOUT.
- FFSKIN (receive audio into the modem) comes from IC2/1 output (pin 1),
  possibly a low-pass filter stage.
- FFSKOUT (modem output) goes through a 56 k series resistor on the audio
  board to IC6 pin 13 ("-OP1"); C30 (value "100", unit missing) and R55
  (100 k pot) in parallel go from pin 13 to pin 4 ("O1?").
- User's reading: only some low-pass filtering between the audio and the
  FFSK lines, so CTCSS decode and encode through the socket look possible,
  among other things.
- Inferred, not measured: IC6/OP1 looks like an inverting amplifier that
  mixes the modem output into the TX audio, gain R55 / 56 k (0 to ~1.8,
  the level trimmer), with C30 across the feedback as the low-pass. If
  C30 is 100 pF its corner with 100 k is ~16 kHz, far above audio; if
  100 nF, ~16 Hz, which would make no sense for FFSK, so pF is likely.
  The 47 nF / 94 nF series capacitors are high-pass filters whose corner
  depends on the load they drive (not known yet): into 100 k, ~34 Hz /
  ~17 Hz, low enough for CTCSS (67-254 Hz). To confirm: C30's value, the
  input impedance behind C30 (47 nF) on the CPU board, what IC2/1 filters
  and its corner, and whether FFSKIN carries de-emphasized or flat
  discriminator audio (CTCSS needs the sub-audio band, which a voice
  high-pass elsewhere would remove).

## Settled by the service manual (P8N; reference/RD58DBG_SBG_Huolto-ohje.pdf)

See notes/reference/service-manual-p8n.md for page references.

- Watchdog: 74HC4040 on 1968.75 Hz, cleared by any I/O to 0x90, disabled by
  LOCAL; about 0.52 s to reset, then power-off about 0.5 s later.
  P8E the same (OH5NXO's chip list: IC4 74HC4040 on 1968.75 Hz, reset by
  /CSWD or /LOCAL, WD out = Q11 (0.52 s), OFF = Q12). PA2 = WDR
  flags a watchdog reset. Emulator: `wd_timeout_s = 0.52`.
- Daisy chain: PIO first, SIO second (as modelled).
- SIO A DCD is a **shared** interrupt: hook change, 8254 OUT2, FX429 IRQ;
  the firmware tells them apart by polling and clears the latch by reading
  port 0x23. Emulator: modem events and hook changes both edge DCDA.
- ADC0809 (EOC unconnected, fixed ~64 µs conversion) and 2 × DAC0832.
  Supply divider 100k/47k → 15.6 V full scale, as the firmware assumes.
- Synth: 2 × MB87006A PLLs, MB501L 128/129 prescaler, 12.8 MHz reference,
  IF 86.5125 MHz, **LO above RX** (emulator default). Control register
  74HC4094; VCO bands are fixed in hardware; lock detect is not read by the CPU.
- A8N audio: OUT0 D0-2 volume (74HC4051), D3 speaker mute, D4 RX audio,
  D5 CCIRC (8254 OUT1 → TX filter), D6 MTC (OUT1 → speaker), D7 mic mute;
  8254 OUT0 clocks the MF6-100 TX low-pass filter at 100× cutoff.
- OUT0/OUT1 latches float during reset (output enable tied to RESET).

## OH5NXO's P8E chip list

`reference/oh5nxo/mods/R58bis/zzz/IC` (2008; the board is not named, the
parts are the P8E's: Z84C0008, 27C512, HN27C101, 32 KB SRAM). IC1 74HC132,
IC2 74HC04, IC3/IC4 74HC4040 (clock dividers above), IC5 74HC139, IC6
74HC154, IC7 Z84C0008, IC8 82S129 (PROM, /CSPROM at I/O 0xC0), IC9
SRM20256, IC10/IC11/IC12 74HC08/32/00, IC13 82C54, IC14 74HC4059, IC15
27C512 (EPROM0), IC16 HN27C101 (EPROM1), IC17/IC18 74HC107, IC19 74HC08,
IC20 74HC32, IC21 Z84C4408 (SIO), IC22 FX429J, IC23 74HC374, IC24 Z84C2008
(PIO), IC25 FX003QC, IC26 74HC08 (?), IC27 74HC21, IC28 74HC109, IC29
74HC74. The file also has the EPROM1 socket pinout (O2_ROMA16 on pin 2,
O2_ROMA15 pin 3, O2_ROMA14 pin 29; multiboard StD on D7, decoder data on
D6..D3) and MT8888 and 82S129 pinouts.
