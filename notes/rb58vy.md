# RB58VY (L8M logic board)

Status (2026-10-08): **our firmware runs on L8M** in the emulator:
`make -C r58 l8m` builds `r58/build-l8m/r58.bin` (64 KB: EPROM0 =
0x0000-0x7FFF, EPROM1 = 0x8000-0xFFFF). Tested in `tests/r58/test_l8m.py`
(SAnE, 6 m RX/TX synthesizer, TX keying and power, setup menu, the EEPROM
copy and its restore after a supply cut). Not tried on a real radio. CI builds it (`make l8m`) and runs the
tests; releases carry it as `r58-l8m-*` (the 64 KB image and its two 32 KB EPROM halves, notes/ci.md; since 2026-10-09). The
P8x build is unchanged by the `#ifdef L8M` code (its image changed only by
the keypad fix below). The emulator side: `emu/notes/r58.md` "L8M".

## The radio

Mobira RB58VY: a low-VHF mobile for the VY-85 trunked system, 25 W /
2.5 W, CU 53 VY handset (same serial protocol as the CU53AN). Logic board
L8M (Z80 84C00 at 4.032 MHz, PIO, SIO, 82C54, ADC0809, DAC0832, FX409/419
FFSK modem, NMC9817 2 KB EEPROM, 2 x HM6264 RAM), synthesizer S8M
(MC145156, 40/41 prescaler, R = 1024), 45 MHz first IF. Service manual:
`reference/huolto-ohjeet/RB58VY_Huolto-ohje.ocr.txt` (chapter 11 = L8M,
chapter 17 = CU 53 VY). The hardware differences from P8x are tabulated
in `emu/notes/r58.md` "L8M".

## Firmware material

| What | Where | State |
|---|---|---|
| Original Nokia firmware, EPROM0 | `reference/oh5nxo/mods/R58vy/rom.0` + OH5NXO's labelled `rom.0.asm` | **incomplete**: EPROM1 (0x8000..0xBFFF) was not dumped; 5 of the 16 scheduler tasks (table at 0x7B00) start there. Runs its EEPROM default copy, then crashes into the missing EPROM |
| OH5NXO R58bis (C) for L8M | `reference/oh5nxo/mods/R58bis/R58/L8M.bin`, source in the same directory (`-DL8M`) | runs in the emulator; 6 m defaults; config and 40 memories in the EEPROM; FFSK via the FX419 on SIO A (sync mode) |
| OH5NXO asm R58 v4.0 L8M port (2000-12) | `reference/oh5nxo/mods/R58/r58.asm.pre4.0`, `r58.asm.vy.rx.sorta.better`, `r58l8m40b.inf` | alpha: RX and TX worked, S8M synth, NV lost when the supply is cut, no FSK. Dropped again in 3G..3Z, which our firmware descends from |

## Our firmware on L8M (done 2026-10-08)

`r58.s` with `-DL8M` (the C modules get `-DL8M` too). Ports that do not
exist on L8M (FX429, CSMEM, the RFC DAC, 8254 counter 2 as CTCSS) are left
undefined there, so every use has an L8M case. What changed:

| Area | L8M |
|---|---|
| I/O map | PIO 00, SIO 10, 8254 20, DAC 30 (TPC only), ADC 40 (L8M order; `ad_bytes` realigned), "OUT 0" latch 50 = OUT1 = OUT2, audio latch 60 = OUT0, watchdog 70 |
| 0x50 latch | the O1_/O2_ bits redefined to its layout; `out2_bank` holds the radio side (TXOFF, TPS, /STE, SRE) so every handset write carries it; `l8m_radio` / `L8M_RADIO()` change those bits |
| Synth | S8M (`s8m_load`): MC145156 frames SW1 SW2, N (10), A (7); N = div / 40, A = div mod 40; divisors always in 12.5 kHz (`channel_step_parms`): 12.5 and 25 kHz steps only; RX loads on an SRE pulse, TX on /STE falling (low = TX VCO on, `halt_txsynth` raises it); no control register, no deviation switching |
| Timers | `TMR_LPF` counter 1, `TMR_MT` (tones) counter 2, counter 0 = SIO B clock (26: 155 kHz, MBUS 9692 bd) |
| Hook | SIO A DCD, put into `pioa_data` bit 1 by `systick` (P8x semantics) |
| PIO B | `piob_out` shadow (S/L, EEA10, EXAL, SMEM always 1); GPIO2's b bit has no pin |
| Banks | `set_bank`: PB4 (S/L): bank 1 = EPROM1 upper half (image 0xC000), bank 2 = lower half (image 0x8000); no bank 0 multiboard |
| SAnE | always the 6 m defaults (S8B: 45 MHz IF) |
| CPU | no P8E detection: `cpu_is_P8E` = 0 (4.032 MHz, no waits) |

**NV: RAM plus the essentials in the EEPROM** (user's choice 2026-10-08;
`r58.s` "L8M EEPROM"). The NV block stays in RAM (Vm-powered: kept while
switched off, lost on a supply cut). EEPROM layout (2 KB): header
`R58` + layout 1 (written last), state block (`nvstart..ram_magic`,
30 B), VIP list + RFC table (130 B), setup block (902 B), the first 81
memories.
- `ee_sync` (mainloop): compares 16 bytes per call, writes at most one,
  then leaves the EEPROM 2-3 ticks for its write cycle; setup, VIP/RFC,
  memories and the header. A full pass takes ~1.3 s.
- `ee_flush` (`powerdown_now`, so also after the switch-off NMI and SAnE):
  every region including the state block, polling each write until two
  reads agree (`ee_settle`, at most ~15 ms each). Only when `ram_magic` is
  valid.
- `ee_boot` (`load_nvdata`): `ram_magic` != 0x5A58 means the RAM lost its
  supply; then every region comes back from the EEPROM if its header is
  there. A fresh EEPROM leaves the RAM alone (SAnE as before).
- While the EEPROM is in (SMEM low) there is no RAM: interrupts are off
  and SP is in the ROM window; `v_nmi` sets SMEM high first.
- Wear: the state block (frequency, volume, scanning) is written only at
  power-down. Memories past 81 live in RAM only.

Not on L8M (first cut):
- **FFSK** (FX429 code: packets, remote config, MPRS): the FX419 is a
  bit-sync modem on SIO A; `send_packet_buffer` sends nothing, nothing is
  received. Needs SIO sync/hunt in the firmware and the emulator.
- **GPS on SIO A** (the modem's channel); SIO B could take NMEA.
- **CTCSS** encoder and decoder, **DTMF decoder** (no multiboard), the FX465
  and external serial strobes, RFC tuning (no RFC DAC).
- **CU58AF** untested on L8M (the emulator's L8M card drives a CU53 only).
- PA1 (TX VCO buffer enable / lock) is left an input; OH5NXO drove it high
  in RX. Check on a real radio.

Open for a real radio: the latch bit polarities of /SRE and TPS, the PA1
handling, the EEPROM write time (`ee_settle` gives up after ~15 ms), the
MBUS clock.
