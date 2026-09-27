# Emulator

## Architecture

| Layer | Files | Notes |
|---|---|---|
| Z80 core | `emu/z80.c` | Instruction-stepped, exact T-states, all undocumented opcodes and flags (MEMPTR, SCF/CCF Q). Counts M1 cycles per step. **Passes zexdoc and zexall** (`make -C emu zex`, ~75 s). About 600 M T-states/s bare. |
| Chips | `pio.c`, `sio.c`, `pit.c`, `daisy.c` | Z80 PIO (mode 3 bit-control interrupts, runtime direction changes), Z80 SIO (async; RR0 status latching and ext/status interrupts, status-affects-vector, TX/RX timing at the programmed baud), Intel 8254 (modes 0, 2, 3, 4; gates tied high), IM2 daisy chain with RETI. |
| Handsets | `cu53an.c`, `cu58af.c` | CU53AN: HEF4555 chip-select decode, two PCF2111 (34-bit frames, latched on deselect), 8-bit HEF4035 shift chain, HEF40373 LED latch, MM74C923 keypad (DA line). CU58AF: bit-level I²C slave engine with PCF8574 ports (keypad matrix, /INT), PCF8576 LCD RAM, PCD3312 DTMF, LED and audio-control ports. |
| Board | `r58.c` | Memory map (incl. P8N SMEM NV plane and the P8E banked 0x8000 window), I/O decode, 1968.75 Hz PA0/CLK2 timebase, CLK0/1 = 4.032 MHz, ADC (last-conversion semantics), DACs, latches, watchdog, power switch → NMI, PB7 relay, FX429 (byte level), synthesizer and external serial frame capture, PC trace ring, breakpoints and watchpoints, audio edge capture of the 8254 tone pin. |
| API | `api.c`, `emu/python/r58emu.py` | Flat C API; Python `Radio` class with symbol lookup from the as80 listing. |
| Front ends | `main.c` (`r58emu`), `r58tui.py` | CLI smoke run; curses TUI with a headless `--script` mode. |

Time is counted in 8.064 MHz crystal periods ("xt"). P8E: 1 T = 1 xt plus one wait state per M1, prefix bytes included. P8N: 1 T = 2 xt, no waits. Peripherals advance after each instruction; I/O happens at instruction granularity.

## Fidelity evidence

- The firmware's own P8E/P8N detection (it times NOPs against the 8254) picks the right card.
- DTMF tone pairs and a complete AX.25 frame with a valid FCS decode from the emulated PWM tone pin on both cards. With the wrong wait-state model (0 or 2 waits on P8E, 1 on P8N) no valid frame decodes, so the timing check is real (`test_wrong_wait_model_breaks_aprs`).
- The emulated LCD contents equal the firmware's `segments[]` RAM after every frame.
- Synth R/N/A values match values computed independently from the firmware source, for example 433.500 MHz → R=1024, N=325, A=1.
- The firmware's SAnE procedure runs end to end: menu, powers itself down through PB7, re-powers.

## Known limits and assumptions

| Item | Assumption | Source of uncertainty |
|---|---|---|
| Watchdog timeout | 0.52 s (`wd_timeout_s`), from the P8N manual; LOCAL disabling it is not modelled | P8E not documented |
| Hook polarity (PA1) | 1 = on cradle (`hook_offhook_level = 0`) | firmware comments disagree |
| Daisy chain | PIO before SIO | manual + P8E block diagram |
| FX429 IRQ | edge on SIO A DCD per event (shared with hook change, per manual) | 8254 OUT2 on DCDA not modelled |
| FX429 modem | byte level only: TX bytes logged as events, RX packets injected with `modem_rx()` | no bit-level FFSK audio |
| RX audio | not modelled; squelch/RSSI are ADC inputs set by the host | |
| CTCSS DSP decoder input (0x80xx bit 0), FX465, 8254 CLK2 rewire | not modelled | |
| CCIR decoder | nibble on PA7..4 settable (`set_ccir`) | |
| DTMF decoder (multiboard) | byte at 0x80xx settable (`multiboard()`) | |
| 8254 modes 1 and 5, BCD | not implemented (gates tied high on the board) | |
| SIO | async only; no sync/SDLC modes, no parity/framing errors | |
| P8E window at 0x8000 | EPROM0 top 16 KB when OUT2.RS=1, EPROM1 bank when RS=0 (only if an EPROM1 image is loaded; else the multiboard) | read from the P8E schematic, unverified on hardware |
| P8N memory | SMEM NV plane; RS/RA14/RA15 window per manual; PB0 second NV copy not modelled | |
| Output-latch polarities (LEDs, backlight) | 1 = on | |
| CU58AF keypad matrix | follows the firmware's `keytbl_cu58af` | the manual gives no key-to-matrix map |

## Debugging workflow

```python
r = Radio(ROM, LST, nv=nv)
r.breakpoint("tx_on")             # by symbol or address
r.watchpoint("digidx")            # stop on RAM write
r.run(5)                          # -> 'break' / 'watch' / 'time' / 'off'
r.symbolize(r.cpu()["pc"])        # 'tx_on+0'
[r.symbolize(p) for p in r.trace(32)]   # last PCs
r.step(10)                        # single instructions
r.events                          # WDRESET, TX_ON/OFF, SYNTH, MODEM_TX, MBUS_TX, ...
```

Watch out: a zeroed NV image contains zeroed hook "scripts". After the boot-time hook edge the firmware "types" eight `0` keys. Blank `cfg_onhook_script` / `cfg_offhook_script` (0xFF), or run SAnE; the test fixture does both.
