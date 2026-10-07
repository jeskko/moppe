> Provenance: written 2026-09-28 by a research subagent from the firmware source
> (line numbers `Lnnnn` = unmodified `reference/r58.asm.als`) or the scanned manuals.
> Items the emulator tests exercise are confirmed; everything else is as-read.
> Corrections found since: see notes/hardware.md.

# R58 firmware (v3_Z ALs 24.09.2018): system spec for emulator writers

Source: `r58/r58.asm`. Every "Lnnnn" below is a line number in that file.
Addresses come from `r58/build/r58.lst`, built with `as80 -DP8x` (Makefile).
With `-DP8x` both `P8N` and `P8E` are defined (L387-390). One binary runs on both
CPU cards. It detects which card it is on at runtime (`check_for_P8E_cpu`, L14791).

Tags used below:
- **[FW]**: the firmware does this for certain.
- **[EXPECT]**: the firmware's behaviour implies this about the hardware.
- **[UNKNOWN]**: the firmware source does not determine this.

---

## 0. Clocks, CPU and wait states

- P8N: Z80 at 4.032 MHz with no wait states. P8E: Z80 at 8.064 MHz with one extra T-state on every M1 cycle. Each CB/ED/DD/FD prefix byte is its own M1, so it also gets the extra T. [FW] Comments at L14785-14786 and L3470-3476, and the per-instruction T counts in the P8E loops (L14502-14530, L3491-3515) all say this. History notes at L316-318 say the author replaced "double-M1 instructions" to fix P8E timing.
- 8254 (TMR, 0x20-0x23): CLK0 and CLK1 run at 4.032 MHz on both cards. CLK2 runs at 1968.75 Hz, which is 4.032 MHz / 2048. All GATEs are tied high. [FW] Comment at L941-946. The CTCSS note at L13400-13404 says the i8254 CTCSS method needs CLK2 rewired to 4.032 MHz. With that rewire, counter 2 is programmed with `4032000*10/dHz` (L13499-13506, L13550).
- PA0 (`PA_CLK2`) carries the same 1968.75 Hz square wave. It is the system time base (§7).
- SIO clock: `WR4_X1_CLK` is commented "153600 bd" (L617), so TxC/RxC is 153.6 kHz on both channels. That gives x16 = 9600 baud, x32 = 4800 baud and x64 = 2400 baud (L617-620). [EXPECT]
- **CPU detection, `check_for_P8E_cpu` (L14791-14830).** It programs counter 1 as LSB-only, mode 0 (`0x50`), loads 65, runs 20 NOPs, then reads counter 1 back.
  - P8N: 80 T is about 19.8 µs, more than 65 counts, so the counter has wrapped and bit 7 is set. `cpu_is_P8E` (0xD015) becomes 0.
  - P8E: 100 T is about 12.4 µs, so bit 7 is clear and `cpu_is_P8E` becomes 1.
  - The emulator therefore needs a free-running 8254 counter 1, clocked in step with CPU T-states (1:1 on P8N, 1 count per 2 T on P8E), with mode-0 readback of the LSB. `cpu_is_P8E` selects the timing loops for AX.25, DTMF and SiRF bit-banging.

## 1. Memory map

| Range | What | Source |
|---|---|---|
| 0x0000-0x7FFF | 32 KiB ROM. Code ends at 0x7FD1: "TheEnd" plus one checksum byte that makes the 8-bit sum of 0x0000..0x7FD0 zero. The firmware never checks it. 0x7FD1-0x7FFF are unused. | L18802-18807, `.cksum` L18803 |
| 0x8000-0xBFFF | Second ROM socket, used as an input port (below). Only 0x80xx is ever read. | L7-9, L1916, L3150 |
| 0xC000-0xFFFF | 16 KiB RAM. Work RAM, the NV block and the stack. | L18814, `ld sp,0` L821/L863/L1054 |

### 1.1 Second ROM socket at 0x8000 (read only)

- The low address byte is don't-care (L3150). The high byte must be 0x80: the code uses `ld h,0x80; ld a,[hl]` and `ld b,0x80; ld a,[bc]`.
- The data byte is `StD Q4 Q3 Q2 Q1 x x CTCSS` (L3151, L8-9):
  - **D7 = StD** of an MT8870-style DTMF decoder, active high. The test is `cp 0x80; jr nc` (L3152-3153).
  - **D6..D3 = Q4..Q1**, the DTMF code. It is extracted as `(A & 0xF8) >> 3 & 0x0F` (L3158, L3169-3172) and mapped through `dtmf_8870_tab` = {D,1,2,3,4,5,6,7,8,9,0,*,#,A,B,C} for codes 0..15 (L1484-1485).
  - **D2..D1**: don't care.
  - **D0 = output of the CTCSS low-pass/slicer** ("DTMF-ROM-multiboard"). The software CTCSS DSP decoder samples it on every PIO-A interrupt (L1905-1918).
- The same raw value is compared with `0x80|(0xB<<3)` to detect DTMF `*` (L15085).
- An FX465 CTCSS chip is loaded serially through OUT1 SD/CLK/TPS (`load_fx465`, L13585-13640). The history note "fx465 in rom socket" (L281) refers to that hardware add-on.
- Emulator default: return 0x00. That means no StD, and the slicer reads 0.

### 1.2 RAM layout (addresses from the listing)

| Addr | Symbol | Notes |
|---|---|---|
| 0xC000 | `nvstart` | Start of the non-volatile block (L18822) |
| 0xC000-0xC01B | core NV vars: `audio_dst, volume, squelch_forced, scan_on, scan_mask, mem_flags, mem_idx, rx_freq(0xC008), tx_freq(0xC00B), duplex_*, band*, vip_freq, mem_ctcss_*, band_autoreject` | L18824-18856 |
| +94 bytes reserved | then `ASSERT(. == 0xC07C)` | L18858-18860 |
| 0xC07C | `vip_list` (30 B) | L18864 |
| 0xC09A | `rfctab` (100 B) | L18869 |
| 0xC0FE | `memories`: 130 × 12 B (rx freq 3, tx freq 3, flags, ctcss tx, band, ctcss rx, 2 spare) | L18872-18890 |
| 0xC716 | `cfg_function`: start of the SETUP block (all `cfg_*`, `repeater_cfg_*`) | L18894-19262 |
| 0xC000+0xA9C | end of used NV. `chk_size_nvdata = 2716` bytes | L19264-19265 |
| 0xD000 | `nvend`. The NV block is exactly 4096 bytes | L19267-19268 |
| 0xD000-0xD015 | Initialised but **not** zeroed: `output_0/1, mbusrx_rp/wp, mbustx_rp/wp, synth_ctrl, rx/tx_refdiv, rx/tx_divisor, cpu_is_P8E` | L19272-19287 |
| 0xD016 | `_bss`. Zeroed at every start, up to `_end` | L19291, clear loop L1136-1146 |
| 0xD150 | `ad_bytes[8]`. Must sit at LO = 0x50 = AD port | L19463-19474 |
| 0xD200/0xD300/0xD400/0xD500 | page-aligned `ccir_history`, `dtmf_history`, `fsk_history`, `gps_history` (256 B ring buffers) | L19517-19520 |
| 0xD600/0xD700 | `mbusrx_buf`, `mbustx_buf` (256 B rings) | L19525-19526 |
| 0xD800.. | `ctcss_sintab`, `ax25_sintab`, `dtmf_sintab`; `segments` at 0xDB00; `indicators` at 0xDB40 | L19527-19532 |
| 0xDCE0 | `_end`. The stack grows down from 0xFFFF to here: 8992 bytes, with `ASSERT > 4 KiB` | L19561-19566 |
| 0xDCE0-0xECDF | Scratch buffer for `all_config_get`, which receives 4096 bytes here before copying them to `nvstart` | L18524-18560 |

### 1.3 RAM chip selects (OUT2, PIO B0, CSMEM)

- OUT2 (port 0x80) bits (L676-690):
  - 0x01 `RA14`, 0x02 `RA15`, 0x04 `RS`
  - 0x08 `SMEM`
  - 0x10 `CS1`, 0x20 `CS2` (CU select: 00 keypad, CS1 latch, CS2 LCD1, CS2|CS1 LCD2)
  - 0x40 `CLK`: CU shift clock, also I²C SCL for the CU58AF
  - 0x80 `DP`: CU serial data
- **RA14, RA15 and RS are always written as 0.** No code path sets them; every OUT2 value is built from `O2_XXX = O2_SMEM` plus the CS, CLK and DP bits (L685-690, L1072, L10207-10243, L11512-11578, L11976-11982, L14215-14216).
- **PB0 (`PB_RAMA12`) is always 0.** Every PIO-B data write has bit 0 clear: L1095, L1112, L2550 (`_a_b____`), L2570/2579, L10091 (0x80).
- **SMEM (OUT2 bit 3).** Normally 1 ("select ram 0, i hope, on P8N", L1071-1073). It is cleared only inside the three NV copy loops, `load_nvdata`, `save_nvdata` and `save_nvmisc_and_restart` (L14207-14290). Those loops toggle between `d = O2_LCD1 & ~SMEM` (0x20) and `e = O2_LCD1 | SMEM` (0x28), one byte at a time:
  - **load** (boot, L14270-14290): SMEM=0, read [addr]; SMEM=1, write [addr].
  - **save** (L14240-14265, DI around each byte) and **NMI save** (L14207-14237): SMEM=1, read; SMEM=0, write.
  - Addresses are 0xC000..0xCFFF only.
- **[EXPECT] P8N model.** With SMEM=0, 0xC000-0xCFFF maps to a separate, battery-backed 4 KiB "saved memory" plane. With SMEM=1 it maps to ordinary work RAM. The firmware never touches any other address while SMEM=0: interrupts are off and nothing is pushed.
- **CSMEM (port 0xB0), P8E only.** `out [CSMEM],1` once at start, commented "select full 16k page of ram on P8E, nop on P8N" (L1075-1076). It is never written again.
  - Comment L385: "P8E works all right with (unnecessary) P8N saves/restores".
  - **[EXPECT] P8E model.** OUT2.SMEM has no effect on RAM, so the copy loops are no-ops. The RAM at 0xC000-0xCFFF (at least) must itself be battery-backed. The CSMEM=0 semantics are **[UNKNOWN]**.
- **What must persist across power-off: 0xC000-0xCFFF (4096 bytes).** Everything from 0xD000 up is rebuilt at boot. Only `_bss` is zeroed; 0xD000-0xD015 is explicitly initialised.

### 1.4 NV validity and first boot

- **The firmware has no magic number or checksum for NV RAM.** `load_nvdata` copies it blindly (L1532, L14270) and the firmware uses whatever it finds. An all-zero image boots, but the radio is unconfigured: synth card S8D, all frequencies 0, and so on.
- The "666" guard, `check_for_666` (L18400-18405), does `a2i(digbuf)` and returns Z only if the digits typed into the keypad buffer equal 666. It also clears `digidx`. Every destructive setup action (`CFG_RST` records, group "dF", L18058-18065) calls it first:
  - `SAnE`, `sane_defaults` (L18409): calls `set_defaults_band` (L18343). That runs `reset_menurecords`, which writes each REC default from the table at L17747-18094 while keeping `cfg_synth_card`. It then copies the band table for S8B (6 m), S8C (2 m) or other (70 cm) (L18311-18341), calls `save_nvdata`, and ends in **`powerdown_now`**.
  - `ALLrSt`, `disaster` (L18414): zeroes 0xC000-0xCFFF except `cfg_synth_card`, then runs `set_defaults_band` (which also powers down).
  - `CH rSt`, `wipe_memories` (L18572); `rFcrSt`, `wipe_rfctab` (L18589); `rFcFIL`, `rfc_fill_blanks` (L18620).
  - `rEboot`, `do_reboot` (L18606-18611): `di; jp .`. It relies on the **watchdog** to reset the CPU.
  - `CFGSnd`/`CFGGEt`: see §5.2.
- To run one, the user enters setup, moves to the "dF" record, types `666`, and presses ENT (`menu_new_value_rst` L17502 jumps to the pointer).
- **Emulator recommendation:** ship a pre-made NV image, or run SAnE once. SAnE ends in `powerdown_now`, so the emulated power relay (PB7) must be able to power-cycle the machine.
- `save_nvdata` is called on:
  - leaving setup (L16833)
  - `execute` / store-memory (L4645, L9427)
  - `save_rfc` (L14168)
  - `set_defaults_band` (L18370)
- `save_nvdata` and `save_nvmisc_and_restart` do nothing while the I register is 0 (`ld a,iv; or a; jp z`, L14209-14211, L14242-14244). I is set to 0x01 only at the end of boot (L1594-1595). The comment at L1020 says "IV is a flag for save_nvxxx, boot complete". The start code never resets I, so after a warm restart (0x38, NMI or `jp start`) I is still 1.

## 2. Reset and boot sequence

### 2.1 Hardware reset entry at 0x0000 (L819-853)

1. `di; ld sp,0`.
2. OUT0 ← 0x08 (`O0_INH`, volume lowest). OUT1 ← 0x80 (`O1_TXOFF`).
3. Disabled code (`#if 0`, L829-833): `in PIOA; and PA_WDR; jp nz,.` ("Not watchdog reset ?!?"). **PA_WDR is not used.**
4. PIO A is programmed with the 5-byte `PIOA_INIT` sequence (L836-840, table L905-911, described in §3), so that `/PWR` can be read.
5. `in PIOA; and PA_PWR; jp nz, powerdown_now` (L841-843). **PA_PWR = 1 means the power switch is in the off position.**
6. A busy loop of 0x0FFF × (dec hl / ld a,h / or l / jr nz). That is about 106 kT: roughly 26 ms on P8N and about 15 ms on P8E. It is commented "Wait but not too long for defined wd state" (L847-852). This is the **first watchdog kick**: `out [WD],a` (L852). Then `jp start`.

### 2.2 RST 38 at 0x0038 (L859-864)

`di; out [WD],a; ld sp,0; jp start`. This is a crash trap: execution of 0xFF, meaning erased ROM or a floating bus. It does a warm restart without re-checking PA_PWR at 0x0000, but `start` checks PA_PWR itself.

### 2.3 NMI at 0x0066 (L870-875) and power-fail save

- `v_nmi`: `di; out [WD],a; jp save_nvmisc_and_restart` (L14207-14237).
  - If I ≠ 0, it copies work RAM 0xC000-0xCFFF into the NV plane, kicking the WD on every byte.
  - It then does `ld sp,1f; retn`, where `1: .word start`. That "returns" to `start`. IFF1 and IFF2 are both 0 because of the `di`.
- `start` then re-checks PA_PWR (L1109-1116, "check if restarted from powerdown nmi") and goes to `powerdown_now` if the switch is off.
- **[EXPECT]** Hardware raises NMI when the power switch is turned off or supply voltage fails. **PA_PWR is only read at 0x0000 and in `start`**; there is no runtime polling. So the emulator must raise NMI on power-switch-off, with PA3 = 1, for the radio to save NV and shut down.

### 2.4 `powerdown_now` (L10080-10095)

- `di`; OUT1 ← `O1_TXOFF`.
- If `cfg_function == 0` (Std): `out PIOB, 0x80`, which sets **PB7 = `PB_PWROFF` = 1** and drops the power relay. B0, EXAL and /RXON go low at the same time.
- In other functions (rPtr or SLAvE) the relay is kept on (history note L78).
- Then `halt; jp powerdown_now`, forever, with interrupts disabled. **No more watchdog kicks happen, so the watchdog eventually resets the CPU.** After that reset, 0x0000 sees PA_PWR and comes straight back here: the power switch must be ON to boot. **[EXPECT]** PB7 = 1 removes power. On the 0x0000 path PIO B is not configured yet (it is in its reset input mode), so the write only latches the value; the hardware relay presumably drops by itself.
- Other callers:
  - TX timeout (`once_per_minute`, L2467-2476)
  - IGN auto-power-off (`once_per_hour`, L2512-2523)
  - low battery (`battcheck_lobatt`, L4344-4371)
  - `set_defaults_band` (L18371)

### 2.5 `start` (0x0156, L1050-1177)

1. `di; out WD; ld sp,0`.
2. OUT0 ← 0x08 and OUT1 ← 0x80, with mirrors `output_0` and `output_1`.
3. OUT2 ← 0x08 (SMEM=1). CSMEM ← 1.
4. MDM control ← 0x00 (NMT modem off).
5. `piob_mode` ← 0x2E. `out PIOB, 0`.
6. Program the PIO: `otir` PIOA_INIT (5 bytes), then PIOB_INIT (5 bytes) (L1098-1107).
7. `out PIOB, 0` again. Check PA_PWR → `powerdown_now` (L1111-1116).
8. Program the SIO: channel A gets `in a,[c]` (a dummy RR0 read) followed by `otir` SIOA_INIT. Channel B does the same with SIOB_INIT (L1118-1128).
9. `check_for_P8E_cpu` (L1130). `init_timer1`: counter 1 in square-wave mode 16-bit, loaded with 0x0004. `ctcss_off_nohang`: counter 2 in mode 0 LSB, loaded with 1, "low for one clock then rise and stay" (L13445-13465).
10. Zero `_bss` through `_end`, kicking the WD on every byte. Re-set `piob_mode` = 0x2E (the 3.N fix). Initialise the MBUS ring pointers. `dark = ad_batt = nosir = 0xFF`. `pkt_ptr = packet`.
11. `start_continue` (L1519):
    - `cu_handler = cu_handler_unknown`, then `load_nvdata`, `init_modem` (MDM ctrl 0x04, about 10000-loop delay, then 0x00, L6012-6032) and `init_ctcss`.
    - A delay of about 2·256·256 iterations with WD kicks: "Give time for LCD to reset" (L1540-1557). At 4 MHz that is about 0.5 s.
    - `in [TMR+3]` (dummy, L1560; see §4.6).
    - Read PB1 (EXIN1). The result is unused (L1566-1569).
    - SIO B: `WR0 = RESET_ESCINT`, read RR0 into `sio_bctrl_mirror` and `sio_bctrl_local`. If the RR0 SYNC bit is set (/LOCAL grounded), `local_mode = 1` (L1571-1581).
    - `shift_external_serial_A/B`: 16 bits each through OUT1 SD/CLK with RAS or TPS strobes.
    - `ld i,0x01; im 2` (L1594-1596), then `jp main`.

### 2.6 `main` (0x0EF9, L3247-3296)

- `ei`.
- `probe_cu58af`, the CCIR/DTMF decoder init, `enable_modem` (MDM ← `RXENB` 0x04), volume, menu, LPF (counter 0 in square-wave mode, count 2016/(lpf_hz/20)), `zero_txpwr`.
- `cu_now_known`: sets `cu_handler` and **clears `nosir`**, which enables soft interrupts.
- Wait until no key and no PTT are down (L3261-3265).
- Synth and band setup, `repeater_init`, `update_gpio12_foo`.
- `gps_configure`, redraw twice, **then busy-wait until `seconds != 0`** (about 1 s; this needs systick running), then `gps_configure` again (L3277-3285).
- Optionally restart the scanner, `ctcss_dec_startstop`, then `mainloop` (§7).

### 2.7 Watchdog (port 0x90)

- **Writing any value to 0x90 kicks it.** There are 41 `out [WD],a` sites. The steady-state kick comes from `systick` at about 98 Hz (L2023). Long DI loops kick inline:
  - NV copies, the bss clear, the boot delays
  - SiRF bit-banging, one kick per byte
  - the DTMF/AX.25 PWM loops, once per cell
  - I²C delays
- **[EXPECT]** If the watchdog is not kicked it resets the CPU (pulls /RESET, so execution restarts at 0x0000). `do_reboot` (`di; jp .`, L18610) and the `powerdown_now` halt loop both depend on this. The timeout is **[UNKNOWN]**. It must be longer than the gap before the first kick (about 26 ms on P8N) and longer than the worst gap between systicks, which is about 10 ms plus systick's own run time. A value between 100 ms and 1 s is safe for emulation.
- Reading the WD port is never done. PA_WDR's meaning is **[UNKNOWN]**: the only code that uses it is disabled.

### 2.8 Master-ON (SIO B DTR, "SB_MON")

- `SB_MON = WR5_DTR` (L722). Both SIO init blocks write WR5 with RTS|DTR|TX_ENB|8 bits (L927, L935), so /DTRB goes active low right after the channel reset, at every `start`.
- **No code ever toggles DTR B afterwards.** The only "pulse" is the transition from channel reset (DTR inactive) to WR5 write (DTR active) at each boot.
- **[EXPECT]** The hardware derives the Master-ON line or pulse (MBUS power-on for other units) from /DTRB.

## 3. Z80 PIO (ports 0x00 A data, 0x01 B data, 0x02 A ctrl, 0x03 B ctrl)

### 3.1 Init words (`init_chips`, L905-921)

- **Port A**: vector `0x50` (→ table 0x0150 = `pioa_int`); `0xCF` mode 3; `0xFF` all 8 bits input; `0x97` interrupt control; mask `0xFE`.
  - 0x97 means interrupts enabled, OR function, active LOW, mask follows.
  - Mask 0xFE: only A0 is monitored.
  - Result: **one interrupt each time PA0 (1968.75 Hz) goes low**, i.e. 1968.75 interrupts/s.
- **Port B**: vector `0x52` (→ `piob_int`, which only does `ei; reti`); mode 3; direction `0x3E`; `0x97`; mask `0xFF`, so no bits are monitored and port B never interrupts. A mask of 0xDF (monitor B5) is commented out at L917.
- At runtime **PIO A's vector is reloaded** with `0x54` (`pioa_base_during_ctcss`), a control write with D0 = 0, in `ctcss_revector` (L13733-13737). This happens when the DSP CTCSS decoder or the RFC-DAC CTCSS encoder starts. The vector is never set back to 0x50; the handler at 0x54 dispatches through jump pointers instead.
- **[EXPECT]** Standard mode-3 PIO behaviour. An interrupt raised while the previous one has not been acknowledged is lost. Interrupts stay off in the CPU until the handler's `ei`, so systick's run time can swallow edges.

### 3.2 Port A pins (all inputs, L696-700)

| Bit | Name | Meaning / polarity |
|---|---|---|
| 0 | PA_CLK2 | 1968.75 Hz square wave, the time base. Falling edge raises the interrupt. |
| 1 | PA_HOOK | Handset hook switch. Changes are detected in systick (L2028-2057). **The polarity is inconsistent in the source.** Bit 0 selects `script_req = 1` = `cfg_onhook_script` (L2041-2047). But `once_per_second` treats bit 0 as "handset off cradle" (L2338-2340). Pick one and check against real behaviour; the sitter comment suggests 1 means on-hook. |
| 2 | PA_WDR | Watchdog-reset status. Unused (only `#if 0` code at L829-833). |
| 3 | PA_PWR | Power switch. **1 = off** (L841-843, L1114-1116). Read only at reset and in `start`. |
| 7..4 | PA_CCIR | 4-bit code from a CCIR selcall tone decoder. 0xF = no tone, 0xE = repeat tone, 0x0-0x9/A-D = tone digit (decoder L2927-3005). The repeater treats nibble 0x8 as "1750 Hz tone" (L15077-15080, L15108-15111). |

### 3.3 Port B pins (L702-714)

| Bit | Name | Direction | Meaning |
|---|---|---|---|
| 0 | PB_RAMA12 | out | RAM A12, always 0 |
| 1 | PB_EXIN1 (/POR) | open-collector via direction | Pulled low while the squelch is open ("SERV"): `pull_down_EXIN1` L2701, released L2762 and L10686 |
| 2 | PB_EXIN2 (/IGN, /EMG) | open-collector via direction | Input: /IGN; `once_per_hour` treats 1 as "ignition off" for the auto power-off timer (L2516-2518). Output: GPio2 bit c (`cfg_gpio2_state & 2`, 0 = pull down), L2552-2555 |
| 3 | PB_DCU | open-collector via direction | CU53 serial data from the keypad (key code, LDR "dark" bit) (L10228, L10247); I²C SDA for the CU58AF (L11944-11970). Released = input = high |
| 4 | PB_RXOFF (/RXON) | out after the first `update_gpio12` | GPio2 bit b (`cfg_gpio2_state & 1`) |
| 5 | PB_TMR0 | in | External CTCSS detector input; `cfg_ctcss_input_method` 1 = positive, 2 = inverted (L2591-2601) |
| 6 | PB_EXAL | out | GPio1 (`cfg_gpio1_state`), or a pulse via `pulse_gpio1` (L2557-2582) |
| 7 | PB_PWROFF | out | **1 = power relay off** (L10090-10091) |

- **Direction at runtime.** Init programs `0x3E` (B1-B5 inputs). The variable `piob_mode` holds 0x2E (`PB_INPUTS` = EXIN1, EXIN2, DCU and TMR0 inputs; B0, B4, B6 and B7 outputs).
- Every `pull_down_*` / `release_*` (L3210-3243) clears or sets one bit of `piob_mode`, then rewrites the direction with the pair `0xCF, piob_mode` to B ctrl. So after the first call (`update_gpio12` at boot, L3273 → L2555), B4 becomes an output. The interrupt word and mask are not rewritten.
- The output latch for B1, B2 and B3 is always 0: open-drain is emulated by switching direction. **An emulator must model PIO-B direction changes. In mode 3, a bit reads the pin level when it is an input and the output latch when it is an output.**
- Data writes to B: 0x00 at init; `_a_b____` (EXAL/RXOFF) in `update_gpio12`; 0x80 in powerdown.

## 4. Z80 SIO (0x10 A data, 0x11 B data, 0x12 A ctrl, 0x13 B ctrl)

### 4.1 Channel A (GPS / NMEA, L923-928)

- `WR0 = 0x18` (channel reset).
- `WR4 = 0x84`: x32 clock = **4800 baud**, 1 stop bit, no parity.
- `WR3 = 0xC1`: Rx 8 bits, Rx enabled.
- `WR5 = 0xEA`: Tx 8 bits, TX enabled, RTS and DTR asserted.
- `WR1 = 0x17`: ext/status int enable, Tx int enable, status-affects-vector (only meaningful on B), Rx int on all characters with parity affecting the vector.
- Runtime WR4 changes: see §6.

### 4.2 Channel B (MBUS, L930-937)

- Same as A, except `WR4 = 0x44`: x16 = **9600 baud**, 8N1.
- **`WR2 = 0x40`**: vector base. With I = 0x01, vectors land at 0x0140-0x014F.

### 4.3 Vector table at 0x0140 (L1023-1043), status affects vector

| Vector | Offset | Handler | Line |
|---|---|---|---|
| 0x40 | B Tx buffer empty | `siob_tbe` | L1616 |
| 0x42 | B ext/status | `siob_esc` | L1680 |
| 0x44 | B Rx char available | `siob_rca` | L1643 |
| 0x46 | B special Rx | `siob_src` (read and discard data, WR0 = 0x30 error reset) | L1702 |
| 0x48 | A Tx buffer empty | `sioa_tbe` | L1714 |
| 0x4A | A ext/status | `sioa_esc` | L1758 |
| 0x4C | A Rx char available | `sioa_rca` | L1740 |
| 0x4E | A special Rx | `sioa_src` | L1868 |
| 0x50 | PIO A | `pioa_int` | L1984 |
| 0x52 | PIO B | `piob_int` | L1885 |
| 0x54 | PIO A (CTCSS) | `pioa_int_during_ctcss` | L1958 |

- Every handler ends with `ei; reti`. **[EXPECT]** Standard Z80 daisy-chain IEI/IEO with RETI decoding. The priority order between PIO and SIO is **[UNKNOWN]**.

### 4.4 Modem-control inputs (RR0) and polarity

The Z80 SIO **RR0 bits for DCD (D3), SYNC/HUNT (D4) and CTS (D5) are the inverted pin levels**: bit = 1 when the /pin is low. The firmware comments this at L1577, L1795, L4462, L9798 and L11607. The bits latch on change until `WR0 = 0x10` (reset ext/status). The firmware always writes that command before re-reading, or after reading inside the handler.

| Channel / bit | Name | Meaning (as bit value) | Source |
|---|---|---|---|
| B CTS (0x20) | SB_PTT | 1 = /PTT pin low = **PTT pressed** | L719, `is_ptt_pressed` L4458-4466 |
| B SYNC (0x10) | SB_LOCAL | 1 = /LOCAL grounded. Sets `local_mode` at boot (L1571-1581); APRS aux-PTT (`aprs_ptt_check` L9792-9867, TX while bit = 1); a rising /LOCAL re-opens the repeater (L14886-14896); `local_mode` also allows TX outside the band limits (L12394) | L720 |
| B DCD (0x08) | SB_DMIDLE / NETFREE | "No MBUS activity". **Defined but never read.** The firmware does not check that the bus is idle before transmitting | L721 |
| A CTS (0x20) | SA_DA | CU53: DA pin; bit 0 = DA high = key made (L1793-1814). CU58AF: /INT; bit 1 = /INT low = key event (L1816-1824). Idle: CU53 DA low → bit 1; CU58AF /INT high → bit 0; `probe_cu58af` relies on this (L11599-11615) | L717 |
| A DCD (0x08) | SA_KKINT | Defined but not tested. **[EXPECT]** This is the NMT modem (MDM) interrupt: every SIO-A ext/status interrupt calls `modem_handler`, which polls MDM status (L1758-1768, L1826-1864). Comment L1754: "CU53_DA or CU58AF_INT, HK, Modem and timer OUT2 … uncommitted SYNC_A" | L716 |

- **Important.** PTT and LOCAL are read **only from `sio_bctrl_mirror`**, which is updated only in `siob_esc` (L1680-1698) and at boot. So the emulator **must raise an SIO B ext/status interrupt** when /PTT, /LOCAL or /DCD change.
- It must also follow the real latch semantics: after `RESET_ESCINT`, if the pin state differs from the latched value, raise a new interrupt.
- The DTMF/AX.25 PWM loops poll SIO A RR0 CTS directly. They issue `RESET_ESCINT` before each `in` to get the live level (L14486-14489, L14526-14529).

### 4.5 Interrupt use

- **Rx A** → GPS ring (§6).
- **Rx B** → MBUS ring (§5).
- **Tx A** → sends the zero-terminated `gps_upload_ptr` string. At the terminator it issues `WR0 = 0x28` (reset Tx int pending) (L1714-1735).
- **Tx B** → drains `mbustx_buf`; `WR0 = 0x28` when the count reaches 0 (L1616-1640).
- **Ext/status A** → CU handler, modem handler, then `in [TMR+3]`, then `WR0 = 0x10`.
- **Ext/status B** → mirror RR0, then `WR0 = 0x10`.
- **Special Rx** (overrun, framing, parity) → discard the byte and `WR0 = 0x30`.

### 4.6 BREAK use (GPS SiRF init, L3466-3530)

- Channel A `WR4 = 0x04` (x1 clock, "crispy BRK twiddling").
- With DI, each bit of the 32-byte SiRF message is bit-banged at 38400 baud, 8N1, LSB first. For each bit the code writes WR5 = `0xEA` (mark) or `0xEA|0x10` (**SEND_BREAK** = space).
- Timing: 96 T/bit on P8N and 210 T/bit on P8E (padding via `cpu_is_P8E`).
- Afterwards `WR4 = 0x84` (4800 baud x32) and `ei`.
- **[EXPECT]** TxDA = NOT(WR5.D4) while the transmitter is idle. An emulator that samples TxD at 38400 baud can decode this.
- `in [TMR+TMRCTRL]` (reading 8254 port 0x23, which is illegal on an 8254) is done at boot and in every SIO A ext/status interrupt. It is commented "dummy read to raise PIO B5 (remove int)" (L1560, L1765). **[EXPECT]** An I/O read of 0x23 clears a hardware interrupt latch. That latch comes from the old TMR0/B5 wiring and may drive an SIO A modem input. For emulation, treat a read of 0x23 as "clear the latch".

## 5. MBUS on SIO B (9600 8N1)

### 5.1 Transport

- **TX.** `putchar(C)` (L10101-10124) blocks while `mbustx_cnt == 255`. If TX is idle it writes directly to the data register; otherwise it queues into the 256-byte ring `mbustx_buf` (0xD700) and `siob_tbe` sends it. `iputc` (L10126-10151) is the non-blocking, drop-when-full version.
- **Echo suppression.** Every transmitted byte sets `mbus_timer = 25` (L1634-1635, L10121-10122, L10149-10150). The timer decrements once per systick (L2093-2101). **`siob_rca` discards every received byte while `mbus_timer != 0`** (L1648-1651). A host must therefore **not send anything for about 255 ms after the last byte the radio sent**. This is a single-wire half-duplex bus: the radio's own echo is dropped by the same rule.
- **RX.** Ring `mbusrx_buf` (0xD600), 255 usable bytes. Bytes arriving when it is full are dropped (L1654-1669). `getchar` (L10153-10166) blocks.
- **Nothing consumes MBUS RX in normal operation** unless `cfg_bus_rf_relay` is on (§5.3), or the user is inside `CFGGEt`. If neither applies, the ring fills and later bytes are dropped.
- **There is no MBUS command protocol for remote keypad or display control in this firmware.** A PC can do these things:
  1. Receive MPRS/APRS position reports (§5.4).
  2. Back up and restore the whole NV block (§5.2); the radio operator starts each transfer.
  3. Inject 12-byte payloads that the radio sends as FSK 0x50 packets (§5.3).
  4. Receive FSK 0x5x packets as nibbles (§5.3).
  5. Key the transmitter through the /PTT line (SIO B /CTS), or run APRS aux-PTT through /LOCAL (SIO B /SYNC). These are hardware lines, not data.
- **"Remote config" and "remote display" travel over the RF FSK modem (NMT MDM chip, ports 0xA2/0xA3) between radios, not over MBUS** (§5.5).

### 5.2 Config Send / Get (setup group "dF", L18058-18059; code L18436-18570)

Both require `666` typed first.

**`CFGSnd`, `all_config_send` (radio → host)**, in this order:
1. The banner bytes from `banner` (0x0070) up to, but not including, EOS 0xFF:
   `"R58 v3_Z ALs 24.09.2018 P8E/P8N S8B/S8C/S8D CU53xx/CU58AF\n"` (L880-897).
2. The length as a little-endian word: `0x00 0x10` (4096).
3. 4096 raw bytes of 0xC000..0xCFFF.
4. One checksum byte = −(8-bit sum of the 4096 data bytes). So the sum of data plus checksum is 0 mod 256.

**`CFGGEt`, `all_config_get` (host → radio)**:
1. The radio purges the RX ring, shows "ready" (`feedback_ready`), then blocks in `getchar`. Mainline is blocked, but interrupts and the watchdog keep running.
2. The host sends: any banner text ending with `'\n'`, the first byte of which triggers "loading"; then `0x00`, `0x10`; then 4096 data bytes; then the checksum byte (data sum + checksum ≡ 0).
3. If the length bytes or the checksum are wrong, the radio shows "error" (`feedback_error`) and nothing is written. If they are right, it copies the buffered data from 0xDCE0 to 0xC000. It does **not** call `save_nvdata`: on P8N the NV plane is updated only at the next save point or NMI.
4. The host must respect the 250 ms echo window before sending, and the 255-byte ring. The radio reads as fast as it can; the ring overruns only if the host floods the radio while its mainline is stalled.
5. A host tool can simply replay a file captured with CFGSnd.

### 5.3 MBUS ↔ RF relay (`cfg_bus_rf_relay`, record "Pr buS rF" L17775)

- **MBUS → RF** (`bus_rf_relay` L3327-3349, called from mainloop when enabled). When at least 12 bytes are buffered it takes 12, builds `outpacket = 0x50, b0..b11`, appends a long CRC (bytes 13-14), and sends a 15-byte FSK frame (`send_packet_buffer`). It does **not** key the transmitter itself (no `tx_on`).
- **RF → MBUS** (`handle_relay_packets` L6254-6265). For any received FSK packet whose first nibble is 5, it `putchar`s **12 bytes, each holding one nibble (0x00-0x0F)** from `fsk_history`, starting at the tag's high nibble. So for 0x50 it sends 05 00 followed by the first 5 payload bytes split into nibbles.
- The relay is not symmetric, probably a firmware bug. An emulator should reproduce it as written.

### 5.4 MPRS / APRS reports out on MBUS (`cfg_mbus_mprs`, "Pr buS Fn": 0 oFF, 1 tnc, 2 KISS, 3 3rd P, 4 LoGGEr; L17771, L18180-18185)

**Trigger.** A received FSK MPRS packet (tag 0x4x, `handle_mprs_packets` L6660-6758) with a valid position: bit 7 of the lat-degrees byte clear.

- `remote_display_buffer` (0xD10C) gets the callsign, with trailing blanks stripped and `-N`/`-1N` appended when the SSID is nonzero. The terminator is EOS 0xFF.
- The locator goes to `locator_display_buffer`.

**Lat/lon formats** (`mprs_lat_format` / `mprs_lon_format`, L8006-8043):
- Latitude `DDMM.mm`, longitude `DDDMM.mm`.
- Hemisphere: N/S from bit 7 of the lat centiminute byte; E/W from bit 7 of the lon centiminute byte.

**Symbol character.** The symbol nibble is (lat minutes byte bits 7:6) << 2 | (lon minutes byte bits 7:6). It maps through `symbol_nibble_to_primary_symbol` (L3892-3908): `p > v s - + r c 0 1 2 3 4 5 6`. Nibble 15 means "use the SSID" and maps through `ssid_nibble_to_primary_symbol` (L3910-3926): `/ a U f b Y X ' s > < O j R k v`.

**Output formats:**

1. **tnc** (L7826-7864):
   `CALL[-SSID]>APRS,RELAY,WIDE:!DDMM.mmN/DDDMM.mmE<sym>\r\n`
2. **KISS** (L7974-8004):
   `C0 00` + dest address `"APRS  "` (each char << 1) + SSID byte `0x60` + source (6 chars << 1, space-padded) + SSID byte `0x60|(ssid<<1)|1` + `03 F0` + `!DDMM.mmN/DDDMM.mmE<sym>` + `C0`.
   Address bytes are FEND/FESC-escaped (`DB DC` / `DB DD`); the info field is not escaped. There is no CRC.
3. **3rd party** (L7866-7895):
   `}CALL[-SSID]>APRS,MPRS*:!DDMM.mmN/DDDMM.mmE<sym>\r` (CR only).
4. **Logger** (L7682-7767):
   `HHMMSS DDMM.mmN DDDMM.mmE LLLLLL S RR CALL[-SSID]\r\n`
   - HHMMSS is the radio's own `gps_utc`, converted to ASCII. **Without a GPS fix this field is garbage** until an RMC sentence has arrived.
   - LLLLLL is the 6-character Maidenhead locator computed from the packet.
   - S is the symbol nibble as one hex digit.
   - RR is `packet_rssi` as two hex digits.

### 5.5 FSK packet formats (radio ↔ radio via MDM; context only)

**Frame on air.** The preamble `AA AA AA` and sync `C4 D7` (L9336-9341) are followed by 8 bytes (short) or 15 bytes (long).
- CRC: the table at `crctbls` (0x0200) is the reflected CCITT table (poly 0x8408). Init 0xFFFF, result complemented. **The high byte is stored first**, at [n], then the low byte at [n+1] (L9100-9160).
- Short frame: CRC over bytes 0-5, stored at 6-7.
- Long frame: CRC over bytes 0-12, stored at 13-14.
- Frames with tag `0xEC` seed the CRC with the 8 bytes of `cfg_remote_passwd` before the data (L9127-9137, L9230-9236).
- The receiver tries a short CRC at byte 8, then a long CRC at byte 15 (`modem_handler` L1826-1864, `check_*_packet` L9187-9299). It stores the data bytes into `fsk_history` as nibbles, then `packet_for_whom` (L6232-6252) dispatches on the first nibble.

**Tags:**
- `0xC` Call (selcall): `C m1 | m2 m3 | m4 m5 | digits…`.
- `0xAC` Ask-config (short): `AC idlo idhi ptrlo ptrhi FF FF FF`.
- `0xEC` Enter-config (long, password-seeded CRC): `EC idlo idhi ptrlo ptrhi d0..d7`.
- `0xDC` display-config reply (long): `DC` + 8 bytes read at the pointer. Pseudo-pointers: 0 = version, 1 = rfc + rssi, 2 = squelch, 3 = squelch-BIG.
- `0xDD` display data: 8 bytes go into `remote_display_buffer` for 5 s.
- `0x4x` MPRS: 6-byte packed callsign with the SSID in byte 4's high nibble, a reserved byte, 3 bytes lat and 3 bytes lon.
- `0x5x` relay.
- Config packets are accepted only when `cfg_remote_id != 0` and the ID matches. The password area (`cfg_remote_passwd`, 0xC913) can be neither read nor written remotely (L6268-6348).

## 6. GPS on SIO A

- **Baud / format by `cfg_gps_config`** (record "PH GPSCFG" L18056; table L18254-18259; `gps_configure` L3352-3408). It is applied twice: once at boot and again after 1 s (L3277-3285).
  - 0 `Std`: nothing is done; stays at **4800 8N1**.
  - 1 `SirF`: bit-bangs `gps_init_block_SiRF_generic` at 38400 through BREAK (§4.6), then 4800 8N1. The block (L3412-3432) is `A0 A2 00 18 81 02 01 01 00 01 05 01 01 01 02 01 00 01 00 01 00 01 00 01 00 01 12 C0 01 68 B0 B3`: switch to NMEA at 4800 baud with GGA 1 s, GSA 5 s, GSV 1 s, RMC 2 s.
  - 2 `SirFt`: the same with `gps_init_block_SiRF_tailored` (RMC every 1 s only, checksum `01 60`), L3434-3452.
  - 3 `AiSin`: `WR4 = 0x47`, **9600 baud, 8 bits, even parity**. Binary protocol, no NMEA.
  - 4 `9600Std`: `WR4 = 0x44`, **9600 8N1** NMEA.
- **RX path.** `sioa_rca` stores every byte into the 256-byte page ring `gps_history` (0xD500) at `gps_hist_idx`. There is no overflow check; the ring simply wraps (L1740-1752). Mainline `gps_check` (L3535-3600) assembles text from `$` to LF into `gps_sentence[100]`; the `$` is dropped and CR is kept. Sentences shorter than 10 characters are ignored.
- **NMEA parsing.** **Only `$GPRMC` is parsed** (`str_gprmc` L3928; `gps_process_sentence` L3932-3951). `GNRMC` and other talker IDs are ignored.
  - A checksum is required: XOR of the characters between `$` and `*`, followed by two hex digits, upper or lower case (L3830-3869).
  - Fields (L3954-4199):
    - UTC `HHMMSS` must be 6 digits; any `.sss` is skipped.
    - Status must be `A`.
    - Latitude: digits before the point are shifted into 5 digit slots (so `DDMM` becomes 0 D D M M); then the first 2 decimal digits; then N/S. Stored into `cfg_gps_latitude` (0xC9BA, NV).
    - Longitude: `DDDMM.mm`, then E/W, into `cfg_gps_longitude` (0xC9C2).
    - Speed in knots, rounded at the first decimal, into `gps_knots`; km/h (capped at 255) into `gps_speed`.
    - Course, integer rounded, into `gps_course`.
    - Date `DDMMYY`, stored as `gps_date` = YYMMDD.
    - Magnetic variation is ignored.
  - On success: `gps_own_locator` updates `cfg_gps_locator`, and `gps_valid_seconds = 5`.
- **Aisin-Seiki binary** (L3605-3805). Frame: `CA CA` + 40 payload bytes + checksum + `0D`. The checksum is the complement of the 8-bit sum of `CA CA` and the payload, so the total including the checksum is 0.
  - Payload [0]: fix quality; 3 = 2D, 4 = 3D, with bit 0x10 masked off.
  - [1..4] and [5..8]: latitude and longitude, MSB first, in units of 1/256 arc-second.
  - [13..14]: heading in 1/1024 of a circle.
  - [16..17]: speed in units of 0.25 m/s.
  - [22..27]: YYMMDDHHMMSS in packed BCD.
  - [35..38]: satellite status.
- **GPS output: waypoint upload** (`cfg_gps_upload` "Pr GPSUPL": 0 oFF, 1 GPWPL, 2 MAGELL; `gps_mprs_call_latlon` L8078-8200). Sent when an MPRS packet is received, at the current SIO A baud. The radio writes `$` directly, then the Tx interrupt sends the rest up to the NUL:
  - `$GPWPL,DDMM.mm,N,DDDMM.mm,E,CALL-SSID*XX\r\n`
  - `$PMGNWPL,DDMM.mm,N,DDDMM.mm,E,,,CALL-SSID*XX\r\n` (altitude and unit left empty)
  - XX is the XOR of the characters after `$`.

## 7. Time base, main loop and soft interrupts ("sir")

### 7.1 PIO-A interrupt (1968.75 Hz), L1984-2020

- Entry: `ex af,af'; exx`. **The alternate register set belongs to the interrupt handler.** E' counts down systick and D' counts down the ADC reader. Mainline code must not use EXX or EX AF, except under DI (for example the DTMF PWM loop).
- `dec e; jr z, systick` fires every 20 interrupts: **98.4375 Hz** ("100 Hz"). It reloads E' = 20 and D' = 3.
- `dec d; jr z, adc_reader` fires every 4 interrupts: about 492 Hz.
  - `adc_reader` (L2000-2020) walks a 16-entry channel list (L1892-1901): IN7, TP4, RSSI, SQL, BATT, RSSI, SQL, TPC, RSSI, SQL, FPM, RSSI, SQL, RPM, RSSI, SQL.
  - `ini` from port `AD+next` stores **the result of the previous conversion** into `ad_bytes[prev]`. Then two `out [AD+next]` writes (settle, then start) begin the next conversion.
  - **[EXPECT] ADC model.** OUT to 0x50+n starts a conversion of channel n. IN from any 0x50-0x57 returns the last conversion result.
  - Channels: 0 RSSI, 1 SQL, 2 BATT, 3 TPC, 4 FPM, 5 RPM, 6 TP4 (temperature), 7 IN7 (L515-522).
  - **BATT scale: 15.6 V full scale (value = V·256/15.6).** Below 9 V, or 8 V after TX, the radio shows low-battery and powers down after 5 s unless the reading recovers above 10 V (L4344-4411). **The emulator must return BATT of about 180-200 (11-12 V).**
- If the CTCSS vector (0x54) is active, it first runs the RFC-DAC encoder (`out DA0`) and/or the DSP decoder (reads 0x80xx bit 0) through `ctcss_enc_jump` / `ctcss_dec_jump` (L1905-1981).

### 7.2 `systick` (L2022-2252), running in the ISR with interrupts off

In order:
1. WD kick.
2. Hook-change detection (L2028-2057).
3. Scanner timers, marker-tone timer (restores OUT0 and stops the tone), `mbus_timer`, `ccir_tx_timer`, `txtail_timer`.
4. Keypad debounce: `keydown` counts to 10, then sets `KEYSIR`. Then typematic.
5. If no TX in the last 100 ms and no tone: `ctcss_dec_periodic`, `squelch`, `rssi_disp`, `ccir_decoder` (reads PIO A), `dtmf_decoder` (reads 0x80xx).
6. Repeater 10 ms work.
7. The clock: `sec100`, `seconds`, `minutes`, `hours`, with `once_per_second` (L2283), `once_per_minute` (L2451: TX TOT, idle timer, unreject) and `once_per_hour` (L2512: IGN APO, modem re-enable).

### 7.3 Soft interrupt, "sir" (L2211-2281)

- `sir` (0xD0AC) bits: 0 `KEYSIR` → `keypad`, 1 `DPYSIR` → `display`, 2 `DTMFSIR` → `i2c_dtmf` (CU58AF only), 7 `INSIR` = re-entry guard (L19337-19342).
- At the end of systick, if `nosir == 0` and `sir != 0` and INSIR is clear, it sets INSIR, restores AF, and pushes AF, BC, DE, HL, IX and IY.
- It then does `call 8b`, where 8b is `ei; reti`. **This RETI ends the hardware interrupt for the daisy chain while execution continues in the handler.** Then `call dosir` runs keypad and display with interrupts enabled, nested above the interrupted mainline.
- Afterwards: `di`, clear INSIR, pop the registers, `ei; ret` back to the interrupted code.
- **The emulator must decode RETI for the PIO/SIO interrupt-under-service state**, or no further interrupts will be acknowledged.
- `nosir`:
  - 0xFF from `start` until `cu_now_known` in `main` (L1161, L11586-11597).
  - Bit 0 is set while `send_packet_buffer` feeds the modem (L9301-9330).
- `halt` is used as a delay of about 0.5 ms (one PIO-A interrupt): in `tx_on` (L13058) and `ctcss_off` (L13437-13438).

### 7.4 `mainloop` (0x0F5B, L3298-3321)

The loop never halts. In order it calls:

1. `redrawcheck`
2. `battcheck` (ad_batt)
3. `pttcheck` (PTT held: `tx_on`, then loops until release; L9578-9681)
4. `aprs_ptt_check` (/LOCAL)
5. `keycheck` (`key` from `keypad`)
6. `fskcheck` (`packet_rdy`)
7. `ccircheck`
8. `dim_lights_if_idle`
9. `idlefn_check`
10. `script_check` (hook scripts)
11. `scanner_run`
12. `repeater_run`
13. `gps_check` (NMEA/Aisin ring)
14. `bus_rf_relay`, if `cfg_bus_rf_relay`
15. `spontaneous_mprs_check`, if `cfg_spontaneous_mprs`

## 8. Other I/O ports touched (for completeness)

- **OUT0** (0x60): VOLUME[2:0], INH, AUDIOC, CCIRC, MTC, MICM (L653-660).
- **OUT1** (0x70): SRE, SCE, STE, CLK, SD, RAS, TPS, TXOFF (L662-669). TXOFF = 1 means no TX. SD/CLK serve the synth and the external shift registers; RAS/TPS are strobes.
- **DA0** (0x30) is the RFC DAC; **DA1** (0x40) is TX power.
- **MDM** (0xA0): data at +2, control/status at +3. Control bits TXENB 01, TXPAR 02, RXENB 04, RXFMT 08, TIMER F0. Status bits RXRDY 01, RXTRUE 02, DCD 04, TXRDY 08, TXIDL 10, TMRINT 20, SYNC 40, SYNT 80 (L531-549).
- **8254 counters**: counter 0 is the TX audio LPF clock (square wave). Counter 1 is the marker/CCIR/DTMF/AX.25 tone and PWM output (square wave, or mode 0 for PWM). Counter 2 is the CTCSS square wave (needs the CLK2 rewire) or idle-high (mode 0 with count 1).
