# H8/532 on-chip peripheral register reference (emulator-oriented)
Source: H8/532 Hardware Manual (reference/datasheets/H8_532_hardware.pdf), text extraction. Section numbers in [].
Conventions: all registers 8-bit unless noted; H'xx = hex; "state" = one ø period; ø = fosc/2 [3.7.1]. R/(W) = flag bits: write 0 clears, write 1 ignored.
"Read-then-write-0" rule: a flag is cleared only if the CPU has READ it while it was 1 and then writes 0 (manual wording "CPU reads the bit, then writes 0"). Minimal emulation: write of 0 to bit clears it; write of 1 never sets it (a stricter model tracks "flag was read as 1 since it was set"; manual's BCLR/MOV #0 idiom works either way).

## 0. Bus / memory / mode summary
- Mode 3 = expanded MAXIMUM, no on-chip ROM, 1 MB (pages 0-15), CPU maximum mode (CP/TP page registers valid). Mode 4 same with 32K on-chip ROM. Modes 1,2 = expanded minimum (64K); mode 7 single-chip. MD2..0 latched in MDCR at reset.
- On-chip RAM: 1 KB, H'FB80-H'FF7F (page 0), 16-bit bus. Enabled by RAMCR.RAME (reset 1). If RAME=0 in expanded modes, those addresses go to external bus; in mode 7 they raise address error. [16]
- Register field: H'FF80-H'FFFF, 8-bit bus. Code cannot execute there.
- Vector tables are at the bottom of page 0 (mode 3: external memory; modes 2,4: on-chip ROM).
- Bus timing [3.7]:
  - on-chip RAM/ROM access (byte or word): 2 states (T1,T2), 16-bit bus.
  - on-chip register field (FF80-FFFF): 3 states, 8-bit bus. Word access to register field = two byte accesses (inferred from the BREQ note "word data access to external memory or H'FF80-H'FFFF accesses both upper and lower bytes"; => 6 states for word).
  - external (mode 3, D7-D0 8-bit bus): 3 states (T1,T2,T3) per byte, plus Tw wait states inserted between T2 and T3 per WCR. Word access to external memory = two byte accesses (upper byte first at even address) => 6 states + 2*waits. External bus is 8-bit only (port 3 = D7-D0).
  - Wait states apply to CPU and DTC cycles to external addresses only; not to on-chip modules/RAM/registers.
- Stack in mode 3 external RAM: SP-relative accesses use TP:SP.

## 1. Interrupt controller [4, 5]
### 1.1 Priority registers (reset H'00, bit 7 and bit 3 read 0, not writable)
| Addr | Reg | bits 6-4 | bits 2-0 |
|---|---|---|---|
| FFF0 | IPRA | IRQ0 | IRQ1 |
| FFF1 | IPRB | FRT1 (ICI/OCIA/OCIB/FOVI) | FRT2 |
| FFF2 | IPRC | FRT3 | 8-bit timer (CMIA/CMIB/OVI) |
| FFF3 | IPRD | SCI (ERI/RXI/TXI) | A/D (ADI) |
- 3-bit field = priority level 0..7 (7 highest). Level 0 = permanently masked (accepted only if level > SR I2-I0, and I2-I0 >= 0, so level 0 never accepted). NMI = level 8. Reset leaves all IPR = 0 so everything except NMI masked.
- Priority change takes effect after the NEXT instruction completes (INTC needs 2 ø to decide) [5.3.2].
- WDT interval interrupt has no IPR field of its own: it is IRQ0 (uses IPRA bits 6-4 and IRQ0 vector). WDT watchdog-mode overflow = NMI.
### 1.2 Data transfer enable (DTC, only to know what bypasses CPU), reset H'00
FFF4 DTEA: b4 IRQ0, b0 IRQ1. FFF5 DTEB: b6 OCIB1,b5 OCIA1,b4 ICI1,b2 OCIB2,b1 OCIA2,b0 ICI2. FFF6 DTEC: b6 OCIB3,b5 OCIA3,b4 ICI3,b1 CMIB,b0 CMIA. FFF7 DTED: b6 TXI,b5 RXI,b0 ADI. (No DTE bit for ERI, FOVI, OVI -> always CPU.) If DTE bit=1 the DTC serves the request instead of the CPU and clears the flag (ICF/OCFx/CMFx/ADF; for SCI TDRE cleared by DTC write to TDR, RDRF by DTC read of RDR). Firmware not using the DTC: leave 0.
### 1.3 External interrupts
- NMI: edge-sensed, edge selected by P1CR.NMIEG (bit4): 0 = falling (reset), 1 = rising. Level 8, unconditional (except deferral rules below). Request held until the exception sequence begins, then cleared. Sets I2-I0 = 7 on acceptance. Also raised by WDT overflow when WT/IT=1 and TME=1.
- IRQ0: LEVEL sensed: Low on pin requests it, if P1CR.IRQ0E=1 (bit5). Must be held Low until CPU accepts or request is dropped (manual: "otherwise the request will be ignored"). Also requested by WDT overflow in interval mode. Pin P15 is IRQ0 input when IRQ0E=1 regardless of P15DDR (P15 still readable via P1DR).
- IRQ1: EDGE sensed: high-to-low transition, if P1CR.IRQ1E=1 (bit6). Request latched until the sequence begins (then cleared); a new edge during the handler stays pending until mask permits. (Manual text mistakenly says "An IRQ0 interrupt is requested by..." in the IRQ1 paragraph; it means IRQ1.) Pin P16.
### 1.4 Vector table, MAXIMUM mode (mode 3/4). Each vector = 4 bytes: byte0 ignored, byte1 -> CP, bytes 2-3 -> PC (big-endian). Same as reset: H'0000-0003.
| Source | Max-mode vector addr | Min-mode | Priority at same level (1 = highest) |
|---|---|---|---|
| Reset | 0000-0003 | 0000-0001 | - |
| (reserved) | 0004-0007 | 0002 | |
| Invalid instruction | 0008-000B | 0004 | |
| DIVXU zero divide | 000C-000F | 0006 | |
| TRAP/VS | 0010-0013 | 0008 | |
| reserved | 0014-001F | 000A-000F | |
| Address error | 0020-0023 | 0010 | |
| Trace | 0024-0027 | 0012 | |
| reserved | 0028-002B | 0014 | |
| NMI (pin and WDT watchdog) | 002C-002F | 0016 | 1 (level 8) |
| reserved | 0030-003F | 0018-001F | |
| TRAPA #0..15 | 0040-007F (4*n+0x40) | 0020-003F | |
| IRQ0 (pin and WDT interval) | 0080-0083 | 0040 | 2 |
| IRQ1 | 0084-0087 | 0042 | 3 |
| (0088-008F: internal-vector area, unused/reserved) | 0088-008F | 0044-0047 | |
| FRT1 ICI | 0090-0093 | 0048 | 4a (ICI>OCIA>OCIB>FOVI within module) |
| FRT1 OCIA | 0094-0097 | 004A | |
| FRT1 OCIB | 0098-009B | 004C | |
| FRT1 FOVI | 009C-009F | 004E | |
| FRT2 ICI/OCIA/OCIB/FOVI | 00A0 / 00A4 / 00A8 / 00AC (+3) | 0050/52/54/56 | 5 |
| FRT3 ICI/OCIA/OCIB/FOVI | 00B0 / 00B4 / 00B8 / 00BC (+3) | 0058/5A/5C/5E | 6 |
| 8-bit timer CMIA/CMIB/OVI | 00C0 / 00C4 / 00C8 (+3) | 0060/62/64 | 7 |
| SCI ERI / RXI / TXI | 00D0 / 00D4 / 00D8 (+3) | 0068/6A/6C | 8 (ERI>RXI>TXI) |
| A/D ADI | 00E0-00E3 | 0070 | 9 (lowest) |
- Vectors in 00C-ish gaps (e.g. 00CC-00CF, 00DC-00DF, 00E4-00FF) unused. Table 5-2 lists no vector for min 0066/006E; none exist.
- Tie-break among equal-level sources: order of the table above (NMI > IRQ0 > IRQ1 > FRT1 > FRT2 > FRT3 > 8-bit timer > SCI > A/D); within a module fixed order ICI>OCIA>OCIB>FOVI, CMIA>CMIB>OVI, ERI>RXI>TXI.
- Vector selection for WDT: interval mode -> IRQ0 vector (0080); watchdog mode -> NMI vector (002C). ISR must test WDT TCSR.OVF to tell source. There is NO chip reset on WDT overflow and no RSTCSR on this chip.
### 1.5 Acceptance rules
- Interrupt (non-NMI) accepted at end of instruction iff level(IPR) > SR.I2-I0 (strictly greater) and not in a deferral window. Highest level wins; ties via order above. NMI always (level 8 > any mask incl. 7).
- Request lines are level from flag&enable (e.g. OCFA & OCIEA); remains pending until flag/enable cleared or accepted; module flags are NOT auto-cleared on CPU acceptance (software clears them). (DTC-served requests clear flags automatically.)
- Sequence (CPU): push PC (next instruction address) then CP then SR, clear SR.T, set SR.I2-I0 = level of accepted interrupt (NMI -> 7; reset -> 7), fetch vector, load CP (byte1) and PC.
- Max-mode stack frame, SP decreases by 6; addresses relative to old SP = 2m: 
  - 2m-6: SR high byte  <- new SP
  - 2m-5: SR low byte
  - 2m-4: don't care (pad byte)
  - 2m-3: CP
  - 2m-2: PC high
  - 2m-1: PC low
  (Min mode: 2m-4 SR hi, 2m-3 SR lo, 2m-2 PC hi, 2m-1 PC lo.) Stack accessed through TP:SP (TP = stack page register). Pushed PC = address of next instruction, RTE returns to it. SP must be even (odd SP -> address error).
- Same frame for TRAPA, trace, zero-divide, invalid instruction, address error (invalid/address-error push PC "when error occurred", not necessarily the start of the instruction).
- Deferral: exceptions (address error, trace, NMI, IRQ0/1, all internal interrupts) are NOT accepted until after the NEXT instruction completes when the instruction just executed is one of: XORC, ORC, ANDC, LDC, RTE (if next is also one of these, defer again). LDC covers writes to SR/CCR/CP/DP/EP/TP page registers (all LDC forms). After reset all interrupts (incl. NMI) disabled until the first instruction has executed (max mode: first instruction should be LDC to TP, then MOV SP). After a DTC transfer cycle, the CPU also executes one more instruction before taking a pending interrupt (incl. NMI).
- SR layout (for reference): T bit 15, I2-I0 bits 10-8, CCR in low byte. (not from this section; check CPU section if needed.)

## 2. FRT1/2/3 16-bit free-running timers [10]
Base: FRT1 H'FF90, FRT2 H'FFA0, FRT3 H'FFB0. Offsets:
| Off | Reg | Size | R/W | Reset |
|---|---|---|---|---|
| +0 | TCR | 8 | R/W | 00 |
| +1 | TCSR | 8 | R/(W) bits 7-4 | 00 |
| +2/+3 | FRC H/L | 16 | R/W | 0000 |
| +4/+5 | OCRA H/L | 16 | R/W | FFFF |
| +6/+7 | OCRB H/L | 16 | R/W | FFFF |
| +8/+9 | ICR H/L | 16 | R | 0000 |
| +A..+F | unused | | | |
(Registers also reset in standby modes.)
TCR bits: 7 ICIE, 6 OCIEB, 5 OCIEA, 4 OVIE (interrupt enables for ICI/OCIB/OCIA/FOVI), 3 OEB, 2 OEA (output enable of FTOB/FTOA pins), 1-0 CKS1/0.
- CKS: 00 = ø/4 (reset), 01 = ø/8, 10 = ø/32, 11 = external FTCI pin, rising edge. (OEB must be 0 when external clock used since FTCI shares the FTOB pin P74/P75/P76.) External pulse width >= 1.5 ø.
TCSR: 7 ICF, 6 OCFB, 5 OCFA, 4 OVF (R/(W), write 0 to clear after read), 3 OLVLB, 2 OLVLA (level driven on compare match: 0=low,1=high), 1 IEDG (0 falling, 1 rising edge of FTI captures), 0 CCLRA (1 = FRC cleared on compare-match A).
- ICF set when capture occurs (FRC copied to ICR even if ICF already 1). OCFA/OCFB set when FRC == OCRx; the match is detected in the last state in which they are equal, i.e. flag is set on the clock tick when FRC would move N -> N+1 (so a match for value N is signalled one counter period after FRC became N; at the same time FRC increments, or clears to 0000 if CCLRA with OCRA). OVF set when FRC goes FFFF -> 0000.
- Pin output: at compare match x with OEx=1, pin FTOx driven to OLVLx. Pin is 0 before first match. Pins: FTOA1=P77, FTOA2=P90, FTOA3=P91, FTOB1=P74, FTOB2=P75, FTOB3=P76. Pin only driven if OEx=1 (port DDR otherwise rules). Capture pins FTI1/2/3 = P71/P72/P73. Min FTI pulse 1.5 ø.
- Interrupts: ICI = ICF&ICIE, OCIA = OCFA&OCIEA, OCIB = OCFB&OCIEB, FOVI = OVF&OVIE; vectors per 1.4, priority per IPRB/IPRC.
- 16-bit access via TEMP (shared 8-bit temp per module access path): 
  - Write: write to HIGH byte (even addr) latches into TEMP; write to LOW byte writes {TEMP, low} to the 16-bit register atomically.
  - Read of FRC/ICR: read HIGH byte returns high and latches LOW byte into TEMP; read LOW byte returns TEMP. OCRA/OCRB reads: both bytes read directly (no TEMP).
  - Must access high then low (MOV.W is OK). Wrong order or single byte = wrong data (manual: not transferred correctly).
- Contention: FRC low-byte write in same cycle as clear -> clear wins; write vs increment -> write wins; OCR low-byte write vs match -> match inhibited. ICR high-byte read coinciding with capture delays capture 1 state.
- Synchronization: all three FRCs reset to 0 together, run in lockstep until clock source changed/FRC written/cleared. After reset all use ø/4.
- Changing CKS can cause a spurious FRC increment (falling-edge of old selected clock, cases per table 10-5). Fine to ignore.

## 3. PWM timers 1-3 [12]
| Ch | TCR | DTR | TCNT | pin |
|---|---|---|---|---|
| 1 | FFC0 | FFC1 | FFC2 | PW1=P92 |
| 2 | FFC4 | FFC5 | FFC6 | PW2=P93 |
| 3 | FFC8 | FFC9 | FFCA | PW3=P94 |
(Manual heading for TCNT mislists "FFC2,FFC4,FFCA"; table 12-2 and appendix B give FFC6 for ch2.)
- TCR reset H'38: b7 OE (1 = run counter + drive pin; 0 = TCNT=0 & stopped, pin is port 9), b6 OS (0 positive logic, 1 negative), b5-3 read 1, b2-0 CKS: 000 ø/2, 001 ø/8, 010 ø/32, 011 ø/128, 100 ø/256, 101 ø/1024, 110 ø/2048, 111 ø/4096.
- DTR reset FF, R/W, double-buffered: new value takes effect when TCNT goes F9 -> 00; immediate when OE=0. Reads return currently valid value.
- TCNT reset 00, counts 00..F9 (250 steps) then wraps to 00; test-write only. Period = 250 x clock period.
- Output (positive): OE=1 and DTR!=0: pin goes 1 when count 00->01, returns 0 when count reaches DTR. DTR=0: constant 0. DTR >= FA: constant 1 (100%). Negative logic = inverted. No interrupts. Output only when OE=1 (shared with P9x; P9xDDR irrelevant when OE=1 per table 9-16... table: OE=1 -> PWx output regardless of DDR).

## 4. 8-bit timer [11]
| Addr | Reg | R/W | Reset |
|---|---|---|---|
| FFD0 | TCR | R/W | 00 |
| FFD1 | TCSR | R/(W) b7-5 | 10 |
| FFD2 | TCORA | R/W | FF |
| FFD3 | TCORB | R/W | FF |
| FFD4 | TCNT | R/W | 00 |
TCR: 7 CMIEB, 6 CMIEA, 5 OVIE, 4-3 CCLR1/0 (00 none, 01 clear on compare-match A, 10 clear on compare-match B, 11 clear on RISING edge of external TMRI = P73), 2-0 CKS2-0: 000 stopped, 001 ø/8, 010 ø/64, 011 ø/1024, 100 stopped, 101 external TMCI (P70) rising edge, 110 external falling edge, 111 external both edges. External pulse >= 1.5 ø (single edge) / 2.5 ø (both).
TCSR: 7 CMFB, 6 CMFA, 5 OVF (R/(W)), 4 reserved reads 1, 3-2 OS3/OS2 (compare-match B effect on TMO: 00 none, 01 output 0, 10 output 1, 11 toggle), 1-0 OS1/OS0 (same for compare-match A). Reset TMO=0; TMO pin = P17; driven when any OS bit nonzero (else P17 is port). If A and B match simultaneously: priority toggle > 1 > 0 > no change.
- Flags: CMFA/CMFB set when TCNT == TCORA/B (signalled in last state of match, i.e. at the tick moving TCNT N->N+1, or clearing it); OVF set on FF -> 00. Cleared by read-then-write-0 (or DTC for CMF).
- Interrupts: CMIA = CMFA&CMIEA, CMIB = CMFB&CMIEB, OVI = OVF&OVIE. Vectors per 1.4, level IPRC bits 2-0.
- Contention: TCNT write vs clear: clear wins; write vs increment: write wins; TCOR write vs match: match inhibited.

## 5. SCI [14]
| Addr | Reg | R/W | Reset |
|---|---|---|---|
| FFD8 | SMR | R/W | 04 |
| FFD9 | BRR | R/W | FF |
| FFDA | SCR | R/W | 0C |
| FFDB | TDR | R/W | FF |
| FFDC | SSR | R/(W) b7-3 | 87 |
| FFDD | RDR | R | 00 |
- SMR: 7 C/A (0 async, 1 sync), 6 CHR (0 = 8 bit, 1 = 7 bit; async), 5 PE (parity enable; async), 4 O/E (0 even, 1 odd), 3 STOP (0 = 1 stop bit, 1 = 2), 2 reserved reads 1, 1-0 CKS: 00 ø, 01 ø/4, 10 ø/16, 11 ø/64.
- Baud rate: async B = OSC(Hz) / (64 * 2^(2n) * (N+1)) with OSC = crystal freq, n = CKS (0..3), N = BRR (0..255); equivalently B = ø / (32 * 4^n * (N+1)). Sync: B = OSC / (8 * 4^n * (N+1)) = ø/(4*4^n*(N+1)). Checks vs manual table 14-3: 12 MHz crystal 9600 baud n=0 N=19; 4.9152 MHz 9600 n=0 N=7. Async internal sample clock = 16x bit rate.
- SCR: 7 TIE (TXI enable), 6 RIE (RXI + ERI enable), 5 TE, 4 RE, 3-2 reserved read 1, 1 CKE1 (1 = external clock at SCK), 0 CKE0. Async: CKE1=0 internal clock (CKE0=0: SCK is port pin P97; CKE0=1: SCK outputs clock at bit rate); CKE1=1 external clock at 16x bit rate. Sync: CKE1=0 internal clock with serial clock output on SCK; CKE1=1 external input clock. TE=1 forces TXD (P95) output; RE=1 forces RXD (P96) input.
- SSR: 7 TDRE (reset 1), 6 RDRF, 5 ORER, 4 FER, 3 PER (R/(W), clear by read-then-write-0), bits 2-0 read 1. NO TEND bit on this chip.
  - TDRE: set at reset/standby; set when TDR content is moved to TSR (this is the moment TXI is requested); set when TE cleared while TDRE=0. Cleared by CPU read-then-write-0, or DTC write of TDR. Writing TDR does NOT clear TDRE by itself; software must clear it (write TDR first, then clear TDRE). Writing TDR while TDRE=0 overwrites (loses) the old byte. TE=1 with TDRE=1: TXD held 1 (one idle frame sent first).
  - RDRF: set when a full frame is received without error and moved RSR -> RDR (7-bit: RDR bit7 = 0). Cleared by read-then-write-0, DTC RDR read, reset. Reading RDR does not clear it.
  - ORER: set when the next frame completes while RDRF=1; the new byte is NOT copied to RDR (lost). Sync mode: ORER also stops further reception until cleared.
  - FER (async: stop bit = 0; first stop bit only checked in masked ROM; sync: no meaning per manual though description says framing error "in synchronous mode" - manual text inconsistent: FER description says sync, section 14.3 says async framing error). Frame still transferred RSR->RDR (RDRF NOT set, flag FER set). Line break = FER with RDR=00.
  - PER: parity mismatch (async, PE=1), frame transferred to RDR, PER set, RDRF not set. NOTE manual SMR PE description says "Receive: parity is not checked" for PE=1 but PER description and table 14-8 say it is checked: treat as checked.
  - Any receive error: RDRF not set; error flag set; RSR copied to RDR for FER/PER (not ORER). Table 14-10 combos: overrun keeps RDRF=1.
- Interrupt requests: TXI = TDRE & TIE (level, stays while TDRE=1 and TIE=1); RXI = RDRF & RIE; ERI = (ORER|FER|PER) & RIE. Vectors D0/D4/D8, level IPRD bits 6-4.
- Timing: frame time = (start+data+parity+stop) bits at B baud; TXI occurs when TDR->TSR transfer happens (right after TDRE cleared with data, i.e. nearly immediately, then again once the previous frame in TSR finishes and a new byte is waiting). Sync: 8 data bits per byte, LSB first, TXD changes on falling SCK edge, RXD latched on rising edge; internal-clock sync transmit starts when TDRE cleared and generates 8 SCK clocks; with RE=1 internal clock, reception clocks start as soon as RE=1.
- Init: clear TE and RE, set SMR/BRR/SCR(clock), wait >= 1 bit time, then set TE/RE. TDR written/read normally as bytes.

## 6. A/D converter [15]
| Addr | Reg | R/W | Reset |
|---|---|---|---|
| FFE0/E1 | ADDRA H/L (AN0 / AN4) | R | 0000 |
| FFE2/E3 | ADDRB (AN1 / AN5) | R | 0000 |
| FFE4/E5 | ADDRC (AN2 / AN6) | R | 0000 |
| FFE6/E7 | ADDRD (AN3 / AN7) | R | 0000 |
| FFE8 | ADCSR | R/(W) b7 | 00 |
- ADDRn high byte = AD9..AD2 (result >> 2), low byte = AD1,AD0 in bits 7-6, bits 5-0 read 0 (result left-justified in 16 bits: FFC0 = full scale). Read high byte latches low byte in TEMP; read low byte returns TEMP (read high first / use MOV.W).
- ADCSR: 7 ADF (R/(W): set at end of conversion; cleared by read-then-write-0 or DTC), 6 ADIE, 5 ADST (start; single mode auto-clears at end), 4 SCAN (0 single, 1 scan), 3 CKS (0 = 274 states per conversion, 1 = 138 states), 2-0 CH2-0.
- Channel select: group 0 (CH2=0), group 1 (CH2=1). Single mode: CH1-0 picks one channel: AN(CH2*4+CH1-0). Scan mode: converts AN(base) .. AN(base+CH1-0) cyclically (CH=000 -> only base; 001 -> base,+1; 010 -> base..+2; 011 -> base..+3). Result of ANk goes to ADDR(k mod 4).
- Single: ADST=1 starts; at end result stored, ADF=1, ADST cleared; ADI requested if ADIE.
  Scan: starts at first channel, goes through the list repeatedly while ADST=1; ADF set (and ADI requested) after each complete pass over all selected channels; continues until software clears ADST.
- Timing (states): single mode total tCONV = 259-274 (CKS=0), 131-138 (CKS=1) from ADCSR write (includes sync delay tD 18-33 / 10-17 and sampling 63/31); max values are safe to emulate (274/138). Scan: first conversion as single, subsequent channels 256 (CKS=0) / 128 (CKS=1) states each.
- While converting, P8DR bit of the channel being converted reads 1.
- ADI vector 00E0 (max), level IPRD bits 2-0. No ADCR on this chip. Changing mode/CH/CKS only with ADST=0.
- Scan-mode note: reading ADDR while ADST cleared mid-pass may give bad data (ZTAT erratum) - ignore.

## 7. Watchdog timer [13]
| Addr | Reg | Notes | Reset |
|---|---|---|---|
| FFEC (read) | TCSR | | 18 |
| FFED (read) | TCNT | | 00 |
| FFEC (word write) | TCSR/TCNT write | see protocol | |
- Write protocol: WORD write to address H'FFEC only. High byte (at FFEC) = password: H'A5 -> low byte (at FFED) goes to TCSR; H'5A -> low byte goes to TCNT. Byte writes and other passwords are ignored (manual: byte access cannot write). Examples: MOV.W #H'5A00,@H'FFEC clears TCNT; MOV.W #H'A54F,@H'FFEC writes TCSR=4F (appendix B says "write addresses are FFED" = location of low byte). Reads are normal byte reads: FFEC = TCSR, FFED = TCNT.
- TCSR bits: 7 OVF (R/(W): set on TCNT FF->00; cleared by read-then-write-0 via TCSR word write with bit7=0; cannot write 1), 6 WT/IT (0 interval timer -> IRQ0 request; 1 watchdog -> NMI request), 5 TME (1 = TCNT runs; 0 = TCNT cleared to 00 and stopped), 4-3 reserved read 1, 2-0 CKS: 000 ø/2, 001 ø/32, 010 ø/64, 011 ø/128, 100 ø/256, 101 ø/512, 110 ø/2048, 111 ø/4096. Overflow interval at ø = 10 MHz: 51.2us, 819.2us, 1.6ms, 3.3ms, 6.6ms, 13.1ms, 52.4ms, 104.9ms (=256 x div / ø).
- Reset: OVF,WT/IT,TME = 0, CKS = 0 (bits 2-0 retained in standby), TCNT = 0. TCNT is cleared when TME=0.
- Overflow, watchdog mode (WT/IT=1,TME=1): sets OVF, requests NMI (vector 002C). NO reset, no RSTCSR (unlike H8/500 later parts). Counter continues counting (wraps to 00 and keeps running; further overflows re-request NMI).
- Overflow, interval mode (WT/IT=0,TME=1): sets OVF, requests IRQ0 (vector 0080, priority IPRA bits 6-4) every overflow. Manual does not say when the WDT-sourced IRQ0 request is dropped (model: pending until accepted).
- ISR must check OVF to distinguish pin vs WDT source.
- Software standby: TME must be 0 to enter; NMI wake uses WDT countup (OVF not set).
- Contention: TCNT write vs increment: write wins.

## 8. I/O ports [9]
All port registers: DDR write-only (reads return H'FF in implemented bits; bits "—" read 1), DR read/write. Reading DR: output pins (DDR=1) return the latch; input pins (DDR=0) return the live pin level (no input latch). 
| Port | DDR addr (reset) | DR addr (reset) | Bits | Notes |
|---|---|---|---|---|
| 1 | FF80 (03) | FF82 (bits7-2 =0; b1,b0 R-only, undefined = pin) | 8 | P17 TMO, P16 IRQ1, P15 IRQ0, P14 WAIT, P13 BREQ, P12 BACK, P11 E, P10 ø. P11/P10 DDR=1 output clocks E/ø (DR read = live clock). DR bits 1,0 read-only. |
| 2 | FF81 (E0) | FF83 (E0) | 5 (b4-0), b7-5 read 1 | P24 WR, P23 RD, P22 DS, P21 R/W, P20 AS. In expanded modes DDR bits fixed 1, pins are bus strobes. |
| 3 | FF84 (00) | FF86 (00) | 8 | Expanded: D7-D0 data bus (DDR unused). |
| 4 | FF85 (00) | FF87 (00) | 8 | Expanded: A7-A0 (DDR fixed 1). |
| 5 | FF88 (00) | FF8A (00) | 8 | Modes 1,3: A15-A8, DDR fixed 1. Modes 2,4: DDR bit 1 = address output, 0 = input (reset 0). MOS pull-up when DDR=0 and DR=1. |
| 6 | FF89 (F0) | FF8B (F0) | 4 (b3-0), b7-4 read 1 | Mode 3: A19-A16, DDR fixed 1. Mode 4: DDR selects. Pull-up when DDR=0 & DR=1. |
| 7 | FF8C (00) | FF8E (00) | 8 | Schmitt inputs. P77 FTOA1, P76 FTOB3/FTCI3, P75 FTOB2/FTCI2, P74 FTOB1/FTCI1, P73 FTI3/TMRI, P72 FTI2, P71 FTI1, P70 TMCI. Timer inputs always live on pin even as general inputs. |
| 8 | none | FF8F (R only) | 8 | Input only; AN7-AN0. Reads live pin level (digital); pin being converted reads 1 during conversion. Writes ignored. |
| 9 | FFFE (00) | FFFF (00) | 8 | P97 SCK, P96 RXD, P95 TXD, P94 PW3, P93 PW2, P92 PW1, P91 FTOA3, P90 FTOA2. |
- FF8D unused.
- P1CR (FFFC, reset H'87, R/W bits 6-3 only; bits 7,2,1,0 read 1): b6 IRQ1E (1 = P16 is IRQ1 input), b5 IRQ0E (1 = P15 IRQ0 input), b4 NMIEG (0 falling, 1 rising), b3 BRLE (1 = P13 BREQ input, P12 BACK output; expanded only). Not reset by software standby, reset by hardware standby/reset.
- Pin function selectors: P17 -> TMO if any OS bit nonzero (DDR then irrelevant for output); P14 -> WAIT input when WCR.WMS1=1; P97 SCK per SMR.C/A/SCR.CKE; P96 RXD when RE=1; P95 TXD when TE=1; P94/93/92 PW3/2/1 when PWM OE=1; P91 FTOA3 when FRT3.OEA=1; P90 FTOA2 when FRT2.OEA=1. FTOA1 on P77 when FRT1.OEA=1; FTOBn on P74-P76 when FRTn.OEB=1.
  (Manual P90 text says "FRT3 TCR OEA" for both P91 and P90 - typo for FRT2 on P90; assumed FRT2.)
- Mode 3 (expanded max, no on-chip ROM): P2 = bus strobes (AS, R/W, DS, RD, WR; DDR forced 1), P3 = D7-D0, P4 = A7-A0, P5 = A15-A8, P6 = A19-A16 (DDR all forced 1; reads of DDR still 1s). P2/P3/P4/P5/P6 DR registers retain no GPIO meaning (writes effectively ignored for pins). Ports 1,7,8,9 as normal. Bus strobes: AS low at T1-ish, DS/RD/WR in T2-T3 (3-state, 8-bit).
- Standby: software standby resets on-chip modules (port 7/9 pins revert to GPIO), DDRs retained.

## 9. System registers
| Addr | Reg | Reset | Notes |
|---|---|---|---|
| FFF8 | WCR | F3 | b7-4 read 1. b3-2 WMS1/0: 00 programmable wait (WAIT pin = P14 GPIO), 01 no waits at all regardless of WC, 10 pin wait (WAIT enabled; WC states plus extra while WAIT low), 11 pin auto-wait (WC states inserted only if WAIT low sampled once in T2). b1-0 WC1/0 = 0..3 wait states (Tw between T2 and T3), only on off-chip accesses. **H'F3 = programmable, 3 waits (reset). H'F0 = programmable, 0 waits. H'F1 = programmable, 1 wait.** Not reset by software standby. |
| FFF9 | RAMCR | FF | b7 RAME (R/W, 1 = on-chip RAM FB80-FF7F enabled); b6-0 read 1. |
| FFFA | MDCR | C0|mode (read-only) | b7-6 read 1, b5-3 read 0, b2-0 = MD2-MD0 latched. Mode 3 -> C3; mode 4 -> C4; mode 1 -> C1; mode 2 -> C2; mode 7 -> C7. Not writable. |
| FFFB | SBYCR | 7F | b7 SSBY (0 sleep on SLEEP, 1 software standby on SLEEP; cannot be set to 1 while WDT TME=1; auto-cleared on NMI wake), b6-0 read 1. |
### Full register field FF80-FFFF, sorted
| Addr | Name | Reset |
|---|---|---|
| FF80 | P1DDR (W; read FF) | 03 |
| FF81 | P2DDR (W; read FF) | E0 |
| FF82 | P1DR | 00 (b1,b0 = pins) |
| FF83 | P2DR | E0 |
| FF84 | P3DDR | 00 |
| FF85 | P4DDR | 00 |
| FF86 | P3DR | 00 |
| FF87 | P4DR | 00 |
| FF88 | P5DDR | 00 |
| FF89 | P6DDR | F0 |
| FF8A | P5DR | 00 |
| FF8B | P6DR | F0 |
| FF8C | P7DDR | 00 |
| FF8D | - | - |
| FF8E | P7DR | 00 |
| FF8F | P8DR (R) | pins |
| FF90 | FRT1 TCR | 00 |
| FF91 | FRT1 TCSR | 00 |
| FF92-93 | FRT1 FRC H/L | 0000 |
| FF94-95 | FRT1 OCRA | FFFF |
| FF96-97 | FRT1 OCRB | FFFF |
| FF98-99 | FRT1 ICR (R) | 0000 |
| FF9A-FF9F | - | - |
| FFA0-FFA9 | FRT2 same layout (TCR A0, TCSR A1, FRC A2/A3, OCRA A4/A5, OCRB A6/A7, ICR A8/A9) | as above |
| FFAA-FFAF | - | - |
| FFB0-FFB9 | FRT3 same layout (TCR B0, TCSR B1, FRC B2/B3, OCRA B4/B5, OCRB B6/B7, ICR B8/B9) | as above |
| FFBA-FFBF | - | - |
| FFC0 | PWM1 TCR | 38 |
| FFC1 | PWM1 DTR | FF |
| FFC2 | PWM1 TCNT | 00 |
| FFC3 | - | - |
| FFC4 | PWM2 TCR | 38 |
| FFC5 | PWM2 DTR | FF |
| FFC6 | PWM2 TCNT | 00 |
| FFC7 | - | - |
| FFC8 | PWM3 TCR | 38 |
| FFC9 | PWM3 DTR | FF |
| FFCA | PWM3 TCNT | 00 |
| FFCB-FFCF | - | - |
| FFD0 | TMR TCR | 00 |
| FFD1 | TMR TCSR | 10 |
| FFD2 | TMR TCORA | FF |
| FFD3 | TMR TCORB | FF |
| FFD4 | TMR TCNT | 00 |
| FFD5-FFD7 | - | - |
| FFD8 | SCI SMR | 04 |
| FFD9 | SCI BRR | FF |
| FFDA | SCI SCR | 0C |
| FFDB | SCI TDR | FF |
| FFDC | SCI SSR | 87 |
| FFDD | SCI RDR (R) | 00 |
| FFDE-FFDF | - | - |
| FFE0-FFE7 | ADDRA..ADDRD H/L (R) | 0000 each |
| FFE8 | ADCSR | 00 |
| FFE9-FFEB | - | - |
| FFEC | WDT TCSR (R) / password byte (W) | 18 |
| FFED | WDT TCNT (R) / data byte (W) | 00 |
| FFEE-FFEF | - | - |
| FFF0 | IPRA | 00 |
| FFF1 | IPRB | 00 |
| FFF2 | IPRC | 00 |
| FFF3 | IPRD | 00 |
| FFF4 | DTEA | 00 |
| FFF5 | DTEB | 00 |
| FFF6 | DTEC | 00 |
| FFF7 | DTED | 00 |
| FFF8 | WCR | F3 |
| FFF9 | RAMCR | FF |
| FFFA | MDCR (R) | C0+mode |
| FFFB | SBYCR | 7F |
| FFFC | P1CR | 87 |
| FFFD | - | - |
| FFFE | P9DDR (W; read FF) | 00 |
| FFFF | P9DR | 00 |
- Unused/"-" register addresses: reads unspecified (manual silent); suggest return FF/00 and ignore writes.

## 10. Uncertainties / manual inconsistencies
1. Read-back of write-only DDRs = H'FF (explicit in manual); read of bits shown "—" = 1 (reserved), WDT/FRT unused bytes unspecified.
2. Interval-mode WDT IRQ0 request clearing behavior unspecified (modelled as pending until accepted; OVF stays set until software clears).
3. SCI parity checking: SMR text says PE=1 receive "not checked" vs PER description (checked). Assumed checked.
4. SCI FER described as "synchronous mode" in the bit table but "no meaning in async" contradicts section 14.3 (framing error is async stop-bit=0). Assumed FER meaningful in async only.
5. Word-access external/register-field = two byte cycles is inferred from the BREQ note and 8-bit bus width, not stated as an explicit cycle count. Register field 3 states/byte, external 3 states/byte + Tw.
6. Compare-match "signalled one counter period after the counter reaches the value" described by manual (match flag set in last state of equality, at the moment of increment).
7. PWM TCNT ch2 address: table says FFC6, heading text says FFC4 (typo).
8. IRQ1 paragraph says "IRQ0 interrupt is requested by high-to-low transition at IRQ1" = IRQ1 (typo).
9. Section 2.3.2 says RAM starts "H'FFB0"; correct start is H'FB80 (matches section 16, figure 2-2).
10. Exact delay of interrupt acceptance in states and SR bit layout not covered here (CPU section 3).
11. Unverified vs images: stack frame diagram taken from text extraction of fig 5-3(b) (clear in text: SR hi, SR lo, don't-care, CP, PC hi, PC lo ascending addresses from new SP); not re-checked against rendered page.
