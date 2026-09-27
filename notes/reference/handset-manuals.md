> Provenance: written 2026-09-28 by a research subagent from the firmware source
> (line numbers `Lnnnn` = unmodified `reference/r58.asm.als`) or the scanned manuals.
> Items the emulator tests exercise are confirmed; everything else is as-read.
> Corrections found since: see notes/hardware.md.

# R58 handsets CU53AN and CU58AF: hardware seen from the radio logic board

Sources:
- **[53/pN]** = `Rx58-CU53AN-handset-service-manual-OH3TR-secure.pdf`, PDF page N (27 pages)
- **[58/pN]** = `Rx58-CU58AF-alpha-handset-service-manual-OH3TR-secure.pdf`, PDF page N (42 pages)

How facts are marked:
- **READ**: printed in the manual and legible.
- **TRACED**: I followed the wires on the scanned schematic at 600 dpi. High confidence, but not printed as text.
- **INFERRED**: my own reasoning.
- **DATASHEET**: taken from general knowledge of the part, not from these manuals. Check it against the real datasheet.

---

## PART 1: CU53AN (numeric handset: CU53AN/AS, modules DM32M, LM32M, EA32M, Q8L)

### 1.1 Pages
| PDF page | Content |
|---|---|
| 2 | Associated documentation list and functional blocks |
| 3-6 | User description: buttons, indicator lights, illumination, display symbols A-I, info-display messages |
| 6-8 | Functional description: serial communication, CS table, keyboard scanning, indicator control, display control, voltage regulation, switches, audio |
| 10 | Handset drawing 4X-1439 (key positions) |
| 11 | LCD glass drawing 4X-185 |
| 12 | Block diagram 3A-1159 |
| 13 | Full circuit diagram 2B-429 (CU53AN/AS), the main source |
| 14-15, 18-19, 21, 23 | PCB layouts |
| 16, 20, 22 | Parts lists DM32M, LM32M, EA32M |
| 24-26 | Mechanics and parts list |
| 27 | Wiring |

### 1.2 IC list [53/p16, p20, p22, p13]
| Ref | Part | Function | Module |
|---|---|---|---|
| IC1 | HEF4555BT | Dual 1-of-4 decoder. IC1/1 is the CS decoder; IC1/2 is unused (inputs tied) | LM32M |
| IC2 | MM74C923 | 20-key keypad encoder (5x4 matrix), 3-state outputs | LM32M |
| IC3 | LM2931AZ-5.0 | 5 V regulator (VCC) | LM32M |
| IC4, IC5 | HEF4035BT | 4-bit parallel/serial shift registers, cascaded to 8 bits | LM32M |
| IC6 | HEF40373BT | 8-bit transparent latch (indicator and illumination) | LM32M |
| IC7, IC8 | PCF2111T (SOT-158) | LCD duplex drivers, 2 backplanes x 32 segments each | DM32M |
| IC9 | HEF4093BT | Quad 2-input Schmitt NAND (clock buffer, encoder OE gating, LDR squaring) | LM32M |
| IC10 | TA7504P | Microphone amplifier (the p13 schematic note says "IC10: TA 7504 or TL071P") | LM32M |
| IC15 | TL071IP | Earphone amplifier | EA32M |
| Q1, Q2, Q3 | BCW32 | Q1: keypad light driver. Q2: indicator bright/dim. Q3: display lamp driver | DM32M |
| Q1 (LM) | BCW32 | 9 V supply follower (VDD) with D22 9V1 zener | LM32M |
| R1 | LDR 10k/5M, MPB2-4H48 | Ambient light sensor | DM32M |
| DS1 | LCD "RTA Custom 16 characters" [53/p24 item 21] | | DM32M |
| D11 | HLMP-2400A yellow | CALL | DM32M |
| D12 | HLMP-2300A red | ROAM | DM32M |
| D13, D14 | HLMP-2500A green | SERV, ON | DM32M |
| D20-D23 | HLMP-1540 green | Keypad illumination | DM32M |
| LA1, LA2 | 5 V/115 mA lamps | Display illumination | DM32M |
| S1 | Reed relay | Hook | DM32M |
| S2 | Slide switch | ON/OFF | DM32M |
| S4, S5 | Switches | + and − (volume) | DM32M |
| S6 | Switch | Additional function (shift) key, INFERRED | |
| S7 | Switch | PTT (labelled "PTTB") | |

There is no DTMF generator and no I2C in the CU53AN.

### 1.3 Handset-to-radio connector C4 (DB25 male through filter Q8L) [53/p13 TRACED; labels READ]
| Pin | Signal | Goes to (in the handset) |
|---|---|---|
| 1, 2 | GND | Digital ground |
| 3 | MIC | Microphone amplifier IC10 output |
| 4 | MIC GND | |
| 5 | /PTT | PTT switch S7, pulled up by R17 10k to VDD. Grounded = transmit [53/p7] |
| 6 | Illegible label (looks like a second "PTT" with overbar) | Tied to pin 8 GND A on the schematic |
| 7 | nc | |
| 8 | GND A | Audio ground |
| 9 | ERP | Earphone audio from the radio, into IC15 through volume pot R3 |
| 10 | nc | |
| 11 | /ON/OFF | Slide switch S2. A logic signal only; it does not switch the supply [53/p7] |
| 12 | CS1 | R11 10k / C1 into HEF4555 A0 (pin 2) |
| 13 | CS2 | R12 10k / C2 into HEF4555 A1 (pin 3) |
| 14 | DA | 74C923 DA output (pin 13) directly, with C20 1n. Also gates the encoder OE (see 1.4) |
| 15 | nc | |
| 16 | DP (data radio → handset) | IC5 serial input J/K̄ (pins 3, 4), and PCF2111 DATA (pin 39) of both drivers through R23 100k |
| 17 | DCU (data handset → radio) | IC4 pin 13, the last shift stage. The manual says "pin 13 of IC4" [53/p7] |
| 18 | CLK | R16 10k / C6 10p into IC9/1 (inverter), then IC9/3 (inverter), giving a buffered non-inverted CLK. That CLK drives IC4/IC5 CLK (pin 6) and, via R24 100k, PCF2111 CLB (pin 1) of both drivers |
| 19-21 | nc | |
| 22 | /HK | Reed switch S1 to ground (closed = in holder, per [53/p7]) |
| 23, 24 | nc | |
| 25 | +VB (13.2 V) | Into regulator IC3 (5 V VCC) and Q1/D22 (9 V VDD). LEDs and lamps run from VB |

The radio reads PTT, HK, ON/OFF and DA directly as port pins. DA is a direct copy of the 74C923 "data available" output.

### 1.4 Serial protocol [53/p6-7 READ; details TRACED on p13]

**Chip select.** IC1/1 is a HEF4555 with E grounded. Its outputs are active HIGH, and exactly one is always high.

| CS2 | CS1 | Output (4555 pin) | Action [53/p6 table] |
|---|---|---|---|
| 0 | 0 | CS/KEYPAD (O0, pin 4) | Parallel keypad data from IC2 into shift register IC4/IC5 |
| 0 | 1 | CS/LATCH (O1, pin 5) | Shift register IC4/IC5 contents into latch IC6 (drives 40373 LE, pin 11) |
| 1 | 0 | CS/LCD1 (O2, pin 6) | Serial DP data into display driver **IC8** |
| 1 | 1 | CS/LCD2 (O3, pin 7) | Serial DP data into display driver **IC7** |

- The CS lines reach the PCF2111 DLEN pins (pin 40) through R22 and R21 (100k each).
- The manual says [53/p6]: keypad and indicator transfers happen on DP/DCU clocked by CLK. During those transfers one of CS/LCD1 or CS/LCD2 will be high. This does no harm because the display drivers do not accept messages shorter than 35 bits.
- INFERRED: the firmware parks CS at an LCD code (1x) while it shifts the 8 keypad/latch bits. Parking at 01 would make the transparent latch follow the shifting data.

**Shift register (TRACED).**
- IC5 and IC4 (HEF4035) are chained: DP → IC5 J/K̄ → IC5 stages 0-3 → IC5 pin 13 → IC4 J/K̄ → IC4 stages 4-7 → IC4 pin 13 = DCU.
- The P/S̄ pins (pin 7) of both chips are tied together and driven by CS/KEYPAD. High means parallel load, low means serial shift. The manual says "When CS/KEYPAD has gone back low, the shift register again operates in serial mode" [53/p6-7].
- T/C̄ (pin 2) is tied to VCC, so outputs are true. Pin 5 (MR, drawn as "OE") goes to ground through R25/R26 100k and never resets.
- The 4035 is positive-edge clocked, and parallel load is synchronous with the clock (DATASHEET). So a keypad read is: set CS=00, give at least one CLK pulse (load), leave CS≠00, then clock 8 bits.
- Stage numbering used below: stage 0 = first IC5 stage (next to DP), stage 7 = last IC4 stage (drives DCU). Output pins per chip: stage 0/4 = pin 1, stage 1/5 = pin 15, stage 2/6 = pin 14, stage 3/7 = pin 13. Parallel inputs are pins 9, 10, 11, 12 for the same stages.

**Parallel-load word read back on DCU (TRACED).** R4 is an 8x100k pull-up network to VCC.

| Stage | Source | Meaning |
|---|---|---|
| 7 | IC9/4 output (Schmitt NAND wired as inverter; input from the LDR divider) | Light level. INFERRED: 0 = bright, 1 = dark (same polarity as the CU58AF LDR bit) |
| 6 | 74C923 D4 (E, pin 15) | Keycode MSB |
| 5 | D3 (pin 16) | |
| 4 | D2 (pin 17) | |
| 3 | D1 (pin 18) | |
| 2 | D0 (A, pin 19) | Keycode LSB |
| 1 | Pull-up only | "Display type" bit = 1 |
| 0 | Pull-up only | "Display type" bit = 1 |

The manual [53/p7] says the lighting level and display type are read together with the keycode. The lighting level is read at one-second intervals when the keyboard is not being used.

- The 74C923 OE̅ (pin 14) is driven by IC9/2 = NAND(DA, CS/KEYPAD). The encoder therefore drives D0-D4 only while a key is available and CS/KEYPAD is high. Otherwise the outputs float and R4 pulls them to 1, so no key reads as 11111.
- Clocking out: after the load, DCU already shows stage 7. Each CLK rising edge shifts the chain toward stage 7 and takes the DP bit into stage 0. The radio therefore receives MSB first: `b7 = LDR, b6..b2 = keycode D4..D0, b1 = 1, b0 = 1`. Equivalently, byte = (LDR<<7) | (key<<2) | 0b11. This is INFERRED from the traced wiring plus the datasheet. Whether the firmware samples before or after each edge needs checking against the code.
- IC9/1 and IC9/3 are two inverters in series, so CLK polarity at the 4035 equals CLK at the connector.

**Indicator/illumination latch IC6 (HEF40373) (TRACED).**
- Inputs: D0-D3 come from IC5 stages 0-3; D4-D7 come from IC4 stages 4-7.
- LE (pin 11) = CS/LATCH, which is transparent while high. OE̅ (pin 1) is grounded.
- To write it: shift 8 bits on DP (the first bit shifted ends up in stage 7), then pulse CS=01 [53/p7 "processor generates CS/LATCH pulse"]. All outputs are active HIGH.

| Latch output | Pin | Drives | Meaning |
|---|---|---|---|
| Q0 | 2 | R34 4k7 → Q2 base | Indicator LEDs bright. When Q2 conducts it bypasses diode pair D4; otherwise the LEDs are dimmed by the D4 drop [53/p7] |
| Q1 | 5 | R33 820 → Q3 base | Display lamps LA1/LA2 (display light) |
| Q2 | 6 | R31 100 → D14 | ON LED (green) |
| Q3 | 9 | R30 68 → D13 | SERV LED (green) |
| Q4 | 12 | R32 8k2 → Q1 base | Keypad illumination D20-D23 |
| Q5 | 15 | R29 56 → D12 | ROAM LED (red HLMP-2300A) |
| Q6 | 16 | R28 56 → D11 | CALL LED (yellow HLMP-2400A) |
| Q7 | 19 | Not connected | |

With MSB-first transmission, the latch byte is: `b7 = nc, b6 = CALL, b5 = ROAM, b4 = keypad light, b3 = SERV, b2 = ON, b1 = display light, b0 = indicator bright` (INFERRED ordering). Manual [53/p7]: Q3 switches the display light and Q1 switches the keypad light. The labels ON/SERV/ROAM/CALL are READ next to the LED boxes on p13.

**Display drivers (PCF2111 x2).**
- IC8 is selected by CS/LCD1 and IC7 by CS/LCD2 [53/p6].
- The display data arrives over DP "in four parts" [53/p7], i.e. 2 drivers x 2 backplanes. The drivers check each message, and only an acceptable message changes the display.
- Neither driver accepts messages shorter than 35 bits [53/p6].
- BP1/BP2 (pins 38/37) of the two drivers are tied together. IC7 has the RC oscillator (R35 1M, C21 680p); IC8's OSC pin also connects (INFERRED: one master, one slave).
- LCD supply is a temperature-compensated 4 V from R27 + D1-D3 (BAW99) [53/p7].
- DATASHEET, verify: a PCF2111 message is DLEN high, then a leading 0, then 32 segment bits, then 1 backplane-select bit (clocked on CLB rising edges), then DLEN low. A further CLB pulse then loads the latches. About 36 clocks in all, which fits "not shorter than 35 bits".

**Keypad scanning [53/p6-7 READ].**
- The 74C923 pulses X1-X4 (open-collector) and senses Y1-Y5 (internal pull-ups).
- C13 (100n) sets the scan frequency. C46 (1µ) sets the debounce ("repeat-blocking") delay. DATASHEET: roughly 10 ms of debounce per µF.
- DA goes high after a key is detected and debounced, and stays high while the key is held (DATASHEET).

### 1.5 Keypad matrix CU53AN [53/p13 TRACED at 600 dpi; key positions from p10]
Encoder code = 4·(Y−1) + (X−1) (DATASHEET 74C923; it matches most of the printed codes).

| | X4 (pin 8) | X3 (pin 9) | X2 (pin 11) | X1 (pin 12) |
|---|---|---|---|---|
| **Y1** (pin 1) | (3) CL | (2) "1" | (1) "2" | (0) "3" |
| **Y2** (pin 2) | (7) STO | (6) "4" | (5) "5" | (4) "6" |
| **Y3** (pin 3) | (11) RCL | (10) "7" | (9) "8" | (8) "9" |
| **Y4** (pin 4) | (15) ENT | (14) * | (13, printed "12") "0" | (12, printed "11") # |
| **Y5** (pin 5) | (19) S4 "+" | (18) S5 "−" | — | (16) S6 (shift / additional function) |

- The numbers in parentheses are READ on the schematic.
- Labels "1"-"9", "0", "+", "−" and "S6" are READ.
- CL/STO/RCL/ENT/*/# are INFERRED: those switches have no printed label, and the assignment follows the physical 4x4 layout on p10 (CL 1 2 3 / STO 4 5 6 / RCL 7 8 9 / ENT * 0 #).
- In row Y4 the schematic prints (15), (14), (12), (11). By the chip's truth table these must be 15, 14, 13, 12; the print looks like a drafting error.
- Codes 17 (Y5·X2) and 19 are the only other Y5 positions. 17 is not used.
- S4/S5 are the side +/− buttons (item 9 on p10). S6 is probably the long "additional function" key (item 10 on p10). That is INFERRED; the parts list places S4 and S5 on DM32M, and S6 is not in the DM list.

### 1.6 LCD glass CU53AN [53/p11, p3-5]
- **Top row**, left to right:
  - Icon A: two car icons stacked (one car = arrived call; two cars = group call)
  - Icon B: telephone ("call back")
  - Info display E: 6 seven-segment digits, with a colon after digit 2 and after digit 4 (drawn "88:88:88")
  - Icon C: key (additional-function active, shown for 5 s)
  - Icon D: open book (status message in memory)
  - Icon H: handset (broadcast call)
  - Icon I: asterisk (audio muting)
  - Icon G: tower (rebroadcast call)
- Info-display messages: L1…L8 (speaker volume), PH/PL (power high/low), bAt, SOS, Err 4/5/6/8 [53/p5].
- **Bottom row F**: 10 seven-segment digits, with a colon between digits 2 and 3. If a number has more than 10 figures, only the last 10 are shown [53/p5].
- The ENT key appears on the display as "_" [53/p3].
- At switch-on all characters appear for an instant [53/p3].
- Segment count: 16·7 + 3 colons + 8 icons ≈ 123, which fits the 128 outputs of 2 x PCF2111.
- **The PCF2111-pin-to-segment mapping is NOT shown.** The schematic draws DS1 with 32-line buses only [53/p13].

### 1.7 Illumination, LDR, timing, power [53/p4, p7, p13]
- The keypad and display are lit internally. The keypad lighting and indicator lights are dimmed when ambient light is dim, as sensed by photoresistor R1.
- Display lighting turns on when a button is pressed and turns off after 10 s if there are no digits in the display [53/p4].
- Pressing the additional-function key briefly lights the display in dim conditions [53/p3]. Holding it while switching on raises TX power (portable use).
- The LDR is read at 1 s intervals when the keyboard is idle [53/p7].
- Supplies: 5 V VCC from IC3 (LM2931) for the logic; 4 V for the LCD; 9 V VDD from Q1/D22 for the audio. All derive from VB = 13.2 V.
- The CU53AN has no reset line. Its state is set purely by the radio's serial writes.

---

## PART 2: CU58AF (alphanumeric, I2C; modules DM58F display module, HS58F handset module, KC58 cord/holder)

### 2.1 Pages
| PDF page | Content |
|---|---|
| 2 | General: 17-character alphanumeric LCD, module list |
| 3-5 | Control part: I2C devices and pin tables (the key pages) |
| 6 | HS58F audio description |
| 7-8 | DM58F: illumination, keyboard, LEDs, ON/OFF, display control (PCF8576 protocol) |
| 9, 10 | Block diagrams (two versions) |
| 11-12 | Mechanics |
| 15-16 | HS58 PCB layout |
| 17-19 | HS58F BOM |
| 20-21 | DM58 layout |
| 22-23 | DM58F BOM |
| 30 | CT58G/CT58S D-connector wiring diagram |

**There is no component-level schematic in this PDF**, only block diagrams. Everything below comes from the text, the BOMs and the block diagrams.

### 2.2 IC list [58/p18, p22-23]
| Ref | Part | Function | Module |
|---|---|---|---|
| IC100 = D100 | PCF8574T | I/O: COL0-2, POWER, LDR. Interrupt source | DM58F |
| IC110 = D110 | PCF8574T | I/O: keyboard ROW0-6 | DM58F |
| IC130 = D130 | PCF8574T | I/O: LEDs, keyboard and LCD backlight | DM58F |
| IC270, IC280 | PCF8576T (VSO56) | LCD drivers, 1:4 multiplex | DM58F |
| IC140 = D140 | HEF4093BT | Schmitt NAND; LDR interrupt shaping [58/p8] | DM58F |
| IC190 = N190 | LM2951ACM | 5 V regulator (from 12 V) | DM58F |
| IC120 = D120 | **PCF8574AT** | Audio control (its address is in the 8574A range) | HS58F |
| IC150 = D150 | PCF8574T | SPEAKER, TANGENT, HOOKIND | HS58F |
| IC370 | **PCD3312CT** | DTMF tone generator (I2C), crystal X370 3.579 MHz | HS58F |
| IC160, IC220 | 74HC4066 | Analog switches (MICCTRL, DTMFCTRL, HS_AUDIO_CTRL, EARPH/SPKR) | HS58F |
| IC200 | HEF4051BT | 1-of-8 analog mux, earphone gain (VOLCTRL1-3) | HS58F |
| IC250 = N250 | TDA2822 | Bridge loudspeaker amplifier | HS58F |
| IC170, IC230 | TL072 | Mic amp N170, earphone amp N230 | HS58F |
| IC180 = N180 | LM2951ACM | 5 V regulator | HS58F |
| D291 | LED panel BU4470, 52x25 mm green | LCD backlight | DM58F |
| DS20 | LCD LTA5N7011A [58/p12] | | |
| D311-D316 | Green LEDs | Keypad light | DM58F |
| D352, D356 | HLMP-2500 green | Indicators | DM58F |
| D354, D368 | HLMP-2300A red | Indicators | DM58F |
| R145 | LDR 10k/5M MPB2-4H48 | | DM58F |
| S140 | Reed relay | HOOK | HS58F |
| S313 | Push button | PTT/tangent or speaker (INFERRED) | HS58F |
| S310, S311, S312 | Push buttons | S310/S311 = the +/− side keys; S312 = power? (INFERRED from layout, p20-21) | DM58F |
| S331 | Slide switch | | DM58F |
| S314-S329 | Keymat switches | | DM58F |

The keymat is "3X4X4 SILICONRUBBER" [58/p12]. A separate "ALPHA KEY" part also exists [58/p12].

### 2.3 Connector (same DB25 position as the CU53AN; signals re-purposed) [58/p9 block-diagram labels, p30 wiring READ]
The block diagram names the handset-side connector "CA", Q8L 305588. Its pin labels, compared with the holder D-connector labels on p30:

| DB25 pin | p30 name | CU58AF use (p9) |
|---|---|---|
| 1, 2 | GND | GND |
| 3 | MIC | XMIC (mic out) |
| 4 | GND | MIC GND |
| 5 | PTT | Not drawn on the p9 CA list. INFERRED: PTT goes via I2C (TANGENT) instead |
| 6 | EXIN1 | |
| 8 | GND | EARGND |
| 9 | EAP (=ERP) | XAF / ERP audio into the handset |
| 10 | GND | |
| 11 | −ON/OFF | PW (power switch line; ON/OFF gives a logic signal [58/p8]) |
| 12, 13 | CS1, CS2 | Not used by the CU58AF (not on the CA list) |
| **14** | **DA** | **INT**: PCF8574 interrupt output (active-low open-drain per DATASHEET) |
| 15 | EXAL | |
| 16 | DP | Not used by the CU58AF |
| **17** | **DCU** | **SDA** |
| **18** | **CLK** | **SCL** ("clock line CLK … from radio part" [58/p3]) |
| 19 | DM | |
| 20, 21 | +VR | |
| 22 | HK | HK |
| 23 | LSP | |
| 24 | EXIN2 | |
| 25 | +VB | +VB (12 V) |

The holder module HD1 (10-pin) carries [58/p30 READ]:
- 1 −ON/OFF (grey)
- 2 CLK (red)
- 3 DCU (blue)
- 7 +VB (brown/brown)
- 8 GND (white/white)
- 10 DA (yellow)
- 4, 5, 6, 9 unlabeled

So the radio's DCU pin becomes a bidirectional I2C SDA, CLK becomes SCL, and DA becomes the interrupt line.

### 2.4 I2C devices [58/p3-5, p7-8 READ]
General rules [58/p3]:
- Write: `S [addr7] 0 A [data 8 bits] …`. Read: `S [addr7] 1 A [data] A … 1 P`.
- Pin direction: write 1 = input (quasi-bidirectional), 0 = output low.
- The outputs are open-collector. A pin driven "0" while tied directly to +5 V will be damaged.

Pin-to-bit mapping (PCF8574 pin → bit): pin 4 = P0, 5 = P1, 6 = P2, 7 = P3, 9 = P4, 10 = P5, 11 = P6, 12 = P7 (DATASHEET).

**D100 (DM58F) + D150 (HS58F), shared address 0100000 (7-bit 0x20; write 0x40, read 0x41).**
The manual says D150 is at the same address as D100 and "pins 10-12 used in D150", while D150's pins 4-9 say "look D100". INFERRED: the two chips behave as one logical port. D100 supplies P0-P4 and D150 supplies P5-P7; each leaves the other's bits high. Initialised state 11111111. Both can generate an interrupt. Small capacitors on each pin guard against RF-induced interrupts.

| Bit (pin) | Name | Active | Meaning |
|---|---|---|---|
| P0 (4) | COL0 | 0 | Keyboard column with pressed key (generates interrupt) |
| P1 (5) | COL1 | 0 | |
| P2 (6) | COL2 | 0 | |
| P3 (7) | POWER | 1 | Power switch pushed |
| P4 (9) | LDR | 0 | 0 in bright light. D140 makes an interrupt through D100 [58/p8] |
| P5 (10) | SPEAKER (D150) | 0 | Speaker button pressed |
| P6 (11) | TANGENT (D150) | 0 | PTT pressed (generates interrupt) [58/p6] |
| P7 (12) | HOOKIND (D150) | 1 | Handset out of holder (off hook); reed switch, interrupt [58/p6] |

**D110 (DM58F), 0100110 (0x26; 0x4C/0x4D).** Keyboard rows, normally outputs at 0. Initialised state "0000000x".

| Bit (pin) | Name |
|---|---|
| P0 (4) | ROW0 |
| P1 (5) | ROW1 |
| P2 (6) | ROW2 |
| P3 (7) | ROW3 |
| P4 (9) | ROW4 |
| P5 (10) | ROW5 |
| P6 (11) | Not listed (the "x") |
| P7 (12) | ROW6 |

**D120 = PCF8574A (HS58F), 0111110 (0x3E; 0x7C/0x7D).** All audio control. When the handset is switched on, the software must immediately send "10000000".

| Bit (pin) | Name | Active | Meaning |
|---|---|---|---|
| P0 (4) | SPKR_CTRL | **0** | Loudspeaker amp on; XAF connected to speaker amp |
| P1 (5) | DTMFCTRL | 1 | DTMF generator connected to mic amp |
| P2 (6) | HS_AUDIO_CTRL | 1 | ERP and MIC lines connected to the radio |
| P3 (7) | MICCTRL | 1 | Microphone connected to mic amp |
| P4 (9) | EARPH_CTRL | 1 | Earphone amp connected to the ERP line |
| P5 (10) | VOLCTRL1 | — | Volume LSB (0-7, selects a feedback resistor through the HEF4051) |
| P6 (11) | VOLCTRL2 | — | |
| P7 (12) | VOLCTRL3 | — | Volume MSB |

Read literally as P7..P0, the init value 10000000 = VOLCTRL3 = 1 with all others 0, i.e. speaker enabled (active 0), volume 4. The manual also writes "D210/6" once [58/p6]; that is a typo for D120/6.

**D130 (DM58F), 0100010 (0x22; 0x44/0x45).** All pins are always outputs. Initialised state 00000000. All illumination control.

| Bit (pin) | Name | Active | Meaning |
|---|---|---|---|
| P0 (4) | LED0 | 1 | Green SERV |
| P1 (5) | LED1 | 1 | Red ROAM |
| P2 (6) | LED2 | 1 | Green ON |
| P3 (7) | LED3 | 1 | Red CALL |
| P4 (9) | — | | Not listed |
| P5 (10) | KBRLIGHT | 1 | Keyboard illumination |
| P6 (11) | LCDLIGHT | 1 | Display illumination |
| P7 (12) | — | | Not listed |

"LED is ON when pin is in state 1" [58/p8].

**PCF8576 x2 (IC270/IC280), address byte 01110000 (7-bit 0x38; write 0x70).**
Hardware subaddresses A2A1A0 = 000 and 001. Used in 1:4 multiplex. Format [58/p8]:

`S 01110000 A C xxxxxxx …`

- C = continuation bit: the next byte is also a command.
- Mode set: `C1001100`. DATASHEET decoding: E = 1 (display enabled), B = 1 (1/2 bias), M = 00 (1:4 mux).
- Load data pointer: `C0aaaaaa`, RAM address 0-39.
- Device select: `C1100a2a1a0`, with a2-a0 = 000 or 001.
- Display data follows the command bytes. When driver 1100000 is full, writing continues automatically in driver 1100001 [58/p8].

**Display data: 40 bytes, 2 bytes per character position** [58/p9]:

- Driver 000: `X, B/F, 1, 2, 3, 4, 5, 6, 7, 8`
- Driver 001: `X, 9, 10, 11, 12, 13, 14, 15, 16, 17`
- X = empty, B/F = bar/function position, 1-17 = alphanumeric digits.

Per alphanumeric digit (14-segment):
- Byte 1: `nc f n e a o l m`
- Byte 2: `h g k d b i c nc`

B/F position:
- Byte 1: all nc
- Byte 2: `bar4 bar3 bar2 bar1 phone car alpha exp`

Bit order is presumably MSB first (listed left to right), as the PCF8576 shifts bytes MSB first. DATASHEET: in 1:4 mode each byte covers 2 segment outputs x 4 backplanes.

Glass [58/p2, p8]:
- 17 alphanumeric 14-segment characters
- 4 function icons (phone, car, alpha, exp)
- 4 bars
- The row split is not drawn anywhere in this PDF. The data order hints at 8 + 9 (digits 1-8 on driver 0, 9-17 on driver 1), but that is a guess.

**DTMF generator PCD3312CT (IC370).**
- It is on the I2C bus, per the BOM ("DTMF TONE GENERATOR"), and is routed to the mic amp by DTMFCTRL.
- **The manual gives no address.** DATASHEET, verify: PCD3312 slave address 0100100 (0x24; write 0x48).
- DTMF levels: high group 86 mV RMS, low group 54 mV RMS [58/p6].

### 2.5 Keypad CU58AF [58/p8]
- It is a 7-row x 3-column matrix, so 21 positions. Rows are on D110, columns on D100 P0-P2.
- Scan procedure [58/p8]:
  1. Columns are inputs ('1'); rows are outputs '0'.
  2. A key press generates an interrupt (INT/DA).
  3. After a delay, read the column.
  4. Then set ROW0-6 to inputs ('1') and COL0-2 to outputs ('0'), and read the row.
- **The key-to-row/column assignment is not given anywhere in the PDF.**
- The switch reference designators on the DM58 layout [58/p21] are S314-S329, plus S310 and S311 (side +/−), S312 and S331. The positions are known but the matrix wiring is not.
- The power switch is read separately as POWER (D100 P3). The speaker button and PTT are on D150.

### 2.6 Illumination, LDR, audio, other [58/p2, p6-8]
- LDR R145 → D100/9 (P4), 0 = bright. D140 (HEF4093) shapes it and makes an interrupt through D100 [58/p8].
- Keyboard light is D130/10 (P5); display light is D130/11 (P6).
- Supplies: +12 V (VB) for the amplifiers and the illumination/LED drivers; +5 V from N180 (HS58F) and N190 (DM58F) [58/p2].
- Earphone path: ERP → N230/B first stage. The gain is set by the 1/8 analog mux (VOLCTRL1-3). HS_AUDIO_CTRL = 1 opens the ERP line. EARPH_CTRL = 1 selects the earphone; SPKR_CTRL = 0 selects the speaker. With 1 kHz 150 mV RMS on ERP at maximum volume the earphone gives 100 dB [58/p6].
- Microphone: 1 kHz 94 dB gives 180 mV RMS on MIC, adjusted by R170 [58/p6].
- There is no explicit reset line. The software must write D120 = 10000000 immediately after switch-on [58/p5].
- PCF8574 power-up defaults are all 1s (DATASHEET). This matches the stated "initialized 11111111" for D100/D150. The "0000000x" (D110) and "00000000" (D130) states are what the software writes.
- p10 is a second, slightly different block diagram. It is unlabeled; possibly an earlier revision.

---

## Things not found or illegible
- CU53AN: no PCF2111-pin-to-LCD-segment map. Connector pin 6 label is illegible. Row Y4 keycode labels are misprinted. CL/STO/RCL/ENT/*/# labels are inferred.
- CU58AF: no component-level schematic in the PDF. No keypad matrix map. No DTMF I2C address. No LCD row layout.
