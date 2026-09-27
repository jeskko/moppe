# Mobira R58 / RD58 firmware workbench

Tools for developing the community ham firmware (OH5NXO et al., v3_Z "ALs",
24.09.2018) for the Mobira/Nokia R58 series (RB58 6 m, RC58 2 m, RD58 70 cm)
without burning an EPROM for every change.

## Status (2026-09-28)

| Area | State |
|---|---|
| Toolchain | Original `as80` assembler ported to 64-bit; the ALs and ALr sources rebuild **byte-identical** to the released binaries (`make -C firmware verify`). |
| Emulator | Boots the real firmware on emulated **P8E** (8.064 MHz Z80, 1 wait/M1) and **P8N** (4.032 MHz) cards with a **CU53AN** or **CU58AF** handset. Z80 core passes zexdoc and zexall. |
| Tests | 29 scenario tests: first-time setup (SAnE), frequency entry, memories, stepping, duplex, TX keying and TX limits, setup menu, squelch, NV persistence, DTMF and **AX.25 APRS decoded from the emulated tone pin**, GPS NMEA into APRS, FFSK/MPRS packet CRC. The DTMF/APRS tests fail if the CPU timing model is wrong. |
| C in firmware | Proof of concept: `make C=1` builds the firmware with the squelch and packet-CRC routines in C (SDCC). All tests pass and the ROM gets 48 bytes smaller. |
| Rewrite evaluation | [notes/rewrite-evaluation.md](notes/rewrite-evaluation.md): a full rewrite does not fit today's 32 KB ROM layout (both cards have banked ROM space that could hold more); an incremental C/asm hybrid works now and is what I recommend. |

Open questions and hardware facts: [notes/hardware.md](notes/hardware.md).
Emulator design, fidelity and limits: [notes/emulator.md](notes/emulator.md).

## Quick start

Needs a C compiler, GNU `cpp`, Python 3 (numpy optional, speeds up audio
decoding). SDCC 4.x only for `make C=1`.

```sh
make -C tools/as80            # assembler
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
r = Radio("firmware/build/r58.bin", "firmware/build/r58.lst", nv=open("my.nv","rb").read())
r.run(2.5)                    # boot
r.type("433500"); r.press("#"); r.run(0.3)
print(r.display(), r.rx_hz())  # ('000012', '    433500') 433500000.0
r.breakpoint("tx_on"); r.ptt(True); print(r.run(1.0), r.symbolize(r.cpu()["pc"]))
```

## Layout

| Path | What |
|---|---|
| `firmware/r58.asm` | Working copy of the firmware source (from `reference/r58.asm.als`) |
| `firmware/c/` | C modules for `make C=1` |
| `tools/as80/` | The assembler (patched, see [notes/toolchain.md](notes/toolchain.md)) |
| `tools/sdcc2as80.py` | SDCC output → as80 dialect converter |
| `emu/` | Emulator in C: `z80.c` core, `pio/sio/pit/daisy.c` Zilog/Intel chips, `cu53an.c`, `cu58af.c` handsets, `r58.c` board, `api.c` flat API |
| `emu/python/` | `r58emu.py` harness, `r58tui.py` terminal UI, `afsk.py` AX.25 decoder |
| `emu/tests/` | Scenario tests; `zex/` Z80 exerciser harness |
| `experiments/c-density/` | C vs assembler code size measurement |
| `notes/` | Findings; `notes/reference/` has the detailed interface specs |
| `reference/` | Source material (not in git): manuals, original sources and binaries |
