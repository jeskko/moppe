# MC68HC16Z1 peripherals: register-level reference

Extracted 2026-10-08 (by a subagent, from the text of the SIM, GPT, QSM
and ADC reference manuals and the MC68HC16Z1 User's Manual in
`reference/oh5nxo/mods/MDR150/`) as the implementation spec for
`emu/hc16z1.c`. Section 5 lists where the manuals disagree or say
nothing.

Corrections from the emulator work, which override the text below:

- **Chip-select BYTE field (16-bit ports):** 01 ("lower byte") asserts
  for the **odd** byte (ADDR0 = 1, D0..D7), and 10 for the even byte
  (D8..D15), not the other way round as 1.8 says. On the MDR150, CS0
  with BYTE 01 is the write strobe of the RAM chip on D0..D7, and HaMDR
  runs with it.
- **ADC conversion time:** the manual's formula (4.2) gives 18 ADC
  clocks for a 10-bit conversion with STS 00. OH5NXO measured 20 on the
  MDR150 in multichannel scan, and his AFSK demodulator is tuned to it.
  The emulator adds 2 clocks in multichannel mode.
- **PIT IACK:** the PIT request is cleared on its interrupt acknowledge
  (assumed in 5; HaMDR works with it).


Sources (cited as): **Z1** = MC68HC16Z1 User's Manual (MC68HC16ZUM; App. D = register summary, Sect. 5 SIM, 8 ADC, 9 QSM, 11 GPT);
**SIMRM**, **GPTRM**, **QSMRM**, **ADCRM** = module reference manuals; **CPU16RM** = CPU16 reference manual.
Where they differ, Z1 is followed and the difference is listed in section 5. "UNSURE" = not stated in the manuals, inferred.

Conventions: addresses are 20-bit (`$FFxxx`, CPU sees `$YFFxxx` with Y=$F, MM=1). Registers are 16-bit, big endian. A "byte at $FFxx5"
means the low byte of the word at $FFxx4. Numbers in `$` are hex, `%` binary. fsys = system clock, fref = crystal (EXTAL).
Unimplemented bits read 0, writes ignored. All modules treat the CPU as always supervisor, so every SUPV bit is a no-op (Z1 D.2.1, D.5.1, D.6.1, D.8.1).

Module map (Z1 3.6, Fig 3-8): ADC $FF700-$FF73F, GPT $FF900-$FF93F, SIM $FFA00-$FFA7F, SRAM control $FFB00-$FFB07 (+1K array, out of scope),
QSM $FFC00-$FFDFF. Anything else in this window is not an on-chip module (goes to the external bus / chip-select).

---------------------------------------------------------------------------------------------------

## 0. Vector numbers and interrupt model (common)  [Z1 5.8, CPU16RM Table 9-1]

* Vector number n (hex) -> vector address = 2*n, bank 0. $0F = uninitialized interrupt ($001E), $11-$17 = level 1-7 autovectors ($0022-$002E),
  **$18 = spurious interrupt ($0030)**, $38-$FF user vectors ($0070-$01FE; Z1/QSMRM say user vectors $40-$FF are the intended range).
* Seven levels; IRQ7 non-maskable (level 7 always taken, edge sensitive on the pin); level L is taken if L > CCR.IP (or L = 7).
  The CPU latches level L into CCR.IP on IACK.
* IACK: CPU space read, FC=%111, ADDR[19:16]=%1111, ADDR[3:1]=level L. Every module that is requesting at level L contends by IARB value
  (serial contention, higher IARB wins, $F highest, $1 lowest). Contention occurs even with a single requester.
  * Winner supplies an 8-bit vector number (internal modules: always a user vector, never autovector, terminated with internal DSACK).
  * Nobody wins (only IARB=0 requesters, or no requester) -> spurious interrupt monitor asserts BERR -> CPU takes **spurious vector $18**.
    So a module with IARB=0 that is requesting causes spurious interrupt. (Z1 5.2.2, 5.8.3, 5.8.4 E.1; SIMRM 6.3).
  * Two modules with same non-zero IARB at the same level: undefined (do not emulate).
* IARB reset values: SIM $F; GPT 0; QSM 0 (ADC has no IARB, no interrupts). Firmware must set unique non-zero IARB in GPTMCR/QSMCR before use.
* SIM interrupt sources (SIM IARB used for both): PIT, and external IRQ[7:1] pins. If PIT and an IRQ pin request the same level, PIT wins (Z1 5.4.7, 5.8.3).
* Equal level between GPT and QSM: IARB decides. Within QSM: ILQSPI == ILSCI -> QSPI first (Z1 D.6.3). Within GPT: priority table (2.4).

---------------------------------------------------------------------------------------------------

## 1. SIM  ($FFA00-$FFA7F)

### 1.1 Register map (Z1 D.2, Table D-2)

| Addr | Reg | Size/use |
|---|---|---|
| FFA00 | SIMCR | 16 |
| FFA02 | SIMTR | factory test (read 0) |
| FFA04 | SYNCR | 16 |
| FFA06 | RSR | byte at FFA07 (high byte reads 0) |
| FFA08 | SIMTRE | test |
| FFA11 | PORTE0 | byte (FFA10 high byte 0) |
| FFA13 | PORTE1 | byte, same latch as PORTE0 |
| FFA15 | DDRE | byte |
| FFA17 | PEPAR | byte |
| FFA19 | PORTF0 | byte |
| FFA1B | PORTF1 | byte, same as PORTF0 |
| FFA1D | DDRF | byte |
| FFA1F | PFPAR | byte |
| FFA21 | SYPCR | byte |
| FFA22 | PICR | 16 |
| FFA24 | PITR | 16 |
| FFA27 | SWSR | byte |
| FFA30-3A | TSTMSRA/B, TSTSC, TSTRC, CREG, DREG | factory test, ignore |
| FFA41 | PORTC | byte |
| FFA44 | CSPAR0 | 16 |
| FFA46 | CSPAR1 | 16 |
| FFA48 | CSBARBT | 16 |
| FFA4A | CSORBT | 16 |
| FFA4C,4E | CSBAR0, CSOR0 | 16 each |
| FFA50.. | CSBAR1,CSOR1 (50,52), 2 (54,56), 3 (58,5A), 4 (5C,5E), 5 (60,62), 6 (64,66), 7 (68,6A), 8 (6C,6E), 9 (70,72), 10 (74,76) | |
| FFA78-7E | unused | |

(Z1 map drawing shows byte registers right-justified in the word, i.e. on the odd address; ports/DDR/PAR, RSR, SYPCR, SWSR, PORTC are single bytes.)

### 1.2 SIMCR $FFA00  (Z1 D.2.1; SIMRM 3.1.6)
`15 EXOFF | 14 FRZSW | 13 FRZBM | 12 0 | 11 RSVD | 10 0 | 9:8 SHEN[1:0] | 7 SUPV | 6 MM | 5:4 0 | 3:0 IARB`
* Reset: EXOFF 0, FRZSW 1, FRZBM 1, bit11 = DATA11 sampled at reset (reads 0 in normal operation; must stay 0; read-only), SHEN 00, SUPV 1, MM 1, IARB $F -> **$60CF** (with DATA11=0).
* R/W any time except **MM: write-once after reset** (later writes ignored), bit 11 read-only. MM=0 would move the module block to $7FF000 (unreachable by CPU16); emulate by ignoring (or just keep MM=1).
* EXOFF: CLKOUT tri-state. FRZSW/FRZBM: with FREEZE asserted (BDM), disable watchdog+PIT / bus monitor. SHEN: show-cycle config (external bus only; no effect on an emulator).

### 1.3 SYNCR $FFA04  (Z1 D.2.3, 5.3.2; SIMRM 4)
`15 W | 14 X | 13:8 Y[5:0] | 7 EDIV | 6:5 0 | 4 RSVD | 3 SLOCK | 2 RSVD | 1 STSIM | 0 STEXT`
* Reset **$3F00** (W=0, X=0, Y=%111111, EDIV 0, STSIM 0, STEXT 0); SLOCK "U" (SYNCR reset leaves SLOCK/lock state unaffected: SIMRM Table 8-4). Gives fsys = 8.388 MHz from 32.768 kHz or 4.194 MHz crystal.
* **Slow reference (25-50 kHz, e.g. 32.768 kHz):  fsys = 4 * fref * (Y+1) * 2^(2W+X)**
* **Fast reference (1-6 MHz, e.g. 4.194 MHz): fsys = (fref/128) * 4 * (Y+1) * 2^(2W+X)**
* External clock (MODCLK=0 at reset): PLL disabled, fsys = EXTAL; W/X/Y have no effect.
* fVCO = 4*fsys if X=0, 2*fsys if X=1. W and Y changes force a VCO relock delay (SLOCK reads 0 until locked); an X change needs no relock. After power-up the MCU stays in reset until the PLL locks.
* EDIV: ECLK = fsys/8 (0) or /16 (1). STSIM/STEXT: LPSTOP clock behaviour only (STSIM 0: SIM clock from crystal, VCO off; 1: VCO; STEXT: CLKOUT during LPSTOP if EXOFF... ).
* Write protection: **none documented** - all bits read/write at any time (RSVD bits read 0, must not be set). No write-once bits. Z1 note: "SLOCK does not indicate lock status until after the first write to SYNCR". Emulator: SLOCK may simply read 1.
* Z1 SYNCR has no SLIMP/RSTEN (SIMRM's version has them at bit 4/2: ignore, differ per 5).

### 1.4 RSR $FFA07  (Z1 D.2.4, 5.7.10)
`7 EXT | 6 POW | 5 SW | 4 HLT | 3 0 | 2 RSVD | 1 SYS (never set on CPU16) | 0 TST`
Read-only (writes ignored); updated by reset logic when RESET is released; several bits can be set. Power-up -> POW (and EXT typically both: UNSURE; real parts set POW only on power-up, EXT on pin reset). Watchdog reset -> SW. Halt monitor (double bus fault, if HME) -> HLT.

### 1.5 SYPCR $FFA21  (Z1 D.2.12, 5.4; SIMRM 3.8.4)
`7 SWE | 6 SWP | 5:4 SWT[1:0] | 3 HME | 2 BME | 1:0 BMT[1:0]`
* **Reset: SWE=1 (watchdog enabled out of reset!), SWP = NOT MODCLK (MODCLK=0 external clock -> SWP=1, /512; MODCLK=1 -> 0), SWT=00, HME=0, BME=0, BMT=00.** => $80 (MODCLK=1) or $C0 (MODCLK=0).
* **Write-once**: the register can be written once after reset; later writes ignored (Z1: "once following power-on or reset"; SIMRM: "power-on or external reset"). Applies to the whole byte.
* Software watchdog time-out = divide ratio / fref (slow ref), = 128*ratio/fref (fast ref), = ratio/fsys (external clock). Ratio (SWP,SWT): 0,00 2^9; 0,01 2^11; 0,10 2^13; 0,11 2^15; 1,00 2^18; 1,01 2^20; 1,10 2^22; 1,11 2^24. (Z1 Tab D-6/5-10; the text lost the superscripts, verified against Table 5-10 ratios and SIMRM.)
  Example: slow ref 32.768 kHz, SWP=0,SWT=00: 512/32768 = 15.6 ms. This is the default after reset with SWE=1, so firmware must service or disable it early.
* Servicing: write **$55 to SWSR then $AA to SWSR**, in that order, any number of instructions between; the timer restarts only on the completed pair. A wrong value after $55 (UNSURE: presumably restarts the sequence) . SWSR reads 0 (shown with read value 0). Changing SWT requires a service sequence before the new period takes effect. On time-out RESET is asserted (RSR.SW=1). Watchdog stops during LPSTOP (not reset), and when FREEZE with FRZSW=1.
* BMT: bus monitor time-out 64/32/16/8 system clocks (00/01/10/11) for DSACK/AVEC; BME enables it for internal-to-external cycles. Time-out -> BERR (bus error exception). HME: double bus fault -> reset instead of halt.

### 1.6 PICR $FFA22 and PITR $FFA24  (Z1 D.2.13, D.2.14, 5.4.6, 5.4.7; SIMRM 3.6)
* PICR: `10:8 PIRQL | 7:0 PIV`, bits 15:11 = 0. Reset **$000F** (PIRQL=0 disabled, PIV=$0F uninitialized). R/W any time. PIRQL=0 disables the interrupt (timer keeps running).
* PITR: `8 PTP | 7:0 PITM`. Reset: PITM=0 (timer off), **PTP = NOT MODCLK** (Table 5-11: MODCLK=0 -> PTP=1; MODCLK=1 -> PTP=0) -> $0000 with MODCLK=1, $0100 with MODCLK=0 (the diagram just says "MODCLK"; Table 5-11 and SIMRM Table 8-4 give the meaning above). R/W any time.
* Clock into the /4 stage: PTP=0: fref (slow ref) or fref/128 (fast ref) (or fsys with external clock); PTP=1: that clock /512.
* **PIT period = PITM * (1 or 512) * 4 / fref** (slow ref); = 128*PITM*(1|512)*4/fref (fast ref); = PITM*(1|512)*4/fsys (external clock). PITM=0 = off. Examples at 32.768 kHz: PTP=0: PITM/8192 s (122 us/count), PTP=1: PITM/16 s (62.5 ms/count).
* The counter counts down from PITM; **on reaching zero it requests the interrupt and reloads from PITM**. A new PITR write is loaded at the end of the current count (not immediately).
* Interrupt: level PIRQL, vector number PIV (8 bit, supplied by SIM on IACK; $0F reset value -> uninitialized vector). Wins against an external IRQ at the same level. SIM arbitrates with SIMCR.IARB.
* Acknowledge/clear: **the manuals do not state it** (UNSURE). Standard SIM behaviour: the request is latched and cleared by the interrupt acknowledge cycle (no software flag, no register to clear). Implement: set pending at zero-crossing; clear when IACK at level PIRQL selects the PIT; if PIRQL<=IP the request stays pending (level 'sticks') until recognised.
* PIT keeps running during LPSTOP; it does not respond to LPSTOP. Stops on FREEZE only if FRZSW.

### 1.7 Ports E, F, C  (Z1 D.2.6-D.2.11, D.2.16, 5.10, 5.9.1.4)
* **Port E**  pins PE7..PE0 = SIZ1,SIZ0,AS,DS,(PE3 not connected),AVEC,DSACK1,DSACK0.
  PEPAR bit=1 -> pin is bus control signal, 0 -> I/O. **Reset PEPAR = DATA8 replicated in all 8 bits** (DATA8 high via pull-ups -> $FF; low -> $00).
  DDRE reset $00 (inputs). PORTE0/1 reset: unaffected by reset / undefined ("U"). PE3: PORTE bit 3 reads 0 and writes ignored, DDE3 reads 0, PEPA3 "returns one" (Z1 5.10.1) although D.2.8 says it can be read and written (UNSURE; use: reads 1... or store it - no function).
  Changing a port E pin from output to input drives it high ~4 ms first (ignore).
* **Port F**  PF7..PF1 = IRQ7..IRQ1, PF0 = MODCLK. PFPAR reset = DATA9 replicated (high -> $FF = IRQ pins; low -> I/O). DDRF reset $00. PORTF0/1 undefined at reset.
* Data register read (both ports): **for a bit configured as pin-assignment=I/O and DDR=0 (discrete input) returns the pin level; otherwise returns the stored latch value** ("A read returns the value at the pin only if the pin is configured as a discrete input. Otherwise the value read is the value stored in the register" - this includes pins assigned to bus-control/IRQ function: read gives the latch). Write: always goes to the latch; it is driven only for DDR=1 pins in I/O mode. PORTx0 and PORTx1 are two addresses of the same register.
* IRQ pins: level sensitive (must stay low until IACK), IRQ7 also needs a falling edge; sampled on falling clock edges, valid after 2 consecutive clocks. External request at level L is passed with the SIM IARB; vector comes from the device or AVEC (autovector $10+L).
* **Port C** PORTC byte at $FFA41: bits 6:0 = PC6..PC0, bit 7 reads 0. Reset **$7F**. PC0..PC6 = the discrete-output function of CS3..CS9 (PC0=CS3 ... PC6=CS9). Read/write any time; it is just a latch, driven on the pin only when the corresponding CSxPA field = %00. Reads return the latch value.

### 1.8 Chip selects  (Z1 D.2.17-D.2.21, 5.9; SIMRM 7)

**CSPAR0 $FFA44**: bits 15:14 = 0; `13:12 CS5PA | 11:10 CS4PA | 9:8 CS3PA | 7:6 CS2PA | 5:4 CS1PA | 3:2 CS0PA | 1:0 CSBTPA`.
**CSPAR1 $FFA46**: bits 15:10 = 0; `9:8 CS10PA | 7:6 CS9PA | 5:4 CS8PA | 3:2 CS7PA | 1:0 CS6PA`.
R/W any time. CSPAR0 bit 1 always reads 1 (write ignored).

Field encoding (all CSxPA except CSBOOT): `00` discrete output (CS3..CS9 -> PC0..PC6; CS10 -> ECLK; **not available** on CSBOOT, CS0-2: do not use), `01` alternate function, `10` chip select, 8-bit port, `11` chip select, 16-bit port.
Pin table: CSBOOT (no alt, no discrete); CS0/CS1/CS2 alt = BR/BG/BGACK; CS3/CS4/CS5 alt = FC0/FC1/FC2 (discrete PC0/PC1/PC2); CS6..CS9 alt = ADDR19..ADDR22 (discrete PC3..PC6); CS10 alt = ADDR23, discrete = ECLK.
(ADDR[23:20] follow ADDR19 on the CPU16.) A chip-select circuit whose pin is programmed 00/01 still runs internally (can generate DSACK/AVEC, e.g. for IACK) - Z1/SIMRM 7.3.

**Reset values** (each field's LSB = 1; MSB from data bus at reset, internal pull-ups -> 1):
* CSBTPA = {1, DATA0}: DATA0=1 -> 16-bit boot port (%11), DATA0=0 -> 8-bit (%10).
* CS0PA,CS1PA,CS2PA = {DATA1, 1}; CS3PA,CS4PA,CS5PA = {DATA2, 1}. (DATA=0 -> %01 alternate function BR/BG/BGACK resp. FC0-2.)
* CS6..CS10 (CSPAR1), LSB of each field = 1, MSB = AND of the high data lines: CS10PA msb = D7; CS9PA msb = D7&D6; CS8PA msb = D7&D6&D5; CS7PA msb = D7&D6&D5&D4; CS6PA msb = D7&D6&D5&D4&D3 (Z1 Table D-11). A low DATAn therefore turns CSn..CS6 into address lines (alternate function %01); e.g. DATA5 low -> CS[8:6] = ADDR[21:19] while CS10, CS9 stay chip selects; DATA7 low -> all five are ADDR[23:19].
* **All pull-ups (default): CSPAR0 = $03FF, CSPAR1 = $03FF** (everything is a 16-bit chip select, CSBOOT 16-bit).
* DATA11 = SIMCR bit 11, DATA8 -> PEPAR, DATA9 -> PFPAR (above).

**CSBAR[0:10], CSBARBT** ($FFA4C,50,54,..,74 and $FFA48): `15:3 ADDR[23:11] | 2:0 BLKSZ`.
* BLKSZ (address bits compared): 000 2 KB (23:11); 001 8 KB (23:13); 010 16 KB (23:14); 011 64 KB (23:16); 100 128 KB (23:17); 101 256 KB (23:18); 110 512 KB (23:19); 111 512 KB (23:20; see note). (Z1 Table D-12; SIMRM calls 111 "1 MB".) Base must be a multiple of block size (low bits of the base field below the block size are not compared). ADDR[23:20] = ADDR19 for CPU16-generated addresses, so compare 23:20 with the CPU address sign-extended from bit 19.
* Reset: **CSBARBT = $0007** (base 0, 512 KB); CSBAR0-10 = **$0000** (base 0, 2 KB block, but disabled via CSOR.BYTE/R/W = 0).
* R/W any time.

**CSOR[0:10], CSORBT** ($FFA4E,52,..,76; $FFA4A): `15 MODE | 14:13 BYTE | 12:11 R/W | 10 STRB | 9:6 DSACK | 5:4 SPACE | 3:1 IPL | 0 AVEC`.
* MODE: 0 asynchronous (CS asserted with AS/DS); 1 synchronous to ECLK (DSACK field ignored, AVEC must not be used, no DSACK termination).
* BYTE (only used for 16-bit ports; for 8-bit ports there is no byte decode): 00 disabled (never asserts), 01 lower byte (assert when ADDR0=0), 10 upper byte (ADDR0=1), 11 both.
* R/W: 00 disabled (never asserts), 01 read only, 10 write only, 11 read/write.
* STRB (async mode): 0 assert with AS, 1 assert with DS. In fast-termination write cycles DS is not asserted, so STRB must be 0 there.
* DSACK: `0000..1101` = internal DSACK with 0..13 wait states, i.e. cycle = **3 + n clocks** (0000 = 3 clks, 0001 = 4, ..., 1101 = 16); `1110` = **fast termination, 2 clocks** ("-1 wait states"); `1111` = external DSACK (waits indefinitely, unless bus monitor BME times it out). Wait states are inserted from state S3. If an external DSACK arrives during internal wait states the cycle ends immediately. Port width reported = 8/16 bit as in CSPAR field.
* SPACE: 00 CPU space (used for IACK strobes), 01 user, 10 supervisor, 11 supervisor/user. CPU16 is always supervisor (FC=%101 data / %110 program, %111 CPU space), so SPACE=01 never matches normal accesses.
* IPL (only if SPACE=00): 000 any level, 001-111 = assert only for IACK at that level (compared to ADDR[3:1]). AVEC: with SPACE=00, 1 = chip select terminates the IACK with autovector, 0 = external vector (DSACK). Chip selects only respond to IACKs from external IRQ pins; internal modules answer their own IACK.
* Match logic: access matches if SPACE ok, base-address compare ok, R/W ok, BYTE ok (16-bit port), and (IACK only) IPL ok. **Internal modules and RAM/ROM arrays have priority over a CS with the same address** (no external cycle).
* Reset: **CSORBT = $7B70** = MODE 0, BYTE 11, R/W 11, STRB 0 (AS), DSACK 1101 (13 wait states = 16 clocks per access), SPACE **11** (Z1 Table 5-26 prints "supervisor space" but the register diagram and SIMRM Table 8-4 give %11), IPL 000, AVEC 0. CSOR0-10 = **$0000** (BYTE/R/W = 0: disabled; DSACK 0 wait states, SPACE CPU space, IPL any, AVEC 0).
* CSBOOT is the only select active at reset: it selects the vector fetch from $000000 (first access ~10 CLKOUT after RESET release, FC=%110 supervisor program).

### 1.9 Bus cycle clocks  (Z1 5.6, D-15; SIMRM 5, 7.5)
* Internal module / internal RAM access (IMB): **2 system clocks**, no wait states (Z1 5.6 "typically accessed in two system clock cycles"; GPT/ADC/QSM/SIM registers all behave this way for emulation).
* Regular external cycle: **3 clocks + wait states** (min 3 if DSACK asserted by S2; extra clocks 1 each until DSACK). Chip-select internal DSACK: 3+n (n=0..13). Fast termination: **2 clocks**, internal handshake.
* 16-bit operand to 8-bit port = two byte cycles (each 3+n / 2 clocks), long word to 16-bit port = two word cycles, to 8-bit port = four byte cycles; misaligned word = two cycles. (Z1 5.5.5.) CPU16 prefetch/instruction timing is the CPU's business.
* Bus monitor: DSACK/AVEC response limit 64/32/16/8 clocks (BMT) -> BERR; monitor does not reset until both bytes of a word-to-8-bit transfer complete, so BMT period must be >= 2 byte cycles.
* IACK cycles are read cycles in CPU space; internal-module IACKs terminate with internal DSACK, so no external cycle.

---------------------------------------------------------------------------------------------------

## 2. GPT  ($FF900-$FF93F)  (Z1 D.8 + 11; GPTRM 3-9)

### 2.1 Register map and reset values (byte/word access both fine; word accesses are coherent snapshots)

| Addr | Reg | Layout (15..0) | Reset | R/W |
|---|---|---|---|---|
| FF900 | GPTMCR | STOP FRZ1 FRZ0 STOPP INCP 0 0 0 SUPV 0 0 0 IARB[3:0] | **$0080** | R/W (see 2.9) |
| FF902 | GPTMTR | test | 0 | - |
| FF904 | ICR | `15:12 IPA`, 11 0, `10:8 IPL`, `7:4 IVBA`, 3:0 0 | $0000 | R/W |
| FF906 | DDRGP | `7:0` DDGP7..0 (bit n = pin n; GP7=IC4/OC5, GP6..3=OC4..OC1, GP2..0=IC3..IC1) | $00 | R/W |
| FF907 | PORTGP | bit n = GPn | $00 (reads pins) | R/W |
| FF908 | OC1M | `7:3` = OC1M5..OC1M1 (bit7 = OC5 ... bit3 = OC1), `2:0` 0 | $00 | R/W |
| FF909 | OC1D | `7:3` = OC1D5..OC1D1, `2:0` 0 | $00 | R/W |
| FF90A | TCNT | 16-bit counter | $0000 | **read-only** (writable in freeze/test only) |
| FF90C | PACTL | 7 PAIS(ro) 6 PAEN 5 PAMOD 4 PEDGE 3 PCLKS(ro) 2 I4/O5 1:0 PACLK | $00 (PAIS/PCLKS reflect pins) | R/W except ro bits |
| FF90D | PACNT | 8-bit | $00 | R/W |
| FF90E,10,12 | TIC1,TIC2,TIC3 | 16-bit | $FFFF | read-only |
| FF914,16,18,1A | TOC1..TOC4 | 16-bit | $FFFF | R/W |
| FF91C | TI4/O5 | IC4 capture (ro, when I4/O5=1) or OC5 compare (rw, when I4/O5=0) | $FFFF | |
| FF91E | TCTL1 | 7:6 OM5/OL5 (bit7=OM5, bit6=OL5), 5:4 OM4/OL4, 3:2 OM3/OL3, 1:0 OM2/OL2 | $00 | R/W |
| FF91F | TCTL2 | 7:6 EDG4B/A, 5:4 EDG3B/A, 3:2 EDG2B/A, 1:0 EDG1B/A | $00 | R/W |
| FF920 | TMSK1 | 7 I4/O5I 6 OC4I 5 OC3I 4 OC2I 3 OC1I 2 IC3I 1 IC2I 0 IC1I | $00 | R/W |
| FF921 | TMSK2 | 7 TOI 6 0 5 PAOVI 4 PAII 3 CPROUT 2:0 CPR[2:0] | $00 | R/W; **CPR write-once** (except freeze/test) |
| FF922 | TFLG1 | 7 I4/O5F 6 OC4F 5 OC3F 4 OC2F 3 OC1F 2 IC3F 1 IC2F 0 IC1F | $00 | flags |
| FF923 | TFLG2 | 7 TOF 6 0 5 PAOVF 4 PAIF 3:0 0 | $00 | flags |
| FF924 | CFORC | 7 FOC5 6 FOC4 5 FOC3 4 FOC2 3 FOC1 2 0 1 FPWMA 0 FPWMB | $00 | R/W; FOC bits write-only strobes, read 0 |
| FF925 | PWMC | 7 PPROUT 6:4 PPR[2:0] 3 SFA 2 SFB 1 F1A 0 F1B | $00 | R/W; F1A/F1B read = state of PWMA/PWMB pin |
| FF926 | PWMA | 8-bit duty | $00 | R/W |
| FF927 | PWMB | 8-bit duty | $00 | R/W |
| FF928 | PWMCNT | 16-bit | $0000 | read-only (freeze/test writable) |
| FF92A | PWMBUFA | 8-bit | $00 | read-only |
| FF92B | PWMBUFB | 8-bit | $00 | read-only |
| FF92C | PRESCL | 9-bit (bits 8:0), 15:9 read 0 | $0000, **reset only at power-on** | read-only (freeze/test writable) |
| FF92E-3F | reserved | | | |

(Z1 map prints PORTGP as "$YFFE06": a typo, correct is $YFF906/907. TCTL1/TCTL2 etc. are byte pairs inside the words at FF91E, FF920, FF922, FF924, FF926; word accesses cover both.)
SUPV=1 at reset has no effect on CPU16.

### 2.2 TCNT clocking, prescaler  (GPTRM 3.1, 5.1)
* A 9-bit free-running prescaler counts system clocks; taps give fsys/2, /4 ... /512. Reset TCNT clock = fsys/4 (CPR=000).
* TCNT clock select CPR[2:0] (TMSK2): 000 /4, 001 /8, 010 /16, 011 /32, 100 /64, 101 /128, 110 /256, 111 PCLK (external pin, synchronised and filtered: pulses >2 sysclk pass, <1 ignored). **CPR can be written once after reset** (further writes ignored) unless freeze/test mode. CPROUT=1 drives the selected clock out of the OC1 pin (high for one sysclk per period).
* PWM counter clock PPR[2:0] (PWMC): 000 /2, 001 /4, ..., 110 /128, 111 PCLK; writable any time. PPROUT drives it out of PWMA.
* PRESCL = the 9-bit counter value (read-only). Each tap divider is bit (k-1) of the prescaler; the timer increments when the selected tap bit falls. Emulate by counting fsys cycles and incrementing TCNT every 4/8/..256 cycles aligned to the prescaler count. Changing the prescaler select while running may cause one extra count.
* STOPP=1 (GPTMCR): prescaler and pulse accumulator stop, input pin changes ignored; INCP=1 (self-clearing) then single-steps the prescaler once and clocks the input synchronizers. STOP=1: all counters stopped, only MCR/ICR accessible (others undefined). FRZ0=1 + FREEZE: same as STOPP while in BDM, and read-only/write-once bits become writable.

### 2.3 Timer overflow
TOF (TFLG2.7) set when TCNT goes $FFFF->$0000. Interrupt if TOI. Source TO.

### 2.4 Output compares OC1..OC5  (GPTRM 3.3)
* Compare: when TCNT (after incrementing) equals TOCx, OCxF (TFLG1) is set (same clock) and then the pin action happens (Fig 11-6: flag then pin change). OC5 uses TI4/O5 (only when PACTL.I4/O5=0; reset state). Writing TOCx does not by itself cause a compare (the logic suppresses false compares on write); match fires when TCNT next equals the value (TOC reset $FFFF).
* Pin action for OC2, OC3, OC4, OC5 from TCTL1 OMx:OLx: 00 disconnected (pin is GP I/O under DDRGP/PORTGP), 01 toggle, 10 clear, 11 set. When OMx:OLx != 00 the pin is an output regardless of DDRGP; writes to PORTGP are latched but do not reach the pin until the OC is disconnected and DDR=1.
* **OC1**: no OM1/OL1 bits. OC1 match sets OC1F and applies to every pin selected in OC1M: OC1Mn=1 -> pin n set to OC1Dn (0 clear, 1 set). Affects OC1..OC5 pins (OC1M5..OC1M1). If OC1 and another compare hit the same pin on the same count, **OC1 wins**. OC1 pin otherwise driven by OC1M/OC1D bit 1.
* CFORC.FOCx (write 1): performs the programmed pin action for OCx immediately (OC1 -> OC1M/OC1D action; others -> OMx:OLx), **OCxF is not set**. Bits self-clear, read 0. Not meaningful for toggle mode (warning in manual).
* Flags/interrupts: OCxF in TFLG1 (OC1F bit3, OC2F bit4, OC3F bit5, OC4F bit6, I4/O5F bit7), enables OCxI in TMSK1 at the same bit position.

### 2.5 Input captures IC1..IC4  (GPTRM 3.2, 3.4)
* TCTL2 EDGxB:A: 00 disabled, 01 rising, 10 falling, 11 either. IC1..IC3 = pins GP0..2; IC4 = GP7 (only when PACTL.I4/O5=1; if I4/O5=0 the pin is OC5).
* On a selected edge (after synchroniser/filter, a few sysclk of delay): TICx <- TCNT (latched on the half-cycle opposite to the increment), ICxF set. **A capture occurs on every edge, even if ICxF is already set**, so TICx holds the latest edge. Flags: ICxF in TFLG1 bits 0..2, I4/O5F bit 7. Writes to PORTGP bit of an IC pin that is an output can cause a capture (pin written = edge).
* TIC1-3 read-only. TI4/O5 in IC4 mode read-only (except freeze/test).

### 2.6 Pulse accumulator  (GPTRM 4; brief)
* PAEN enables. PAI pin = GP... dedicated input; PAIS (PACTL.7) and PCLKS (PACTL.3) read the pin levels (also usable as GP inputs).
* PAMOD=0 event counting: each active edge on PAI (PEDGE 0 = falling, 1 = rising) increments PACNT and sets PAIF. PAMOD=1 gated: PACNT is incremented by the clock selected by PACLK (00 fsys/512, 01 same as TCNT clock, 10 TOF event, 11 PCLK) while PAI is in the active state (PEDGE=0: PAI high counts, i.e. "zero on PAI inhibits"; PEDGE=1: PAI low counts); PAIF set when PAI goes from active to inactive. PACNT $FF->$00 sets PAOVF. Enables PAOVI, PAII (TMSK2). Max external rate fsys/4.

### 2.7 Flag clearing protocol  (GPTRM 7.1.2, Z1 D.8.13)
All flags (TFLG1, TFLG2) are set only by hardware. Clear = **read the register with the flag set, then write 0 to that bit** (writing 1 does nothing). If a new event sets the flag between the read and the write the flag is NOT cleared. Model: on a read, remember `armed = flags_set_now`; on a write of byte value v, `flags &= ~(armed & ~v)`, then `armed = 0` for written bits (UNSURE about exact arming granularity; simple approximation = write 0 clears the bit if it was set at the previous read). Flags are not cleared by IACK; interrupt stays pending until cleared in the ISR.

### 2.8 Interrupts  (GPTRM 7.1; Z1 D.8.3, Table D-43)
* Request raised for source x iff flag x AND enable x. 12 vector slots, 11 sources: IC1(1) IC2(2) IC3(3) OC1(4) OC2(5) OC3(6) OC4(7) IC4/OC5(8) TOF(9) PAOVF(10) PAIF(11).
* ICR: `IPA[3:0]` (called PAB in GPTRM), `IPL[2:0]` (IRL; 0 = GPT interrupts disabled, 7 = highest), `IVBA[3:0]` = vector number high nibble.
* On IACK at level IPL, if the GPT wins IARB (GPTMCR.IARB != 0 and highest): it returns **vector = (IVBA << 4) | source_number**, source number = hard-wired order above where IC1 is highest priority (1) down to PAIF (11) lowest. Highest-priority pending source is chosen; the vector is held steady during the IACK.
* **Priority adjust IPA (1..11)**: the named source becomes top priority and its vector number low nibble becomes **0**; the other sources keep their relative order and numbers (e.g. IPA=4 -> OC1 gets vector $X0 and highest priority). IPA=0: no adjustment (source 0 "adjusted channel" never occurs). IPA 12-15: unspecified.
* If IARB=0 (reset) and the GPT requests at a level above IP mask -> CPU takes spurious interrupt ($18).

### 2.9 GPTMCR bits  (Z1 D.8.1, GPTRM 9)
STOP (15) stops module clocks; FRZ1 (14) read/write, no function; FRZ0 (13) freeze response; STOPP (12) stop prescaler; INCP (11) self-clearing single step; IARB[3:0] arbitration ID. Others 0. Reset $0080.

### 2.10 Port GP
* DDGP[7:0] (FF906): 1 = output, 0 = input. **PORTGP reads the actual pin state** (even when the pin is used by a timer function), writes go to the latch and are driven out only when DDR=1 and the OC function is disconnected for that pin. PORTGP has no separate input latch.
* PWMA, PWMB, PAI, PCLK are not part of PORTGP; PAIS/PCLKS (PACTL) give PAI/PCLK, and F1A/F1B (PWMC) give the PWM pin states (FPWMx=1: pin is a discrete output driven with F1x).

### 2.11 PWM unit  (GPTRM 6; Z1 D.8.14-17)
* Free-running 16-bit PWMCNT clocked by PPR prescaler (reset fsys/2). Channel A/B each use 8 bits of it: **fast mode (SFx=0) uses PWMCNT[7:0] -> period 256 PWMCNT counts; slow mode (SFx=1) uses PWMCNT[14:7] -> period 32768 counts.**
* **PWM frequency = f(PWMCNT clock) / 256 (fast) or / 32768 (slow)**, f(PWMCNT clock) = fsys/2^(PPR+1) (PPR 0..6) or PCLK (PPR=7). Example 16.78 MHz, PPR=0: 8.39 MHz -> 32.8 kHz fast / 256 Hz slow (Z1 Table D-50).
* Waveform: when the 8-bit field rolls $FF->$00 (zero detect) the output latch is set (pin high) and **PWMBUFx is loaded from PWMx** (new duty takes effect at the end of the cycle, i.e. at the next rollover; PWMx write is buffered, PWMBUFx is read-only and shows the duty in progress); the latch is cleared when the 8-bit field == PWMBUFx. => high time = PWMBUFx counts of the 8-bit field out of 256 (in slow mode one field count = 128 PWMCNT counts).
* **PWMx = $00: pin low continuously. $80: 50%. $FF: high 255/256.** 100% duty: F1x = 1 (takes effect after the end of the current cycle; clearing F1x resumes normal operation after the current cycle).
* FPWMx=1: pin is a discrete output driven with F1x (immediately, replaces PWM; for PWMA this overrides PPROUT). F1x reads back the pin state. PPR bits are not buffered: set them before writing PWMA/B.
* Writing PWMCNT (freeze/test only) with MSB of the 8-bit field going 1->0 is seen as a zero detect.
* Reset: PWMA/B/PWMC/PWMBUF all 0, PWMCNT 0, so pins low (PWMA/B at power-up).

---------------------------------------------------------------------------------------------------

## 3. QSM  ($FFC00-$FFDFF)  (Z1 D.6, 9; QSMRM 3, 5)

### 3.1 Register map and resets

| Addr | Reg | Layout | Reset |
|---|---|---|---|
| FFC00 | QSMCR | 15 STOP 14 FRZ1 13 FRZ0(unimpl.) 7 SUPV 3:0 IARB, rest 0 | **$0080** (STOP=0, IARB=0 -> interrupts are spurious until IARB set) |
| FFC02 | QTEST | factory | 0 |
| FFC04 | QILR (byte) | `5:3 ILQSPI`, `2:0 ILSCI`, 7:6 0 | $00 (both disabled) |
| FFC05 | QIVR (byte) | `7:0 INTV`; bit 0 reads 1, writes ignored | **$0F** (uninitialized vector) |
| FFC08 | SCCR0 | 12:0 SCBR, 15:13 0 | **$0004** |
| FFC0A | SCCR1 | 15 0, 14 LOOPS 13 WOMS 12 ILT 11 PT 10 PE 9 M 8 WAKE 7 TIE 6 TCIE 5 RIE 4 ILIE 3 TE 2 RE 1 RWU 0 SBK | $0000 |
| FFC0C | SCSR | 8 TDRE 7 TC 6 RDRF 5 RAF 4 IDLE 3 OR 2 NF 1 FE 0 PF | **$0180** (TDRE=TC=1) |
| FFC0E | SCDR | 8:0 R8/T8..R0/T0 (RDR read / TDR write, same address) | RDR undefined; reads 0 above bit 8 |
| FFC15 | PORTQS (byte) | bit n = PQSn | $00 |
| FFC16 | PQSPAR (byte) | 6 PQSPA6(PCS3) 5 PCS2 4 PCS1 3 PCS0/SS 1 MOSI 0 MISO; bits 7,2 not implemented (SCK and TXD not assignable) | $00 |
| FFC17 | DDRQS (byte) | 7 TXD 6 PCS3 5 PCS2 4 PCS1 3 PCS0/SS 2 SCK 1 MOSI 0 MISO (1 = output) | $00 |
| FFC18 | SPCR0 | 15 MSTR 14 WOMQ 13:10 BITS 9 CPOL 8 CPHA 7:0 SPBR | **$0104** |
| FFC1A | SPCR1 | 15 SPE 14:8 DSCKL 7:0 DTL | **$0404** |
| FFC1C | SPCR2 | 15 SPIFIE 14 WREN 13 WRTO 11:8 ENDQP 3:0 NEWQP | $0000 |
| FFC1E | SPCR3 (byte) | 2 LOOPQ 1 HMIE 0 HALT | $00 |
| FFC1F | SPSR (byte) | 7 SPIF 6 MODF 5 HALTA 3:0 CPTQP | $00 |
| FFD00-1F | Receive RAM RR0-F | | undefined |
| FFD20-3F | Transmit RAM TR0-F | | undefined |
| FFD40-4F | Command RAM CR0-F (bytes) | | undefined |

(SPCR3: Z1 shows LOOPQ/HMIE/HALT as bits 10:8 of the word at FFC1E, so they are bits 2:0 of byte FFC1E; SPSR is the byte FFC1F.)

### 3.2 Interrupts  (Z1 D.6.3; QSMRM 3.2.3-3.2.4)
* Two sources, SCI (level ILSCI) and QSPI (level ILQSPI); level 0 = disabled. Vector number on IACK = **{INTV[7:1], 0} for SCI, {INTV[7:1], 1} for QSPI**. IARB from QSMCR (reset 0 -> spurious).
* SCI interrupt request = (TIE & TDRE) | (TCIE & TC) | (RIE & (RDRF | OR)) | (ILIE & IDLE)  (Z1 D.6.5: RIE enables RDRF and OR; NF/FE/PF have no enables). Held asserted while the condition holds (no IACK clearing; flags cleared per 3.4).
* QSPI request = (SPIFIE & SPIF) | (HMIE & (MODF | HALTA)).

### 3.3 SCI baud and frame  (Z1 D.6.4-5; QSMRM 5.2)
* **Baud = fsys / (32 * SCBR)**, SCBR 1..8191. SCBR=0 disables the baud generator. (16.78 MHz, SCBR 1 -> 524,288 baud.) Bit time = 32*SCBR/fsys; receiver samples at 16x (RT1..RT16; start bit validated with RT3,5,7, data bit = majority of RT8,9,10).
* Frame: M=0: 1 start + 8 data + 1 stop (10 bit-times); M=1: 1 start + 9 data + 1 stop (11). LSB first. PE=1: the MSB of the data field (bit 7, or bit 8 if M=1) is replaced by the parity bit (PT 0 even, 1 odd) -> 7 or 8 data bits.
* TE 0->1: TXD becomes SCI output and a **preamble of 10/11 ones** is sent first (if shifter empty; otherwise after the current frame). TE 1->0: transmitter finishes all pending frames/preamble/break, TC set, TXD reverts to PORTQS/DDRQS. TXD pin when TE=1 is forced output regardless of DDQS7. WOMS: open-drain TXD.
* SBK=1: after current frame, continuous break frames (10/11 zeros each) until SBK cleared; at least one mark bit after.
* LOOPS=1 (needs TE and RE): TX output fed to RX internally, TXD pin held high, RXD ignored.
* RWU / WAKE: RWU=1 inhibits receiver flags (RDRF.. and IDLE) and interrupts; cleared by hardware on idle line (WAKE=0) or on an address frame, MSB=1 (WAKE=1).
* ILT: 0 = count ones from any point (short), 1 = count ones only after a stop bit (long); IDLE set after 10/11 consecutive ones; not set again until after RDRF set.

### 3.4 SCSR flags and exact clearing sequences  (Z1 D.6.6; QSMRM 5.2.3)
* Receive flags (RDRF, IDLE, OR, NF, FE, PF) are cleared by: **read SCSR (either byte or word) while the flag is set, then read SCDR (low byte, byte/word/long access)**. Clears all receive flags that were set at the time of the SCSR read.
* TDRE and TC are cleared by: **read SCSR with TDRE/TC set, then WRITE SCDR (low byte, byte or word)**. The write loads TDR (clears TDRE; TC cleared, transmitter busy). Writing TDR with TDRE=0 overwrites the pending data (no TDRE protocol enforced).
* A flag set by hardware after the SCSR read but before the SCDR access is NOT cleared (needs a new SCSR read with it set, then SCDR access). Reading either byte of SCSR arms all 16 bits. Writing 0 to a flag bit does nothing. A long-word read (SCSR+SCDR consecutively) clears the receive flags set at the time but never TDRE/TC.
* Flag meanings: **TDRE** 1 = TDR empty (set when TDR content is moved into the transmit shifter; reset 1). **TC** 1 = transmitter idle, set when the shifter has completely sent the last frame including stop bit(s), and any queued preamble/break, with no new data (reset 1; cleared by the SCSR-read + SCDR-write sequence). **RDRF** set when the receive shifter is transferred to RDR at the end of the stop bit; NF/FE/PF set at the same time (they describe the data in RDR). **OR**: shifter ready but RDRF still set: transfer inhibited, RDR keeps old data, the new frame is lost, OR set (NF/FE/PF not set with OR). **RAF** set at RT1 of a possible start bit, cleared when the chosen idle condition is detected or the start bit is rejected as noise (not software-clearable). **FE**: stop bit sensed 0 (a break sets FE and RDRF). **NF**: disagreement among samples on start/data/stop. RE=0 inhibits RDRF/IDLE/OR/NF/FE/PF being set.
* Timing: TDR->shifter transfer (TDRE set) occurs when the shifter finishes the previous frame (or immediately/at next bit boundary if idle, after any preamble); TC sets one frame-end (end of stop bit) after the last transfer. UNSURE: exact bit-time at which TDRE sets when the shifter is idle (presumably at the start of the new frame, i.e. one write immediately after a TDRE-cleared idle transmitter makes TDRE go back to 1 almost at once). Frame time = (10|11) * 32 * SCBR / fsys.
* SCDR read: R8 in bit 8 only meaningful for M=1.

### 3.5 Port QS  (Z1 D.6.8-9)
* PORTQS read returns **the pin values**; write goes to the latch, driven where DDRQS=1 (pin is I/O). Write PORTQS before setting DDRQS. RXD is a dedicated SCI input pin (not part of PORTQS); PQS7 is the TXD pin.
* PQSPAR bit = 1 assigns MISO(0), MOSI(1), PCS0/SS(3), PCS1(4), PCS2(5), PCS3(6) to the QSPI; 0 = I/O. DDRQS still sets direction (e.g. MISO master: DDQS0=0 input; MOSI master: DDQS1=1 output; slave reversed; PCS1-3 outputs need DDQS=1; PCS0/SS master input = mode fault, output = chip select).
* **SPE (SPCR1.15)**: when 0 the QSPI is disabled and all its pins are plain I/O; when 1 the pins allocated by PQSPAR are QSPI controlled and **PQS2 becomes SCK** (SCK is not in PQSPAR, always QSPI when SPE=1; direction by MSTR: master output, slave input). TXD: PQS7 becomes TXD when SCCR1.TE=1.
* QSPI summary: SCK = fsys/(2*SPBR) (SPBR 0/1 disables); BITS[3:0]=0000 -> 16 bits, 1000..1111 -> 8..15, 0001-0111 reserved (8); queue of 16 commands (CR: CONT, BITSE, DT, DSCK, PCS3..PCS0), executes NEWQP..ENDQP, TR/RR words right-justified, sets SPIF at ENDQP end, CPTQP = last completed command, HALT/HALTA, WREN/WRTO wraparound; delay before SCK = DSCKL/fsys (DSCK=1) else 1/2 SCK period; delay after transfer = 32*DTL/fsys (DT=1; DTL=0 -> 8192/fsys) else 17/fsys. SPCR2 is buffered (new values apply after the current transfer; writing NEWQP restarts at that entry). Not needed if the firmware does not use the QSPI.

---------------------------------------------------------------------------------------------------

## 4. ADC  ($FF700-$FF73F)  (Z1 D.5 + 8; ADCRM 3, 5)

### 4.1 Map and resets
| Addr | Reg | Layout | Reset |
|---|---|---|---|
| FF700 | ADCMCR | 15 STOP, 14:13 FRZ[1:0], 7 SUPV | STOP=1 after reset. Z1 reset row "1 0 0 1" = STOP 1, FRZ 00, SUPV 1 -> **$8080** (ADCRM shows SUPV 0 -> $8000; SUPV has no effect) |
| FF702 | ADCTEST | factory | 0 |
| FF707 | PORTADA (byte) | PADA7..0 | reflects pins |
| FF70A | ADCTL0 | 7 RES10, 6:5 STS[1:0], 4:0 PRS[4:0] | **$0003** (8-bit, STS 00 = 2 clk, PRS 3 = fsys/8) |
| FF70C | ADCTL1 | 6 SCAN, 5 MULT, 4 S8CM, 3 CD, 2 CC, 1 CB, 0 CA (bit 7 unused) | $0000 |
| FF70E | ADCSTAT | 15 SCF, 10:8 CCTR[2:0], 7:0 CCF7..CCF0 | $0000, read-only |
| FF710-1E | RJURR0-7 | right-justified unsigned | |
| FF720-2E | LJSRR0-7 | left-justified signed | |
| FF730-3E | LJURR0-7 | left-justified unsigned | |
(All result registers read-only, undefined/0 until written by a conversion.)
STOP=1 (reset state): ADC clock disabled, registers still accessible, any conversion aborted; firmware must clear STOP (recovery time needed for analog bias). Writes to ADCTL1 while STOP=1: UNSURE, treat as no conversion.
FRZ (FREEZE only, ignore): 00 ignore, 10 finish conversion then freeze, 11 freeze immediately.

### 4.2 Clock and conversion time  (Z1 D.5.4; ADCRM 5.1-5.3)
* **ADC clock = fsys / (2 * (max(PRS,1) + 1))**: PRS=0 acts as 1 (fsys/4), 1 -> /4, 2 -> /6, 3 -> /8, ..., 31 -> /64. (Valid ADC clock 0.5-2.1 MHz.) Z1 Table D-27 lists %00000 as reserved; ADCRM says it behaves as 1.
* **Conversion time per result (ADC clocks) = 2 (initial sample) + 2 (transfer) + S (final sample) + R (resolution)**, S = 2/4/8/16 for STS = 00/01/10/11, R = 10 (RES10=0, 8-bit) or 12 (RES10=1, 10-bit).
  Totals: 8-bit 16/18/22/30; 10-bit 18/20/24/32 ADC clocks for STS 00/01/10/11. In system clocks multiply by 2*(PRS'+1).
* A sequence = 4 or 8 conversions back-to-back (no inter-conversion gap documented): total = N * conversion time. Each result (and its CCF) appears at the end of its conversion (Fig 5-1/5-2: result transferred and CCF set at EOC).

### 4.3 Control, modes, channel order  (Z1 D.5.5; ADCRM 5.5-5.7)
* **A write to ADCTL1 starts a new conversion sequence immediately; if a sequence is in progress it is aborted and SCF and all CCF flags are reset** (and CCTR -> 0). ADCTL1 is also readable. Writes to ADCTL1 with STOP=0 only.
* ADCTL0 write: Z1: "writes have immediate effect" (applies to the next conversion); ADCRM 5.7: "aborts conversion and ADC activity halts until a write to ADCTL1" (differ - see 5). Recommended: abort current conversion without starting a new one.
* Modes (SCAN,MULT,S8CM): 0 single 4-conv single-channel (4 samples of one channel -> RSLT0-3); 1 single 8-conv single-channel (RSLT0-7); 2 single 4-conv multichannel (4 channels, RSLT0-3); 3 single 8-conv multichannel (8 channels, RSLT0-7); 4-7 same but **SCAN=1 = continuous**: the sequence restarts automatically and overwrites the results.
* Channel select (CD:CA = value 0..15). Input numbers: 0-7 AN0-AN7; 8-11 reserved (convert as... unspecified, return 0/anything); 12 (%1100) VRH; 13 VRL; 14 (VRH-VRL)/2; 15 test/reserved.
  * **MULT=0 (single channel):** all 4 (S8CM=0) or 8 (S8CM=1) conversions use the single input selected by CD:CA (S8CM=1 uses the full 4-bit field; table rows identical).
  * **MULT=1, S8CM=0 (4 channels):** CD:CC selects the group, CB:CA ignored: %00 -> AN0,AN1,AN2,AN3 into RSLT0..3; %01 -> AN4..AN7 into RSLT0..3; %10 -> reserved x4; %11 -> VRH, VRL, (VRH-VRL)/2, test into RSLT0..3.
  * **MULT=1, S8CM=1 (8 channels):** CD selects: CD=0 -> AN0..AN7 into RSLT0..7; CD=1 -> reserved x4 into RSLT0-3, then VRH, VRL, (VRH-VRL)/2, test into RSLT4..7. CC:CA ignored.
* ADCSTAT: **CCTR** = index of the next result register to be written (the channel being converted), counts 0..3 or 0..7; **CCFn** set when result n is written, cleared when result register n is read (any of the three formats, RJURRn/LJSRRn/LJURRn - UNSURE if any format clears; manual says "result register containing the converted value is read"); **SCF** set at end of the sequence (SCAN=0) or at the end of the first sequence only (SCAN=1); cleared by an ADCTL1 write (new sequence starts). ADCSTAT is read-only.
* SCAN=1 at end of a sequence: restart from the first channel/result register 0 automatically, results overwritten, CCFs set again (CCFn already set stay set until read), SCF stays set (set after the first sequence, only cleared by ADCTL1 write), CCTR wraps to 0. Single mode: stops, CCTR holds (UNSURE: reads 0 or N after the end).

### 4.4 Result formats (Z1 D.5.7-9; ADCRM 5.8)
Each conversion result r (8 or 10 bit) is read at 3 addresses:
* RJURR ($FF710+2n): unsigned right-justified: 10-bit: bits 9:0 = r, bits 15:10 = 0; 8-bit: bits 7:0 = r, bits 15:8 = 0.
* LJURR ($FF730+2n): unsigned left-justified: 10-bit: bits 15:6 = r, 5:0 = 0; 8-bit: bits 15:8 = r, 7:0 = 0.
* LJSRR ($FF720+2n): signed left-justified: same bit placement as LJURR but with the MSB inverted (zero reference (VRH-VRL)/2): value = r XOR (1<<(n-1)) placed left-justified. 8-bit: +full scale $7F, mid $00, zero-1 count $FF, -full scale $80 (upper byte).
* Result code (UNSURE, standard SAR): r = clamp(floor((Vin - VRL) / (VRH - VRL) * 2^n), 0, 2^n - 1), n = 8 or 10 (1 LSB = (VRH-VRL)/2^n). So VRH -> $FF/$3FF, VRL -> 0, (VRH-VRL)/2 -> $80/$200 (nominal; hardware may read one count lower). Vin clipped to VRL..VRH.

### 4.5 Port ADA
PORTADA ($FF707): read returns the digital (logic-level) state of pins AN7..AN0 (PADA7..0), any time, even during a conversion or when the pin is also used as an analog input. Input-only (writes ignored). Port ADB does not exist on the Z1. Reads of pins at mid-level are indeterminate (emulate as threshold on the modelled analog voltage, e.g. > ~VDD/2 -> 1).

### 4.6 Interrupts
**The ADC has no interrupt on the Z1** (no IARB/interrupt registers; ADCRM has no interrupt section; ADCRM/Z1 register maps contain no ILR/IVR). Firmware polls ADCSTAT (SCF/CCF).

---------------------------------------------------------------------------------------------------

## 5. Manual differences, ambiguities and UNSURE items (for review)

1. **SYNCR**: Z1 has RSVD at bits 4 and 2 and SLOCK at bit 3; SIMRM's generic SIM has SLIMP (4) and RSTEN (2). Z1 followed. SYNCR has no write-once bits in either manual; SLOCK semantics after relock not specified.
2. **SIMCR bit 11**: Z1 "RSVD" (reads DATA11 sampled at reset; must stay 0); SIMRM calls it SLVEN (slave/factory mode).
3. **CSORBT SPACE**: Z1 Table 5-26 says "supervisor space" but the register diagram and SIMRM say %11 (supervisor/user): reset value $7B70 used. BLKSZ=111: Z1 512 KB, SIMRM 1 MB (compares ADDR[23:20] only).
4. **SYPCR write-once**: Z1 "after power-on or reset", SIMRM "power-on or external reset" (watchdog reset behaviour unclear). Implementation: allow one write after any reset.
5. **PEPAR bit 3**: Z1 5.10.1 "returns one when read", Z1 D.2.8 "can be read and written, no function".
6. **Spurious vector**: SIMRM 6.4.3 says "spurious interrupt vector number ($F)"; CPU16RM Table 9-1 and Z1 vector table: spurious = $18, $0F = uninitialized. $18 used.
7. **ADC**: ADCTL0 write aborts-and-halts (ADCRM) vs immediate effect (Z1 D.5.4). ADCRM's generic register offsets (PDR $02, test $06) are not used on the Z1; Z1 map: ADCTEST $702, PORTADA $706/707.
8. **QSM**: QSMCR FRZ bit naming differs (Z1: FRZ1 = FREEZE halts QSPI, FRZ0 not implemented; QSMRM same). SCSR/SCDR high bits: SCSR bits 15:9 read 0.
9. **PIT clear on IACK**, SWSR wrong-sequence behaviour, exact TDRE timing while idle, TC during preamble, ADC result code at exactly mid-scale, ADC behaviour when STOP=1 and ADCTL1 is written, CCF clearing from each result alias, TFLG arming granularity: not stated in the manuals (UNSURE, noted inline).
10. PEPAR/PFPAR/CSPAR reset values depend on data bus pull-ups (default $FF/$FF/$03FF/$03FF); a board that holds DATA lines low at reset (e.g. the Moppe board's latches) changes them: take them from the board design.
11. Z1 PITR/SYPCR diagram reset label "MODCLK" for PTP/SWP: tables 5-9, 5-11 define them as the complement (MODCLK=0 -> prescaled by 512).
12. SYNCR formula superscripts were lost in the text extraction; they were verified against the 16.78 MHz multiplier table (Z1 Table 5-2: Y=0,W:X=00 -> 4; W:X=11 -> 32; Y=63 W:X=00 -> 256) and the $3F00 -> 8.388 MHz statement.
13. Software watchdog ratio exponents (2^9...2^24) were also checked against Table 5-10 (text-extraction lost the superscripts).
