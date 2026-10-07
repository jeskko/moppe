> Provenance: written 2026-09-28 by a research subagent from the firmware source
> (line numbers `Lnnnn` = unmodified `reference/r58.asm.als`) or the scanned manuals.
> Items the emulator tests exercise are confirmed; everything else is as-read.
> Corrections found since: see notes/hardware.md.

# R58 firmware (v3_Z "ALs", 24.09.2018): RF, TX/RX and UI spec for an emulator

Source: `r58/r58.asm`. `L1234` means that line of the source. `@0xNNNN` is an address from
`r58/build/r58.lst`, built with `-DP8x` as in the Makefile. All firmware frequencies are **integer kHz**, stored
as 24-bit little-endian values ("FREQ", 3 bytes, L446). TCXO = 12800 kHz (L397-398). Nothing in the Makefile overrides it.

---------------------------------------------------------------------------------------------------------------------

## 0. Quick reference: ports and RAM the tests will poke or peek

| Item | Value | Source |
|---|---|---|
| OUT0 0x60 | VOLUME 0x07, INH 0x08, AUDIOC 0x10, CCIRC 0x20, MTC 0x40, MICM 0x80 | L653-660 |
| OUT1 0x70 | SRE 01, SCE 02, STE 04, CLK 08, SD 10, RAS 20, TPS 40, TXOFF 80 | L663-670 |
| DA0 0x30 = DA_RFC (RX front-end tuning), DA1 0x40 = DA_TXPWR | | L497-498, L524-525 |
| AD 0x50+ch: 0 RSSI, 1 SQL, 2 BATT, 3 TPC, 4 FPM, 5 RPM, 6 TP4, 7 IN7 | | L499, L513-520 |
| PIO B bit4 PB_RXOFF (/RXON, a GPIO only), bit7 PB_PWROFF | | L706-709 |
| PIO A bit3 PA_PWR: 1 means the on/off switch is in the off position, and the firmware powers down | | L684, L1114-1116 |
| SIO B RR0 CTS (0x20) = SB_PTT; SIO B RR0 SYNC (0x10) = /LOCAL | | L719-721 |

RAM (the NV block is 0xC000-0xCFFF; it is battery-backed and loaded as-is, with no checksum and no defaulting at boot, L14270-14292):

| Symbol | Addr | Notes |
|---|---|---|
| volume | 0xC001 | 0..9 |
| scan_on | 0xC003 | |
| mem_flags / mem_idx | 0xC006 / 0xC007 | flag bits VALID 1, HIDDEN 2, SCANNABLE 4 |
| rx_freq / tx_freq | 0xC008 / 0xC00B | kHz, 3 bytes LE |
| duplex_state | 0xC00E | 0 SIMPLEX, 1 DUPLEX, 2 REVERSE, 3 SPLIT (L437-440) |
| duplex_shift | 0xC00F | signed kHz, 3 bytes |
| band_step / band_step_hz | 0xC013 / 0xC014 | |
| memories | 0xC0FE | 130 x 12 bytes: rx(3) tx(3) flags ctcssT band ctcssR foo foo |
| cfg_function | 0xC716 | 0 Std, 1 rPtr, 2 Slave |
| cfg_implied | 0xC717 | 3 implied leading digits, stored as digit values |
| cfg_txpwr | 0xC71F | |
| cfg_tx_tot_minutes | 0xC724 | 0 means TX is never allowed |
| cfg_squelch_level | 0xC727 | |
| cfg_def_frequency | 0xC72E | |
| cfg_synth_card | 0xC732 | 0 S8D, 1 S8C, 2 S8B (L413-415) |
| cfg_if_freq | 0xC733 | |
| cfg_rx_vco_center / cfg_tx_vco_center | 0xC736 / 0xC739 | |
| cfg_tx_oob_0 | 0xC73F | |
| cfg_tx_band_start / cfg_tx_band_end | 0xC742 / 0xC745 | |
| cfg_band1_start | 0xC748 | 6 records x 14 bytes, then the "other" record |
| cfg_other_duplex | 0xC7A2 | |
| cfg_inj_below | 0xC932 | |
| cfg_enter_time | 0xC98D | |
| cfg_external_serial_A / B | 0xCA3A / 0xCA3C | |
| cfg_deviation_fone / cfg_deviation_sign | 0xCA5D / 0xCA5E | |
| cfg_pll_delay | 0xCA6F | |
| synth_ctrl | 0xD00A | not cleared at boot (it sits outside `_bss`) |
| rx_refdiv / tx_refdiv | 0xD00B / 0xD00D | |
| rx_divisor / tx_divisor | 0xD00F / 0xD012 | |
| key | 0xD0B0 | 0xFF means none |
| lastdigit | 0xD0AE | |
| key_time | 0xD0B2 | |
| keydown | 0xD0B4 | |
| digidx | 0xD0B5 | |
| tx_is_legal | 0xD0CB | |
| txon | 0xD0CC | |
| seconds | 0xD0D1 | |
| local_mode | 0xD0DC | |
| cu_is_alfa | 0xD0DD | 0 means a CU53AN handset |
| menu_active | 0xD100 | |
| ad_tpc | 0xD153 | |

Code entry points: start 0x0156, main 0x0EF9, mainloop 0x0F5B, is_ptt_pressed 0x150A, pttcheck 0x36E9, tx_on 0x4C0F,
tx_off 0x4C50, load_rxsynth 0x4B12, load_txsynth 0x4AE7, load_synth_ctrl 0x4AB6, strobe_to_synth 0x4B85,
powerdown_now 0x39D3, redraw 0x3D54.

---------------------------------------------------------------------------------------------------------------------

## 1. Synthesizer programming

### 1.1 Common bit-bang primitives (L12891-12930)

The RX PLL, the TX PLL and the control register all share **SD (0x10)** and **CLK (0x08)** on OUT1. Each has its own
strobe: **SRE (0x01)** for RX, **STE (0x04)** for TX and **SCE (0x02)** for control. Every write carries TXOFF = 1 (0x80)
unless noted; see the TX exceptions in §2.

A single bit is sent as three OUT writes (L12910-12930):
1. `A = (A & ~SD) | (bit ? SD : 0)`, then `out`. Data is set up while CLK is low.
2. `A |= CLK`, then `out`. This is the **rising edge, where the device latches**.
3. `A &= ~CLK`, then `out`.

SD is **not** returned to 0 between bits.

`send_to_synth` (L12898) sends B bits of register C **MSB first**, using `rl c`.

`strobe_to_synth` (L12891) takes A = (A | strobe) and writes it. It then writes `A & ~(SCE|STE|SRE|SD)`. The strobe
pulse is therefore high for one OUT period, with SD still at the last bit value. The emulator should latch the shifted
bits on the **rising edge of the strobe**; the bits are already stable on either edge.

Since all devices see the same SD and CLK, model one shared shift register, or one per device, clocked by every CLK
rise. Each device latches when its own strobe rises. The last bit shifted before the strobe is the MC145158-style
"control" bit: 1 selects R and 0 selects N/A.

### 1.2 Control register (SCE): 8 bits, MSB first, no selector bit (L12697-12722)

`C = (deviation << 4) | (synth_ctrl & 0x0F)`. The sequence is `OUT1=0x80`, 8 bits of C, then the SCE strobe.

| Bit | Meaning | Source |
|---|---|---|
| 7..4 | Deviation DAC, 0..15. `cfg_deviation_fone` (menu PH:FonE d, default 15) is used normally. `cfg_deviation_sign` (PH:SiG dE, default 7) is used by `change_to_signalling_deviation` at PTT release before MPRS or end-of-TX signalling. The analog scale cannot be determined from the firmware. | L12710-12743, L18038-18039 |
| 0 | RX VCO band: 1 if `rx_freq < cfg_rx_vco_center`, 0 ("high band") if `rx_freq >= center`. The comparison uses the displayed RX frequency, **not** the LO. | L12657-12668 |
| 1 | TX VCO band: the same rule, applied to `tx_freq` and `cfg_tx_vco_center`. | L12670-12681 |
| 2 | 1 cuts the supply to the TX prescaler and PLL (TX synth halted). 0 means on. | L12683-12695 |
| 3 | 1 turns on the supply to the TX VCO and amplifiers. 0 means off. | same |

`halt_txsynth` sets bits 3:2 to `01`. `enable_txsynth` sets them to `10`. Each of these, and `load_rxsynth`, calls
`load_synth_ctrl`, so a control frame is sent every time.

Examples on S8D defaults (fone = 15, centers 450000), RX and TX both below the center:
- 0xF7 when idle (RX on, TX halted).
- 0xFB during TX.
- 0x7B for the frame sent by `change_to_signalling_deviation` at PTT release.
- 0xF7 again after `tx_off`.

`synth_ctrl` (0xD00A) is not in `_bss`, so it is not zeroed at boot. The first control frame after power-on (from
`halt_txsynth`, L3268) sends bits 0 and 1 as whatever the RAM held. Do not test bits 0 and 1 of the first SCE frame.

### 1.3 R (reference) register: 17 bits on SRE or STE (L12749-12765, L12783-12799)

The sequence is `OUT1=0x80`, then 16 bits of `rx_refdiv` or `tx_refdiv` MSB first (the high byte, then the low byte),
then one **1** bit, then the SRE or STE strobe. The comment at L12756 notes that the 16-bit send "has excess bits...
they overflow ok". With a 14-bit R latch plus the control bit, the leading two zero bits fall off the end.

Decode: `ctrl = bit0 = 1`, `R = (bits >> 1) & 0x3FFF`.

### 1.4 N/A register: 18 bits on SRE or STE, then a trailing 0 selector bit (L12808-12889)

The firmware's "linear divisor" D is N·P + A.

- **S8D** (`cfg_synth_card == 0`, 128/129 prescaler), `send_NA_128_to_synth` (L12834): the bits are D16, D15..D8,
  D7..D0, then **0**. That is 17 data bits: N = D>>7 (10 bits), A = D&0x7F (7 bits).
- **S8B/S8C** (64/65 prescaler), `send_NA_64_to_synth` (L12864): the bits are D15..D8, D7, D6, then a padding **0**,
  then D5..D0, then **0**. That is N = D>>6 (10 bits), followed by a 7-bit A field whose MSB is 0 and whose low 6 bits
  are D&0x3F.

**Decode, the same for all cards:** take the last 18 bits before the strobe. `ctrl = b0` (must be 0).
`A = (bits >> 1) & 0x7F`. `N = (bits >> 8) & 0x3FF`.

**Total division ratio:** `Ntot = N·P + A`, where P is 128 for S8D and 64 for S8B/S8C. The emulator's hardware
configuration must choose P; it comes from the RF deck, not the firmware. In both cases Ntot equals the firmware's D.

Divisor clamping in `check_and_clamp_divisor` (L12617) applies to each `freq2div` result, **not** to the sum with the
IF. It clamps to 0x1FFFF for S8D and 0xFFFF for S8B/S8C.

Frame order within `load_rxsynth` (L12777) is: **control (SCE) → R (SRE) → N/A (SRE)**. `load_txsynth` (L12743) sends
control (SCE, via enable_txsynth) → R (STE) → N/A (STE).

### 1.5 Channel step: R and grid (`channel_step_parms`, L12518-12562)

The step config BC holds C = divisor and B = shift. The grid is `C / 2^B` kHz.

| band_step (TAB index, L402-409) | Displayed step (band_step_hz) | Physical grid | R | Exact? |
|---|---|---|---|---|
| 0 STEP_25 | 25 | 12.5 kHz (C=25, B=1) | 1024 | yes |
| 1 STEP_20 | 20 | 10 kHz (C=10, B=0) | 1280 | yes |
| 2 STEP_15 | 15 | 15 kHz (C=15, B=0) | 853 (12800/15 truncated) | **no**: the reference is 15.00586 kHz (comment "NOT EXACT XXX", L12128) |
| 3 STEP_12 | 12 (the user sees 12.5) | 12.5 kHz | 1024 | yes |
| 4 STEP_10 | 10 | 10 kHz | 1280 | yes |
| 5 STEP_6 | 6 (the user sees 6.25) | 6.25 kHz (C=25, B=2) | 2048 | yes (ALLOW_6_25_kHz is defined, L11) |
| any other value | 25 | 12.5 kHz | 1024 | |

The 25 kHz step programs a **12.5 kHz** reference. RX and TX always use the same R (`set_channel_step`, L12503).

`freq2div(f)` (L12584) computes `f·2^B / C` in integer kHz and rounds to the nearest channel. The rounding has quirks:
the fractional bits are computed using 2r+1, and for B = 0 the final round-up compare depends on the carry. (A Python
model reproduced it exactly; it was not kept. `test_freq.py` compares the build against the release instead.)

`div2freq` (L12564) computes `D·C >> B`, which truncates. The displayed kHz value is therefore the grid frequency
truncated to a whole kHz. For example, 433.5125 MHz is displayed and stored as 433512.

### 1.6 Forward computation (firmware)

These steps come from `determine_rx_div` (L12321), `determine_tx_div` (L12288) and `determine_tx_div_split` (L12311):

```
rx_div  = freq2div(rx_freq);        rx_freq := div2freq(rx_div)    (aligned)
if_div  = freq2div(cfg_if_freq)                                     (IF quantized to the SAME grid!)
RX D    = rx_div + if_div   (cfg_inj_below == 0, "AboUE", default)
        = rx_div - if_div   (cfg_inj_below != 0, "bELou")
TX D    = freq2div(tx_freq); tx_freq := div2freq(TX D)              (no IF: TX VCO is on-frequency)
```

The firmware has no RX or TX multiplier or TX mixer. The config fields PH:tr oFF, t mult and r mult (L18044-18046,
L19114-19116) are never used in any calculation.

### 1.7 Per-card defaults (`defaults_70cm`, `defaults_2m`, `defaults_6m`, L18298-18338; applied by SAnE/ALLrSt via `set_defaults_band`, L18343)

| | S8D (RD58, 70 cm) | S8C (RC58, 2 m) | S8B (RB58, 6 m) |
|---|---|---|---|
| Prescaler (hardware, L24-26) | 128/129 | 64/65 | 64/65 |
| Hardware 1st IF (L24-26) | 86.5125 MHz | 21.4 MHz | 45.0 MHz |
| cfg_if_freq default | 86512 kHz (86512.5 on the 12.5 kHz grid, which gives if_div 6921 and is exact) | 21400 | 45000 |
| Injection default | above (`cfg_inj_below` menu default 0) | above | above |
| cfg_implied | 4,3,3 | 1,4,5 | 0,5,1 |
| RX/TX VCO center | 450000 / 450000 | 150000 / 150000 | 60000 / 60000 |
| TX limits (tr Lo / tr Hi) | 432000 / 438000 | 144000 / 146000 | 50000 / 52000 |
| Band 1 start/end/dpx/step | 433400/433600/0/25 | 145200/145600/0/25 | 51490/51610/0/20 |
| Band 2 | 434600/435000/-1600/25 | 145600/145800/-600/25 | 51810/51970/-600/20 |
| Other: dpx / step | -1600 / 25 | -600 / 25 | -600 / 20 |

`ldi_10` copies only start, end, duplex and step into bands 1 and 2. Bands 3-6 and the scan fields keep their old
values; ALLrSt zeroes them first.

Whether injection is physically above or below cannot be determined from the firmware. It only has the per-install
setting, which defaults to "above" for all three cards. The changelog (L120) mentions that "below" was added "for 220
things".

### 1.8 Inverse formula for the emulator

This turns latched register values into Hz. Let `fref = 12 800 000 / R` Hz and `Ntot = N·P + A`.

- **TX frequency (Hz)** = `Ntot_TX × fref`. The RF is on the VCO frequency.
- **RX LO (Hz)** = `Ntot_RX × fref`.
- **Physical RX frequency** = `LO − IF_hw` when injection is above (the default), or `LO + IF_hw` when it is below.
  IF_hw is 86 512 500 Hz for S8D, 21 400 000 Hz for S8C and 45 000 000 Hz for S8B.
- **Firmware-intended RX** (for comparing with the display) = `(Ntot_RX ∓ if_div) × fref`, where
  `if_div = round(cfg_if_freq / grid)`.

The physical and firmware-intended values agree except in two cases:
- S8D with a 10 or 20 kHz step: if_div = 8651 gives 86.510 MHz, so the physical RX is **2.5 kHz below** the display.
- Any card with a 15 kHz step: R = 853 makes every frequency about 1.000391 × nominal. For example, a displayed 433515
  (S8D) actually produces TX = 433 684 408 Hz and LO = 520 223 212 Hz.

Worked values from the model (S8D, default config, 25 kHz step; R = 1024 in every case):

| rx_freq (kHz) | RX N / A / D | TX = same f: N / A / D |
|---|---|---|
| 0 (fresh NV) | 54 / 9 / 6921 (LO = 86.5125 MHz) | 0 / 0 / 0 |
| 433500 | 325 / 1 / 41601 (LO 520.0125 MHz) | 270 / 120 / 34680 |
| 433525 | 325 / 3 / 41603 | 270 / 122 / 34682 |
| 433475 | 324 / 127 / 41599 | 270 / 118 / 34678 |
| 434500 | 325 / 81 / 41681 | 271 / 72 / 34760 |
| 434700 | 325 / 97 / 41697 | 271 / 88 / 34776 |
| 433100 | 324 / 97 / 41569 | 270 / 88 / 34648 |
| 431900 | 324 / 1 / 41473 | 269 / 120 / 34552 |
| 440000 | 329 / 9 / 42121 | 275 / 0 / 35200 |

For the 12.5 kHz step, 433512 gives RX 325/2 and TX 270/121 (433.5125 MHz exactly).

Other cards:
- S8C at 145500: R = 1024, RX N = 208, A = 40 (D = 13352), TX N = 181, A = 56 (D = 11640).
- S8B at 51510 with a 20 kHz step: R = 1280, RX N = 150, A = 51 (D = 9651), TX N = 80, A = 31 (D = 5151).

Example bit strings for S8D at 433.500:
- R frame (17 bits): `0000010000000000` followed by `1`.
- RX N/A frame (18 bits): `01010001010000001` (D = 41601) followed by `0`.

### 1.9 External serial registers A and B (RAS and TPS), L12934-12985

- **A:** 16 bits from `cfg_external_serial_A` (PH:SErCtA, WORD), always shifted.
- **B:** 16 bits from `cfg_external_serial_B` (PH:SErCtB), shifted **only if non-zero**.

Both are sent MSB first from HL on the same SD and CLK lines. Each bit is written as SD, then a CLK rise, then a CLK
fall, with a `nop` between writes. The strobe (RAS 0x20 for A, TPS 0x40 for B) is raised for about 1 µs (two `nop`s)
and then dropped. SD is then cleared.

They are shifted at boot (L1587-1588, before `main`) and again whenever the menu value is set (L17451-17470).

**TPS is shared.** `load_fx465` (L13585-13644) also uses TPS to send an 8-bit frame to an FX465 CTCSS chip:
D5..D0 (tone code, 0x30 = no tone), then RX/TX (1 = RX), then PTL = 0, MSB first, then a TPS pulse. That frame is only
sent when PH:CtCGEn = "Fx465" (method 2; L13490, L13456), and the default is i8254. That write keeps TXOFF clear while
`txon` is set.

### 1.10 Lock detect

**None.** No input port is read for PLL lock. The firmware waits open-loop for `cfg_pll_delay` halts, which is
PH:PLLdEL, default 0. The PIO A interrupt runs at 1968.75 Hz, so each halt is about 0.5 ms (L13052-13058).

The only "lock" in the source is an unrelated FSK comment (L13908).

---------------------------------------------------------------------------------------------------------------------

## 2. TX/RX sequencing

### 2.1 When synths are loaded

- **RX synth:** loaded only in `temporary_change_rx_freq` (L12154). Callers are:
  - boot (`main` L3268-3270);
  - every frequency change (`changed_frequency`, `changed_frequency_duplex_okay`: entry, step, memory, VIP, duplex
    key, scanner);
  - the monitor ('B') key in duplex, which temporarily listens on the input (tx_freq) and then restores (L4672-4728).

  It is **not** reloaded after TX, and not on menu edits. After changing IFFrEq, band edges and so on in setup, the
  synth keeps the old values until the next frequency change.
- **TX synth:** loaded at every `tx_on` (L13050). It is halted at boot (L3268) and at every `tx_off` (L13083).

Boot order: serial A at RAS, then serial B at TPS if non-zero, then (in `main`) control frame (halt), then control
frame, R frame and N/A frame to the RX synth. `main` does **not** call `locate_band`. It uses the `band_step` and
`duplex_state` already stored in NV (L3268-3270).

### 2.2 PTT detection (`is_ptt_pressed`, L4458-4468)

PTT is pressed if `sio_bctrl_mirror & 0x20` is non-zero (SIO B RR0 CTS, which means the /CTSB pin is low and /PTT is
active). On a CU58AF it is also pressed if `cu58af_buttons & 0x40` (TANGENT) is set.

The mirror is updated only by the SIO B external/status interrupt (`siob_esc`, L1680-1697) and once at boot (L1574).
**The emulator must raise the SIO B ext/status interrupt when CTS changes.**

At boot, `main` waits for PTT and all keys to be released (L3262-3266). In repeater function (`cfg_function == 1`),
`pttcheck` ignores PTT (L9588-9590).

### 2.3 TX on (`pttcheck` L9578 → `tx_on` L13020 / `tx_on_legal_or_not` L13029)

1. `scanner_stop`. If `tx_is_legal == 0`, the firmware goes to **tx_error** (§2.5).
2. If `cfg_tx_tot_minutes == 0`, return without TX. This is the state after zeroed NV. Menu default is 255.
3. `update_LPF`. Then, with interrupts disabled: `txon = 1`, marker tone off, `tx_cut_local_audio` (OUT0 AUDIOC and
   CCIRC cleared, squelch closed, `txtail_timer = 100`; L2817).
4. `OUT1 = 0x80` (TXOFF = 1). `DA1 = 0`. `load_txsynth`, which sends control 0x?B (TX on, bits 3:2 = 10), then R on
   STE, then N/A on STE.
5. Wait `cfg_pll_delay` halts.
6. **`OUT1 = 0x00`** (TXOFF = 0, which keys the TX). Then `DA1 = real_txpwr`, which is `cfg_txpwr + txpwr_increment`
   saturated at 255 (L12992-13013). Then the transmit LED (ROAM segment/bit).
7. Back in `pttcheck`: `ctcss_maybe`. If digits are pending in the normal display, it sends CCIR (`ptt_ccir_xmit`).
   Then `mic_on` (OUT0 MICM cleared) and `tx_tune_tone_maybe`.
8. Loop while PTT is held (L9622-9650):
   - Keys go to `handle_key_during_tx` (L4617). '+' and '-' step `cfg_txpwr` by ±26 (saturating) and rewrite DA1
     immediately (L10055-10073). Other keys send DTMF.
   - The display is redrawn when the battery ADC changes.
   - During TX the lower row shows **tx_freq**. The upper-right two digits show the TX power (0..99 scale) instead of
     RSSI, unless the radio is in rPtr mode (L11093-11102).

**TOT:** once a minute, if `txon` is set and `tx_tot_timer > cfg_tx_tot_minutes`, the firmware calls `powerdown_now`
(L2451-2462). A value of 255 never trips.

### 2.4 TX off (L9652-9676, `tx_off` L13073)

The sequence at PTT release is:
1. `ctcss_off`.
2. `change_to_signalling_deviation`: a control frame with the deviation set to `cfg_deviation_sign`. OUT1 bit 7 stays
   0 because `txon` is set, so the carrier stays up (L12724-12741).
3. Remote config packets, if in the menu.
4. MPRS report, if configured.
5. `tx_off`: `OUT1 = 0x80`, `DA1 = 0`, `txon = 0`, then `halt_txsynth`. The halt sends a control frame with the
   deviation back to `fone` and bits 3:2 = 01.
6. LED off, redraw, `remember_vip`, `repeater_operator_ptt`.

**RXOFF:** the firmware does **not** switch the receiver during TX. PB_RXOFF (PIO B bit 4, "/RXON") is only
GPio2 bit 0 (GE:GPio 2, default 0, which leaves RX on), written by `update_gpio12` (L2531-2553). The RX synth stays
programmed throughout TX, and the RX audio path is muted through OUT0 AUDIOC.

### 2.5 Out-of-band TX ("ILL" tx spots)

`set_legal_tx_flag` (L12359-12400) runs on every frequency change. `tx_is_legal = 1` when:
- `cfg_tx_band_start < tx_freq < cfg_tx_band_end` (**both comparisons strict**, so 432000 exactly is illegal with the
  default limits), or
- `tx_freq` equals one of `cfg_tx_oob_0..4` (tr:tSPot0..4; the "ILL" item in the L123 changelog).

Otherwise `tx_is_legal = local_mode`, which is non-zero if /LOCAL (SIO B RR0 SYNC) was grounded at boot (L1572-1581).
Note that a tSPot of 0 makes tx_freq 0 legal.

When TX is illegal (`tx_error`, L9683-9691), the firmware starts a **300 Hz marker tone**: timer 1 counter set to
MT_300HZ, OUT0 MTC set, duration 100 × 10 ms. It then loops in `waitkey` until PTT is released. **No** TX synth
frames, OUT1 stays 0x80 and DA1 stays 0. No text such as "ILL" is displayed; the display just keeps redrawing.

### 2.6 TX power DAC and the TPC ADC

- DA1 (0x40) is the only TX power control. It is 0 in RX and `real_txpwr` in TX.
- AD_TPC (0x53) is sampled round-robin with the other ADC channels (`ad_list`, L1892-1897, read in the PIO A interrupt
  L2000-2012) into `ad_tpc`. It is **only displayed** (menu St:Ad tPc, L18074). **The firmware has no closed TPC loop**;
  levelling happens in the analog hardware.
- FPM and RPM feed the repeater "antenna bad" check (L15687).
- The displayed P digit is `byte_decade(real_txpwr)`, which is `(v·10) >> 8` (L16446-16465).

### 2.7 Band records, duplex and repeater shift

`locate_band` (L12198-12250) is called by `parameters_from_band` for changed_frequency and by go_mem.

1. It first assumes DUPLEX.
2. It searches bands 1-6 for `start <= rx_freq < end`. Empty records (0/0) never match.
3. If no band matches, it uses the "other" record and sets **SIMPLEX**, then sets `band` (1..6, or 0 for other).
4. `set_band_duplex_shift` (L12258): if the band's shift is non-zero, it keeps it. Otherwise it sets
   `duplex_shift = cfg_other_duplex` and **SIMPLEX**. Only a band with a non-zero dpx is auto-duplex.
5. The step, scan tail, listen time and autoreject values come from the band record.

`determine_tx_div` (L12288) derives tx_freq from duplex_state:

| State | tx_freq |
|---|---|
| 0 SIMPLEX | rx |
| 1 DUPLEX | rx + shift (the shift is signed and usually negative) |
| 2 REVERSE | rx − shift |
| 3 SPLIT | tx_freq kept as set |

Key R (RCL) controls the duplex state (`duplex_key`, L5007-5042):
- **Quick press, or fewer than 2 digits pending:** `step_duplex_state` (L12404) cycles 0 → 1 → 2 → 0. When entering
  state 2 or 0 it **swaps rx_freq and tx_freq** before recomputing.
- **With 2 or more digits entered and R held:**
  - held ≥ 1 s: shows "SHIFt NEG"; releasing then sets `shift = −digits` and DUPLEX.
  - held ≥ 2 s: "SHIFt POS"; sets `+digits`.
  - held ≥ 3 s: "SPLIt"; sets tx_freq = digits (3-4 digits use the implied prefix, 1-2 digits pick memory N's RX
    frequency) and SPLIT.

  These overrides are temporary and are lost on the next band lookup.

The duplex indicator (`set_dpx_ind_from_rx_tx_freq`, L11229) is set only when TX ≠ RX. On a CU53AN it shows segment
V_D (0x53) when TX is below RX and V_U (0x43) when TX is above. On a CU58AF it uses ARROW0 or ARROW1.

The monitor key 'B' in duplex temporarily tunes RX to tx_freq while held (L4672-4728). This is the "listen on the
input" feature.

---------------------------------------------------------------------------------------------------------------------

## 3. User interface

### 3.1 Key codes (values in `[key]`, 0xD0B0; 0xFF means none)

The CU53AN keypad returns 5 bits, read MSB first with inverted sense (`sub 1; rl c`, L10251-10262). They index
`keytbl_cu53an` (L13097):

```
idx 0-11 'Z'   12 '+'  13 '-'  14 '?'  15 'B'
16 'E'  17 '*'  18 0   19 '#'  20 'R'  21 7  22 8  23 9
24 'S'  25 4    26 5   27 6    28 'C'  29 1  30 2  31 3
```

The CU58AF table is at L13104. The key names on the CU53AN handset are CL = 'C', STO = 'S', RCL = 'R', ENT = 'E',
SHIFT (top button) = 'B', and the side keys '+' and '-' (r58en.txt).

Caution: the old v1.6 notes swap the roles of ENT and # on the numeric handset. In v3_Z the firmware binds '#' to
execute and 'E' to setup, and the v3_Z setup map ("0 ENT" opens group 0) agrees.

Values that appear in [key]:

| Code | Action outside the menu (`dokey_not_menu`, L4491) | Action in the menu (`menu_input`, L4556) |
|---|---|---|
| 0..9 (short press, delivered on **release**) | append to digbuf (`insdig`). While scanning it toggles scan-mask bits instead. | append digit |
| 0x80\|d (digit held 0.5 s, auto-repeat) | 0x81 squelch up, 0x84 squelch down, 0x87 default squelch; 0x82 memory up, 0x85 memory down, 0x88 default memory; 0x83 frequency up one step, 0x86 frequency down; 0x89 default frequency; 0x80 default volume | alpha entry (`insdig_alpha`; 0x80 is punctuation) |
| '#' | execute (§3.3); hold ≥ 1 s stores a memory | with no digits, next record; with digits, set the value |
| 'E' (ENT) | toggle setup, or with digits position the menu (§3.5) | the same (exit) |
| 'C' | backspace; if held (keydown ≥ 20), clear all | backspace |
| '*' | with no digits, 1750 Hz beep; with digits, send an FSK call | set the default value; FREQ copies rx_freq, DPX copies other_duplex, EXE runs |
| '+' / '-' | volume ±1 (0..9) | value ±1 (FREQ steps ±25 kHz, or ±20 for S8B) |
| 'B' | monitor: short press toggles forced squelch (STAR segment); long press is momentary | monitor |
| 'S' (STO) | short: start the scanner. Held 1 s: "rEJECtEd", adds a reject. Held 2 s: "CLEArEd", clears rejects. | next group |
| 'R' (RCL) | duplex (§2.7) | previous record |
| 'T', 'K' | selective-squelch mute and audio destination (not produced by the CU53AN table) | |

**Timing** (`keypad` L10177-10366, `typematic` L10368, debounce at L2126-2142). The systick runs at 100 Hz.

- A key is fetched after `keydown` reaches 10 ticks (100 ms debounce).
- Non-digit keys are placed in [key] at that moment, which is the press, not the release.
- Auto-repeat is driven by key_timer and key_speed; each repeat increments `key_time`:
  - '+' and '-': first repeat at 0.5 s, then every 0.2 s.
  - 'S' and 'R': at 1 s, then every 1 s.
  - other non-digit keys: at 1 s, then every 1 s.
  - '*' and 'B': never repeat.
- Digits go to `lastdigit`. They are delivered as a plain digit when the key is released before 0.5 s (L1801-1806).
  Otherwise, at 0.5 s, `typematic` delivers `0x80|d`, and it keeps repeating:
  - 1 and 4: every 80 ms.
  - 2, 3, 5 and 6: every 330 ms.
  - 7, 8, 9 and 0: every 1 s.
  - in the menu: every 660 ms.
- With PTT pressed, digits are delivered immediately as DTMF.
- Long-press actions ('#' store, R shift, S reject) poll `key_time`, where 1 is about 1 s, 2 about 2 s and 3 about 3 s.

### 3.2 Normal display (CU53AN: 6-digit upper row, 10-digit lower row; L963-1015)

**Upper row** (`draw_upper_row`, L11038), with both upper colons lit (COLON_UL 0x63, COLON_UR 0x4F): `P V QQ SS`.

- P = `(txpwr·10) >> 8`.
- V = volume 0..9.
- QQ = the squelch level scaled 0..99 by `dpydiv99`. For example, 127 displays as "49".
- SS = srssi scaled 0..99. During TX in normal mode it shows TX power instead.
- The squelch-forced state is the STAR segment (0x6B), which is not a digit.

**Lower row** (`draw_lower_row`, L11371). Priority order: call notice, then adjust feedback text, then the digit
buffer, then menu, then remote display, then the scan mask while scanning. Otherwise it shows:

- **3 chars memory info:** blank when not on a memory. On a memory, the index uses `dpyval99` (a space for tens = 0),
  and the status character is ' ' (scannable), '-' (not scannable) or '=' (hidden). In rPtr mode it shows "rP ".
- **7 chars frequency:** `draw_long`, leading-zero blanked. The value is **rx_freq** in RX and **tx_freq** in TX, in
  kHz, with **no decimal point**. A value of 0 displays as 7 blanks.

RX 433.500 MHz, not on a memory, shows the lower row **`"    433500"`**. On memory 12 (scannable) it shows
**`"12  433500"`**.

The upper row after SAnE, with volume v and no signal, is "0v49" followed by the RSSI digits.

**Digit entry:** the typed digits are shown followed by '_' and then blanks to 10 characters (L11155). For example,
typing 4, 3, 3 shows `"433_      "`.

**Feedback strings** are 10 characters (L11271-11302): " rEJECtEd ", "  CLEArEd ", "  dEFAULt ", "   StorEd ",
"SHIFt NEG ", "SHIFt POS ", "SPLIt     ", "ALLrIGHt  ", " Lo batt  ", " Hold It  ", " rEAdY    ", " LoAdinG  ",
" Error    ".

The CU58AF uses 8/9 characters; the upper row is `P V <audio_dst> QQ <'*'|' '> SS` and the lower row shows a 6-digit
frequency.

### 3.3 Frequency entry and memory (`execute` L4640; `go_mem` L9496; `save_memory` L9366)

Pressing '#' after typing digits does one of the following, **on release**, depending on how many digits were typed:

| Digits | Result |
|---|---|
| 0 | `next_vip`: cycle the 10-entry recent list (L5180) |
| 1-2 | recall memory N (`go_mem`; indices ≥ 130 clamp to 99) |
| 3-4 | prefix with the implied digits (`fill_implied`, L4852). With S8D defaults, "500" becomes 433500 and "4500" becomes 434500. |
| ≥ 5 | the absolute kHz value: "60500" is 60500 and "433525" is 433525 |

Then the firmware leaves memory mode, remembers the VIP entry, and calls `changed_frequency`, which runs locate_band,
the step, RX synth, TX divisor and legality.

A memory recall loads rx and tx, calls `locate_band`, sets `duplex_state` from `tx − rx`
(`set_duplex_from_tx_rx`, L12269), then recomputes.

**Store:** hold '#' for ≥ 1 s. The index is the typed digits, or the current mem_idx if none were typed; the valid
range is 0..129.
- Released between 1 and 2 s: flags VALID | SCANNABLE (status ' ').
- 2 to 3 s: VALID only ('-').
- ≥ 3 s: VALID | HIDDEN ('=').

rx, tx, flags and band_step are saved, and the display shows that memory.

**Stepping:** `step_channel_up` (L12467) adds `band_step_hz + 1` and re-aligns. `step_channel_down` (L12479) subtracts
1, looks up the destination band, then subtracts `step − 1` and re-aligns.
- With 25 kHz steps: 433500 goes up to 433525, and down to 433475.
- With 12.5 kHz steps: 433500 goes up to 433512 (433.5125 MHz), then 433525; down from 433500 goes to 433487.

**Volume** (`set_vola_a`, L4798):
- 0 sets OUT0 INH with VOLUME = 0.
- 1 clears INH with VOLUME = 0.
- 2..9 set VOLUME = v − 2.

**Squelch:** `cfg_squelch_level` goes up or down by 1 per repeat, saturating at 0 and 255.

**Defaults:** 7, 8, 9 and 0 held long load the default squelch, memory, frequency and volume. Holding 7 even longer
stores the current squelch as the default.

### 3.4 Boot sequence and banner

Reset (L819-827) writes OUT0 = INH and OUT1 = 0x80. `start` (L1050) then:
1. Initializes the PIO and SIO. If PA_PWR is high, it calls `powerdown_now`.
2. Clears `_bss` and calls `load_nvdata`.
3. Spins about 2×256×256 loops "for LCD reset".
4. Reads /LOCAL into `local_mode` and shifts serial A and B.
5. Switches to IM2 and jumps to `main`.

`main` (L3247) then:
1. Probes for a CU58AF, and sets up volume and menu.
2. Writes DA1 = 0.
3. Waits for all keys and PTT to be released.
4. Halts the TX synth, sets the channel step, and loads the RX synth (§2.1).
5. Turns on the lights and ON LED and runs repeater init.
6. Calls `redraw` twice.
7. **Waits until `seconds != 0`, about 1 s.**
8. Resumes the scanner if `scan_on` was set in NV, then enters `mainloop`.

**The LCD shows no banner.** The banner text "R58 v3_Z ALs 24.09.2018 P8E/P8N S8B/S8C/S8D CU53xx/CU58AF\n" (L881-897)
is only sent over MBUS by dF:CFGSnd. The first thing displayed is the normal screen. The version can be read in setup
as St:SoFt, which shows "3_Z ALs".

`powerdown_now` (L10080) writes OUT1 = 0x80. If `cfg_function == 0` it then writes PIO B = PB_PWROFF (0x80). It then
halts with interrupts disabled, forever.

**A fresh, zeroed NV is not usable.** The card defaults to S8D, IF = 0, rx_freq = 0, the implied digits are "000" and
the TOT is 0, which means no TX. It also has no band or TX limits. To initialize it, open **dF:SAnE with "828 E"**,
type **"666"** and press **'#'**. `sane_defaults` (L18400) resets every BYTE, TAB, cSEC, WORD and STR menu value to its
REC default, loads the card defaults from §1.7, saves, and **powers down**. After re-powering the display shows
frequency 0 (blank), because rx_freq is not reset. Alternatively, preload the NV block at 0xC000.

### 3.5 Setup menu

- **Enter/exit:** 'E' with no digits toggles `menu_active`. `cfg_enter_time` (dF:EntLen, default 0) sets how long 'E'
  must be held to enter (`enter_safety_delay`, L17077).
- **Positioning:** "g E" goes to group g, record 0. "gs E" goes to group g, record s. "gss E" (3 or more digits) splits
  as n / 100 and n % 100 (L17109-17210). Examples: "8 E" opens PH:SynCrd, "82 E" opens IFFrEq, "828 E" opens SAnE and
  "43 E" opens b1:StEP. The groups are `menu_0`..`menu_9` (`menu_quickspots`), and the numbering matches
  `r58p8x3Zi.setup`.
- **Initial position after boot:** `start_menu`, GE:tPc (`init_menu`, L16705).
- **Navigation:** '#' goes to the next record, 'R' to the previous one and 'S' to the next group. Navigation wraps.
- **Display:**
  - Upper row: the 6-character title, with the colons off (for example `"tPc   "`, `"SynCrd"`).
  - Lower row: the 2-character tag, then the lower colon (segment 0x57), then ' ', then the 7-character value
    (L16742):
    - BYTE: 4 blanks plus `dpyval255`.
    - WORD: 2 blanks plus 5 digits.
    - FREQ: `draw_long`.
    - DPX: a signed value, or "    oFF" when 0.
    - TAB: the string right-justified in 7.
    - STR: '_'-padded, right-justified.
    - RST: "  666 ?".
    - cSEC: the value followed by "0".
  - Examples of the lower row:
    - tPc = 0: `"GE       0"`.
    - SynCrd: `"PH     S8d"`.
    - IFFrEq: `"PH   86512"`.
    - SAnE: `"dF   666 ?"`.
- **Set a value:** type digits and press '#' (`menu_new_value`, L17378). TAB values clamp to the last entry. RST
  records call their routine, which acts only if the digits are 666. Leaving the menu calls `save_nvdata`. Values do
  **not** retune the synth (§2.1).

---------------------------------------------------------------------------------------------------------------------

## 4. Test scenarios

All scenarios assume a CU53AN, an S8D deck (P = 128) and NV already initialized with SAnE defaults.

For each frame, check the latched R, N and A and the synth control byte. Lower-row text is the 10-character string,
and "freq(X)" means the decoded Hz from §1.8.

1. **Boot frame order.** Set rx_freq = 433500, band_step = 0 and duplex = 0 in NV, then power on.
   - Expected OUT1 serial sequence:
     1. 16 bits + RAS (serial A = 0).
     2. SCE frame with bits 3:2 = 01.
     3. SCE frame 0xF7.
     4. SRE R = 1024.
     5. SRE N = 325, A = 1.
   - No STE frames, OUT1 stays 0x80, and DA1 = 0.
   - The RX LO is 520.0125 MHz and the physical RX is 433.500000 MHz.
   - After about 1 s the lower row shows `"    433500"` and the upper colons are lit.
2. **Absolute entry.** Type "433525" and press '#' (release it before 1 s).
   - While typing, the lower row shows `"433525_   "`.
   - After release: SRE R = 1024, N = 325, A = 3 (RX = 433.525 MHz), and the display shows `"    433525"`.
3. **Implied entry.** "500 #" gives 433500 (N = 325, A = 1). "4500 #" gives 434500 (N = 325, A = 81) and is simplex,
   with no duplex arrow, because 434.5 is outside bands 1 and 2.
4. **Step up/down.** From 433500, hold 3 for 0.5 to 0.8 s. The key sequence is a single 0x83, the result is 433525 and
   the display shows `"    433525"`. From 433500, a single 0x86 gives 433475 (N = 324, A = 127).
5. **Simplex TX.** At 433500, press PTT.
   1. SCE frame 0xFB.
   2. STE R = 1024.
   3. STE N = 270, A = 120, so the TX is 433.500 MHz.
   4. OUT1 = 0x00.
   5. DA1 = cfg_txpwr.

   On release:
   1. SCE 0x7B.
   2. OUT1 = 0x80.
   3. DA1 = 0.
   4. SCE 0xF7.

   The RX synth is not reprogrammed.
6. **Auto-duplex band.** "434700 #": the RX synth is programmed to N = 325, A = 97, and the lower row shows
   `"    434700"` with segment V_D (TX below) lit. On PTT, STE N = 270, A = 88, so the TX is 433.100 MHz, and during TX
   the lower row shows `"    433100"`.
7. **Duplex key cycle.** At 433500 (simplex, shift = −1600), press R briefly.
   1. First press: state 1. TX would be 431900, which is illegal. V_D is lit and the RX synth stays at 433500.
   2. Second press: state 2. RX = 431900 (N = 324, A = 1), TX = 433500, V_U is lit, and the display shows
      `"    431900"`.
   3. Third press: state 0. RX = 433500 and there is no arrow.
8. **Out-of-band PTT.** "440000 #" then PTT: no STE frames, OUT1 bit 7 stays 1, DA1 stays 0, and OUT0 MTC is set with
   timer 1 at the 300 Hz count. After release, TX is still off. The same happens at exactly 432000, because the limit
   is strict. The same frequency set as tr:tSPot0 ("762 E", "440000 #", "E"; then re-enter "440000 #") transmits.
9. **TOT = 0 blocks TX.** On zeroed NV, PTT never clears OUT1 bit 7.
10. **Memory store and recall.** At 433525, type "12" and hold '#' for about 1.5 s: the lower row shows
    `"12  433525"`. Then "433500 #" shows `"    433500"`, and "12 #" gives `"12  433525"` with the RX synth at A = 3.
    Hold '#' for more than 3 s instead to see the status character '='.
11. **Setup entry and display.** Press 'E': the upper row shows `"tPc   "` and the lower row `"GE       0"` with the lower
    colon lit. Type "200 #" and press 'E' to exit: the upper row's first digit is 7. PTT then gives DA1 = 200. During
    TX, '+' raises DA1 to 226 and '-' lowers it to 200.
12. **Quick setup positioning.** "8 E" gives upper `"SynCrd"`, lower `"PH     S8d"`. '#' goes to upper `"3diGit"`. '#'
    again goes to `"IFFrEq"` with lower `"PH   86512"`. 'E' exits.
13. **SAnE from zeroed NV.** Before SAnE, the boot RX frame is R = 1024 with N = 0, A = 0, and the lower row is blank.
    Type "828 E", then "666 #": the radio powers down (PIO B bit 7 = 1, then halt). After re-power the RX frame is
    R = 1024, N = 54, A = 9 (LO 86.5125 MHz, rx_freq = 0). "500 #" then gives 433500.
14. **Volume.** From volume 1, press '+' three times: V = 4 and OUT0 bits 2..0 = 2 with INH clear. Pressing '-' down to
    0 sets OUT0 INH.
15. **Step table.** Set b1:StEP ("43 E") to 3 (12.5 kHz) and exit. Then "433500 #" followed by 0x83 gives 433512:
    RX N = 325, A = 2 (433.5125 MHz), displayed `"    433512"`. Set it to 1 (20 kHz) and re-enter 433500: R = 1280,
    and the physical RX is 433.5075 MHz, 2.5 kHz off the display (§1.8).
16. **Other cards.** Set PH:SynCrd to 1 (S8C) with P = 64 and 2 m defaults (SAnE after changing the card). "145500 #"
    gives SRE R = 1024 and an 18-bit N/A with N = 208 and an A field of 40 (bit 7 of the A field = 0). The LO is
    166.9 MHz, so RX = 145.5 MHz. PTT gives TX N = 181, A = 56.

---------------------------------------------------------------------------------------------------------------------

## 5. Not determinable from the firmware

- The analog meaning of the deviation nibble, of the VCO band bits (other than "1 = below center") and of the
  DA1 → power curve.
- Which physical LO injection side each deck uses. The firmware only has a setting, defaulting to "above".
- The PLL chip type. The frame format matches an MC145158-style part (14-bit R + control 1, 10-bit N + 7-bit A +
  control 0), but the chip is not named in the source.
- The physical key legends of the CU53AN codes (see the caution in §3.1).
- The exact LCD segment encoding is in `cu53an_font` @0x0500 and the segment tables at L995-1015; it is not decoded
  here.
