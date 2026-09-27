# R58 hardware as the emulator models it

Status tags: **confirmed** = the firmware in the emulator depends on it and
the tests pass; **source** = read from firmware source or a document, not
exercised; **inferred** = our deduction; **open** = unresolved.

Detailed per-area specs are in `notes/reference/`.

## CPU cards

| | P8E ("/H" units) | P8N |
|---|---|---|
| CPU | Z84C0008, 8.064 MHz, **+1 wait state per M1** incl. prefix bytes (confirmed: P8E detection, DTMF/AX.25 loops) | Z80, 4.032 MHz, no waits (confirmed) |
| Crystal | 8.064 MHz (schematic) | same |
| 8254 | CLK0/CLK1 4.032 MHz, CLK2 1968.75 Hz (confirmed) | same |
| System tick | PIO A0 = 1968.75 Hz square, interrupt per falling edge; systick every 20th = 98.44 Hz (confirmed) | same |
| SIO clock | 153.6 kHz → 9600 (×16, MBUS on B), 4800 (×32, GPS on A) (source; GPS RX confirmed) | same |

## Memory

| Range | P8E | P8N |
|---|---|---|
| 0x0000-0x7FFF | EPROM0 (27C512 per parts list), firmware 32 KB (confirmed) | EPROM0 27C512 (manual p87-90, p105) |
| 0x8000-0xBFFF | OUT2.RS=1: EPROM0 top 16 KB; RS=0: EPROM1 socket (27C010, A14/A15/A16 = OUT2 bits 0/1/3), where the community DTMF/CTCSS "multiboard" sits and reads as a status byte at 0x80xx (source: schematic IC5/IC10-12/IC16) | banked window, 6 pages: RS=1 → EPROM0 0x8000 (RA14=0) or 0xC000 (RA14=1) page; RS=0 → EPROM1 (27C512) page RA15:RA14. Multiboard in the EPROM1 socket (manual) |
| 0xC000-0xFFFF | 16 KB RAM; 0xC000-0xCFFF config battery-backed (inferred: SMEM copy loops are no-ops on P8E) | 16 KB of a 32K×8 RAM; OUT2.SMEM=0 swaps in the battery RAM at 0xC000-0xCFFF, PIO B0 picks one of two 4 KB copies (manual; firmware always uses copy 0) |

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
| Hook polarity on PA1 after buffering | 1 = on cradle | manual: 0 = in holder *at the connector*; buffer polarity not shown |
| Watchdog on P8E | same as P8N (0.52 s) | P8N only in manual |
| MON (SIO B DTR): manual says the radio powers off ~1 s after power-on unless MON is pulsed; firmware sets DTR once | not modelled | real radio |
| CU58AF keypad row 6: manual says PCF8574 P7 (P6 unused), firmware decodes '+ S R' from P6 | follow firmware | real handset |
| P8N memory decode for more ROM | none | no P8N schematic |
| The 16 KB RS window and EPROM1 banking on real P8E hardware | modelled, unverified | a bench test |

## Settled by the service manual (P8N; reference/RD58DBG_SBG_Huolto-ohje.pdf)

See notes/reference/service-manual-p8n.md for page references.

- Watchdog: 74HC4040 on 1968.75 Hz, cleared by any I/O to 0x90, disabled by
  LOCAL; about 0.52 s to reset, then power-off about 0.5 s later. PA2 = WDR
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
