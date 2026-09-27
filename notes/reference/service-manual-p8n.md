> Provenance: 2026-09-28 research subagent, OCR of reference/RD58DBG_SBG_Huolto-ohje.pdf (P8N, A8N, S8D, CU53AN). Page numbers are PDF pages.

# RD58 service manual ("Huolto-ohje RD58DBG/SBG") findings

Source: `reference/RD58DBG_SBG_Huolto-ohje.pdf`, 244 pages, 3rd edition 08.02.1990.
Page numbers below are **PDF page numbers**. All pages except p1 are 300 dpi 1-bit scans. The text layer
only holds the red TTRK/Nokia banner, so I OCR'd every page (tesseract `fin`). OCR text and page PNGs
are in `scratchpad/manual/pNNN.{png,txt}`.

Labels used below: **read** means stated in the manual. **inferred** means derived from the drawings,
from pin numbers or from datasheet knowledge. **not found** means the manual does not cover it.

## The most important caveat

This manual covers the **P8N** logic board only, together with the A8N audio board. The product structure
lists (p5–6) name P8N for both RD58DBG and RD58SBG. **"P8E" does not appear anywhere** (I searched the OCR of
every page). The P8N section has **no full circuit diagram**. It has a block diagram (2A 304819, p102), board
layouts (p103–104) and a parts list (p105–106). The parts list refers to "1B 304819 Piirikaavio P8N", but
that sheet is not in the PDF. The **A8N full schematic is included** (2B-423 / 1B 304802, p107).

## Table of contents (PDF pages)

| Pages | Content |
|---|---|
| 1 | Legal notice (TTRK publication permission) |
| 2 | Cover |
| 3 | Contents list (chapters 1–25) |
| 4–13 | Product structure (RD58 variants tree p4; DBG p5, SBG p6: A8N, P8N, S8D, V8DRB, V8DTB, R8DG, T8DB, DF8D/AF8D, Q8N); accessories p7–13 |
| 14–21 | Technical data (RD58DBG p15–17, RD58SBG p19–21) |
| 22–28 | System block diagram (p22); channel table / channel numbers 3200.., 3720.. (p24–28) |
| 29–32 | Block diagram / interconnection drawings |
| 33–40 | Unit interfaces: SP (S8D) p33, VR/VX p34, VT/VZ/SR/ST p35, RP (receiver) p36, TP/TK (transmitter) p37, **CA handset connector p38–39**, FA/UK p40 |
| 41–52 | Installation instructions (Asennusohje) |
| 53–72 | **Service mode ("LOCAL-tila") user guide**: test numbers 10–99, 700–900 parameter programming (p54–69); Actionet system-parameter table p70–72 |
| 73–77 | Tuning instructions (synth/VCO, TX, RX) |
| 78–82 | Chassis RD58: unit location & cabling (p78–79), exploded view (p80), parts (p81–82) |
| **83–112** | **System logic P8N + A8N**: description p84–101; P8N block diagram p102; P8N layouts p103–104; P8N parts p105–106; **A8N schematic p107**; A8N layouts p108–109; A8N parts p110–112 |
| 113–118 | Filter module Q8N |
| 119–145 | Synthesizer S8D + VCOs V8DR/V8DT: description p120–128, test p129–132, block diagram p133, S8D schematic p134, layouts p135–136, parts p137–138, VCO drawings p139–145 |
| 146–157 | Receiver R8D(BG) |
| 158–170 | Transmitter T8D |
| 171–178 | Antenna filter AF8D (simplex) |
| 179–180 | (Duplex filter DF8D, short; p179 has no image) |
| 181–209 | **Handset CU53AN**: description p181–189, drawings/parts p190–209 (DM32M display module, LM32A logic module, EA32M earpiece amp, O8L filter) |
| 210–217 | Interface unit JT58 / E8J |
| 218–220 | Handset holder HT58, swivel VT58 |
| 221–227 | Battery UL50 / charger CM1 |
| 228–233 | Test box TK58 |
| 234–239 | Cables (VK58, UC58, US58R, system cable) |
| 240–243 | Installation kit M58, extra speaker SP58 |

Handset CU58AF is not covered anywhere.

---

## Q1. Memory map (P8N): read, pp. 87–90, 102, 105–106

**Parts (p105–106, read):**
- IC15 and IC16 are both **EPROM 64K×8 CMOS 300 ns, MBM 27C512-30, DIL-28** (EPROM0 and EPROM1).
- IC8 and IC9 are both **SRAM 32K×8, 120–150 ns, SO-28**.
- G1 is a 3 V 500 mAh lithium cell (BR2354).
- Decoding logic: IC5 74HC139 (dual 2→4, memory decoder), IC6 74HC154 (4→16, I/O decoder), IC23 74HC374 (OUT2).

**Program memory (p87–88, 90, read):** 32 KB is direct plus 96 KB in six 16 KB pages, total 128 KB = 2 × 27C512.
The decode table (p90, "Muistin osoitus P8N:ssä") reads:

| A15 | A14 | RS | RA15 | RA14 | EPROM0 A14 | /CSROM0 | /CSROM1 | Result |
|---|---|---|---|---|---|---|---|---|
| 0 | 0 | x | x | x | 0 | 0 | 1 | EPROM0 0000–3FFF (direct) |
| 0 | 1 | x | x | x | 1 | 0 | 1 | EPROM0 4000–7FFF (direct) |
| 1 | 0 | 1 | x | 0 | 0 | 0 | 1 | EPROM0 chip 8000–BFFF = page 1 |
| 1 | 0 | 1 | x | 1 | 1 | 0 | 1 | EPROM0 chip C000–FFFF = page 2 |
| 1 | 0 | 0 | 0/0/1/1 | 0/1/0/1 | x | 1 | 0 | EPROM1 pages 3/4/5/6 (chip A15:A14 = RA15:RA14) |
| 1 | 1 | x | x | x | x | 1 | 1 | RAM0/RAM1 |

- In the block diagram (p102), OUT2 D0 = RA14 feeds a mux "A14/A15 → PROM0 A14". EPROM0's A14 is therefore CPU A14 when A15=0 and RA14 when A15=1.
- EPROM1 uses RA14 and RA15 as its A14 and A15, so all 64 KB of it is reachable, in 4 pages.
- Summary: **8000–BFFF is a banked window with 6 pages.** RS=1 selects EPROM0's upper 32 KB (RA14 picks the 16 K half). RS=0 selects EPROM1 (RA15:RA14 picks the page).

**OUT2 (IC23, port 80H) bits (p95, read):**

| Bit | Signal | Function |
|---|---|---|
| D0 | RA14 | Bank address bit |
| D1 | RA15 | Bank address bit |
| D2 | RS | ROM select |
| D3 | SMEM | RAM / battery-RAM select |
| D4 | CS1 | Handset chip-select code |
| D5 | CS2 | Handset chip-select code |
| D6 | CLK | Handset serial clock |
| D7 | DP | Handset serial data (radio → handset) |

**RAM (p87–89, read):**
- C000–FFFF: IC8, a 32K×8 SRAM with **16K used**.
- The battery RAM is IC9 (32K×8, supplied from +VG, backed by G1). Only **two 4 KB blocks** of it are used. It overlays **C000–CFFF** when OUT2 **SMEM** selects it; the diagram shows RAM 16k at C000–FFFF with the battery RAM at C000–CFFF.
- The 4 KB block is chosen by **PIO B0 driving the battery RAM's A12**.
- Both blocks hold identical copies plus checksums, so firmware keeps redundant copies and has an error-check / repair routine.
- The SMEM polarity is not stated (not found).

**Battery backing (p89, 99–100, read):**
- The normal RAM IC8 runs from **+VM**. While the radio is off but a supply is still connected, it gets a trickle current through R85/R86/D14. Capacitor C83 on A8N keeps its data through short supply interruptions. So IC8 is also "semi-retained".
- IC9 (+VG, lithium G1) is the truly non-volatile one. It holds device, subscriber and system parameters.
- **RESET blocks the RAM chip selects** (via IC5/2), so an access in progress when RESET arrives cannot corrupt RAM.

**Comparison with our P8E reading.** The manual cannot confirm the P8E reading, because P8E is not found. It does contradict carrying the P8N scheme over directly:
- On P8N, **OUT2 bit 3 is SMEM, not A16**.
- EPROM1 is a 27C512 with only RA14 and RA15.
- With RS=1, **both** 16 K halves of EPROM0's upper 32 K are selectable via RA14, not only the top 16 K.

If the P8E really uses a 27C010 with A16 on bit 3, SMEM must have moved somewhere else on that board. Please check this against the P8E schematic.

**I/O map (p89–90, read):**

| Port | Device |
|---|---|
| 00H | PIO |
| 10H | SIO |
| 20H | 8254 timer |
| 30H | D/A0 |
| 40H | D/A1 |
| 50H | A/D |
| 60H | OUT0 |
| 70H | OUT1 |
| 80H | OUT2 |
| 90H | Watchdog |
| A0H | Modem |

- The 74HC154 decodes A4–A7. A0–A3 are left for the chips' internal registers, so each device mirrors across its 16-byte block (inferred).
- The decoder is enabled only when **IORQ is active and M1 is inactive**, so interrupt acknowledge cycles select no device.

## Q2. Watchdog: read p85–86, 102; timing inferred

- **Circuit (read):** IC4 is a **74HC4040** ripple counter clocked by **Φ2 = 1968.75 Hz**. Software clears it by accessing **I/O 90H** (the CSWD strobe; the manual says "selecting the address", so either IN or OUT works).
- **Grounding LOCAL disables it**: the block diagram shows _LOCAL feeding the counter's reset.
- **Timeout (read):** if it is not cleared, **pin 15** goes high and discharges C1 (the power-on R1/C1 RC). That produces a **RESET**; normal power-on reset is about 30 ms long.
- **Second stage (read):** if the fault persists and the counter is still not cleared after the reset, **pin 1** goes high about 0.5 s later. That drives **OFF** and powers the radio down.
- **Timing (inferred from 4040 pinout):** pin 15 = Q11 and pin 1 = Q12. Q11 rises after 1024 Φ2 clocks = **0.520 s**, and Q12 after 2048 clocks = 1.040 s (0.52 s later), which matches the "≈0.5 s".
- **Reset scope (read):** it resets the whole logic, because RESET goes to the CPU, the RAM decoder, OUT0/OUT1/OUT2 (their /OE or reset pin) and the CCIR decoder.
- **Conflicting text:** p85 says a watchdog event causes an NMI, and that the situation is reported on the WDR line. p86 and the block diagram show a RESET.
- **PA_WDR (PIO A2, read p91):** "WDR; tieto vahtikoiran antamasta RESET-pulssista", i.e. it tells software that the reset came from the watchdog. It is the Q11 level, so after a watchdog reset firmware can read WDR=1 until it clears the counter (inferred).

## Q3. Power on/off: read pp. 85, 97–100, 38–40, 107

- **Switch (read):** the handset slide switch pulls CA-11 **ON/OFF** to 0 V for "on" and to +VR for "off". It is only a logic signal. The same line is on the UK battery connector.
- **Relay (read):** a **bistable (latching) relay RE1** on A8N switches between +VR (car battery) and +VRP (own battery). It is pulsed by Q6/Q7 through C84/C85/C86, with different pulse polarity depending on which supply is present.
- **Switch-off sequence (read):** opening the switch causes an **NMI**. The CPU learns that this is a power-off event from the **PWR line = PIO A3**. The NMI handler saves state and then pulses **PIO B7 = OFF high**, which fires the relay off through Q8/Q7.
- **Hardware fallback (read):** if the CPU never sends OFF, the R100 (270k) / C93 (4.7 µF) RC and the Schmitt NAND IC14/4 turn on Q9 and power off anyway. Our estimate is about 1 s (inferred from τ ≈ 1.27 s).
- **MON, "Master power on" (read p92, p99):** SIO **DTRB** drives MON (PP2 pin 4). Firmware must **pulse** DTRB; each pulse turns on Q4 on P8N and discharges C93. This lets software prevent switch-off, for example during an emergency call.
- **Low voltage (read):** if the supply drops or fails, an NMI is also generated and the handler saves data to RAM. C88/C89 power the logic during the NMI and C83 holds the RAM.
- **Undervoltage reset (read p86):** D2/R2 on IC1/1 pin 1 cause RESET while the voltage is low.
- **Firmware voltage limits (read p69):** alarm at 11.2 V and shutdown at 10.2 V (tests 931/932), measured by the ADC.
- **NMI detail:** the exact NMI circuit (edge vs level, what triggers it) is not found, because the P8N schematic is missing.

## Q4. Interrupts and SIO/PIO pin use: read p85, 91–92, 102

- **Daisy chain (read):** the PIO has higher priority. PIO IEO feeds SIO IEI (block diagram p102). PIO IEI is presumably tied high (inferred).
- **CPU:** Z84C00 PLCC44. The SIO is a **Z84C44** (Z80 SIO, PLCC44); the PIO is a **Z84C20**.

**PIO port A (all inputs):**

| Bit | Signal |
|---|---|
| A0 | **Φ2 1968.75 Hz "clock interrupt"**, the system tick input |
| A1 | _HK (hook) |
| A2 | WDR |
| A3 | PWR |
| A4–A7 | CCIR decoder D0–D3 |

**PIO port B:**

| Bit | Direction | Signal |
|---|---|---|
| B0 | out | Battery-RAM block select (A12) |
| B1 | in | EXIN1 |
| B2 | in | EXIN2 |
| B3 | in | **DCU** (serial data handset → radio) |
| B4 | out | _RXON |
| B5 | in | Timer OUT2 state ("TIMER"). The text says "TMR0 interrupt", read via "pin 36". |
| B6 | out | EXAL (external alarm) |
| B7 | out | OFF |

**SIO channel A:**
- **DCDA** = the combined interrupt ("keskeytyskytkentä", block "KK").
- **CTSA** = **DA** (handset key-data-available).
- Channel A data lines are not used for MBUS.

**SIO channel B = MBUS (9600 baud, one-wire DM bus):**
- TXDB and RXDB carry the data.
- **DCDB** = bus-busy (low while traffic; 3 ms release RC).
- **TxCB/RxCB** = MBUSCLK from the separate divider TMR1.
- **CTSB = PTT**.
- **SYNCB = _LOCAL**.
- **DTRB = MON**.

**Combined interrupt on DCDA (read p92):** three sources pulse DCDA:
1. HK changes in either direction.
2. **8254 counter 0's OUT2**. The manual says "TIMER0 lähtö OUT2", meaning chip IC13 output OUT2, the signalling tick.
3. **FX429 IRQ** goes low.

The ISR checks the sources in this order:
1. It reads HK via PIO A1 and compares with the previous value.
2. It reads PIO B5 to see whether the timer fired.
3. If neither, it concludes the modem caused the interrupt.

After an HK or timer interrupt, the **combining latch must be reset by reading an 8254 register**. So in the emulator the latch clears on an I/O read to 20H–23H (inferred).

- **CCIR decoder (read):** IC25, with its own **560 kHz** resonator X2. Its 4-bit tone code goes to PIO A4–A7 and it is reset by RESET. It has no interrupt of its own. The value 15 means "no tone" (inferred from test 54, p61).
- **Timer OUT0 (read):** OUT0 is LPFCLK to A8N. It is not an interrupt.

## Q5. Hook, PTT and LOCAL: read p38–39, 91–92, 189

- **CA-22 HK (read):** "0" = handset in its holder. A reed switch closes on the holder magnet, so a lifted handset gives 1 at the connector.
- **Hook bit polarity at PIO A1:** the block diagram labels PIO A1 "_HK" (active-low naming). **The polarity after any P8N buffering is not found.** If the line passes straight through, then **lifted = 1, on hook = 0** (inferred).
- **PTT (read):** CA-5; "0" = pressed. It goes to **SIO CTSB**.
- **LOCAL (read):** CA-7, active low. It goes to **SIO SYNCB** and to the watchdog reset/disable. The mode is sampled at power-on (p54), and service mode is left by powering off.
- **EXIN1/EXIN2:** CA-6/CA-24, active low, to PIO B1/B2.
- **DA:** CA-14, "1" = data coming, to CTSA.
- **Other CA pins:** EXAL CA-15, DP CA-16, DCU CA-17, CLK CA-18, DM (MBUS) CA-19, CS1 CA-12, CS2 CA-13.

## Q6. Wait-state generator: not found

- There is no mention of WAIT, WSG or wait states anywhere in the manual.
- The P8N parts list does include 74HC107 dual JK flip-flops (IC17/18), which could form a wait generator. Their function is not documented.
- The P8E is not covered at all.

## Q7. Clocks: read p85–86, 95, 102, 106

- **Crystal (read):** X1 **8.064 MHz ±10 ppm**, trimmed by C5. It drives inverter IC2/1 and divider IC3 (74HC4040).
- **Clocks derived from it (read):**

| Clock | Frequency | Feeds |
|---|---|---|
| Φ0 | **4.032 MHz** | CPU, PIO, SIO, 8254 (CLK0 and CLK1) and FX429 modem |
| Φ1 | **1.008 MHz** | ADC clock, via PP1-13 to A8N |
| Φ2 | **1968.75 Hz** (8.064 MHz / 4096) | PIO A0 tick, watchdog clock, **8254 CLK2** |

- The manual says "ports 0 and 1 divide Φ0, port 2 divides Φ2".
- **SIO baud clock (read):** "TIMER1" IC14 is a **74HC4059 programmable divide-by-N** fed from Φ0. Its jam inputs are hard-wired and it gives MBUSCLK to TxCB/RxCB for 9600 baud.
- **Divisor (not found):** exact 9600 needs /420 in ×1 mode. In ×16 mode the closest is /26, which gives 9692 baud (inferred).
- **P8E CPU clock:** not found.

## Q8. ADC and DAC: read p93, 107, 110–112

- **ADC (read):** IC10 **ADC0809CCV** (8 channels, 8 bits), with CLK = Φ1 1.008 MHz.
  - START and ALE = NOR(/CSA/D, /WR). A write to 50H+n starts a conversion on channel n (A0–A2 = mux address).
  - OE = NOR(/CSA/D, /RD). Reading returns the last conversion result.
  - **EOC is not connected**, so firmware must wait a fixed time.
  - Conversion takes about 64 clocks ≈ **64 µs** (inferred from ADC0809 datasheet: 64 clocks at 1.008 MHz).
  - Reference: +REF = the 5.0 V reference from IC16 REF-02 (inferred from the schematic; the text says the result is proportional to the 5 V reference).
- **ADC channels (read p93 + schematic):**

| Input | Signal | Notes |
|---|---|---|
| IN0 | RSSI | From RP-6; receiver gives 0.5–4.5 V (p150) |
| IN1 | SQ | Squelch info |
| IN2 | +V | Supply measurement; divider below |
| IN3 | TPC | D/A1 output, read back |
| IN4 | FPM | Forward power; "not used" |
| IN5 | RPM | Reflected power; "not used" |
| IN6 | **TP4** | Test point only; the manual says nothing about temperature |
| IN7 | Grounded | Inferred from schematic |

  - **+V divider (read, schematic):** +V → R78 100k → node → R79 47k (parts list 47.5k 1%) → GND, with C79 47 nF. The scale is 0.320, so the ADC code is about V × 16.3 and full scale ≈ 15.6 V (inferred). For example, 13.2 V gives about 215.
- **DACs (read):** IC8 and IC9 are **DAC0832LCJ** used in voltage-switching mode. The 5 V reference (IC16) goes into IOUT1, and the output is taken from the Vref pin. ILE=1 and WR2/XFER are grounded, so writes are transparent.
  - Output is about 5 V × N/256 (inferred).
  - **D/A0 (30H) → RFC** (receiver front-end band tuning). It is buffered by IC17/1 with gain 1+10k/5.6k ≈ **2.8**, running from +9 V.
  - **D/A1 (40H) → TPC** (transmitter power control, 0.5–4.5 V). IC17/2 is a unity-gain follower.

## Q9. Synthesizer S8D: read p120–126, 129, 138

- **PLL (read):** **two Fujitsu MB87006A** chips (IC2 = TX, IC8 = RX). Prescalers are **MB501L, P/P+1 = 128/129**, and the divide ratio is f = (N·128 + A)·fref.
- **Reference (read):** 12.8 MHz TCXO (TCO-909F, ±1 ppm). fref = **12.5 kHz** for 12.5 and 25 kHz channel spacing, or 10 kHz for 20 kHz spacing. R, N and A are shifted in serially and latched on the enable pulse.
- **Serial lines (read):** OUT1 D0 SRE (RX synth enable, active 1), D1 SCE (control register enable), D2 STE (TX synth enable), D3 CLK, D4 SD.
  - Minimum pulse widths: enable ≥1 µs, CLK ≥1 µs, data ≥3 µs.
  - The timing diagrams referenced in the text ("kts. ajoituskuvat") are **not in the PDF**.
  - The MB87006A bit format (control bit, 14-bit R, 7-bit A + 11-bit N) is **not in the manual**; take it from the datasheet.
- **IF and injection (read):** first IF **86.5125 MHz**, **high-side injection** (LO = RX + 86.5125 MHz). Second LO 86.0575 MHz gives a 455 kHz second IF (p150).
  - The TX VCO runs directly on the output frequency; there is no offset.
- **VCO bands (read):** V8DR 486.5125–516.5125 (A band) or 526.5125–556.5125 MHz (B band). V8DT 400–430 (A) or 440–470 MHz (B).
  - The band is fixed in hardware by the resonator strip length, plus an extra 22 pF capacitor for the A band.
  - It is **not** switched by software. The service-mode test 17 "synth range A/B" (p58) only changes the firmware's divider and tuning tables (inferred).
- **Control register (read p124–125, 129):** IC6 is a **74HC4094**, 8 bits named B1..B8 with B8 = MSB.

| Bit | 4094 pin | Function |
|---|---|---|
| B3 | Q3 | Supply to TX PLL IC2 and prescaler IC3 (via Q8) |
| B4 | Q4, IC6/7 | Supply to V8DT, the TX VCO (via Q6/Q7) |
| B5–B8 | IC6/14,13,12,11 | 4-bit **deviation correction attenuator** (IC7 74HC4066 switches R33–36 in parallel with R37) |

  - B1 and B2 are not described.
  - Deviation code: B5 is the LSB. 0000 = smallest deviation, counting up to the largest. The factory test sets B5..B8 = 1,1,1,0.
  - Firmware uses 42 deviation-correction bands across the range (p59).
- **Lock detect (read):** MB87006 pin 7 → Q4 → VT connector → transmitter. If the PLL is **unlocked, TX is inhibited** in hardware.
  - The lock signal is not returned to the CPU (inferred: no such input is listed).
  - The TX power-inhibit "RS" line on VT-1 comes from this path.

## Q10. A8N audio board: read p94, 100–101, 107

- **OUT0 (IC4 74HC374, 60H):** it is a 3-state latch whose **/OE = RESET**, so its outputs float during reset. OUT1 is built the same way.

| Bit | Signal | Function |
|---|---|---|
| D0–D2 | A, B, C | Select input of IC7 74HC4051 (8-step loudspeaker volume, resistor ladder) |
| D3 | INH | 4051 inhibit = loudspeaker mute |
| D4 | **_MUTE** | Active low: RX audio switch IC3/3 opens (used during signalling reception) |
| D5 | CCIRC | Switch IC3/1 routes "CCIROUT+MT" (8254 OUT1) into the TX programmable filter / modulator (CCIR tones) |
| D6 | MTC | Switch IC3/2 routes the same OUT1 square wave into the earpiece/loudspeaker path as marker tones, shaped by R50/C27 and R51/C28 |
| D7 | MICM | Microphone mute via Q4 |

- **OUT1 (IC5, 70H):**

| Bit | Signal |
|---|---|
| D0 | SRE |
| D1 | SCE |
| D2 | STE |
| D3 | CLK |
| D4 | SD |
| D5 | RAS (unused) |
| D6 | TPS (unused) |
| D7 | TXON |

  - D7 reaches the transmitter as **_TXON** through two NOR gates (74HC02). TP-3 "0" = transmitter on, so **TX is keyed when D7 = 0** (inferred from the gates).
- **8254 counter 1, OUT1 (read):** it generates CCIR tones, test tones (300 Hz, 1 kHz, 3 kHz) and the pilot, plus marker tones (300, 500, 1000, 2000 and 3000 Hz, test 51). It reaches the audio path through IC3/1 (CCIRC) and IC3/2 (MTC) as described in the OUT0 table.
- **8254 counter 0, OUT0 = LPFCLK (read):** level-shifted to 9 V by Q5, it clocks the **MF6CWM-100** switched-capacitor 6th-order low-pass filter IC6, with **fc = fclk/100**.
  - With 12.5 kHz spacing, fc is 2.91 kHz for FFSK and speech (about 291 kHz clock, so divisor ≈ 14 → 288 kHz, inferred). With 25 kHz spacing it is 3.36 kHz (divisor 12 = 336 kHz).
  - During CCIR transmission, firmware **changes the LPF clock to follow each tone**.
  - All TX audio (speech, FFSK and CCIR) passes through this filter. R55 sets the maximum deviation.
- **FFSK modem (read p96):** IC22 is an **FX429J** (1200 baud, 1200/1800 Hz), clocked at 4.032 MHz and mapped at I/O A0H. FFSKIN comes from the RX audio (IC2/1) and FFSKOUT goes to the TX filter.
- **Squelch:** it is implemented in software from the RSSI/SQ readings. The open/close thresholds are −114/−118 dBm (p69).

## Q11. Firmware and protocol: read p54–72, 181–187

**System:**
- The radio is an **MPT1327-style trunked set** for the Finnish **Autonet** / **Actionet** networks. The handset chapter cites **MPT 1343**.
- FFSK 1200 baud is used for trunking signalling and CCIR selective calling for tone signalling.
- The manual does not mention "ARTS" in the text. It appears only in the drawing title "CU53 ... ARTS 90" (p209).
- The p70–72 table lists parameters 700–742, 800+ and 900 with defaults and limits: NC1/NC2/NX1/NX2/NZ1/NZ2 sample and error limits for DCC/TSCC, FPP, timers TC/TD/TJ/TW/TN/TA, operator code, LAB bit and others.

**Service ("LOCAL") mode:** enter it by powering on with CA-7 grounded. You type a 2-digit test number followed by ENT on the handset, and an automatic tester can inject the same key codes. Tests by group:

| Tests | Function |
|---|---|
| 10–19 | Channels, spacing (151/153), simplex/duplex (16), synth range (17), C/D band (18), EPROM default tables (19) |
| 2x | TX power (5 levels) and deviation correction (21) |
| 3x | Squelch |
| 4x | Volume, loudspeaker, microphone |
| 50 | CCIR transmit; tone table 0=1981, 1=1124, 2=1197, 3=1275, 4=1358, 5=1446, 6=1540, 7=1640, 8=1747, 9=1860, A=2400, B=930, C=2247, D=991, E=2110 Hz |
| 51 | Marker tones |
| 54 | CCIR receive (shows 15 when there is no tone) |
| 55 | Modem transmit of 0101/0000/1111 patterns |
| 60–64 | D/A write (62), A/D read (63), **arbitrary OUT (64XXXYYY writes port XXX)** |
| 70 | Password + STO opens system-parameter programming |
| 001–250 | Channel table |
| 90–95 | Save tuning values to NV memory |

**Channel numbering:** frequency = 400 MHz + n × 12.5 kHz (n = 0000–5600). Autonet uses TX 3200–3400 (440.0–442.5 MHz) and RX 3720–3920 (446.5–449.0 MHz), a 6.5 MHz duplex split (p24).

**Error codes (p185):**
- Err 4: in-call parameters lost.
- Err 5: tuning parameters lost.
- Err 6: own ID or channel table lost; the radio locks up.
- Err 8: bad group number.

These errors are raised from the battery-RAM checksums.

## Other points for the emulator

**Handset CU53AN (read p187–188, 196–200):**
- The link is synchronous serial. The radio drives CLK (OUT2 D6) and sends on DP (OUT2 D7); the handset sends on **DCU**, read at PIO B3.
- CS2:CS1 (OUT2 D5:D4) is decoded by a HEF4555:

| CS2:CS1 | Select | Action |
|---|---|---|
| 00 | CS/KEYPAD | Parallel-load the 74C923 key code into the shift registers |
| 01 | CS/LATCH | Shift registers → HEF40373 LED/backlight latch |
| 10 | CS/LCD1 | Serial data to PCF2111 IC8 |
| 11 | CS/LCD2 | Serial data to PCF2111 IC7 |

- **Key/LED transfer:** the shift registers are 2 × HEF4035, 8 bits. Transfers happen while CS/LCD1 or CS/LCD2 is selected, because the LCD drivers ignore bursts shorter than 35 bits.
- **Keypad:** the 74C923 raises **DA** (CTSA) when a key is pressed.
- **Key byte contents:** the key byte also carries ambient-light (LDR) and display-type bits. Firmware polls the light level every 1 s when no key is pressed.
- **LEDs:** latch outputs Q1, Q2 and Q3 switch the keypad light, LED brightness and display light.

**Other hardware:**
- MBUS (DM, CA-19) is a one-wire open-collector 9600-baud bus on SIO channel B.
- The PIO A0 **1968.75 Hz tick** is probably the main timebase (interrupt on A0 edges), and the 8254 counter 2 (clocked by Φ2) provides signalling timing through the DCDA combined interrupt.
- OUT0/OUT1 (/OE = RESET) and OUT2 (RESET input) float or clear during reset; the resulting default states are not documented.
- Both OUT0/OUT1 latches and the ADC/DACs are on A8N, reached via PP1: A0–A2, D0–D7, /WR, /RD, Φ1, /CSD/A0, /CSD/A1, /CSA/D, /CSO0, /CSO1, RESET.
