# Mobira R58 / RD58 firmware workbench

Tools for developing the community ham firmware (OH5NXO et al., v3_Z "ALs",
24.09.2018) for the Mobira/Nokia R58 series (RB58 6 m, RC58 2 m, RD58 70 cm)
without burning an EPROM for every change.

## Status (2026-09-28)

| Area | State |
|---|---|
| Toolchain | SDCC's **sdasz80 + sdldz80** (with cpp and a small preprocessor). The source was converted from the original as80 dialect and rebuilds **byte-identical** to the released ALs binary (`make -C firmware verify`, which also checks the as80 build of the old source). |
| Emulator | Boots the real firmware on emulated **P8E** (8.064 MHz Z80, 1 wait/M1) and **P8N** (4.032 MHz) cards with a **CU53AN** or **CU58AF** handset. Z80 core passes zexdoc and zexall. |
| Tests | 141 tests. Firmware scenarios: first-time setup (SAnE), frequency entry, memories, stepping, duplex, TX keying and TX limits, setup menu, squelch, NV persistence, DTMF and **AX.25 APRS decoded from the emulated tone pin**, GPS NMEA into APRS, FFSK packets sent and received (call, remote display/config, relay, MPRS), remote configuration between two emulated radios over a simulated RF link, MBUS config dump/load (CFGSnd/CFGGEt); scanner, repeater access and CW ID, every menu record type, low battery, TOT, typematic; ROM-window decode and code running from bank 1. **Differential tests** (`emu/tests/test_diff.py`) run the released firmware and a candidate build side by side and compare display, synth, latches, events and NV. The DTMF/APRS tests fail if the CPU timing model is wrong. |
| C in firmware | `make C=1` links C modules (squelch, packet CRCs, systick timers, battery check) as normal SDCC objects. All tests pass; the differential tests show no behaviour difference to the stock build. |
| Rewrite evaluation | [notes/rewrite-evaluation.md](notes/rewrite-evaluation.md): a full rewrite does not fit today's 32 KB ROM layout (both cards have banked ROM space that could hold more); an incremental C/asm hybrid works now and is what I recommend. |

| **Next** | Hybrid firmware (C except timing-critical parts) with banked EPROM0: [notes/hybrid-plan.md](notes/hybrid-plan.md). Phases 1 (toolchain) and 2 (bank switching) done; Phase 3: the setup menu, APRS/MPRS/GPS, the FSK packet layer and the repeater/CW code run from bank 1 (64 KB image; ~15 KB free in fixed ROM, bank 1 nearly full). Phase 4 (C port) started: timers and battery check in C. Pending: the ROM window bench test on a real board (`make -C firmware banktest`). |

Open questions and hardware facts: [notes/hardware.md](notes/hardware.md).
Emulator design, fidelity and limits: [notes/emulator.md](notes/emulator.md).

## Quick start

Needs a C compiler, GNU `cpp`, Python 3 (numpy optional, speeds up audio
decoding), SDCC 4.x (sdasz80, sdldz80; tested with 4.6.0).

```sh
make -C firmware verify       # build firmware/build/r58.bin, check vs release
make -C emu                   # emulator (r58emu, libr58.so)

python3 -m unittest discover -s emu/tests      # test suite, ~15 s

python3 emu/python/r58tui.py --nv my.nv        # interactive radio in the terminal
python3 emu/python/r58tui.py --script '433500#. '   # headless: keys, then screen
```

In the TUI: digits `* #`, `c`=CL `s`=STO `r`=RCL `e`=ENT `b`=SHIFT `+ -`;
Space toggles PTT, `g` a received signal, `p` the power switch, Tab lengthens
the next key press (long presses reach store/step/squelch functions),
`q` quits and saves the NV (battery RAM) image. A missing NV file is
initialised with the firmware's own SAnE defaults.

Scripting from Python:

```python
import sys; sys.path.insert(0, "emu/python")
from r58emu import Radio
r = Radio("firmware/build/r58.bin", "firmware/build/r58.map", nv=open("my.nv","rb").read())
r.run(2.5)                    # boot
r.type("433500"); r.press("#"); r.run(0.3)
print(r.display(), r.rx_hz())  # ('000012', '    433500') 433500000.0
r.breakpoint("tx_on"); r.ptt(True); print(r.run(1.0), r.symbolize(r.cpu()["pc"]))
```

## Layout

| Path | What |
|---|---|
| `firmware/r58.s` | Firmware source (sdasz80 syntax, see [notes/toolchain.md](notes/toolchain.md)); `asm.h` helper macros |
| `firmware/r58.asm` | The original as80 source (from `reference/r58.asm.als`), reference only |
| `firmware/c/` | C modules for `make C=1` |
| `tools/asmpp.py`, `link.py`, `cglue.py`, `ihx2bin.py` | Build steps around sdasz80/sdldz80 |
| `tools/jp2jr.py` | Size optimiser: `jp` → `jr` outside timing-critical code |
| `tools/bankxref.py` | Cross-references of a source block, before moving it to bank 1 |
| `tools/as80tosdas.py` | One-shot as80 → sdasz80 source converter |
| `tools/as80/` | The original assembler (patched), for reference builds |
| `emu/` | Emulator in C: `z80.c` core, `pio/sio/pit/daisy.c` Zilog/Intel chips, `cu53an.c`, `cu58af.c` handsets, `r58.c` board, `api.c` flat API |
| `emu/python/` | `r58emu.py` harness, `r58tui.py` terminal UI, `afsk.py` AX.25 decoder |
| `emu/tests/` | Scenario tests; `zex/` Z80 exerciser harness |
| `experiments/c-density/` | C vs assembler code size measurement |
| `notes/` | Findings; `notes/reference/` has the detailed interface specs |
| `reference/` | Source material (not in git): manuals, original sources and binaries |
