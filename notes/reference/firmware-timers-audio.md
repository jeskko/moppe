> Provenance: written 2026-09-28 by a research subagent from the firmware source
> (line numbers `Lnnnn` = unmodified `reference/r58.asm.als`) or the scanned manuals.
> Items the emulator tests exercise are confirmed; everything else is as-read.
> Corrections found since: see notes/hardware.md.

# R58 firmware: timers, audio, ADC/DAC, modem, interrupts. A spec for emulator writers

Source: `firmware/r58.asm` (v3_Z ALs, 24.09.2018). Build `-DP8x` defines both P8N and P8E (r58.asm:384-387).
Line numbers are `r58.asm` lines. Addresses come from `firmware/build/r58.lst` (symbol table at the end, `# name l 0xADDR`).
"FW expects" means the firmware assumes this but does not prove it. Anything marked (inferred) is my own reading.

---------------------------------------------------------------------------
## 0. I/O map and constants (r58.asm:496-566)

| port | name | use |
|---|---|---|
| 0x00-03 | PIO A data/B data/A ctrl/B ctrl (ADATA=0,BDATA=1,ACTRL=2,BCTRL=3) | 508-511 |
| 0x10-13 | SIO A data/B data/A ctrl/B ctrl | same offsets |
| 0x20-23 | 8254: counters 0,1,2 at +0..+2, control at +3 (`TMRCTRL`=3, line 513) | |
| 0x30 | DA0 = `DA_RFC` (write) | 524 |
| 0x40 | DA1 = `DA_TXPWR` (write) | 525 |
| 0x50-57 | AD: OUT selects mux and starts a conversion; IN reads the result | 515-522 |
| 0x60/0x70/0x80 | OUT0/OUT1/OUT2 latches (write-only) | 500-502 |
| 0x90 | WD: any write retriggers the watchdog. Also used as a timing dummy | 503 |
| 0xA0-A3 | FX429: only +2 (`MDMDATA`) and +3 (`MDMCTRL`) are used | 504, 531-532 |
| 0xB0 | CSMEM: `out 1` selects the full 16k RAM page on P8E (a nop on P8N) | 506, 1075-1076 |
| mem 0x80xx (read) | second-ROM-socket "multiboard": DTMF 8870 + CTCSS slicer | 7-9, 1916, 3150 |

8254 control-word constants (556-566): `TMR_0/1/2` = 0x00/0x40/0x80; modes `INTTC`=0 (mode 0), `ONESHOT`=2, `RATEGEN`=4, `SQWAVE`=6 (mode 3), `SWTRIGG`=8; RW `LSB`=0x10, `MSB`=0x20, `BOTH`=0x30. BCD is never used. The latch command (RW=00) and the read-back command (0xC0-0xFF) are never used.

The clocks are stated at 881-885: "All timer-gates are fixed on. timer-clocks 0 and 1 are 4.032 MHz, 2 is 1968.75 Hz. System hz is 100, from PIO A0 change-interrupt 1968.75 Hz". The gates are hard-wired high. `MT_CALCHZ(f) = 4032000/f` (887).

---------------------------------------------------------------------------
## 1. 8254 usage

### 1.1 Every TMR access (assembled code only)

| line | routine | access | meaning |
|---|---|---|---|
| 1560 | start_continue | `in a,[TMR+3]` | "dummy read to raise PIO B5 (remove int)" |
| 1765 | sioa_esc | `in a,[TMR+3]` | same dummy read, done on every SIO-A ext/status interrupt |
| 9885-9888 | beep1750 | ctr1 LSB, MSB = MT_1750HZ (2304) | 1750 Hz tone burst |
| 9929-9932 | tx_tune_tone_maybe | ctr1 LSB, MSB = 4032000/cfg_txtune_hz | TX test tone |
| 10025-10030 | ccir_from_digbuf | ctr1 LSB, MSB from `ccirtbl` | CCIR selcall tone, 100 ms each |
| 10413-10418 | init_LPF | ctrl 0x36 (ctr0, BOTH, mode 3); ctr0 LSB, MSB | clock for the TX-audio switched-capacitor LPF |
| 10435-10436 | init_timer1 | ctrl 0x76 (ctr1, BOTH, mode 3) | marker/CCIR tone generator |
| 10438-10442 | silence_timer1 | ctr1 LSB=0x04, MSB=0x00 | "silence" = 1.008 MHz square wave ("leaks anyway") |
| 10573-10576 | start_marker_tone | ctr1 LSB, MSB = pitch (HL) | marker tones, blips, CW, notes |
| 13460-13463 | ctcss_off_nohang (method i8254) | ctrl 0x90 (ctr2, LSB, mode 0); ctr2=1 | "low for one clock, then rise and stay": OUT2 parks high |
| 13500-13506 | ctcss_maybe (method i8254) | ctrl 0xB6 (ctr2, BOTH, mode 3); `outi` x2 to 0x22 | CTCSS square wave on OUT2 |
| 14463-14464 | dtmf_bang_tone | ctrl 0x50 (ctr1, LSB, mode 0) | PWM DTMF |
| 14484 / 14524 | DTMF P8N / P8E loop | ctr1 LSB = PWM value, every 130 timer clocks | |
| 14601-14602 | emit_ax25_packet | ctrl 0x50 (ctr1, LSB, mode 0) | PWM AFSK |
| 14670 / 14733 | AX.25 P8N / P8E loop | ctr1 LSB = PWM value, every 168 (P8N) or 140 (P8E) timer clocks | |
| 14538, 14606 | after DTMF/AX.25 | `call init_timer1` | back to mode 3, count 4 |
| 14800-14811 | check_for_P8E_cpu | ctrl 0x50; ctr1=65; 20 NOPs; `in a,[TMR+1]` | CPU-card detection |

The FX614/TCM3105 code at 13916-14039 is inside `#if 0` and is not assembled. It would have read and written ctr2 (13920, 13923) and put ctr2 in mode 0 MSB-only (14030-14034).

### 1.2 Counter 0: TX-audio low-pass filter clock (not CTCSS)
- init_LPF (10401-10419): `N = 2016 / (cfg_lpf_hz/20)`, using integer div248 twice. Mode 3, 16-bit. Comment 10395-10399: "4032000 / N = LPF CLK ... = Hz*100", so the clock is 100x the cutoff. The default `cfg_lpf_hz` is 3600 (REC at 18037, "tx audion alipäästö" = TX audio low-pass), giving N=11 and a 366.5 kHz clock.
- Called from main (3258) and from update_LPF in tx_on (13035), which reinitialises only if the setting changed (10421-10429).
- If cfg_lpf_hz=0 (blank NVRAM), div248 divides by C=0 and returns HL=0xFFFF, a ~61.5 Hz clock. That kills TX audio but does no other harm.
- emit_ax25_packet assumes "LPF is not touched, assumed to be above 2200 Hz" (14570).
- Emulator: timer OUT0 (not the OUT0 latch) only matters for audio fidelity. Treat the LPF cutoff as f(timer OUT0)/100.

### 1.3 Counter 1: the "CCIR/MARKER pin" tone generator (14303)
- Normal state is mode 3, 16-bit (init_timer1, 10434). Tone frequency = 4.032 MHz / N. Idle N=4 (silence_timer1).
- Pitch changes write LSB then MSB with no new control word, usually under `di`.
- Where OUT1 goes is decided by OUT0 bits: CCIRC routes the tone to the TX modulator, MTC routes it to the local speaker (see §2).
- It is temporarily switched to mode 0 LSB-only for PWM (DTMF/AX.25), then restored by init_timer1.

### 1.4 Counter 2
- The hardware CLK2 is 1968.75 Hz, the same net as PIO A0 (`PA_CLK2` = 0x01, line 696).
- Boot (1135) calls ctcss_off_nohang, which normally leaves ctr2 in mode 0 with count 1, so OUT2 rises after one clock and stays high.
- CTCSS method "i8254" (cfg_ctcss_output_method=0, tab at 18268) needs a hardware mod. Comment 13400-13406: "OUT2 emits CTCSS square wave. This needs a rewire of the timer CLK2 from the same place as CLK0 and CLK1, 4.032 MHz ... Please cut the CLK2 wire into 'keskeytyskytkenta' (interrupt circuit)." So after the mod, CLK2 = 4.032 MHz and PA0 still gets 1968.75 Hz from its original source.
- Counts come from `ctcss_counter_counts` (13555, addr 0x4EE0): `.word 0` for "oFF", then `40320000/dHz` for 42 tones (67.0 ... 254.1 Hz, list at 13508-13551). The table is indexed by `cfg_ctcss_tx_hz`, which is a TAB index (17749, tab 18279-18282), not Hz.
- Where OUT2 goes: sioa_esc's header says "SIO A ext/status change - CU53_DA or CU58AF_INT, HK, Modem and timer OUT2" (1754). So OUT2 is (FW expects) wired to an SIO-A ext/status input. The firmware never tests which pin fired. Every ESC interrupt runs the CU handler and the modem poll. A CTCSS square wave on OUT2 would therefore cause harmless ESC interrupts at twice the tone rate. The disabled FX614 note says "Side-effects of timer OUT2 should be disconnected" (13888).
- Emulator: model CLK2 as selectable (1968.75 Hz stock, 4.032 MHz modded), with OUT2 feeding the CTCSS modulation and optionally an SIO-A ext/status pin.

### 1.5 PIO B5 "TMR0" and the TMR+3 dummy read
- `PB_TMR0` = 0x20 is a PIO B input, "in CTCSS-detect" (707). Since 3.U "CTCSS detector input is now TMR0 ... TMR0 must be disconnected from old circuit before detector wire is soldered into it" (237-241). The PIO B monitor mask is 0xFF, so no PIO B interrupt is ever generated (918-919). The old 0xDF mask that watched B5 is commented out. piob_int (1885) is just `push af; doreti`.
- read_ctcss_detect (2591-2605): method 0 = DSP decoder status. Method 1 returns `PB & 0x20` (NZ when the pin is high). Method 2 returns the pin inverted. The tab labels them "-Piob5" and "Piob5" (18273-18275), and the comment at 2588 calls them "-TMR0" and "+TMR0". The labels look swapped relative to the code; implement the code as written.
- The FW expects a read of port 0x23 (8254 control address, which is not readable on a real 8254) to have a board-level side effect: it clears a latch and "raises PIO B5" (1560, 1765). For the emulator: `IN 0x23` returns 0xFF (or bus float) and optionally clears any latched PB5 interrupt source. Nothing depends on the value.

### 1.6 check_for_P8E_cpu (14791-14823, addr 0x538D; called at 1130 before init_timer1)
```
out [WD],a ; ld a,0x50 ; out [TMR+3],a ; ld a,65 ; out [TMR+1],a
20 x nop ; in a,[TMR+1] ; out [WD],a ; rlca ; and 1 ; xor 1 ; ld [cpu_is_P8E],a
```
- In mode 0 with LSB-only access, the counter counts down from 65 at 4.032 MHz and wraps past 0 (0x00 to 0xFF...). The read returns the counter LSB directly, with no latch.
- P8N: 20x4T = 80 CPU T = 80 timer clocks, about 91 counting the out/in phases. 65-91 wraps, so bit 7 = 1 and cpu_is_P8E=0.
- P8E: 20x5T = 100 T at 8.064 MHz = about 50-56 timer clocks, so the result is about 9-15 and bit 7 = 0, giving cpu_is_P8E=1.
- Emulator: the 8254 must be clocked in real time relative to CPU T-states (P8E: 1 timer clock per 2 CPU clocks, wait states included). The mode-0 counter must be readable while it runs. The margin is wide (±10 clocks).
- `cpu_is_P8E` (0xD015) selects the P8E or P8N PWM loops (14472, 14624) and the GPS BRK bit-bang padding (3503).

### 1.7 Mode-0 PWM semantics the FW relies on (14303-14334)
"Using timer mode 0; the output goes low when the count is written. After the count decrements to 0 the output rises. The loop takes 130T times, slightly longer than any written count." Each LSB write re-arms the counter: OUT goes low at the write, then high after about N clocks. N is loaded on the next CLK, so the low time is about N+1 clocks. This is 8253-style "new count reloads, OUT low". The duty cycle (low) is N/cell, and the audio is the low-pass of OUT1. Counts must stay below the cell length. AL7 fixed a bug where 65+65=130 overflowed (270-273).

---------------------------------------------------------------------------
## 2. Audio path control

### 2.1 OUT0 (0x60). Shadow copy in `output_0` (0xD000). Bits at 655-661

| bit | name | FW meaning / polarity |
|---|---|---|
| 0-2 | O0_VOLUME | speaker volume attenuator, 0..7 |
| 3 | O0_INH | 1 = speaker inhibited (boot value: `O0_INH` alone, 824-825, 1060-1062) |
| 4 | O0_AUDIOC | 1 = RX audio to speaker (squelch gate) |
| 5 | O0_CCIRC | 1 = timer-1 OUT (tone) to the TX modulator |
| 6 | O0_MTC | 1 = timer-1 OUT (marker tone) to the local speaker |
| 7 | O0_MICM | 1 = microphone muted |

The two `and` lines at 2833-2834 are intentional: `and ~AUDIOC` then `and ~CCIRC`.

Writers:
- set_vola (4793-4843): volume 0 sets INH with vol bits 0. Volume 1 sets vol 0 with INH clear. Volumes 2..9 set vol bits 0..7 with INH clear.
- audioc_on/off (2792-2804), called by squelch.
- tx_cut_local_audio (2817-2836): clears AUDIOC and CCIRC.
- mic_off_ccir_off (2842: MICM=1, CCIRC=0), mic_on (2849: CCIRC=0, MICM=0, plus silence_timer1), mic_off (2855), ccir_on (2861), ccir_off (2868, plus silence), mtc_on (2875), mtc_off (2881, plus silence). All are di/out/ei.
- ptt_ccir_xmit (9941-9978): volume bits cleared during CCIR TX.
- ding (10509-10560).
- DTMF (14459: `or CCIRC|MICM`, restored at 14541) and AX.25 (14599/14609): tones to TX, mic cut, MTC not set.
- CU58AF audio destination (11718-11738): INH set when audio goes to handset or ear.
- systick (2079-2087): while mt_timer≠0, OUT0 is rewritten from the shadow every tick.

### 2.2 OUT1 (0x70). Bits at 663-670. No shadow; each routine composes the value

`SRE`=0x01 RX-synth strobe, `SCE`=0x02 synth-control strobe, `STE`=0x04 TX-synth strobe, `CLK`=0x08 serial clock, `SD`=0x10 serial data, `RAS`=0x20 strobe for external serial A, `TPS`=0x40 strobe for external serial B and for the FX465 load, `TXOFF`=0x80 (1 = transmitter off).

- Boot writes 0x80 (826, 1066). Powerdown writes 0x80 (10083).
- tx_on (13020-13069): OUT1=0x80, DA_TXPWR=0, load TX synth, then wait `cfg_pll_delay` x `halt` (≈0.508 ms each, 13054-13060). Then **OUT1=0x00** (TX on) and DA_TXPWR = cfg_txpwr+txpwr_increment, saturating at 255 (12992-13013).
- tx_off (13073-13090): ctcss_off, then OUT1=0x80, DA_TXPWR=0.
- The synth and external-serial shifters (12827-12985) always idle with TXOFF=1. The exceptions are change_to_signalling_deviation (12724-12740) and load_fx465 (13605-13645), which keep TXOFF=0 while `[txon]`.
- Deviation is a 4-bit field (bits 7..4) of the synth control byte (synth_dev_and_ctrl_into_c, 12697): `cfg_deviation_fone` (speech, def 15) or `cfg_deviation_sign` (signalling, def 7), 18038-18039.

### 2.3 Tone generation (all on timer 1 unless noted)

| feature | code | routing | timing |
|---|---|---|---|
| marker tone | start_marker_tone 10568-10584: writes pitch, sets MTC **in shadow only**, mt_timer=D (10 ms ticks). systick copies the shadow to OUT0 on the next tick (2084); when mt_timer reaches 0, stop_marker_tone (10586-10597) clears MTC and silences | local speaker | software-timed, systick |
| key blip | blip 10445 (cfg_key_blip_pitch 1..7 → 500..3500 Hz, blip_hz 10482-10505), 3 ticks | local | |
| squelch-close blip | serv_blip 10459 (cfg_serv_blip_pitch), called at 2766 | local | |
| bleep / tx_error | 300 Hz, 100 ticks (10473, 9683-9686) | local | |
| ding (call alert) | 10509-10560: AUDIOC=0, INH=0, VOL=7, mton=1, then 5x (1200 Hz 50 ms, 1400 Hz 50 ms) | local | |
| 1750 Hz | beep1750 9871-9896: tx_on, mic_off_ccir_off, signalling deviation, ctr1=2304, CCIRC on until a key event | TX | |
| TX tune tone | tx_tune_tone_maybe 9898-9939 | TX | |
| CCIR selcall TX | ptt_ccir_xmit 9941-9978 and ccir_from_digbuf 10003-10037: 200 ms silence, then MTC+CCIRC, 100 ms per tone (ccir_tx_timer via systick 2092-2099), repeated digit sent as E. ccirtbl 13112-13128: 0=1981, 1=1124, 2=1197, 3=1275, 4=1358, 5=1446, 6=1540, 7=1640, 8=1747, 9=1860, A=2400, B=930, C=2247, D=991, E=2110 Hz, F=count 4 | TX + local | |
| CW ID / repeater blips / notes | send_cw_prolog 15956 (ccir_on, silence), cw_slots 16075 (start_marker_tone), note_to_pitch_table 16104 (500..2900 Hz, 100 ms), send_cw_epilog 15985 | TX (CCIRC) + local (MTC) | systick |
| DTMF | dtmf_bang_tone 14385-14565, PWM | TX only | **cycle-exact** |
| AX.25 AFSK 1200/2200 | emit_ax25_packet 14567-14617 + loops 14620-14773, PWM | TX only | **cycle-exact** |
| DTMF on CU58AF | dtmf_cu58af 11642: sent over I2C, generated by the control unit | not a timer | |
| CTCSS | §4.1 / §1.4 | TX | per interrupt or timer |

### 2.4 Constant-time PWM loops (run with DI; PIO interrupts are lost for the duration)

The P8E rule the firmware assumes: every M1 cycle, including each prefix byte (CB/ED/DD/FD), costs +1 T. Memory and I/O cycles add no waits. Evidence: nop 4→5, `out (n),a` 11→12, `ex (sp),hl` 19→20, `rlc d` (CB) 8→10, `adc hl,bc` (ED) 15→17, `ld a,i` 9→11 (3483, 14751-14755). AL"G" notes "replacing some double-M1 instructions" (287-290).

1. **DTMF** (14303-14565). The PWM cell is 130 timer clocks (31015 Hz). P8N loop 14476-14491 = 130 T. P8E loop 14499-14532 = 260 T (70 + padding of 9x`out [WD]` + `ld e,a` = 113, then 77). Value = dtmf_sintab[phase1>>8] + dtmf_sintab[phase2>>8]. The table is built by calculate_sintab(gain=cfg_dtmf_gain ≤31, centre 32) (14394-14397), so the sum is about 2..126. Phase increments at 14344-14352 (e.g. 697 Hz=1473, 1750=3698; 16-bit phase per 32.24 µs cell).
   - Each iteration also writes `WR0_RESET_ESCINT` to SIO A ctrl and reads RR0. The loop runs while `RR0 & CTS(SA_DA) == 0`, meaning the CU53 key is still down (inverted input) (14485-14491).
   - An emulator must latch SIO RR0 ext/status bits until reset-ESC, as the real SIO does.
   - The loop is entered from handle_key_during_tx (4617-4636) for non-alpha CUs.
2. **AX.25 AFSK** (14620-14773).
   - P8N: cell 168 T = 168 timer clocks (24 kHz), 20 cells per bit. Phase inc 1200=3277, 2200=6007. Sine centred at 84.
   - P8E: cell 280 T = 140 timer clocks (28.8 kHz), 24 cells per bit. Phase inc 1200=2731, 2200=5006. Centre 70. Uses burn_p8e_89T/105T (14761-14773).
   - Both give a bit time of 3360 timer clocks = exactly 1200 baud. Bits are NRZI: a 0 bit swaps the tone. The packet is a byte stream of pre-stuffed bits ending in 0x7F.
   - I verified every branch of both loops sums to 168 / 280 T under the rule above.
3. **GPS SiRF BRK bit-bang** (3458-3530): not audio, but cycle-exact. SIO A WR5 SEND_BREAK is toggled at 38400 baud (P8N 105 T, P8E 210 T per bit).
4. **check_for_P8E_cpu** (§1.6).

Other timing is not critical: mdm_delay is 25 nops (9356). ctcss_off hang uses `halt` (13436-13439). tx_on PLL wait uses `halt` (13058). The boot delay loops are 849-853 and 1547-1558.

---------------------------------------------------------------------------
## 3. ADC

### 3.1 Protocol: adc_reader (2000-2020, addr 0x07F4)
```
C = ad_list[i+1]  (next channel port 0x50+n)
L = ad_list[i]    (previous channel), H = HI(ad_bytes)   ; LO(ad_bytes)==AD (19474)
ini               ; IN from port C (the NEXT channel's address!) -> ad_bytes[prev]
out [c],a         ; "once to settle analog mux"
ld d,4
out [c],a         ; "start of conversion"
```
- **The FW expects an IN from any 0x50-0x57 to return the result of the last started conversion, whatever the port address.** The address of an OUT selects the mux channel and starts a conversion. If an emulator returns "the channel at the read address", every value ends up stored one slot shifted.
- The data byte written is don't-care (A = current ad_select). The ADC width is 8 bits.
- Conversion-to-read time is 4 PIO ticks (~2.03 ms). The first read after boot is garbage.

### 3.2 Cadence
- The alternate register D counts PIO ticks. systick sets E=20, D=3 (2203-2204); adc_reader sets D=4. That gives 5 ADC reads per 20 ticks, ≈492 Hz.
- ad_list (1892-1897, 0x075C): IN7, TP4, RSSI, SQL, BATT, RSSI, SQL, TPC, RSSI, SQL, FPM, RSSI, SQL, RPM, RSSI, SQL (+IN7 wrap). RSSI and SQL are each read about 154 Hz; the others about 30.8 Hz.
- Results go to ad_bytes 0xD150.. (19463-19471): rssi, sql, batt, tpc, fpm, rpm, tp4, in7.

### 3.3 Channel use and scaling

| ch | var | FW use | scaling / thresholds | "normal" value to feed |
|---|---|---|---|---|
| 0 RSSI | ad_rssi | S-meter (rssi_disp 2896-2921, shown 0..99 via dpydiv99), squelch history for sql_bi (2648-2653, 2730-2732), optional squelch source (2616), repeater peak/S-report (cfg_rssi_S1/S9 18000-18001), RFC menu display (16934) | higher = stronger. The FW defines no absolute scale | ~0x20 no signal, 0xC0-0xF0 strong |
| 1 SQL | ad_sql | squelch source 0 "SqL" (default; higher = open) or 1 "SqLnot" (inverted), 2601-2634, tab 18126 | open if sql > level+hyst/2, close if sql < level-hyst/2 (2637-2773). `squelch_tightening` subtracts | with REC defaults (level 127, hyst 4): noise ≤0x60, signal ≥0xA0. **With zeroed NVRAM (level 0, hyst 0) it opens for any sql>0, so feed 0 to keep it closed** |
| 2 BATT | ad_batt | battcheck 4376-4400, battcheck_lobatt 4344-4372, PTT loop 9621-9635 | **V = count·15.6/256** (0.061 V/count). RX: <147 (9 V) lobatt, <164 (10 V) warning icon. Recently TXed (txtail_timer≠0): <131 (8 V) lobatt, <147 warning. Lobatt recovers at ≥164, else powers down after 5 s. Initialised to 0xFF before the first conversion (1168-1169) | 13.8 V → **0xE2** |
| 3 TPC | ad_tpc | display only (18074) | – | anything, e.g. 0x80 in TX, 0 in RX |
| 4 FPM | ad_fpm | display only (18075) | – | 0 in RX |
| 5 RPM | ad_rpm | repeater "ant bad" alert if ad_rpm > cfg_rpm_limit (15685-15690, default 0) | – | **0** |
| 6 TP4 | ad_tp4 | repeater temperature alert. NTC to ground, so "A/D goes down as temperature rises" (15668, 114). Hot if ad_tp4 < cfg_temperature_limit_hot (def 0); cold if > cfg_temperature_limit_cold (def 255) (15671-15683) | – | ~0x80 |
| 7 IN7 | ad_in7 | display only (18078) | – | any |

Squelch details:
- Opening is delayed by `cfg_squelch_head` ticks, closing by `cfg_squelch_tail` (squelch_is_closed/open 2775-2790).
- If the RSSI from 20 ms ago was > `cfg_squelch_BIG` (def 255), the squelch closes with no tail (2730-2744).
- When `cfg_squelch_ctcss` is set and the RX CTCSS Hz ≠ 0, the squelch stays closed unless read_ctcss_detect is NZ (2677-2685, 2707-2717).
- squelch/rssi/ctcss/ccir/dtmf decoding is skipped for 100 ms after TX (txtail_timer ≥90) and while mton (2147-2160).

---------------------------------------------------------------------------
## 4. DACs (write-only, 8-bit)

### 4.1 DA_RFC (0x30): RX frequency correction and optional CTCSS
- rfc = rfctab[(rx_freq_kHz mod 100000)/1000], a 100-entry table in NVRAM at 0xC09A (14156-14197). The value is written by lookup_rfc (from 12156 on every frequency change), save_rfc, and menu_rfc_change (16937-16951).
- The steady state is DC = `[rfc]` (0xD0CD). The FW expects the value to be never 0 or 255 in practice (13745).
- CTCSS method "rFcdAc" (output_method=1), ctcss_generator_on (13740-13767):
  - ctcss_sintab (page 0xD800) = rfc + gain·sin, clamped so it fits in 0..255 (calculate_sintab 13681-13731; cfg_ctcss_generator_gain def 127).
  - Phase inc = Hz·8522/256 (ctcss_hz_to_phase_inc 13653-13674; 8522 = 65536/1968.75·256).
  - Every PIO-A interrupt, ctcss_enc_entry (1968-1977) outputs sintab[phacc>>8] to DA_RFC, at a 1968.75 Hz sample rate. The DAC write happens a constant ~60 T after interrupt entry, so there is no jitter.
  - Stop: jump = skip, and DA_RFC = rfc (13770-13778).
- FW quirk: ctcss_maybe passes `get_ctcss_tx_hz` (a TAB index 0..42) directly as "Hz" to the RFC and FX465 methods (13475-13491, 13750-13751, 13562-13568). Only the i8254 method indexes correctly. RX CTCSS (`cfg_ctcss_rx_hz`, a BYTE in Hz, 17750) is consistent.

### 4.2 DA_TXPWR (0x40)
- 0 whenever not transmitting: zero_txpwr at boot (3259), in tx_on before keying (13049), and in tx_off (13078).
- During TX: real_txpwr = cfg_txpwr + txpwr_increment, saturating (12992-13001). Written at 13012.
- The +/- keys during TX step it by ±26 (10052-10075). Repeater DTMF #3 adds repeater_cfg_txincr (14920-14927).
- The display shows it as 0..99 (11093-11097). The ADC TPC/FPM/RPM channels are the loop feedback, but the firmware does not close a loop in software.

---------------------------------------------------------------------------
## 5. Modem and signalling decoders

### 5.1 FX429 FFSK modem (0xA2 data, 0xA3 control/status)

Control (write) bits (534-540): `TXENB` 0x01, `TXPAR` 0x02 (unused), `RXENB` 0x04, `RXFMT` 0x08, `TIMER` 0xF0 (unused).
Status (read) bits (542-549): `RXRDY` 0x01, `RXTRUE` 0x02 (unused), `DCD` 0x04, `TXRDY` 0x08, `TXIDL` 0x10, `TMRINT` 0x20 (unused), `SYNC` 0x40, `SYNT` 0x80 (unused).

Control writes in sequence:
- 1084-1085: 0x00 at boot.
- init_modem (6012-6032): 0x04, a ~10000-iteration delay ("at least 1 bit"), then 0x00.
- main enable_modem (3254, 6044): 0x04, which means RX enabled and hunting for sync.
- re_enable_modem hourly (2526, 6034-6041): 0x00 then 0x04, and rewinds pkt_ptr.

RX is interrupt-driven through SIO A ext/status:
- sioa_esc (1758-1772) calls modem_handler (1826-1866) on **every** A-ESC interrupt. It reads status once:
  - SYNC set, RXRDY clear: rewind pkt_ptr to `packet` (0xD0EA) and call mute_fsk_at_sync_maybe.
  - RXRDY set: read MDMDATA and store at pkt_ptr++.
- After byte 2: MDMCTRL = RXENB|RXFMT (0x0C), then mute_fsk_at_tag_maybe (1859-1864).
- After byte 8: check_short_packet (9187-9222). The CRC is the X.25-style reflected table (init FFFF, complemented, **[6]=~crc_hi, [7]=~crc_lo**) over bytes 0-5. If it matches: store to fsk_history, set packet_rdy, write MDMCTRL=0x04, and rewind.
- If it does not match: continue to byte 15, check_long_packet (9224-9270). CRC over 0-12 (preceded by cfg_remote_passwd if [0]==0xEC), [13]/[14]. Always rewind and write 0x04.
- Mainline fskcheck (6003-6010) consumes packet_rdy.

FW expectations for the emulator:
- The FX429 IRQ reaches an SIO-A ext/status pin. By elimination it is probably DCD-A, `SA_KKINT` (716); CTS-A is the CU DA (717) and SYNC-A is "uncommitted" (1756). This wiring is inferred.
- Provide one ESC transition per SYNC event and per received byte. Reading status or data should drop the IRQ so the next event makes a new edge.
- "never both simultaneously" (1833): do not report SYNC and RXRDY in the same status read.
- The DCD status bit is polled by the scanner (5949-5951, skips FSK channels).

TX, polled, with interrupts on (send_packet_buffer 9301-9334):
- The caller keys TX (tx_on) and sets mic_off_ccir_off (9022-9025). The modem audio does **not** go through CCIRC.
- Write MDMCTRL=0x01. For each byte: mdm_delay, poll status until TXRDY, then write MDMDATA.
- Header 0xAA 0xAA 0xAA 0xC4 0xD7 (9336-9342), then B bytes from `outpacket` (0xDB4A); short = 8 bytes, long = 15 (19500-19501).
- Poll TXIDL, then write MDMCTRL=0x04.
- Emulator minimum: TXRDY goes true about 6.67 ms (8 bits at 1200 bd) after each data write, and TXIDL goes true once the last byte has shifted out. send_call_packet sends the short packet 3 times (9020-9044).
- The FW does not show bit order or the "RXFMT" meaning. It only needs the byte stream after the 0xC4D7 sync to be delivered.

### 5.2 FX465 CTCSS (output_method=2, "Fx465"; 13562-13645)
- An 8-bit serial word goes out MSB first on OUT1 SD/CLK, with a TPS pulse to latch: D5..D0, RX(1)/TX(0), PTL(0). Codes come from tab_fx465 (13346-13378, Hz → code; NOTONE=0x30).
- ctcss_fx465_off loads RX mode with the RX Hz.
- TX is refused unless cfg_function=Std, because FX465 is RX-only in duplex functions (13564-13566).
- Its detector output (FW expects) arrives on PB5 (§1.5, methods 1/2).

### 5.3 Multiboard in the second ROM socket (memory reads of 0x80xx; the low byte is don't-care)
- bit7 = StD (8870 delayed steering), bits 6..3 = Q4..Q1, bits 2..1 unused, bit0 = CTCSS LPF+slicer output (1-3 header, 1916-1919, 3150-3155).
- DTMF (dtmf_decoder 3149-3187, systick 100 Hz):
  - If the value ≥0x80 (StD high), code = (v>>3)&15 is mapped through dtmf_8870_tab (1484): 0→D, 1-9, 10→0, 11→'*', 12→'#', 13→A, 14→B, 15→C.
  - A digit is stored once per change of value. StD low resets prevdata, and dtmf_idletime grows.
  - Emulator idle: **bit7=0** (e.g. 0x00). An open bus returning 0xFF would inject one 'C' digit.
- CTCSS DSP decoder (method 0, "dSP"):
  - ctcss_dec_entry (1907-1956) runs every PIO-A interrupt while enabled.
  - It samples bit0 and correlates it against the quadrant of a DDS at the RX tone, accumulating sin and cos in ±1 steps.
  - Every 12 systicks (~122 ms), ctcss_dec_periodic (13829-13880) computes mag = max+min/2 of the low bytes. If mag ≥ cfg_ctcss_dec_threshold (def 100), status = 0xFF, meaning detected. The comment "store 0 if decode" is stale.
  - Emulator: bit0 = square(sign) of the received CTCSS tone at interrupt time.

### 5.4 CCIR selcall decoder (PIO A bits 7..4, `PA_CCIR`=0xF0, 700; ccir_decoder 2927-3005)
- Sampled at 100 Hz. It must be equal at systick entry (2029) and at the call. 0xF = no tone, 0xE = repeat previous tone, 0x0-0xD = digit value (stored raw).
- A series is accepted at the first notone if its duration > cfg_ccir_minlen (cs), then matched against cfg_ccir_1..3 and the repeater/gpio prefixes (3007-3044).
- Emulator idle: PA7..4 = 1111.

---------------------------------------------------------------------------
## 6. Interrupt structure

### 6.1 Mode and vectors
- I = HI(intvec) = 0x01, IM2 (1594-1596), set only after init. EI happens first in `main` (3248).
- intvec is at 0x0140 (1025-1043; the `ASSERT` requires it on page 1).

| vector (low byte) | handler | addr |
|---|---|---|
| 0x40 | siob_tbe (MBUS TX) | 0x0637 |
| 0x42 | siob_esc (PTT = CTS-B, /LOCAL = SYNC-B, DMIDLE = DCD-B; 719-721). Mirrors RR0 into sio_bctrl_mirror | 0x0681 |
| 0x44 | siob_rca (MBUS RX) | 0x065C |
| 0x46 | siob_src | 0x0694 |
| 0x48 | sioa_tbe (GPS upload) | 0x069F |
| 0x4A | sioa_esc (CU DA/INT, modem, OUT2) | 0x06CD |
| 0x4C | sioa_rca (NMEA RX) | 0x06BC |
| 0x4E | sioa_src | 0x074C |
| 0x50 | pioa_int | 0x07E7 |
| 0x52 | piob_int (stub) | 0x0757 |
| 0x54 | pioa_int_during_ctcss | 0x07CC |

SIO: `WR2`=0x40 is written on channel B (937). `WR1` = STATUS_VECTOR|ESC_ENB|TX_ENB|INT_ALLC on both channels (926, 936). Status-affects-vector uses the standard Z80-SIO V3..V1 encoding: B tbe/esc/rca/src = 0/1/2/3, A = 4/5/6/7, and vector = 0x40 | V<<1. SIO A is ×32 clock (GPS, 4800 bd); SIO B is ×16 (MBUS, 9600 bd) (922-937).
Every handler ends with `pop af; ei; reti` (`doreti`, 1609). ESC handlers issue WR0_RESET_ESCINT (0x10), SRC handlers issue ERROR_RESET (0x30), and TBE-with-nothing-to-send issues RESET_TXINT (0x28).

### 6.2 PIO programming (init_chips 902-920, 1098-1108)
- **A**: vector 0x50, mode 3 (0xCF), all inputs (0xFF), int control 0x97 (enable, OR, active LOW, mask follows), mask 0xFE, so only A0 is monitored. The result is one interrupt per falling edge of the 1968.75 Hz square wave, **1968.75 int/s**. Evidence: "halt = 1/1968.75 s ... half a millisecond" (13058), the DDS scale 8522 (13661), and E=20 → ~98.4 Hz systick.
- **B**: vector 0x52, mode 3, I/O 0x3E (B1-B5 inputs; B0, B6, B7 outputs), 0x97, mask 0xFF, so no interrupts. PIO B direction is later rewritten from piob_mode for I2C/EXIN (3238-3243).
- ctcss_revector (13733-13737) writes 0x54 to PIO-A ctrl, a new vector. It is used by both the RFC encoder start and the DSP decoder start. **It is never reverted to 0x50**; stop just points the jump slots at the skip labels.

### 6.3 PIO-A handler cadence (1958-2020; comment 1600-1606)
The handler uses only the alternate register set: `ex af,af'` and `exx`. Alternate E counts down to systick; alternate D counts down to adc_reader; alternate B, C, H, L are scratch. The main program must never touch the alternate set with interrupts enabled; DTMF/AX.25 save it under DI (14443-14450, 14588-14591).
```
pioa_int:              ex af; exx
ctcss_dec_ret:         dec e; jr z,systick     ; every 20th -> ~98.4 Hz
                       dec d; jr z,adc_reader  ; every 4th (3 after systick)
                       ex af; exx; ei; reti
pioa_int_during_ctcss: ex af; exx; jp [ctcss_enc_jump]   ; enc entry|skip
                       -> jp [ctcss_dec_jump]            ; dec entry|skip -> ctcss_dec_ret
```
- E and D are uninitialised at boot until the first systick; the first one can take up to 256 ticks.
- On a systick tick, D is not decremented.
- systick (2022-2215): watchdog, hook change (PA1), scan/mt/mbus/ccir/txtail/key timers, then decoders (ctcss_dec_periodic, squelch, rssi_disp, ccir_decoder, dtmf_decoder), repeater 10 ms step, and the clock. It then reloads E=20, D=3 and `exx`.
- After that it does "soft-interrupt" (sir) work: it ends the hardware interrupt by `call 8b` (ei; reti trick) and runs dosir with the main register set and interrupts enabled (2205-2242).
- PIO-A interrupts during a long DI (DTMF/AX.25 PWM, GPS BRK, nvram save) are lost, apart from one pending edge.

### 6.4 Other inputs worth knowing for "normal" operation
- PA3 `PA_PWR` must read 0, otherwise the firmware goes to powerdown_now at reset (841-843, 1113-1115).
- PA1 = hook (a change runs a script, 2031-2051). PA2 = WDR (unused).
- PB2 `EXIN2` (/IGN) = 0 means ignition on. Otherwise the auto-power-off counter runs, checked hourly (once_per_hour 2512-2524).
- SIO-B CTS = /PTT: RR0 CTS=1 means PTT pressed (4460-4462). SIO-B SYNC = /LOCAL, inverted (1576-1581).
